// LMStudioCLI.swift — Wraps the `lms` CLI tool shipped with LM Studio.
// Enable via: LM Studio → Settings → Local Server → Install CLI Tool
//
// Provides: listing loaded models (via HTTP API), load/unload, and
// model download from HuggingFace with real-time progress callbacks.

import Foundation

// MARK: - Data types

struct DownloadProgress: Identifiable {
    let id: String            // catalog entry UUID string
    let modelName: String
    var fraction: Double      // 0.0 – 1.0
    var statusText: String
    var isComplete: Bool
    var error: String?
}

struct ModelCatalogEntry: Identifiable {
    let id: UUID = UUID()
    let name: String
    let shortDesc: String
    let repo: String           // HuggingFace repo  e.g. "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF"
    let file: String           // GGUF filename
    let sizeGB: Double
    let category: Category
    let contextK: Int          // context window in K tokens
    let params: String         // "7B", "32B" etc.

    enum Category: String, CaseIterable {
        case coding     = "Coding"
        case general    = "General"
        case reasoning  = "Reasoning"
        case multimodal = "Multimodal"

        var icon: String {
            switch self {
            case .coding:     return "chevron.left.forwardslash.chevron.right"
            case .general:    return "brain"
            case .reasoning:  return "lightbulb.fill"
            case .multimodal: return "photo.fill"
            }
        }

        var color: String { // name for Color lookup
            switch self {
            case .coding:     return "blue"
            case .general:    return "green"
            case .reasoning:  return "yellow"
            case .multimodal: return "purple"
            }
        }
    }

    /// GB formatted as "4.7 GB" or "19.8 GB"
    var sizeLabel: String { String(format: "%.1f GB", sizeGB) }

    /// Unique HuggingFace path used by `lms get`
    var hfRef: String { "\(repo)/\(file)" }
}

// NOTE: The static ModelCatalogEntry.catalog has been replaced by LMStudioCatalogService,
// which fetches live data from lms search CLI and lmstudio.ai/models.
// ModelCatalogEntry is kept for backward-compat with existing download() calls.

// MARK: - LMStudioCLI actor

actor LMStudioCLI {
    static let shared = LMStudioCLI()
    private init() {}

    private let searchPaths: [String] = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        return [
            "/usr/local/bin/lms",
            "/usr/bin/lms",
            "/opt/homebrew/bin/lms",
            "\(home)/.lmstudio/bin/lms",
            "\(home)/Library/Application Support/LM Studio/lms"
        ]
    }()

    // MARK: - Path detection (nonisolated — no actor state accessed)

    nonisolated var binaryPath: String? {
        searchPaths.first { FileManager.default.fileExists(atPath: $0) }
    }
    nonisolated var isAvailable: Bool { binaryPath != nil }

    // MARK: - List loaded models via HTTP

    func listLoaded(endpoint: String) async -> [String] {
        let base = endpoint.isEmpty ? "http://localhost:1234" : endpoint
        guard let url = URL(string: "\(base)/v1/models") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }

        struct Resp: Codable { struct M: Codable { let id: String }; let data: [M] }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return [] }
        return resp.data.map(\.id)
    }

    // MARK: - Load / Unload via lms CLI

    func load(model: String) async throws {
        guard let bin = binaryPath else { throw CLIError.notInstalled }
        try await run(bin, args: ["load", model])
    }

    func unload(model: String) async throws {
        guard let bin = binaryPath else { throw CLIError.notInstalled }
        try await run(bin, args: ["unload", model])
    }

    // MARK: - Search via lms CLI (delegates to LMStudioCatalogService)

    /// Run `lms search <query>` and return raw text output for parsing
    func searchRaw(query: String) async -> String {
        guard let bin = binaryPath else { return "" }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = query.isEmpty ? ["search", "--limit", "40"] : ["search", query, "--limit", "30"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - Delete model from disk

    func deleteModel(id: String) async throws {
        guard let bin = binaryPath else { throw CLIError.notInstalled }
        // lms rm accepts either the full model id or just the filename stem
        let modelName = id.components(separatedBy: "/").last?
            .replacingOccurrences(of: ".gguf", with: "") ?? id
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["rm", modelName]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw CLIError.commandFailed("rm \(modelName)", proc.terminationStatus)
        }
    }


    /// Download model from HuggingFace via `lms get`.
    /// `onProgress` is called on an arbitrary thread — wrap in MainActor.run.
    func download(entry: ModelCatalogEntry,
                  onProgress: @escaping (DownloadProgress) -> Void) async throws {
        guard let bin = binaryPath else { throw CLIError.notInstalled }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["get", entry.hfRef]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        var buffer = ""
        let key = entry.id.uuidString

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard !chunk.isEmpty else { return }
            buffer += chunk

            // LM Studio CLI outputs lines like:
            //   "Downloading Qwen2.5-Coder-7B... 23.4%"
            //   "[=======>   ] 45%  12.3 MB/s"
            let lines = buffer.components(separatedBy: "\n")
            for line in lines {
                // Match percent: 0–100, optional decimal
                let pctPattern = #"(\d{1,3}(?:\.\d+)?)\s*%"#
                if let range = line.range(of: pctPattern, options: .regularExpression) {
                    let raw = line[range].replacingOccurrences(of: "%", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    let fraction = min((Double(raw) ?? 0.0) / 100.0, 1.0)

                    var speed = ""
                    if line.contains("MB/s") || line.contains("KB/s") {
                        if let r = line.range(of: #"\d+\.?\d*\s*[MK]B/s"#,
                                              options: .regularExpression) {
                            speed = String(line[r])
                        }
                    }

                    let prog = DownloadProgress(
                        id: key, modelName: entry.name,
                        fraction: fraction,
                        statusText: "Downloading… \(speed)",
                        isComplete: false, error: nil)
                    onProgress(prog)
                }
            }
            // Keep last incomplete line in buffer
            buffer = lines.last ?? ""
        }

        try proc.run()
        // waitUntilExit is blocking — fine on actor background thread
        proc.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        if proc.terminationStatus != 0 {
            let prog = DownloadProgress(id: key, modelName: entry.name, fraction: 0,
                                        statusText: "Failed", isComplete: false,
                                        error: "Exit code \(proc.terminationStatus)")
            onProgress(prog)
            throw CLIError.downloadFailed(proc.terminationStatus)
        }

        let done = DownloadProgress(id: key, modelName: entry.name, fraction: 1.0,
                                    statusText: "Complete ✓", isComplete: true, error: nil)
        onProgress(done)
    }

    // MARK: - Helpers

    private func run(_ bin: String, args: [String]) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        proc.standardOutput = Pipe() // suppress output
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw CLIError.commandFailed(args.joined(separator: " "), proc.terminationStatus)
        }
    }

    // MARK: - Errors

    enum CLIError: LocalizedError {
        case notInstalled
        case commandFailed(String, Int32)
        case downloadFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "lms CLI not found.\nEnable it in: LM Studio → Settings → Local Server → Install CLI Tool"
            case .commandFailed(let cmd, let code):
                return "lms \(cmd) failed (exit \(code))"
            case .downloadFailed(let code):
                return "Download failed (exit \(code))"
            }
        }
    }
}

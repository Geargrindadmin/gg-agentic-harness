// LMStudioCLI.swift — Wraps the `lms` CLI tool shipped with LM Studio.
// Enable via: LM Studio → Settings → Local Server → Install CLI Tool
//
// Provides: listing loaded models (via HTTP API), load/unload, and
// model download from HuggingFace with real-time progress callbacks.

import Foundation

private final class LMStudioDownloadLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ chunk: String) -> [String] {
        lock.lock()
        buffer += chunk
        let lines = buffer.components(separatedBy: "\n")
        buffer = lines.last ?? ""
        lock.unlock()
        return Array(lines.dropLast())
    }
}

// MARK: - Data types

struct DownloadProgress: Identifiable {
    let id: String            // catalog entry UUID string
    let modelName: String
    var fraction: Double      // 0.0 – 1.0
    var statusText: String
    var isComplete: Bool
    var error: String?
    var canCancel: Bool = false
    var isCancelled: Bool = false
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

    struct ListedModel: Decodable {
        struct Quantization: Decodable {
            let name: String?
            let bits: Int?
        }

        let type: String?
        let modelKey: String?
        let displayName: String?
        let publisher: String?
        let path: String?
        let sizeBytes: Int?
        let indexedModelIdentifier: String?
        let paramsString: String?
        let architecture: String?
        let quantization: Quantization?
        let variants: [String]?
        let selectedVariant: String?
        let vision: Bool?
        let trainedForToolUse: Bool?
        let maxContextLength: Int?
    }

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
        try await run(bin, args: ["load", normalizedModelKey(model), "--yes"])
    }

    func unload(model: String) async throws {
        guard let bin = binaryPath else { throw CLIError.notInstalled }
        try await run(bin, args: ["unload", normalizedUnloadIdentifier(model)])
    }

    func listLibraryModels() async -> [LMStudioModel] {
        guard let bin = binaryPath else { return [] }
        let output = await runCommand(bin, args: ["ls", "--json"])
        guard output.exitCode == 0 else { return [] }
        return Self.parseLibraryModelsJSON(output.data)
    }

    func listLoadedModelIds() async -> Set<String> {
        guard let bin = binaryPath else { return [] }
        let output = await runCommand(bin, args: ["ps", "--json"])
        guard output.exitCode == 0 else { return [] }
        return Self.parseLoadedModelIdentifiersJSON(output.data)
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
        throw CLIError.deleteNotSupported
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

        let lineBuffer = LMStudioDownloadLineBuffer()
        let key = entry.id.uuidString

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard !chunk.isEmpty else { return }

            // LM Studio CLI outputs lines like:
            //   "Downloading Qwen2.5-Coder-7B... 23.4%"
            //   "[=======>   ] 45%  12.3 MB/s"
            let lines = lineBuffer.append(chunk)
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
        let result = await runCommand(bin, args: args)
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed(args.joined(separator: " "), result.exitCode, result.output)
        }
    }

    private func runCommand(_ bin: String, args: [String]) async -> (exitCode: Int32, output: String, data: Data) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (proc.terminationStatus, output, data)
    }

    nonisolated static func parseLibraryModelsJSON(_ data: Data) -> [LMStudioModel] {
        guard let decoded = try? JSONDecoder().decode([ListedModel].self, from: data) else { return [] }
        return decoded.map { model in
            let resolvedId = model.selectedVariant
                ?? model.indexedModelIdentifier
                ?? model.path
                ?? model.modelKey
                ?? model.displayName
                ?? UUID().uuidString
            let type = normalizeModelType(model.type, vision: model.vision, toolUse: model.trainedForToolUse)
            return LMStudioModel(
                id: resolvedId,
                type: type,
                publisher: model.publisher,
                contextLength: model.maxContextLength,
                state: "not-loaded"
            )
        }
    }

    nonisolated static func parseLoadedModelIdentifiersJSON(_ data: Data) -> Set<String> {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let array = raw as? [[String: Any]] {
            let ids = array.compactMap { row -> String? in
                row["identifier"] as? String
                ?? row["id"] as? String
                ?? row["modelKey"] as? String
                ?? row["path"] as? String
            }
            return Set(ids)
        }
        return []
    }

    private func normalizedModelKey(_ model: String) -> String {
        if let atIndex = model.firstIndex(of: "@") {
            return String(model[..<atIndex])
        }
        if model.localizedCaseInsensitiveContains(".gguf") {
            let trimmed = model.components(separatedBy: "/").dropLast().joined(separator: "/")
            if !trimmed.isEmpty { return trimmed }
        }
        return model
    }

    private func normalizedUnloadIdentifier(_ model: String) -> String {
        if let selected = model.split(separator: "/").last, selected.localizedCaseInsensitiveContains(".gguf") {
            return model.replacingOccurrences(of: ".gguf", with: "")
        }
        return model
    }

    nonisolated private static func normalizeModelType(_ type: String?, vision: Bool?, toolUse: Bool?) -> String {
        if let type, !type.isEmpty { return type }
        if vision == true { return "vlm" }
        if toolUse == true { return "tools" }
        return "llm"
    }

    // MARK: - Errors

    enum CLIError: LocalizedError {
        case notInstalled
        case commandFailed(String, Int32, String)
        case downloadFailed(Int32)
        case deleteNotSupported

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "lms CLI not found.\nEnable it in: LLM Studio → Settings → Local Server → Install CLI Tool"
            case .commandFailed(let cmd, let code, let output):
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty
                    ? "lms \(cmd) failed (exit \(code))"
                    : "lms \(cmd) failed (exit \(code)): \(trimmed)"
            case .downloadFailed(let code):
                return "Download failed (exit \(code))"
            case .deleteNotSupported:
                return "Delete from disk requires the LLM Studio local server API. The installed lms CLI does not support model deletion."
            }
        }
    }
}

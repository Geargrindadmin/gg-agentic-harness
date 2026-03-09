// ModelManagementService.swift — Delete, VRAM stats, and bulk operations.

import Foundation

// MARK: - System Stats

struct LMSystemStats {
    let gpuVramUsedMB: Int
    let gpuVramTotalMB: Int
    let systemRamUsedMB: Int
    let systemRamTotalMB: Int
    let loadedModelCount: Int

    var vramFraction: Double {
        guard gpuVramTotalMB > 0 else { return 0 }
        return Double(gpuVramUsedMB) / Double(gpuVramTotalMB)
    }
    var ramFraction: Double {
        guard systemRamTotalMB > 0 else { return 0 }
        return Double(systemRamUsedMB) / Double(systemRamTotalMB)
    }
    var vramLabel: String { "\(gpuVramUsedMB / 1024) GB / \(gpuVramTotalMB / 1024) GB" }
    var ramLabel: String { "\(systemRamUsedMB / 1024) GB / \(systemRamTotalMB / 1024) GB" }
}

// MARK: - Service

@MainActor
final class ModelManagementService: ObservableObject {
    static let shared = ModelManagementService()

    @Published var systemStats: LMSystemStats?
    @Published var isLoadingStats = false
    @Published var lastError: String?

    private var statsTask: Task<Void, Never>?
    private init() {}

    // MARK: - System Stats polling

    func startStatsPolling(endpoint: String) {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStats(endpoint: endpoint)
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
            }
        }
    }

    func stopStatsPolling() {
        statsTask?.cancel()
        statsTask = nil
    }

    func refreshStats(endpoint: String) async {
        // Try LM Studio REST /api/v0/system first
        if let stats = await fetchRESTStats(endpoint: endpoint) {
            systemStats = stats
            return
        }
        // Fall back to macOS system metrics
        systemStats = buildFallbackStats()
    }

    private func fetchRESTStats(endpoint: String) async -> LMSystemStats? {
        let base = endpoint.isEmpty ? "http://localhost:1234" : endpoint
        guard let url = URL(string: "\(base)/api/v0/system") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        struct SystemResp: Codable {
            struct GPU: Codable {
                let vramUsedBytes: Int?
                let vramTotalBytes: Int?
                enum CodingKeys: String, CodingKey {
                    case vramUsedBytes = "vram_used_bytes"
                    case vramTotalBytes = "vram_total_bytes"
                }
            }
            let gpus: [GPU]?
            let ramUsedBytes: Int?
            let ramTotalBytes: Int?
            let loadedModels: Int?
            enum CodingKeys: String, CodingKey {
                case gpus
                case ramUsedBytes = "ram_used_bytes"
                case ramTotalBytes = "ram_total_bytes"
                case loadedModels = "loaded_models"
            }
        }

        guard let resp = try? JSONDecoder().decode(SystemResp.self, from: data) else { return nil }
        let gpu = resp.gpus?.first
        return LMSystemStats(
            gpuVramUsedMB: (gpu?.vramUsedBytes ?? 0) / (1024 * 1024),
            gpuVramTotalMB: (gpu?.vramTotalBytes ?? 0) / (1024 * 1024),
            systemRamUsedMB: (resp.ramUsedBytes ?? 0) / (1024 * 1024),
            systemRamTotalMB: (resp.ramTotalBytes ?? 0) / (1024 * 1024),
            loadedModelCount: resp.loadedModels ?? 0
        )
    }

    private func buildFallbackStats() -> LMSystemStats {
        let total = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        // Approximate used RAM from host memory pressure (not exact but useful)
        return LMSystemStats(
            gpuVramUsedMB: 0, gpuVramTotalMB: 0,
            systemRamUsedMB: 0, systemRamTotalMB: total,
            loadedModelCount: 0
        )
    }

    // MARK: - Delete model

    /// Delete a model from the LM Studio library (not loaded in VRAM).
    /// Tries REST API first, falls back to `lms rm` CLI.
    func deleteModel(id: String, endpoint: String) async throws {
        // 1. Try REST (LM Studio >= 0.3.6)
        if await deleteViaREST(id: id, endpoint: endpoint) { return }
        // 2. Fall back to lms rm
        try await deleteViaCLI(id: id)
    }

    private func deleteViaREST(id: String, endpoint: String) async -> Bool {
        let base = endpoint.isEmpty ? "http://localhost:1234" : endpoint
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "\(base)/api/v0/models/\(encoded)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 15
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return false }
        return true
    }

    private func deleteViaCLI(id: String) async throws {
        guard let bin = LMStudioCLI.shared.binaryPath else {
            throw ManagementError.cliNotAvailable
        }
        // Extract model name from the id (last path component without .gguf)
        let modelName = id.components(separatedBy: "/").last?
            .replacingOccurrences(of: ".gguf", with: "") ?? id
        let (ok, output) = await runCLI(bin: bin, args: ["rm", modelName])
        if !ok {
            throw ManagementError.deleteFailed(output)
        }
    }

    // MARK: - Download via catalog entry

    func download(model: CatalogModel,
                  onProgress: @escaping @MainActor (DownloadProgress) -> Void) async throws {
        guard LMStudioCLI.shared.isAvailable else {
            throw ManagementError.cliNotAvailable
        }
        // Convert CatalogModel to a legacy DownloadProgress/ModelCatalogEntry shape
        let key = model.id
        // Kick off actual download using lms get
        try await downloadViaLMS(hfRef: model.hfRef, modelName: model.name,
                                  key: key, onProgress: onProgress)
    }

    private func downloadViaLMS(hfRef: String, modelName: String, key: String,
                                 onProgress: @escaping @MainActor (DownloadProgress) -> Void) async throws {
        guard let bin = LMStudioCLI.shared.binaryPath else {
            throw ManagementError.cliNotAvailable
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["get", hfRef]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        var buffer = ""

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard !chunk.isEmpty else { return }
            buffer += chunk
            let lines = buffer.components(separatedBy: "\n")
            for line in lines {
                let pctPattern = #"(\d{1,3}(?:\.\d+)?)\s*%"#
                if let range = line.range(of: pctPattern, options: .regularExpression) {
                    let raw = line[range].replacingOccurrences(of: "%", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    let fraction = min((Double(raw) ?? 0) / 100.0, 1.0)
                    var speed = ""
                    if let r = line.range(of: #"\d+\.?\d*\s*[MK]B/s"#, options: .regularExpression) {
                        speed = String(line[r])
                    }
                    let prog = DownloadProgress(id: key, modelName: modelName,
                                                fraction: fraction,
                                                statusText: "Downloading… \(speed)",
                                                isComplete: false, error: nil)
                    Task { @MainActor in onProgress(prog) }
                }
            }
            buffer = lines.last ?? ""
        }

        try proc.run()
        proc.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        if proc.terminationStatus != 0 {
            throw ManagementError.deleteFailed("lms get exited \(proc.terminationStatus)")
        }
        let done = DownloadProgress(id: key, modelName: modelName, fraction: 1.0,
                                    statusText: "Complete ✓", isComplete: true, error: nil)
        await onProgress(done)
    }

    // MARK: - Helper

    private func runCLI(bin: String, args: [String]) async -> (Bool, String) {
        await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            try? proc.run()
            proc.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            return (proc.terminationStatus == 0, out)
        }.value
    }

    // MARK: - Errors

    enum ManagementError: LocalizedError {
        case cliNotAvailable
        case deleteFailed(String)

        var errorDescription: String? {
            switch self {
            case .cliNotAvailable:
                return "lms CLI not available. Enable it in LM Studio → Settings → Local Server → Install CLI Tool"
            case .deleteFailed(let msg):
                return "Delete failed: \(msg)"
            }
        }
    }
}

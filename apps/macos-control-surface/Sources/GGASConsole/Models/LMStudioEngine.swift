// LMStudioEngine.swift — OpenAI-compatible client for LM Studio local API.
// LM Studio exposes a fully OpenAI-compatible API at localhost:1234 (configurable).

import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct LMStudioMessage: Codable {
    let role: String
    let content: String
}

struct LMStudioRequest: Codable {
    let model: String
    let messages: [LMStudioMessage]
    let temperature: Double
    let max_tokens: Int
    let stream: Bool
}

struct LMStudioChoice: Codable {
    struct Message: Codable { let content: String }
    let message: Message
}

struct LMStudioResponse: Codable {
    let choices: [LMStudioChoice]
}

struct LMStudioModel: Codable, Identifiable, Hashable {
    let id: String
    // Extended fields returned by LM Studio (optional — absent on some versions)
    let type: String?              // e.g. "llm", "embeddings", "vlm"
    let publisher: String?         // e.g. "lmstudio-community"
    let contextLength: Int?        // max context window
    let state: String?             // "loaded" | "not-loaded" (from /api/v0/models)

    enum CodingKeys: String, CodingKey {
        case id, type, publisher, state
        case contextLength = "context_length"
    }

    /// Short human-readable label: just the last path segment of the id.
    var shortName: String { id.components(separatedBy: "/").last ?? id }

    /// True when the model is actively loaded in VRAM.
    var isLoaded: Bool { state == "loaded" }

    /// Context size string, e.g. "128K" or "8K"
    var contextLabel: String? {
        guard let ctx = contextLength else { return nil }
        return ctx >= 1_024 ? "\(ctx / 1024)K" : "\(ctx)"
    }

    /// Icon name based on model type
    var typeIcon: String {
        switch type {
        case "embeddings": return "waveform"
        case "vlm":        return "photo.fill"
        default:           return "cpu.fill"
        }
    }
}

struct LMStudioModelsResponse: Codable {
    let data: [LMStudioModel]
}

@MainActor
final class LMStudioEngine {
    static let shared = LMStudioEngine()
    private init() {}

    private let defaultEndpoint = "http://localhost:1234"
    private var triedLaunchingApp = false

    private var systemPrompt: String {
        let projectRoot = ProjectSettings.shared.projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedRoot = projectRoot.isEmpty ? "(project root not configured)" : projectRoot
        return """
        You are a senior AI agent coordinator for GG Agentic Harness.
        GG Agentic Harness is a macOS developer control surface that orchestrates multi-model agent workflows.
        Project: \(resolvedRoot)
        When given a task, analyse it, plan an approach, and describe what workers you would spawn.
        Keep responses concise and actionable.
        """
    }

    // MARK: - Query

    func query(task: String, config: CoordinatorConfig,
               settings: LMStudioSettings = LMStudioSettings()) async throws -> String {
        let base = config.endpoint.isEmpty ? defaultEndpoint : config.endpoint
        guard let url = URL(string: "\(base)/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        let sysPrompt = settings.systemPromptOverride.isEmpty
            ? systemPrompt
            : settings.systemPromptOverride

        let body = LMStudioRequest(
            model: config.model,
            messages: [
                LMStudioMessage(role: "system", content: sysPrompt),
                LMStudioMessage(role: "user",   content: task)
            ],
            temperature: settings.temperature,
            max_tokens: settings.maxTokens,
            stream: false
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 120

        let session = URLSession(configuration: .ephemeral)
        let (data, _) = try await session.data(for: req)
        let resp = try JSONDecoder().decode(LMStudioResponse.self, from: data)
        return resp.choices.first?.message.content ?? "(empty response)"
    }

    // MARK: - Health

    func ping(endpoint: String, allowAutoStart: Bool = false) async -> Bool {
        let base = endpoint.isEmpty ? defaultEndpoint : endpoint
        guard let primary = URL(string: "\(base)/v1/models"),
              let fallback = URL(string: "\(base)/api/v0/models") else { return false }

        var req = URLRequest(url: primary)
        req.timeoutInterval = 2
        if (try? await URLSession.shared.data(for: req)) != nil { return true }

        req = URLRequest(url: fallback)
        req.timeoutInterval = 2
        if (try? await URLSession.shared.data(for: req)) != nil { return true }

        // Optional fallback: only auto-start LM Studio when an explicit operator action
        // requests it. Passive health checks must stay side-effect free.
        if allowAutoStart, await ensureServerRunning(base: base) {
            var retry = URLRequest(url: primary); retry.timeoutInterval = 2
            if (try? await URLSession.shared.data(for: retry)) != nil { return true }
            var retryFallback = URLRequest(url: fallback); retryFallback.timeoutInterval = 2
            if (try? await URLSession.shared.data(for: retryFallback)) != nil { return true }
        }
        return false
    }

    func startLocalServer(endpoint: String) async -> Bool {
        let base = endpoint.isEmpty ? defaultEndpoint : endpoint
        return await ensureServerRunning(base: base)
    }

    // MARK: - List models

    /// Returns ALL models downloaded in the LLM Studio library.
    ///
    /// LLM Studio exposes two endpoints:
    /// • `/api/v0/models`  — full library (downloaded, not necessarily loaded). Requires LLM Studio ≥ 0.3.
    /// • `/v1/models`      — only the currently-loaded model(s) in VRAM. OpenAI-compat fallback.
    ///
    /// We try the REST API first, then fall back to the local `lms` CLI.
    func listModels(endpoint: String) async -> [LMStudioModel] {
        let base = endpoint.isEmpty ? "http://localhost:1234" : endpoint

        // 1️⃣  Try the full library endpoint (LLM Studio ≥ 0.3)
        if let libraryModels = await fetchLibraryModels(base: base), !libraryModels.isEmpty {
            let loadedIds = Set((await fetchLoadedModels(base: base)).map(\.id))
            if loadedIds.isEmpty { return libraryModels }
            return libraryModels.map { model in
                if loadedIds.contains(model.id) {
                    return LMStudioModel(
                        id: model.id,
                        type: model.type,
                        publisher: model.publisher,
                        contextLength: model.contextLength,
                        state: "loaded"
                    )
                }
                return model
            }
        }

        // 2️⃣  Fall back to CLI-backed library and loaded-state detection.
        let libraryModels = await LMStudioCLI.shared.listLibraryModels()
        if !libraryModels.isEmpty {
            let loadedIds = await LMStudioCLI.shared.listLoadedModelIds()
            if loadedIds.isEmpty { return libraryModels }
            return libraryModels.map { model in
                if loadedIds.contains(model.id) {
                    return LMStudioModel(
                        id: model.id,
                        type: model.type,
                        publisher: model.publisher,
                        contextLength: model.contextLength,
                        state: "loaded"
                    )
                }
                return model
            }
        }

        // 3️⃣  Final fallback to OpenAI /v1/models (loaded models only).
        return await fetchLoadedModels(base: base)
    }

    /// IDs of models currently loaded in VRAM (active in the OpenAI-compat API).
    func loadedModelIds(endpoint: String) async -> Set<String> {
        let base = endpoint.isEmpty ? "http://localhost:1234" : endpoint
        let models = await fetchLoadedModels(base: base)
        if !models.isEmpty {
            return Set(models.map(\.id))
        }
        return await LMStudioCLI.shared.listLoadedModelIds()
    }

    // MARK: - Private fetch helpers

    private func fetchLibraryModels(base: String) async -> [LMStudioModel]? {
        // /api/v0/models returns { data: [ { id, type, publisher, state, ... } ] }
        guard let url = URL(string: "\(base)/api/v0/models") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(LMStudioModelsResponse.self, from: data)
        else { return nil }
        return result.data
    }

    private func fetchLoadedModels(base: String) async -> [LMStudioModel] {
        guard let url = URL(string: "\(base)/v1/models") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let resp = try? JSONDecoder().decode(LMStudioModelsResponse.self, from: data)
        else { return [] }
        return resp.data
    }

    // MARK: - Load / Unload via REST (no CLI required)

    /// Load a model into VRAM via the LM Studio REST API.
    /// Uses `POST /api/v0/models/{encoded-id}/load`
    func loadModel(id: String, endpoint: String) async throws {
        let base = endpoint.isEmpty ? "http://localhost:1234" : endpoint
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "\(base)/api/v0/models/\(encoded)/load") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{}".data(using: .utf8)
        req.timeoutInterval = 60   // loading can take time

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw LMAPIError.httpError(status, "load \(id)")
            }
            return
        } catch {
            // Older LM Studio builds can require CLI load semantics.
            try await LMStudioCLI.shared.load(model: id)
        }
    }

    /// Unload a model from VRAM via the LM Studio REST API.
    /// Uses `POST /api/v0/models/{encoded-id}/unload`
    func unloadModel(id: String, endpoint: String) async throws {
        let base = endpoint.isEmpty ? "http://localhost:1234" : endpoint
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "\(base)/api/v0/models/\(encoded)/unload") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{}".data(using: .utf8)
        req.timeoutInterval = 15

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw LMAPIError.httpError(status, "unload \(id)")
            }
            return
        } catch {
            // Older LM Studio builds can require CLI unload semantics.
            try await LMStudioCLI.shared.unload(model: id)
        }
    }

    /// Returns the IDs of models currently loaded in VRAM.
    func listLoadedIds(endpoint: String) async -> [String] {
        await fetchLoadedModels(base:
            endpoint.isEmpty ? "http://localhost:1234" : endpoint
        ).map(\.id)
    }

    // MARK: - Auto-start support

    /// Attempts to launch LLM Studio app or daemon if the API is offline.
    /// Returns true if a start attempt was made (so callers can retry).
    private func ensureServerRunning(base: String) async -> Bool {
        #if os(macOS)
        if triedLaunchingApp { return false }
        triedLaunchingApp = true

        // 1) Try the LLM Studio app bundle
        let appPaths = [
            "/Applications/LM Studio.app",
            NSHomeDirectory() + "/Applications/LM Studio.app"
        ]
        if let appPath = appPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            let appURL = URL(fileURLWithPath: appPath)
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            // brief delay to allow the daemon to boot
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            return true
        }

        // 2) Fall back to `lms server start` if available
        if let lms = LMStudioCLI.shared.binaryPath {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: lms)
            task.arguments = ["server", "start", "--port", URL(string: base)?.port.map(String.init) ?? "1234"]
            try? task.run()
            try? await Task.sleep(nanoseconds: 500_000_000)
            return true
        }
        #endif
        return false
    }

    // MARK: - Delete model from library

    /// Delete a downloaded model from the LLM Studio library via REST.
    /// Requires LLM Studio >= 0.3.6.
    func deleteModel(id: String, endpoint: String) async throws {
        let base = endpoint.isEmpty ? "http://localhost:1234" : endpoint
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "\(base)/api/v0/models/\(encoded)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 30

        let (_, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // 404 means already gone — treat as success
        guard (200..<300).contains(status) || status == 404 else {
            throw LMAPIError.httpError(status, "delete \(id)")
        }
    }

    // MARK: - System resource stats

    /// Fetch GPU VRAM and system RAM usage from LM Studio's /api/v0/system endpoint.
    func systemStats(endpoint: String) async -> LMSystemStats? {
        await ModelManagementService.shared.refreshStats(endpoint: endpoint)
        return await MainActor.run { ModelManagementService.shared.systemStats }
    }

    // MARK: - API errors


    enum LMAPIError: LocalizedError {
        case httpError(Int, String)
        var errorDescription: String? {
            if case .httpError(let code, let op) = self {
                return "LLM Studio API error \(code) during '\(op)'. Is LLM Studio running with local server enabled?"
            }
            return nil
        }
    }
}

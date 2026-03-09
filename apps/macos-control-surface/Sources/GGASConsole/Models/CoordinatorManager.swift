// CoordinatorManager.swift — Singleton managing all coordinator agent configurations.
// Routes dispatch calls to the active coordinator backend.

import SwiftUI
import Foundation

// MARK: - Coordinator Types

enum CoordinatorType: String, CaseIterable, Identifiable, Codable {
    case claude   = "Claude API"
    case kimi     = "Kimi CLI"
    case lmStudio = "LM Studio"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .claude:   return "c.circle.fill"
        case .kimi:     return "k.circle.fill"
        case .lmStudio: return "cpu.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .claude:   return Color(red: 0.73, green: 0.53, blue: 1.00)   // purple
        case .kimi:     return Color(red: 0.20, green: 0.75, blue: 1.00)   // blue
        case .lmStudio: return Color(red: 0.94, green: 0.72, blue: 0.18)   // amber
        }
    }
}

// MARK: - Coordinator Config

struct CoordinatorConfig: Identifiable, Codable {
    var id: UUID = UUID()
    var type: CoordinatorType
    var label: String
    var endpoint: String     // LM Studio: "http://localhost:1234"  |  others: ignored
    var model: String        // LM Studio model name | Kimi: binary path | Claude: model id
    var isOnline: Bool = false
    var isBuiltIn: Bool = false  // built-ins can't be deleted

    static func claudeDefault() -> CoordinatorConfig {
        CoordinatorConfig(type: .claude, label: "claude-opus-4",
                          endpoint: "", model: "claude-opus-4-5", isBuiltIn: true)
    }
    static func kimiDefault() -> CoordinatorConfig {
        let bin = ProcessInfo.processInfo.environment["KIMI_BINARY"] ?? "kimi"
        return CoordinatorConfig(type: .kimi, label: "Kimi Code",
                                 endpoint: "", model: bin, isBuiltIn: true)
    }
    static func lmStudioDefault() -> CoordinatorConfig {
        CoordinatorConfig(type: .lmStudio, label: "Qwen2.5-Coder-7B",
                          endpoint: "http://localhost:1234",
                          model: "qwen2.5-coder-7b-instruct", isBuiltIn: false)
    }
}

// MARK: - Output Lines

struct CoordinatorOutputLine: Identifiable {
    let id = UUID()
    let timestamp: Date
    let text: String
    let level: Level

    enum Level { case info, success, error, agent }

    var color: Color {
        switch level {
        case .info:    return .secondary
        case .success: return Color(red: 0.0, green: 0.88, blue: 0.45)
        case .error:   return .red
        case .agent:   return Color(red: 0.20, green: 0.75, blue: 1.00)
        }
    }
}

// MARK: - LM Studio Settings

struct LMStudioSettings {
    var temperature: Double = 0.3
    var maxTokens: Int = 2048
    var topP: Double = 0.95
    var systemPromptOverride: String = ""   // empty = use engine default
}

struct CoordinatorRuntimeSettings: Codable {
    var workerBackend: String = "kimi-pool"
    var workerModel: String = "kimi-3.5"
    var dispatchPath: String = "kimi-pool"
    var bridgeContext: String = ""
    var bridgeWorktree: String = "."
    var bridgeAgents: Int = 4
    var bridgeStrategy: String = "parallel"
    var bridgeRoles: String = ""
    var bridgeTimeoutSeconds: Int = 1800

    enum CodingKeys: String, CodingKey {
        case workerBackend, workerModel, dispatchPath
        case bridgeContext, bridgeWorktree, bridgeAgents, bridgeStrategy, bridgeRoles, bridgeTimeoutSeconds
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workerBackend = try c.decodeIfPresent(String.self, forKey: .workerBackend) ?? "kimi-pool"
        workerModel = try c.decodeIfPresent(String.self, forKey: .workerModel) ?? "kimi-3.5"
        dispatchPath = try c.decodeIfPresent(String.self, forKey: .dispatchPath) ?? "kimi-pool"
        bridgeContext = try c.decodeIfPresent(String.self, forKey: .bridgeContext) ?? ""
        bridgeWorktree = try c.decodeIfPresent(String.self, forKey: .bridgeWorktree) ?? "."
        bridgeAgents = try c.decodeIfPresent(Int.self, forKey: .bridgeAgents) ?? 4
        bridgeStrategy = try c.decodeIfPresent(String.self, forKey: .bridgeStrategy) ?? "parallel"
        bridgeRoles = try c.decodeIfPresent(String.self, forKey: .bridgeRoles) ?? ""
        bridgeTimeoutSeconds = try c.decodeIfPresent(Int.self, forKey: .bridgeTimeoutSeconds) ?? 1800
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workerBackend, forKey: .workerBackend)
        try c.encode(workerModel, forKey: .workerModel)
        try c.encode(dispatchPath, forKey: .dispatchPath)
        try c.encode(bridgeContext, forKey: .bridgeContext)
        try c.encode(bridgeWorktree, forKey: .bridgeWorktree)
        try c.encode(bridgeAgents, forKey: .bridgeAgents)
        try c.encode(bridgeStrategy, forKey: .bridgeStrategy)
        try c.encode(bridgeRoles, forKey: .bridgeRoles)
        try c.encode(bridgeTimeoutSeconds, forKey: .bridgeTimeoutSeconds)
    }
}

// MARK: - Resolved inference params (global defaults merged with per-model overrides)

struct ResolvedInferenceParams {
    let temperature: Double
    let maxTokens: Int
    let topP: Double
    let systemPrompt: String
}

// MARK: - Manager

@MainActor
final class CoordinatorManager: ObservableObject {

    static let shared = CoordinatorManager()

    @Published var coordinators: [CoordinatorConfig]
    @Published var activeId: UUID
    @Published var outputLines: [CoordinatorOutputLine] = []
    @Published var isDispatching = false
    @Published var lmSettings = LMStudioSettings()    // model inference params
    @Published var localRuns: [AgentRun] = []         // LM Studio runs (not in the control-plane)
    @Published var runtimeSettings: CoordinatorRuntimeSettings {
        didSet { persistRuntimeSettings() }
    }

    private var healthTask: Task<Void, Never>?
    private let runtimeSettingsKey = "ggas.control.runtime.settings"

    private init() {
        let defaults: [CoordinatorConfig] = [
            .claudeDefault(), .kimiDefault(), .lmStudioDefault()
        ]
        self.coordinators = defaults
        self.activeId = defaults[0].id
        if let data = UserDefaults.standard.data(forKey: runtimeSettingsKey),
           let decoded = try? JSONDecoder().decode(CoordinatorRuntimeSettings.self, from: data) {
            self.runtimeSettings = decoded
        } else {
            self.runtimeSettings = CoordinatorRuntimeSettings()
        }
        startHealthPolling()
    }

    var active: CoordinatorConfig? {
        coordinators.first { $0.id == activeId }
    }

    // MARK: - Dispatch

    func dispatch(task: String) async {
        guard let coord = active else { return }
        isDispatching = true
        addLine("→ Dispatching via \(coord.label)…", level: .info)

        do {
            let selectedProviderId = ProviderDetectionService.shared.selectedProvider?.id
            switch coord.type {
            case .claude:
                let run = try await A2AClient.shared.dispatch(
                    task: task,
                    mode: "auto",
                    source: "coordinator-claude",
                    coordinator: "claude",
                    model: coord.model,
                    coordinatorProvider: selectedProviderId,
                    coordinatorModel: coord.model,
                    workerBackend: runtimeSettings.workerBackend,
                    workerModel: runtimeSettings.workerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : runtimeSettings.workerModel,
                    dispatchPath: runtimeSettings.dispatchPath,
                    bridgeContext: normalizedBridgeContext,
                    bridgeWorktree: normalizedBridgeWorktree,
                    bridgeAgents: runtimeSettings.bridgeAgents,
                    bridgeStrategy: runtimeSettings.bridgeStrategy,
                    bridgeRoles: normalizedBridgeRoles,
                    bridgeTimeoutSeconds: runtimeSettings.bridgeTimeoutSeconds
                )
                addLine("✅ run:\(run.runId) dispatched (Claude)", level: .success)

            case .kimi:
                // Capacity gate (Phase 4) — prevent over-spawning OOM crashes
                let capacity = HardwareTopologyService.shared.maxConcurrentAgents()
                if capacity.maxConcurrentAgents < 1 {
                    addLine("⚠️ Insufficient RAM to spawn Kimi agent (\(String(format: "%.1f", capacity.availableRAMGB)) GB available). " +
                            "Close other apps and retry.", level: .error)
                    isDispatching = false
                    return
                }
                addLine("✅ Capacity: up to \(capacity.maxConcurrentAgents) agents (\(String(format: "%.1f", capacity.availableRAMGB)) GB free)", level: .info)
                let run = try await A2AClient.shared.dispatch(
                    task: task,
                    mode: "auto",
                    source: "coordinator-kimi",
                    coordinator: "custom",
                    model: coord.model,
                    coordinatorProvider: "antigravity",
                    coordinatorModel: coord.model,
                    workerBackend: runtimeSettings.workerBackend,
                    workerModel: runtimeSettings.workerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : runtimeSettings.workerModel,
                    dispatchPath: runtimeSettings.dispatchPath,
                    bridgeContext: normalizedBridgeContext,
                    bridgeWorktree: normalizedBridgeWorktree,
                    bridgeAgents: runtimeSettings.bridgeAgents,
                    bridgeStrategy: runtimeSettings.bridgeStrategy,
                    bridgeRoles: normalizedBridgeRoles,
                    bridgeTimeoutSeconds: runtimeSettings.bridgeTimeoutSeconds
                )
                addLine("✅ run:\(run.runId) dispatched (Kimi →A2A)", level: .success)


            case .lmStudio:
                let runId = "local-\(UUID().uuidString.prefix(8))"
                let startedAt = ISO8601DateFormatter().string(from: Date())
                let startTime = Date()

                // Insert a "running" placeholder so Run History updates immediately
                var placeholder = AgentRun(
                    runId: runId, task: task, mode: "lm-studio",
                    source: coord.label, status: .running,
                    prUrl: nil, startedAt: startedAt,
                    completedAt: nil, durationMs: nil)
                placeholder.log = ["📥 Prompt: \(task)"]
                localRuns.insert(placeholder, at: 0)

                do {
                    // Resolve per-model config, falling back to global lmSettings
                    let params = resolvedParams(for: coord.model)
                    let effectiveSettings = LMStudioSettings(
                        temperature: params.temperature,
                        maxTokens: params.maxTokens,
                        topP: params.topP,
                        systemPromptOverride: params.systemPrompt
                    )
                    let response = try await LMStudioEngine.shared.query(
                        task: task, config: coord, settings: effectiveSettings)
                    addLine("🤖 \(response)", level: .agent)

                    let ms = Int(Date().timeIntervalSince(startTime) * 1000)
                    let completedAt = ISO8601DateFormatter().string(from: Date())
                    var completed = AgentRun(
                        runId: runId, task: task, mode: "lm-studio",
                        source: coord.label, status: .complete,
                        prUrl: nil, startedAt: startedAt,
                        completedAt: completedAt, durationMs: ms)
                    completed.log = ["📥 Prompt: \(task)", "🤖 \(response)"]

                    if let idx = localRuns.firstIndex(where: { $0.runId == runId }) {
                        localRuns[idx] = completed
                    }
                } catch {
                    addLine("❌ \(error.localizedDescription)", level: .error)
                    let ms = Int(Date().timeIntervalSince(startTime) * 1000)
                    var failed = AgentRun(
                        runId: runId, task: task, mode: "lm-studio",
                        source: coord.label, status: .failed,
                        prUrl: nil, startedAt: startedAt,
                        completedAt: ISO8601DateFormatter().string(from: Date()),
                        durationMs: ms)
                    failed.log = ["📥 Prompt: \(task)", "❌ \(error.localizedDescription)"]
                    if let idx = localRuns.firstIndex(where: { $0.runId == runId }) {
                        localRuns[idx] = failed
                    }
                }
            }
        } catch {
            addLine("❌ \(error.localizedDescription)", level: .error)
        }

        isDispatching = false
    }

    // MARK: - Per-model config resolution

    /// Resolve inference params for a model: per-model config overrides global lmSettings.
    func resolvedParams(for modelId: String) -> ResolvedInferenceParams {
        let cfg = ModelUserConfigStore.shared.config(for: modelId)
        return ResolvedInferenceParams(
            temperature: cfg.temperature > 0 ? cfg.temperature : lmSettings.temperature,
            maxTokens: cfg.maxTokens > 0 ? cfg.maxTokens : lmSettings.maxTokens,
            topP: cfg.topP > 0 ? cfg.topP : lmSettings.topP,
            systemPrompt: cfg.systemPromptOverride.isEmpty
                ? lmSettings.systemPromptOverride
                : cfg.systemPromptOverride
        )
    }

    /// Pin a model to a specific coordinator (writes to ModelUserConfigStore).
    func setModelAsCoordinator(modelId: String, coordinatorId: UUID) {
        ModelUserConfigStore.shared.assignCoordinator(modelId: modelId, coordinatorId: coordinatorId)
        addLine("📌 \(modelId) pinned to coordinator", level: .info)
    }

    // MARK: - Coordinator CRUD

    /// Call this after the user loads a model in LMStudioManagerView so the dispatch
    /// engine sends the correct model id to /v1/chat/completions.
    func updateLMStudioModel(id: String) {
        guard let idx = coordinators.firstIndex(where: { $0.type == .lmStudio }) else { return }
        coordinators[idx].model = id
        // Also update label so the card shows the short model name
        coordinators[idx].label = id.components(separatedBy: "/").last ?? id
        addLine("⇄ Active model → \(coordinators[idx].label)", level: .info)
    }

    func add(_ config: CoordinatorConfig) {
        coordinators.append(config)
    }

    func remove(id: UUID) {
        guard let idx = coordinators.firstIndex(where: { $0.id == id }),
              !coordinators[idx].isBuiltIn else { return }
        if activeId == id { activeId = coordinators[0].id }
        coordinators.remove(at: idx)
    }

    func setActive(id: UUID) {
        activeId = id
        addLine("⇄ Switched to \(coordinators.first { $0.id == id }?.label ?? id.uuidString)", level: .info)
    }

    func clearOutput() { outputLines.removeAll() }

    // MARK: - Health polling

    private func startHealthPolling() {
        healthTask?.cancel()
        healthTask = Task {
            while !Task.isCancelled {
                await checkHealth()
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    private func checkHealth() async {
        for i in coordinators.indices {
            let online: Bool
            switch coordinators[i].type {
            case .claude:
                online = await A2AClient.shared.ping()
            case .kimi:
                let bin = coordinators[i].model
                if bin.hasPrefix("/") {
                    online = FileManager.default.fileExists(atPath: bin)
                } else {
                    // Check common binary locations on macOS
                    let searchPaths = ["/usr/local/bin", "/usr/bin", "/opt/homebrew/bin",
                                       "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/.cargo/bin"]
                    online = searchPaths.contains { dir in
                        FileManager.default.fileExists(atPath: "\(dir)/\(bin)")
                    }
                }
            case .lmStudio:
                let ep = coordinators[i].endpoint
                online = await LMStudioEngine.shared.ping(endpoint: ep)
            }
            coordinators[i].isOnline = online
        }
    }

    // MARK: - Helpers

    func addLine(_ text: String, level: CoordinatorOutputLine.Level) {
        let line = CoordinatorOutputLine(timestamp: Date(), text: text, level: level)
        outputLines.append(line)
        if outputLines.count > 500 { outputLines.removeFirst(100) }
    }

    private func persistRuntimeSettings() {
        guard let data = try? JSONEncoder().encode(runtimeSettings) else { return }
        UserDefaults.standard.set(data, forKey: runtimeSettingsKey)
    }

    private var normalizedBridgeWorktree: String? {
        let trimmed = runtimeSettings.bridgeWorktree.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedBridgeContext: String? {
        let trimmed = runtimeSettings.bridgeContext.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedBridgeRoles: [String]? {
        let roles = runtimeSettings.bridgeRoles
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return roles.isEmpty ? nil : roles
    }
}

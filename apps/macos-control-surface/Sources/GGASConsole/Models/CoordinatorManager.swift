// CoordinatorManager.swift — Singleton managing all coordinator agent configurations.
// Routes dispatch calls to the active coordinator backend.

import SwiftUI
import Foundation

// MARK: - Coordinator Types

enum CoordinatorType: String, CaseIterable, Identifiable, Codable {
    case codex    = "Codex"
    case claude   = "Claude Code"
    case kimi     = "Kimi Code"
    case lmStudio = "LM Studio"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .codex:    return "chevron.left.forwardslash.chevron.right"
        case .claude:   return "c.circle.fill"
        case .kimi:     return "k.circle.fill"
        case .lmStudio: return "cpu.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .codex:    return Color(red: 0.19, green: 0.69, blue: 0.96)
        case .claude:   return Color(red: 0.73, green: 0.53, blue: 1.00)   // purple
        case .kimi:     return Color(red: 0.20, green: 0.75, blue: 1.00)   // blue
        case .lmStudio: return Color(red: 0.94, green: 0.72, blue: 0.18)   // amber
        }
    }
}

enum WorkerRuntimeOption: String, CaseIterable, Identifiable, Codable {
    case codex
    case claude
    case kimi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .kimi: return "Kimi Code"
        }
    }

    var icon: String {
        switch self {
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "c.circle.fill"
        case .kimi: return "k.circle.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .codex: return Color(red: 0.19, green: 0.69, blue: 0.96)
        case .claude: return Color(red: 0.73, green: 0.53, blue: 1.00)
        case .kimi: return Color(red: 0.20, green: 0.75, blue: 1.00)
        }
    }

    var defaultModel: String {
        switch self {
        case .codex: return "gpt-5.3-codex"
        case .claude: return "claude-sonnet-4-6"
        case .kimi: return "kimi-k2.5"
        }
    }

    func backend(topology: WorkerTopologyOption) -> String {
        switch (self, topology) {
        case (.codex, .single): return "codex-agent"
        case (.codex, .team): return "codex-swarm"
        case (.claude, .single): return "claude-agent"
        case (.claude, .team): return "claude-swarm"
        case (.kimi, .single): return "kimi-bridge-agent"
        case (.kimi, .team): return "kimi-bridge-swarm"
        }
    }
}

enum WorkerTopologyOption: String, CaseIterable, Identifiable, Codable {
    case single
    case team

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "Single Worker"
        case .team: return "Agent Team"
        }
    }
}

enum WorkerRoleOption: String, CaseIterable, Identifiable, Codable {
    case scout
    case planner
    case builder
    case reviewer
    case assembler
    case specialist

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scout: return "Scout"
        case .planner: return "Planner"
        case .builder: return "Builder"
        case .reviewer: return "Reviewer"
        case .assembler: return "Assembler"
        case .specialist: return "Specialist"
        }
    }

    var icon: String {
        switch self {
        case .scout: return "binoculars.fill"
        case .planner: return "list.bullet.clipboard.fill"
        case .builder: return "hammer.fill"
        case .reviewer: return "checkmark.shield.fill"
        case .assembler: return "square.stack.3d.down.right.fill"
        case .specialist: return "sparkles"
        }
    }

    var defaultPersonaId: String {
        switch self {
        case .scout:
            return "explorer-agent"
        case .planner:
            return "project-planner"
        case .reviewer:
            return "test-engineer"
        case .builder, .assembler, .specialist:
            return "backend-specialist"
        }
    }

    var personaLabel: String {
        switch defaultPersonaId {
        case "explorer-agent":
            return "Explorer Agent"
        case "project-planner":
            return "Project Planner"
        case "test-engineer":
            return "Test Engineer"
        case "backend-specialist":
            return "Backend Specialist"
        default:
            return defaultPersonaId
        }
    }

    var personaSummary: String {
        "\(label) -> \(personaLabel)"
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
        CoordinatorConfig(type: .claude, label: "claude-opus-4-5",
                          endpoint: "", model: "claude-opus-4-5", isBuiltIn: true)
    }
    static func codexDefault() -> CoordinatorConfig {
        CoordinatorConfig(type: .codex, label: "gpt-5.3-codex",
                          endpoint: "", model: "gpt-5.3-codex", isBuiltIn: true)
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
    var workerBackend: String = "kimi-bridge-agent"
    var workerModel: String = "kimi-k2.5"
    var dispatchPath: String = "kimi-bridge-agent"
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
        workerBackend = try c.decodeIfPresent(String.self, forKey: .workerBackend) ?? "kimi-bridge-agent"
        workerModel = try c.decodeIfPresent(String.self, forKey: .workerModel) ?? "kimi-3.5"
        dispatchPath = try c.decodeIfPresent(String.self, forKey: .dispatchPath) ?? "kimi-bridge-agent"
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

    var selectedWorkerRuntime: WorkerRuntimeOption {
        let backend = workerBackend.lowercased()
        if backend.contains("claude") {
            return .claude
        }
        if backend.contains("codex") {
            return .codex
        }
        return .kimi
    }

    var selectedWorkerTopology: WorkerTopologyOption {
        workerBackend.lowercased().contains("swarm") ? .team : .single
    }

    var selectedWorkerRoles: [WorkerRoleOption] {
        bridgeRoles
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .compactMap(WorkerRoleOption.init(rawValue:))
            .reduce(into: [WorkerRoleOption]()) { partialResult, role in
                if !partialResult.contains(role) {
                    partialResult.append(role)
                }
            }
    }

    var usesExplicitWorkerRoles: Bool {
        !selectedWorkerRoles.isEmpty
    }

    var recommendedWorkerRoles: [WorkerRoleOption] {
        let requestedCount = max(1, min(6, bridgeAgents))
        let sequence: [WorkerRoleOption] = [.scout, .builder, .reviewer, .planner, .specialist, .assembler]
        return Array(sequence.prefix(requestedCount))
    }

    var effectiveWorkerRoles: [WorkerRoleOption] {
        usesExplicitWorkerRoles ? selectedWorkerRoles : recommendedWorkerRoles
    }

    var bridgeRolesForDispatch: [String]? {
        let roles = selectedWorkerRoles.map(\.rawValue)
        return roles.isEmpty ? nil : roles
    }

    var effectiveBridgeAgentsForDispatch: Int {
        if selectedWorkerTopology == .team, usesExplicitWorkerRoles {
            return max(selectedWorkerRoles.count, 1)
        }
        return bridgeAgents
    }

    var plannedWorkerCount: Int {
        if selectedWorkerTopology == .team, usesExplicitWorkerRoles {
            return max(selectedWorkerRoles.count, 1)
        }
        return selectedWorkerTopology == .team ? max(bridgeAgents, 2) : 1
    }

    var workerPlanLabel: String {
        if selectedWorkerTopology == .team {
            return "\(selectedWorkerRuntime.label) Team ×\(plannedWorkerCount)"
        }
        return "\(selectedWorkerRuntime.label) Single"
    }

    mutating func setWorkerRuntime(_ runtime: WorkerRuntimeOption) {
        let previousRuntime = selectedWorkerRuntime
        let topology = selectedWorkerTopology
        let currentModel = workerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldResetModel = currentModel.isEmpty || currentModel == previousRuntime.defaultModel
        workerBackend = runtime.backend(topology: topology)
        dispatchPath = workerBackend
        if shouldResetModel {
            workerModel = runtime.defaultModel
        }
        if topology == .team && bridgeAgents < 2 {
            bridgeAgents = 3
        }
    }

    mutating func setWorkerTopology(_ topology: WorkerTopologyOption) {
        workerBackend = selectedWorkerRuntime.backend(topology: topology)
        dispatchPath = workerBackend
        if topology == .team && bridgeAgents < 2 {
            bridgeAgents = 3
        }
    }

    mutating func toggleWorkerRole(_ role: WorkerRoleOption) {
        var roles = usesExplicitWorkerRoles ? selectedWorkerRoles : recommendedWorkerRoles
        if let existingIndex = roles.firstIndex(of: role) {
            roles.remove(at: existingIndex)
        } else {
            roles.append(role)
        }
        bridgeRoles = roles.map(\.rawValue).joined(separator: ", ")
        bridgeAgents = max(roles.count, 1)
    }

    mutating func resetWorkerRolesToHarnessDefault() {
        bridgeRoles = ""
    }

    mutating func applyWorkerRoles(_ roles: [WorkerRoleOption]) {
        let uniqueRoles = roles.reduce(into: [WorkerRoleOption]()) { partialResult, role in
            if !partialResult.contains(role) {
                partialResult.append(role)
            }
        }
        bridgeRoles = uniqueRoles.map(\.rawValue).joined(separator: ", ")
        bridgeAgents = max(uniqueRoles.count, 1)
        setWorkerTopology(.team)
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
            .codexDefault(), .claudeDefault(), .kimiDefault(), .lmStudioDefault()
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
            let dispatchIdentity = dispatchIdentity(for: coord, selectedProviderId: selectedProviderId)
            switch coord.type {
            case .codex:
                let run = try await A2AClient.shared.dispatch(
                    task: task,
                    mode: "auto",
                    source: dispatchIdentity.source,
                    coordinator: dispatchIdentity.coordinator,
                    model: coord.model,
                    coordinatorProvider: dispatchIdentity.coordinatorProvider,
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
                addLine("✅ run:\(run.runId) dispatched (Codex)", level: .success)

            case .claude:
                let run = try await A2AClient.shared.dispatch(
                    task: task,
                    mode: "auto",
                    source: dispatchIdentity.source,
                    coordinator: dispatchIdentity.coordinator,
                    model: coord.model,
                    coordinatorProvider: dispatchIdentity.coordinatorProvider,
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
                    source: dispatchIdentity.source,
                    coordinator: dispatchIdentity.coordinator,
                    model: coord.model,
                    coordinatorProvider: dispatchIdentity.coordinatorProvider,
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
                addLine("✅ run:\(run.runId) dispatched (Kimi → harness)", level: .success)


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
            case .codex:
                online = localBinaryExists(command: "codex", envVar: "CODEX_BINARY")
            case .claude:
                online = await A2AClient.shared.ping()
            case .kimi:
                online = localBinaryExists(command: coordinators[i].model, envVar: "KIMI_BINARY")
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
        runtimeSettings.bridgeRolesForDispatch
    }

    func dispatchIdentity(for coord: CoordinatorConfig, selectedProviderId: String?) -> (source: String, coordinator: String, coordinatorProvider: String?) {
        switch coord.type {
        case .codex:
            return ("coordinator-codex", "codex", selectedProviderId ?? "openai")
        case .claude:
            return ("coordinator-claude", "claude", selectedProviderId ?? "claude")
        case .kimi:
            return ("coordinator-kimi", "kimi", "antigravity")
        case .lmStudio:
            return ("coordinator-lmstudio", "custom", selectedProviderId)
        }
    }

    private func localBinaryExists(command: String, envVar: String? = nil) -> Bool {
        if let envVar, let envPath = ProcessInfo.processInfo.environment[envVar], !envPath.isEmpty {
            return FileManager.default.fileExists(atPath: envPath)
        }

        if command.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: command)
        }

        let searchPaths = [
            "/usr/local/bin",
            "/usr/bin",
            "/opt/homebrew/bin",
            "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/.cargo/bin",
            "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/.local/bin",
            "\(ProcessInfo.processInfo.environment["HOME"] ?? "")/.kimi/bin"
        ]
        return searchPaths.contains { dir in
            FileManager.default.fileExists(atPath: "\(dir)/\(command)")
        }
    }
}

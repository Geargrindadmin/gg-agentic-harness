// Models.swift — GGAS Console shared data models

import Foundation

// MARK: - Task 9: RunEvent SSE model (from GET /api/events)

enum RunEventType: String, Codable {
    case runCreated    = "run_created"
    case runStarted    = "run_started"
    case runCompleted  = "run_completed"
    case runFailed     = "run_failed"
    case runCancelled  = "run_cancelled"
    case snapshot                      // initial hydration burst on connect
    case unknown
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RunEventType(rawValue: raw) ?? .unknown
    }
}

struct RunEventMessage: Decodable {
    let type: RunEventType
    let runId: String?
    let status: String?
    let coordinator: String?
    let model: String?
    let coordinatorProvider: String?
    let coordinatorModel: String?
    let workerBackend: String?
    let workerModel: String?
    let dispatchPath: String?
    let task: String?
    let runs: [AgentRun]?   // present for type == .snapshot
    let ts: String?
}

// MARK: - A2A REST API models

struct AgentRun: Identifiable, Codable, Hashable {
    var id: String { runId }
    let runId: String
    let task: String
    let mode: String
    let source: String
    let coordinator: String?
    let model: String?
    let coordinatorProvider: String?
    let coordinatorModel: String?
    let workerBackend: String?
    let workerModel: String?
    let dispatchPath: String?
    let status: RunStatus
    let prUrl: String?
    let startedAt: String
    let updatedAt: String?
    let completedAt: String?
    let durationMs: Int?
    var log: [String] = []   // populated separately via GET /api/task/:id

    enum CodingKeys: String, CodingKey {
        case runId, task, mode, source, coordinator, model
        case coordinatorProvider, coordinatorModel, workerBackend, workerModel, dispatchPath
        case status, prUrl, startedAt, updatedAt, completedAt, durationMs, log
    }

    // Custom init so that absent 'log' key (not returned by /api/runs list) defaults to []
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runId       = try c.decode(String.self,    forKey: .runId)
        task        = try c.decode(String.self,    forKey: .task)
        mode        = try c.decode(String.self,    forKey: .mode)
        source      = try c.decode(String.self,    forKey: .source)
        coordinator = try c.decodeIfPresent(String.self, forKey: .coordinator)
        model       = try c.decodeIfPresent(String.self, forKey: .model)
        coordinatorProvider = try c.decodeIfPresent(String.self, forKey: .coordinatorProvider)
        coordinatorModel    = try c.decodeIfPresent(String.self, forKey: .coordinatorModel)
        workerBackend = try c.decodeIfPresent(String.self, forKey: .workerBackend)
        workerModel   = try c.decodeIfPresent(String.self, forKey: .workerModel)
        dispatchPath  = try c.decodeIfPresent(String.self, forKey: .dispatchPath)
        status      = try c.decode(RunStatus.self, forKey: .status)
        prUrl       = try c.decodeIfPresent(String.self, forKey: .prUrl)
        startedAt   = try c.decode(String.self,    forKey: .startedAt)
        updatedAt   = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        durationMs  = try c.decodeIfPresent(Int.self,    forKey: .durationMs)
        log         = (try? c.decodeIfPresent([String].self, forKey: .log)) ?? []
    }

    // Memberwise init used by A2AClient.dispatch()
    init(runId: String, task: String, mode: String, source: String,
         coordinator: String? = nil, model: String? = nil,
         coordinatorProvider: String? = nil, coordinatorModel: String? = nil,
         workerBackend: String? = nil, workerModel: String? = nil, dispatchPath: String? = nil,
         status: RunStatus, prUrl: String?, startedAt: String,
         completedAt: String?, durationMs: Int?) {
        self.runId       = runId
        self.task        = task
        self.mode        = mode
        self.source      = source
        self.coordinator = coordinator
        self.model = model
        self.coordinatorProvider = coordinatorProvider
        self.coordinatorModel = coordinatorModel
        self.workerBackend = workerBackend
        self.workerModel = workerModel
        self.dispatchPath = dispatchPath
        self.status      = status
        self.prUrl       = prUrl
        self.startedAt   = startedAt
        self.updatedAt   = nil
        self.completedAt = completedAt
        self.durationMs  = durationMs
        self.log         = []
    }

    enum RunStatus: String, Codable, CaseIterable {
        case accepted, running, complete, failed, cancelled
        var color: String {
            switch self {
            case .running:   return "yellow"
            case .complete:  return "green"
            case .failed:    return "red"
            case .cancelled: return "gray"
            case .accepted:  return "blue"
            }
        }
    }

    var durationFormatted: String {
        guard let ms = durationMs else { return "—" }
        if ms < 1000 { return "\(ms)ms" }
        if ms < 60_000 { return String(format: "%.1fs", Double(ms) / 1000) }
        return "\(ms / 60_000)m \((ms % 60_000) / 1000)s" }
    func hash(into hasher: inout Hasher) { hasher.combine(runId) }
    static func == (lhs: AgentRun, rhs: AgentRun) -> Bool { lhs.runId == rhs.runId }
}

struct LogLine: Identifiable, Codable, Hashable {
    let id: String
    let ts: String
    let level: String
    let msg: String
    let runId: String?
}

struct SkillStats: Codable, Identifiable {
    var id: String { skill }
    let skill: String
    let type: String
    let calls: Int
    let failures: Int
    let avgDurationMs: Double?
    let lastUsed: String?
}

struct AgentAnalyticsSummary: Codable {
    let totalRuns: Int
    let totalWorkers: Int
    let activeWorkers: Int
    let failedWorkers: Int
    let distinctPersonas: Int
    let distinctRuntimes: Int
    let lastUpdatedAt: String?
}

struct AgentAnalyticsMetric: Codable, Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let type: String
    let calls: Int
    let failures: Int
    let active: Int
    let avgDurationMs: Double?
    let lastUsed: String?
}

struct DispatchRequest: Codable {
    let task: String
    let mode: String
    let source: String
    let coordinator: String?
    let model: String?
    let coordinatorProvider: String?
    let coordinatorModel: String?
    let workerBackend: String?
    let workerModel: String?
    let dispatchPath: String?
    let bridgeContext: String?
    let bridgeWorktree: String?
    let bridgeAgents: Int?
    let bridgeStrategy: String?
    let bridgeRoles: [String]?
    let bridgeTimeoutSeconds: Int?
    let harnessSettings: HarnessSettingsModel?
}

// MARK: - Integration control surface models

struct HarnessSettingsModel: Codable, Equatable {
    struct Diagram: Codable, Equatable {
        var autoRefreshSeconds: Int
        var primaryArtifact: String
    }

    struct Execution: Codable, Equatable {
        var loopBudget: Int
        var retryLimit: Int
        var retryBackoffSeconds: [Int]
        var promptImproverMode: String
        var contextSource: String
        var hydraMode: String
        var validateMode: String
        var docSyncMode: String
    }

    struct Governor: Codable, Equatable {
        var cpuHighPct: Double?
        var cpuLowPct: Double?
        var modelVramGb: Double?
        var perAgentOverheadGb: Double?
        var reservedRamGb: Double?
    }

    struct Artifacts: Codable, Equatable {
        var promptVersion: String?
        var workflowVersion: String?
        var blueprintVersion: String?
        var toolBundle: String?
        var riskTier: String?
    }

    var diagram: Diagram
    var execution: Execution
    var governor: Governor
    var artifacts: Artifacts

    static let defaults = HarnessSettingsModel(
        diagram: .init(autoRefreshSeconds: 15, primaryArtifact: "docs/architecture/agentic-harness-dynamic-user-diagram.html"),
        execution: .init(
            loopBudget: 50,
            retryLimit: 3,
            retryBackoffSeconds: [1, 2, 4],
            promptImproverMode: "auto",
            contextSource: "standard",
            hydraMode: "off",
            validateMode: "none",
            docSyncMode: "auto"
        ),
        governor: .init(cpuHighPct: nil, cpuLowPct: nil, modelVramGb: nil, perAgentOverheadGb: nil, reservedRamGb: nil),
        artifacts: .init(promptVersion: nil, workflowVersion: nil, blueprintVersion: nil, toolBundle: nil, riskTier: nil)
    )
}

struct HarnessDiagramModel: Codable, Equatable {
    struct DiagramInfo: Codable, Equatable {
        let title: String
        let artifactPath: String
        let artifactRelativePath: String
        let autoRefreshSeconds: Int
    }

    struct LiveStatus: Codable, Equatable {
        struct RuntimeInfo: Codable, Equatable {
            let available: Bool
            let path: String?
            let runningAcp: Int?
        }

        struct Pool: Codable, Equatable {
            let total: Int
            let active: Int
            let idle: Int
        }

        struct Runs: Codable, Equatable {
            let total: Int
            let running: Int
        }

        let codex: RuntimeInfo
        let kimi: RuntimeInfo
        let claude: RuntimeInfo
        let pool: Pool
        let runs: Runs
        let governor: GovernorStatus
        let uptime: Double
    }

    struct RuntimeCoordinatorSelection: Codable, Equatable {
        let selected: String
        let reason: String
        let requested: String?
    }

    struct RuntimeDiscovery: Codable, Equatable {
        let runtime: String
        let label: String?
        let binaryPath: String?
        let authenticated: Bool
        let localCliAuth: Bool
        let directApiAvailable: Bool
        let preferredTransport: String?
        let summary: String
    }

    struct LiveActivity: Codable, Equatable {
        let totalRuns: Int
        let runningRuns: Int
        let completedRuns: Int
        let failedRuns: Int
        let activeWorkers: Int
        let pendingMessages: Int
        let latestRunId: String?
        let latestTask: String?
        let latestStatus: String?
        let latestUpdatedAt: String?
    }

    struct BreakdownEntry: Codable, Equatable, Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let count: Int
    }

    struct RecentRun: Codable, Equatable, Identifiable {
        var id: String { runId }
        let runId: String
        let task: String
        let status: String
        let coordinator: String?
        let workerBackend: String?
        let updatedAt: String
    }

    struct Live: Codable, Equatable {
        struct RuntimeDiscoveryPayload: Codable, Equatable {
            let coordinatorSelection: RuntimeCoordinatorSelection
            let discoveries: [RuntimeDiscovery]
        }

        let status: LiveStatus
        let runtimeDiscovery: RuntimeDiscoveryPayload
        let activity: LiveActivity
        let workersByRole: [BreakdownEntry]
        let workersByRuntime: [BreakdownEntry]
        let recentRuns: [RecentRun]
    }

    let generatedAt: String
    let projectRoot: String
    let diagram: DiagramInfo
    let settings: HarnessSettingsModel
    let live: Live
}

struct IntegrationSettingsModel: Codable {
    struct LiteLLM: Codable {
        var enabled: Bool
        var baseUrl: String
        var apiKey: String
        var model: String
        var temperature: Double
        var maxTokens: Int
        var timeoutMs: Int
    }

    struct Observability: Codable {
        struct Langfuse: Codable {
            var enabled: Bool
            var host: String
            var publicKey: String
            var secretKey: String
        }
        struct OpenLLMetry: Codable {
            var enabled: Bool
            var otlpEndpoint: String
            var headers: [String: String]
        }
        var enabled: Bool
        var serviceName: String
        var environment: String
        var langfuse: Langfuse
        var openllmetry: OpenLLMetry
    }

    struct QualityTools: Codable {
        struct ToolFlags: Codable {
            var lint: Bool
            var typeCheck: Bool
            var test: Bool
            var build: Bool
        }
        var defaultProjectRoot: String
        var tools: ToolFlags
    }

    struct McpCatalog: Codable {
        var catalogPath: String
        var kimiConfigPath: String
        var selectedServerIds: [String]
    }

    var liteLLM: LiteLLM
    var observability: Observability
    var qualityTools: QualityTools
    var mcpCatalog: McpCatalog
}

struct QualityJobModel: Codable, Identifiable {
    struct ToolFailure: Codable {
        let tool: String
        let message: String
    }
    let id: String
    let status: String
    let tools: [String]
    let profile: String
    let startedAt: String
    let completedAt: String?
    let exitCode: Int?
    let output: [String]
    let failures: [ToolFailure]
}

struct MCPServerCatalogItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let mcpName: String
    let description: String
    let command: String
    let args: [String]?
    let env: [String: String]?
}

struct MCPServerCatalogResponse: Codable {
    let servers: [MCPServerCatalogItem]
    let selectedServerIds: [String]
    let kimiConfigPath: String
}

struct MCPApplyResponse: Codable {
    let selectedServerIds: [String]
    let appliedServers: [String]
    let kimiConfigPath: String
}

/// Response from GET /api/status
struct AgentStatus: Codable {
    struct BinaryInfo: Codable {
        let available: Bool
        let path: String?
        let runningAcp: Int?
    }
    struct PoolInfo: Codable {
        let total: Int
        let active: Int
        let idle: Int
    }
    struct RunsInfo: Codable {
        let total: Int
        let running: Int
    }
    let codex: BinaryInfo
    let kimi: BinaryInfo
    let claude: BinaryInfo
    let pool: PoolInfo
    let runs: RunsInfo
    let uptime: Double
}

struct GovernorStatus: Codable, Equatable {
    let timestamp: String
    let totalRamGb: Double
    let freeRamGb: Double
    let availableRamGb: Double
    let reservedRamGb: Double
    let modelVramGb: Double
    let perAgentOverheadGb: Double
    let cpuPressure: Double
    let cpuPaused: Bool
    let allowedAgents: Int
    let activeWorkers: Int
    let queuedWorkers: Int
    let canSpawnNow: Bool
    let note: String
    let reason: String
}

struct ControlPlaneMeta: Codable, Hashable {
    static let expectedProtocolVersion = 1
    static let requiredCapabilities: Set<String> = [
        "planner",
        "usage",
        "governor",
        "worker-steering",
        "sse-events"
    ]

    let service: String
    let version: String
    let protocolVersion: Int
    let apiBasePath: String
    let capabilities: [String]
    let generatedAt: String

    var capabilitySet: Set<String> {
        Set(capabilities)
    }
}

struct ControlPlaneCompatibility: Hashable {
    let reachable: Bool
    let compatible: Bool
    let meta: ControlPlaneMeta?
    let message: String?
}

struct WorkerActionResponse: Codable {
    let status: String
    let messageId: String?
}

struct TraceEntry: Identifiable, Codable {
    let id: String
    let runId: String
    let agentId: String
    let role: String
    let action: String
    let target: String?
    let timestamp: String
    let result: String
    let summary: String?

    // MARK: - Factory: parse raw log line into structured TraceEntry

    static func parse(line: String, index: Int, runId: String, sessionId: String, startedAt: String) -> TraceEntry {
        // Detect [agent:role-slug] commit prefix
        if let range = line.range(of: #"\[agent:(\w+)-([\w-]+)\]"#, options: .regularExpression) {
            let tag = String(line[range])           // e.g. "[agent:builder-auth]"
            let parts = tag.dropFirst(7).dropLast(1).split(separator: "-", maxSplits: 1)
            let role  = String(parts.first ?? "builder")
            let slug  = String(parts.dropFirst().joined(separator: "-"))
            return TraceEntry(id: "\(runId)-\(index)", runId: runId,
                              agentId: slug, role: role, action: "commit",
                              target: nil, timestamp: startedAt,
                              result: "success", summary: line.replacingOccurrences(of: tag + " ", with: ""))
        }
        // [ggas] system/orchestrator lines
        if line.hasPrefix("[ggas]") {
            let msg = line.replacingOccurrences(of: "[ggas] ", with: "")
            let action = msg.lowercased().contains("error") ? "error"
                       : msg.lowercased().contains("dispatch") ? "dispatch"
                       : msg.lowercased().contains("command") ? "exec"
                       : "info"
            return TraceEntry(id: "\(runId)-\(index)", runId: runId,
                              agentId: "ggas", role: "system", action: action,
                              target: nil, timestamp: startedAt,
                              result: action == "error" ? "failure" : "success", summary: msg)
        }
        // Shell execution lines (starts with $ or common shell prefixes)
        if line.hasPrefix("$") || line.hasPrefix("+ ") || line.hasPrefix("% ") {
            return TraceEntry(id: "\(runId)-\(index)", runId: runId,
                              agentId: sessionId, role: "builder", action: "exec",
                              target: line, timestamp: startedAt,
                              result: "success", summary: nil)
        }
        // File path lines (write/read detection)
        if line.contains("/") && !line.hasPrefix("http") {
            let lower = line.lowercased()
            let action = lower.contains("write") || lower.contains("creat") || lower.contains("modif") ? "write"
                       : lower.contains("read") ? "read"
                       : "output"
            return TraceEntry(id: "\(runId)-\(index)", runId: runId,
                              agentId: sessionId, role: "builder", action: action,
                              target: line.components(separatedBy: " ").first(where: { $0.hasPrefix("/") }),
                              timestamp: startedAt, result: "success", summary: line)
        }
        // Default: treat as agent output
        return TraceEntry(id: "\(runId)-\(index)", runId: runId,
                          agentId: sessionId, role: "runner", action: "output",
                          target: nil, timestamp: startedAt,
                          result: "success", summary: line.isEmpty ? nil : line)
    }
}

// MARK: - Planner models (harness-owned control-plane store)

struct PlannerProject: Codable, Hashable {
    let id: String
    let name: String
    let root: String
}

struct PlannerCounts: Codable, Hashable {
    let todo: Int
    let inProgress: Int
    let done: Int
    let archived: Int
}

struct PlannerNote: Identifiable, Hashable, Codable {
    var id: String
    var title: String
    var content: String
    var pinned: Bool
    var taskId: String?
    var projectId: String?
    var source: String
    var createdAt: String
    var updatedAt: String

    var preview: String {
        String(content.prefix(120))
    }
}

struct PlannerTask: Identifiable, Hashable, Codable {
    var id: String
    var projectId: String
    var title: String
    var description: String?
    var status: String
    var priority: Int
    var source: String
    var sourceSession: String?
    var labels: [String]
    var attachments: [String]
    var isGlobal: Bool
    var runId: String?
    var runtime: String?
    var linkedRunStatus: String?
    var assignedAgentId: String?
    var worktreePath: String?
    var createdAt: String
    var updatedAt: String
    var completedAt: String?
    var notes: [PlannerNote]

    var priorityLabel: String {
        switch priority {
        case 4: return "Urgent"
        case 3: return "High"
        case 2: return "Medium"
        case 1: return "Low"
        default: return "None"
        }
    }

    var priorityColorName: String {
        switch priority {
        case 4: return "red"
        case 3: return "orange"
        case 2: return "yellow"
        case 1: return "blue"
        default: return "gray"
        }
    }

    var runStatusLabel: String? {
        guard let linkedRunStatus, !linkedRunStatus.isEmpty else { return nil }
        return linkedRunStatus.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct PlannerSnapshotModel: Codable {
    let project: PlannerProject
    let tasks: [PlannerTask]
    let notes: [PlannerNote]
    let counts: PlannerCounts
    let updatedAt: String
}

// Backward-compatible aliases while the imported app is being normalized.
typealias ForgeTask = PlannerTask
typealias ForgeTaskNote = PlannerNote
typealias ForgeNote = PlannerNote

// MARK: - Usage models

struct UsageSnapshotModel: Codable {
    let generatedAt: String
    let providers: [UsageProviderModel]
}

struct UsageProviderCreditModel: Codable, Hashable {
    let label: String
    let balance: Double
    let limit: Double?
    let unit: String
}

struct UsageWindowModel: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetAt: String?
    let detail: String
}

struct UsageProviderModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let plan: String?
    let summary: String
    let source: String?
    let windows: [UsageWindowModel]
    let credits: UsageProviderCreditModel?
    let error: String?
    let lastCheckedAt: String

    var statusColor: String {
        switch status {
        case "ok": return "green"
        case "warning": return "orange"
        case "needs_login": return "red"
        default: return "gray"
        }
    }
}

// MARK: - Replay models

struct ReplaySourceModel: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let label: String
    let root: String
    let available: Bool
}

struct ReplaySessionModel: Codable, Identifiable, Hashable {
    let id: String
    let source: String
    let path: String
    let title: String
    let format: String
    let turnCount: Int
    let modifiedAt: String
    let sizeBytes: Int
}

struct ReplayRenderModel: Codable, Hashable {
    let sessionId: String
    let title: String
    let inputPath: String
    let outputPath: String
    let outputUrl: String
    let turnCount: Int
}

// MARK: - Model fit

struct ModelFitSystemModel: Codable, Hashable {
    let availableRamGb: Double?
    let totalRamGb: Double?
    let cpuCores: Int?
    let cpuName: String?
    let hasGpu: Bool?
    let gpuName: String?
    let gpuVramGb: Double?
    let backend: String?
    let unifiedMemory: Bool?
}

struct ModelFitRecommendationModel: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let shortName: String
    let provider: String
    let category: String
    let useCase: String
    let fitLevel: String
    let score: Double
    let estimatedTps: Double
    let memoryRequiredGb: Double
    let memoryAvailableGb: Double
    let runtime: String
    let runtimeLabel: String
    let bestQuant: String
    let contextLength: Int
    let notes: [String]
    let lmStudioQuery: String
}

struct ModelFitSnapshotModel: Codable, Hashable {
    let available: Bool
    let binaryPath: String?
    let system: ModelFitSystemModel?
    let recommendations: [ModelFitRecommendationModel]
    let error: String?
}

struct ModelFitSystemSnapshotModel: Codable, Hashable {
    let available: Bool
    let binaryPath: String?
    let system: ModelFitSystemModel?
    let error: String?
}

// MARK: - Free models

struct FreeModelEntryModel: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    let tier: String
    let sweScore: String
    let context: String
}

struct FreeModelProviderModel: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let name: String
    let signupUrl: String
    let modelCount: Int
    let tiers: [String]
    let models: [FreeModelEntryModel]
}

struct FreeModelsCatalogModel: Codable, Hashable {
    let providers: [FreeModelProviderModel]
    let totalProviders: Int
    let totalModels: Int
}

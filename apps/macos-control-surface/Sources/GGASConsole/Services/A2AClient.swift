// A2AClient.swift — REST client for the harness control-plane.
// Endpoints match the headless control-plane server.

import Foundation

@MainActor
final class A2AClient: ObservableObject {

    static let shared = A2AClient()

    private var base: String { ProjectSettings.shared.controlPlaneAPIBaseURL }
    private var controlPlaneBase: String { ProjectSettings.shared.normalizedControlPlaneBaseURL }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 5
        cfg.timeoutIntervalForResource = 5
        return URLSession(configuration: cfg)
    }()

    // MARK: - Bus Runs (message-bus native — primary data source for SwarmView)

    func apiURL(_ path: String) -> URL? {
        URL(string: base + path)
    }

    /// GET /api/bus → list of all message-bus runs
    func fetchBusRuns() async throws -> [BusRunInfo] {
        let r: BusRunList = try await get("/bus")
        return r.runs
    }

    /// GET /api/bus/:runId/status → worker heartbeats + active file locks
    func fetchBusStatus(runId: String) async throws -> BusRunStatus {
        try await get("/bus/\(runId)/status")
    }

    // MARK: - Sprint 7: Peer escalation events (for SwarmView orange arrows)

    struct EscalationJSON: Decodable {
        let id: String
        let runId: String
        let fromDomain: String
        let targetDomain: String
        let finding: String
        let severity: String
        let timestamp: String
    }

    /// GET /api/escalations?since=ISO8601 — returns recent peer escalation events for the arrows overlay.
    func fetchEscalations(since: Date = Date(timeIntervalSinceNow: -30)) async throws -> [EscalationJSON] {
        struct Resp: Decodable { let escalations: [EscalationJSON] }
        let iso = ISO8601DateFormatter()
        let sinceStr = iso.string(from: since).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let r: Resp = try await get("/escalations?since=\(sinceStr)&limit=50")
        return r.escalations
    }

    // MARK: - Comm link extraction from SSE bus stream

    /// Fetch comm-link pairs by reading the SSE bus stream.
    /// Detects intent-to-communicate by looking for payload.toId on ANY message type
    /// (Kimi uses HEARTBEAT/ESCALATE/PROGRESS with toId instead of AGENT_MSG).
    func fetchBusMessages(runId: String) async throws -> [(from: String, to: String)] {
        guard let url = apiURL("/bus/\(runId)/stream") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        let (data, _) = try await session.data(for: req)
        let body = String(data: data, encoding: .utf8) ?? ""
        var results: [(from: String, to: String)] = []
        for line in body.components(separatedBy: "\n") {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard let d = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let msg = obj["message"] as? [String: Any],
                  let fromId = msg["agentId"] as? String,
                  let payload = msg["payload"] as? [String: Any],
                  let toId = payload["toId"] as? String,
                  !toId.isEmpty
            else { continue }
            // Accept any message type that carries a toId — AGENT_MSG, HEARTBEAT, ESCALATE, PROGRESS
            results.append((from: fromId, to: toId))
        }
        return results
    }

    // MARK: - Runs (RunStore — dispatch history)


    /// GET /api/runs → { runs: [AgentRun] }  (RunStore dispatch history, NOT bus runs)
    func fetchRuns() async throws -> [AgentRun] {
        struct Response: Codable { let runs: [AgentRun] }
        let r: Response = try await get("/runs")
        return r.runs
    }

    /// DELETE /api/task/:id
    func cancelRun(_ runId: String) async throws {
        try await deleteRequest("/task/\(runId)")
    }

    // MARK: - Logs (per-run embedded in task status)

    /// GET /api/task/:id → { runId, status, …, log: [String] }
    /// Returns the inline log strings for a given run.
    func fetchRunLog(runId: String) async throws -> [String] {
        struct Response: Codable { let log: [String]? }
        let r: Response = try await get("/task/\(runId)")
        return r.log ?? []
    }

    /// Convenience: poll tasks list and derive simple LogLine array from their log strings.
    func fetchLogs(runId: String? = nil, limit: Int = 200) async throws -> [LogLine] {
        if let rid = runId {
            let strings = try await fetchRunLog(runId: rid)
            return strings.prefix(limit).enumerated().map { i, s in
                LogLine(id: "\(rid)-\(i)", ts: "", level: "info", msg: s, runId: rid)
            }
        }
        // Without a runId: inspect the most recent live or recently completed run.
        // The control-plane can keep workers active across multiple sessions, so
        // picking the newest active run avoids mixing historical logs into the live view.
        let runs = try await fetchRuns()
            .sorted { ($0.updatedAt ?? $0.startedAt) > ($1.updatedAt ?? $1.startedAt) }
        guard let activeRun = runs.first(where: { $0.status == .running || $0.status == .accepted || $0.status == .complete }) ?? runs.first else {
            return []
        }
        let logStrings = (try? await fetchRunLog(runId: activeRun.runId)) ?? []
        return logStrings.prefix(limit).enumerated().map { i, s in
            LogLine(id: "\(activeRun.runId)-\(i)", ts: activeRun.startedAt, level: "info", msg: s, runId: activeRun.runId)
        }
    }

    func streamLogs(runId: String? = nil, handler: @escaping ([LogLine]) -> Void) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                if let lines = try? await fetchLogs(runId: runId) {
                    handler(lines)
                    // Feed swarm-signal lines into the dot-matrix model
                    let swarmKeywords = ["SPAWN_MANAGER", "SPAWN_WORKER", "AGENT_DONE",
                                        "AGENT_FAILED", "HANDOFF_READY", "SPAWN_COORDINATOR",
                                        "AGENT_MSG", "WORKTREE_PATH"]
                    let swarmLines = lines.filter { line in
                        swarmKeywords.contains(where: { line.msg.contains($0) })
                    }
                    if !swarmLines.isEmpty {
                        await MainActor.run {
                            for line in swarmLines {
                                AgentSwarmModel.shared.ingest(line: line.msg)
                            }
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    // MARK: - Skills

    /// GET /api/skill-stats → { stats: [SkillStats], … }
    func fetchSkillStats() async throws -> [SkillStats] {
        struct Response: Codable {
            let stats: [SkillStats]?   // actual server key
            let skills: [SkillStats]?  // fallback if key changes
        }
        let r: Response = try await get("/skill-stats")
        return r.stats ?? r.skills ?? []
    }

    // MARK: - Planner

    func fetchPlannerSnapshot() async throws -> PlannerSnapshotModel {
        try await get("/planner")
    }

    func fetchPlannerTasks(status: String? = nil) async throws -> [PlannerTask] {
        var path = "/planner/tasks"
        if let status, !status.isEmpty {
            path += "?status=\(status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? status)"
        }
        struct Response: Codable { let tasks: [PlannerTask] }
        let response: Response = try await get(path)
        return response.tasks
    }

    func createPlannerTask(
        title: String,
        description: String? = nil,
        status: String = "todo",
        priority: Int = 0,
        labels: [String] = [],
        runId: String? = nil,
        runtime: String? = nil
    ) async throws -> PlannerTask {
        struct Body: Codable {
            let title: String
            let description: String?
            let status: String
            let priority: Int
            let labels: [String]
            let runId: String?
            let runtime: String?
            let source: String
        }
        struct Response: Codable { let task: PlannerTask }
        let response: Response = try await post(
            "/planner/tasks",
            body: Body(
                title: title,
                description: description,
                status: status,
                priority: priority,
                labels: labels,
                runId: runId,
                runtime: runtime,
                source: "planner-ui"
            )
        )
        return response.task
    }

    func updatePlannerTask(_ task: PlannerTask) async throws -> PlannerTask {
        struct Body: Codable {
            let title: String
            let description: String?
            let status: String
            let priority: Int
            let labels: [String]
            let attachments: [String]
            let isGlobal: Bool
            let runId: String?
            let runtime: String?
            let linkedRunStatus: String?
            let assignedAgentId: String?
            let worktreePath: String?
            let source: String
        }
        struct Response: Codable { let task: PlannerTask }
        let response: Response = try await patch(
            "/planner/tasks/\(task.id)",
            body: Body(
                title: task.title,
                description: task.description,
                status: task.status,
                priority: task.priority,
                labels: task.labels,
                attachments: task.attachments,
                isGlobal: task.isGlobal,
                runId: task.runId,
                runtime: task.runtime,
                linkedRunStatus: task.linkedRunStatus,
                assignedAgentId: task.assignedAgentId,
                worktreePath: task.worktreePath,
                source: task.source
            )
        )
        return response.task
    }

    func deletePlannerTask(taskId: String) async throws {
        try await deleteRequest("/planner/tasks/\(taskId)")
    }

    func fetchPlannerNotes(taskId: String? = nil) async throws -> [PlannerNote] {
        var path = "/planner/notes"
        if let taskId, !taskId.isEmpty {
            path += "?taskId=\(taskId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? taskId)"
        }
        struct Response: Codable { let notes: [PlannerNote] }
        let response: Response = try await get(path)
        return response.notes
    }

    func createPlannerNote(
        title: String? = nil,
        content: String,
        pinned: Bool = false,
        taskId: String? = nil
    ) async throws -> PlannerNote {
        struct Body: Codable {
            let title: String?
            let content: String
            let pinned: Bool
            let taskId: String?
            let source: String
        }
        struct Response: Codable { let note: PlannerNote }
        let response: Response = try await post(
            "/planner/notes",
            body: Body(title: title, content: content, pinned: pinned, taskId: taskId, source: "planner-ui")
        )
        return response.note
    }

    func updatePlannerNote(_ note: PlannerNote) async throws -> PlannerNote {
        struct Body: Codable {
            let title: String
            let content: String
            let pinned: Bool
            let taskId: String?
            let projectId: String?
            let source: String
        }
        struct Response: Codable { let note: PlannerNote }
        let response: Response = try await patch(
            "/planner/notes/\(note.id)",
            body: Body(
                title: note.title,
                content: note.content,
                pinned: note.pinned,
                taskId: note.taskId,
                projectId: note.projectId,
                source: note.source
            )
        )
        return response.note
    }

    func deletePlannerNote(noteId: String) async throws {
        try await deleteRequest("/planner/notes/\(noteId)")
    }

    // MARK: - Usage

    func fetchUsageSnapshot() async throws -> UsageSnapshotModel {
        try await get("/usage")
    }

    // MARK: - Integrations (LiteLLM / Observability / Quality / MCP catalog)

    func fetchIntegrationSettings() async throws -> IntegrationSettingsModel {
        try await get("/integrations/settings")
    }

    func saveIntegrationSettings(_ settings: IntegrationSettingsModel) async throws -> IntegrationSettingsModel {
        try await put("/integrations/settings", body: settings)
    }

    func fetchMcpCatalog() async throws -> MCPServerCatalogResponse {
        try await get("/integrations/mcp/catalog")
    }

    func applyMcpCatalog(serverIds: [String]) async throws -> MCPApplyResponse {
        struct ApplyRequest: Codable { let serverIds: [String] }
        return try await post("/integrations/mcp/apply", body: ApplyRequest(serverIds: serverIds))
    }

    func startQualityJob(tools: [String], profile: String) async throws -> QualityJobModel {
        struct RunRequest: Codable {
            let tools: [String]
            let profile: String
        }
        return try await post("/integrations/quality/run", body: RunRequest(tools: tools, profile: profile))
    }

    func fetchQualityJob(_ id: String) async throws -> QualityJobModel {
        try await get("/integrations/quality/jobs/\(id)")
    }

    func fetchQualityJobs() async throws -> [QualityJobModel] {
        struct Response: Codable { let jobs: [QualityJobModel] }
        let r: Response = try await get("/integrations/quality/jobs")
        return r.jobs
    }

    // MARK: - Worker steering

    func sendWorkerGuidance(runId: String, agentId: String, message: String) async throws {
        struct Body: Codable { let message: String }
        _ = try await post("/workers/\(runId)/\(agentId)/message", body: Body(message: message)) as WorkerActionResponse
    }

    func retryWorker(runId: String, agentId: String, dryRun: Bool = false) async throws {
        struct Body: Codable { let dryRun: Bool }
        _ = try await post("/workers/\(runId)/\(agentId)/retry", body: Body(dryRun: dryRun)) as WorkerActionResponse
    }

    func retaskWorker(runId: String, agentId: String, taskSummary: String, dryRun: Bool = false) async throws {
        struct Body: Codable {
            let taskSummary: String
            let dryRun: Bool
        }
        _ = try await post("/workers/\(runId)/\(agentId)/retask", body: Body(taskSummary: taskSummary, dryRun: dryRun)) as WorkerActionResponse
    }

    func terminateWorker(runId: String, agentId: String, reason: String? = nil) async throws {
        struct Body: Codable { let reason: String? }
        _ = try await post("/workers/\(runId)/\(agentId)/terminate", body: Body(reason: reason)) as WorkerActionResponse
    }

    func fetchGovernorStatus() async throws -> GovernorStatus {
        try await get("/governor/status")
    }

    func fetchControlPlaneMeta() async throws -> ControlPlaneMeta {
        try await get("/meta")
    }

    func probeControlPlaneCompatibility() async -> ControlPlaneCompatibility {
        guard await ping() else {
            return ControlPlaneCompatibility(
                reachable: false,
                compatible: false,
                meta: nil,
                message: "Harness control-plane is unreachable."
            )
        }

        do {
            let meta = try await fetchControlPlaneMeta()
            if meta.protocolVersion != ControlPlaneMeta.expectedProtocolVersion {
                return ControlPlaneCompatibility(
                    reachable: true,
                    compatible: false,
                    meta: meta,
                    message: "Control-plane protocol mismatch. Expected v\(ControlPlaneMeta.expectedProtocolVersion), got v\(meta.protocolVersion). Restart the harness services."
                )
            }

            let missing = ControlPlaneMeta.requiredCapabilities.subtracting(meta.capabilitySet)
            if !missing.isEmpty {
                return ControlPlaneCompatibility(
                    reachable: true,
                    compatible: false,
                    meta: meta,
                    message: "Control-plane is missing required capabilities: \(missing.sorted().joined(separator: ", ")). Restart the harness services."
                )
            }

            return ControlPlaneCompatibility(
                reachable: true,
                compatible: true,
                meta: meta,
                message: nil
            )
        } catch {
            return ControlPlaneCompatibility(
                reachable: true,
                compatible: false,
                meta: nil,
                message: "Control-plane metadata is unavailable. A stale server may still be running; restart the harness services."
            )
        }
    }

    // MARK: - Dispatch

    /// POST /api/task → { runId, status, mode, stream, poll }
    func dispatch(
        task: String,
        mode: String = "auto",
        source: String = "console",
        coordinator: String? = nil,
        model: String? = nil,
        coordinatorProvider: String? = nil,
        coordinatorModel: String? = nil,
        workerBackend: String? = nil,
        workerModel: String? = nil,
        dispatchPath: String? = nil,
        bridgeContext: String? = nil,
        bridgeWorktree: String? = nil,
        bridgeAgents: Int? = nil,
        bridgeStrategy: String? = nil,
        bridgeRoles: [String]? = nil,
        bridgeTimeoutSeconds: Int? = nil
    ) async throws -> AgentRun {
        // Convert "auto" to a valid server mode value
        let normalized = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let serverMode: String
        switch normalized {
        case "go", "execute":
            serverMode = "go"
        case "minion", "auto", "plan", "review":
            serverMode = "minion"
        default:
            serverMode = "minion"
        }
        let r: DispatchResponse = try await post(
            "/task",
            body: DispatchRequest(
                task: task,
                mode: serverMode,
                source: source,
                coordinator: coordinator,
                model: model,
                coordinatorProvider: coordinatorProvider,
                coordinatorModel: coordinatorModel,
                workerBackend: workerBackend,
                workerModel: workerModel,
                dispatchPath: dispatchPath,
                bridgeContext: bridgeContext,
                bridgeWorktree: bridgeWorktree,
                bridgeAgents: bridgeAgents,
                bridgeStrategy: bridgeStrategy,
                bridgeRoles: bridgeRoles,
                bridgeTimeoutSeconds: bridgeTimeoutSeconds
            )
        )
        // Build an AgentRun from the flat dispatch response
        return AgentRun(
            runId:       r.runId,
            task:        task,
            mode:        r.mode,
            source:      source,
            coordinator: r.coordinator ?? coordinator,
            model: r.model ?? model,
            coordinatorProvider: r.coordinatorProvider ?? coordinatorProvider,
            coordinatorModel: r.coordinatorModel ?? coordinatorModel,
            workerBackend: r.workerBackend ?? workerBackend,
            workerModel: r.workerModel ?? workerModel,
            dispatchPath: r.dispatchPath ?? dispatchPath,
            status:      .accepted,
            prUrl:       nil,
            startedAt:   ISO8601DateFormatter().string(from: Date()),
            completedAt: nil,
            durationMs:  nil
        )
    }

    // MARK: - Trace (derived from run log — server has no dedicated trace endpoint)

    /// GET /api/task/:id → { runId, status, log: [String], … }
    /// Parses log lines into structured TraceEntry objects.
    func fetchTrace(runId: String) async throws -> [TraceEntry] {
        struct RunDetail: Decodable {
            let runId: String
            let log: [String]?
            let sessionId: String?
            let startedAt: String
        }
        let detail: RunDetail = try await get("/task/\(runId)")
        let lines = detail.log ?? []
        let sessionId = detail.sessionId ?? "unknown"
        return lines.enumerated().map { i, line in
            TraceEntry.parse(line: line,
                             index: i,
                             runId: runId,
                             sessionId: sessionId,
                             startedAt: detail.startedAt)
        }
    }

    // MARK: - Health

    func ping() async -> Bool {
        guard let url = URL(string: "\(controlPlaneBase)/health") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        guard let (_, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse else {
            return false
        }
        return (200..<300).contains(http.statusCode)
    }

    /// GET /api/status — binary + pool health
    func fetchStatus() async throws -> AgentStatus {
        try await get("/status")
    }

    // MARK: - Task 9: RunEvent SSE stream (Live push from server)

    /// Subscribe to the server's /api/events SSE stream.
    /// Yields RunEventMessage values as the server pushes them.
    /// Reconnects automatically every 3 s on transient failures.
    func subscribeRunEvents() -> AsyncStream<RunEventMessage> {
        AsyncStream { continuation in
            Task {
                while !Task.isCancelled {
                    guard let url = apiURL("/events") else { break }
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 0   // no timeout — long-lived SSE connection
                    do {
                        let (bytes, _) = try await URLSession.shared.bytes(for: req)
                        var buffer = ""
                        for try await byte in bytes {
                            guard let ch = String(bytes: [byte], encoding: .utf8) else { continue }
                            buffer += ch
                            if buffer.hasSuffix("\n\n") {
                                for line in buffer.components(separatedBy: "\n") {
                                    guard line.hasPrefix("data: ") else { continue }
                                    let json = String(line.dropFirst(6))
                                    guard let data = json.data(using: .utf8),
                                          let msg = try? JSONDecoder.ggasDecoder.decode(RunEventMessage.self, from: data)
                                    else { continue }
                                    continuation.yield(msg)
                                }
                                buffer = ""
                            }
                        }
                    } catch {
                        // transient failure — wait and reconnect
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = apiURL(path) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder.ggasDecoder.decode(T.self, from: data)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        guard let url = apiURL(path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await session.data(for: req)
        // Surface HTTP error body in the decode error for easier debugging
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw NSError(domain: "A2AClient", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        return try JSONDecoder.ggasDecoder.decode(T.self, from: data)
    }

    private func put<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        guard let url = apiURL(path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw NSError(domain: "A2AClient", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        return try JSONDecoder.ggasDecoder.decode(T.self, from: data)
    }

    private func patch<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        guard let url = apiURL(path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw NSError(domain: "A2AClient", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        return try JSONDecoder.ggasDecoder.decode(T.self, from: data)
    }

    private func deleteRequest(_ path: String) async throws {
        guard let url = apiURL(path) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try await session.data(for: req)
    }

    // MARK: - Flat dispatch response

    private struct DispatchResponse: Decodable {
        let runId: String
        let status: String
        let mode: String
        let coordinator: String?
        let model: String?
        let coordinatorProvider: String?
        let coordinatorModel: String?
        let workerBackend: String?
        let workerModel: String?
        let dispatchPath: String?
        // stream + poll URLs are informational, not decoded
    }
}

extension JSONDecoder {
    static let ggasDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

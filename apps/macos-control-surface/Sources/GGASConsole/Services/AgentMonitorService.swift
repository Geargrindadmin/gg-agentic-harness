// AgentMonitorService.swift — Single-source bus polling for the GGAS macOS app.
// Architecture inspired by exo-explore/exo ClusterStateService.swift (Apache 2.0).
// Pattern: @MainActor ObservableObject, 500ms poll interval, retry-on-error,
// resetTransientState() for coordinator switches. SwarmView and A2AClient delegate
// ALL polling to this service — they are display-only consumers.

import Foundation
import Combine

// MARK: - Service

@MainActor
final class AgentMonitorService: ObservableObject {

    static let shared = AgentMonitorService()

    // MARK: Published state (consumed by SwarmView, RunHistoryView, etc.)

    @Published private(set) var busStatuses: [BusRunStatus] = []
    @Published private(set) var commLinks: [(from: String, to: String)] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isConnected: Bool = false

    // MARK: Private

    private var timer: Timer?
    private var seenLinks: [String: Set<String>] = [:]
    private let pollInterval: TimeInterval
    private static let iso = ISO8601DateFormatter()  // cached — ISO8601DateFormatter is expensive to alloc
    private var eventStreamTask: Task<Void, Never>?  // Task 9: live SSE connection

    // Sprint 5 — SQLite WAL watcher (USE_SQLITE_WATCHER=1 to enable)
    private var walWatcher: SQLiteWALWatcher?
    private var walWatcherTask: Task<Void, Never>?

    private init(pollInterval: TimeInterval = 0.5) {
        self.pollInterval = pollInterval
    }

    // MARK: - Lifecycle

    /// Start polling + event stream. Safe to call multiple times — only one loop runs.
    func startPolling() {
        guard timer == nil else { return }

        // Sprint 5: use direct SQLite WAL watcher if enabled; otherwise fall back to HTTP timer
        if CheckpointStore.isEnabled {
            startSQLiteWatcher()
        } else {
            Task { await fetchSnapshot() }
            timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
                Task { await self?.fetchSnapshot() }
            }
        }
        startEventStream()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        eventStreamTask?.cancel()
        eventStreamTask = nil
        walWatcherTask?.cancel()
        walWatcherTask = nil
        walWatcher?.stop()
        walWatcher = nil
        CheckpointStore.shared.close()
    }

    /// Task 9: Subscribe to /api/events SSE. Sets isConnected based on stream health.
    private func startEventStream() {
        guard eventStreamTask == nil else { return }
        eventStreamTask = Task {
            var connected = false
            for await event in A2AClient.shared.subscribeRunEvents() {
                if Task.isCancelled { break }
                if !connected {
                    connected = true
                    await MainActor.run { self.isConnected = true; self.lastError = nil }
                }
                // On snapshot, optionally log count (extend here to hydrate RunHistoryView directly)
                if event.type == .snapshot {
                    let count = event.runs?.count ?? 0
                    await MainActor.run {
                        _ = count  // snapshot count available for future RunHistory hydration
                    }
                }
            }
            // Stream ended (server offline or reconnect delay)
            await MainActor.run {
                self.isConnected = false
                self.lastError = "Event stream disconnected — retrying…"
            }
            eventStreamTask = nil
            // Auto-restart: subscribeRunEvents() already reconnects, but the Task
            // itself ended — re-launch it so the outer @Published values update.
            if !Task.isCancelled { startEventStream() }
        }
    }

    /// Called when the active coordinator switches — clears transient swarm state.
    func resetTransientState() {
        busStatuses = []
        commLinks = []
        seenLinks = [:]
        lastError = nil
        isConnected = false
    }

    // MARK: - Sprint 5: SQLite WAL Watcher

    /// Opens CheckpointStore and starts watching the WAL file for changes.
    /// Each WAL write triggers fetchSnapshotFromSQLite() instead of an HTTP poll.
    /// Falls back to HTTP timer if the DB is not found (server not yet started).
    private func startSQLiteWatcher() {
        do {
            try CheckpointStore.shared.open()
        } catch {
            print("[AgentMonitorService] SQLite open failed (\(error.localizedDescription)) — falling back to HTTP poll")
            timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
                Task { await self?.fetchSnapshot() }
            }
            return
        }

        let watcher = SQLiteWALWatcher(dbPath: CheckpointStore.shared.dbPath)
        walWatcher = watcher
        watcher.start()

        walWatcherTask = Task {
            // Immediate snapshot on open
            await fetchSnapshotFromSQLite()

            for await _ in watcher.changes {
                if Task.isCancelled { break }
                await fetchSnapshotFromSQLite()
            }

            // WAL watcher ended (file removed?) — graceful degradation to HTTP
            await MainActor.run {
                self.lastError = "WAL watcher stopped — switching to HTTP poll"
            }
            timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
                Task { await self?.fetchSnapshot() }
            }
        }
    }

    /// Read agent state directly from SQLite instead of HTTP.
    /// Merges worker_status rows into the same BusRunStatus shape that SwarmView already consumes.
    private func fetchSnapshotFromSQLite() async {
        // Collect all known runIds from the bus HTTP endpoint (only run IDs, lightweight)
        guard let runs = try? await A2AClient.shared.fetchBusRuns(), !runs.isEmpty else {
            // No runs known — nothing to display yet
            return
        }

        var statuses: [BusRunStatus] = []
        for info in runs {
            let workers = (try? await CheckpointStore.shared.fetchWorkerStatuses(runId: info.runId)) ?? []
            if workers.isEmpty { continue }
            // Map WorkerStatusRow → BusWorkerState (mirrors HTTP shape)
            var workerMap: [String: BusWorkerState] = [:]
            for w in workers {
                workerMap[w.agentId] = BusWorkerState(
                    status: w.status,
                    progressPct: w.progressPct,
                    lastHeartbeat: w.lastHeartbeat,
                    currentTask: w.currentTask,
                    worktreePath: nil,
                    runtime: nil,
                    role: nil,
                    personaId: nil,
                    launchTransport: nil,
                    executionStatus: nil,
                    lastSummary: nil
                )
            }
            statuses.append(BusRunStatus(
                runId: info.runId,
                totalMessages: 0,
                workers: workerMap,
                activeLocks: [:],
                telemetry: nil
            ))
        }

        busStatuses = statuses
        isConnected = !statuses.isEmpty
        if isConnected { lastError = nil }
    }

    // MARK: - Snapshot fetch

    private func fetchSnapshot() async {
        do {
            let busRuns = try await A2AClient.shared.fetchBusRuns()

            var statuses: [BusRunStatus] = []
            for info in busRuns {
                if let s = try? await A2AClient.shared.fetchBusStatus(runId: info.runId) {
                    statuses.append(s)
                }
            }

            let visible = visibleStatuses(from: statuses)

            // Comm links — incremental: only scan visible runs
            let visibleRunIds = Set(visible.map { $0.runId })
            var newLinks: [(from: String, to: String)] = []
            for run in busRuns where visibleRunIds.contains(run.runId) {
                let links = (try? await A2AClient.shared.fetchBusMessages(runId: run.runId)) ?? []
                newLinks.append(contentsOf: mergeNewLinks(for: run.runId, links: links))
            }
            // Prune seenLinks for runs that are no longer visible (prevents unbounded growth)
            seenLinks = seenLinks.filter { visibleRunIds.contains($0.key) }

            // Fallback: when bus is empty, ingest A2A RunStore logs
            if visible.isEmpty {
                await ingestRunStoreFallback()
            }

            // Publish
            busStatuses = visible
            if !newLinks.isEmpty {
                commLinks.append(contentsOf: newLinks)
                for link in newLinks {
                    AgentSwarmModel.shared.ingestAgentMsg(from: link.from, to: link.to)
                }
            }
            isConnected = true
            lastError = nil

            // Sprint 7: fetch peer escalation events and hydrate SwarmView orange arrows
            if let escs = try? await A2AClient.shared.fetchEscalations() {
                for esc in escs {
                    AgentSwarmModel.shared.ingestPeerEscalation(
                        fromDomain:   esc.fromDomain,
                        targetDomain: esc.targetDomain,
                        finding:      esc.finding,
                        severity:     esc.severity
                    )
                }
            }

        } catch {
            isConnected = false
            lastError = error.localizedDescription
        }
    }

    func visibleStatuses(from statuses: [BusRunStatus], now: Date = Date()) -> [BusRunStatus] {
        let cut30 = now.addingTimeInterval(-30 * 60)
        let cut2 = now.addingTimeInterval(-2 * 60)

        return statuses.filter { status in
            let workers = status.workers.values
            guard !workers.isEmpty else { return false }
            let heartbeats = workers.compactMap { Self.iso.date(from: $0.lastHeartbeat) }
            guard heartbeats.contains(where: { $0 > cut30 }) else { return false }

            let allDone = workers.allSatisfy { $0.status == "complete" || $0.status == "failed" }
            if allDone, let latestBeat = heartbeats.max(), latestBeat < cut2 {
                return false
            }
            return true
        }
    }

    func mergeNewLinks(for runId: String, links: [(from: String, to: String)]) -> [(from: String, to: String)] {
        var seen = seenLinks[runId] ?? []
        var newLinks: [(from: String, to: String)] = []

        for link in links {
            let key = "\(link.from)→\(link.to)"
            if seen.insert(key).inserted {
                newLinks.append(link)
            }
        }

        seenLinks[runId] = seen
        return newLinks
    }

    // MARK: - RunStore fallback (for older-style swarms not using message bus)

    private func ingestRunStoreFallback() async {
        guard let runs = try? await A2AClient.shared.fetchRuns() else { return }
        let swarmRuns = runs.filter { r in
            let src = r.source.lowercased()
            return src.contains("kimi") || src.contains("swarm") || r.mode == "swarm"
        }

        // Collect all swarm lines, reset model, then ingest
        var allLines: [String] = []
        for run in swarmRuns.prefix(5) {
            let log = (try? await A2AClient.shared.fetchRunLog(runId: run.runId)) ?? []
            allLines.append(contentsOf: log)
        }

        if !allLines.isEmpty {
            await MainActor.run {
                AgentSwarmModel.shared.reset()
                for line in allLines { AgentSwarmModel.shared.ingest(line: line) }
            }
        }
    }
}

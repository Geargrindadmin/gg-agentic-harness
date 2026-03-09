// CheckpointStore.swift — GRDB.swift DatabasePool for ZMQ checkpoint/escalation reads
// Sprint 5, T41–T43 / T71–T72
//
// Reads directly from the local SQLite checkpoint store used by the harness monitor.
// All reads are concurrent-safe via DatabasePool. Never writes to the DB — only the
// Node.js server process owns writes.
//
// Feature gated by USE_SQLITE_WATCHER (env var, default OFF).
// AgentMonitorService falls back to HTTP polling if pool initialization fails.

import Foundation
import GRDB

// MARK: - Row models (mirrors TypeScript schema in BusDatabase.ts)

struct CheckpointRow: FetchableRecord, Codable {
    let id: String
    let runId: String
    let agentId: String
    let domain: String
    let depth: Int
    let parentId: String?
    let phase: String
    let stepNumber: Int
    let stateJson: String
    let createdAt: String

    // Parse stateJson into a typed dictionary lazily
    var state: [String: String] {
        guard let data = stateJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return dict
    }
}

struct EscalationRow: FetchableRecord, Codable {
    let id: String
    let runId: String
    let fromAgent: String
    let fromDomain: String
    let targetDomain: String
    let finding: String
    let severity: String
    let createdAt: String
}

struct WorkerStatusRow: FetchableRecord, Codable {
    let runId: String
    let agentId: String
    let status: String
    let progressPct: Int
    let currentTask: String
    let domain: String
    let depth: Int
    let parentId: String?
    let lastHeartbeat: String
}

// MARK: - CheckpointStore

final class CheckpointStore {

    static let shared = CheckpointStore()

    /// Set to true to enable SQLite WAL watcher instead of HTTP polling
    static let isEnabled: Bool = ProcessInfo.processInfo.environment["USE_SQLITE_WATCHER"] == "1"

    private var pool: DatabasePool?
    let dbPath: String

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        dbPath = ProcessInfo.processInfo.environment["BUS_DB_PATH"]
            ?? (home + "/.ggas/bus/bus.db")
    }

    // MARK: - Lifecycle

    /// Open the DatabasePool. Safe to call multiple times — no-op if already open.
    func open() throws {
        guard pool == nil else { return }
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw CheckpointStoreError.dbNotFound(dbPath)
        }
        var config = Configuration()
        config.readonly = true           // We never write — the Node.js server owns writes
        config.maximumReaderCount = 4   // Allow concurrent SwiftUI readers
        pool = try DatabasePool(path: dbPath, configuration: config)
    }

    func close() {
        pool = nil
    }

    // MARK: - Checkpoint Queries

    /// All checkpoints for a specific run, ordered by step ascending
    func fetchCheckpoints(runId: String, limit: Int = 200) async throws -> [CheckpointRow] {
        guard let pool else { return [] }
        return try await pool.read { db in
            try CheckpointRow
                .fetchAll(db, sql: """
                    SELECT id, runId, agentId, domain, depth, parentId,
                           phase, stepNumber, stateJson, createdAt
                    FROM checkpoints
                    WHERE runId = ?
                    ORDER BY stepNumber ASC
                    LIMIT ?
                    """, arguments: [runId, limit])
        }
    }

    /// Latest checkpoint per agentId for a run — used for SwarmView status display
    func fetchLatestCheckpointsPerAgent(runId: String) async throws -> [CheckpointRow] {
        guard let pool else { return [] }
        return try await pool.read { db in
            try CheckpointRow
                .fetchAll(db, sql: """
                    SELECT c.id, c.runId, c.agentId, c.domain, c.depth, c.parentId,
                           c.phase, c.stepNumber, c.stateJson, c.createdAt
                    FROM checkpoints c
                    INNER JOIN (
                        SELECT agentId, MAX(stepNumber) AS maxStep
                        FROM checkpoints
                        WHERE runId = ?
                        GROUP BY agentId
                    ) latest ON c.agentId = latest.agentId AND c.stepNumber = latest.maxStep
                    WHERE c.runId = ?
                    """, arguments: [runId, runId])
        }
    }

    // MARK: - Escalation Queries

    func fetchEscalations(runId: String) async throws -> [EscalationRow] {
        guard let pool else { return [] }
        return try await pool.read { db in
            try EscalationRow
                .fetchAll(db, sql: """
                    SELECT id, runId, fromAgent, fromDomain, targetDomain,
                           finding, severity, createdAt
                    FROM escalations
                    WHERE runId = ?
                    ORDER BY createdAt ASC
                    """, arguments: [runId])
        }
    }

    // MARK: - Worker Status Queries (mirrors BusDatabase.ts worker_status table)

    func fetchWorkerStatuses(runId: String) async throws -> [WorkerStatusRow] {
        guard let pool else { return [] }
        return try await pool.read { db in
            try WorkerStatusRow
                .fetchAll(db, sql: """
                    SELECT runId, agentId, status, progress_pct AS progressPct,
                           currentTask, domain, depth, parentId, lastHeartbeat
                    FROM worker_status
                    WHERE runId = ?
                    """, arguments: [runId])
        }
    }

    // MARK: - Resume point (crash recovery aid — mirrors CheckpointStore.ts getResumePoint)

    func fetchResumePoint(runId: String, agentId: String) async throws -> CheckpointRow? {
        guard let pool else { return nil }
        return try await pool.read { db in
            try CheckpointRow
                .fetchOne(db, sql: """
                    SELECT id, runId, agentId, domain, depth, parentId,
                           phase, stepNumber, stateJson, createdAt
                    FROM checkpoints
                    WHERE runId = ? AND agentId = ?
                    ORDER BY stepNumber DESC
                    LIMIT 1
                    """, arguments: [runId, agentId])
        }
    }
}

// MARK: - WAL Watcher

/// Watches the SQLite WAL file for changes and notifies via async stream.
/// Used by AgentMonitorService when USE_SQLITE_WATCHER=1.
final class SQLiteWALWatcher {

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private let walPath: String
    private let debounceMs: Int

    private let continuation: AsyncStream<Void>.Continuation

    let changes: AsyncStream<Void>

    init(dbPath: String, debounceMs: Int = 100) {
        self.walPath = dbPath + "-wal"
        self.debounceMs = debounceMs

        var cont: AsyncStream<Void>.Continuation!
        self.changes = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func start() {
        fd = open(walPath, O_EVTONLY)
        guard fd >= 0 else {
            print("[SQLiteWALWatcher] Could not open \(walPath) — falling back to HTTP poll")
            continuation.finish()
            return
        }

        var lastFired = DispatchTime.now()
        let debounceNs = Int64(debounceMs) * 1_000_000

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: .global(qos: .background)
        )

        source?.setEventHandler { [weak self] in
            guard let self else { return }
            let now = DispatchTime.now()
            let elapsed = now.uptimeNanoseconds - lastFired.uptimeNanoseconds
            guard elapsed > UInt64(debounceNs) else { return }
            lastFired = now
            self.continuation.yield()
        }

        source?.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
            self.continuation.finish()
        }

        source?.resume()
        print("[SQLiteWALWatcher] Watching \(walPath) (debounce \(debounceMs)ms)")
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}

// MARK: - Errors

enum CheckpointStoreError: LocalizedError {
    case dbNotFound(String)

    var errorDescription: String? {
        switch self {
        case .dbNotFound(let path): return "Bus database not found at: \(path)"
        }
    }
}

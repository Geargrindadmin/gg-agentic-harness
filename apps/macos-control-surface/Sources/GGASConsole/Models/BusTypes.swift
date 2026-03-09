// BusTypes.swift — Codable models for the harness control-plane message-bus REST API.
// Endpoints: GET /api/bus  •  GET /api/bus/:runId/status  •  GET /api/bus/:runId/stream (SSE)
//
// Phase 3 (exo TaggedModel pattern): BusPayload is now a tagged union enum decoded via
// `type` discriminator. Migration shim keeps existing `.toId`, `.message` accesses working.
//
// Phase 5 (exo bus topic separation): BusTopic logically partitions messages into channels.
// Writes route to `.commands`. Agent-local events go to `.localEvents`. Coordinator-visible
// state (heartbeats, task outcomes) go to `.globalEvents`. Topology votes use `.election`.
// Handshakes use `.connection`.

import Foundation

// MARK: - Phase 5: Bus Topic Separation (exo pattern)

/// Logical channel a message belongs to.
/// Derived from `BusMessage.type` — no extra wire bytes needed.
enum BusTopic: String, Hashable, CaseIterable {
    /// Outbound commands from coordinator → agents (DISPATCH, RETRY, CANCEL)
    case commands
    /// Agent-private events (FILE_LOCK, FILE_UNLOCK, BLOCKED, UNBLOCKED — self only)
    case localEvents
    /// Coordinator-visible state: HEARTBEAT, TASK_START, TASK_COMPLETE, TASK_FAILED, PROGRESS, ESCALATE
    case globalEvents
    /// Coordinator-election signals (not yet emitted by the control-plane; reserved for Phase 6)
    case election
    /// Handshake / session-open messages (CONNECTED)
    case connection
    /// Sprint 7: ZMQ PUB/SUB peer escalation arrows between worker domains
    case peerEscalation

    /// Derive topic from a raw `BusMessage.type` string.
    static func from(messageType: String) -> BusTopic {
        switch messageType.uppercased() {
        case "HEARTBEAT", "TASK_START", "TASK_COMPLETE", "TASK_FAILED",
             "PROGRESS", "ESCALATE", "ESCALATE_RESOLVED":
            return .globalEvents
        case "FILE_LOCK", "FILE_UNLOCK", "BLOCKED", "UNBLOCKED":
            return .localEvents
        case "DISPATCH", "RETRY_AGENT", "CANCEL":
            return .commands
        case "AGENT_MSG":
            return .globalEvents     // comm-line messages are globally visible
        case "PEER_ESCALATION":
            return .peerEscalation
        case "CONNECTED":
            return .connection
        default:
            return .globalEvents     // safe default: surface unknown types to coordinator
        }
    }

    var displayName: String {
        switch self {
        case .commands:         return "Commands"
        case .localEvents:      return "Local Events"
        case .globalEvents:     return "Global Events"
        case .election:         return "Election"
        case .connection:       return "Connection"
        case .peerEscalation:   return "Peer Escalation"
        }
    }
}

extension BusMessage {
    /// Computed topic for this message — no decoding overhead.
    var topic: BusTopic { BusTopic.from(messageType: type) }
}



// MARK: - /api/bus → { runs: [BusRunInfo] }

struct BusRunList: Codable {
    let runs: [BusRunInfo]
}

struct BusRunInfo: Codable {
    let runId: String
    let agents: Int
    let startedAt: String?
}

// MARK: - /api/bus/:runId/status → BusRunStatus

struct BusRunStatus: Codable {
    let runId: String
    let totalMessages: Int
    let workers: [String: BusWorkerState]   // agentId → state
    let activeLocks: [String: String]        // filepath → agentId
}

struct BusWorkerState: Codable {
    let status: String          // "running" | "complete" | "failed"
    let progressPct: Int
    let lastHeartbeat: String
    let currentTask: String?
    let worktreePath: String?   // optional — reported when agent sets its working directory
}

// MARK: - Bus SSE message (event: bus_message) → BusMessage

struct BusSSEEvent: Codable {
    let event: String           // "bus_message" | "connected"
    let message: BusMessage?
    let runId: String?
}

struct BusMessage: Codable {
    let id: String
    let type: String            // HEARTBEAT | TASK_START | TASK_COMPLETE | TASK_FAILED |
                                // ESCALATE | AGENT_MSG | FILE_LOCK | FILE_UNLOCK | PROGRESS
    let agentId: String
    let runId: String
    let timestamp: String
    let payload: BusPayload
}

// MARK: - Tagged union payload (exo TaggedModel pattern)
//
// The server sends different payload shapes for each `type`.
// Decoding precedence: try each case by field presence.
// All raw JSON fields are kept in `rawFields` for forward-compatibility.

enum BusPayload: Codable {

    // AGENT_MSG / routed messages
    case agentMessage(toId: String, message: String)

    // PROGRESS
    case progress(progressPct: Int, currentTask: String?)

    // TASK_COMPLETE
    case taskComplete(summary: String?)

    // TASK_FAILED
    case taskFailed(reason: String?)

    // ESCALATE
    case escalate(question: String?)

    // FILE_LOCK / FILE_UNLOCK
    case fileLock(filepath: String, agentId: String)
    case fileUnlock(filepath: String)

    // HEARTBEAT / TASK_START / anything else
    case other([String: JSONValue])

    // MARK: Decoding

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)

        if let toId = try? container.decode(String.self, forKey: AnyCodingKey("toId")),
           !toId.isEmpty {
            let msg = (try? container.decode(String.self, forKey: AnyCodingKey("message"))) ?? ""
            self = .agentMessage(toId: toId, message: msg)
            return
        }
        if let pct = try? container.decode(Int.self, forKey: AnyCodingKey("progressPct")) {
            let task = try? container.decode(String.self, forKey: AnyCodingKey("currentTask"))
            self = .progress(progressPct: pct, currentTask: task)
            return
        }
        if let summary = try? container.decode(String.self, forKey: AnyCodingKey("summary")) {
            self = .taskComplete(summary: summary)
            return
        }
        if let reason = try? container.decode(String.self, forKey: AnyCodingKey("reason")) {
            self = .taskFailed(reason: reason)
            return
        }
        if let question = try? container.decode(String.self, forKey: AnyCodingKey("question")) {
            self = .escalate(question: question)
            return
        }
        if let filepath = try? container.decode(String.self, forKey: AnyCodingKey("filepath")) {
            let agent = (try? container.decode(String.self, forKey: AnyCodingKey("agentId"))) ?? ""
            self = agent.isEmpty ? .fileUnlock(filepath: filepath) : .fileLock(filepath: filepath, agentId: agent)
            return
        }
        // Fallback: store raw JSON fields for forward-compatibility
        var raw: [String: JSONValue] = [:]
        for key in container.allKeys {
            raw[key.stringValue] = (try? container.decode(JSONValue.self, forKey: key)) ?? .null
        }
        self = .other(raw)
    }

    // MARK: Encoding

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        switch self {
        case .agentMessage(let toId, let message):
            try container.encode(toId,    forKey: AnyCodingKey("toId"))
            try container.encode(message, forKey: AnyCodingKey("message"))
        case .progress(let pct, let task):
            try container.encode(pct,  forKey: AnyCodingKey("progressPct"))
            try container.encodeIfPresent(task, forKey: AnyCodingKey("currentTask"))
        case .taskComplete(let summary):
            try container.encodeIfPresent(summary, forKey: AnyCodingKey("summary"))
        case .taskFailed(let reason):
            try container.encodeIfPresent(reason, forKey: AnyCodingKey("reason"))
        case .escalate(let question):
            try container.encodeIfPresent(question, forKey: AnyCodingKey("question"))
        case .fileLock(let fp, let agent):
            try container.encode(fp,    forKey: AnyCodingKey("filepath"))
            try container.encode(agent, forKey: AnyCodingKey("agentId"))
        case .fileUnlock(let fp):
            try container.encode(fp, forKey: AnyCodingKey("filepath"))
        case .other(let dict):
            for (k, v) in dict { try container.encode(v, forKey: AnyCodingKey(k)) }
        }
    }

    // MARK: - Migration shim (keeps old property-access call sites working)

    var toId: String? {
        if case .agentMessage(let id, _) = self { return id }
        return nil
    }
    var message: String? {
        if case .agentMessage(_, let m) = self { return m }
        return nil
    }
    var progressPct: Int? {
        if case .progress(let pct, _) = self { return pct }
        return nil
    }
    var currentTask: String? {
        if case .progress(_, let t) = self { return t }
        return nil
    }
    var summary: String? {
        if case .taskComplete(let s) = self { return s }
        return nil
    }
    var reason: String? {
        if case .taskFailed(let r) = self { return r }
        return nil
    }
    var question: String? {
        if case .escalate(let q) = self { return q }
        return nil
    }
}

// MARK: - JSON helpers

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}

/// Recursive JSON value type for forward-compatible payload storage.
indirect enum JSONValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                            { self = .null; return }
        if let b = try? c.decode(Bool.self)         { self = .bool(b); return }
        if let i = try? c.decode(Int.self)          { self = .int(i); return }
        if let d = try? c.decode(Double.self)       { self = .double(d); return }
        if let s = try? c.decode(String.self)       { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self)  { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i):    try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b):   try c.encode(b)
        case .array(let a):  try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null:          try c.encodeNil()
        }
    }
}

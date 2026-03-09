// AgentSwarmModel.swift — Swarm topology state model.

import Foundation
import Combine
import SwiftUI

// MARK: - Status

enum AgentDotStatus {
    case idle, queued, running, done, failed
    var isActive: Bool { self == .running || self == .queued }
}

// MARK: - Node structs

struct WorkerNode: Identifiable {
    let id: String
    var label: String
    var status: AgentDotStatus = .running
    var summary: String = ""
    var worktreePath: String? = nil
    var lastHeartbeat: Date? = nil
}

struct ManagerNode: Identifiable {
    let id: String
    var label: String
    var status: AgentDotStatus = .idle
    var workers: [WorkerNode] = []
    var worktreePath: String? = nil

    var activeWorkerCount: Int { workers.filter(\.status.isActive).count }
    var doneWorkerCount:   Int { workers.filter { $0.status == .done }.count }
}

// MARK: - Communication link (AGENT_MSG)

struct AgentLink: Identifiable {
    let id = UUID()
    let fromId: String   // raw ID from signal (matches worker or manager label)
    let toId: String
    let timestamp: Date
}

// MARK: - Peer escalation (Sprint 7: ZMQ PUB/SUB fan-out)

struct PeerEscalation: Identifiable {
    let id = UUID()
    let fromDomain: String
    let targetDomain: String
    let finding: String
    let severity: String   // "low" | "medium" | "high" | "critical"
    let timestamp: Date

    var severityColor: Color {
        switch severity.lowercased() {
        case "critical": return Color(red: 1.0, green: 0.18, blue: 0.18)
        case "high":     return Color(red: 1.0, green: 0.50, blue: 0.10)
        case "medium":   return Color(red: 1.0, green: 0.80, blue: 0.10)
        default:         return Color(red: 0.60, green: 0.60, blue: 0.70)
        }
    }
}

// MARK: - Swarm Model

@MainActor
final class AgentSwarmModel: ObservableObject {
    static let shared = AgentSwarmModel()

    @Published var managers: [ManagerNode] = []
    @Published var coordinatorStatus: AgentDotStatus = .idle
    @Published var coordinatorLabel: String = "Coordinator"
    @Published var activeLinks: [AgentLink] = []
    @Published var activeEscalations: [PeerEscalation] = []   // Sprint 7: peer PUB/SUB arrows
    @Published var totalRunning = 0
    @Published var totalDone    = 0
    @Published var totalFailed  = 0

    private var managerIndex: [String: Int] = [:]
    private var nextManagerSlot = 0
    private var seenWorkers: Set<String> = []

    private init() {}

    // MARK: - Computed

    var activeManagers: [ManagerNode] { managers.filter { $0.status != .idle } }

    // MARK: - Bus-native status ingestion (replaces keyword log parsing for bus agents)

    /// Call this every poll cycle with the latest bus run status.
    /// Builds/updates coordinator + worker nodes directly from structured bus data.
    func ingestBusStatus(_ statuses: [BusRunStatus]) {
        guard !statuses.isEmpty else { return }

        // Bootstrap coordinator on first call with any data
        if coordinatorStatus == .idle {
            coordinatorStatus = .running
            coordinatorLabel  = "kimi"
        }

        // Process EVERY run (show all manager/worker nodes, not just active ones)
        for latest in statuses {
            guard !latest.workers.isEmpty else { continue }

            let mgId = latest.runId
            if managerIndex[mgId] == nil {
                let slot = managers.count
                managerIndex[mgId] = slot
                managers.append(ManagerNode(id: mgId, label: mgId, status: .running))
            }
            guard let mSlot = managerIndex[mgId] else { continue }

            for (agentId, worker) in latest.workers {
                let dotStatus: AgentDotStatus
                switch worker.status {
                case "queued":   dotStatus = .queued
                case "complete", "handoff_ready", "completed", "terminated": dotStatus = .done
                case "failed":   dotStatus = .failed
                default:         dotStatus = .running
                }
                let heartbeat = ISO8601DateFormatter().date(from: worker.lastHeartbeat)
                let summary = worker.currentTask ?? managers[mSlot].workers.first(where: { $0.id == agentId })?.summary ?? ""
                if let wi = managers[mSlot].workers.firstIndex(where: { $0.id == agentId }) {
                    managers[mSlot].workers[wi].status = dotStatus
                    managers[mSlot].workers[wi].summary = summary
                    managers[mSlot].workers[wi].lastHeartbeat = heartbeat
                    if let wtp = worker.worktreePath { managers[mSlot].workers[wi].worktreePath = wtp }
                } else if !seenWorkers.contains(agentId) {
                    managers[mSlot].workers.append(
                        WorkerNode(
                            id: agentId,
                            label: agentId,
                            status: dotStatus,
                            summary: summary,
                            worktreePath: worker.worktreePath,
                            lastHeartbeat: heartbeat
                        )
                    )
                    seenWorkers.insert(agentId)
                }
            }
            if latest.workers.values.allSatisfy({ ["complete", "handoff_ready", "completed", "terminated"].contains($0.status) }) {
                managers[mSlot].status = .done
            } else if latest.workers.values.contains(where: { $0.status == "queued" }) {
                managers[mSlot].status = .queued
            } else {
                managers[mSlot].status = .running
            }
        }

        // Mark coordinator done once all managers are done
        if !managers.isEmpty, managers.allSatisfy({ $0.status == .done }) {
            coordinatorStatus = .done
        }

        recount()
        objectWillChange.send()   // force SwiftUI refresh
    }

    // MARK: - Log parser

    func ingest(line: String) {
        let line = line.trimmingCharacters(in: .whitespaces)

        if line.contains("SPAWN_COORDINATOR") || line.contains("Swarm Coordinator") {
            reset()
            coordinatorStatus = .running
            if let r = line.range(of: "SPAWN_COORDINATOR:") {
                let name = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { coordinatorLabel = name }
            }

        } else if line.hasPrefix("SPAWN_MANAGER:") {
            let mid = String(line.dropFirst("SPAWN_MANAGER:".count)).trimmingCharacters(in: .whitespaces)
            spawnManager(id: mid)

        } else if line.hasPrefix("SPAWN_WORKER:") {
            let rest = String(line.dropFirst("SPAWN_WORKER:".count)).trimmingCharacters(in: .whitespaces)
            let parts = rest.components(separatedBy: " parent:")
            if parts.count == 2 {
                spawnWorker(id: parts[0].trimmingCharacters(in: .whitespaces),
                            parentId: parts[1].trimmingCharacters(in: .whitespaces))
            }

        } else if line.hasPrefix("AGENT_MSG:") {
            parseAgentMsg(String(line.dropFirst("AGENT_MSG:".count)).trimmingCharacters(in: .whitespaces))

        } else if line.hasPrefix("AGENT_DONE:") {
            let rest = String(line.dropFirst("AGENT_DONE:".count)).trimmingCharacters(in: .whitespaces)
            let parts = rest.components(separatedBy: " — ")
            markDone(id: parts[0].trimmingCharacters(in: .whitespaces),
                     summary: parts.count > 1 ? parts[1] : "")

        } else if line.hasPrefix("AGENT_FAILED:") {
            let rest = String(line.dropFirst("AGENT_FAILED:".count)).trimmingCharacters(in: .whitespaces)
            markFailed(id: rest.components(separatedBy: " — ")[0].trimmingCharacters(in: .whitespaces))

        } else if line.contains("HANDOFF_READY") {
            coordinatorStatus = .done

        } else if line.hasPrefix("WORKTREE_PATH:") {
            let rest = String(line.dropFirst("WORKTREE_PATH:".count)).trimmingCharacters(in: .whitespaces)
            let parts = rest.components(separatedBy: " ")
            if parts.count >= 2 {
                let agentId   = parts[0]
                let treePath  = parts[1...].joined(separator: " ")
                setWorktreePath(agentId: agentId, path: treePath)
            }
        }

        recount()
    }

    /// Called by A2AClient.streamBusStatus() when an AGENT_MSG bus message is detected.
    func ingestAgentMsg(from fromId: String, to toId: String) {
        let link = AgentLink(fromId: fromId, toId: toId, timestamp: Date())
        activeLinks.append(link)
        let linkId = link.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.activeLinks.removeAll { $0.id == linkId }
        }
    }

    // MARK: - Reset

    func reset() {
        managers = []
        coordinatorStatus = .idle
        coordinatorLabel = "Coordinator"
        managerIndex = [:]
        nextManagerSlot = 0
        seenWorkers = []
        activeLinks = []
        activeEscalations = []
        totalRunning = 0; totalDone = 0; totalFailed = 0
    }

    // MARK: - Peer escalation ingestion (Sprint 7)

    /// Call when ZMQ PeerRegistry PUB message arrives for a PEER_ESCALATION event.
    func ingestPeerEscalation(fromDomain: String, targetDomain: String,
                               finding: String, severity: String) {
        let esc = PeerEscalation(fromDomain: fromDomain, targetDomain: targetDomain,
                                 finding: finding, severity: severity, timestamp: Date())
        activeEscalations.append(esc)
        let escId = esc.id
        // Auto-expire after 8 seconds (longer than AGENT_MSG 5s — domain events are slower)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.activeEscalations.removeAll { $0.id == escId }
        }
        objectWillChange.send()
    }


    // MARK: - Mutations

    private func spawnManager(id: String) {
        if let existing = managerIndex[id] {
            managers[existing].status = .running
            return
        }
        let slot = managers.count
        managerIndex[id] = slot
        nextManagerSlot += 1
        managers.append(ManagerNode(id: id, label: id, status: .running))
    }

    private func spawnWorker(id: String, parentId: String) {
        guard !seenWorkers.contains(id) else { return }
        guard let mSlot = managerIndex[parentId] else { return }
        managers[mSlot].workers.append(WorkerNode(id: id, label: id, status: .running))
        seenWorkers.insert(id)
    }

    private func parseAgentMsg(_ rest: String) {
        for sep in [" → ", " -> ", " >> ", " to "] {
            if let r = rest.range(of: sep) {
                let from = String(rest[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                let to   = String(rest[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                let link = AgentLink(fromId: from, toId: to, timestamp: Date())
                activeLinks.append(link)
                // Auto-expire after 5 seconds
                let linkId = link.id
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    self?.activeLinks.removeAll { $0.id == linkId }
                }
                return
            }
        }
    }

    private func markDone(id: String, summary: String) {
        if let mSlot = managerIndex[id] {
            managers[mSlot].status = .done
            return
        }
        for mi in managers.indices {
            if let wi = managers[mi].workers.firstIndex(where: { $0.id == id }) {
                managers[mi].workers[wi].status  = .done
                managers[mi].workers[wi].summary = summary
                return
            }
        }
    }

    private func markFailed(id: String) {
        if let mSlot = managerIndex[id] { managers[mSlot].status = .failed; return }
        for mi in managers.indices {
            if let wi = managers[mi].workers.firstIndex(where: { $0.id == id }) {
                managers[mi].workers[wi].status = .failed
                return
            }
        }
    }

    private func setWorktreePath(agentId: String, path: String) {
        // Try manager first
        if let mSlot = managerIndex[agentId] {
            managers[mSlot].worktreePath = path; return
        }
        // Try worker
        for mi in managers.indices {
            if let wi = managers[mi].workers.firstIndex(where: { $0.id == agentId }) {
                managers[mi].workers[wi].worktreePath = path; return
            }
        }
    }

    private func recount() {
        var r = 0; var d = 0; var f = 0
        for m in managers {
            for w in m.workers {
                switch w.status {
                case .running, .queued: r += 1
                case .done:             d += 1
                case .failed:           f += 1
                default: break
                }
            }
        }
        totalRunning = r; totalDone = d; totalFailed = f
    }

    // MARK: - Simulation

    func simulateForPreview() {
        reset()
        coordinatorStatus = .running
        coordinatorLabel = "claude-coordinator"
        let orcbs = ["Orchestrator-01","Orchestrator-02","Orchestrator-03","Orchestrator-04"]
        for mid in orcbs {
            spawnManager(id: mid)
            spawnWorker(id: "\(mid)-Scout",   parentId: mid)
            spawnWorker(id: "\(mid)-Builder", parentId: mid)
            spawnWorker(id: "\(mid)-Reviewer",parentId: mid)
        }
        markDone(id: "Orchestrator-01-Scout", summary: "done")
        parseAgentMsg("Orchestrator-01-Scout → Orchestrator-01-Builder")
        recount()
    }
}

// MARK: - Phase 5: Graph topology structs (exo topology pattern)

/// A positioned node in the Canvas topology graph.
struct ResourceNode: Identifiable {
    let id: String          // agentId or "coordinator" / "manager-{runId}"
    let label: String
    var status: AgentDotStatus
    var role: NodeRole
    var position: CGPoint   // assigned by layout engine; updated each frame
    var loadFraction: Double = 0   // 0.0–1.0 for ring fill / heat coloring

    enum NodeRole {
        case coordinator
        case manager
        case worker(category: String)
    }
}

/// A directed edge in the Canvas topology graph.
struct EdgePath: Identifiable {
    let id: UUID
    let fromId: String
    let toId: String
    var topic: BusTopic
    var animPhase: Double   // 0.0–1.0; drives dash-offset animation for active comm lines
    var isActive: Bool      // true while the AgentLink is alive (5s window)
}

// MARK: - Graph computation helpers (AgentSwarmModel extension)

extension AgentSwarmModel {

    /// Flattens coordinator + managers + workers into positional ResourceNode array.
    /// Layout: coordinator top-center, managers in a row below, workers in columns below each manager.
    func computeGraphNodes(in size: CGSize) -> [ResourceNode] {
        var nodes: [ResourceNode] = []
        let cx = size.width / 2
        let topY: CGFloat = 60

        // Coordinator
        nodes.append(ResourceNode(
            id: "coordinator",
            label: coordinatorLabel,
            status: coordinatorStatus,
            role: .coordinator,
            position: CGPoint(x: cx, y: topY)
        ))

        let visibleManagers = managers.filter { $0.status != .idle }
        guard !visibleManagers.isEmpty else { return nodes }

        let mCount = CGFloat(visibleManagers.count)
        let mSpacingX: CGFloat = max(110, min(180, (size.width - 80) / mCount))
        let mStartX = cx - mSpacingX * (mCount - 1) / 2
        let managerY: CGFloat = topY + 110

        for (mi, manager) in visibleManagers.enumerated() {
            let mx = mStartX + CGFloat(mi) * mSpacingX
            nodes.append(ResourceNode(
                id: "manager-\(manager.id)",
                label: String(manager.label.prefix(12)),
                status: manager.status,
                role: .manager,
                position: CGPoint(x: mx, y: managerY),
                loadFraction: Double(manager.activeWorkerCount) / max(1.0, Double(manager.workers.count))
            ))

            let wCount = CGFloat(manager.workers.count)
            let wSpacingX: CGFloat = max(70, min(100, mSpacingX / max(1, wCount)))
            let wStartX = mx - wSpacingX * (wCount - 1) / 2
            let workerY = managerY + 100

            for (wi, worker) in manager.workers.enumerated() {
                let wx = wStartX + CGFloat(wi) * wSpacingX
                nodes.append(ResourceNode(
                    id: worker.id,
                    label: String(worker.label
                        .components(separatedBy: "-").last?
                        .prefix(10) ?? worker.label.prefix(10)),
                    status: worker.status,
                    role: .worker(category: worker.label),
                    position: CGPoint(x: wx, y: workerY)
                ))
            }
        }
        return nodes
    }

    /// Builds edges: coordinator→manager, manager→worker, plus active comm-link & peer escalation edges.
    func computeGraphEdges(nodes: [ResourceNode]) -> [EdgePath] {
        var edges: [EdgePath] = []
        let idSet = Set(nodes.map { $0.id })

        // Structural edges
        for manager in managers where manager.status != .idle {
            if idSet.contains("coordinator") && idSet.contains("manager-\(manager.id)") {
                edges.append(EdgePath(id: UUID(), fromId: "coordinator",
                                      toId: "manager-\(manager.id)",
                                      topic: .commands, animPhase: 0, isActive: false))
            }
            for worker in manager.workers {
                if idSet.contains("manager-\(manager.id)") && idSet.contains(worker.id) {
                    edges.append(EdgePath(id: UUID(), fromId: "manager-\(manager.id)",
                                          toId: worker.id,
                                          topic: .commands, animPhase: 0, isActive: false))
                }
            }
        }

        // Active comm-link edges (AGENT_MSG flashes)
        for link in activeLinks {
            let from = nodes.first { $0.label.hasSuffix(link.fromId) || $0.id == link.fromId }
            let to   = nodes.first { $0.label.hasSuffix(link.toId)   || $0.id == link.toId   }
            if let f = from, let t = to {
                edges.append(EdgePath(id: link.id, fromId: f.id, toId: t.id,
                                      topic: .globalEvents, animPhase: 0, isActive: true))
            }
        }

        // Sprint 7: Peer escalation edges (domain→domain orange arrows)
        for esc in activeEscalations {
            // Find a node whose role.category matches fromDomain, then one matching targetDomain
            func nodeForDomain(_ domain: String) -> ResourceNode? {
                nodes.first { node in
                    if case .worker(let cat) = node.role {
                        return cat.lowercased().contains(domain.lowercased())
                    }
                    return node.id.lowercased().contains(domain.lowercased())
                }
            }
            if let from = nodeForDomain(esc.fromDomain),
               let to   = nodeForDomain(esc.targetDomain) {
                edges.append(EdgePath(id: esc.id, fromId: from.id, toId: to.id,
                                      topic: .peerEscalation, animPhase: 0, isActive: true))
            }
        }

        return edges
    }
}

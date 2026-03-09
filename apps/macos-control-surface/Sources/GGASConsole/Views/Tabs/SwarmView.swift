// SwarmView.swift — Hierarchical swarm tree with right-side legend.
// Bounce fix: pulse ring uses scaleEffect (visual only, no layout impact).

import AppKit
import SwiftUI

// MARK: - Node position preference key

private struct NodePos { let id: String; let center: Anchor<CGPoint> }
private struct NodePosKey: PreferenceKey {
    static var defaultValue: [NodePos] = []
    static func reduce(value: inout [NodePos], nextValue: () -> [NodePos]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Status colors

private func dotColor(_ s: AgentDotStatus) -> Color {
    switch s {
    case .idle, .queued: return Color(white: 0.22)
    case .running:       return Color(red: 0.0, green: 0.88, blue: 0.45)
    case .done:          return Color(white: 0.42)   // grey = done/inactive
    case .failed:        return Color(red: 1.0, green: 0.22, blue: 0.22)
    }
}
private extension Color {
    static let dotIdle    = Color(white: 0.22)
    static let dotRunning = Color(red: 0.0,  green: 0.88, blue: 0.45)
    static let dotDone    = Color(white: 0.42)        // grey = done/inactive
    static let dotFailed  = Color(red: 1.0,  green: 0.22, blue: 0.22)
}

// MARK: - LLM identity (coordinator ring)

private enum LLMType {
    case codex, claude, gemini, kimi, gpt, unknown
    static func detect(_ l: String) -> LLMType {
        let s = l.lowercased()
        if s.contains("codex")   { return .codex }
        if s.contains("claude")  { return .claude }
        if s.contains("gemini")  { return .gemini }
        if s.contains("kimi")    { return .kimi   }
        if s.contains("gpt") || s.contains("openai") { return .gpt }
        return .unknown
    }
    var ringColor: Color {
        switch self {
        case .codex:   return Color(red: 0.19, green: 0.69, blue: 0.96)
        case .claude:  return Color(red: 0.68, green: 0.38, blue: 1.0)
        case .gemini:  return Color(red: 0.16, green: 0.55, blue: 0.96)
        case .kimi:    return Color(red: 0.0,  green: 0.88, blue: 0.45)
        case .gpt:     return Color(red: 0.07, green: 0.73, blue: 0.58)
        case .unknown: return Color(white: 0.55)
        }
    }
    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        case .kimi:   return "Kimi"
        case .gpt:    return "GPT"
        case .unknown: return "Coord"
        }
    }
}

// MARK: - 14-category persona ring colors

private struct PersonaCat { let keywords: [String]; let color: Color; let name: String }
private let personaCategories: [PersonaCat] = [
    .init(keywords: ["scout","explorer","archaeologist","hunter"],
          color: Color(red: 0.0, green: 0.85, blue: 1.0),  name: "Scout / Explorer"),
    .init(keywords: ["builder","developer","engineer","frontend","backend","fullstack","mcp","build"],
          color: Color(red: 0.6, green: 0.92, blue: 0.18), name: "Builder / Dev"),
    .init(keywords: ["qa","tester","tdd","test","e2e","smoke","flaky","verification"],
          color: Color(red: 1.0, green: 0.75, blue: 0.0),  name: "QA / Tester"),
    .init(keywords: ["architect","planner","designer","graphql","ux"],
          color: Color(red: 0.55, green: 0.32, blue: 1.0), name: "Architect / Planner"),
    .init(keywords: ["security","penetration","compliance","chaos","audit"],
          color: Color(red: 1.0, green: 0.38, blue: 0.18), name: "Security / Audit"),
    .init(keywords: ["documentation","writer","technical-writer","documenter","comment"],
          color: Color(red: 0.22, green: 0.74, blue: 1.0), name: "Docs / Writer"),
    .init(keywords: ["analyst","product","financial","manager","ceo","cto","cmo","business"],
          color: Color(red: 1.0, green: 0.60, blue: 0.15), name: "Analyst / Product"),
    .init(keywords: ["orchestrator","coordinator","board","dispatcher","conductor","distributor","multi-agent"],
          color: Color(red: 1.0, green: 0.85, blue: 0.0),  name: "Orchestrator"),
    .init(keywords: ["infra","devops","git","pipeline","ci","resolver"],
          color: Color(red: 0.56, green: 0.64, blue: 0.72), name: "Infra / DevOps"),
    .init(keywords: ["database","data","mongoose","db"],
          color: Color(red: 0.08, green: 0.72, blue: 0.65), name: "Database / Data"),
    .init(keywords: ["performance","optimizer","profiler"],
          color: Color(red: 1.0,  green: 0.35, blue: 0.60), name: "Performance"),
    .init(keywords: ["auth","messaging","api-designer"],
          color: Color(red: 0.2,  green: 0.55, blue: 1.0),  name: "Auth / API"),
    .init(keywords: ["knowledge","context","memory","synthesizer","beads"],
          color: Color(red: 0.44, green: 0.30, blue: 0.88), name: "Knowledge / Context"),
    .init(keywords: ["reviewer","review","simplifier","pr-test","silent","type-design"],
          color: Color(red: 1.0,  green: 0.28, blue: 0.55), name: "Reviewer / PR"),
]

private func personaRingColor(for label: String) -> Color? {
    let lower = label.lowercased()
    for cat in personaCategories {
        if cat.keywords.contains(where: { lower.contains($0) }) { return cat.color }
    }
    return nil
}

// MARK: - Label helpers

private func shortWorkerLabel(_ id: String) -> String {
    let parts = id.components(separatedBy: CharacterSet(charactersIn: "-_ "))
    let roles = ["Scout","Builder","Reviewer","Architect","Planner","Tester","Designer",
                 "Analyst","Writer","Researcher","Debugger","Documenter","Optimizer",
                 "Coordinator","Engineer","Developer","Security","Auth"]
    if let role = parts.first(where: { p in roles.contains(where: { $0.lowercased() == p.lowercased() }) }) {
        if let idx = parts.firstIndex(of: role), idx+1 < parts.count,
           parts[idx+1].allSatisfy(\.isNumber) { return "\(role)-\(parts[idx+1])" }
        return role
    }
    let last = parts.last ?? id
    return last.count <= 4 ? "W-\(last)" : String(id.prefix(6))
}

private func shortManagerLabel(_ id: String) -> String {
    if id.hasPrefix("Orchestrator-") { return "O -\(id.dropFirst("Orchestrator-".count))" }
    if id.hasPrefix("Manager-")      { return "M -\(id.dropFirst("Manager-".count))" }
    if id.hasPrefix("Builder-")      { return "B -\(id.dropFirst("Builder-".count))" }
    return String(id.prefix(7))
}

// MARK: - Dynamic sizing

private struct SwarmSizes {
    var coord: CGFloat; var mgr: CGFloat; var worker: CGFloat
    var hGap: CGFloat;  var vGap: CGFloat; var workerGap: CGFloat

    static let base = SwarmSizes(coord: 36, mgr: 26, worker: 16,
                                  hGap: 56, vGap: 40, workerGap: 16)

    static func compute(managerCount: Int, maxWorkerCount: Int, available: CGSize) -> SwarmSizes {
        var s = base
        let n = CGFloat(max(1, managerCount))
        let w = CGFloat(max(0, maxWorkerCount))
        let estW = n * (s.mgr + s.hGap) + 96
        let estH = s.coord + s.vGap * 2 + s.mgr + s.vGap + w * (s.worker + s.workerGap) + 60
        var scale: CGFloat = 1.0
        if available.width  > 0 { scale = min(scale, available.width  / estW * 0.90) }
        if available.height > 0 { scale = min(scale, available.height / estH * 0.90) }
        scale = max(0.28, min(1.0, scale))
        return SwarmSizes(coord: s.coord * scale, mgr: s.mgr * scale, worker: s.worker * scale,
                          hGap: s.hGap * scale, vGap: s.vGap * scale, workerGap: s.workerGap * scale)
    }
}

// MARK: - Node ID helpers

private func coordNID()           -> String { "coord" }
private func mgrNID(_ id: String) -> String { "mgr-\(id)" }
private func wkrNID(_ id: String) -> String { "wkr-\(id)" }

private func resolveNodePoint(_ rawId: String, pts: [String: CGPoint]) -> CGPoint? {
    pts[wkrNID(rawId)] ?? pts[mgrNID(rawId)] ??
    (rawId.lowercased().contains("coord") ? pts[coordNID()] : nil)
}

// MARK: - Main view

struct SwarmView: View {
    // Delegate ALL polling to AgentMonitorService — this view is display-only (Phase 2)
    @ObservedObject private var monitor   = AgentMonitorService.shared
    @ObservedObject private var swarmModel = AgentSwarmModel.shared
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    @State private var currentSizes = SwarmSizes.base
    @State private var availableSize: CGSize = .zero
    @State private var graphMode = true   // Phase 5: true = topology graph, false = bubble tree
    @State private var selectedRunId = ""
    @State private var selectedAgentId = ""
    @State private var selectedTopologyNodeId: String?
    @State private var guidanceText = ""
    @State private var retaskText = ""
    @State private var actionStatus: String?
    @State private var consoleTarget: WorkerConsoleTarget?

    // Derived view data — computed from AgentMonitorService.busStatuses
    private var busStatuses: [BusRunStatus] {
        if let selectedRunId = workflow.selectedRunId,
           monitor.busStatuses.contains(where: { $0.runId == selectedRunId }) {
            return monitor.busStatuses.filter { $0.runId == selectedRunId }
        }
        return monitor.busStatuses
    }

    private var allWorkers: [(runId: String, agentId: String, status: AgentDotStatus)] {
        busStatuses.flatMap { run in
            run.workers.map { (agentId, worker) in
                let dot: AgentDotStatus = worker.status == "complete" ? .done
                                       : worker.status == "failed"   ? .failed
                                       : worker.status == "queued"   ? .queued : .running
                return (run.runId, agentId, dot)
            }
        }
    }
    private var flattenedWorkers: [(runId: String, agentId: String, worker: BusWorkerState)] {
        busStatuses
            .flatMap { run in
                run.workers.map { (agentId, worker) in
                    (runId: run.runId, agentId: agentId, worker: worker)
                }
            }
            .sorted { left, right in
                if left.runId == right.runId { return left.agentId < right.agentId }
                return left.runId < right.runId
            }
    }
    private var selectedWorker: (runId: String, agentId: String, worker: BusWorkerState)? {
        flattenedWorkers.first { $0.runId == selectedRunId && $0.agentId == selectedAgentId }
    }
    private var selectedRunStatus: BusRunStatus? {
        if let workflowRunId = workflow.selectedRunId,
           let status = monitor.busStatuses.first(where: { $0.runId == workflowRunId }) {
            return status
        }
        if let status = monitor.busStatuses.first(where: { $0.runId == selectedRunId }) {
            return status
        }
        return monitor.busStatuses.first
    }
    private var hasData: Bool {
        (!busStatuses.isEmpty && allWorkers.count > 0)
        || swarmModel.coordinatorStatus != .idle
        || !swarmModel.activeManagers.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HStack(spacing: 0) {
                treeArea
                Divider()
                sidePanel
                    .frame(width: 212)
            }
        }
        // AgentMonitorService feeds this view via @ObservedObject — no .task {} loop needed
        .onChange(of: busStatuses.count) { _, _ in refreshSizes() }
        .onAppear { syncSelection() }
        .onChange(of: busStatuses.count) { _, _ in syncSelection() }
        .onChange(of: workflow.selectedRunId) { _, _ in
            syncSelection()
        }
        .sheet(item: $consoleTarget) { target in
            WorkerConsoleSheet(
                target: target,
                onSendGuidance: { message in
                    try await A2AClient.shared.sendWorkerGuidance(
                        runId: target.runId,
                        agentId: target.agentId,
                        message: message
                    )
                },
                onOpenFiles: {
                    WorktreePanelController.shared.open(
                        agentId: target.agentId,
                        worktreePath: target.worktreePath
                    )
                }
            )
        }
    }


    private func refreshSizes() {
        let runCount = Set(allWorkers.map(\.runId)).count
        let maxWorkers = busStatuses.map { $0.workers.count }.max() ?? 0
        withAnimation(.easeOut(duration: 0.32)) {
            currentSizes = SwarmSizes.compute(managerCount: runCount,
                                              maxWorkerCount: maxWorkers,
                                              available: availableSize)
        }
    }


    // MARK: - Tree area

    @ViewBuilder
    private var treeArea: some View {
        if !hasData {
            emptyState
        } else if graphMode {
            // Phase 5: Canvas-based topology graph
            TopologyGraphView(
                swarmModel: swarmModel,
                selectedNodeId: selectedTopologyNodeId,
                onSelectNode: { node in
                    selectedTopologyNodeId = node.id
                    focusNode(node)
                },
                onOpenConsole: { node in
                    selectedTopologyNodeId = node.id
                    focusNode(node)
                    openConsole(for: node)
                },
                onOpenFiles: { node in
                    selectedTopologyNodeId = node.id
                    focusNode(node)
                    openFiles(for: node)
                }
            )
                .background(Color(NSColor.underPageBackgroundColor))
        } else {
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    treeWithConnectors
                        .padding(.horizontal, 40)
                        .padding(.vertical, 32)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
                }
            }
            .background(Color(NSColor.underPageBackgroundColor))
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { availableSize = geo.size; refreshSizes() }
                        .onChange(of: geo.size) { _, newSize in availableSize = newSize; refreshSizes() }
                }
            )
        }
    }

    // MARK: - Tree + Canvas overlay

    private var treeWithConnectors: some View {
        let managers = AgentSwarmModel.shared.activeManagers
        // Comm links come from the model — fed by app-level poller
        let links    = AgentSwarmModel.shared.activeLinks
        let sizes    = currentSizes

        return nodeLayout(sizes: sizes)
            .coordinateSpace(name: "swarmTree")
            .overlayPreferenceValue(NodePosKey.self) { prefs in
                GeometryReader { geo in
                    Canvas { ctx, _ in
                        let pts = prefs.reduce(into: [String: CGPoint]()) { $0[$1.id] = geo[$1.center] }
                        drawHierarchy(ctx: &ctx, pts: pts, managers: managers)
                        drawCommLinks(ctx: &ctx, pts: pts, links: links)
                    }
                }
            }
    }

    // MARK: - Node layout

    private func nodeLayout(sizes: SwarmSizes) -> some View {
        let llm = LLMType.detect(AgentSwarmModel.shared.coordinatorLabel)

        return VStack(spacing: sizes.vGap) {
            if AgentSwarmModel.shared.coordinatorStatus != .idle {
                SwarmDotView(nodeId: coordNID(), label: llm.displayName, sublabel: nil,
                             status: AgentSwarmModel.shared.coordinatorStatus, size: sizes.coord,
                             ringColor: llm.ringColor, agentId: "coordinator", runId: nil)
                // Explicit easeOut on this transition — no ambient spring
                .transition(.scale(scale: 0.3).combined(with: .opacity).animation(.easeOut(duration: 0.25)))
            }

            if !AgentSwarmModel.shared.activeManagers.isEmpty {
                HStack(alignment: .top, spacing: sizes.hGap) {
                    ForEach(AgentSwarmModel.shared.activeManagers) { mgr in
                        managerColumn(mgr, sizes: sizes)
                        // Column fades in — connector positions are pre-drawn by Canvas
                        .transition(.opacity.animation(.easeOut(duration: 0.22)))
                    }
                }
                // easeOut = smooth layout reflow, no overshoot/bounce
                .animation(.easeOut(duration: 0.35), value: AgentSwarmModel.shared.activeManagers.count)
            }
        }
    }

    private func managerColumn(_ mgr: ManagerNode, sizes: SwarmSizes) -> some View {
        VStack(spacing: sizes.vGap * 0.5) {
            SwarmDotView(nodeId: mgrNID(mgr.id),
                         label: shortManagerLabel(mgr.label),
                         sublabel: mgr.label != shortManagerLabel(mgr.label) ? mgr.label : nil,
                         status: mgr.status, size: sizes.mgr,
                         ringColor: personaRingColor(for: mgr.label),
                         worktreePath: mgr.worktreePath,
                         agentId: mgr.id,
                         runId: mgr.id)
            .transition(.scale(scale: 0.35).combined(with: .opacity).animation(.easeOut(duration: 0.22)))

            if !mgr.workers.isEmpty {
                VStack(spacing: sizes.workerGap) {
                    ForEach(mgr.workers) { w in
                        SwarmDotView(nodeId: wkrNID(w.id),
                                     label: shortWorkerLabel(w.label),
                                     sublabel: w.label != shortWorkerLabel(w.label) ? w.label : nil,
                                     status: w.status, size: sizes.worker,
                                     ringColor: personaRingColor(for: w.label),
                                     worktreePath: w.worktreePath,
                                     agentId: w.id,
                                     runId: mgr.id,
                                     onOpenConsole: {
                                         selectedTopologyNodeId = w.id
                                         selectedRunId = mgr.id
                                         selectedAgentId = w.id
                                         guidanceText = w.summary
                                         if retaskText.isEmpty { retaskText = w.summary }
                                         consoleTarget = WorkerConsoleTarget(
                                             runId: mgr.id,
                                             agentId: w.id,
                                             label: shortWorkerLabel(w.label),
                                             subtitle: w.runtime.map(shortRuntimeLabel) ?? w.personaId,
                                             worktreePath: w.worktreePath
                                                ?? "\(ProjectSettings.shared.projectRoot)/.agent/control-plane/worktrees/\(mgr.id)/\(w.id)"
                                         )
                                     })
                        .transition(.scale(scale: 0.3).combined(with: .opacity).animation(.easeOut(duration: 0.20)))
                    }
                }
                .animation(.easeOut(duration: 0.28), value: mgr.workers.count)
            }
        }
    }

    // MARK: - Canvas lines

    private func drawHierarchy(ctx: inout GraphicsContext,
                                pts: [String: CGPoint],
                                managers: [ManagerNode]) {
        guard let cPt = pts[coordNID()] else { return }
        let sh = GraphicsContext.Shading.color(Color(red: 0, green: 0.88, blue: 0.45, opacity: 0.40))
        for mgr in managers {
            guard let mPt = pts[mgrNID(mgr.id)] else { continue }
            let my = (cPt.y + mPt.y) / 2
            var p = Path(); p.move(to: cPt)
            p.addCurve(to: mPt, control1: .init(x: cPt.x, y: my),
                                control2: .init(x: mPt.x, y: my))
            ctx.stroke(p, with: sh, lineWidth: 1.5)
            for w in mgr.workers {
                guard let wPt = pts[wkrNID(w.id)] else { continue }
                let wy = (mPt.y + wPt.y) / 2
                var wp = Path(); wp.move(to: mPt)
                wp.addCurve(to: wPt, control1: .init(x: mPt.x, y: wy),
                                     control2: .init(x: wPt.x, y: wy))
                ctx.stroke(wp, with: sh, lineWidth: 1.2)
            }
        }
    }

    private func drawCommLinks(ctx: inout GraphicsContext,
                                pts: [String: CGPoint],
                                links: [AgentLink]) {
        let sh   = GraphicsContext.Shading.color(Color(red: 1.0, green: 0.32, blue: 0.18, opacity: 0.28))
        let dash = StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4])
        for link in links {
            guard let a = resolveNodePoint(link.fromId, pts: pts),
                  let b = resolveNodePoint(link.toId,   pts: pts) else { continue }
            let ctrl = CGPoint(x: (a.x+b.x)/2 - (b.y-a.y)*0.25,
                               y: (a.y+b.y)/2 + (b.x-a.x)*0.25)
            var cp = Path(); cp.move(to: a); cp.addQuadCurve(to: b, control: ctrl)
            ctx.stroke(cp, with: sh, style: dash)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 56)).foregroundColor(.secondary.opacity(0.28))
            Text("No active swarm").font(.title3.weight(.medium)).foregroundColor(.secondary)
            Text("Launch a planner task with any sub-agent model to watch the swarm update in real time")
                .font(.callout).foregroundColor(.secondary.opacity(0.52))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Circle().fill(dotColor(AgentSwarmModel.shared.coordinatorStatus)).frame(width: 9, height: 9)
                Text(LLMType.detect(AgentSwarmModel.shared.coordinatorLabel).displayName)
                    .font(.system(size: 11, weight: .medium))
            }
            Divider().frame(height: 18)
            statBadge("Working",  AgentSwarmModel.shared.totalRunning, .dotRunning)
            statBadge("Finished", AgentSwarmModel.shared.totalDone,    .dotDone)
            statBadge("Failed",   AgentSwarmModel.shared.totalFailed,  .dotFailed)
            if let task = workflow.selectedTaskTitle {
                Divider().frame(height: 18)
                Text(task)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                if let runId = workflow.selectedRunId, !runId.isEmpty {
                    Text(String(runId.prefix(12)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Phase 5: graph mode toggle
            HStack(spacing: 1) {
                toggleBtn("Graph",  icon: "point.3.connected.trianglepath.dotted", active: graphMode)  { graphMode = true  }
                toggleBtn("Tree",   icon: "list.bullet.indent",                    active: !graphMode) { graphMode = false }
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.12)))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func toggleBtn(_ label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color(red: 0.94, green: 0.72, blue: 0.18) : Color.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(active ? RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.18)) : nil)
        }
        .buttonStyle(.plain)
    }

    private func statBadge(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(value) \(label)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Side panel

    private var sidePanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                steeringPanel

                Divider().opacity(0.4)

                runTelemetryPanel

                Divider().opacity(0.4)

                selectedWorkerTelemetryPanel

                Divider().opacity(0.4)

                // ── Node types ─────────────────────────────────────────
                legendSection("Node Types")
                legendNodeRow(size: 18, status: .running, label: "Coordinator",
                              desc: "LLM driving the swarm")
                legendNodeRow(size: 13, status: .running, label: "Orchestrator",
                              desc: "Manages a task cluster")
                legendNodeRow(size: 9,  status: .running, label: "Worker",
                              desc: "Executes a single task")

                Divider().opacity(0.4)

                // ── Status ─────────────────────────────────────────────
                legendSection("Status Colors")
                legendColorRow(.dotRunning, "Working", "Active — ring pulses")
                legendColorRow(.dotDone,    "Done",    "Task complete")
                legendColorRow(.dotFailed,  "Failed",  "Task failed")
                legendColorRow(.dotIdle,    "Idle",    "Not yet started")

                Divider().opacity(0.4)

                // ── Coordinator ring ───────────────────────────────────
                legendSection("Coordinator Ring — LLM")
                legendRingRow(Color(red: 0.19, green: 0.69, blue: 0.96),"Codex",   "OpenAI Codex")
                legendRingRow(Color(red: 0.68, green: 0.38, blue: 1.0), "Claude",  "Anthropic")
                legendRingRow(Color(red: 0.16, green: 0.55, blue: 0.96),"Gemini",  "Google")
                legendRingRow(Color(red: 0.0,  green: 0.88, blue: 0.45),"Kimi",    "Moonshot AI")
                legendRingRow(Color(red: 0.07, green: 0.73, blue: 0.58),"GPT",     "OpenAI")

                Divider().opacity(0.4)

                // ── Persona rings (14 categories) ──────────────────────
                legendSection("Worker Ring — Persona")
                ForEach(personaCategories, id: \.name) { cat in
                    legendRingRow(cat.color, cat.name, "")
                }

                Divider().opacity(0.4)

                // ── Lines ──────────────────────────────────────────────
                legendSection("Connector Lines")
                legendLineRow(dashed: false,
                              color: Color(red: 0, green: 0.88, blue: 0.45),
                              label: "Hierarchy",
                              desc: "Coord → Orchestrator → Worker")
                legendLineRow(dashed: true,
                              color: Color(red: 1.0, green: 0.22, blue: 0.22),
                              label: "AGENT_MSG",
                              desc: "Agent-to-agent message (5s)")
                legendLineRow(dashed: true,
                              color: Color(red: 1.0, green: 0.50, blue: 0.10),
                              label: "PEER_ESC",
                              desc: "Domain escalation (8s, ZMQ PUB)")
            }
            .padding(12)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }

    @ViewBuilder
    private var steeringPanel: some View {
        legendSection("Worker Steering")

        if flattenedWorkers.isEmpty {
            Text("No worker state available yet")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        } else {
            Picker("Worker", selection: workerSelectionBinding) {
                ForEach(Array(flattenedWorkers.enumerated()), id: \.offset) { _, entry in
                    Text(entry.agentId)
                        .tag("\(entry.runId)|\(entry.agentId)")
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            if let selected = selectedWorker {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.agentId)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text(selected.runId)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("Status: \(selected.worker.status)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    if let runtime = selected.worker.runtime {
                        Text("Runtime: \(runtime)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    if let persona = selected.worker.personaId {
                        Text("Persona: \(persona)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    if let task = selected.worker.currentTask, !task.isEmpty {
                        Text(task)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }

                CommandTextEditor(
                    text: $guidanceText,
                    placeholder: "Guidance for the selected worker…",
                    font: .systemFont(ofSize: 11)
                )
                .frame(minHeight: 56, maxHeight: 84)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.8)
                )

                CommandTextEditor(
                    text: $retaskText,
                    placeholder: "Retask summary…",
                    font: .systemFont(ofSize: 11)
                )
                .frame(minHeight: 56, maxHeight: 84)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.8)
                )

                Button("Send Guidance") {
                    Task {
                        do {
                            try await A2AClient.shared.sendWorkerGuidance(
                                runId: selected.runId,
                                agentId: selected.agentId,
                                message: guidanceText
                            )
                            actionStatus = "Guidance sent"
                        } catch {
                            actionStatus = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(guidanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Retask + Retry") {
                    Task {
                        do {
                            try await A2AClient.shared.retaskWorker(
                                runId: selected.runId,
                                agentId: selected.agentId,
                                taskSummary: retaskText
                            )
                            actionStatus = "Worker retasked"
                        } catch {
                            actionStatus = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(retaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Retry Worker") {
                    Task {
                        do {
                            try await A2AClient.shared.retryWorker(
                                runId: selected.runId,
                                agentId: selected.agentId
                            )
                            actionStatus = "Worker retry queued"
                        } catch {
                            actionStatus = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Terminate Worker") {
                    Task {
                        do {
                            try await A2AClient.shared.terminateWorker(
                                runId: selected.runId,
                                agentId: selected.agentId,
                                reason: "Terminated from Swarm tab"
                            )
                            actionStatus = "Worker terminated"
                        } catch {
                            actionStatus = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)

                Button("Open Files") {
                    WorktreePanelController.shared.open(
                        agentId: selected.agentId,
                        worktreePath: selected.worker.worktreePath
                            ?? "\(ProjectSettings.shared.projectRoot)/.agent/control-plane/worktrees/\(selected.runId)/\(selected.agentId)"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let actionStatus {
                    Text(actionStatus)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var runTelemetryPanel: some View {
        legendSection("Run Telemetry")

        if let telemetry = selectedRunStatus?.telemetry {
            VStack(alignment: .leading, spacing: 8) {
                telemetryMetricRow("Coordinator", telemetry.coordinatorRuntime)
                telemetryMetricRow("Messages", "\(telemetry.totalMessages)")
                telemetryMetricRow("Delegations", "\(telemetry.delegationCount)")
                telemetryMetricRow("Workers", "\(telemetry.activeWorkers) active / \(telemetry.totalWorkers) total")
                telemetryMetricRow("Governor", "\(telemetry.governorActiveWorkers)/\(telemetry.governorAllowedAgents) active")
                if telemetry.governorQueuedWorkers > 0 {
                    telemetryMetricRow("Queue", "\(telemetry.governorQueuedWorkers)")
                }

                if !telemetry.runtimeBreakdown.isEmpty {
                    telemetryBreakdown(title: "Runtime Mix", items: telemetry.runtimeBreakdown)
                }

                if !telemetry.roleBreakdown.isEmpty {
                    telemetryBreakdown(title: "Role Mix", items: telemetry.roleBreakdown)
                }
            }
        } else {
            Text("No run telemetry yet")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var selectedWorkerTelemetryPanel: some View {
        legendSection("Selected Worker")

        if let selected = selectedWorker {
            VStack(alignment: .leading, spacing: 8) {
                telemetryMetricRow("Agent", selected.agentId)
                if let runtime = selected.worker.runtime {
                    telemetryMetricRow("Runtime", runtime)
                }
                if let role = selected.worker.role {
                    telemetryMetricRow("Role", role)
                }
                if let persona = selected.worker.personaId {
                    telemetryMetricRow("Persona", persona)
                }
                if let transport = selected.worker.launchTransport {
                    telemetryMetricRow("Launch", transport)
                }
                if let executionStatus = selected.worker.executionStatus {
                    telemetryMetricRow("Execution", executionStatus)
                }
                telemetryMetricRow("Heartbeat", relativeHeartbeat(selected.worker.lastHeartbeat))
                if let summary = selected.worker.lastSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
                HStack(spacing: 8) {
                    Button("Live Console") {
                        consoleTarget = WorkerConsoleTarget(
                            runId: selected.runId,
                            agentId: selected.agentId,
                            label: selected.agentId,
                            subtitle: selected.worker.runtime.map(shortRuntimeLabel) ?? selected.worker.personaId,
                            worktreePath: selected.worker.worktreePath
                                ?? "\(ProjectSettings.shared.projectRoot)/.agent/control-plane/worktrees/\(selected.runId)/\(selected.agentId)"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("View Worktree") {
                        WorktreePanelController.shared.open(
                            agentId: selected.agentId,
                            worktreePath: selected.worker.worktreePath
                                ?? "\(ProjectSettings.shared.projectRoot)/.agent/control-plane/worktrees/\(selected.runId)/\(selected.agentId)"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let worktreePath = selected.worker.worktreePath {
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktreePath)])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        } else {
            Text("Select a worker to inspect its runtime, persona, and worktree.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    private func telemetryMetricRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
            Spacer()
        }
    }

    private func telemetryBreakdown(title: String, items: [TelemetryCount]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            ForEach(items.prefix(4)) { item in
                telemetryMetricRow(item.label, "\(item.count)")
            }
        }
    }

    private func relativeHeartbeat(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else {
            return "Unknown"
        }
        let delta = max(0, Int(Date().timeIntervalSince(date)))
        if delta < 60 {
            return "\(delta)s ago"
        }
        return "\(delta / 60)m ago"
    }

    private var workerSelectionBinding: Binding<String> {
        Binding(
            get: { "\(selectedRunId)|\(selectedAgentId)" },
            set: { value in
                let parts = value.components(separatedBy: "|")
                guard parts.count == 2 else { return }
                selectedRunId = parts[0]
                selectedAgentId = parts[1]
                selectedTopologyNodeId = parts[1]
                if let selected = selectedWorker {
                    guidanceText = selected.worker.currentTask ?? guidanceText
                    if retaskText.isEmpty {
                        retaskText = selected.worker.currentTask ?? ""
                    }
                }
            }
        )
    }

    private func syncSelection() {
        guard !flattenedWorkers.isEmpty else { return }
        if let runId = workflow.selectedRunId,
           let match = flattenedWorkers.first(where: { $0.runId == runId }) {
            selectedRunId = match.runId
            selectedAgentId = match.agentId
            selectedTopologyNodeId = match.agentId
            guidanceText = match.worker.currentTask ?? guidanceText
            retaskText = retaskText.isEmpty ? (match.worker.currentTask ?? "") : retaskText
            return
        }
        if selectedWorker == nil {
            selectedRunId = flattenedWorkers[0].runId
            selectedAgentId = flattenedWorkers[0].agentId
            selectedTopologyNodeId = flattenedWorkers[0].agentId
            guidanceText = flattenedWorkers[0].worker.currentTask ?? ""
            retaskText = flattenedWorkers[0].worker.currentTask ?? ""
        }
    }

    private func focusNode(_ node: ResourceNode) {
        guard let runId = node.runId, let agentId = node.agentId, !runId.isEmpty, !agentId.isEmpty else {
            return
        }
        selectedRunId = runId
        selectedAgentId = agentId
        shell.focusWorktree(
            path: resolvedWorktreePath(runId: runId, agentId: agentId, providedPath: node.worktreePath),
            label: node.label
        )
        if let worker = flattenedWorkers.first(where: { $0.runId == runId && $0.agentId == agentId })?.worker {
            guidanceText = worker.currentTask ?? guidanceText
            if retaskText.isEmpty {
                retaskText = worker.currentTask ?? ""
            }
        }
    }

    private func openConsole(for node: ResourceNode) {
        guard let runId = node.runId, let agentId = node.agentId, !runId.isEmpty, !agentId.isEmpty else {
            return
        }
        consoleTarget = WorkerConsoleTarget(
            runId: runId,
            agentId: agentId,
            label: node.label,
            subtitle: node.subtitle,
            worktreePath: resolvedWorktreePath(runId: runId, agentId: agentId, providedPath: node.worktreePath)
        )
    }

    private func openFiles(for node: ResourceNode) {
        guard let agentId = node.agentId, !agentId.isEmpty else {
            return
        }
        let worktreePath = resolvedWorktreePath(
            runId: node.runId,
            agentId: agentId,
            providedPath: node.worktreePath
        )
        WorktreePanelController.shared.open(agentId: agentId, worktreePath: worktreePath)
    }

    private func resolvedWorktreePath(runId: String?, agentId: String, providedPath: String?) -> String {
        if let providedPath,
           !providedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return providedPath
        }
        if let runId, !runId.isEmpty {
            return "\(ProjectSettings.shared.projectRoot)/.agent/control-plane/worktrees/\(runId)/\(agentId)"
        }
        return ProjectSettings.shared.projectRoot
    }

    // Legend helpers
    private func legendSection(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func legendNodeRow(size: CGFloat, status: AgentDotStatus,
                                label: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dotColor(status)).frame(width: size, height: size)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11, weight: .medium))
                Text(desc).font(.system(size: 9)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private func legendColorRow(_ color: Color, _ label: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11, weight: .medium))
                if !desc.isEmpty {
                    Text(desc).font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    private func legendRingRow(_ color: Color, _ label: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(Color(white: 0.22)).frame(width: 10, height: 10)
                Circle().stroke(color, lineWidth: 2.5).frame(width: 14, height: 14)
            }
            .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11, weight: .medium))
                if !desc.isEmpty {
                    Text(desc).font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    private func legendLineRow(dashed: Bool, color: Color, label: String, desc: String) -> some View {
        HStack(spacing: 8) {
            Canvas { ctx, size in
                var p = Path()
                p.move(to: .init(x: 0, y: size.height / 2))
                p.addLine(to: .init(x: size.width, y: size.height / 2))
                let style: StrokeStyle = dashed
                    ? .init(lineWidth: 1.5, lineCap: .round, dash: [4, 3])
                    : .init(lineWidth: 1.5)
                ctx.stroke(p, with: .color(color), style: style)
            }
            .frame(width: 28, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11, weight: .medium))
                Text(desc).font(.system(size: 9)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Dot view
// KEY FIX: pulse ring uses .scaleEffect (purely visual, zero layout impact)
// This eliminates the bounce caused by frame size oscillating with pulseScale.

private struct SwarmDotView: View {
    let nodeId:      String
    let label:       String
    let sublabel:    String?
    let status:      AgentDotStatus
    let size:        CGFloat
    let ringColor:   Color?
    var worktreePath: String? = nil   // explicit path (nil = fallback inferred from run/agent)
    var agentId:      String  = ""
    var runId:        String? = nil
    var onOpenConsole: (() -> Void)? = nil

    @State private var pulseScale:   CGFloat = 1.0
    @State private var pulseOpacity: Double  = 0.65

    /// The path used when opening WorktreePanel. Falls back to the harness-owned
    /// control-plane worktree convention under .agent/control-plane/worktrees.
    private var resolvedWorktreePath: String {
        if let p = worktreePath, !p.isEmpty { return p }
        if nodeId == "coord" {
            return ProjectSettings.shared.projectRoot
        }
        let aid = agentId.isEmpty ? nodeId : agentId
        if let runId, !runId.isEmpty {
            return "\(ProjectSettings.shared.projectRoot)/.agent/control-plane/worktrees/\(runId)/\(aid)"
        }
        return "\(ProjectSettings.shared.projectRoot)/.agent/control-plane/worktrees/\(aid)"
    }

    var body: some View {
        VStack(spacing: max(3, size * 0.22)) {
            ZStack {
                // Persona / LLM ring (outer, fixed frame — no layout change)
                if let ring = ringColor {
                    Circle()
                        .stroke(ring, lineWidth: max(1.5, size * 0.10))
                        .frame(width: size + max(3, size * 0.28),
                               height: size + max(3, size * 0.28))
                }

                // Main dot
                Circle()
                    .fill(dotColor(status))
                    .frame(width: size, height: size)
                    .shadow(color: dotColor(status).opacity(status == .running ? 0.50 : 0.14),
                            radius: status == .running ? size * 0.5 : 2)
                    .anchorPreference(key: NodePosKey.self, value: .center) {
                        [NodePos(id: nodeId, center: $0)]
                    }
                    // Pulse ring — visual only, no layout impact
                    .overlay(
                        Circle()
                            .stroke(dotColor(status).opacity(pulseOpacity), lineWidth: 1.5)
                            .scaleEffect(pulseScale)
                            .opacity(status == .running ? 1 : 0)
                            .onAppear {
                                guard status == .running else { return }
                                withAnimation(
                                    .easeOut(duration: 1.65).repeatForever(autoreverses: false)
                                ) {
                                    pulseScale = 2.8; pulseOpacity = 0
                                }
                            }
                    )
            }
            // Primary label
            Text(label)
                .font(.system(size: max(7, size * 0.44), weight: .semibold, design: .monospaced))
                .foregroundColor(.primary.opacity(0.82))
                .lineLimit(1).fixedSize()
            // Sublabel (full ID) for larger nodes
            if let sub = sublabel, size >= 18 {
                Text(sub)
                    .font(.system(size: max(6, size * 0.30), design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.44))
                    .lineLimit(1).fixedSize()
            }
            // ── Files button — always visible below the label ──────────
            // Green when worktreePath is confirmed; grey when using fallback inference.
            if size >= 14 {
                HStack(spacing: 4) {
                    if let onOpenConsole {
                        Button(action: onOpenConsole) {
                            HStack(spacing: 3) {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: max(6, size * 0.30), weight: .medium))
                                if size >= 22 {
                                    Text("CLI")
                                        .font(.system(size: max(6, size * 0.28), weight: .medium))
                                }
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, max(4, size * 0.18))
                            .padding(.vertical,   max(1, size * 0.08))
                            .background(Capsule().fill(Color.accentColor.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        let aid = agentId.isEmpty ? nodeId : agentId
                        WorktreePanelController.shared.open(agentId: aid,
                                                            worktreePath: resolvedWorktreePath)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: max(6, size * 0.30), weight: .medium))
                            if size >= 22 {
                                Text("Files")
                                    .font(.system(size: max(6, size * 0.28), weight: .medium))
                            }
                        }
                        .foregroundColor(worktreePath != nil
                            ? Color(red: 0.0, green: 0.88, blue: 0.45)
                            : Color(white: 0.52))
                        .padding(.horizontal, max(4, size * 0.18))
                        .padding(.vertical,   max(1, size * 0.08))
                        .background(
                            Capsule()
                                .fill(Color(white: 0.12))
                                .overlay(Capsule().stroke(Color(white: 0.26), lineWidth: 0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open worktree for \(agentId.isEmpty ? nodeId : agentId)")
                }
            }
        }
    }
}

// MARK: - Phase 5: Topology Graph View (Canvas-based)

struct TopologyGraphView: View {
    @ObservedObject var swarmModel: AgentSwarmModel
    let selectedNodeId: String?
    let onSelectNode: (ResourceNode) -> Void
    let onOpenConsole: (ResourceNode) -> Void
    let onOpenFiles: (ResourceNode) -> Void
    @State private var animPhase: Double = 0

    var body: some View {
        GeometryReader { geo in
            let nodes = swarmModel.computeGraphNodes(in: geo.size)
            let edges = swarmModel.computeGraphEdges(nodes: nodes)
            let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

            ZStack {
                Canvas { ctx, _ in
                    for edge in edges {
                        guard let from = nodeMap[edge.fromId], let to = nodeMap[edge.toId] else { continue }
                        drawTopologyEdge(ctx: &ctx, from: from.position, to: to.position,
                                         topic: edge.topic, isActive: edge.isActive, phase: animPhase)
                    }
                }

                ForEach(nodes) { node in
                    TopologyNodeView(
                        node: node,
                        selected: selectedNodeId == node.id,
                        onSelect: { onSelectNode(node) },
                        onOpenConsole: node.role.isWorkerLike ? { onOpenConsole(node) } : nil,
                        onOpenFiles: node.agentId == nil ? nil : { onOpenFiles(node) }
                    )
                    .position(node.position)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                animPhase = 1.0
            }
        }
    }

    // MARK: - Edge drawing

    private func drawTopologyEdge(ctx: inout GraphicsContext, from: CGPoint, to: CGPoint,
                                   topic: BusTopic, isActive: Bool, phase: Double) {
        let edgeColor: Color
        switch topic {
        case .commands:
            edgeColor = Color(red: 0.0, green: 0.88, blue: 0.45).opacity(0.45)
        case .globalEvents:
            edgeColor = isActive
                ? Color(red: 1.0, green: 0.22, blue: 0.22).opacity(0.85)
                : Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.35)
        case .peerEscalation:
            // Sprint 7: orange domain-to-domain escalation arrow
            edgeColor = Color(red: 1.0, green: 0.50, blue: 0.10).opacity(0.92)
        default:
            edgeColor = Color(white: 0.4).opacity(0.3)
        }

        let mid  = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: to, control: CGPoint(x: mid.x + (to.y - from.y) * 0.15,
                                                    y: mid.y - (to.x - from.x) * 0.15))

        if topic == .peerEscalation {
            // Thick animated orange dashes for peer escalation
            let offset = phase * 24
            ctx.stroke(path, with: .color(edgeColor),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                          dash: [8, 5], dashPhase: offset))
        } else if isActive {
            // Animated dashed stroke for comm links
            let offset = phase * 18
            ctx.stroke(path, with: .color(edgeColor),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                          dash: [6, 6], dashPhase: offset))
        } else {
            ctx.stroke(path, with: .color(edgeColor), lineWidth: 1.5)
        }

        // Arrowhead at destination
        let dx = to.x - from.x, dy = to.y - from.y
        let angle = atan2(dy, dx)
        let aLen:  CGFloat = topic == .peerEscalation ? 10 : 7
        let aAngle: CGFloat = .pi / 6
        let p1 = CGPoint(x: to.x - aLen * cos(angle - aAngle),
                         y: to.y - aLen * sin(angle - aAngle))
        let p2 = CGPoint(x: to.x - aLen * cos(angle + aAngle),
                         y: to.y - aLen * sin(angle + aAngle))
        var arrow = Path()
        arrow.move(to: p1); arrow.addLine(to: to); arrow.addLine(to: p2)
        let arrowLineW: CGFloat = topic == .peerEscalation ? 2.0 : 1.2
        ctx.stroke(arrow, with: .color(edgeColor), lineWidth: arrowLineW)
    }

}

private struct TopologyNodeView: View {
    let node: ResourceNode
    let selected: Bool
    let onSelect: () -> Void
    let onOpenConsole: (() -> Void)?
    let onOpenFiles: (() -> Void)?

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.55

    private var runtimeRing: Color {
        if let runtime = node.runtime, !runtime.isEmpty {
            return LLMType.detect(runtime).ringColor
        }
        return Color(white: 0.55)
    }

    private var personaRing: Color? {
        if let persona = node.personaId, !persona.isEmpty {
            return personaRingColor(for: persona)
        }
        switch node.role {
        case .worker(let category):
            return personaRingColor(for: category)
        default:
            return nil
        }
    }

    private var size: CGFloat {
        switch node.role {
        case .coordinator: return 42
        case .manager: return 28
        case .worker: return 18
        }
    }

    private var cardWidth: CGFloat {
        switch node.role {
        case .coordinator: return 156
        case .manager: return 132
        case .worker: return 118
        }
    }

    private var baseColor: Color {
        switch node.status {
        case .running: return Color(red: 0.0, green: 0.88, blue: 0.45)
        case .done: return Color(white: 0.38)
        case .failed: return Color(red: 1.0, green: 0.22, blue: 0.22)
        case .queued: return Color(red: 0.94, green: 0.72, blue: 0.18)
        case .idle: return Color(white: 0.22)
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if let personaRing {
                    Circle()
                        .stroke(personaRing.opacity(0.85), style: StrokeStyle(lineWidth: 1.8, dash: [3, 2]))
                        .frame(width: size + 12, height: size + 12)
                }

                Circle()
                    .stroke(runtimeRing, lineWidth: selected ? 3.5 : 2.4)
                    .frame(width: size + 6, height: size + 6)

                Circle()
                    .fill(baseColor.opacity(node.loadFraction > 0.7 ? 1.0 : 0.88))
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(runtimeRing.opacity(pulseOpacity), lineWidth: 2)
                            .scaleEffect(pulseScale)
                            .opacity(node.status == .running ? 1 : 0)
                    )
            }
            .shadow(color: baseColor.opacity(node.status == .running ? 0.4 : 0.12), radius: node.status == .running ? 12 : 4)

            Text(node.label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(.primary)

            if let subtitle = node.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let detail = node.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            if onOpenConsole != nil || onOpenFiles != nil {
                HStack(spacing: 6) {
                    if let onOpenConsole {
                        Button(action: onOpenConsole) {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                        .help("Open live worker console")
                    }
                    if let onOpenFiles {
                        Button(action: onOpenFiles) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                        .help("Open worktree")
                    }
                }
            }
        }
        .frame(width: cardWidth)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.windowBackgroundColor).opacity(selected ? 0.92 : 0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(selected ? runtimeRing.opacity(0.9) : Color.white.opacity(0.08), lineWidth: selected ? 1.6 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onSelect)
        .contextMenu {
            if let onOpenConsole {
                Button("Open Live Console", action: onOpenConsole)
            }
            if let onOpenFiles {
                Button("Open Worktree", action: onOpenFiles)
            }
        }
        .onAppear {
            guard node.status == .running else { return }
            withAnimation(.easeOut(duration: 1.45).repeatForever(autoreverses: false)) {
                pulseScale = 2.4
                pulseOpacity = 0
            }
        }
    }
}

private struct WorkerConsoleTarget: Identifiable, Equatable {
    let runId: String
    let agentId: String
    let label: String
    let subtitle: String?
    let worktreePath: String

    var id: String { "\(runId)|\(agentId)" }
}

private struct WorkerConsoleSheet: View {
    let target: WorkerConsoleTarget
    let onSendGuidance: (String) async throws -> Void
    let onOpenFiles: () -> Void

    @State private var lines: [String] = []
    @State private var guidance = ""
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.label)
                        .font(.system(size: 14, weight: .semibold))
                    Text(target.subtitle ?? "\(target.runId) · \(target.agentId)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Files", action: onOpenFiles)
                    .buttonStyle(.bordered)
            }

            ScrollView {
                Text(lines.joined(separator: ""))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(minHeight: 320)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.9))
            )

            CommandTextEditor(
                text: $guidance,
                placeholder: "Inject steering instructions into this worker…",
                font: .systemFont(ofSize: 12)
            )
            .frame(minHeight: 72, maxHeight: 96)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )

            HStack {
                Button("Send Guidance") {
                    Task {
                        do {
                            try await onSendGuidance(guidance)
                            statusMessage = "Guidance sent"
                            guidance = ""
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(guidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
        .task(id: target.id) {
            for await line in A2AClient.shared.subscribeWorkerStream(runId: target.runId, agentId: target.agentId) {
                lines.append(line)
                if lines.count > 1000 {
                    lines.removeFirst(lines.count - 1000)
                }
            }
        }
    }
}

private extension ResourceNode.NodeRole {
    var isWorkerLike: Bool {
        switch self {
        case .worker:
            return true
        case .coordinator, .manager:
            return false
        }
    }
}

// MARK: - Preview

struct SwarmView_Previews: PreviewProvider {
    static var previews: some View {
        SwarmView()
            .onAppear { AgentSwarmModel.shared.simulateForPreview() }
            .frame(width: 1200, height: 700)
            .preferredColorScheme(.dark)
    }
}

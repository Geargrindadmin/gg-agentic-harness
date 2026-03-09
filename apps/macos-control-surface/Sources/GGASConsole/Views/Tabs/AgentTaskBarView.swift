// AgentTaskBarView.swift — Organized row-based view of all active agents
// Shows agents from all bus runs as sortable table rows with inline system metrics.

import SwiftUI

// MARK: - Flat agent row data

struct AgentRow: Identifiable {
    let id: String          // e.g. "run-abc123 / sub-01-02"
    let runId: String
    let agentId: String
    let status: AgentDotStatus
    let progressPct: Double // 0–100
    let currentTask: String
    let lastHeartbeat: Date?
    let lastMessageTo: String?
    let lastMessageFrom: String?
}

// MARK: - Sort options

enum AgentRowSort: String, CaseIterable {
    case status   = "Status"
    case progress = "Progress"
    case agentId  = "Agent"
    case runId    = "Run"
    case heartbeat = "Last Seen"
}

// MARK: - View

struct AgentTaskBarView: View {
    @ObservedObject private var model = AgentSwarmModel.shared
    @ObservedObject private var metrics = SystemMetricsService.shared
    @EnvironmentObject private var forge: ForgeStore
    @State private var sortBy: AgentRowSort = .status
    @State private var showOnlyActive = false
    @State private var searchText = ""

    private var rows: [AgentRow] {
        var result: [AgentRow] = []

        // ─── Live bus agents (swarms) ──────────────────────────────────────
        for manager in model.managers {
            for worker in manager.workers {
                let link = model.activeLinks.last { $0.fromId == worker.id || $0.toId == worker.id }
                result.append(AgentRow(
                    id: "\(manager.id)/\(worker.id)",
                    runId: manager.id,
                    agentId: worker.id,
                    status: worker.status,
                    progressPct: worker.status == .done ? 100 : (worker.status == .failed ? 0 : 50),
                    currentTask: worker.summary.isEmpty ? "running…" : worker.summary,
                    lastHeartbeat: worker.lastHeartbeat,
                    lastMessageTo: link?.toId == worker.id ? link?.fromId : nil,
                    lastMessageFrom: link?.fromId == worker.id ? link?.toId : nil
                ))
            }
        }

        // ─── Planner tasks linked to runs or kept for operator tracking ────
        for task in forge.tasks {
            // Avoid duplicates with bus agents by checking runId overlap
            let taskRunId = task.runId ?? task.id
            let alreadyPresent = result.contains { $0.runId == taskRunId }
            guard !alreadyPresent else { continue }

            let status: AgentDotStatus
            switch task.linkedRunStatus ?? task.status {
            case "in_progress", "running": status = .running
            case "done", "completed":      status = .done
            case "failed", "error":        status = .failed
            default:                       status = .idle
            }

            result.append(AgentRow(
                id: "forge-\(task.id)",
                runId: taskRunId,
                agentId: task.title,
                status: status,
                progressPct: status == .done ? 100 : (status == .running ? 50 : 0),
                currentTask: task.description ?? task.runStatusLabel ?? task.status,
                lastHeartbeat: nil,
                lastMessageTo: nil,
                lastMessageFrom: nil
            ))
        }

        return result
    }

    private var filteredRows: [AgentRow] {
        var r = rows
        if showOnlyActive { r = r.filter { $0.status.isActive } }
        if !searchText.isEmpty {
            r = r.filter {
                $0.agentId.localizedCaseInsensitiveContains(searchText) ||
                $0.runId.localizedCaseInsensitiveContains(searchText) ||
                $0.currentTask.localizedCaseInsensitiveContains(searchText)
            }
        }
        return r.sorted { a, b in
            switch sortBy {
            case .status:    return statusOrder(a.status) < statusOrder(b.status)
            case .progress:  return a.progressPct > b.progressPct
            case .agentId:   return a.agentId < b.agentId
            case .runId:     return a.runId < b.runId
            case .heartbeat: return (a.lastHeartbeat ?? .distantPast) > (b.lastHeartbeat ?? .distantPast)
            }
        }
    }

    private func statusOrder(_ s: AgentDotStatus) -> Int {
        switch s { case .running: return 0; case .queued: return 1; case .idle: return 2; case .done: return 3; case .failed: return 4 }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header bar ───────────────────────────────────────────────────
            headerBar

            // ── Table ────────────────────────────────────────────────────────
            if filteredRows.isEmpty {
                emptyState
            } else {
                tableContent
            }
        }
        .navigationTitle("Agents")
        .task { SystemMetricsService.shared.start() }
    }

    // MARK: Header bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter agents…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 200)

            Divider().frame(height: 18)

            // Sort picker
            Picker("Sort", selection: $sortBy) {
                ForEach(AgentRowSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.caption)

            Toggle("Active only", isOn: $showOnlyActive)
                .toggleStyle(.checkbox)
                .font(.caption)

            Spacer()

            // Live summary chips
            let m = metrics.metrics
            summaryChip(icon: "person.3.fill",         label: "\(filteredRows.filter { $0.status.isActive }.count) active",   color: .accentColor)
            summaryChip(icon: "cpu.fill",              label: String(format: "%.0f%%", m.cpuPct),                              color: metricColor(m.cpuPct))
            summaryChip(icon: "memorychip.fill",       label: String(format: "%.1f GB", m.ramUsedGB),                          color: metricColor(m.ramUsedGB / max(m.ramTotalGB, 1) * 100))
            summaryChip(icon: "arrow.down.arrow.up",   label: formatNet(m.netInKBs + m.netOutKBs),                              color: .cyan)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: Table

    private var tableContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                columnHeaders
                Divider()
                ForEach(filteredRows) { row in
                    AgentRowView(row: row)
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("").frame(width: 28)   // status dot
            columnHeader("Agent ID",    width: 160)
            columnHeader("Run ID",      width: 130)
            columnHeader("Progress",    width: 90)
            columnHeader("Current Task",width: nil)
            columnHeader("Last Msg →",  width: 100)
            columnHeader("Last Msg ←",  width: 100)
            columnHeader("Seen",        width: 70)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.04))
    }

    private func columnHeader(_ title: String, width: CGFloat?) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 4)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No agents running")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Spawn a swarm to see agents here in real time.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    private func summaryChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(label).font(.system(size: 10, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }

    private func metricColor(_ pct: Double) -> Color {
        switch pct { case ..<50: return .green; case ..<80: return .orange; default: return .red }
    }

    private func formatNet(_ kbs: Double) -> String {
        if kbs > 1_000 { return String(format: "%.1f MB/s", kbs / 1_024) }
        return String(format: "%.0f KB/s", kbs)
    }
}

// MARK: - Individual row

struct AgentRowView: View {
    let row: AgentRow

    var body: some View {
        HStack(spacing: 0) {
            // Status dot
            statusDot
                .frame(width: 28)

            // Agent ID
            Text(row.agentId)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)
                .padding(.horizontal, 4)

            // Run ID (truncated)
            Text(String(row.runId.prefix(12)))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
                .padding(.horizontal, 4)

            // Progress bar
            progressBar
                .frame(width: 90)
                .padding(.horizontal, 4)

            // Current task
            Text(row.currentTask)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            // Last message TO
            Text(row.lastMessageTo ?? "–")
                .font(.system(size: 10))
                .foregroundStyle(.cyan.opacity(0.8))
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 4)

            // Last message FROM
            Text(row.lastMessageFrom ?? "–")
                .font(.system(size: 10))
                .foregroundStyle(.mint.opacity(0.8))
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 4)

            // Last heartbeat
            Text(relativeTime(row.lastHeartbeat))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background(row.status.isActive ? Color.accentColor.opacity(0.04) : Color.clear)
    }

    private var dotColor: Color {
        switch row.status {
        case .running: return .green
        case .queued:  return .yellow
        case .done:    return Color(white: 0.42)
        case .failed:  return .red
        case .idle:    return .gray
        }
    }

    private var dotPulse: Bool {
        row.status == .running || row.status == .queued
    }

    private var statusDot: some View {
        ZStack {
            if dotPulse {
                Circle().fill(dotColor.opacity(0.25)).frame(width: 14, height: 14)
                    .scaleEffect(1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: dotPulse)
            }
            Circle().fill(dotColor).frame(width: 7, height: 7)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 3)
                    .fill(progressColor)
                    .frame(width: geo.size.width * CGFloat(row.progressPct / 100), height: 4)
                Text(String(format: "%.0f%%", row.progressPct))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: 6)
            }
        }
        .frame(height: 14)
    }

    private var progressColor: Color {
        switch row.status {
        case .done:   return .gray
        case .failed: return .red
        default:      return .accentColor
        }
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "–" }
        let diff = Date.now.timeIntervalSince(date)
        if diff < 60   { return "\(Int(diff))s" }
        if diff < 3600 { return "\(Int(diff/60))m" }
        return "\(Int(diff/3600))h"
    }
}

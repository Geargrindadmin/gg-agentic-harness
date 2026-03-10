// ContentView.swift — Main window with sidebar navigation

import SwiftUI

enum ConsoleTab: String, CaseIterable, Identifiable {
    case tasks         = "Planner"
    case swarm         = "Swarm"
    case notes         = "Notes"
    case replays       = "Replays"
    case modelFit      = "Model Fit"
    case freeModels    = "Free Models"
    case agentTaskBar  = "Agents"
    case agentAnalytics = "Agent Analytics"
    case usage         = "Usage"
    case terminal      = "Terminal"
    case llmStudio     = "LLM Studio"
    case dispatch      = "Dispatch"
    case harness       = "Harness"
    case packages      = "Packages"
    case skills        = "Skill Analytics"
    case trace         = "Trace"
    case liveLog       = "Live Log"
    case runHistory    = "Run History"
    case config        = "Config"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tasks:        return "checklist"
        case .swarm:        return "circle.grid.3x3.fill"
        case .notes:        return "note.text"
        case .replays:      return "movieclapper.fill"
        case .modelFit:     return "slider.horizontal.below.rectangle"
        case .freeModels:   return "globe.americas.fill"
        case .agentTaskBar: return "list.bullet.rectangle.fill"
        case .agentAnalytics: return "chart.line.uptrend.xyaxis"
        case .usage:       return "gauge.with.dots.needle.67percent"
        case .terminal:     return "terminal.fill"
        case .llmStudio:    return "square.and.arrow.down.on.square"
        case .dispatch:     return "paperplane.fill"
        case .harness:      return "point.3.connected.trianglepath.dotted"
        case .packages:     return "shippingbox.fill"
        case .skills:       return "chart.bar.fill"
        case .trace:        return "magnifyingglass"
        case .liveLog:      return "bolt.fill"
        case .runHistory:   return "clock.arrow.circlepath"
        case .config:       return "gear"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var forge: ForgeStore
    @EnvironmentObject private var shell: AppShellState

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $shell.selectedTab)
                    .navigationSplitViewColumnWidth(
                        min: shell.sidebarCollapsed ? 52 : 220,
                        ideal: shell.sidebarCollapsed ? 52 : 236,
                        max: shell.sidebarCollapsed ? 60 : 250
                    )
            } detail: {
                IDEWorkspaceView {
                    detailView(for: shell.selectedTab)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 1220, minHeight: 678)

            StatusBarView()
        }
        .frame(minWidth: 1220, minHeight: 700)
    }

    @ViewBuilder
    private func detailView(for tab: ConsoleTab) -> some View {
        switch tab {
        case .tasks:        TasksView()
        case .swarm:        SwarmView()
        case .notes:        NotesView()
        case .replays:      ReplaysView()
        case .modelFit:     ModelFitView()
        case .freeModels:   FreeModelsView()
        case .agentTaskBar: AgentTaskBarView()
        case .agentAnalytics: AgentAnalyticsView()
        case .usage:        UsageView()
        case .terminal:     TerminalTabView()
        case .llmStudio:   LLMStudioTabView()
        case .dispatch:     DispatchView()
        case .harness:      HarnessView()
        case .packages:     PackagesTabView()
        case .skills:       SkillAnalyticsView()
        case .trace:        TraceView()
        case .liveLog:      LiveLogView()
        case .runHistory:   RunHistoryView()
        case .config:       ConfigView()
        }
    }
}

// MARK: - Sidebar (explicit buttons — avoids List selection tap-swallow bug)

struct SidebarView: View {
    @Binding var selection: ConsoleTab
    @EnvironmentObject var forge: ForgeStore
    @EnvironmentObject private var shell: AppShellState
    @ObservedObject private var monitor = AgentMonitorService.shared

    private let primaryTabs: [ConsoleTab] = [
        .tasks,
        .swarm,
        .notes,
        .replays,
        .modelFit,
        .freeModels,
        .agentTaskBar,
        .agentAnalytics,
        .terminal,
        .llmStudio,
        .dispatch,
        .harness,
        .packages,
        .skills
    ]

    private let diagnosticTabs: [ConsoleTab] = [
        .usage,
        .trace,
        .liveLog,
        .runHistory,
        .config
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, shell.sidebarCollapsed ? 7 : 16)
                .padding(.top, shell.sidebarCollapsed ? 12 : 16)
                .padding(.bottom, 8)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    if !shell.sidebarCollapsed {
                        sectionHeader("Operate")
                    }
                    ForEach(primaryTabs) { tab in
                        SidebarButton(
                            tab: tab,
                            isSelected: selection == tab,
                            badge: badgeCount(for: tab)
                        ) {
                            selectTab(tab)
                        }
                    }

                    if !shell.sidebarCollapsed {
                        sectionHeader("Diagnostics")
                    }
                    ForEach(diagnosticTabs) { tab in
                        SidebarButton(
                            tab: tab,
                            isSelected: selection == tab,
                            badge: badgeCount(for: tab)
                        ) {
                            selectTab(tab)
                        }
                    }
                }
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            if !shell.sidebarCollapsed {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                AgentHealthStrip()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
            }
        }
        .frame(
            minWidth: shell.sidebarCollapsed ? 52 : 220,
            idealWidth: shell.sidebarCollapsed ? 52 : 236,
            maxWidth: shell.sidebarCollapsed ? 60 : 250,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func badgeCount(for tab: ConsoleTab) -> Int {
        switch tab {
        case .tasks: return forge.tasks.filter { $0.status == "in_progress" }.count
        default: return 0
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private var header: some View {
        if shell.sidebarCollapsed {
            VStack(spacing: 10) {
                Button {
                    shell.toggleSidebarCollapsed()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .help("Expand sidebar")

                statusDot
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .center, spacing: 6) {
                    Text("GearGrind")
                        .font(.headline.bold())
                    Spacer()
                    Button {
                        shell.toggleSidebarCollapsed()
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(8)
                            .background(Circle().fill(Color.secondary.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Collapse sidebar")

                    statusDot
                }

                Text("Agentic System")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        if shell.sidebarCollapsed {
            Circle()
                .fill(monitor.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .frame(width: 38, height: 18)
                .help(monitor.isConnected ? "Connected to harness event stream" : "Harness control-plane unreachable")
        } else if monitor.isConnected {
            LiveBadge()
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 38, height: 18)
                .help("Harness control-plane unreachable")
        }
    }

    private func selectTab(_ tab: ConsoleTab) {
        shell.selectTab(tab)
    }
}

// MARK: - Agent health indicator

struct AgentHealthStrip: View {
    @State private var status: AgentStatus? = nil
    @State private var offline = false
    @State private var loading = true
    @State private var polling: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Runtime Health")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            if offline {
                Label("Server offline", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
                    .padding(.horizontal, 4)
            } else if let s = status {
                HStack(spacing: 6) {
                    agentDot(name: "codex",  info: s.codex)
                    agentDot(name: "kimi",   info: s.kimi)
                    agentDot(name: "claude", info: s.claude)
                    Spacer()
                    if s.pool.total > 0 {
                        Text("\(s.pool.active)A /\(s.pool.idle)I")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .help("Pool: \(s.pool.active) active, \(s.pool.idle) idle sessions")
                    }
                }
                .padding(.horizontal, 4)
            } else {
                Text(loading ? "Checking harness runtime status…" : "Runtime health unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
        .task { startPolling() }
        .onDisappear { polling?.cancel() }
    }

    @ViewBuilder
    private func agentDot(name: String, info: AgentStatus.BinaryInfo) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(info.available ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 10))
                .foregroundStyle(info.available ? .primary : .secondary)
        }
        .help(info.available
            ? "\(name): \(info.path ?? "found")"
            : "\(name): not found in PATH")
    }

    // MARK: Lifecycle

    func startPolling() {
        polling?.cancel()
        polling = Task {
            while !Task.isCancelled {
                do {
                    let s = try await A2AClient.shared.fetchStatus()
                    await MainActor.run { status = s; offline = false; loading = false }
                } catch {
                    // Fallback: /api/status might not be deployed yet — check /health instead
                    let isUp = await A2AClient.shared.ping()
                    await MainActor.run { offline = !isUp; loading = false }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}

struct SidebarButton: View {
    @EnvironmentObject private var shell: AppShellState
    let tab: ConsoleTab
    let isSelected: Bool
    let badge: Int
    let action: () -> Void

    var body: some View {
        if shell.sidebarCollapsed {
            Button(action: action) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.rawValue)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 7)
            .help(tab.rawValue)
        } else {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: tab.icon)
                        .frame(width: 16)
                        .foregroundStyle(isSelected ? .white : .primary)

                    Text(tab.rawValue)
                        .font(.body)
                        .foregroundStyle(isSelected ? .white : .primary)

                    Spacer()

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(isSelected ? Color.white.opacity(0.3) : Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color.clear)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.rawValue)
            .padding(.horizontal, 8)
            .help(tab.rawValue)
        }
    }
}

// MARK: - Task 9: Live connection badge (driven by /api/events SSE health)

struct LiveBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .scaleEffect(pulsing ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }
            Text("Live")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.green)
        }
        .help("Connected to A2A event stream")
    }
}

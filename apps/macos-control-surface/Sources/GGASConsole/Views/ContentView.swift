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
    case terminal      = "Terminal"
    case control       = "Console"
    case dispatch      = "Dispatch"
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
        case .terminal:     return "terminal.fill"
        case .control:      return "cpu.fill"
        case .dispatch:     return "paperplane.fill"
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
                SidebarView(selection: $shell.selectedTab, showUsage: $shell.showUsage)
            } detail: {
                detailView(for: shell.selectedTab)
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 1100, minHeight: 678)
            .sheet(isPresented: $shell.showUsage) {
                UsageView()
                    .frame(minWidth: 720, minHeight: 560)
            }
            .sheet(isPresented: $shell.showLMStudioManager) {
                LMStudioManagerView(initialSearchQuery: shell.lmStudioCatalogQuery)
                    .frame(minWidth: 860, minHeight: 560)
            }

            StatusBarView()
        }
        .frame(minWidth: 1100, minHeight: 700)
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
        case .terminal:     TerminalTabView()
        case .control:      ControlPanelView()
        case .dispatch:     DispatchView()
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
    @Binding var showUsage: Bool
    @EnvironmentObject var forge: ForgeStore
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
        .control,
        .dispatch,
        .packages,
        .skills
    ]

    private let diagnosticTabs: [ConsoleTab] = [
        .trace,
        .liveLog,
        .runHistory,
        .config
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .center, spacing: 6) {
                        Text("GearGrind")
                            .font(.headline.bold())
                        Spacer()
                        Button {
                            showUsage = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Usage and harness capacity")
                        if monitor.isConnected {
                            LiveBadge()
                        } else {
                            Label("Offline", systemImage: "circle.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.red)
                                .help("Harness control-plane unreachable")
                        }
                    }
                    Text("Agentic System")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                sectionHeader("Operate")
                ForEach(primaryTabs) { tab in
                    SidebarButton(
                        tab: tab,
                        isSelected: selection == tab,
                        badge: badgeCount(for: tab)
                    ) {
                        selection = tab
                    }
                }

                sectionHeader("Diagnostics")
                ForEach(diagnosticTabs) { tab in
                    SidebarButton(
                        tab: tab,
                        isSelected: selection == tab,
                        badge: badgeCount(for: tab)
                    ) {
                        selection = tab
                    }
                }

                Divider()
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                AgentHealthStrip()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 220, idealWidth: 236, maxWidth: 250, maxHeight: .infinity, alignment: .topLeading)
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
}

// MARK: - Agent health indicator

struct AgentHealthStrip: View {
    @State private var status: AgentStatus? = nil
    @State private var offline = false
    @State private var polling: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
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
                ProgressView().scaleEffect(0.5).frame(maxWidth: .infinity, alignment: .leading)
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
                    await MainActor.run { status = s; offline = false }
                } catch {
                    // Fallback: /api/status might not be deployed yet — check /health instead
                    let isUp = await A2AClient.shared.ping()
                    await MainActor.run { offline = !isUp }
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}

struct SidebarButton: View {
    let tab: ConsoleTab
    let isSelected: Bool
    let badge: Int
    let action: () -> Void

    var body: some View {
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
        .padding(.horizontal, 8)
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

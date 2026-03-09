// ContentView.swift — Main window with sidebar navigation

import SwiftUI

enum ConsoleTab: String, CaseIterable, Identifiable {
    case runHistory    = "Run History"
    case liveLog       = "Live Log"
    case swarm         = "Swarm"
    case agentTaskBar  = "Agents"
    case skills        = "Skill Analytics"
    case usage         = "Usage"
    case control       = "Control"
    case dispatch      = "Dispatch"
    case trace         = "Trace"
    case tasks         = "Planner"
    case notes         = "Notes"
    case terminal      = "Terminal"
    case packages      = "Packages"
    case config        = "Config"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .runHistory:   return "clock.arrow.circlepath"
        case .liveLog:      return "bolt.fill"
        case .swarm:        return "circle.grid.3x3.fill"
        case .agentTaskBar: return "list.bullet.rectangle.fill"
        case .skills:       return "chart.bar.fill"
        case .usage:        return "gauge.with.dots.needle.67percent"
        case .control:      return "cpu.fill"
        case .dispatch:     return "paperplane.fill"
        case .trace:        return "magnifyingglass"
        case .tasks:        return "checklist"
        case .notes:        return "note.text"
        case .terminal:     return "terminal.fill"
        case .packages:     return "shippingbox.fill"
        case .config:       return "gear"
        }
    }
}

struct ContentView: View {
    @State private var selection: ConsoleTab = .runHistory
    @EnvironmentObject var forge: ForgeStore

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $selection)
            } detail: {
                detailView(for: selection)
            }
            .frame(minWidth: 1100, minHeight: 678)

            StatusBarView()
        }
        .frame(minWidth: 1100, minHeight: 700)
    }

    @ViewBuilder
    private func detailView(for tab: ConsoleTab) -> some View {
        ZStack {
            // Terminal is ALWAYS mounted so jcode processes survive sidebar switches.
            // It is shown when terminal tab is active, hidden otherwise.
            TerminalTabView()
                .opacity(tab == .terminal ? 1 : 0)
                .allowsHitTesting(tab == .terminal)

            // All other tabs are shown/hidden normally via the switch
            if tab != .terminal {
                switch tab {
                case .runHistory:   RunHistoryView()
                case .liveLog:      LiveLogView()
                case .swarm:        SwarmView()
                case .agentTaskBar: AgentTaskBarView()
                case .skills:       SkillAnalyticsView()
                case .usage:        UsageView()
                case .control:      ControlPanelView()
                case .dispatch:     DispatchView()
                case .trace:        TraceView()
                case .tasks:        TasksView()
                case .notes:        NotesView()
                case .packages:     PackagesTabView()
                case .config:       ConfigView()
                case .terminal:     EmptyView()
                }
            }
        }
    }
}

// MARK: - Sidebar (explicit buttons — avoids List selection tap-swallow bug)

struct SidebarView: View {
    @Binding var selection: ConsoleTab
    @EnvironmentObject var forge: ForgeStore
    @ObservedObject private var monitor = AgentMonitorService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .center, spacing: 6) {
                    Text("GearGrind")
                        .font(.headline.bold())
                    Spacer()
                    // Task 9: Live/Offline badge driven by /api/events SSE stream health
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

            ForEach(ConsoleTab.allCases) { tab in
                SidebarButton(
                    tab: tab,
                    isSelected: selection == tab,
                    badge: badgeCount(for: tab)
                ) {
                    selection = tab
                }
            }

            Spacer()

            AgentHealthStrip()
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
        }
        .frame(minWidth: 180)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func badgeCount(for tab: ConsoleTab) -> Int {
        switch tab {
        case .tasks: return forge.tasks.filter { $0.status == "in_progress" }.count
        default: return 0
        }
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

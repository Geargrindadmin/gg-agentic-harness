import AppKit
import SwiftUI
import MarkdownUI

struct IDEWorkspaceView<Content: View>: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    @ObservedObject private var settings = ProjectSettings.shared

    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            centerPane
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            RightInspectorRail(
                activeDocument: shell.activeDocument,
                workspaceRootPath: settings.projectRoot,
                gitWorktreesRootPath: gitWorktreesRootPath,
                selectedRunRootPath: selectedRunRootPath
            )
            .frame(width: shell.rightInspectorCollapsed ? 52 : 252, alignment: .trailing)
            .animation(.easeInOut(duration: 0.18), value: shell.rightInspectorCollapsed)
        }
    }

    private var centerPane: some View {
        VStack(spacing: 0) {
            if !shell.openDocuments.isEmpty {
                IDETabStrip()
                Divider()
            }
            ZStack {
                if let document = shell.activeDocument {
                    IDEDocumentView(
                        document: document,
                        workspaceRootPath: settings.projectRoot,
                        selectedRunRootPath: selectedRunRootPath
                    )
                    .id(document.id)
                } else {
                    content
                }
            }
            if shell.selectedTab != .terminal {
                Divider()
                if shell.ideTerminalDockVisible {
                    IDETerminalDockView(
                        workspaceRootPath: settings.projectRoot,
                        selectedRunRootPath: selectedRunRootPath
                    )
                    .frame(height: 280)
                } else {
                    IDETerminalCollapsedBar(
                        workspaceRootPath: settings.projectRoot,
                        selectedRunRootPath: selectedRunRootPath
                    )
                }
            }
        }
    }

    private var selectedRunRootPath: String? {
        guard let runId = workflow.selectedRunId, !runId.isEmpty else { return nil }
        return "\(settings.projectRoot)/.agent/control-plane/worktrees/\(runId)"
    }

    private var gitWorktreesRootPath: String {
        "\(settings.projectRoot)/.agent/control-plane/worktrees"
    }
}

private struct IDETabStrip: View {
    @EnvironmentObject private var shell: AppShellState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shell.openDocuments) { document in
                    HStack(spacing: 8) {
                        Button {
                            shell.selectDocument(document)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: iconName(for: document.path))
                                    .font(.system(size: 10, weight: .medium))
                                if isDirty(document) {
                                    Circle()
                                        .fill(Color(red: 0.94, green: 0.72, blue: 0.18))
                                        .frame(width: 7, height: 7)
                                }
                                Text(document.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            shell.closeDocument(document)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(shell.activeDocumentId == document.id ? Color.white.opacity(0.09) : Color.white.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(shell.activeDocumentId == document.id ? Color.white.opacity(0.10) : Color.clear, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(white: 0.06))
    }

    private func iconName(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "md", "markdown", "mdx": return "doc.richtext"
        case "swift": return "swift"
        case "ts", "tsx", "js", "jsx": return "chevron.left.forwardslash.chevron.right"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        default: return "doc.plaintext"
        }
    }

    private func isDirty(_ document: IDEDocumentContext) -> Bool {
        DocumentSessionStore.shared.sessionIfLoaded(path: document.path)?.isDirty ?? false
    }
}

private struct RightInspectorRail: View {
    @EnvironmentObject private var shell: AppShellState

    let activeDocument: IDEDocumentContext?
    let workspaceRootPath: String
    let gitWorktreesRootPath: String
    let selectedRunRootPath: String?

    var body: some View {
        HStack(spacing: 0) {
            if !shell.rightInspectorCollapsed {
                railContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(white: 0.10))
                Divider()
            }
            iconRail
        }
        .background(Color(white: 0.08))
    }

    @ViewBuilder
    private var railContent: some View {
        switch shell.idePanelTab {
        case .explorer:
            IDEExplorerView(
                workspaceRootPath: workspaceRootPath,
                gitWorktreesRootPath: gitWorktreesRootPath,
                selectedRunRootPath: selectedRunRootPath
            )
        case .problems:
            IDEProblemsView(
                activeDocument: activeDocument,
                workspaceRootPath: workspaceRootPath,
                selectedRunRootPath: selectedRunRootPath
            )
        case .worktrees:
            IDEWorktreesView(workspaceRootPath: workspaceRootPath)
        case .context:
            IDEContextView(activeDocument: activeDocument, selectedRunRootPath: selectedRunRootPath)
        case .extensions:
            IDEExtensionsView()
        }
    }

    private var iconRail: some View {
        VStack(spacing: 10) {
            Button {
                shell.toggleRightInspectorCollapsed()
            } label: {
                Image(systemName: shell.rightInspectorCollapsed ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .help(shell.rightInspectorCollapsed ? "Expand right rail" : "Collapse right rail")

            ForEach(IDEPanelTab.allCases) { tab in
                Button {
                    shell.idePanelTab = tab
                    if shell.rightInspectorCollapsed {
                        shell.rightInspectorCollapsed = false
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(shell.idePanelTab == tab ? .primary : .secondary)
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(shell.idePanelTab == tab ? Color.white.opacity(0.10) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(tab.rawValue)
            }
            Spacer()
        }
        .frame(width: 52)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background(Color(white: 0.06))
    }
}

private struct IDEExplorerView: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    @StateObject private var store = WorkspaceExplorerStore.shared

    let workspaceRootPath: String
    let gitWorktreesRootPath: String
    let selectedRunRootPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.isLoading {
                Spacer()
                ProgressView("Loading files…")
                Spacer()
            } else if let error = store.error {
                Spacer()
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                ScrollView {
                    OutlineGroup(store.nodes, children: \.children) { node in
                        IDEFileTreeRow(node: node) {
                            UIActionBus.perform(
                                .openDocument(path: node.path, sourceLabel: sourceLabel),
                                shell: shell,
                                workflow: workflow
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
        .task(id: rootPath) {
            await store.load(rootPath: rootPath)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Explorer")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    Task { await store.load(rootPath: rootPath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Picker("Source", selection: $shell.explorerRootMode) {
                ForEach(ExplorerRootMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 11, weight: .medium))

            Text(rootLabel)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            if shell.explorerRootMode == .selectedRun {
                if let runId = workflow.selectedRunId, !runId.isEmpty {
                    Text("Following selected run \(runId)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(red: 0.94, green: 0.72, blue: 0.18))
                } else {
                    Text("No planner/swarm run is selected. The explorer will stay empty until a run is active.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else if shell.explorerRootMode == .focusedWorktree {
                Text("Focused on a specific worktree chosen from the Worktrees rail.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if shell.explorerRootMode == .gitWorktrees {
                Text("Browse every harness-managed git worktree, including swarm worker trees and run sandboxes.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var rootPath: String {
        switch shell.explorerRootMode {
        case .workspace:
            return workspaceRootPath
        case .gitWorktrees:
            return gitWorktreesRootPath
        case .focusedWorktree:
            return shell.focusedWorktreePath ?? ""
        case .selectedRun:
            return selectedRunRootPath ?? ""
        }
    }

    private var rootLabel: String {
        switch shell.explorerRootMode {
        case .workspace:
            return workspaceRootPath.isEmpty ? "Workspace not configured" : workspaceRootPath
        case .gitWorktrees:
            return gitWorktreesRootPath.isEmpty ? "Git worktrees not configured" : gitWorktreesRootPath
        case .focusedWorktree:
            return shell.focusedWorktreePath ?? "No focused worktree"
        case .selectedRun:
            return selectedRunRootPath ?? "No selected run worktree root"
        }
    }

    private var sourceLabel: String {
        switch shell.explorerRootMode {
        case .workspace:
            return "Workspace"
        case .gitWorktrees:
            return "Git Worktrees"
        case .focusedWorktree:
            return shell.focusedWorktreeLabel
        case .selectedRun:
            return workflow.selectedRunId.map { "Run \($0)" } ?? "Selected Run"
        }
    }
}

private struct IDEProblemsView: View {
    let activeDocument: IDEDocumentContext?
    let workspaceRootPath: String
    let selectedRunRootPath: String?

    var body: some View {
        if let activeDocument {
            IDEProblemsDocumentContent(
                activeDocument: activeDocument,
                activeSession: DocumentSessionStore.shared.session(
                    path: activeDocument.path,
                    sourceLabel: activeDocument.sourceLabel,
                    workspaceRootPath: workspaceRootPath,
                    selectedRunRootPath: selectedRunRootPath
                )
            )
            .id("problems:\(activeDocument.id):\(selectedRunRootPath ?? "none")")
        } else {
            IDEProblemsOverviewContent()
        }
    }
}

private struct IDEProblemsDocumentContent: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    @EnvironmentObject private var controlPlane: UIActionBusControlPlane
    @ObservedObject private var monitor = AgentMonitorService.shared
    @ObservedObject private var explorerStore = WorkspaceExplorerStore.shared
    @ObservedObject private var worktreeStore = GitWorktreeStore.shared

    let activeDocument: IDEDocumentContext
    @ObservedObject var activeSession: DocumentViewerStore

    private var problems: [IDEProblem] {
        let selectedRunStatus = workflow.selectedRunId.flatMap { runId in
            monitor.busStatuses.first(where: { $0.runId == runId })
        }
        return IDEProblemCollector.collect(
            activeDocument: activeDocument,
            activeSession: activeSession,
            selectedRunId: workflow.selectedRunId,
            selectedRunStatus: selectedRunStatus,
            monitorLastError: monitor.lastError,
            controlPlaneLastError: controlPlane.lastErrorMessage,
            explorerError: explorerStore.error,
            worktreeError: worktreeStore.error
        )
    }

    var body: some View {
        IDEProblemsListBody(problems: problems)
    }
}

private struct IDEProblemsOverviewContent: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    @EnvironmentObject private var controlPlane: UIActionBusControlPlane
    @ObservedObject private var monitor = AgentMonitorService.shared
    @ObservedObject private var explorerStore = WorkspaceExplorerStore.shared
    @ObservedObject private var worktreeStore = GitWorktreeStore.shared

    private var problems: [IDEProblem] {
        let selectedRunStatus = workflow.selectedRunId.flatMap { runId in
            monitor.busStatuses.first(where: { $0.runId == runId })
        }
        return IDEProblemCollector.collect(
            activeDocument: nil,
            activeSession: nil,
            selectedRunId: workflow.selectedRunId,
            selectedRunStatus: selectedRunStatus,
            monitorLastError: monitor.lastError,
            controlPlaneLastError: controlPlane.lastErrorMessage,
            explorerError: explorerStore.error,
            worktreeError: worktreeStore.error
        )
    }

    var body: some View {
        IDEProblemsListBody(problems: problems)
    }
}

private struct IDEProblemsListBody: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    @State private var guidanceText = ""
    @State private var retaskText = ""
    @State private var actionStatus: String?

    let problems: [IDEProblem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if problems.isEmpty {
                Spacer()
                Text("No active IDE problems in the current context.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(problems) { problem in
                            problemCard(problem)
                        }
                    }
                    .padding(12)
                }
                if let selectedProblem {
                    Divider()
                    VStack(spacing: 0) {
                        quickActionPanel(for: selectedProblem)
                        if hasWorkerControls(selectedProblem) {
                            Divider()
                            workerActionPanel(for: selectedProblem)
                        }
                    }
                }
            }
        }
        .onAppear {
            syncProblemSelection()
            syncDrafts()
        }
        .onChange(of: problems.map(\.id)) { _, _ in
            syncProblemSelection()
            syncDrafts()
        }
        .onChange(of: shell.selectedProblemId) { _, _ in
            syncDrafts()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Problems")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                severitySummary
            }
            Text("Active document state, selected run failures, locks, and shell-control errors are aggregated here for user and agent repair loops.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var severitySummary: some View {
        let errors = problems.filter { $0.severity == .error }.count
        let warnings = problems.filter { $0.severity == .warning }.count
        return HStack(spacing: 6) {
            if errors > 0 {
                problemCountBadge(value: errors, color: Color(red: 1.0, green: 0.35, blue: 0.30))
            }
            if warnings > 0 {
                problemCountBadge(value: warnings, color: Color(red: 0.94, green: 0.72, blue: 0.18))
            }
            if errors == 0 && warnings == 0 {
                problemCountBadge(value: problems.count, color: .secondary)
            }
        }
    }

    private func problemCountBadge(value: Int, color: Color) -> some View {
        Text("\(value)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    private func problemCard(_ problem: IDEProblem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(severityColor(problem.severity))
                    .frame(width: 9, height: 9)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(problem.title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(problem.message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(problem.severity.rawValue.capitalized)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(severityColor(problem.severity))
            }

            if let path = problem.path {
                Text(path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 6) {
                if let runId = problem.runId {
                    problemTag(runId)
                }
                if let agentId = problem.agentId {
                    problemTag(agentId)
                }
            }

            HStack(spacing: 10) {
                if problem.supports(.openDocument), problem.path != nil {
                    Button("Open") {
                        triggerProblemAction(problem, capability: .openDocument, successMessage: nil)
                    }
                    .buttonStyle(.plain)
                }
                if let runId = problem.runId, runId != workflow.selectedRunId {
                    Button("Select Run") {
                        UIActionBus.perform(
                            .selectRun(runId: runId, title: nil, runtime: nil),
                            shell: shell,
                            workflow: workflow
                        )
                    }
                    .buttonStyle(.plain)
                }
                if problem.supports(.focusWorktree), problem.worktreePath != nil {
                    Button("Focus Worktree") {
                        triggerProblemAction(problem, capability: .focusWorktree, successMessage: nil)
                    }
                    .buttonStyle(.plain)
                }
                if problem.supports(.revealInspector), let panel = problem.panel, panel != shell.idePanelTab {
                    Button("Show Panel") {
                        triggerProblemAction(problem, capability: .revealInspector, successMessage: nil)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .medium))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected(problem) ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected(problem) ? Color.white.opacity(0.16) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            UIActionBus.perform(.selectProblem(id: problem.id), shell: shell, workflow: workflow)
        }
    }

    private func severityColor(_ severity: IDEProblemSeverity) -> Color {
        switch severity {
        case .error:
            return Color(red: 1.0, green: 0.35, blue: 0.30)
        case .warning:
            return Color(red: 0.94, green: 0.72, blue: 0.18)
        case .info:
            return Color(red: 0.20, green: 0.75, blue: 1.00)
        }
    }

    private func problemTag(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
            )
    }

    private var selectedProblem: IDEProblem? {
        if let selectedProblemId = shell.selectedProblemId,
           let selected = problems.first(where: { $0.id == selectedProblemId }) {
            return selected
        }
        return problems.first
    }

    private func isSelected(_ problem: IDEProblem) -> Bool {
        problem.id == selectedProblem?.id
    }

    private func syncProblemSelection() {
        guard !problems.isEmpty else {
            if shell.selectedProblemId != nil {
                shell.selectedProblemId = nil
            }
            return
        }

        if let selectedProblemId = shell.selectedProblemId,
           problems.contains(where: { $0.id == selectedProblemId }) {
            return
        }

        shell.selectedProblemId = problems.first?.id
    }

    private func syncDrafts() {
        guard let selectedProblem else {
            guidanceText = ""
            retaskText = ""
            actionStatus = nil
            return
        }

        retaskText = selectedProblem.message
        guidanceText = ""
        actionStatus = nil
    }

    @ViewBuilder
    private func quickActionPanel(for problem: IDEProblem) -> some View {
        let quickActions = quickActionButtons(for: problem)
        if !quickActions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Quick Actions")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    if let statusMessage = actionStatus, !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                FlowLayout(spacing: 8) {
                    ForEach(quickActions, id: \.title) { action in
                        Button(action.title) {
                            triggerProblemAction(
                                problem,
                                capability: action.capability,
                                successMessage: action.successMessage
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func workerActionPanel(for problem: IDEProblem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Worker Controls")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(problem.workerTarget?.runId ?? problem.runId ?? "run") · \(problem.workerTarget?.agentId ?? problem.agentId ?? "worker")")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let statusMessage = actionStatus, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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

            HStack(spacing: 8) {
                Button("Send Guidance") {
                    triggerProblemAction(
                        problem,
                        capability: .sendWorkerGuidance,
                        text: guidanceText,
                        successMessage: "Guidance sent"
                    ) {
                        guidanceText = ""
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    !problem.supports(.sendWorkerGuidance) ||
                    guidanceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                Button("Retask + Retry") {
                    triggerProblemAction(
                        problem,
                        capability: .retaskWorker,
                        text: retaskText,
                        successMessage: "Worker retasked"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(
                    !problem.supports(.retaskWorker) ||
                    retaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            HStack(spacing: 8) {
                Button("Retry Worker") {
                    triggerProblemAction(problem, capability: .retryWorker, successMessage: "Worker retry queued")
                }
                .buttonStyle(.bordered)
                .disabled(!problem.supports(.retryWorker))

                Button("Terminate Worker") {
                    triggerProblemAction(
                        problem,
                        capability: .terminateWorker,
                        text: "Terminated from Problems rail",
                        successMessage: "Worker terminated"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!problem.supports(.terminateWorker))
            }
        }
        .padding(12)
    }

    private func hasWorkerControls(_ problem: IDEProblem) -> Bool {
        problem.supports(.sendWorkerGuidance) ||
        problem.supports(.retryWorker) ||
        problem.supports(.retaskWorker) ||
        problem.supports(.terminateWorker)
    }

    private func triggerProblemAction(
        _ problem: IDEProblem,
        capability: IDEProblemActionCapability,
        text: String? = nil,
        successMessage: String?,
        onSuccess: (() -> Void)? = nil
    ) {
        Task {
            do {
                try await UIActionBus.performAsync(
                    .performProblemAction(
                        problemId: problem.id,
                        capability: capability,
                        text: text,
                        dryRun: false
                    ),
                    shell: shell,
                    workflow: workflow
                )
                actionStatus = successMessage
                onSuccess?()
            } catch {
                actionStatus = error.localizedDescription
            }
        }
    }

    private func quickActionButtons(for problem: IDEProblem) -> [ProblemQuickAction] {
        var actions: [ProblemQuickAction] = []
        if problem.supports(.openDocument) {
            actions.append(.init(title: "Open File", capability: .openDocument, successMessage: nil))
        }
        if problem.supports(.saveDocument) {
            actions.append(.init(title: "Save Draft", capability: .saveDocument, successMessage: "Document saved"))
        }
        if problem.supports(.revertDocument) {
            actions.append(.init(title: "Revert Draft", capability: .revertDocument, successMessage: "Draft reverted"))
        }
        if problem.supports(.applyStagedPatch) {
            actions.append(.init(title: "Apply Patch", capability: .applyStagedPatch, successMessage: "Patch applied"))
        }
        if problem.supports(.discardStagedPatch) {
            actions.append(.init(title: "Discard Patch", capability: .discardStagedPatch, successMessage: "Patch discarded"))
        }
        if problem.supports(.focusWorktree) {
            actions.append(.init(title: "Focus Worktree", capability: .focusWorktree, successMessage: nil))
        }
        if problem.supports(.revealInspector) {
            actions.append(.init(title: "Show Source", capability: .revealInspector, successMessage: nil))
        }
        return actions
    }
}

private struct ProblemQuickAction {
    let title: String
    let capability: IDEProblemActionCapability
    let successMessage: String?
}

private struct IDEContextView: View {
    @EnvironmentObject private var workflow: WorkflowContextStore
    @EnvironmentObject private var controlPlane: UIActionBusControlPlane
    @EnvironmentObject private var rpcService: UIActionBusRPCService

    let activeDocument: IDEDocumentContext?
    let selectedRunRootPath: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                contextCard(title: "Selection") {
                    contextRow("Task", workflow.selectedTaskTitle ?? "None")
                    contextRow("Run", workflow.selectedRunId ?? "None")
                    contextRow("Runtime", workflow.selectedRuntime ?? "None")
                }

                contextCard(title: "Document") {
                    contextRow("Open File", activeDocument?.title ?? "None")
                    contextRow("Source", activeDocument?.sourceLabel ?? "No file open")
                    if let path = activeDocument?.path {
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                contextCard(title: "Worktrees") {
                    contextRow("Selected Run Root", selectedRunRootPath ?? "No selected run")
                    Text("Use the Explorer tab to browse the workspace root or the current run’s worktrees directly from the app shell.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                contextCard(title: "UI Control") {
                    contextRow("Commands", controlPlane.commandsDirectoryURL.path)
                    contextRow("Snapshot", controlPlane.snapshotURL.path)
                    contextRow("RPC Endpoint", rpcService.endpointDescription)
                    contextRow("RPC Status", rpcService.isRunning ? "Listening" : "Stopped")
                    contextRow("Last Command", controlPlane.lastProcessedCommandId ?? "None yet")
                    if let lastError = controlPlane.lastErrorMessage, !lastError.isEmpty {
                        Text(lastError)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    if let rpcError = rpcService.lastErrorMessage, !rpcError.isEmpty {
                        Text(rpcError)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
        }
    }

    private func contextCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    private func contextRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct IDEWorktreesView: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    @ObservedObject private var store = GitWorktreeStore.shared
    let workspaceRootPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.isLoading {
                Spacer()
                ProgressView("Loading worktrees…")
                Spacer()
            } else if let error = store.error {
                Spacer()
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(store.groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                if let subtitle = group.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(group.worktrees) { worktree in
                                    WorktreeCard(
                                        worktree: worktree,
                                        onFocus: {
                                            UIActionBus.perform(
                                                .focusWorktree(path: worktree.path, label: worktree.label),
                                                shell: shell,
                                                workflow: workflow
                                            )
                                        },
                                        onOpenChanged: {
                                            for file in worktree.changedFilesList.prefix(8) {
                                                UIActionBus.perform(
                                                    .openDocument(path: file, sourceLabel: worktree.label),
                                                    shell: shell,
                                                    workflow: workflow
                                                )
                                            }
                                        },
                                        onTerminalHere: {
                                            UIActionBus.perform(
                                                .launchTerminal(
                                                    preset: .zsh,
                                                    workingDirectory: worktree.path,
                                                    title: "zsh • \(worktree.label)",
                                                    destination: .workspaceDock
                                                ),
                                                shell: shell,
                                                workflow: workflow
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .task(id: workspaceRootPath) {
            await store.refresh(projectRoot: workspaceRootPath)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Worktrees")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    Task { await store.refresh(projectRoot: workspaceRootPath) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Text("Browse git worktrees, agent sandboxes, and run-specific trees. Focus one to drive the Explorer.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

private struct WorktreeCard: View {
    let worktree: GitWorktreeSummary
    let onFocus: () -> Void
    let onOpenChanged: () -> Void
    let onTerminalHere: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(worktree.label)
                        .font(.system(size: 11, weight: .semibold))
                    Text(worktree.path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if worktree.isMain {
                    tag("main", color: .secondary)
                } else if worktree.detached {
                    tag("detached", color: .orange)
                } else if let branch = worktree.branch {
                    tag(branch, color: .blue)
                }
            }

            HStack(spacing: 6) {
                if let runId = worktree.runId {
                    tag(runId, color: .purple)
                }
                if let agentId = worktree.agentId {
                    tag(agentId, color: .green)
                }
                if let runtime = worktree.runtime {
                    tag(runtime, color: .cyan)
                }
            }

            HStack(spacing: 10) {
                dirtyBadge
                if let ahead = worktree.aheadCount, let behind = worktree.behindCount {
                    trackingBadge(ahead: ahead, behind: behind)
                }
                Text("\(worktree.changedFilesCount) changed")
                Text("\(worktree.untrackedFilesCount) untracked")
                if worktree.prunable {
                    Text("prunable")
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Focus") { onFocus() }
                    .buttonStyle(.plain)
                Button("Open Changed") { onOpenChanged() }
                    .buttonStyle(.plain)
                    .foregroundStyle(worktree.changedFilesList.isEmpty ? .secondary : .primary)
                    .disabled(worktree.changedFilesList.isEmpty)
                Button("Terminal Here") { onTerminalHere() }
                    .buttonStyle(.plain)
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 10, weight: .medium))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    private var dirtyBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: dirtyIconName)
                .font(.system(size: 9, weight: .semibold))
            Text(dirtyLabel)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(dirtyColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(dirtyColor.opacity(0.12)))
    }

    private func trackingBadge(ahead: Int, behind: Int) -> some View {
        HStack(spacing: 6) {
            Label("\(ahead)", systemImage: "arrow.up")
            Label("\(behind)", systemImage: "arrow.down")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private var dirtyIconName: String {
        if worktree.prunable { return "exclamationmark.triangle.fill" }
        if worktree.changedFilesCount > 0 { return "pencil.line" }
        if worktree.untrackedFilesCount > 0 { return "plus.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var dirtyLabel: String {
        if worktree.prunable { return "prunable" }
        if worktree.changedFilesCount > 0 { return "dirty" }
        if worktree.untrackedFilesCount > 0 { return "new" }
        return "clean"
    }

    private var dirtyColor: Color {
        if worktree.prunable { return .orange }
        if worktree.changedFilesCount > 0 { return .yellow }
        if worktree.untrackedFilesCount > 0 { return .blue }
        return .green
    }
}

private struct IDEExtensionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Extensions")
                .font(.system(size: 13, weight: .semibold))
            Text("This rail is reserved for future agentic IDE tools: plugin surfaces, extension state, and file-aware assistants. The first live tool is Explorer.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                extensionBadge("Explorer", detail: "Local workspace and run worktree browsing")
                extensionBadge("Context", detail: "Task/run/file state linked to the planner and swarm")
                extensionBadge("Future Plugins", detail: "Model helpers, diff tools, and editor assistants")
            }

            Spacer()
        }
        .padding(14)
    }

    private func extensionBadge(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
    }
}

private struct IDEFileTreeRow: View {
    let node: WorkspaceFileNode
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? "folder" : iconName)
                .foregroundStyle(node.isDirectory ? Color(red: 0.94, green: 0.72, blue: 0.18) : .secondary)
                .frame(width: 14)
            Text(node.name)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            Spacer()
            if !node.isDirectory, node.size > 0 {
                Text(byteLabel)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard !node.isDirectory else { return }
            onOpen()
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch node.fileExtension {
        case "md", "markdown", "mdx": return "doc.text"
        case "swift": return "swift"
        case "ts", "tsx", "js", "jsx": return "chevron.left.forwardslash.chevron.right"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        case "sh": return "terminal"
        default: return "doc.plaintext"
        }
    }

    private var byteLabel: String {
        if node.size < 1024 { return "\(node.size)B" }
        if node.size < 1024 * 1024 { return String(format: "%.1fK", Double(node.size) / 1024.0) }
        return String(format: "%.1fM", Double(node.size) / 1_048_576.0)
    }
}

private struct IDEDocumentView: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    let document: IDEDocumentContext
    let workspaceRootPath: String
    let selectedRunRootPath: String?
    @StateObject private var store: DocumentViewerStore

    init(document: IDEDocumentContext, workspaceRootPath: String, selectedRunRootPath: String?) {
        self.document = document
        self.workspaceRootPath = workspaceRootPath
        self.selectedRunRootPath = selectedRunRootPath
        _store = StateObject(
            wrappedValue: DocumentSessionStore.shared.session(
                path: document.path,
                sourceLabel: document.sourceLabel,
                workspaceRootPath: workspaceRootPath,
                selectedRunRootPath: selectedRunRootPath
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            bodyContent
        }
        .background(Color(white: 0.07))
        .task(id: document.path) {
            await store.load()
        }
        .task(id: selectedRunRootPath) {
            store.configure(
                sourceLabel: document.sourceLabel,
                workspaceRootPath: workspaceRootPath,
                selectedRunRootPath: selectedRunRootPath
            )
            await store.load()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.isMarkdown ? "doc.richtext" : "doc.plaintext")
                .foregroundStyle(Color(red: 0.20, green: 0.75, blue: 1.00))
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(document.sourceLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if store.hasStagedPatch {
                Text("Patch Ready")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.75, blue: 1.00))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.20, green: 0.75, blue: 1.00).opacity(0.12))
                    )
            }
            if store.isDirty {
                Text("Unsaved")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.94, green: 0.72, blue: 0.18))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.12))
                    )
            }
            Spacer()
            if store.availableModes.count > 1 {
                Picker("Mode", selection: $store.mode) {
                    ForEach(store.availableModes) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: modePickerWidth)
            }
            if let related = store.relatedDocument {
                Button(related.label) {
                    UIActionBus.perform(
                        .openDocument(path: related.path, sourceLabel: related.label),
                        shell: shell,
                        workflow: workflow
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            if store.hasStagedPatch {
                Button("Discard Patch") {
                    UIActionBus.perform(.discardStagedPatchForActiveDocument, shell: shell, workflow: workflow)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button("Apply Patch") {
                    Task {
                        try? await UIActionBus.performAsync(
                            .applyStagedPatchToActiveDocument,
                            shell: shell,
                            workflow: workflow
                        )
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.isEditable ? .primary : .secondary)
                .disabled(!store.isEditable)
            }
            Button("Revert") {
                Task {
                    try? await UIActionBus.performAsync(.revertActiveDocument, shell: shell, workflow: workflow)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.isDirty ? .secondary : .tertiary)
            .disabled(!store.isDirty)
            Button("Save") {
                Task {
                    try? await UIActionBus.performAsync(.saveActiveDocument, shell: shell, workflow: workflow)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.isDirty && store.isEditable ? .primary : .secondary)
            .disabled(!store.isDirty || !store.isEditable)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: document.path)])
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(document.path, forType: .string)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                shell.closeDocument()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var bodyContent: some View {
        if store.isLoading {
            Spacer()
            ProgressView("Loading file…")
            Spacer()
        } else if let error = store.error {
            Spacer()
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            Spacer()
        } else if store.mode == .diff && store.hasDiff {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 12) {
                    diffBanner
                    Text(store.diffContent)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
        } else if store.mode == .patch && store.hasStagedPatch {
            patchReviewView
        } else if store.mode == .preview && store.isMarkdown {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Markdown(store.content)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                    if store.isTruncated {
                        truncationBanner
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if store.isEditable {
            editorView
        } else {
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 12) {
                    if store.isTruncated {
                        truncationBanner
                    }
                    Text(store.content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(24)
            }
        }
    }

    private var patchReviewView: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 18) {
                patchBanner
                if let error = store.stagedPatchError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Staged Patch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(store.stagedPatch)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Patched Result")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(store.stagedPatchPreviewContent)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }

    private var editorView: some View {
        VStack(spacing: 0) {
            if store.isTruncated {
                truncationBanner
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            CommandTextEditor(
                text: Binding(
                    get: { store.content },
                    set: { store.replaceContent($0) }
                ),
                placeholder: "File contents…",
                font: .monospacedSystemFont(ofSize: 12, weight: .regular)
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }

    private var truncationBanner: some View {
        Text(store.isEditable ? "Editing raw source. Save writes directly to disk." : "Preview truncated at 512 KB for in-app viewing.")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(red: 0.94, green: 0.72, blue: 0.18))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.12))
            )
    }

    private var diffBanner: some View {
        Text("Diff compares the open file against its related workspace/run counterpart.")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(red: 0.20, green: 0.75, blue: 1.00))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.20, green: 0.75, blue: 1.00).opacity(0.12))
            )
    }

    private var patchBanner: some View {
        Text("Review the staged patch before applying it to the editable buffer. Save still writes the resulting draft to disk.")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(red: 0.20, green: 0.75, blue: 1.00))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.20, green: 0.75, blue: 1.00).opacity(0.12))
            )
    }

    private var modePickerWidth: CGFloat {
        if store.hasStagedPatch {
            return 330
        }
        return store.isMarkdown ? 250 : 170
    }
}

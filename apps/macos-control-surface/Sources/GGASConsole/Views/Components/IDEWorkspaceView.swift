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

private struct IDEContextView: View {
    @EnvironmentObject private var workflow: WorkflowContextStore
    @EnvironmentObject private var controlPlane: UIActionBusControlPlane

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
                    contextRow("Last Command", controlPlane.lastProcessedCommandId ?? "None yet")
                    if let lastError = controlPlane.lastErrorMessage, !lastError.isEmpty {
                        Text(lastError)
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
                .frame(width: store.isMarkdown ? 250 : 170)
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
}

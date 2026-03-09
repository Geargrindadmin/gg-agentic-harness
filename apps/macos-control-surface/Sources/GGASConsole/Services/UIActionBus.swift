import Foundation

enum UIActionBusAction: Equatable {
    case selectTab(ConsoleTab)
    case selectRun(runId: String?, title: String?, runtime: String?)
    case clearWorkflowSelection
    case openDocument(path: String, sourceLabel: String)
    case replaceActiveDocumentContent(String)
    case saveActiveDocument
    case revertActiveDocument
    case closeActiveDocument
    case focusWorktree(path: String, label: String)
    case revealInspector(IDEPanelTab)
    case setExplorerRoot(ExplorerRootMode)
    case launchTerminal(
        preset: TerminalSessionPreset,
        workingDirectory: String?,
        title: String?,
        destination: TerminalLaunchDestination
    )
}

struct UIActionBusSnapshot: Equatable, Codable {
    let selectedTab: ConsoleTab
    let activeDocumentPath: String?
    let activeDocumentSourceLabel: String?
    let activeDocumentDirty: Bool
    let activeDocumentEditable: Bool
    let openDocumentPaths: [String]
    let selectedTaskId: String?
    let selectedRunId: String?
    let selectedRuntime: String?
    let idePanelTab: IDEPanelTab
    let explorerRootMode: ExplorerRootMode
    let focusedWorktreePath: String?
    let rightInspectorCollapsed: Bool
    let sidebarCollapsed: Bool
    let terminalDockVisible: Bool
}

@MainActor
enum UIActionBus {
    static func perform(
        _ action: UIActionBusAction,
        shell: AppShellState,
        workflow: WorkflowContextStore
    ) {
        switch action {
        case .selectTab(let tab):
            shell.selectedTab = tab
        case .selectRun(let runId, let title, let runtime):
            workflow.select(runId: runId, title: title, runtime: runtime)
        case .clearWorkflowSelection:
            workflow.clear()
        case .openDocument(let path, let sourceLabel):
            shell.openDocument(path: path, sourceLabel: sourceLabel)
        case .replaceActiveDocumentContent(let content):
            activeDocumentSession(shell: shell, workflow: workflow)?.replaceContent(content)
        case .saveActiveDocument, .revertActiveDocument:
            break
        case .closeActiveDocument:
            shell.closeDocument()
        case .focusWorktree(let path, let label):
            shell.focusWorktree(path: path, label: label)
        case .revealInspector(let panel):
            shell.idePanelTab = panel
            shell.rightInspectorCollapsed = false
        case .setExplorerRoot(let rootMode):
            shell.explorerRootMode = rootMode
            shell.idePanelTab = .explorer
            shell.rightInspectorCollapsed = false
        case .launchTerminal(let preset, let workingDirectory, let title, let destination):
            shell.launchTerminal(
                preset: preset,
                workingDirectory: workingDirectory,
                title: title,
                destination: destination
            )
        }
    }

    static func performAsync(
        _ action: UIActionBusAction,
        shell: AppShellState,
        workflow: WorkflowContextStore
    ) async throws {
        switch action {
        case .saveActiveDocument:
            try await activeDocumentSession(shell: shell, workflow: workflow)?.save()
        case .revertActiveDocument:
            await activeDocumentSession(shell: shell, workflow: workflow)?.revert()
        default:
            perform(action, shell: shell, workflow: workflow)
        }
    }

    static func snapshot(
        shell: AppShellState,
        workflow: WorkflowContextStore
    ) -> UIActionBusSnapshot {
        let activeDocument = shell.activeDocument
        let activeSession = activeDocument.flatMap { _ in
            activeDocumentSession(shell: shell, workflow: workflow)
        }
        return UIActionBusSnapshot(
            selectedTab: shell.selectedTab,
            activeDocumentPath: activeDocument?.path,
            activeDocumentSourceLabel: activeDocument?.sourceLabel,
            activeDocumentDirty: activeSession?.isDirty ?? false,
            activeDocumentEditable: activeSession?.isEditable ?? false,
            openDocumentPaths: shell.openDocuments.map(\.path),
            selectedTaskId: workflow.selectedTaskId,
            selectedRunId: workflow.selectedRunId,
            selectedRuntime: workflow.selectedRuntime,
            idePanelTab: shell.idePanelTab,
            explorerRootMode: shell.explorerRootMode,
            focusedWorktreePath: shell.focusedWorktreePath,
            rightInspectorCollapsed: shell.rightInspectorCollapsed,
            sidebarCollapsed: shell.sidebarCollapsed,
            terminalDockVisible: shell.ideTerminalDockVisible
        )
    }

    private static func activeDocumentSession(
        shell: AppShellState,
        workflow: WorkflowContextStore
    ) -> DocumentViewerStore? {
        guard let activeDocument = shell.activeDocument else { return nil }
        return DocumentSessionStore.shared.session(
            path: activeDocument.path,
            sourceLabel: activeDocument.sourceLabel,
            workspaceRootPath: ProjectSettings.shared.projectRoot,
            selectedRunRootPath: selectedRunRootPath(for: workflow)
        )
    }

    private static func selectedRunRootPath(for workflow: WorkflowContextStore) -> String? {
        guard let runId = workflow.selectedRunId, !runId.isEmpty else { return nil }
        let projectRoot = ProjectSettings.shared.projectRoot
        let trimmed = projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return "\(trimmed)/.agent/control-plane/worktrees/\(runId)"
    }
}

extension ConsoleTab: Codable {}
extension IDEPanelTab: Codable {}
extension ExplorerRootMode: Codable {}
extension TerminalSessionPreset: Codable {}
extension TerminalLaunchDestination: Codable {}

import Foundation

enum UIActionBusAction: Equatable {
    case selectTab(ConsoleTab)
    case selectRun(runId: String?, title: String?, runtime: String?)
    case clearWorkflowSelection
    case selectProblem(id: String?)
    case performProblemAction(
        problemId: String,
        capability: IDEProblemActionCapability,
        text: String?,
        dryRun: Bool
    )
    case openDocument(path: String, sourceLabel: String)
    case replaceActiveDocumentContent(String)
    case stagePatchForActiveDocument(String)
    case applyStagedPatchToActiveDocument
    case discardStagedPatchForActiveDocument
    case saveActiveDocument
    case revertActiveDocument
    case closeActiveDocument
    case focusWorktree(path: String, label: String)
    case sendWorkerGuidance(runId: String, agentId: String, message: String)
    case retryWorker(runId: String, agentId: String, dryRun: Bool)
    case retaskWorker(runId: String, agentId: String, taskSummary: String, dryRun: Bool)
    case terminateWorker(runId: String, agentId: String, reason: String?)
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
    let activeDocumentViewMode: String?
    let activeDocumentDirty: Bool
    let activeDocumentEditable: Bool
    let activeDocumentHasStagedPatch: Bool
    let selectedProblemId: String?
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
    let problems: [IDEProblem]
}

enum UIActionBusError: LocalizedError {
    case problemNotFound(String)
    case unsupportedProblemAction(problemId: String, capability: IDEProblemActionCapability)
    case problemMissingPath(String)
    case problemMissingPanel(String)
    case problemMissingWorktree(String)
    case problemMissingWorkerTarget(String)
    case problemActionRequiresText(IDEProblemActionCapability)

    var errorDescription: String? {
        switch self {
        case .problemNotFound(let problemId):
            return "Problem '\(problemId)' is not present in the current UI snapshot."
        case .unsupportedProblemAction(let problemId, let capability):
            return "Problem '\(problemId)' does not support '\(capability.rawValue)'."
        case .problemMissingPath(let problemId):
            return "Problem '\(problemId)' does not reference a document path."
        case .problemMissingPanel(let problemId):
            return "Problem '\(problemId)' does not expose a source inspector panel."
        case .problemMissingWorktree(let problemId):
            return "Problem '\(problemId)' does not reference a worktree path."
        case .problemMissingWorkerTarget(let problemId):
            return "Problem '\(problemId)' does not expose a worker target."
        case .problemActionRequiresText(let capability):
            return "Problem action '\(capability.rawValue)' requires non-empty text."
        }
    }
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
            shell.selectTab(tab)
        case .selectRun(let runId, let title, let runtime):
            workflow.select(runId: runId, title: title, runtime: runtime)
        case .clearWorkflowSelection:
            workflow.clear()
        case .selectProblem(let id):
            shell.selectProblem(id: id)
        case .performProblemAction:
            break
        case .openDocument(let path, let sourceLabel):
            shell.openDocument(path: path, sourceLabel: sourceLabel)
        case .replaceActiveDocumentContent(let content):
            activeDocumentSession(shell: shell, workflow: workflow)?.replaceContent(content)
        case .discardStagedPatchForActiveDocument:
            activeDocumentSession(shell: shell, workflow: workflow)?.discardStagedPatch()
        case .stagePatchForActiveDocument,
             .applyStagedPatchToActiveDocument,
             .saveActiveDocument,
             .revertActiveDocument,
             .sendWorkerGuidance,
             .retryWorker,
             .retaskWorker,
             .terminateWorker:
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
        workflow: WorkflowContextStore,
        workerControlService: IDEWorkerControlService? = nil
    ) async throws {
        let workerControlService = workerControlService ?? .shared
        switch action {
        case .performProblemAction(let problemId, let capability, let text, let dryRun):
            try await performProblemAction(
                problemId: problemId,
                capability: capability,
                text: text,
                dryRun: dryRun,
                shell: shell,
                workflow: workflow,
                workerControlService: workerControlService
            )
        case .stagePatchForActiveDocument(let patch):
            try await activeDocumentSession(shell: shell, workflow: workflow)?.stagePatch(patch)
        case .applyStagedPatchToActiveDocument:
            activeDocumentSession(shell: shell, workflow: workflow)?.applyStagedPatch()
        case .saveActiveDocument:
            try await activeDocumentSession(shell: shell, workflow: workflow)?.save()
        case .revertActiveDocument:
            await activeDocumentSession(shell: shell, workflow: workflow)?.revert()
        case .sendWorkerGuidance(let runId, let agentId, let message):
            try await workerControlService.sendGuidance(
                to: IDEWorkerTarget(runId: runId, agentId: agentId),
                message: message
            )
        case .retryWorker(let runId, let agentId, let dryRun):
            try await workerControlService.retry(
                target: IDEWorkerTarget(runId: runId, agentId: agentId),
                dryRun: dryRun
            )
        case .retaskWorker(let runId, let agentId, let taskSummary, let dryRun):
            try await workerControlService.retask(
                target: IDEWorkerTarget(runId: runId, agentId: agentId),
                summary: taskSummary,
                dryRun: dryRun
            )
        case .terminateWorker(let runId, let agentId, let reason):
            try await workerControlService.terminate(
                target: IDEWorkerTarget(runId: runId, agentId: agentId),
                reason: reason
            )
        default:
            perform(action, shell: shell, workflow: workflow)
        }
    }

    static func snapshot(
        shell: AppShellState,
        workflow: WorkflowContextStore,
        controlPlaneError: String? = nil
    ) -> UIActionBusSnapshot {
        let activeDocument = shell.activeDocument
        let activeSession = activeDocument.flatMap { _ in
            activeDocumentSession(shell: shell, workflow: workflow)
        }
        let problems = IDEProblemCollector.collect(
            shell: shell,
            workflow: workflow,
            controlPlaneError: controlPlaneError
        )
        return UIActionBusSnapshot(
            selectedTab: shell.selectedTab,
            activeDocumentPath: activeDocument?.path,
            activeDocumentSourceLabel: activeDocument?.sourceLabel,
            activeDocumentViewMode: activeSession?.mode.rawValue,
            activeDocumentDirty: activeSession?.isDirty ?? false,
            activeDocumentEditable: activeSession?.isEditable ?? false,
            activeDocumentHasStagedPatch: activeSession?.hasStagedPatch ?? false,
            selectedProblemId: shell.selectedProblemId,
            openDocumentPaths: shell.openDocuments.map(\.path),
            selectedTaskId: workflow.selectedTaskId,
            selectedRunId: workflow.selectedRunId,
            selectedRuntime: workflow.selectedRuntime,
            idePanelTab: shell.idePanelTab,
            explorerRootMode: shell.explorerRootMode,
            focusedWorktreePath: shell.focusedWorktreePath,
            rightInspectorCollapsed: shell.rightInspectorCollapsed,
            sidebarCollapsed: shell.sidebarCollapsed,
            terminalDockVisible: shell.ideTerminalDockVisible,
            problems: problems
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

    private static func performProblemAction(
        problemId: String,
        capability: IDEProblemActionCapability,
        text: String?,
        dryRun: Bool,
        shell: AppShellState,
        workflow: WorkflowContextStore,
        workerControlService: IDEWorkerControlService
    ) async throws {
        guard let problem = IDEProblemCollector.collect(shell: shell, workflow: workflow).first(where: { $0.id == problemId }) else {
            throw UIActionBusError.problemNotFound(problemId)
        }
        guard problem.supports(capability) else {
            throw UIActionBusError.unsupportedProblemAction(problemId: problemId, capability: capability)
        }

        switch capability {
        case .openDocument:
            guard let path = problem.path else {
                throw UIActionBusError.problemMissingPath(problemId)
            }
            shell.openDocument(path: path, sourceLabel: sourceLabel(for: problem, workflow: workflow))
        case .revealInspector:
            guard let panel = problem.panel else {
                throw UIActionBusError.problemMissingPanel(problemId)
            }
            shell.idePanelTab = panel
            shell.rightInspectorCollapsed = false
        case .focusWorktree:
            guard let worktreePath = problem.worktreePath else {
                throw UIActionBusError.problemMissingWorktree(problemId)
            }
            shell.focusWorktree(
                path: worktreePath,
                label: problem.agentId ?? URL(fileURLWithPath: worktreePath).lastPathComponent
            )
        case .saveDocument:
            try await ensureProblemDocumentIsActive(problem, shell: shell, workflow: workflow)?.save()
        case .revertDocument:
            await ensureProblemDocumentIsActive(problem, shell: shell, workflow: workflow)?.revert()
        case .applyStagedPatch:
            ensureProblemDocumentIsActive(problem, shell: shell, workflow: workflow)?.applyStagedPatch()
        case .discardStagedPatch:
            ensureProblemDocumentIsActive(problem, shell: shell, workflow: workflow)?.discardStagedPatch()
        case .sendWorkerGuidance:
            let workerTarget = try requiredWorkerTarget(for: problem)
            try await workerControlService.sendGuidance(
                to: workerTarget,
                message: try requiredText(text, capability: capability)
            )
        case .retryWorker:
            try await workerControlService.retry(target: try requiredWorkerTarget(for: problem), dryRun: dryRun)
        case .retaskWorker:
            try await workerControlService.retask(
                target: try requiredWorkerTarget(for: problem),
                summary: try requiredText(text, capability: capability),
                dryRun: dryRun
            )
        case .terminateWorker:
            try await workerControlService.terminate(
                target: try requiredWorkerTarget(for: problem),
                reason: optionalText(text)
            )
        }
    }

    private static func ensureProblemDocumentIsActive(
        _ problem: IDEProblem,
        shell: AppShellState,
        workflow: WorkflowContextStore
    ) -> DocumentViewerStore? {
        guard let path = problem.path else { return nil }
        shell.openDocument(path: path, sourceLabel: sourceLabel(for: problem, workflow: workflow))
        return activeDocumentSession(shell: shell, workflow: workflow)
    }

    private static func requiredWorkerTarget(for problem: IDEProblem) throws -> IDEWorkerTarget {
        guard let workerTarget = problem.workerTarget else {
            throw UIActionBusError.problemMissingWorkerTarget(problem.id)
        }
        return workerTarget
    }

    private static func requiredText(
        _ text: String?,
        capability: IDEProblemActionCapability
    ) throws -> String {
        let trimmed = optionalText(text)
        guard let trimmed else {
            throw UIActionBusError.problemActionRequiresText(capability)
        }
        return trimmed
    }

    private static func optionalText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sourceLabel(
        for problem: IDEProblem,
        workflow: WorkflowContextStore
    ) -> String {
        if let runId = problem.runId, !runId.isEmpty {
            return workflow.selectedRunId == runId ? "Selected Run" : "Run \(runId)"
        }
        return problem.panel?.rawValue ?? "Problems"
    }
}

extension ConsoleTab: Codable {}
extension IDEPanelTab: Codable {}
extension ExplorerRootMode: Codable {}
extension TerminalSessionPreset: Codable {}
extension TerminalLaunchDestination: Codable {}

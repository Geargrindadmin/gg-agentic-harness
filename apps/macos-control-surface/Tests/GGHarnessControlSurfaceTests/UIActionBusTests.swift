import Foundation
import Testing
@testable import GGHarnessControlSurface

struct UIActionBusTests {
    @MainActor
    @Test
    func performMutatesShellViaSemanticActions() {
        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()

        UIActionBus.perform(.selectTab(.swarm), shell: shell, workflow: workflow)
        UIActionBus.perform(.revealInspector(.worktrees), shell: shell, workflow: workflow)
        UIActionBus.perform(
            .openDocument(path: "/tmp/run-123/main.swift", sourceLabel: "Run 123"),
            shell: shell,
            workflow: workflow
        )
        UIActionBus.perform(
            .focusWorktree(path: "/tmp/run-123", label: "Run 123"),
            shell: shell,
            workflow: workflow
        )
        UIActionBus.perform(
            .launchTerminal(
                preset: .zsh,
                workingDirectory: "/tmp/run-123",
                title: "zsh • Run 123",
                destination: .workspaceDock
            ),
            shell: shell,
            workflow: workflow
        )

        #expect(shell.selectedTab == .swarm)
        #expect(shell.idePanelTab == .explorer)
        #expect(shell.activeDocument?.path == "/tmp/run-123/main.swift")
        #expect(shell.focusedWorktreePath == "/tmp/run-123")
        #expect(shell.ideTerminalDockVisible == true)
        #expect(shell.pendingTerminalLaunch?.destination == .workspaceDock)
    }

    @MainActor
    @Test
    func performSelectProblemFocusesProblemsRail() {
        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()
        shell.rightInspectorCollapsed = true

        UIActionBus.perform(.selectProblem(id: "worker-failure:run-123:builder-1"), shell: shell, workflow: workflow)

        #expect(shell.selectedProblemId == "worker-failure:run-123:builder-1")
        #expect(shell.idePanelTab == .problems)
        #expect(shell.rightInspectorCollapsed == false)
    }

    @MainActor
    @Test
    func snapshotCapturesVisibleUiContext() {
        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()

        workflow.select(runId: "run-123", title: "Investigate planner drift", runtime: "codex")
        UIActionBus.perform(.selectTab(.tasks), shell: shell, workflow: workflow)
        UIActionBus.perform(.setExplorerRoot(.selectedRun), shell: shell, workflow: workflow)
        UIActionBus.perform(
            .openDocument(path: "/tmp/run-123/Task.md", sourceLabel: "Run 123"),
            shell: shell,
            workflow: workflow
        )
        UIActionBus.perform(
            .launchTerminal(
                preset: .agent,
                workingDirectory: "/tmp/run-123",
                title: "agent • run-123",
                destination: .workspaceDock
            ),
            shell: shell,
            workflow: workflow
        )

        let snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)

        #expect(snapshot.selectedTab == .tasks)
        #expect(snapshot.selectedRunId == "run-123")
        #expect(snapshot.selectedRuntime == "codex")
        #expect(snapshot.activeDocumentPath == "/tmp/run-123/Task.md")
        #expect(snapshot.openDocumentPaths == ["/tmp/run-123/Task.md"])
        #expect(snapshot.explorerRootMode == .selectedRun)
        #expect(snapshot.terminalDockVisible == true)
    }

    @MainActor
    @Test
    func activeDocumentEditingActionsReplaceSaveAndRevertBuffers() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-action-bus-doc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("main.swift")
        try "print(\"before\")\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()

        UIActionBus.perform(
            .openDocument(path: fileURL.path, sourceLabel: "Workspace"),
            shell: shell,
            workflow: workflow
        )
        UIActionBus.perform(
            .replaceActiveDocumentContent("print(\"after\")\n"),
            shell: shell,
            workflow: workflow
        )

        var snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        #expect(snapshot.activeDocumentDirty == true)
        #expect(snapshot.problems.contains(where: { $0.title == "Unsaved changes" }))

        try await UIActionBus.performAsync(.saveActiveDocument, shell: shell, workflow: workflow)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "print(\"after\")\n")

        UIActionBus.perform(
            .replaceActiveDocumentContent("print(\"draft\")\n"),
            shell: shell,
            workflow: workflow
        )
        try await UIActionBus.performAsync(.revertActiveDocument, shell: shell, workflow: workflow)

        snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        #expect(snapshot.activeDocumentDirty == false)
        #expect(snapshot.activeDocumentPath == fileURL.path)
    }

    @MainActor
    @Test
    func activeDocumentPatchActionsStageDiscardAndApplyDraft() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-action-bus-patch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("main.swift")
        try "print(\"before\")\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let patch = """
        --- a/main.swift
        +++ b/main.swift
        @@ -1 +1 @@
        -print("before")
        +print("after")
        """

        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()

        UIActionBus.perform(
            .openDocument(path: fileURL.path, sourceLabel: "Workspace"),
            shell: shell,
            workflow: workflow
        )

        try await UIActionBus.performAsync(
            .stagePatchForActiveDocument(patch),
            shell: shell,
            workflow: workflow
        )

        var snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        #expect(snapshot.activeDocumentHasStagedPatch == true)
        #expect(snapshot.activeDocumentViewMode == "Patch")

        UIActionBus.perform(.discardStagedPatchForActiveDocument, shell: shell, workflow: workflow)

        snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        #expect(snapshot.activeDocumentHasStagedPatch == false)

        try await UIActionBus.performAsync(
            .stagePatchForActiveDocument(patch),
            shell: shell,
            workflow: workflow
        )
        try await UIActionBus.performAsync(
            .applyStagedPatchToActiveDocument,
            shell: shell,
            workflow: workflow
        )

        snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        #expect(snapshot.activeDocumentDirty == true)
        #expect(snapshot.activeDocumentHasStagedPatch == false)
        #expect(
            DocumentSessionStore.shared.sessionIfLoaded(path: fileURL.path)?.content == "print(\"after\")\n"
        )
    }

    @MainActor
    @Test
    func closeActiveDocumentRemovesOnlySelectedEditorTab() {
        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()

        UIActionBus.perform(
            .openDocument(path: "/tmp/worktree-a/main.swift", sourceLabel: "Worker A"),
            shell: shell,
            workflow: workflow
        )
        UIActionBus.perform(
            .openDocument(path: "/tmp/worktree-b/README.md", sourceLabel: "Worker B"),
            shell: shell,
            workflow: workflow
        )

        #expect(shell.openDocuments.count == 2)
        #expect(shell.activeDocument?.path == "/tmp/worktree-b/README.md")

        UIActionBus.perform(.closeActiveDocument, shell: shell, workflow: workflow)

        #expect(shell.openDocuments.count == 1)
        #expect(shell.activeDocument?.path == "/tmp/worktree-a/main.swift")
    }

    @MainActor
    @Test
    func problemTargetedDocumentActionsUseProblemCapabilities() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-action-bus-problem-actions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("main.swift")
        try "print(\"before\")\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let patch = """
        --- a/main.swift
        +++ b/main.swift
        @@ -1 +1 @@
        -print("before")
        +print("after")
        """

        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()

        UIActionBus.perform(
            .openDocument(path: fileURL.path, sourceLabel: "Workspace"),
            shell: shell,
            workflow: workflow
        )
        UIActionBus.perform(
            .replaceActiveDocumentContent("print(\"draft\")\n"),
            shell: shell,
            workflow: workflow
        )

        var snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        let dirtyProblem = try #require(snapshot.problems.first(where: { $0.id == "document-dirty:\(fileURL.path)" }))
        #expect(dirtyProblem.actionCapabilities.contains(.saveDocument))
        #expect(dirtyProblem.actionCapabilities.contains(.revertDocument))

        try await UIActionBus.performAsync(
            .performProblemAction(
                problemId: dirtyProblem.id,
                capability: .revertDocument,
                text: nil,
                dryRun: false
            ),
            shell: shell,
            workflow: workflow
        )

        snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        #expect(snapshot.activeDocumentDirty == false)

        try await UIActionBus.performAsync(
            .stagePatchForActiveDocument(patch),
            shell: shell,
            workflow: workflow
        )

        snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        let stagedPatchProblem = try #require(
            snapshot.problems.first(where: { $0.id == "document-staged-patch:\(fileURL.path)" })
        )
        #expect(stagedPatchProblem.actionCapabilities.contains(.applyStagedPatch))
        #expect(stagedPatchProblem.actionCapabilities.contains(.discardStagedPatch))

        try await UIActionBus.performAsync(
            .performProblemAction(
                problemId: stagedPatchProblem.id,
                capability: .applyStagedPatch,
                text: nil,
                dryRun: false
            ),
            shell: shell,
            workflow: workflow
        )

        snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        #expect(snapshot.activeDocumentHasStagedPatch == false)
        #expect(DocumentSessionStore.shared.sessionIfLoaded(path: fileURL.path)?.content == "print(\"after\")\n")
    }

    @MainActor
    @Test
    func workerSteeringActionsDelegateToWorkerControlService() async throws {
        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()
        var guidanceTarget: IDEWorkerTarget?
        var guidanceMessage: String?
        var retryTarget: IDEWorkerTarget?
        var retaskTarget: IDEWorkerTarget?
        var retaskSummary: String?
        var terminatedTarget: IDEWorkerTarget?
        var terminateReason: String?

        let service = IDEWorkerControlService(
            sendGuidanceHandler: { target, message in
                guidanceTarget = target
                guidanceMessage = message
            },
            retryHandler: { target, _ in
                retryTarget = target
            },
            retaskHandler: { target, summary, _ in
                retaskTarget = target
                retaskSummary = summary
            },
            terminateHandler: { target, reason in
                terminatedTarget = target
                terminateReason = reason
            }
        )

        try await UIActionBus.performAsync(
            .sendWorkerGuidance(runId: "run-123", agentId: "builder-1", message: "Unblock the patch"),
            shell: shell,
            workflow: workflow,
            workerControlService: service
        )
        try await UIActionBus.performAsync(
            .retryWorker(runId: "run-123", agentId: "builder-1", dryRun: true),
            shell: shell,
            workflow: workflow,
            workerControlService: service
        )
        try await UIActionBus.performAsync(
            .retaskWorker(
                runId: "run-123",
                agentId: "builder-1",
                taskSummary: "Reconcile the staged patch with main.swift",
                dryRun: false
            ),
            shell: shell,
            workflow: workflow,
            workerControlService: service
        )
        try await UIActionBus.performAsync(
            .terminateWorker(runId: "run-123", agentId: "builder-1", reason: "Stop failed run"),
            shell: shell,
            workflow: workflow,
            workerControlService: service
        )

        #expect(guidanceTarget == IDEWorkerTarget(runId: "run-123", agentId: "builder-1"))
        #expect(guidanceMessage == "Unblock the patch")
        #expect(retryTarget == IDEWorkerTarget(runId: "run-123", agentId: "builder-1"))
        #expect(retaskTarget == IDEWorkerTarget(runId: "run-123", agentId: "builder-1"))
        #expect(retaskSummary == "Reconcile the staged patch with main.swift")
        #expect(terminatedTarget == IDEWorkerTarget(runId: "run-123", agentId: "builder-1"))
        #expect(terminateReason == "Stop failed run")
    }
}

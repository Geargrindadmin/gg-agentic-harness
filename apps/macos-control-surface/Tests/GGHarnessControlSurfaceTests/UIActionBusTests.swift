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
}

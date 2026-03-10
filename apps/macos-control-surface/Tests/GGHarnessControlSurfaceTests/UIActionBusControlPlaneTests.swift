import Foundation
import Testing
@testable import GGHarnessControlSurface

struct UIActionBusControlPlaneTests {
    @MainActor
    @Test
    func syncNowAppliesQueuedCommandsAndWritesSnapshot() async throws {
        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-action-bus-tests-\(UUID().uuidString)", isDirectory: true)
        let controlPlane = UIActionBusControlPlane(rootURL: rootURL)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }

        controlPlane.bind(shell: shell, workflow: workflow)
        try FileManager.default.createDirectory(at: controlPlane.commandsDirectoryURL, withIntermediateDirectories: true)

        let runCommand = UIActionBusCommandEnvelope(
            id: "cmd-1",
            type: "selectRun",
            runId: "run-123",
            title: "Investigate planner drift",
            runtime: "codex"
        )
        let tabCommand = UIActionBusCommandEnvelope(
            id: "cmd-2",
            type: "selectTab",
            tab: "swarm"
        )

        try JSONEncoder().encode(runCommand).write(to: controlPlane.commandsDirectoryURL.appendingPathComponent("001-select-run.json"))
        try JSONEncoder().encode(tabCommand).write(to: controlPlane.commandsDirectoryURL.appendingPathComponent("002-select-tab.json"))

        let processed = try await controlPlane.syncNow()

        #expect(processed == ["cmd-1", "cmd-2"])
        #expect(workflow.selectedRunId == "run-123")
        #expect(workflow.selectedTaskTitle == "Investigate planner drift")
        #expect(workflow.selectedRuntime == "codex")
        #expect(shell.selectedTab == .swarm)

        let snapshotData = try Data(contentsOf: controlPlane.snapshotURL)
        let snapshot = try JSONDecoder().decode(UIActionBusSnapshot.self, from: snapshotData)
        #expect(snapshot.selectedRunId == "run-123")
        #expect(snapshot.selectedRuntime == "codex")
        #expect(snapshot.selectedTab == .swarm)

        let remainingCommands = try FileManager.default.contentsOfDirectory(
            at: controlPlane.commandsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        #expect(remainingCommands.isEmpty)
    }

    @Test
    func commandEnvelopeResolvesAliasBasedTerminalLaunch() throws {
        let envelope = UIActionBusCommandEnvelope(
            id: "cmd-3",
            type: "launchTerminal",
            title: "agent • run-123",
            preset: "agent",
            workingDirectory: "/tmp/run-123",
            destination: "dock"
        )

        let action = try envelope.resolvedAction()
        let expected: UIActionBusAction = .launchTerminal(
            preset: .agent,
            workingDirectory: "/tmp/run-123",
            title: "agent • run-123",
            destination: .workspaceDock
        )

        #expect(action == expected)
    }

    @Test
    func commandEnvelopeResolvesUsageTabAlias() throws {
        let envelope = UIActionBusCommandEnvelope(
            id: "cmd-4",
            type: "selectTab",
            tab: "usage"
        )

        let action = try envelope.resolvedAction()

        #expect(action == .selectTab(.usage))
    }

    @Test
    func commandEnvelopeResolvesPatchStageAlias() throws {
        let patch = """
        --- a/main.swift
        +++ b/main.swift
        @@ -1 +1 @@
        -print("before")
        +print("after")
        """
        let envelope = UIActionBusCommandEnvelope(
            id: "cmd-5",
            type: "queueActiveDocumentPatch",
            patch: patch
        )

        let action = try envelope.resolvedAction()

        #expect(action == .stagePatchForActiveDocument(patch))
    }

    @Test
    func commandEnvelopeResolvesProblemsInspectorAlias() throws {
        let envelope = UIActionBusCommandEnvelope(
            id: "cmd-6",
            type: "revealInspector",
            panel: "problems"
        )

        let action = try envelope.resolvedAction()

        #expect(action == .revealInspector(.problems))
    }

    @Test
    func commandEnvelopeResolvesSelectProblemAlias() throws {
        let envelope = UIActionBusCommandEnvelope(
            id: "cmd-7",
            type: "selectProblem",
            problemId: "worker-failure:run-123:builder-1"
        )

        let action = try envelope.resolvedAction()

        #expect(action == .selectProblem(id: "worker-failure:run-123:builder-1"))
    }

    @Test
    func commandEnvelopeResolvesRetryWorkerAlias() throws {
        let envelope = UIActionBusCommandEnvelope(
            id: "cmd-8",
            type: "retryWorker",
            runId: "run-123",
            agentId: "builder-1",
            dryRun: true
        )

        let action = try envelope.resolvedAction()

        #expect(action == .retryWorker(runId: "run-123", agentId: "builder-1", dryRun: true))
    }

    @Test
    func commandEnvelopeResolvesGenericProblemAction() throws {
        let envelope = UIActionBusCommandEnvelope(
            id: "cmd-9",
            type: "performProblemAction",
            dryRun: true,
            problemId: "worker-failure:run-123:builder-1",
            problemAction: "retryWorker"
        )

        let action = try envelope.resolvedAction()

        #expect(
            action == .performProblemAction(
                problemId: "worker-failure:run-123:builder-1",
                capability: .retryWorker,
                text: nil,
                dryRun: true
            )
        )
    }

    @Test
    func commandEnvelopeResolvesProblemWorkerAlias() throws {
        let envelope = UIActionBusCommandEnvelope(
            id: "cmd-10",
            type: "retaskProblemWorker",
            text: "Retry the patch with the updated base file",
            dryRun: false,
            problemId: "worker-failure:run-123:builder-1"
        )

        let action = try envelope.resolvedAction()

        #expect(
            action == .performProblemAction(
                problemId: "worker-failure:run-123:builder-1",
                capability: .retaskWorker,
                text: "Retry the patch with the updated base file",
                dryRun: false
            )
        )
    }
}

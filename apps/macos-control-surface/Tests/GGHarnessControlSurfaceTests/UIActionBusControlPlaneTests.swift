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
}

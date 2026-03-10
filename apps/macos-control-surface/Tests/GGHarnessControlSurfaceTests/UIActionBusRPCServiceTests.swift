import Foundation
import Testing
@testable import GGHarnessControlSurface

struct UIActionBusRPCServiceTests {
    @MainActor
    @Test
    func snapshotRequestReturnsCurrentUiSnapshot() async throws {
        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()
        workflow.select(runId: "run-123", title: "Repair planner", runtime: "codex")

        let request = UIActionBusRPCRequest(type: .snapshot)
        let response = await UIActionBusRPCService.handle(request, shell: shell, workflow: workflow)

        #expect(response.ok == true)
        #expect(response.processedCommandId == nil)
        #expect(response.snapshot?.selectedRunId == "run-123")
        #expect(response.snapshot?.selectedRuntime == "codex")
    }

    @MainActor
    @Test
    func commandRequestExecutesSemanticActionAndReturnsUpdatedSnapshot() async throws {
        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()
        let request = UIActionBusRPCRequest(
            type: .command,
            command: UIActionBusCommandEnvelope(
                id: "rpc-1",
                type: "selectTab",
                tab: "swarm"
            )
        )

        let response = await UIActionBusRPCService.handle(request, shell: shell, workflow: workflow)

        #expect(response.ok == true)
        #expect(response.processedCommandId == "rpc-1")
        #expect(shell.selectedTab == .swarm)
        #expect(response.snapshot?.selectedTab == .swarm)
    }

    @MainActor
    @Test
    func invalidCommandRequestReturnsStructuredError() async throws {
        let shell = AppShellState()
        let workflow = WorkflowContextStore.testingInstance()
        let request = UIActionBusRPCRequest(
            type: .command,
            command: UIActionBusCommandEnvelope(
                id: "rpc-2",
                type: "openDocument"
            )
        )

        let response = await UIActionBusRPCService.handle(request, shell: shell, workflow: workflow)

        #expect(response.ok == false)
        #expect(response.processedCommandId == "rpc-2")
        #expect(response.error?.contains("path") == true)
    }
}

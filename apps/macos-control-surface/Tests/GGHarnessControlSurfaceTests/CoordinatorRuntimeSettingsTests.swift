import Testing
@testable import GGHarnessControlSurface

struct CoordinatorRuntimeSettingsTests {
    @Test
    func switchingWorkerRuntimePreservesTopologyAndResetsDefaultModelWhenAppropriate() {
        var settings = CoordinatorRuntimeSettings()
        settings.setWorkerTopology(.team)
        settings.setWorkerRuntime(.codex)

        #expect(settings.selectedWorkerRuntime == .codex)
        #expect(settings.selectedWorkerTopology == .team)
        #expect(settings.workerBackend == "codex-swarm")
        #expect(settings.dispatchPath == "codex-swarm")
        #expect(settings.workerModel == "gpt-5.3-codex")
        #expect(settings.bridgeAgents >= 3)
    }

    @Test
    func workerPlanLabelReflectsSingleVsTeamModes() {
        var settings = CoordinatorRuntimeSettings()
        settings.setWorkerRuntime(.claude)
        settings.setWorkerTopology(.single)
        #expect(settings.workerPlanLabel == "Claude Code Single")

        settings.setWorkerTopology(.team)
        settings.bridgeAgents = 4
        #expect(settings.workerPlanLabel == "Claude Code Team ×4")
    }

    @Test
    func recommendedRolesReflectHarnessDefaultTeamPlanUntilExplicitOverride() {
        var settings = CoordinatorRuntimeSettings()
        settings.setWorkerTopology(.team)
        settings.bridgeAgents = 4

        #expect(settings.usesExplicitWorkerRoles == false)
        #expect(settings.recommendedWorkerRoles == [.scout, .builder, .reviewer, .planner])
        #expect(settings.effectiveWorkerRoles == [.scout, .builder, .reviewer, .planner])
        #expect(settings.bridgeRolesForDispatch == nil)
        #expect(settings.effectiveBridgeAgentsForDispatch == 4)
    }

    @Test
    func togglingRoleCreatesExplicitRolePlanAndSyncsDispatchCount() {
        var settings = CoordinatorRuntimeSettings()
        settings.setWorkerTopology(.team)
        settings.bridgeAgents = 3

        settings.toggleWorkerRole(.specialist)

        #expect(settings.usesExplicitWorkerRoles == true)
        #expect(settings.selectedWorkerRoles == [.scout, .builder, .reviewer, .specialist])
        #expect(settings.bridgeRolesForDispatch == ["scout", "builder", "reviewer", "specialist"])
        #expect(settings.effectiveBridgeAgentsForDispatch == 4)

        settings.resetWorkerRolesToHarnessDefault()

        #expect(settings.usesExplicitWorkerRoles == false)
        #expect(settings.bridgeRolesForDispatch == nil)
    }

    @MainActor
    @Test
    func lmStudioEndpointAccessorUpdatesWithoutDirectArrayBinding() {
        let manager = CoordinatorManager.shared
        let original = manager.lmStudioEndpoint
        let replacement = "http://localhost:4321"
        defer { manager.setLMStudioEndpoint(original) }

        manager.setLMStudioEndpoint(replacement)

        #expect(manager.lmStudioEndpoint == replacement)
    }
}

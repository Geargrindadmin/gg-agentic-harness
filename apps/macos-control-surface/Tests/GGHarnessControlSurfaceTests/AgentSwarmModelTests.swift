import Foundation
import Testing
@testable import GGHarnessControlSurface

@MainActor
struct AgentSwarmModelTests {
    @Test
    func ingestBusStatusBuildsCoordinatorManagersWorkersAndCounts() throws {
        let model = AgentSwarmModel.shared
        model.reset()
        let status = try JSONDecoder.ggasDecoder.decode(BusRunStatus.self, from: FixtureControlPlaneData.busStatus)

        model.ingestBusStatus([status])

        #expect(model.coordinatorStatus == .running)
        #expect(model.coordinatorLabel == "claude")
        #expect(model.managers.count == 1)
        #expect(model.managers.first?.id == "run-fixture")
        #expect(model.managers.first?.workers.count == 1)
        #expect(model.managers.first?.workers.first?.id == "builder-1")
        #expect(model.managers.first?.workers.first?.worktreePath == "/tmp/run-fixture/builder-1")
        #expect(model.totalRunning == 1)
        #expect(model.totalDone == 0)
        #expect(model.totalFailed == 0)
    }

    @Test
    func activeCommLinksProduceGraphEdgesBetweenKnownNodes() throws {
        let model = AgentSwarmModel.shared
        model.reset()
        let status = try JSONDecoder.ggasDecoder.decode(BusRunStatus.self, from: FixtureControlPlaneData.busStatus)

        model.ingestBusStatus([status])
        model.ingestAgentMsg(from: "builder-1", to: "run-fixture")

        let nodes = model.computeGraphNodes(in: CGSize(width: 900, height: 600))
        let edges = model.computeGraphEdges(nodes: nodes)

        #expect(edges.contains(where: { $0.fromId == "coordinator" && $0.toId == "manager-run-fixture" }))
        #expect(edges.contains(where: { $0.fromId == "manager-run-fixture" && $0.toId == "builder-1" }))
        #expect(edges.contains(where: { $0.fromId == "builder-1" && $0.toId == "manager-run-fixture" && $0.isActive }))
    }
}

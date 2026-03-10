import Foundation
import Testing
@testable import GGHarnessControlSurface

@Suite(.serialized)
@MainActor
struct A2AClientTests {
    private func withFixtureSession(_ body: () async throws -> Void) async throws {
        await A2AClientFixtureGate.shared.acquire()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        A2AClient.shared.configureForTesting(baseURL: "http://fixture-control-plane", session: session)
        defer {
            FixtureURLProtocol.handlers = [:]
            A2AClient.shared.resetTestingOverrides()
            Task { await A2AClientFixtureGate.shared.release() }
        }
        try await body()
    }

    @Test
    func fetchAgentAnalyticsDecodesCoordinatorRuntimeAndPersonaUsage() async throws {
        try await withFixtureSession {
            FixtureURLProtocol.handlers["/api/agent-analytics"] = (200, FixtureControlPlaneData.agentAnalytics)

            let analytics = try await A2AClient.shared.fetchAgentAnalytics()

            #expect(analytics.summary.totalRuns == 5)
            #expect(analytics.summary.distinctRuntimes == 3)
            #expect(analytics.coordinators.first?.key == "codex")
            #expect(analytics.workerRuntimes.first?.calls == 9)
            #expect(analytics.personas.first?.key == "backend-specialist")
        }
    }

    @Test
    func fetchBusStatusDecodesTelemetryAndSelectedWorkerFields() async throws {
        try await withFixtureSession {
            FixtureURLProtocol.handlers["/api/bus/run-fixture/status"] = (200, FixtureControlPlaneData.busStatus)

            let status = try await A2AClient.shared.fetchBusStatus(runId: "run-fixture")

            #expect(status.runId == "run-fixture")
            #expect(status.telemetry?.coordinatorRuntime == "claude")
            #expect(status.telemetry?.runtimeBreakdown.first?.key == "codex")
            #expect(status.workers["builder-1"]?.runtime == "codex")
            #expect(status.workers["builder-1"]?.personaId == "backend-specialist")
            #expect(status.workers["builder-1"]?.launchTransport == "background-terminal")
        }
    }

    @Test
    func fetchPlannerSnapshotDecodesTaskRunLinksAndNotes() async throws {
        try await withFixtureSession {
            FixtureURLProtocol.handlers["/api/planner"] = (200, FixtureControlPlaneData.plannerSnapshot)

            let snapshot = try await A2AClient.shared.fetchPlannerSnapshot()

            #expect(snapshot.project.id == "project-1")
            #expect(snapshot.tasks.count == 1)
            #expect(snapshot.tasks.first?.runId == "run-fixture")
            #expect(snapshot.tasks.first?.runtime == "codex")
            #expect(snapshot.tasks.first?.assignedAgentId == "builder-1")
            #expect(snapshot.notes.first?.taskId == "task-1")
            #expect(snapshot.counts.inProgress == 1)
        }
    }

    @Test
    func replayEndpointsDecodeSourcesSessionsAndRenderPayload() async throws {
        try await withFixtureSession {
            FixtureURLProtocol.handlers["/api/replays/sources"] = (200, FixtureControlPlaneData.replaySources)
            FixtureURLProtocol.handlers["/api/replays/sessions"] = (200, FixtureControlPlaneData.replaySessions)
            FixtureURLProtocol.handlers["/api/replays/render"] = (200, FixtureControlPlaneData.replayRender)

            let sources = try await A2AClient.shared.fetchReplaySources()
            let sessions = try await A2AClient.shared.fetchReplaySessions(limit: 25)
            let render = try await A2AClient.shared.renderReplay(path: "/Users/shawn/.claude/projects/demo/session.jsonl")

            #expect(sources.count == 1)
            #expect(sources.first?.key == "claude")
            #expect(sessions.first?.turnCount == 42)
            #expect(render.sessionId == "session-1")
            #expect(render.outputPath == "/tmp/replays/session-1.html")
        }
    }

    @Test
    func modelFitAndFreeModelEndpointsDecodeHarnessCatalogData() async throws {
        try await withFixtureSession {
            FixtureURLProtocol.handlers["/api/model-fit/recommendations"] = (200, FixtureControlPlaneData.modelFit)
            FixtureURLProtocol.handlers["/api/free-models/catalog"] = (200, FixtureControlPlaneData.freeModels)

            let fit = try await A2AClient.shared.fetchModelFitRecommendations(limit: 10)
            let freeModels = try await A2AClient.shared.fetchFreeModelsCatalog()

            #expect(fit.available)
            #expect(fit.recommendations.first?.lmStudioQuery == "Qwen2.5 Coder 7B")
            #expect(freeModels.totalProviders == 1)
            #expect(freeModels.providers.first?.models.first?.label == "Qwen 2.5 Coder 32B Instruct")
        }
    }

    @Test
    func harnessSettingsAndDiagramDecodeHeadlessControlPlanePayloads() async throws {
        try await withFixtureSession {
            FixtureURLProtocol.handlers["/api/harness/settings"] = (200, FixtureControlPlaneData.harnessSettings)
            FixtureURLProtocol.handlers["/api/harness/diagram"] = (200, FixtureControlPlaneData.harnessDiagram)

            let settings = try await A2AClient.shared.fetchHarnessSettings()
            let diagram = try await A2AClient.shared.fetchHarnessDiagram()

            #expect(settings.execution.loopBudget == 28)
            #expect(settings.execution.promptImproverMode == "force")
            #expect(settings.governor.cpuHighPct == 90)
            #expect(diagram.diagram.artifactRelativePath == "docs/architecture/agentic-harness-dynamic-user-diagram.html")
            #expect(diagram.live.activity.runningRuns == 2)
            #expect(diagram.live.status.governor.allowedAgents == 6)
        }
    }
}

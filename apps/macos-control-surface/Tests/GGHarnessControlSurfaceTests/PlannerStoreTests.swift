import Foundation
import Testing
@testable import GGHarnessControlSurface

@Suite(.serialized)
@MainActor
struct PlannerStoreTests {
    @Test
    func reloadHydratesProjectTasksNotesAndCounts() async throws {
        await A2AClientFixtureGate.shared.acquire()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        A2AClient.shared.configureForTesting(baseURL: "http://fixture-planner", session: session)
        defer {
            FixtureURLProtocol.handlers = [:]
            A2AClient.shared.resetTestingOverrides()
            Task { await A2AClientFixtureGate.shared.release() }
        }

        FixtureURLProtocol.handlers["fixture-planner/api/planner"] = (200, FixtureControlPlaneData.plannerSnapshot)

        let store = PlannerStore(autoStart: false)
        await store.reload()

        #expect(store.project?.id == "project-1")
        #expect(store.tasks.count == 1)
        #expect(store.notes.count == 1)
        #expect(store.counts.inProgress == 1)
        #expect(store.isAvailable == true)
        #expect(store.lastError == nil)
        #expect(store.openTasks.count == 1)
    }

    @Test
    func createTaskRefreshesSnapshotAndReturnsCreatedTask() async throws {
        await A2AClientFixtureGate.shared.acquire()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        A2AClient.shared.configureForTesting(baseURL: "http://fixture-planner-create", session: session)
        defer {
            FixtureURLProtocol.handlers = [:]
            A2AClient.shared.resetTestingOverrides()
            Task { await A2AClientFixtureGate.shared.release() }
        }

        FixtureURLProtocol.handlers["fixture-planner-create/api/planner/tasks"] = (
            200,
            Data(
                """
                {
                  "task": {
                    "id": "task-new",
                    "projectId": "project-1",
                    "title": "New task",
                    "description": "Created from test",
                    "status": "todo",
                    "priority": 2,
                    "source": "planner-ui",
                    "sourceSession": null,
                    "labels": ["test"],
                    "attachments": [],
                    "isGlobal": false,
                    "runId": null,
                    "runtime": "codex",
                    "linkedRunStatus": null,
                    "assignedAgentId": null,
                    "worktreePath": null,
                    "createdAt": "2026-03-09T12:10:00.000Z",
                    "updatedAt": "2026-03-09T12:10:00.000Z",
                    "completedAt": null,
                    "notes": []
                  }
                }
                """.utf8
            )
        )
        FixtureURLProtocol.handlers["fixture-planner-create/api/planner"] = (
            200,
            Data(
                """
                {
                  "project": {
                    "id": "project-1",
                    "name": "GG Harness",
                    "root": "/Users/shawn/Documents/gg-agentic-harness"
                  },
                  "tasks": [
                    {
                      "id": "task-new",
                      "projectId": "project-1",
                      "title": "New task",
                      "description": "Created from test",
                      "status": "todo",
                      "priority": 2,
                      "source": "planner-ui",
                      "sourceSession": null,
                      "labels": ["test"],
                      "attachments": [],
                      "isGlobal": false,
                      "runId": null,
                      "runtime": "codex",
                      "linkedRunStatus": null,
                      "assignedAgentId": null,
                      "worktreePath": null,
                      "createdAt": "2026-03-09T12:10:00.000Z",
                      "updatedAt": "2026-03-09T12:10:00.000Z",
                      "completedAt": null,
                      "notes": []
                    }
                  ],
                  "notes": [],
                  "counts": {
                    "todo": 1,
                    "inProgress": 0,
                    "done": 0,
                    "archived": 0
                  },
                  "updatedAt": "2026-03-09T12:10:00.000Z"
                }
                """.utf8
            )
        )

        let store = PlannerStore(autoStart: false)
        let created = try await store.createTask(
            title: "New task",
            description: "Created from test",
            status: "todo",
            priority: 2,
            labels: ["test"],
            runtime: "codex"
        )

        #expect(created.id == "task-new")
        #expect(store.tasks.map(\.id) == ["task-new"])
        #expect(store.counts.todo == 1)
    }
}

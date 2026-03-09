import Testing
@testable import GGHarnessControlSurface

@MainActor
struct WorkflowContextStoreTests {
    @Test
    func selectingTaskCopiesPlannerSelectionIntoSharedWorkflowContext() {
        let store = WorkflowContextStore.shared
        store.clear()

        let task = PlannerTask(
            id: "task-1",
            projectId: "project-1",
            title: "Stabilize planner workflow",
            description: "Tie planner selection to swarm context",
            status: "in_progress",
            priority: 3,
            source: "planner",
            sourceSession: nil,
            labels: ["planner", "swarm"],
            attachments: [],
            isGlobal: false,
            runId: "run-123",
            runtime: "codex",
            linkedRunStatus: "running",
            assignedAgentId: "builder-1",
            worktreePath: "/tmp/run-123/builder-1",
            createdAt: "2026-03-09T10:00:00Z",
            updatedAt: "2026-03-09T10:05:00Z",
            completedAt: nil,
            notes: []
        )

        store.select(task: task)

        #expect(store.selectedTaskId == "task-1")
        #expect(store.selectedTaskTitle == "Stabilize planner workflow")
        #expect(store.selectedTaskStatus == "in_progress")
        #expect(store.selectedRunId == "run-123")
        #expect(store.selectedRuntime == "codex")
    }

    @Test
    func syncingTasksRefreshesMatchingSelectionAndClearsStaleSelection() {
        let store = WorkflowContextStore.shared
        store.clear()
        store.select(runId: "run-123", title: "Planner kickoff", runtime: "claude")

        let refreshedTask = PlannerTask(
            id: "task-2",
            projectId: "project-1",
            title: "Planner kickoff",
            description: nil,
            status: "done",
            priority: 2,
            source: "planner",
            sourceSession: nil,
            labels: [],
            attachments: [],
            isGlobal: false,
            runId: "run-123",
            runtime: "kimi",
            linkedRunStatus: "complete",
            assignedAgentId: nil,
            worktreePath: nil,
            createdAt: "2026-03-09T11:00:00Z",
            updatedAt: "2026-03-09T11:15:00Z",
            completedAt: "2026-03-09T11:15:00Z",
            notes: []
        )

        store.sync(tasks: [refreshedTask])

        #expect(store.selectedTaskId == "task-2")
        #expect(store.selectedTaskStatus == "done")
        #expect(store.selectedRuntime == "kimi")

        store.sync(tasks: [])

        #expect(store.selectedTaskId == nil)
        #expect(store.selectedTaskTitle == nil)
        #expect(store.selectedTaskStatus == nil)
        #expect(store.selectedRunId == nil)
        #expect(store.selectedRuntime == nil)
    }
}

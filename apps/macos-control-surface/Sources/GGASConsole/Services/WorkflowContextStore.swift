import Foundation

@MainActor
final class WorkflowContextStore: ObservableObject {
    static let shared = WorkflowContextStore()

    @Published var selectedTaskId: String?
    @Published var selectedTaskTitle: String?
    @Published var selectedTaskStatus: String?
    @Published var selectedRunId: String?
    @Published var selectedRuntime: String?

    private init() {}

    var hasSelection: Bool {
        selectedTaskId != nil || selectedRunId != nil
    }

    func select(task: PlannerTask) {
        selectedTaskId = task.id
        selectedTaskTitle = task.title
        selectedTaskStatus = task.status
        selectedRunId = task.runId
        selectedRuntime = task.runtime
    }

    func select(runId: String?, title: String? = nil, runtime: String? = nil) {
        selectedRunId = runId
        if let title {
            selectedTaskTitle = title
        }
        if let runtime {
            selectedRuntime = runtime
        }
    }

    func clear() {
        selectedTaskId = nil
        selectedTaskTitle = nil
        selectedTaskStatus = nil
        selectedRunId = nil
        selectedRuntime = nil
    }

    func sync(tasks: [PlannerTask]) {
        if let taskId = selectedTaskId, let task = tasks.first(where: { $0.id == taskId }) {
            selectedTaskTitle = task.title
            selectedTaskStatus = task.status
            selectedRunId = task.runId
            selectedRuntime = task.runtime
            return
        }

        if let runId = selectedRunId, let task = tasks.first(where: { $0.runId == runId }) {
            selectedTaskId = task.id
            selectedTaskTitle = task.title
            selectedTaskStatus = task.status
            selectedRuntime = task.runtime
            return
        }

        if !tasks.contains(where: { $0.id == selectedTaskId || $0.runId == selectedRunId }) {
            clear()
        }
    }
}


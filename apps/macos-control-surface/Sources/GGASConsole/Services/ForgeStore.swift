// PlannerStore.swift — harness-owned planner/tasks/notes client.
// Keeps the macOS app optional by storing planner state in the headless control-plane.

import Foundation

@MainActor
final class PlannerStore: ObservableObject {
    @Published var project: PlannerProject?
    @Published var tasks: [PlannerTask] = []
    @Published var notes: [PlannerNote] = []
    @Published var counts = PlannerCounts(todo: 0, inProgress: 0, done: 0, archived: 0)
    @Published var isAvailable = false
    @Published var isLoading = false
    @Published var lastError: String?
    private var runEventTask: Task<Void, Never>?

    init(autoStart: Bool = true) {
        if autoStart {
            refresh()
            startRunEventSync()
        }
    }

    func refresh() {
        Task { await reload() }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await A2AClient.shared.fetchPlannerSnapshot()
            project = snapshot.project
            tasks = snapshot.tasks
            notes = snapshot.notes
            counts = snapshot.counts
            isAvailable = true
            lastError = nil
        } catch {
            isAvailable = false
            lastError = error.localizedDescription
        }
    }

    func createTask(
        title: String,
        description: String? = nil,
        status: String = "todo",
        priority: Int = 0,
        labels: [String] = [],
        runId: String? = nil,
        runtime: String? = nil
    ) async throws -> PlannerTask {
        let task = try await A2AClient.shared.createPlannerTask(
            title: title,
            description: description,
            status: status,
            priority: priority,
            labels: labels,
            runId: runId,
            runtime: runtime
        )
        await reload()
        return task
    }

    func updateTask(_ task: PlannerTask) async throws {
        _ = try await A2AClient.shared.updatePlannerTask(task)
        await reload()
    }

    func deleteTask(_ taskId: String) async throws {
        try await A2AClient.shared.deletePlannerTask(taskId: taskId)
        await reload()
    }

    func createNote(
        title: String? = nil,
        content: String,
        pinned: Bool = false,
        taskId: String? = nil
    ) async throws -> PlannerNote {
        let note = try await A2AClient.shared.createPlannerNote(
            title: title,
            content: content,
            pinned: pinned,
            taskId: taskId
        )
        await reload()
        return note
    }

    func updateNote(_ note: PlannerNote) async throws {
        _ = try await A2AClient.shared.updatePlannerNote(note)
        await reload()
    }

    func deleteNote(_ noteId: String) async throws {
        try await A2AClient.shared.deletePlannerNote(noteId: noteId)
        await reload()
    }

    var openTasks: [PlannerTask] {
        tasks.filter { $0.status == "todo" || $0.status == "in_progress" }
    }

    deinit {
        runEventTask?.cancel()
    }

    private func startRunEventSync() {
        guard runEventTask == nil else { return }
        runEventTask = Task {
            for await event in A2AClient.shared.subscribeRunEvents() {
                if Task.isCancelled { break }
                switch event.type {
                case .runCreated, .runStarted, .runCompleted, .runFailed, .runCancelled:
                    await reload()
                case .snapshot:
                    if !tasks.isEmpty {
                        await reload()
                    }
                case .unknown:
                    break
                }
            }
        }
    }
}

typealias ForgeStore = PlannerStore

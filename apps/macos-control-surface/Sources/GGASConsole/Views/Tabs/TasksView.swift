import SwiftUI

private struct PlannerPreset: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let prompt: String

    static let defaults: [PlannerPreset] = [
        .init(id: "review", title: "Code Review", icon: "eye.fill", color: .blue,
              prompt: "Review the most recent code changes and identify the highest-risk regressions, security issues, and missing tests."),
        .init(id: "tests", title: "Write Tests", icon: "checkmark.shield.fill", color: .green,
              prompt: "Write or extend tests for the current task, focusing on edge cases and regression coverage."),
        .init(id: "debug", title: "Debug", icon: "ant.fill", color: .red,
              prompt: "Investigate the failing behavior, isolate the root cause, and propose the smallest safe fix."),
        .init(id: "refactor", title: "Refactor", icon: "arrow.triangle.2.circlepath", color: .purple,
              prompt: "Refactor the current area to reduce complexity and duplication while preserving behavior."),
        .init(id: "docs", title: "Docs", icon: "doc.text.fill", color: .orange,
              prompt: "Update the implementation notes, usage docs, and operational guidance for the active change."),
        .init(id: "security", title: "Security", icon: "lock.shield.fill", color: .pink,
              prompt: "Run a security-focused review of the active change and identify any unsafe defaults or missing controls.")
    ]
}

private struct PlannerTaskDraft {
    var title = ""
    var description = ""
    var status = "todo"
    var priority = 0
    var labels = ""

    init() {}

    init(task: PlannerTask) {
        title = task.title
        description = task.description ?? ""
        status = task.status
        priority = task.priority
        labels = task.labels.joined(separator: ", ")
    }

    var normalizedLabels: [String] {
        labels
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private func plannerColor(_ name: String) -> Color {
    switch name {
    case "red": return .red
    case "orange": return .orange
    case "yellow": return .yellow
    case "blue": return .blue
    case "green": return .green
    case "purple": return .purple
    case "pink": return .pink
    case "cyan": return .cyan
    default: return .secondary
    }
}

struct TasksView: View {
    @EnvironmentObject private var forge: ForgeStore
    @StateObject private var coordinator = CoordinatorManager.shared
    @State private var customPrompt = ""
    @State private var showCreateSheet = false
    @State private var editingTask: PlannerTask?
    @State private var launchError: String?
    @State private var actionInFlight = false

    private let columnSpecs: [(status: String, title: String, icon: String, color: Color)] = [
        ("todo", "Todo", "circle", .orange),
        ("in_progress", "In Progress", "circle.lefthalf.filled", .blue),
        ("done", "Done", "checkmark.circle.fill", .green)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summaryRow
            Divider()
            launcherSection
            Divider()
            if !forge.isAvailable && !forge.isLoading {
                unavailableState
            } else {
                kanbanBoard
            }
        }
        .navigationTitle("Planner")
        .sheet(isPresented: $showCreateSheet) {
            PlannerTaskEditorSheet(
                title: "New Planner Task",
                draft: PlannerTaskDraft(),
                onSave: { draft in
                    Task { await createTask(from: draft) }
                }
            )
        }
        .sheet(item: $editingTask) { task in
            PlannerTaskEditorSheet(
                title: "Edit Task",
                draft: PlannerTaskDraft(task: task),
                onSave: { draft in
                    Task { await updateTask(task, from: draft) }
                },
                onDelete: {
                    Task { await deleteTask(task) }
                }
            )
        }
        .alert("Planner Action Failed", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("OK", role: .cancel) { launchError = nil }
        } message: {
            Text(launchError ?? "")
        }
        .task {
            if forge.tasks.isEmpty {
                forge.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Planner")
                    .font(.headline.bold())
                Text(forge.project?.root ?? "Harness planner store")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if forge.isLoading {
                ProgressView().scaleEffect(0.7)
            }

            Button {
                forge.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button {
                showCreateSheet = true
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionInFlight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            PlannerSummaryChip(title: "Todo", value: forge.counts.todo, color: .orange)
            PlannerSummaryChip(title: "In Progress", value: forge.counts.inProgress, color: .blue)
            PlannerSummaryChip(title: "Done", value: forge.counts.done, color: .green)
            if let status = forge.lastError, !status.isEmpty {
                Label(status, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    private var launcherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Task Launcher", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Routes through the harness control plane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150), spacing: 10)
            ], spacing: 10) {
                ForEach(PlannerPreset.defaults) { preset in
                    Button {
                        Task {
                            do {
                                _ = try await dispatchPrompt(preset.prompt)
                            } catch {
                                launchError = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preset.icon)
                                .foregroundStyle(preset.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(preset.prompt)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(preset.color.opacity(0.18), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(actionInFlight)
                }
            }

            HStack(spacing: 10) {
                TextField("Dispatch a custom planner prompt…", text: $customPrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                Button {
                    Task {
                        do {
                            _ = try await dispatchPrompt(customPrompt)
                        } catch {
                            launchError = error.localizedDescription
                        }
                    }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || actionInFlight)
            }
        }
        .padding(16)
    }

    private var kanbanBoard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(columnSpecs, id: \.status) { spec in
                    PlannerColumnView(
                        title: spec.title,
                        icon: spec.icon,
                        color: spec.color,
                        tasks: forge.tasks.filter { $0.status == spec.status },
                        onOpen: { editingTask = $0 },
                        onAdvance: { task in Task { await advance(task) } },
                        onLaunch: { task in Task { await launch(task) } }
                    )
                }
            }
            .padding(16)
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Planner store unavailable")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(forge.lastError ?? "The harness control plane is not reachable.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createTask(from draft: PlannerTaskDraft) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            _ = try await forge.createTask(
                title: draft.title,
                description: draft.description.isEmpty ? nil : draft.description,
                status: draft.status,
                priority: draft.priority,
                labels: draft.normalizedLabels
            )
            showCreateSheet = false
        } catch {
            launchError = error.localizedDescription
        }
    }

    private func updateTask(_ task: PlannerTask, from draft: PlannerTaskDraft) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            var updated = task
            updated.title = draft.title
            updated.description = draft.description.isEmpty ? nil : draft.description
            updated.status = draft.status
            updated.priority = draft.priority
            updated.labels = draft.normalizedLabels
            try await forge.updateTask(updated)
            editingTask = nil
        } catch {
            launchError = error.localizedDescription
        }
    }

    private func deleteTask(_ task: PlannerTask) async {
        guard !actionInFlight else { return }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await forge.deleteTask(task.id)
            editingTask = nil
        } catch {
            launchError = error.localizedDescription
        }
    }

    private func advance(_ task: PlannerTask) async {
        var updated = task
        switch task.status {
        case "todo":
            updated.status = "in_progress"
        case "in_progress":
            updated.status = "done"
        default:
            updated.status = "todo"
        }
        do {
            try await forge.updateTask(updated)
        } catch {
            launchError = error.localizedDescription
        }
    }

    private func launch(_ task: PlannerTask) async {
        let prompt = buildPrompt(for: task)
        do {
            let run = try await dispatchPrompt(prompt)
            var updated = task
            updated.status = "in_progress"
            updated.runId = run?.runId
            updated.linkedRunStatus = run?.status.rawValue
            updated.runtime = run?.workerBackend ?? run?.coordinator ?? updated.runtime
            try await forge.updateTask(updated)
        } catch {
            launchError = error.localizedDescription
        }
    }

    @discardableResult
    private func dispatchPrompt(_ prompt: String) async throws -> AgentRun? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !actionInFlight else { return nil }

        actionInFlight = true
        defer { actionInFlight = false }

        let manager = CoordinatorManager.shared
        guard let active = manager.active else {
            throw NSError(domain: "Planner", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active coordinator configured"])
        }

        let selectedProviderId = ProviderDetectionService.shared.selectedProvider?.id
        let workerModel = manager.runtimeSettings.workerModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let bridgeRoles = manager.runtimeSettings.bridgeRoles
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let run = try await A2AClient.shared.dispatch(
            task: trimmed,
            mode: "minion",
            source: "planner",
            coordinator: active.type == .claude ? "claude" : "custom",
            model: active.model,
            coordinatorProvider: active.type == .kimi ? "antigravity" : selectedProviderId,
            coordinatorModel: active.model,
            workerBackend: manager.runtimeSettings.workerBackend,
            workerModel: workerModel.isEmpty ? nil : workerModel,
            dispatchPath: manager.runtimeSettings.dispatchPath,
            bridgeContext: manager.runtimeSettings.bridgeContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : manager.runtimeSettings.bridgeContext,
            bridgeWorktree: manager.runtimeSettings.bridgeWorktree.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : manager.runtimeSettings.bridgeWorktree,
            bridgeAgents: manager.runtimeSettings.bridgeAgents,
            bridgeStrategy: manager.runtimeSettings.bridgeStrategy,
            bridgeRoles: bridgeRoles.isEmpty ? nil : bridgeRoles,
            bridgeTimeoutSeconds: manager.runtimeSettings.bridgeTimeoutSeconds
        )

        manager.addLine("✅ planner dispatched run:\(run.runId)", level: .success)
        if prompt == customPrompt {
            customPrompt = ""
        }
        return run
    }

    private func buildPrompt(for task: PlannerTask) -> String {
        var sections: [String] = [task.title]
        if let description = task.description, !description.isEmpty {
            sections.append(description)
        }
        if !task.notes.isEmpty {
            sections.append("Context notes:\n" + task.notes.map { "- \($0.content)" }.joined(separator: "\n"))
        }
        if !task.labels.isEmpty {
            sections.append("Labels: " + task.labels.joined(separator: ", "))
        }
        return sections.joined(separator: "\n\n")
    }
}

private struct PlannerSummaryChip: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption)
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }
}

private struct PlannerColumnView: View {
    let title: String
    let icon: String
    let color: Color
    let tasks: [PlannerTask]
    let onOpen: (PlannerTask) -> Void
    let onAdvance: (PlannerTask) -> Void
    let onLaunch: (PlannerTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundStyle(.tertiary)
                    Text("No tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.05))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(tasks) { task in
                            PlannerTaskCard(
                                task: task,
                                onOpen: { onOpen(task) },
                                onAdvance: { onAdvance(task) },
                                onLaunch: { onLaunch(task) }
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .frame(minHeight: 460, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct PlannerTaskCard: View {
    let task: PlannerTask
    let onOpen: () -> Void
    let onAdvance: () -> Void
    let onLaunch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if let description = task.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()
                Circle()
                    .fill(plannerColor(task.priorityColorName))
                    .frame(width: 9, height: 9)
            }

            if !task.labels.isEmpty {
                FlexibleTagRow(tags: task.labels)
            }

            HStack(spacing: 8) {
                Text(task.priorityLabel)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(plannerColor(task.priorityColorName).opacity(0.16), in: Capsule())
                    .foregroundStyle(plannerColor(task.priorityColorName))

                if let runStatus = task.runStatusLabel {
                    Text(runStatus)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()

                if !task.notes.isEmpty {
                    Label("\(task.notes.count)", systemImage: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("Edit", action: onOpen)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(task.status == "done" ? "Reopen" : "Advance", action: onAdvance)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button("Launch", action: onLaunch)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.8)
        )
    }
}

private struct FlexibleTagRow: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tags.chunked(into: 3), id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct PlannerTaskEditorSheet: View {
    let title: String
    @State var draft: PlannerTaskDraft
    let onSave: (PlannerTaskDraft) -> Void
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())
            TextField("Task title", text: $draft.title)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: $draft.description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)

            HStack(spacing: 12) {
                Picker("Status", selection: $draft.status) {
                    Text("Todo").tag("todo")
                    Text("In Progress").tag("in_progress")
                    Text("Done").tag("done")
                }
                .pickerStyle(.menu)

                Stepper(value: $draft.priority, in: 0...4) {
                    Text("Priority \(draft.priority)")
                }
            }

            TextField("Labels (comma-separated)", text: $draft.labels)
                .textFieldStyle(.roundedBorder)

            Spacer()

            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520, height: 360)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

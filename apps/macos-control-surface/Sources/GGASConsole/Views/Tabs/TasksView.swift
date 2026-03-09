import SwiftUI

private struct PlannerPreset: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
    let prompt: String
    let suggestedRoles: [WorkerRoleOption]
    let note: String

    static let defaults: [PlannerPreset] = [
        .init(id: "review", title: "Code Review", icon: "eye.fill", color: .blue,
              prompt: "Review the most recent code changes and identify the highest-risk regressions, security issues, and missing tests.",
              suggestedRoles: [.scout, .reviewer, .planner],
              note: "Changes prompt only"),
        .init(id: "tests", title: "Write Tests", icon: "checkmark.shield.fill", color: .green,
              prompt: "Write or extend tests for the current task, focusing on edge cases and regression coverage.",
              suggestedRoles: [.builder, .reviewer, .specialist],
              note: "Changes prompt only"),
        .init(id: "debug", title: "Debug", icon: "ant.fill", color: .red,
              prompt: "Investigate the failing behavior, isolate the root cause, and propose the smallest safe fix.",
              suggestedRoles: [.scout, .builder, .reviewer],
              note: "Changes prompt only"),
        .init(id: "refactor", title: "Refactor", icon: "arrow.triangle.2.circlepath", color: .purple,
              prompt: "Refactor the current area to reduce complexity and duplication while preserving behavior.",
              suggestedRoles: [.planner, .builder, .reviewer],
              note: "Changes prompt only"),
        .init(id: "docs", title: "Docs", icon: "doc.text.fill", color: .orange,
              prompt: "Update the implementation notes, usage docs, and operational guidance for the active change.",
              suggestedRoles: [.planner, .specialist],
              note: "Changes prompt only"),
        .init(id: "security", title: "Security", icon: "lock.shield.fill", color: .pink,
              prompt: "Run a security-focused review of the active change and identify any unsafe defaults or missing controls.",
              suggestedRoles: [.scout, .reviewer, .specialist],
              note: "Changes prompt only")
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

private struct PlannerNoteDraft {
    var title = ""
    var content = ""
    var pinned = false
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
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    @StateObject private var coordinator = CoordinatorManager.shared
    @State private var customPrompt = ""
    @State private var showCreateSheet = false
    @State private var editingTask: PlannerTask?
    @State private var noteTask: PlannerTask?
    @State private var launchError: String?
    @State private var actionInFlight = false
    @State private var showAdvancedWorkerOptions = false

    private let columnSpecs: [(status: String, title: String, icon: String, color: Color)] = [
        ("todo", "Todo", "circle", .orange),
        ("in_progress", "In Progress", "circle.lefthalf.filled", .blue),
        ("done", "Done", "checkmark.circle.fill", .green)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .navigationTitle("Planner")
        .sheet(isPresented: $showCreateSheet) {
            PlannerTaskEditorSheet(
                title: "New Planner Task",
                draft: PlannerTaskDraft(),
                onSave: { draft in
                    await createTask(from: draft)
                }
            )
        }
        .sheet(item: $editingTask) { task in
            PlannerTaskEditorSheet(
                title: "Edit Task",
                draft: PlannerTaskDraft(task: task),
                onSave: { draft in
                    await updateTask(task, from: draft)
                },
                onDelete: {
                    await deleteTask(task)
                }
            )
        }
        .sheet(item: $noteTask) { task in
            PlannerNoteEditorSheet(
                taskTitle: task.title,
                draft: PlannerNoteDraft(title: "\(task.title) note"),
                onSave: { draft in
                    await createNote(for: task, draft: draft)
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
            workflow.sync(tasks: forge.tasks)
        }
        .onChange(of: forge.tasks) { _, tasks in
            workflow.sync(tasks: tasks)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Planner")
                    .font(.headline.bold())
                Text("Plan work, pick the coordinating LLM, and let the harness move tasks through the board as runs progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PlannerSummaryChip(title: "Todo", value: "\(forge.counts.todo)", color: .orange)
                PlannerSummaryChip(title: "In Progress", value: "\(forge.counts.inProgress)", color: .blue)
                PlannerSummaryChip(title: "Done", value: "\(forge.counts.done)", color: .green)
                if let active = coordinator.active {
                    PlannerSummaryChip(title: "Coordinator", value: active.label, color: active.type.accentColor)
                }
                PlannerSummaryChip(title: "Sub-Agents", value: coordinator.runtimeSettings.workerPlanLabel, color: coordinator.runtimeSettings.selectedWorkerRuntime.accentColor)
                if let status = forge.lastError, !status.isEmpty {
                    Label(status, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Spacer()
            }

            if workflow.hasSelection {
                selectedTaskContextCard
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    private var selectedTaskContextCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workflow.selectedTaskTitle ?? "Selected Task")
                    .font(.system(size: 12, weight: .semibold))

                HStack(spacing: 8) {
                    if let status = workflow.selectedTaskStatus {
                        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    if let runtime = workflow.selectedRuntime, !runtime.isEmpty {
                        Text(runtime)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }

                    if let runId = workflow.selectedRunId, !runId.isEmpty {
                        Text(String(runId.prefix(12)))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button("Open Swarm") {
                shell.selectedTab = .swarm
            }
            .buttonStyle(.bordered)
            .disabled(workflow.selectedRunId == nil)

            Button("Open LLM Studio") {
                shell.openLMStudioCatalog()
            }
            .buttonStyle(.bordered)

            Button {
                workflow.clear()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    private var launcherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Execution Planner", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if coordinator.active?.type == .lmStudio {
                    Button {
                        shell.openLMStudioCatalog()
                    } label: {
                        Label("Manage Models", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }
                Text("Harness-driven execution")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("1. Select the coordinating LLM. 2. Choose the sub-agent model and deployment shape. 3. Pick a work intent or write a custom prompt. Work intent changes the objective, not the team, unless you explicitly apply a suggested team.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Color.accentColor)
                Text("The selected coordinating agent owns the run and launches all sub-agents. Role boxes define worker lanes; the harness maps each lane to a persona before spawn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.12), lineWidth: 0.8)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(coordinator.coordinators) { coord in
                        PlannerCoordinatorCard(
                            config: coord,
                            isActive: coord.id == coordinator.activeId
                        ) {
                            coordinator.setActive(id: coord.id)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            PlannerSubagentDeploymentPanel(
                runtimeSettings: $coordinator.runtimeSettings,
                showAdvancedWorkerOptions: $showAdvancedWorkerOptions
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Work Intent")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Intent sets the task objective. Team shape stays as-is unless you apply the suggestion.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 210), spacing: 10)
                ], spacing: 10) {
                ForEach(PlannerPreset.defaults) { preset in
                    PlannerIntentCard(
                        preset: preset,
                        onApplyIntent: {
                            Task {
                                do {
                                    _ = try await dispatchPrompt(preset.prompt)
                                } catch {
                                    launchError = error.localizedDescription
                                }
                            }
                        },
                        onApplySuggestedTeam: {
                            coordinator.runtimeSettings.applyWorkerRoles(preset.suggestedRoles)
                        }
                    )
                    .disabled(actionInFlight)
                }
            }
            }

            HStack(spacing: 10) {
                CommandTextEditor(
                    text: $customPrompt,
                    onSubmit: {
                        Task {
                            do {
                                _ = try await dispatchPrompt(customPrompt)
                            } catch {
                                launchError = error.localizedDescription
                            }
                        }
                    },
                    placeholder: "Describe the next task for the selected coordinator…",
                    submitOnCommandReturn: true,
                    autoFocus: true
                )
                .frame(minHeight: 72, maxHeight: 112)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.8)
                )

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
                        selectedTaskId: workflow.selectedTaskId,
                        onSelect: { workflow.select(task: $0) },
                        onOpen: { editingTask = $0 },
                        onAdvance: { task in Task { await advance(task) } },
                        onLaunch: { task in Task { await launch(task) } },
                        onAddNote: { task in noteTask = task }
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

    private func createTask(from draft: PlannerTaskDraft) async -> Bool {
        guard !actionInFlight else { return false }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            let task = try await forge.createTask(
                title: draft.title,
                description: draft.description.isEmpty ? nil : draft.description,
                status: draft.status,
                priority: draft.priority,
                labels: draft.normalizedLabels
            )
            workflow.select(task: task)
            showCreateSheet = false
            return true
        } catch {
            launchError = error.localizedDescription
            return false
        }
    }

    private func updateTask(_ task: PlannerTask, from draft: PlannerTaskDraft) async -> Bool {
        guard !actionInFlight else { return false }
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
            workflow.select(task: updated)
            editingTask = nil
            return true
        } catch {
            launchError = error.localizedDescription
            return false
        }
    }

    private func deleteTask(_ task: PlannerTask) async -> Bool {
        guard !actionInFlight else { return false }
        actionInFlight = true
        defer { actionInFlight = false }
        do {
            try await forge.deleteTask(task.id)
            if workflow.selectedTaskId == task.id {
                workflow.clear()
            }
            editingTask = nil
            return true
        } catch {
            launchError = error.localizedDescription
            return false
        }
    }

    private func createNote(for task: PlannerTask, draft: PlannerNoteDraft) async -> Bool {
        guard !actionInFlight else { return false }
        actionInFlight = true
        defer { actionInFlight = false }

        do {
            _ = try await forge.createNote(
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.title,
                content: draft.content,
                pinned: draft.pinned,
                taskId: task.id
            )
            workflow.select(task: task)
            noteTask = nil
            return true
        } catch {
            launchError = error.localizedDescription
            return false
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
            workflow.select(task: updated)
        } catch {
            launchError = error.localizedDescription
        }
    }

    private func launch(_ task: PlannerTask) async {
        workflow.select(task: task)
        let prompt = buildPrompt(for: task)
        do {
            let run = try await dispatchPrompt(prompt)
            var updated = task
            updated.status = "in_progress"
            updated.runId = run?.runId
            updated.linkedRunStatus = run?.status.rawValue
            updated.runtime = coordinator.active?.label ?? run?.coordinatorModel ?? run?.coordinator ?? updated.runtime
            try await forge.updateTask(updated)
            workflow.select(task: updated)
            shell.selectedTab = .swarm
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
        let dispatchIdentity = manager.dispatchIdentity(for: active, selectedProviderId: selectedProviderId)

        let run = try await A2AClient.shared.dispatch(
            task: trimmed,
            mode: "minion",
            source: "planner",
            coordinator: dispatchIdentity.coordinator,
            model: active.model,
            coordinatorProvider: dispatchIdentity.coordinatorProvider,
            coordinatorModel: active.model,
            workerBackend: manager.runtimeSettings.workerBackend,
            workerModel: workerModel.isEmpty ? nil : workerModel,
            dispatchPath: manager.runtimeSettings.dispatchPath,
            bridgeContext: manager.runtimeSettings.bridgeContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : manager.runtimeSettings.bridgeContext,
            bridgeWorktree: manager.runtimeSettings.bridgeWorktree.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : manager.runtimeSettings.bridgeWorktree,
            bridgeAgents: manager.runtimeSettings.effectiveBridgeAgentsForDispatch,
            bridgeStrategy: manager.runtimeSettings.bridgeStrategy,
            bridgeRoles: manager.runtimeSettings.bridgeRolesForDispatch,
            bridgeTimeoutSeconds: manager.runtimeSettings.bridgeTimeoutSeconds
        )

        manager.addLine("✅ planner dispatched run:\(run.runId)", level: .success)
        workflow.select(runId: run.runId, title: trimmed, runtime: coordinator.active?.label)
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

private struct PlannerIntentCard: View {
    let preset: PlannerPreset
    let onApplyIntent: () -> Void
    let onApplySuggestedTeam: () -> Void
    private let cardHeight: CGFloat = 228

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: preset.icon)
                    .foregroundStyle(preset.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(preset.note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(preset.prompt)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("Suggested Team")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(preset.suggestedRoles, id: \.id) { role in
                        HStack(spacing: 4) {
                            Image(systemName: role.icon)
                                .font(.system(size: 9, weight: .bold))
                            Text(role.label)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(preset.color.opacity(0.10), in: Capsule())
                        .foregroundStyle(preset.color)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button("Run Intent") {
                    onApplyIntent()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                Button("Apply Suggested Team") {
                    onApplySuggestedTeam()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(preset.color.opacity(0.18), lineWidth: 0.8)
        )
    }
}

private struct PlannerCoordinatorCard: View {
    let config: CoordinatorConfig
    let isActive: Bool
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: config.type.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(config.type.accentColor)
                    Text(config.type.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(config.type.accentColor)
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(config.type.accentColor)
                    }
                }

                Text(config.label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(config.isOnline ? Color(red: 0.0, green: 0.88, blue: 0.45) : Color(white: 0.35))
                        .frame(width: 5, height: 5)
                    Text(config.isOnline ? "Online" : "Offline")
                        .font(.system(size: 9))
                        .foregroundColor(config.isOnline ? Color(red: 0.0, green: 0.88, blue: 0.45) : .secondary)
                }
            }
            .padding(10)
            .frame(width: 148, height: 90, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isActive ? config.type.accentColor.opacity(0.72) : Color.secondary.opacity(hovered ? 0.3 : 0.15),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct PlannerSubagentDeploymentPanel: View {
    @Binding var runtimeSettings: CoordinatorRuntimeSettings
    @Binding var showAdvancedWorkerOptions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sub-Agent Deployment")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Planner tasks can launch a single worker or a harness-managed agent team. Codex, Claude, and Kimi all run under the same worktree, mailbox, and governor rules.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sub-Agent Model")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: workerRuntimeBinding) {
                        ForEach(WorkerRuntimeOption.allCases) { runtime in
                            Text(runtime.label).tag(runtime)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Deployment")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: topologyBinding) {
                        ForEach(WorkerTopologyOption.allCases) { topology in
                            Text(topology.label).tag(topology)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    AppTextField(
                        text: $runtimeSettings.workerModel,
                        placeholder: runtimeSettings.selectedWorkerRuntime.defaultModel,
                        font: .monospacedSystemFont(ofSize: 11, weight: .regular)
                    )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                        .frame(minWidth: 180)
                }
            }

            if runtimeSettings.selectedWorkerTopology == .team {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agents")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        AppTextField(
                            text: bridgeAgentsBinding,
                            placeholder: "4",
                            font: .monospacedSystemFont(ofSize: 11, weight: .regular)
                        )
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                            .frame(width: 90)
                            .disabled(runtimeSettings.usesExplicitWorkerRoles)
                            .opacity(runtimeSettings.usesExplicitWorkerRoles ? 0.55 : 1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Strategy")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: $runtimeSettings.bridgeStrategy) {
                            Text("parallel").tag("parallel")
                            Text("sequential").tag("sequential")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sub-Agent Roles")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(runtimeSettings.usesExplicitWorkerRoles
                                 ? "Selected roles define exactly which worker lanes the harness spawns."
                                 : "These boxes show the harness default role mix for the current team size. Tap any box to override.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if runtimeSettings.usesExplicitWorkerRoles {
                            Button("Use Harness Defaults") {
                                runtimeSettings.resetWorkerRolesToHarnessDefault()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(WorkerRoleOption.allCases) { role in
                            PlannerWorkerRoleChip(
                                role: role,
                                isSelected: runtimeSettings.effectiveWorkerRoles.contains(role),
                                isAutoSuggested: !runtimeSettings.usesExplicitWorkerRoles && runtimeSettings.effectiveWorkerRoles.contains(role)
                            ) {
                                runtimeSettings.toggleWorkerRole(role)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Label("\(runtimeSettings.plannedWorkerCount) worker lane\(runtimeSettings.plannedWorkerCount == 1 ? "" : "s")", systemImage: "person.3.fill")
                        Text(runtimeSettings.usesExplicitWorkerRoles ? "Explicit role plan" : "Harness default role plan")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Persona Mapping")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(runtimeSettings.effectiveWorkerRoles, id: \.id) { role in
                            HStack(spacing: 8) {
                                Image(systemName: role.icon)
                                    .frame(width: 14)
                                    .foregroundStyle(.secondary)
                                Text(role.personaSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            DisclosureGroup(isExpanded: $showAdvancedWorkerOptions) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Worktree")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            AppTextField(
                                text: $runtimeSettings.bridgeWorktree,
                                placeholder: ".",
                                font: .monospacedSystemFont(ofSize: 11, weight: .regular)
                            )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                )
                                .frame(minWidth: 140)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Timeout (s)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            AppTextField(
                                text: bridgeTimeoutBinding,
                                placeholder: "1800",
                                font: .monospacedSystemFont(ofSize: 11, weight: .regular)
                            )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                                )
                                .frame(width: 100)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extra Context")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        CommandTextEditor(
                            text: $runtimeSettings.bridgeContext,
                            placeholder: "Optional extra context for the selected sub-agent runtime",
                            font: .monospacedSystemFont(ofSize: 11, weight: .regular)
                        )
                            .frame(minHeight: 68, maxHeight: 96)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("Advanced Worker Options")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    private var workerRuntimeBinding: Binding<WorkerRuntimeOption> {
        Binding(
            get: { runtimeSettings.selectedWorkerRuntime },
            set: { newValue in
                runtimeSettings.setWorkerRuntime(newValue)
            }
        )
    }

    private var topologyBinding: Binding<WorkerTopologyOption> {
        Binding(
            get: { runtimeSettings.selectedWorkerTopology },
            set: { newValue in
                runtimeSettings.setWorkerTopology(newValue)
            }
        )
    }

    private var bridgeAgentsBinding: Binding<String> {
        Binding(
            get: { String(runtimeSettings.bridgeAgents) },
            set: { newValue in
                if let parsed = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines)), parsed > 0 {
                    runtimeSettings.bridgeAgents = parsed
                }
            }
        )
    }

    private var bridgeTimeoutBinding: Binding<String> {
        Binding(
            get: { String(runtimeSettings.bridgeTimeoutSeconds) },
            set: { newValue in
                if let parsed = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines)), parsed > 0 {
                    runtimeSettings.bridgeTimeoutSeconds = parsed
                }
            }
        )
    }
}

private struct PlannerWorkerRoleChip: View {
    let role: WorkerRoleOption
    let isSelected: Bool
    let isAutoSuggested: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: role.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(role.label)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if isAutoSuggested {
                        Text("Auto")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.16), in: Capsule())
                    }
                }

                Text(role.personaLabel)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.9) : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.14), lineWidth: isSelected ? 1.2 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PlannerSummaryChip: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption)
            Text(value)
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
    let selectedTaskId: String?
    let onSelect: (PlannerTask) -> Void
    let onOpen: (PlannerTask) -> Void
    let onAdvance: (PlannerTask) -> Void
    let onLaunch: (PlannerTask) -> Void
    let onAddNote: (PlannerTask) -> Void

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
                                isSelected: selectedTaskId == task.id,
                                onSelect: { onSelect(task) },
                                onOpen: {
                                    onSelect(task)
                                    onOpen(task)
                                },
                                onAdvance: {
                                    onSelect(task)
                                    onAdvance(task)
                                },
                                onLaunch: {
                                    onSelect(task)
                                    onLaunch(task)
                                },
                                onAddNote: {
                                    onSelect(task)
                                    onAddNote(task)
                                }
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
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onAdvance: () -> Void
    let onLaunch: () -> Void
    let onAddNote: () -> Void

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

                if let runtime = task.runtime, !runtime.isEmpty {
                    Text(runtime)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
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
                Button("Note", action: onAddNote)
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
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.15), lineWidth: isSelected ? 1.2 : 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onSelect)
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
    let onSave: (PlannerTaskDraft) async -> Bool
    var onDelete: (() async -> Bool)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.bold())
            AppTextField(text: $draft.title, placeholder: "Task title", autoFocus: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.8)
                )
            CommandTextEditor(
                text: $draft.description,
                placeholder: "Description",
                font: .systemFont(ofSize: 13)
            )
            .frame(minHeight: 84, maxHeight: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 0.8)
            )

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

            AppTextField(text: $draft.labels, placeholder: "Labels (comma-separated)")
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.8)
                )

            Spacer()

            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive) {
                        Task {
                            saving = true
                            let deleted = await onDelete()
                            saving = false
                            if deleted {
                                dismiss()
                            }
                        }
                    }
                    .disabled(saving)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(saving)
                Button("Save") {
                    Task {
                        saving = true
                        let saved = await onSave(draft)
                        saving = false
                        if saved {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }
        .padding(20)
        .frame(width: 520, height: 360)
    }
}

private struct PlannerNoteEditorSheet: View {
    let taskTitle: String
    @State var draft: PlannerNoteDraft
    let onSave: (PlannerNoteDraft) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Note")
                .font(.title3.bold())
            Text(taskTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            AppTextField(text: $draft.title, placeholder: "Note title", autoFocus: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 0.8)
                )

            Toggle("Pinned", isOn: $draft.pinned)
                .toggleStyle(.checkbox)

            CommandTextEditor(
                text: $draft.content,
                placeholder: "Write the task note…",
                font: .systemFont(ofSize: 13)
            )
            .frame(minHeight: 180, maxHeight: 240)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 0.8)
            )

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(saving)
                Button(saving ? "Saving…" : "Save Note") {
                    Task {
                        saving = true
                        let saved = await onSave(draft)
                        saving = false
                        if saved {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
            }
        }
        .padding(20)
        .frame(width: 520, height: 380)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

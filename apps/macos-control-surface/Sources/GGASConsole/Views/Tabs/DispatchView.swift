// DispatchView.swift — submit a new agent task

import SwiftUI

struct DispatchView: View {
    @StateObject private var providerSvc = ProviderDetectionService.shared
    @State private var taskText = ""
    @State private var mode = "auto"
    @State private var source = "console"
    @State private var coordinator = "auto"
    @State private var coordinatorProvider = ""
    @State private var coordinatorModel = ""
    @State private var workerBackend = "kimi-pool"
    @State private var workerModel = ""
    @State private var dispatchPath = ""
    @State private var bridgeContext = ""
    @State private var bridgeWorktree = "."
    @State private var bridgeAgents = "4"
    @State private var bridgeStrategy = "parallel"
    @State private var bridgeRoles = ""
    @State private var bridgeTimeoutSeconds = "1800"
    @State private var submitting = false
    @State private var result: AgentRun?
    @State private var error: String?

    private let modes = ["auto", "minion", "go"]
    private let workerBackends = ["kimi-pool", "kimi-bridge-agent", "kimi-bridge-swarm", "lm-studio", "jcode-direct", "litellm-gateway"]
    private let bridgeStrategies = ["parallel", "sequential"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox("Dispatch Agent Task") {
                VStack(alignment: .leading, spacing: 14) {
                    // Task input
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Task", systemImage: "pencil")
                            .font(.caption).foregroundStyle(.secondary)
                        CommandTextEditor(
                            text: $taskText,
                            onSubmit: submit,
                            placeholder: "Describe what the agent should do…",
                            submitOnCommandReturn: true,
                            autoFocus: true
                        )
                            .frame(minHeight: 100)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    }

                    // Mode picker
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Mode", systemImage: "dial.low").font(.caption).foregroundStyle(.secondary)
                            Picker("", selection: $mode) {
                                ForEach(modes, id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.segmented).frame(maxWidth: 280)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Source", systemImage: "tag").font(.caption).foregroundStyle(.secondary)
                            TextField("console", text: $source)
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 120)
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Coordinator", systemImage: "person.crop.circle")
                                .font(.caption).foregroundStyle(.secondary)
                            Picker("", selection: $coordinator) {
                                Text("Auto").tag("auto")
                                Text("Codex").tag("codex")
                                Text("Claude").tag("claude")
                                Text("Kimi").tag("kimi")
                            }
                            .pickerStyle(.segmented)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Provider", systemImage: "network")
                                .font(.caption).foregroundStyle(.secondary)
                            if providerSvc.availableProviders.isEmpty {
                                TextField("provider id", text: $coordinatorProvider)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("", selection: $coordinatorProvider) {
                                    ForEach(providerSvc.availableProviders) { provider in
                                        Text(provider.displayName).tag(provider.id)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Coordinator Model", systemImage: "cpu")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("model id", text: $coordinatorModel)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Text(coordinatorHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Worker Backend", systemImage: "shippingbox")
                                .font(.caption).foregroundStyle(.secondary)
                            Picker("", selection: $workerBackend) {
                                ForEach(workerBackends, id: \.self) { backend in
                                    Text(backend).tag(backend)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Worker Model", systemImage: "wrench.and.screwdriver")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("e.g. kimi-3.5", text: $workerModel)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Dispatch Path", systemImage: "arrow.triangle.branch")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("optional", text: $dispatchPath)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if isBridgeBackend {
                        VStack(alignment: .leading, spacing: 12) {
                            if isBridgeSwarmBackend {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("Bridge Agents", systemImage: "person.3")
                                            .font(.caption).foregroundStyle(.secondary)
                                        TextField("4", text: $bridgeAgents)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("Bridge Strategy", systemImage: "square.stack.3d.up")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Picker("", selection: $bridgeStrategy) {
                                            ForEach(bridgeStrategies, id: \.self) { strategy in
                                                Text(strategy).tag(strategy)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("Bridge Roles", systemImage: "list.bullet.rectangle")
                                            .font(.caption).foregroundStyle(.secondary)
                                        TextField("planner, builder, reviewer", text: $bridgeRoles)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Bridge Worktree", systemImage: "folder")
                                        .font(.caption).foregroundStyle(.secondary)
                                    TextField(".", text: $bridgeWorktree)
                                        .textFieldStyle(.roundedBorder)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("Bridge Timeout (s)", systemImage: "timer")
                                        .font(.caption).foregroundStyle(.secondary)
                                    TextField("1800", text: $bridgeTimeoutSeconds)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Label("Bridge Context", systemImage: "text.alignleft")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextField("Optional extra instructions for the spawned Kimi worker", text: $bridgeContext, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(2...4)
                            }
                        }
                    }

                    // Submit
                    HStack {
                        Spacer()
                        Button(action: submit) {
                            Label(submitting ? "Dispatching…" : "Dispatch", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submitting)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
                .padding(4)
            }

            // Result / error
            if let run = result {
                GroupBox("Dispatched ✓") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Run ID", value: run.runId)
                        LabeledContent("Status", value: run.status.rawValue)
                        LabeledContent("Mode",   value: run.mode)
                        LabeledContent("Coordinator", value: run.coordinator ?? "n/a")
                        LabeledContent("Provider", value: run.coordinatorProvider ?? "n/a")
                        LabeledContent("Coord Model", value: run.coordinatorModel ?? run.model ?? "n/a")
                        LabeledContent("Worker", value: run.workerBackend ?? "n/a")
                        LabeledContent("Worker Model", value: run.workerModel ?? "n/a")
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(4)
                }
            }
            if let err = error {
                GroupBox {
                    Text(err).foregroundStyle(.red).font(.caption).textSelection(.enabled)
                } label: {
                    Label("Error", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            }

            Spacer()
        }
        .padding(20)
        .navigationTitle("Dispatch")
        .task {
            providerSvc.refresh()
            if coordinatorProvider.isEmpty {
                coordinatorProvider = providerSvc.selectedProvider?.id ?? ""
            }
            if coordinatorModel.isEmpty {
                coordinatorModel = providerSvc.selectedModel
            }
        }
    }

    private func submit() {
        let task = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        submitting = true
        result = nil
        error = nil
        Task {
            do {
                let run = try await A2AClient.shared.dispatch(
                    task: task,
                    mode: mode,
                    source: source,
                    coordinator: coordinator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : coordinator,
                    model: coordinatorModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : coordinatorModel,
                    coordinatorProvider: coordinatorProvider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : coordinatorProvider,
                    coordinatorModel: coordinatorModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : coordinatorModel,
                    workerBackend: workerBackend,
                    workerModel: workerModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : workerModel,
                    dispatchPath: dispatchPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : dispatchPath,
                    bridgeContext: bridgeContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bridgeContext,
                    bridgeWorktree: normalizedBridgeWorktree,
                    bridgeAgents: parsedBridgeAgents,
                    bridgeStrategy: isBridgeSwarmBackend ? bridgeStrategy : nil,
                    bridgeRoles: normalizedBridgeRoles,
                    bridgeTimeoutSeconds: parsedBridgeTimeoutSeconds
                )
                result = run
                taskText = ""
            } catch {
                self.error = error.localizedDescription
            }
            submitting = false
        }
    }

    private var isBridgeBackend: Bool {
        workerBackend == "kimi-bridge-agent" || workerBackend == "kimi-bridge-swarm"
    }

    private var coordinatorHelpText: String {
        switch coordinator {
        case "auto":
            return "Auto lets the harness choose the coordinating runtime from authenticated local CLIs first, then provider-backed fallbacks."
        case "codex":
            return "Pinned to Codex for the coordinator. The harness still controls sub-agent routing, worktrees, and spawn limits."
        case "claude":
            return "Pinned to Claude for the coordinator. The harness still controls sub-agent routing, worktrees, and spawn limits."
        case "kimi":
            return "Pinned to Kimi for the coordinator. Kimi remains harness-controlled and cannot autonomously spawn child workers."
        default:
            return "The harness owns sub-agent orchestration even when the coordinator runtime is pinned."
        }
    }

    private var isBridgeSwarmBackend: Bool {
        workerBackend == "kimi-bridge-swarm"
    }

    private var normalizedBridgeWorktree: String? {
        let trimmed = bridgeWorktree.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedBridgeRoles: [String]? {
        guard isBridgeSwarmBackend else { return nil }
        let roles = bridgeRoles
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return roles.isEmpty ? nil : roles
    }

    private var parsedBridgeAgents: Int? {
        guard isBridgeSwarmBackend else { return nil }
        return Int(bridgeAgents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var parsedBridgeTimeoutSeconds: Int? {
        guard isBridgeBackend else { return nil }
        return Int(bridgeTimeoutSeconds.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

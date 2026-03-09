// ControlPanelView.swift — Mission control for coordinator agents.
// Select the coordinating LLM, steer harness-managed sub-agent deployment, and dispatch tasks.

import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject private var launcher: LaunchManager
    @EnvironmentObject private var workflow: WorkflowContextStore
    @StateObject private var mgr = CoordinatorManager.shared
    @State private var commandText = ""
    @State private var showModelManager = false
    @State private var showLMParams = false
    @State private var serverOnline = false
    @State private var startingServer = false
    @State private var selectedRunLogs: [LogLine] = []
    @State private var selectedRunLogTask: Task<Void, Never>?
    @Namespace private var scroll

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            headerBar

            Divider()

            // ── Command input ────────────────────────────────────────────────
            commandSection

            Divider()

            // ── Output stream ────────────────────────────────────────────────
            outputStream
        }
        .background(Color(NSColor.underPageBackgroundColor))
        .navigationTitle("Console")
        .sheet(isPresented: $showModelManager) {
            LMStudioManagerView()
        }
        .task { await pollServerStatus() }
        .task(id: workflow.selectedRunId) {
            bindSelectedRunLogs()
        }
        .onDisappear {
            selectedRunLogTask?.cancel()
        }
    }

    // MARK: - Server polling

    private func pollServerStatus() async {
        while !Task.isCancelled {
            let up = await A2AClient.shared.ping()
            serverOnline = up
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func startHarnessServer() {
        guard !startingServer else { return }
        startingServer = true
        mgr.addLine("⚡ Starting harness control-plane server…", level: .info)
        Task {
            await launcher.restart()
            let up = await A2AClient.shared.ping()
            serverOnline = up
            startingServer = false
            mgr.addLine(up ? "✅ Harness control-plane server online" : "❌ Harness control-plane failed to start — check the Terminal tab",
                        level: up ? .success : .error)
        }
    }

    private func bindSelectedRunLogs() {
        selectedRunLogTask?.cancel()
        selectedRunLogs = []
        guard let runId = workflow.selectedRunId, !runId.isEmpty else { return }
        selectedRunLogTask = A2AClient.shared.streamLogs(runId: runId) { lines in
            self.selectedRunLogs = lines
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Coordinator Console")
                    .font(.system(size: 13, weight: .bold))
                if let active = mgr.active {
                    Text("Planner selection: \(active.label)")
                        .font(.system(size: 10))
                        .foregroundColor(active.type.accentColor)
                }
                if let task = workflow.selectedTaskTitle {
                    Text(task)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // ── Control-plane status ────────────────────────────────────────
            HStack(spacing: 6) {
                Circle()
                    .fill(serverOnline
                          ? Color(red: 0.0, green: 0.88, blue: 0.45)
                          : Color.red)
                    .frame(width: 6, height: 6)
                Text(serverOnline ? "Server online" : "Server offline")
                    .font(.system(size: 10))
                    .foregroundColor(serverOnline ? .secondary : .red)

                if !serverOnline {
                    Button(startingServer ? "Starting…" : "Start Server") {
                        startHarnessServer()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .disabled(startingServer)
                    .tint(.orange)
                }
            }

            // LM Studio manager button
            if mgr.coordinators.contains(where: { $0.type == .lmStudio }) {
                Button { showModelManager = true } label: {
                    Label("Manage Models", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Browse, download, and manage LM Studio models")
            }

            Button { mgr.clearOutput() } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Clear output")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Command input

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Use the Planner tab to choose the coordinating LLM, set sub-agent model and team behavior, and launch kanban tasks. This console is for manual prompts and live coordinator output.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                if workflow.hasSelection {
                    HStack(spacing: 8) {
                        if let runId = workflow.selectedRunId, !runId.isEmpty {
                            Label(String(runId.prefix(12)), systemImage: "waveform.path.ecg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let runtime = workflow.selectedRuntime, !runtime.isEmpty {
                            Text(runtime)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if mgr.active?.type == .lmStudio {
                Divider()
                lmParamsRow
                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Command  ·  ⌘↵ to send", systemImage: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                HStack(alignment: .bottom, spacing: 10) {
                    // CommandTextEditor handles ⌘↵ at the AppKit level
                    CommandTextEditor(text: $commandText, onSubmit: runCommand,
                                      placeholder: "Send a manual prompt to the coordinator selected in Planner…",
                                      submitOnCommandReturn: true,
                                      autoFocus: true)
                        .frame(minHeight: 72, maxHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(white: 0.25), lineWidth: 0.5)
                        )

                    Button(action: runCommand) {
                        VStack(spacing: 4) {
                            Image(systemName: mgr.isDispatching ? "hourglass" : "paperplane.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(mgr.isDispatching ? "…" : "Run")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .frame(width: 54, height: 54)
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(mgr.active?.type.accentColor ?? .accentColor)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || mgr.isDispatching)
                    .help("Send to \(mgr.active?.label ?? "coordinator") (⌘↵)")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - LM Studio params row

    private var lmParamsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Toggle header
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showLMParams.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9))
                    Text("LM PARAMETERS")
                        .font(.system(size: 9, weight: .semibold))
                    Text("temp:\(String(format: "%.2f", mgr.lmSettings.temperature))  tokens:\(mgr.lmSettings.maxTokens)  top-p:\(String(format: "%.2f", mgr.lmSettings.topP))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: showLMParams ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(Color(red: 0.94, green: 0.72, blue: 0.18)) // amber
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if showLMParams {
                VStack(spacing: 10) {
                    // Temperature
                    HStack(spacing: 10) {
                        Text("Temp")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 60, alignment: .trailing)
                        Slider(value: $mgr.lmSettings.temperature, in: 0.0...2.0, step: 0.05)
                            .tint(Color(red: 0.94, green: 0.72, blue: 0.18))
                        Text(String(format: "%.2f", mgr.lmSettings.temperature))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 36)
                    }

                    // Top-P
                    HStack(spacing: 10) {
                        Text("Top-P")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 60, alignment: .trailing)
                        Slider(value: $mgr.lmSettings.topP, in: 0.0...1.0, step: 0.05)
                            .tint(Color(red: 0.94, green: 0.72, blue: 0.18))
                        Text(String(format: "%.2f", mgr.lmSettings.topP))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 36)
                    }

                    // Max tokens
                    HStack(spacing: 10) {
                        Text("Max Tokens")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 60, alignment: .trailing)
                        Slider(value: Binding(
                            get: { Double(mgr.lmSettings.maxTokens) },
                            set: { mgr.lmSettings.maxTokens = Int($0) }
                        ), in: 128...8192, step: 128)
                        .tint(Color(red: 0.94, green: 0.72, blue: 0.18))
                        Text("\(mgr.lmSettings.maxTokens)")
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 36)
                    }

                    // System prompt override
                    HStack(alignment: .top, spacing: 10) {
                        Text("System")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 60, alignment: .trailing)
                            .padding(.top, 4)
                        CommandTextEditor(
                            text: $mgr.lmSettings.systemPromptOverride,
                            placeholder: "Leave empty to use the harness default…"
                        )
                            .frame(height: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(white: 0.25), lineWidth: 0.5)
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Output stream

    private var outputStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let runId = workflow.selectedRunId, !runId.isEmpty {
                        consoleSectionHeader("Selected Run Feed · \(String(runId.prefix(12)))")
                        if selectedRunLogs.isEmpty {
                            Text("Waiting for run output…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.5))
                        } else {
                            ForEach(selectedRunLogs) { line in
                                LogLineRow(line: line)
                                    .id(line.id)
                            }
                        }
                    }

                    consoleSectionHeader("Coordinator Output")
                    if mgr.outputLines.isEmpty {
                        Text("Awaiting command…")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.35))
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(mgr.outputLines) { line in
                            OutputLineRow(line: line)
                                .id(line.id)
                        }
                    }
                    // Anchor for auto-scroll
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onChange(of: mgr.outputLines.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: selectedRunLogs.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .background(Color(NSColor.underPageBackgroundColor))
    }

    // MARK: - Actions

    private func runCommand() {
        let task = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }
        commandText = ""
        Task { await mgr.dispatch(task: task) }
    }
}

private struct ConsoleSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.7)
            .padding(.top, 2)
    }
}

private func consoleSectionHeader(_ title: String) -> some View {
    ConsoleSectionHeader(title: title)
}

// MARK: - Output line row

private struct OutputLineRow: View {
    let line: CoordinatorOutputLine

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: line.timestamp)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timeString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))
                .frame(width: 54, alignment: .trailing)
                .padding(.top, 1)

            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(line.color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Add Coordinator Sheet

struct AddCoordinatorSheet: View {
    @Binding var isPresented: Bool
    @State private var type: CoordinatorType = .lmStudio
    @State private var label = ""
    @State private var endpoint = "http://localhost:1234"
    @State private var selectedModelId = ""
    @State private var discoveredModels: [LMStudioModel] = []
    @State private var isDiscovering = false
    @State private var discoveryError: String? = nil

    // Debounce endpoint edits before re-fetching
    @State private var endpointDebounceTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Coordinator")
                .font(.title3.bold())

            // Type
            Picker("Type", selection: $type) {
                ForEach(CoordinatorType.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: type) { _, _ in prefill() }

            // Label
            LabeledContent("Label") {
                TextField("e.g. Qwen2.5-Coder-7B", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            if type == .lmStudio {
                // Endpoint + refresh button
                LabeledContent("Endpoint") {
                    HStack(spacing: 6) {
                        TextField("http://localhost:1234", text: $endpoint)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: endpoint) { _, _ in scheduleDiscovery() }
                        Button {
                            Task { await discover() }
                        } label: {
                            Image(systemName: isDiscovering ? "arrow.clockwise" : "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .rotationEffect(isDiscovering ? .degrees(360) : .zero)
                                .animation(
                                    isDiscovering
                                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                        : .default,
                                    value: isDiscovering
                                )
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDiscovering)
                        .help("Refresh model list from LM Studio")
                    }
                }

                // Model picker — auto-populates
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Model")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if isDiscovering {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.6)
                                Text("Scanning LM Studio…")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        } else if !discoveredModels.isEmpty {
                            Text("\(discoveredModels.count) model(s) loaded")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    if discoveredModels.isEmpty && !isDiscovering {
                        // Empty / error state
                        HStack(spacing: 8) {
                            Image(systemName: discoveryError != nil ? "exclamationmark.triangle" : "info.circle")
                                .foregroundStyle(discoveryError != nil ? .orange : .secondary)
                                .font(.caption)
                            Text(discoveryError ?? "No models found — is LM Studio running with a model loaded?")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if !discoveredModels.isEmpty {
                        ScrollView {
                            VStack(spacing: 3) {
                                ForEach(discoveredModels) { m in
                                    ModelRow(model: m, isSelected: m.id == selectedModelId)
                                        .onTapGesture {
                                            selectedModelId = m.id
                                            if label.isEmpty { label = m.shortName }
                                        }
                                }
                            }
                        }
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                }
            }

            Spacer()

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add") { addCoordinator() }
                    .buttonStyle(.borderedProminent)
                    .disabled(label.isEmpty || (type == .lmStudio && selectedModelId.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 420, height: 380)
        .onAppear { prefill() }
    }

    // MARK: - Helpers

    private func prefill() {
        switch type {
        case .codex:
            label = "Codex"; endpoint = ""; selectedModelId = "gpt-5.3-codex"
        case .claude:
            label = "Claude Code"; endpoint = ""; selectedModelId = "claude-opus-4-5"
        case .kimi:
            label = "Kimi Code"; endpoint = ""
            selectedModelId = ProcessInfo.processInfo.environment["KIMI_BINARY"] ?? "kimi"
        case .lmStudio:
            label = ""; endpoint = "http://localhost:1234"; selectedModelId = ""
            // Auto-discover immediately
            Task { await discover() }
        }
    }

    private func scheduleDiscovery() {
        endpointDebounceTask?.cancel()
        endpointDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s debounce
            guard !Task.isCancelled else { return }
            await discover()
        }
    }

    @MainActor
    private func discover() async {
        guard type == .lmStudio else { return }
        isDiscovering = true
        discoveryError = nil
        let models = await LMStudioEngine.shared.listModels(endpoint: endpoint)
        discoveredModels = models
        isDiscovering = false
        if models.isEmpty {
            discoveryError = "Could not reach LM Studio at \(endpoint)"
        } else {
            // Sort: loaded models first, then alphabetical by shortName
            let sorted = models.sorted {
                if $0.isLoaded != $1.isLoaded { return $0.isLoaded }
                return $0.shortName < $1.shortName
            }
            discoveredModels = sorted
            if selectedModelId.isEmpty || !sorted.map(\.id).contains(selectedModelId) {
                selectedModelId = sorted[0].id
                if label.isEmpty { label = sorted[0].shortName }
            }
        }
    }

    private func addCoordinator() {
        let config = CoordinatorConfig(
            type: type, label: label,
            endpoint: endpoint, model: selectedModelId, isBuiltIn: false)
        CoordinatorManager.shared.add(config)
        isPresented = false
    }
}

// MARK: - Model row

private struct ModelRow: View {
    let model: LMStudioModel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Type icon
            Image(systemName: model.typeIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(model.shortName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)

                    // "LIVE" badge for models actively loaded in VRAM
                    if model.isLoaded {
                        Text("LIVE")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color(red: 0.0, green: 0.88, blue: 0.45)))
                    }
                }
                if let pub = model.publisher {
                    Text(pub)
                        .font(.system(size: 9))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                }
            }

            Spacer()

            if let ctx = model.contextLabel {
                Text(ctx)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(
                        Capsule().fill(isSelected
                            ? Color.white.opacity(0.2)
                            : Color.secondary.opacity(0.15))
                    )
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.07))
        )
        .animation(.easeOut(duration: 0.1), value: isSelected)
    }
}

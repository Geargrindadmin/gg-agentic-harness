// ControlPanelView.swift — Mission control for coordinator agents.
// Switch between Claude API, Kimi CLI, LM Studio, and dispatch commands.

import SwiftUI

struct ControlPanelView: View {
    @EnvironmentObject private var launcher: LaunchManager
    @StateObject private var mgr = CoordinatorManager.shared
    @State private var commandText = ""
    @State private var showAddSheet = false
    @State private var showModelManager = false
    @State private var showLMParams = false
    @State private var serverOnline = false
    @State private var startingServer = false
    @FocusState private var commandFocused: Bool
    @Namespace private var scroll

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            headerBar

            Divider()

            // ── Coordinator cards ────────────────────────────────────────────
            coordinatorRow

            Divider()

            // ── Command input ────────────────────────────────────────────────
            commandSection

            Divider()

            // ── Output stream ────────────────────────────────────────────────
            outputStream
        }
        .background(Color(NSColor.underPageBackgroundColor))
        .navigationTitle("Control Panel")
        .sheet(isPresented: $showAddSheet) {
            AddCoordinatorSheet(isPresented: $showAddSheet)
        }
        .sheet(isPresented: $showModelManager) {
            LMStudioManagerView()
        }
        .task { await pollServerStatus() }
    }

    // MARK: - Server polling

    private func pollServerStatus() async {
        while !Task.isCancelled {
            let up = await A2AClient.shared.ping()
            serverOnline = up
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func startA2AServer() {
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

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Coordinator Control")
                    .font(.system(size: 13, weight: .bold))
                if let active = mgr.active {
                    Text("Active: \(active.label)")
                        .font(.system(size: 10))
                        .foregroundColor(active.type.accentColor)
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
                        startA2AServer()
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

    // MARK: - Coordinator cards row

    private var coordinatorRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(mgr.coordinators) { coord in
                    CoordinatorCard(
                        config: coord,
                        isActive: coord.id == mgr.activeId
                    ) {
                        mgr.setActive(id: coord.id)
                    } onDelete: {
                        mgr.remove(id: coord.id)
                    }
                }

                // Add button
                Button {
                    showAddSheet = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("Add")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .frame(width: 80, height: 88)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(white: 0.09))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(white: 0.22).opacity(0.6),
                                            style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Add coordinator")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 112)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Command input

    private var commandSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            workerRoutingRow
            Divider()

            // LM Studio params row — collapsible
            if mgr.active?.type == .lmStudio {
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
                                      placeholder: "Type a task or command…",
                                      submitOnCommandReturn: true)
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

    // MARK: - Worker routing controls

    private var workerRoutingRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Worker Routing")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backend")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $mgr.runtimeSettings.workerBackend) {
                        Text("kimi-pool").tag("kimi-pool")
                        Text("kimi-bridge-agent").tag("kimi-bridge-agent")
                        Text("kimi-bridge-swarm").tag("kimi-bridge-swarm")
                        Text("lm-studio").tag("lm-studio")
                        Text("jcode-direct").tag("jcode-direct")
                        Text("litellm-gateway").tag("litellm-gateway")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Worker Model")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("kimi-3.5", text: $mgr.runtimeSettings.workerModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minWidth: 200)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Dispatch Path")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("kimi-pool", text: $mgr.runtimeSettings.dispatchPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minWidth: 180)
                }
            }
            .padding(.horizontal, 16)

            if isBridgeWorkerBackend {
                VStack(alignment: .leading, spacing: 8) {
                    if isBridgeSwarmBackend {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Agents")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                TextField("4", text: bridgeAgentsBinding)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 80)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Strategy")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Picker("", selection: $mgr.runtimeSettings.bridgeStrategy) {
                                    Text("parallel").tag("parallel")
                                    Text("sequential").tag("sequential")
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 120)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Roles")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                TextField("planner, builder, reviewer", text: $mgr.runtimeSettings.bridgeRoles)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(minWidth: 240)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Worktree")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField(".", text: $mgr.runtimeSettings.bridgeWorktree)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(minWidth: 160)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Timeout (s)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("1800", text: bridgeTimeoutBinding)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 100)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bridge Context")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("Optional extra context for spawned Kimi work", text: $mgr.runtimeSettings.bridgeContext, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                .padding(.horizontal, 16)
            } else if isUnsupportedWorkerBackend {
                Text("This backend is visible for planning, but direct `lm-studio` and `jcode-direct` execution is not implemented in the harness control-plane yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var isBridgeWorkerBackend: Bool {
        mgr.runtimeSettings.workerBackend == "kimi-bridge-agent" || mgr.runtimeSettings.workerBackend == "kimi-bridge-swarm"
    }

    private var isBridgeSwarmBackend: Bool {
        mgr.runtimeSettings.workerBackend == "kimi-bridge-swarm"
    }

    private var isUnsupportedWorkerBackend: Bool {
        mgr.runtimeSettings.workerBackend == "lm-studio" || mgr.runtimeSettings.workerBackend == "jcode-direct"
    }

    private var bridgeAgentsBinding: Binding<String> {
        Binding(
            get: { String(mgr.runtimeSettings.bridgeAgents) },
            set: { newValue in
                if let parsed = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines)), parsed > 0 {
                    mgr.runtimeSettings.bridgeAgents = parsed
                }
            }
        )
    }

    private var bridgeTimeoutBinding: Binding<String> {
        Binding(
            get: { String(mgr.runtimeSettings.bridgeTimeoutSeconds) },
            set: { newValue in
                if let parsed = Int(newValue.trimmingCharacters(in: .whitespacesAndNewlines)), parsed > 0 {
                    mgr.runtimeSettings.bridgeTimeoutSeconds = parsed
                }
            }
        )
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
                            placeholder: "Leave empty to use GGAS default…"
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
                LazyVStack(alignment: .leading, spacing: 3) {
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

// MARK: - Coordinator Card

private struct CoordinatorCard: View {
    let config: CoordinatorConfig
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Top: type badge + active check
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

                // Label
                Text(config.label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(1)

                Spacer()

                // Status dot
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
            .frame(width: 130, height: 88, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: isActive ? 0.15 : (hovered ? 0.13 : 0.10)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isActive
                                    ? config.type.accentColor.opacity(0.70)
                                    : Color(white: hovered ? 0.30 : 0.20),
                                lineWidth: isActive ? 1.5 : 1
                            )
                    )
            )
            .animation(.easeOut(duration: 0.12), value: isActive)
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            if !config.isBuiltIn {
                Button("Remove", role: .destructive, action: onDelete)
            }
        }
        .help(config.isBuiltIn ? config.label : "\(config.label) — right-click to remove")
    }
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
        case .claude:
            label = "Claude API"; endpoint = ""; selectedModelId = "claude-opus-4-5"
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

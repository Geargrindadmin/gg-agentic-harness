import SwiftUI

struct IntegrationControlSurfaceView: View {
    @State private var settings = IntegrationControlSurfaceView.defaultSettings()
    @State private var catalog: [MCPServerCatalogItem] = []
    @State private var selectedCatalogIds: Set<String> = []

    @State private var selectedQualityTools: Set<String> = ["lint", "test"]
    @State private var qualityProfile: String = "quick"
    @State private var activeQualityJob: QualityJobModel? = nil

    @State private var loading = false
    @State private var saving = false
    @State private var runningQuality = false
    @State private var applyingCatalog = false
    @State private var statusMessage: String? = nil

    private let availableQualityTools = ["lint", "type-check", "test", "build"]

    var body: some View {
        GroupBox("AI Integration Control Surfaces") {
            VStack(alignment: .leading, spacing: 14) {
                liteLLMSection
                Divider()
                observabilitySection
                Divider()
                qualitySection
                Divider()
                mcpCatalogSection

                HStack {
                    if let message = statusMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if loading || saving {
                        ProgressView().scaleEffect(0.7)
                    }
                    Button(saving ? "Saving…" : "Save Integration Settings") {
                        Task { await saveSettings() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || loading)
                    .font(.caption)
                }
            }
            .padding(4)
        }
        .task {
            await reloadAll()
        }
    }

    // MARK: - Sections

    private var liteLLMSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("LiteLLM Coordinator Gateway", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Enable LiteLLM coordination before worker dispatch", isOn: $settings.liteLLM.enabled)
                .font(.caption)
            HStack(spacing: 10) {
                TextField("Base URL", text: $settings.liteLLM.baseUrl)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $settings.liteLLM.model)
                    .textFieldStyle(.roundedBorder)
                TextField("Timeout ms", value: $settings.liteLLM.timeoutMs, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
            HStack(spacing: 10) {
                SecureField("LiteLLM API key (optional)", text: $settings.liteLLM.apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Temp")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $settings.liteLLM.temperature, in: 0...1.2, step: 0.05)
                    .frame(maxWidth: 120)
                Text(String(format: "%.2f", settings.liteLLM.temperature))
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 34)
                TextField("Max tokens", value: $settings.liteLLM.maxTokens, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
        }
    }

    private var observabilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Langfuse + OpenLLMetry", systemImage: "waveform.path.ecg")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Enable observability export", isOn: $settings.observability.enabled)
                .font(.caption)
            HStack(spacing: 10) {
                TextField("Service name", text: $settings.observability.serviceName)
                    .textFieldStyle(.roundedBorder)
                TextField("Environment", text: $settings.observability.environment)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Langfuse", isOn: $settings.observability.langfuse.enabled)
                .font(.caption)
            HStack(spacing: 10) {
                TextField("Langfuse host", text: $settings.observability.langfuse.host)
                    .textFieldStyle(.roundedBorder)
                TextField("Public key", text: $settings.observability.langfuse.publicKey)
                    .textFieldStyle(.roundedBorder)
                SecureField("Secret key", text: $settings.observability.langfuse.secretKey)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("OpenLLMetry OTLP", isOn: $settings.observability.openllmetry.enabled)
                .font(.caption)
            TextField("OTLP endpoint", text: $settings.observability.openllmetry.otlpEndpoint)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Harness Validation Runner", systemImage: "checklist.checked")
                .font(.caption).foregroundStyle(.secondary)
            Text("Runs deterministic repo checks through the headless harness. Tooling here mirrors the control-plane server, not external scanners.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(availableQualityTools, id: \.self) { tool in
                    qualityToggle(tool)
                }
            }
            HStack(spacing: 10) {
                TextField("Project root", text: $settings.qualityTools.defaultProjectRoot)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $qualityProfile) {
                    Text("quick").tag("quick")
                    Text("full").tag("full")
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                Button(runningQuality ? "Running…" : "Run Selected Tools") {
                    Task { await runQuality() }
                }
                .buttonStyle(.bordered)
                .disabled(runningQuality || selectedQualityTools.isEmpty)
            }

            if let job = activeQualityJob {
                HStack(spacing: 8) {
                    Text("Job: \(job.id)")
                    Text("Status: \(job.status)")
                    Text("Exit: \(job.exitCode.map(String.init) ?? "—")")
                }
                .font(.system(size: 10, design: .monospaced))
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(job.output.suffix(120), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(line.lowercased().contains("failed") ? .red : .secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 120)
                .padding(6)
                .background(Color.black.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var mcpCatalogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Curated Open-Source MCP Catalog", systemImage: "shippingbox")
                .font(.caption).foregroundStyle(.secondary)

            TextField("Kimi MCP config path", text: $settings.mcpCatalog.kimiConfigPath)
                .textFieldStyle(.roundedBorder)

            if catalog.isEmpty {
                Text("No catalog entries loaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(catalog) { item in
                        Toggle(isOn: Binding(
                            get: { selectedCatalogIds.contains(item.id) },
                            set: { enabled in
                                if enabled {
                                    selectedCatalogIds.insert(item.id)
                                } else {
                                    selectedCatalogIds.remove(item.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(item.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Reload Catalog") { Task { await reloadCatalog() } }
                    .buttonStyle(.bordered)
                Button(applyingCatalog ? "Applying…" : "Apply Selection to .mcp.kimi.json") {
                    Task { await applyCatalogSelection() }
                }
                .buttonStyle(.bordered)
                .disabled(applyingCatalog)
                Spacer()
                Text("Selected: \(selectedCatalogIds.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func qualityToggle(_ tool: String) -> some View {
        Toggle(tool, isOn: Binding(
            get: { selectedQualityTools.contains(tool) },
            set: { enabled in
                if enabled {
                    selectedQualityTools.insert(tool)
                } else {
                    selectedQualityTools.remove(tool)
                }
                setToolFlag(tool, enabled: enabled)
            }
        ))
        .toggleStyle(.checkbox)
        .font(.caption)
    }

    private func setToolFlag(_ tool: String, enabled: Bool) {
        switch tool {
        case "promptfoo": settings.qualityTools.tools.promptfoo = enabled
        case "semgrep": settings.qualityTools.tools.semgrep = enabled
        case "trivy": settings.qualityTools.tools.trivy = enabled
        case "gitleaks": settings.qualityTools.tools.gitleaks = enabled
        default: break
        }
    }

    private func resetSelectedToolsFromSettings() {
        var selected = Set<String>()
        if settings.qualityTools.tools.promptfoo { selected.insert("promptfoo") }
        if settings.qualityTools.tools.semgrep { selected.insert("semgrep") }
        if settings.qualityTools.tools.trivy { selected.insert("trivy") }
        if settings.qualityTools.tools.gitleaks { selected.insert("gitleaks") }
        selectedQualityTools = selected
    }

    private func reloadAll() async {
        loading = true
        defer { loading = false }
        do {
            let loaded = try await A2AClient.shared.fetchIntegrationSettings()
            settings = loaded
            selectedQualityTools = ["lint", "test"]
            await reloadCatalog()
            statusMessage = "Integration settings loaded"
        } catch {
            statusMessage = "Failed to load integration settings: \(error.localizedDescription)"
        }
    }

    private func reloadCatalog() async {
        do {
            let response = try await A2AClient.shared.fetchMcpCatalog()
            catalog = response.servers
            selectedCatalogIds = Set(response.selectedServerIds)
        } catch {
            statusMessage = "Failed to load MCP catalog: \(error.localizedDescription)"
        }
    }

    private func saveSettings() async {
        saving = true
        defer { saving = false }
        do {
            settings.mcpCatalog.selectedServerIds = Array(selectedCatalogIds)
            settings = try await A2AClient.shared.saveIntegrationSettings(settings)
            statusMessage = "Integration settings saved"
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func runQuality() async {
        runningQuality = true
        defer { runningQuality = false }
        do {
            let tools = Array(selectedQualityTools).sorted()
            let job = try await A2AClient.shared.startQualityJob(tools: tools, profile: qualityProfile)
            activeQualityJob = job
            statusMessage = "Started quality job \(job.id)"
            await pollQualityJob(job.id)
        } catch {
            statusMessage = "Failed to run quality job: \(error.localizedDescription)"
        }
    }

    private func pollQualityJob(_ id: String) async {
        for _ in 0..<60 {
            do {
                let latest = try await A2AClient.shared.fetchQualityJob(id)
                activeQualityJob = latest
                if latest.status == "complete" || latest.status == "completed" || latest.status == "failed" {
                    statusMessage = "Quality job \(latest.status)"
                    return
                }
            } catch {
                statusMessage = "Polling error: \(error.localizedDescription)"
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        statusMessage = "Quality job polling timeout"
    }

    private func applyCatalogSelection() async {
        applyingCatalog = true
        defer { applyingCatalog = false }
        do {
            _ = try await A2AClient.shared.applyMcpCatalog(serverIds: Array(selectedCatalogIds).sorted())
            statusMessage = "Catalog selection applied to .mcp.kimi.json"
            await reloadCatalog()
        } catch {
            statusMessage = "Apply failed: \(error.localizedDescription)"
        }
    }

    private static func defaultSettings() -> IntegrationSettingsModel {
        let home = NSHomeDirectory()
        let configuredRoot = ProjectSettings.shared.projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackRoot = configuredRoot.isEmpty ? home + "/Documents/gg-agentic-harness" : configuredRoot
        return IntegrationSettingsModel(
            liteLLM: .init(
                enabled: false,
                baseUrl: "http://localhost:4000",
                apiKey: "",
                model: "lmstudio",
                temperature: 0.2,
                maxTokens: 1200,
                timeoutMs: 12000
            ),
            observability: .init(
                enabled: false,
                serviceName: "gg-control-plane-server",
                environment: "development",
                langfuse: .init(enabled: false, host: "http://localhost:3000", publicKey: "", secretKey: ""),
                openllmetry: .init(enabled: false, otlpEndpoint: "http://localhost:4318/v1/logs", headers: [:])
            ),
            qualityTools: .init(
                defaultProjectRoot: fallbackRoot,
                tools: .init(promptfoo: true, semgrep: true, trivy: true, gitleaks: true)
            ),
            mcpCatalog: .init(catalogPath: "", kimiConfigPath: fallbackRoot + "/.mcp.json", selectedServerIds: [])
        )
    }
}

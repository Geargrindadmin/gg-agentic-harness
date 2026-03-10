import SwiftUI
import WebKit

struct HarnessView: View {
    @EnvironmentObject private var launcher: LaunchManager
    @ObservedObject private var projectSettings = ProjectSettings.shared
    @State private var settings = HarnessSettingsModel.defaults
    @State private var diagram: HarnessDiagramModel?
    @State private var compatibility: ControlPlaneCompatibility?
    @State private var loading = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var retryBackoffText = "1, 2, 4"
    @State private var cpuHighText = ""
    @State private var cpuLowText = ""
    @State private var modelVramText = ""
    @State private var perAgentText = ""
    @State private var reservedRamText = ""
    @State private var promptVersionText = ""
    @State private var workflowVersionText = ""
    @State private var blueprintVersionText = ""
    @State private var toolBundleText = ""

    private let promptImproverModes = ["off", "auto", "force"]
    private let contextSources = ["standard", "codegraphcontext", "hybrid"]
    private let hydraModes = ["off", "shadow", "active"]
    private let validateModes = ["none", "tsc", "lint", "test", "all"]
    private let docSyncModes = ["auto", "off"]
    private let riskTiers = ["", "low", "medium", "high"]

    var body: some View {
        HSplitView {
            diagramPane
                .frame(minWidth: 760, idealWidth: 980)

            settingsPane
                .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
        }
        .padding(16)
        .navigationTitle("Harness")
        .task { await refresh() }
    }

    private var diagramPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live Harness Diagram")
                        .font(.title3.weight(.semibold))
                    Text("Local HTML artifact with live hydration from the headless control plane.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if loading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Refresh") {
                    Task { await refresh() }
                }
                .buttonStyle(.bordered)
            }

            if let diagram {
                HStack(spacing: 10) {
                    liveMetric("Running Runs", "\(diagram.live.activity.runningRuns)")
                    liveMetric("Active Workers", "\(diagram.live.activity.activeWorkers)")
                    liveMetric("Loop Budget", "\(settings.execution.loopBudget)")
                    liveMetric("Retries", "\(settings.execution.retryLimit)")
                }
            }

            GroupBox {
                if let fileURL = diagramFileURL {
                    HarnessDiagramWebView(
                        fileURL: fileURL,
                        projectRoot: projectSettings.projectRoot,
                        controlPlaneBaseURL: projectSettings.normalizedControlPlaneBaseURL
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Diagram artifact not found")
                            .font(.headline)
                        Text(diagramRelativePath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                }
            }

            if let diagram {
                GroupBox("Live Summary") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Current activity is sourced from `\(projectSettings.normalizedControlPlaneBaseURL)/api/harness/diagram`.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let latestTask = diagram.live.activity.latestTask, !latestTask.isEmpty {
                            LabeledContent("Latest Task", value: latestTask)
                        }
                        if let latestRunId = diagram.live.activity.latestRunId {
                            LabeledContent("Latest Run", value: latestRunId)
                        }
                        LabeledContent("Allowed Workers", value: "\(diagram.live.status.governor.allowedAgents)")
                        LabeledContent("Pending Messages", value: "\(diagram.live.activity.pendingMessages)")
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }

    private var settingsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard

                GroupBox("Execution Policy") {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper("Loop Budget: \(settings.execution.loopBudget)", value: $settings.execution.loopBudget, in: 1...500)
                        Stepper("Retry Limit: \(settings.execution.retryLimit)", value: $settings.execution.retryLimit, in: 0...10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Retry Backoff (seconds)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("1, 2, 4", text: $retryBackoffText)
                                .textFieldStyle(.roundedBorder)
                        }

                        harnessPicker("Prompt Improver", selection: $settings.execution.promptImproverMode, options: promptImproverModes)
                        harnessPicker("Context Source", selection: $settings.execution.contextSource, options: contextSources)
                        harnessPicker("Hydra Mode", selection: $settings.execution.hydraMode, options: hydraModes)
                        harnessPicker("Validate Mode", selection: $settings.execution.validateMode, options: validateModes)
                        harnessPicker("Doc Sync Mode", selection: $settings.execution.docSyncMode, options: docSyncModes)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Governor Overrides") {
                    VStack(alignment: .leading, spacing: 10) {
                        optionalNumberField("CPU High %", text: $cpuHighText)
                        optionalNumberField("CPU Low %", text: $cpuLowText)
                        optionalNumberField("Model VRAM GB", text: $modelVramText)
                        optionalNumberField("Per-Agent Overhead GB", text: $perAgentText)
                        optionalNumberField("Reserved RAM GB", text: $reservedRamText)
                        Text("Leave governor fields blank to keep environment or built-in defaults.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Run Metadata Defaults") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Prompt version", text: $promptVersionText)
                            .textFieldStyle(.roundedBorder)
                        TextField("Workflow version", text: $workflowVersionText)
                            .textFieldStyle(.roundedBorder)
                        TextField("Blueprint version", text: $blueprintVersionText)
                            .textFieldStyle(.roundedBorder)
                        TextField("Tool bundle", text: $toolBundleText)
                            .textFieldStyle(.roundedBorder)
                        harnessPicker("Risk Tier", selection: Binding(
                            get: { settings.artifacts.riskTier ?? "" },
                            set: { settings.artifacts.riskTier = $0.isEmpty ? nil : $0 }
                        ), options: riskTiers)
                    }
                    .padding(.top, 4)
                }

                if let successMessage, !successMessage.isEmpty {
                    Text(successMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var headerCard: some View {
        GroupBox("Headless Harness Settings") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    HarnessConnectionBadge(
                        compatibility: compatibility,
                        launcherState: launcher.state
                    )
                    Spacer()
                    Text(projectSettings.normalizedControlPlaneBaseURL)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Text("These values are stored in the harness itself, so the system still works with no app installed. Dispatch fanout and team composition remain in the existing Planner and Dispatch tabs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let compatibilityMessage {
                    Text(compatibilityMessage)
                        .font(.caption)
                        .foregroundStyle(compatibility?.compatible == true ? Color.secondary : Color.orange)
                }

                HStack(spacing: 8) {
                    Button {
                        Task { await save() }
                    } label: {
                        Label(saving ? "Saving..." : "Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || loading)

                    Button("Reset to Defaults") {
                        Task { await resetToDefaults() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(saving || loading)

                    Button("Reload") {
                        Task { await refresh() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(saving)
                }

                Text("Saved to \(harnessSettingsPath)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Changes apply to newly dispatched runs. In-flight runs keep the policy they started with.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private var compatibilityMessage: String? {
        if let compatibility, let message = compatibility.message, !message.isEmpty {
            return message
        }

        switch launcher.state {
        case .idle:
            return "The local control-plane has not been started from the app yet."
        case .starting:
            return launcher.statusMessage
        case .online:
            if let meta = compatibility?.meta {
                return "Connected to control-plane v\(meta.version) with protocol v\(meta.protocolVersion)."
            }
            return launcher.statusMessage.isEmpty ? nil : launcher.statusMessage
        case .offline, .noScript:
            return launcher.statusMessage.isEmpty ? nil : launcher.statusMessage
        }
    }

    private var harnessSettingsPath: String {
        URL(fileURLWithPath: projectSettings.projectRoot)
            .appendingPathComponent(".agent/control-plane/server/harness-settings.json").path
    }

    private var diagramRelativePath: String {
        diagram?.diagram.artifactRelativePath ?? settings.diagram.primaryArtifact
    }

    private var diagramFileURL: URL? {
        let root = projectSettings.projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return nil }
        let fileURL = URL(fileURLWithPath: root).appendingPathComponent(diagramRelativePath)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    @ViewBuilder
    private func liveMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private func harnessPicker(_ title: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.isEmpty ? "unset" : option).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func optionalNumberField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("env/default", text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func refresh() async {
        loading = true
        errorMessage = nil
        successMessage = nil
        defer { loading = false }

        compatibility = await A2AClient.shared.probeControlPlaneCompatibility()

        do {
            let fetchedSettings = try await A2AClient.shared.fetchHarnessSettings()
            settings = fetchedSettings
            synchronizeEditorState(from: fetchedSettings)
        } catch {
            errorMessage = "Failed to load harness settings: \(error.localizedDescription)"
        }

        do {
            diagram = try await A2AClient.shared.fetchHarnessDiagram()
        } catch {
            if errorMessage == nil {
                errorMessage = "Failed to load live diagram data: \(error.localizedDescription)"
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        successMessage = nil
        defer { saving = false }

        do {
            var next = settings
            next.execution.retryBackoffSeconds = try parseIntegerList(retryBackoffText)
            next.governor.cpuHighPct = parseOptionalDouble(cpuHighText)
            next.governor.cpuLowPct = parseOptionalDouble(cpuLowText)
            next.governor.modelVramGb = parseOptionalDouble(modelVramText)
            next.governor.perAgentOverheadGb = parseOptionalDouble(perAgentText)
            next.governor.reservedRamGb = parseOptionalDouble(reservedRamText)
            next.artifacts.promptVersion = normalizedOptionalText(promptVersionText)
            next.artifacts.workflowVersion = normalizedOptionalText(workflowVersionText)
            next.artifacts.blueprintVersion = normalizedOptionalText(blueprintVersionText)
            next.artifacts.toolBundle = normalizedOptionalText(toolBundleText)

            let saved = try await A2AClient.shared.saveHarnessSettings(next)
            settings = saved
            synchronizeEditorState(from: saved)
            compatibility = await A2AClient.shared.probeControlPlaneCompatibility()
            diagram = try? await A2AClient.shared.fetchHarnessDiagram()
            successMessage = "Saved headless settings to the harness. New runs will use this policy."
        } catch {
            errorMessage = "Failed to save harness settings: \(error.localizedDescription)"
        }
    }

    private func resetToDefaults() async {
        saving = true
        errorMessage = nil
        successMessage = nil
        defer { saving = false }

        do {
            let reset = try await A2AClient.shared.resetHarnessSettings()
            settings = reset
            synchronizeEditorState(from: reset)
            compatibility = await A2AClient.shared.probeControlPlaneCompatibility()
            diagram = try? await A2AClient.shared.fetchHarnessDiagram()
            successMessage = "Restored harness defaults. New runs will use the default policy."
        } catch {
            errorMessage = "Failed to reset harness settings: \(error.localizedDescription)"
        }
    }

    private func synchronizeEditorState(from settings: HarnessSettingsModel) {
        retryBackoffText = settings.execution.retryBackoffSeconds.map(String.init).joined(separator: ", ")
        cpuHighText = optionalNumberString(settings.governor.cpuHighPct)
        cpuLowText = optionalNumberString(settings.governor.cpuLowPct)
        modelVramText = optionalNumberString(settings.governor.modelVramGb)
        perAgentText = optionalNumberString(settings.governor.perAgentOverheadGb)
        reservedRamText = optionalNumberString(settings.governor.reservedRamGb)
        promptVersionText = settings.artifacts.promptVersion ?? ""
        workflowVersionText = settings.artifacts.workflowVersion ?? ""
        blueprintVersionText = settings.artifacts.blueprintVersion ?? ""
        toolBundleText = settings.artifacts.toolBundle ?? ""
    }

    private func parseIntegerList(_ value: String) throws -> [Int] {
        let entries = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let parsed = entries.compactMap(Int.init)
        guard !parsed.isEmpty, parsed.count == entries.count else {
            throw HarnessEditorError.invalidBackoff
        }
        return parsed
    }

    private func parseOptionalDouble(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private func normalizedOptionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func optionalNumberString(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(value)
    }

    private enum HarnessEditorError: LocalizedError {
        case invalidBackoff

        var errorDescription: String? {
            switch self {
            case .invalidBackoff:
                return "Retry backoff must be a comma-separated list of integers."
            }
        }
    }
}

private struct HarnessConnectionBadge: View {
    let compatibility: ControlPlaneCompatibility?
    let launcherState: LaunchManager.State

    private var color: Color {
        if let compatibility {
            if compatibility.compatible {
                return .green
            }
            return compatibility.reachable ? .orange : .red
        }

        switch launcherState {
        case .online:
            return .green
        case .starting:
            return .yellow
        case .offline, .noScript:
            return .red
        case .idle:
            return .secondary
        }
    }

    private var label: String {
        if let compatibility {
            if compatibility.compatible {
                return "Connected"
            }
            return compatibility.reachable ? "Needs Attention" : "Offline"
        }

        switch launcherState {
        case .online:
            return "Connected"
        case .starting:
            return "Starting"
        case .offline, .noScript:
            return "Offline"
        case .idle:
            return "Idle"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
        )
    }
}

private struct HarnessDiagramWebView: NSViewRepresentable {
    let fileURL: URL
    let projectRoot: String
    let controlPlaneBaseURL: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard let requestURL = configuredFileURL else { return }
        if context.coordinator.lastLoadedURL == requestURL {
            return
        }
        context.coordinator.lastLoadedURL = requestURL
        webView.loadFileURL(requestURL, allowingReadAccessTo: URL(fileURLWithPath: projectRoot))
    }

    private var configuredFileURL: URL? {
        guard var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "controlPlane", value: controlPlaneBaseURL)
        ]
        return components.url
    }

    final class Coordinator {
        var lastLoadedURL: URL?
    }
}

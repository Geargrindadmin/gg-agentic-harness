// ConfigView.swift — server status + prerequisites + MCP port map

import SwiftUI

// MARK: - Tool Reinstaller

@MainActor
final class ToolReinstaller: ObservableObject {
    @Published var isRunning = false
    @Published var lastMessage = ""

    func reinstall(_ tool: String) async {
        isRunning = true
        lastMessage = "Reinstalling \(tool)…"

        // Resolve harness project root from user config, not a hardcoded repo path.
        let harnessRoot = ProjectSettings.shared.projectRoot
        let ggForge  = NSHomeDirectory() + "/.ggas/forge/bin/GGForgeMCP"
        let controlPlaneURL = ProjectSettings.shared.normalizedControlPlaneBaseURL

        let script: String
        switch tool {
        case "claude":
            let ggSkills = harnessRoot + "/mcp-servers/gg-skills/dist/index.js"
            let ggBridge = harnessRoot + "/mcp-servers/gg-agent-bridge/dist/index.js"
            let skills   = harnessRoot + "/.agent/skills"
            let flows    = harnessRoot + "/.agent/workflows"
            script = """
            source ~/.nvm/nvm.sh 2>/dev/null || true
            export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
            npm install -g @anthropic-ai/claude-code
            echo "✓ Claude Code reinstalled"

            echo "→ Re-wiring harness MCP services…"
            claude mcp remove gg-skills       -s user 2>/dev/null || true
            claude mcp remove gg-agent-bridge -s user 2>/dev/null || true
            claude mcp remove gg-forge        -s user 2>/dev/null || true
            claude mcp remove context7        -s user 2>/dev/null || true
            claude mcp remove chrome-devtools -s user 2>/dev/null || true
            claude mcp remove obsidian        -s user 2>/dev/null || true

            claude mcp add gg-skills -s user \\
              -e SKILLS_DIR="\(skills)" \\
              -e WORKFLOWS_DIR="\(flows)" \\
              -- node "\(ggSkills)" && echo "✓ gg-skills registered"

            if [ -f "\(ggBridge)" ]; then
              claude mcp add gg-agent-bridge -s user \\
                -e A2A_HTTP_URL="\(controlPlaneURL)" \\
                -- node "\(ggBridge)" && echo "✓ gg-agent-bridge registered"
            else
              echo "ℹ gg-agent-bridge is not present in this repo — skipping bridge registration"
            fi

            if [ -f "\(ggForge)" ]; then
              claude mcp add gg-forge -s user -- "\(ggForge)" && echo "✓ gg-forge registered"
            else
              echo "⚠ gg-forge binary not found — run setup.sh to build it"
            fi

            claude mcp add context7        -s user -- npx -y @upstash/context7-mcp && echo "✓ context7 registered"
            claude mcp add chrome-devtools -s user -- npx -y chrome-devtools-mcp@latest && echo "✓ chrome-devtools registered"
            claude mcp add obsidian        -s user -- npx @mauricio.wolff/mcp-obsidian@latest "\(harnessRoot)" && echo "✓ obsidian registered"

            echo "✓ All MCP services re-wired — restart Claude to activate"
            echo "→ Next: run 'claude' to log in"
            """
        case "kimi":
            script = """
            curl -fsSL code.kimi.com/install.sh | bash
            export PATH="$HOME/.kimi/bin:$HOME/.local/bin:$PATH"
            echo "✓ Kimi Code reinstalled"
            echo "→ .mcp.json and runtime configs are already in \(harnessRoot)"
            echo "→ Next: run 'kimi login' to authenticate"
            """
        default: // node
            script = """
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
            source ~/.nvm/nvm.sh 2>/dev/null || true
            export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            nvm install --lts && nvm use --lts
            node --version && npm --version
            echo "✓ Node.js reinstalled"
            """
        }
        // Run reinstall script in a background shell process
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", script]
        try? proc.run()
        proc.waitUntilExit()
        lastMessage = "Done — see Terminal tab"
        isRunning = false
    }
}

// MARK: - Config View

struct ConfigView: View {
    @EnvironmentObject var launcher: LaunchManager
    @StateObject private var reinstaller = ToolReinstaller()
    @StateObject private var keyStore     = APIKeyStore.shared
    @StateObject private var openClaw     = OpenClawService.shared
    @StateObject private var providerSvc  = ProviderDetectionService.shared
    @State private var showAdvancedConfig = false

    @State private var a2aOnline      = false
    @State private var plannerStoreExists  = false
    @State private var controlPlaneMeta: ControlPlaneMeta? = nil
    @State private var controlPlaneCompatibilityMessage: String? = nil
    @State private var claudeVersion: String? = nil
    @State private var kimiVersion:   String? = nil
    @State private var nodeVersion:   String? = nil
    @State private var npmVersion:    String? = nil
    @State private var geminiKeySet   = false
    @State private var checking       = false
    @State private var showSetupWizard = false

    // Editable API key state
    @State private var editingAnthropicKey = ""
    @State private var editingMoonshotKey  = ""
    @State private var keySaveMessage: String? = nil
    @State private var keySaving = false

    private var plannerStorePath: String {
        let root = ProjectSettings.shared.projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return "" }
        return URL(fileURLWithPath: root)
            .appendingPathComponent(".agent/control-plane/server/planner.json").path
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                servicesSection
                apiKeysSection
                prereqSection
                endpointsSection
                advancedSection
                HStack {
                    Button("Refresh Status") { Task { await refresh() } }.buttonStyle(.bordered)
                    if checking { ProgressView().scaleEffect(0.7) }
                    Spacer()
                    Text("CLI output → Terminal tab").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(16)
        }
        .navigationTitle("Config")
        .task { await refresh() }
        .onChange(of: launcher.state) { _, _ in Task { await refresh() } }
        .sheet(isPresented: $showSetupWizard) { SetupWizardView(showWizard: $showSetupWizard) }
    }

    // MARK: - Sections (extracted to satisfy Swift type-checker)

    @ViewBuilder private var servicesSection: some View {
        GroupBox("Harness Control Plane") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    LaunchStateBadge(state: launcher.state)
                    Text(launcher.statusMessage.isEmpty ? "Ready" : launcher.statusMessage)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { showSetupWizard = true } label: {
                        Label("Reinstall Doctor", systemImage: "stethoscope")
                    }
                    .buttonStyle(.bordered)
                    .help("Re-run the setup wizard to repair Node.js, Claude, or Kimi")

                    if launcher.state == .starting {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Button(launcher.state == .online ? "Restart" : "Start Services") {
                            Task { await launcher.restart() }
                        }.buttonStyle(.borderedProminent)
                    }
                }
                Divider()
                ServerRow(name: "gg-control-plane-server  \(ProjectSettings.shared.normalizedControlPlaneBaseURL)", online: a2aOnline)
                if let controlPlaneMeta {
                    ServerRow(
                        name: "Control Plane Meta",
                        online: true,
                        detail: "v\(controlPlaneMeta.version) · protocol \(controlPlaneMeta.protocolVersion) · \(controlPlaneMeta.capabilities.count) capabilities"
                    )
                } else if let controlPlaneCompatibilityMessage, !controlPlaneCompatibilityMessage.isEmpty {
                    ServerRow(
                        name: "Control Plane Meta",
                        online: false,
                        detail: controlPlaneCompatibilityMessage
                    )
                }
                ServerRow(name: "Planner Store    .agent/control-plane/server/planner.json", online: plannerStoreExists,
                          detail: plannerStoreExists ? nil : "Created automatically when the control-plane serves planner data")
                HStack(spacing: 8) {
                    Text("Control-plane URL")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AppTextField(
                        text: Binding(
                            get: { ProjectSettings.shared.controlPlaneBaseURL },
                            set: { ProjectSettings.shared.controlPlaneBaseURL = $0 }
                        ),
                        placeholder: "http://127.0.0.1:7891",
                        font: .monospacedSystemFont(ofSize: 11, weight: .regular)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
                }
            }.padding(4)
        }
    }

    @ViewBuilder private var integrationSection: some View {
        IntegrationControlSurfaceView()
    }

    @ViewBuilder private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvancedConfig) {
            VStack(alignment: .leading, spacing: 16) {
                integrationSection
                mcpSection
                aiProviderSection
                openClawSection
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Advanced Integrations")
                    .font(.subheadline.weight(.semibold))
                Text("Optional gateways, provider overrides, MCP catalog selection, and external messaging integrations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - API Keys Section

    @ViewBuilder private var apiKeysSection: some View {
        GroupBox("API Keys") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Optional when the harness uses direct provider APIs instead of your local authenticated CLIs.\nKeys are stored in ~/.ggas/env.")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                // Anthropic
                apiKeyRow(
                    label: "Anthropic (Claude)",
                    icon: "cpu.fill",
                    isSet: keyStore.hasAnthropicKey,
                    currentKey: keyStore.currentValue(for: "ANTHROPIC_API_KEY"),
                    editingValue: $editingAnthropicKey,
                    placeholder: "sk-ant-…",
                    docsURL: "https://console.anthropic.com/settings/keys",
                    envKey: "ANTHROPIC_API_KEY"
                )

                Divider()

                // Moonshot / Kimi
                apiKeyRow(
                    label: "Moonshot (Kimi)",
                    icon: "bolt.fill",
                    isSet: keyStore.hasMoonshotKey,
                    currentKey: keyStore.currentValue(for: "MOONSHOT_API_KEY"),
                    editingValue: $editingMoonshotKey,
                    placeholder: "sk-…",
                    docsURL: "https://platform.moonshot.cn/console/api-keys",
                    envKey: "MOONSHOT_API_KEY"
                )

                if let msg = keySaveMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button(keySaving ? "Saving…" : "Save API Keys") {
                    Task { await saveKeys() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keySaving || (editingAnthropicKey.isEmpty && editingMoonshotKey.isEmpty))
                .font(.caption)
            }.padding(4)
        }
    }

    @ViewBuilder
    private func apiKeyRow(
        label: String, icon: String, isSet: Bool,
        currentKey: String?, editingValue: Binding<String>,
        placeholder: String, docsURL: String, envKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(isSet ? .green : .orange)
                    .frame(width: 16)
                Text(label).font(.system(size: 12, weight: .medium))
                Spacer()
                if isSet {
                    Text("set").font(.caption2).foregroundStyle(.green)
                    Button("Clear") {
                        APIKeyStore.shared.clear(envKey)
                        if editingValue.wrappedValue.isEmpty { keySaveMessage = nil }
                    }
                    .font(.caption2).buttonStyle(.borderless).foregroundStyle(.red)
                } else {
                    Text("not set").font(.caption2).foregroundStyle(.orange)
                    if let url = URL(string: docsURL) {
                        Link("Get key ↗", destination: url).font(.caption2).foregroundStyle(.blue)
                    }
                }
            }
            if isSet, let masked = currentKey {
                Text(maskKey(masked)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }
            TextField(isSet ? "Enter new key to replace…" : placeholder, text: editingValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }
    }

    private func maskKey(_ key: String) -> String {
        guard key.count > 8 else { return String(repeating: "•", count: key.count) }
        return key.prefix(6) + String(repeating: "•", count: key.count - 10) + key.suffix(4)
    }

    @MainActor
    private func saveKeys() async {
        keySaving = true
        var bridgeRewired = false
        let anthropic = editingAnthropicKey.trimmingCharacters(in: .whitespaces)
        let moonshot  = editingMoonshotKey.trimmingCharacters(in: .whitespaces)

        // Only overwrite keys that have new values entered
        let finalAnthropic = anthropic.isEmpty ? (keyStore.currentValue(for: "ANTHROPIC_API_KEY") ?? "") : anthropic
        let finalMoonshot  = moonshot.isEmpty  ? (keyStore.currentValue(for: "MOONSHOT_API_KEY")  ?? "") : moonshot

        APIKeyStore.shared.save(anthropic: finalAnthropic, moonshot: finalMoonshot)

        // Re-wire gg-agent-bridge with new keys
        let projectRoot = ProjectSettings.shared.projectRoot
        let ggBridge    = projectRoot + "/mcp-servers/gg-agent-bridge/dist/index.js"
        let controlPlaneURL = ProjectSettings.shared.normalizedControlPlaneBaseURL
        if !projectRoot.isEmpty && !finalAnthropic.isEmpty && FileManager.default.fileExists(atPath: ggBridge) {
            let script = """
            claude mcp remove gg-agent-bridge -s user 2>/dev/null || true
            claude mcp add gg-agent-bridge -s user \\
              -e A2A_HTTP_URL="\(controlPlaneURL)" \\
              -e KIMI_BINARY="$HOME/.local/bin/kimi" \\
              -e PROJECT_ROOT="\(projectRoot)" \\
              -e ANTHROPIC_API_KEY="\(finalAnthropic)" \\
              -e MOONSHOT_API_KEY="\(finalMoonshot)" \\
              -- node "\(ggBridge)" 2>&1
            """
            await Task.detached(priority: .utility) {
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ggas_rekey.sh")
                try? ("#!/bin/bash\n" + script).write(to: tmp, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
                let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [tmp.path]
                p.standardOutput = Pipe(); p.standardError = Pipe()
                try? p.run(); p.waitUntilExit()
                try? FileManager.default.removeItem(at: tmp)
            }.value
            bridgeRewired = true
        }

        editingAnthropicKey = ""
        editingMoonshotKey  = ""
        keySaveMessage = bridgeRewired
            ? "Keys saved to ~/.ggas/env and bridge updated"
            : "Keys saved to ~/.ggas/env"
        keySaving = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.keySaveMessage = nil }
    }

    // MARK: - OpenClaw Section

    @ViewBuilder private var openClawSection: some View {
        GroupBox("OpenClaw Gateway") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Optional self-hosted messaging gateway for Telegram, WhatsApp, and Discord.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                HStack(spacing: 12) {
                    // Status dot
                    Circle()
                        .fill(openClaw.isRunning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(openClaw.isRunning ? "Running on :18789" : "Not running")
                        .font(.system(size: 12))
                    Spacer()
                    if openClaw.isRunning {
                        Button("Open Dashboard ↗") { openClaw.openBrowser() }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        Button("Stop") { openClaw.stop() }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Button("Start Gateway") { openClaw.start() }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                        if let err = openClaw.lastError {
                            Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
                        }
                    }
                }

                // Channel status
                HStack(spacing: 16) {
                    ForEach(openClaw.channels) { ch in
                        HStack(spacing: 5) {
                            Image(systemName: ch.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(ch.connected ? .green : .secondary)
                            Text(ch.label)
                                .font(.caption)
                                .foregroundStyle(ch.connected ? .primary : .secondary)
                        }
                    }
                    Spacer()
                    if !openClaw.isRunning {
                        Link("OpenClaw Docs ↗", destination: URL(string: "https://docs.openclaw.ai")!)
                            .font(.caption2).foregroundStyle(.blue)
                    }
                }
            }.padding(4)
        }
    }

    // MARK: - AI Provider Section

    @ViewBuilder private var aiProviderSection: some View {
        GroupBox("Optional jcode Model Overrides") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Only use this if you want to override model selection for jcode-backed provider flows. Coordinator selection happens in the Control tab.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Refresh Providers") { providerSvc.refresh() }
                        .font(.caption).buttonStyle(.borderless).foregroundStyle(.blue)
                    Spacer()
                }
                Divider()

                if providerSvc.availableProviders.isEmpty {
                    Text("No providers detected. Run gg-cli login or set ANTHROPIC_API_KEY / OPENROUTER_API_KEY.")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    ForEach(providerSvc.availableProviders) { prov in
                        HStack(spacing: 10) {
                            Image(systemName: prov.icon)
                                .frame(width: 16)
                                .foregroundStyle(providerSvc.selectedProvider == prov ? Color.accentColor : Color.secondary)
                            Text(prov.displayName)
                                .font(.system(size: 12))
                            Spacer()
                            if providerSvc.selectedProvider == prov {
                                Picker("", selection: Binding(
                                    get: { providerSvc.selectedModel },
                                    set: { providerSvc.select(provider: prov, model: $0) }
                                )) {
                                    ForEach(prov.models, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .font(.caption)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Button("Select") {
                                    providerSvc.select(provider: prov, model: prov.models.first ?? "")
                                }
                                .font(.caption).buttonStyle(.borderless).foregroundStyle(.blue)
                            }
                        }
                    }
                }
                if !providerSvc.selectedModel.isEmpty {
                    Divider()
                    HStack {
                    Text("Override:").font(.caption.bold()).foregroundStyle(.secondary)
                        Text("\(providerSvc.selectedProvider?.displayName ?? "–") · \(providerSvc.selectedModel)")
                            .font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text("Saved to ~/.ggas/config.json").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }.padding(4)
        }
    }

    @ViewBuilder private var mcpSection: some View {
        GroupBox("MCP Tooling") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Built-in").font(.caption.bold()).foregroundStyle(.secondary)
                mcpRow("gg-control-plane-server", transport: ProjectSettings.shared.normalizedControlPlaneBaseURL, exposes: "HTTP runtime service")
                mcpRow("gg-skills",               transport: "stdio only", exposes: nil)
                Text("The macOS app talks to the harness control-plane over HTTP. MCP tools remain repo-managed and stdio-based.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 2)
            }.padding(4)
        }
    }

    @ViewBuilder private var prereqSection: some View {
        GroupBox("Prerequisites") {
            VStack(alignment: .leading, spacing: 12) {
                // ── Project root picker ────────────────────────────────────
                projectRootRow
                Divider()
                nodeRow
                npmRow
                Divider()
                claudeRow
                Divider()
                kimiRow
                Divider()
                geminiRow
                if reinstaller.isRunning {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text(reinstaller.lastMessage).font(.caption).foregroundStyle(.secondary)
                        Text("→ Terminal tab").font(.caption2).foregroundStyle(.blue)
                    }
                } else if !reinstaller.lastMessage.isEmpty {
                    Text(reinstaller.lastMessage).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(4)
        }
    }

    @ViewBuilder private var projectRootRow: some View {
        let settings = ProjectSettings.shared
        let configured = settings.isConfigured
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: configured ? "folder.fill" : "folder.badge.questionmark")
                .foregroundStyle(configured ? .blue : .orange)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("Project Folder")
                    .font(.system(size: 12, weight: .medium))
                if configured {
                    Text(settings.projectRoot)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Not configured — package installs will fail for non-default paths")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Choose…") { settings.chooseFolder() }
                .buttonStyle(.bordered)
                .font(.caption)
        }
    }

    @ViewBuilder private var nodeRow: some View {
        ToolRow(
            name: "Node.js", version: nodeVersion,
            installNote: "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash",
            docsURL: "https://nodejs.org",
            onRecheck:   { nodeVersion = await shellVersion("node") },
            onReinstall: { await reinstaller.reinstall("node") }
        )
    }

    // npm is bundled with Node.js; re-check only (reinstall Node to repair npm)
    @ViewBuilder private var npmRow: some View {
        HStack(spacing: 8) {
            Image(systemName: npmVersion != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(npmVersion != nil ? .green : .red)
            Text("npm").font(.system(size: 12, design: .monospaced))
            if let v = npmVersion { Text(v).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("Re-check") { Task { npmVersion = await shellVersion("npm") } }
                .font(.caption).buttonStyle(.borderless).foregroundStyle(.blue)
            Text(npmVersion != nil ? "bundled with Node.js" : "install Node.js to get npm")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var claudeRow: some View {
        ToolRow(
            name: "Claude Code CLI", version: claudeVersion,
            installNote: "npm install -g @anthropic-ai/claude-code",
            docsURL: "https://docs.anthropic.com/en/docs/claude-code",
            onRecheck:   { claudeVersion = await shellVersion("claude") },
            onReinstall: { await reinstaller.reinstall("claude") }
        )
    }

    @ViewBuilder private var kimiRow: some View {
        ToolRow(
            name: "Kimi Code 3.5 CLI", version: kimiVersion,
            installNote: "curl -L code.kimi.com/install.sh | bash",
            docsURL: "https://kimi.com/code",
            onRecheck:   { kimiVersion = await shellVersion("kimi") },
            onReinstall: { await reinstaller.reinstall("kimi") }
        )
    }

    @ViewBuilder private var geminiRow: some View {
        HStack(spacing: 8) {
            Image(systemName: geminiKeySet ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(geminiKeySet ? .green : .orange)
            Text("GEMINI_API_KEY").font(.system(size: 12, design: .monospaced))
            Spacer()
            Text(geminiKeySet ? "set" : "not set").font(.caption)
                .foregroundStyle(geminiKeySet ? Color.secondary : Color.orange)
            if !geminiKeySet, let url = URL(string: "https://aistudio.google.com/apikey") {
                Link("Get key ↗", destination: url).font(.caption).foregroundStyle(.blue)
            }
        }
    }

    @ViewBuilder private var endpointsSection: some View {
        GroupBox("Endpoints") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 5) {
                envRow("Control Plane", ProjectSettings.shared.normalizedControlPlaneBaseURL)
                envRow("Control Plane API", ProjectSettings.shared.controlPlaneAPIBaseURL)
                envRow("Realtime",    "SSE via /api/events")
                envRow("Planner",     plannerStorePath.isEmpty ? "(project root not configured)" : plannerStorePath)
            }
            .font(.system(size: 12, design: .monospaced)).padding(4)
        }
    }

    // MARK: - Helpers

    private func refresh() async {
        checking = true
        async let compatibility = A2AClient.shared.probeControlPlaneCompatibility()
        async let cl  = shellVersion("claude")
        async let km  = shellVersion("kimi")
        async let nd  = shellVersion("node")
        async let npm = shellVersion("npm")
        let compatibilityResult = await compatibility
        (claudeVersion, kimiVersion, nodeVersion, npmVersion) =
            await (cl, km, nd, npm)
        a2aOnline = compatibilityResult.compatible
        controlPlaneMeta = compatibilityResult.meta
        controlPlaneCompatibilityMessage = compatibilityResult.message
        plannerStoreExists = !plannerStorePath.isEmpty && FileManager.default.fileExists(atPath: plannerStorePath)
        geminiKeySet  = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil
        checking = false
    }

    private func shellVersion(_ cmd: String) async -> String? {
        await Task.detached(priority: .utility) {
            let pipe = Pipe()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = [cmd, "--version"]
            proc.standardOutput = pipe; proc.standardError = Pipe()
            try? proc.run(); proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let d = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: d, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: "\n").first
        }.value
    }

    private func envRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func mcpRow(_ name: String, transport: String, exposes: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: exposes != nil ? "network" : "lock.shield.fill")
                .foregroundStyle(exposes != nil ? .orange : .green).frame(width: 16)
            Text(name).font(.system(size: 12, design: .monospaced))
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(transport).font(.caption2).foregroundStyle(.secondary)
                if let exp = exposes { Text(exp).font(.caption2).foregroundStyle(.orange) }
            }
        }
    }
}

// MARK: - Tool Row

struct ToolRow: View {
    let name: String
    let version: String?
    let installNote: String
    let docsURL: String
    let onRecheck:   () async -> Void
    let onReinstall: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: version != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(version != nil ? .green : .red)
                Text(name).font(.system(size: 12, design: .monospaced))
                if let v = version { Text(v).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Re-check") { Task { await onRecheck() } }
                    .font(.caption).buttonStyle(.borderless).foregroundStyle(.blue)
                Button(version != nil ? "Update" : "Install") { Task { await onReinstall() } }
                    .font(.caption).buttonStyle(.bordered)
                    .foregroundStyle(version != nil ? .orange : .green)
            }
            if version == nil {
                HStack {
                    Text(installNote).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    if let url = URL(string: docsURL) {
                        Link("Docs ↗", destination: url).font(.caption2).foregroundStyle(.blue)
                    }
                }.padding(.leading, 20)
            }
        }
    }
}

// MARK: - Shared helpers

extension URLSession {
    static var ephemeral: URLSession { URLSession(configuration: .ephemeral) }
}

extension Notification.Name {
    static let runSetupWizard = Notification.Name("runSetupWizard")
}

// MARK: - Reusable subviews

struct LaunchStateBadge: View {
    let state: LaunchManager.State
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption.bold()).foregroundStyle(color)
        }
    }
    private var color: Color {
        switch state {
        case .online: return .green; case .starting: return .yellow
        case .offline, .noScript: return .red; case .idle: return .secondary
        }
    }
    private var label: String {
        switch state {
        case .idle: return "idle"; case .starting: return "starting"
        case .online: return "online"; case .offline: return "offline"
        case .noScript: return "no script"
        }
    }
}

struct ServerRow: View {
    let name: String; let online: Bool; var detail: String? = nil
    var body: some View {
        HStack {
            Circle().fill(online ? Color.green : Color.red).frame(width: 8, height: 8)
            Text(name).font(.system(size: 12, design: .monospaced))
            Spacer()
            if let d = detail {
                Text(d).font(.caption).foregroundStyle(.orange)
            } else {
                Text(online ? "online" : "offline").font(.caption)
                    .foregroundStyle(online ? .green : .red)
            }
        }
    }
}

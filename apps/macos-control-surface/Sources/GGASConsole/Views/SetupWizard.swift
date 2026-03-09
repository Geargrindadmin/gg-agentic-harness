// SetupWizard.swift — First-run onboarding: installs Node.js, Claude Code, Kimi Code

import SwiftUI
import Foundation

// MARK: - Model

enum WizardStep: Int, CaseIterable {
    case welcome               = 0
    case projectFolder         = 1
    case nodejs                = 2
    case claude                = 3
    case kimi                  = 4
    case apiKeys               = 5
    case setup                 = 6   // runs AFTER Claude/Kimi installs to avoid MCP overwrites
    case installIntoProjects   = 7   // install agentic layer into other projects
    case done                  = 8

    var title: String {
        switch self {
        case .welcome:             return "Welcome to GG Agentic Harness"
        case .projectFolder:       return "Choose Your Project Folder"
        case .nodejs:              return "Install Node.js"
        case .claude:              return "Install Claude Code"
        case .kimi:                return "Install Kimi Code"
        case .apiKeys:             return "Enter API Keys"
        case .setup:               return "Wire Harness Project"
        case .installIntoProjects: return "Install into Other Projects"
        case .done:                return "You're all set!"
        }
    }

    var icon: String {
        switch self {
        case .welcome:             return "gearshape.2.fill"
        case .projectFolder:       return "folder.badge.gearshape"
        case .nodejs:              return "shippingbox.fill"
        case .claude:              return "cpu.fill"
        case .kimi:                return "bolt.fill"
        case .apiKeys:             return "key.fill"
        case .setup:               return "wrench.and.screwdriver.fill"
        case .installIntoProjects: return "tray.and.arrow.down.fill"
        case .done:                return "checkmark.seal.fill"
        }
    }
}

enum StepStatus { case pending, running, success, failed(String), skipped }

@MainActor
final class SetupWizardVM: ObservableObject {
    @Published var currentStep: WizardStep = .welcome
    @Published var nodeStatus:            StepStatus = .pending
    @Published var setupStatus:           StepStatus = .pending
    @Published var claudeStatus:          StepStatus = .pending
    @Published var kimiStatus:            StepStatus = .pending
    @Published var apiKeysStatus:         StepStatus = .pending
    @Published var installProjectsStatus: StepStatus = .pending
    @Published var output: [CLILine] = []
    @Published var isComplete = false
    @Published var runtimeDiscovery: A2AClient.RuntimeDiscoveryResponse? = nil

    /// Extra project folders to install the agentic layer into
    @Published var targetProjects: [String] = []
    /// Overwrite existing files on install (--force flag)
    @Published var installForce: Bool = false

    /// Optional custom npm prefix for Claude (empty = use npm default)
    @Published var claudeInstallDir: String = ""
    /// Optional custom install dir for Kimi (empty = ~/.kimi/bin default)
    @Published var kimiInstallDir: String = ""

    /// API keys entered in the wizard
    @Published var anthropicAPIKey: String = ""
    @Published var moonshotAPIKey:  String = ""
    @Published var openAIAPIKey:    String = ""
    @Published var geminiAPIKey:    String = ""

    struct CLILine: Identifiable {
        let id = UUID(); let text: String; let isError: Bool
    }

    func refreshRuntimeDiscovery() async {
        runtimeDiscovery = try? await A2AClient.shared.fetchRuntimeDiscovery()
    }

    func advance() async {
        switch currentStep {
        case .welcome:             currentStep = .projectFolder
        case .projectFolder:       currentStep = .nodejs; await installNode()
        case .nodejs:              currentStep = .claude; await installClaude()
        case .claude:              currentStep = .kimi;   await installKimi()
        case .kimi:                currentStep = .apiKeys
        case .apiKeys:             await saveAPIKeys(); currentStep = .setup; await runSetupScript()
        case .setup:               currentStep = .installIntoProjects
        case .installIntoProjects: await runInstallIntoProjects(); currentStep = .done; isComplete = true
        case .done:                break
        }
    }

    func skipStep() {
        switch currentStep {
        case .nodejs:              nodeStatus            = .skipped; currentStep = .claude
        case .claude:              claudeStatus          = .skipped; currentStep = .kimi
        case .kimi:                kimiStatus            = .skipped; currentStep = .apiKeys
        case .apiKeys:             apiKeysStatus         = .skipped; currentStep = .setup; Task { await self.runSetupScript() }
        case .setup:               setupStatus           = .skipped; currentStep = .installIntoProjects
        case .installIntoProjects: installProjectsStatus = .skipped; currentStep = .done; isComplete = true
        default: break
        }
    }

    // MARK: - Installation Steps

    // MARK: Wire Harness project (setup.sh)

    /// Runs kit/setup.sh --non-interactive in the project root.
    /// setup.sh handles:
    ///  - npm install + npm run build for all 3 MCP servers
    ///  - Generate .mcp.json + .mcp.kimi.json from templates
    ///  - Install CLAUDE.md, KIMI.md, AGENTS.md, CODEX.md, GEMINI.md
    ///  - Init .beads/ database
    ///  - Write .agent-mode file
    private func runSetupScript() async {
        setupStatus = .running
        let projectRoot = ProjectSettings.shared.projectRoot
        guard !projectRoot.isEmpty, FileManager.default.fileExists(atPath: projectRoot) else {
            setupStatus = .failed("Project root not configured")
            log("✗ Project root not set — go back and choose your project folder", error: true)
            return
        }

        let setupScript = projectRoot + "/kit/setup.sh"
        guard FileManager.default.fileExists(atPath: setupScript) else {
            setupStatus = .failed("kit/setup.sh not found")
            log("✗ kit/setup.sh not found in \(projectRoot) — is this the right folder?", error: true)
            return
        }

        log("→ Running setup.sh --non-interactive in \(projectRoot)…")
        log("  This builds MCP servers, wires configs, and installs the agent constitution.")

        let script = """
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        export PATH="$HOME/.local/bin:$HOME/.kimi/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
        cd "\(projectRoot)"
        bash kit/setup.sh --non-interactive 2>&1
        """

        let (ok, _) = await runShellScript(script)
        setupStatus = ok ? .success : .failed("setup.sh exited non-zero")
        if ok {
            log("✓ Harness project wired — MCP servers built, configs generated, constitution installed")
        } else {
            log("⚠ setup.sh had errors — check logs above. You can skip and fix manually via Terminal.", error: true)
            log("  Tip: cd \(projectRoot) && bash kit/setup.sh --non-interactive", error: true)
        }
    }

    private func installNode() async {
        if commandExists("node") {
            let v    = shellOutput("node", "--version") ?? "installed"
            let npmV = shellOutput("npm",  "--version")
            nodeStatus = .success
            log("✓ Node.js already installed: \(v)")
            if let npmV {
                log("✓ npm already installed: v\(npmV)")
            } else {
                // Rare: node present but npm missing — repair via nvm
                log("⚠ npm not found — repairing via nvm…")
                let repair = """
                source ~/.nvm/nvm.sh 2>/dev/null || true
                export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
                nvm install --lts && nvm use --lts
                """
                let (ok, _) = await runShellScript(repair)
                let newV = shellOutput("npm", "--version")
                log(ok && newV != nil ? "✓ npm repaired: v\(newV!)" : "✗ npm repair failed — install Node.js manually")
            }
            currentStep = .claude
            await installClaude()
            return
        }

        nodeStatus = .running
        log("→ Installing Node.js + npm via nvm…")
        log("  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash")

        let script = """
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        source ~/.nvm/nvm.sh 2>/dev/null || true
        [ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"
        nvm install --lts
        nvm use --lts
        node --version && npm --version
        """
        let (ok, msg) = await runShellScript(script)
        nodeStatus = ok ? .success : .failed(msg)
        if ok {
            let npmV = shellOutput("npm", "--version") ?? "installed"
            log("✓ Node.js installed — npm v\(npmV) ready")
        }
    }

    private func installClaude() async {
        if commandExists("claude") {
            let v = shellOutput("claude", "--version") ?? "installed"
            claudeStatus = .success
            log("✓ Claude Code already installed: \(v)")
            log("→ Re-wiring harness MCP servers (verifying Claude knows about them)…")
            await rewireMCPServers()
            return
        }

        claudeStatus = .running
        log("→ Installing Claude Code CLI…")

        // Build the npm install command — optionally set a custom prefix dir
        let prefixLine: String
        if claudeInstallDir.isEmpty {
            prefixLine = "npm install -g @anthropic-ai/claude-code"
            log("  npm install -g @anthropic-ai/claude-code (default location)")
        } else {
            prefixLine = "npm install -g @anthropic-ai/claude-code --prefix \"\(claudeInstallDir)\""
            log("  npm install -g @anthropic-ai/claude-code --prefix \"\(claudeInstallDir)\"")
        }

        let script = """
        source ~/.nvm/nvm.sh 2>/dev/null || true
        export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        \(prefixLine)
        """
        let (ok, msg) = await runShellScript(script)
        claudeStatus = ok ? .success : .failed(msg)
        if ok {
            if !claudeInstallDir.isEmpty {
                log("✓ Claude Code installed to \(claudeInstallDir)/bin")
                log("  Add \"\(claudeInstallDir)/bin\" to your PATH to use 'claude' globally")
            } else {
                log("✓ Claude Code installed — run 'claude' to log in with your Anthropic account")
            }
            log("→ Wiring harness MCP servers into Claude…")
            await rewireMCPServers()
        }
    }

    /// Re-registers all harness MCP servers with Claude CLI.
    /// Safe to run repeatedly — removes existing registration first to avoid duplicates.
    private func rewireMCPServers() async {
        await buildMCPServers()  // Gap 4 — ensure dist/ exists before registering
        // Use ProjectSettings — portable to any user's machine (no folder name hardcoded)
        let projectRoot = ProjectSettings.shared.projectRoot
        let controlPlaneURL = ProjectSettings.shared.normalizedControlPlaneBaseURL
        guard !projectRoot.isEmpty, FileManager.default.fileExists(atPath: projectRoot) else {
            log("⚠ Project root not configured — open Config tab and choose your project folder")
            return
        }
        let ggForge = NSHomeDirectory() + "/.ggas/forge/bin/GGForgeMCP"
        let ggSkills    = projectRoot + "/mcp-servers/gg-skills/dist/index.js"
        let ggBridge    = projectRoot + "/mcp-servers/gg-agent-bridge/dist/index.js"
        let agentSkills = projectRoot + "/.agent/skills"
        let agentFlows  = projectRoot + "/.agent/workflows"

        log("→ Project root: \(projectRoot)")

        // Build the claude mcp add commands
        // -s user = user scope (available in all projects)
        let rewireScript = """
        # Remove old registrations first (ignore errors if not registered)
        claude mcp remove gg-skills     -s user 2>/dev/null || true
        claude mcp remove gg-agent-bridge -s user 2>/dev/null || true
        claude mcp remove gg-forge        -s user 2>/dev/null || true
        claude mcp remove context7        -s user 2>/dev/null || true
        claude mcp remove chrome-devtools -s user 2>/dev/null || true
        claude mcp remove obsidian        -s user 2>/dev/null || true

        # Re-register harness MCP services
        claude mcp add gg-skills -s user \\
          -e SKILLS_DIR="\(agentSkills)" \\
          -e WORKFLOWS_DIR="\(agentFlows)" \\
          -- node "\(ggSkills)" 2>&1

        # Optional bridge: only register if the repo actually carries it.
        if [ -f "\(ggBridge)" ]; then
          claude mcp add gg-agent-bridge -s user \\
            -e A2A_HTTP_URL="\(controlPlaneURL)" \\
            -e KIMI_BINARY="$HOME/.local/bin/kimi" \\
            -e PROJECT_ROOT="\(projectRoot)" \\
            -- node "\(ggBridge)" 2>&1
        else
          echo "ℹ gg-agent-bridge is not present in this repo — skipping bridge registration"
        fi

        # Re-register GG Forge (local memory/tasks MCP) if binary exists
        if [ -f "\(ggForge)" ]; then
          claude mcp add gg-forge -s user -- "\(ggForge)" 2>&1
          echo "✓ gg-forge MCP registered"
        else
          echo "⚠ gg-forge binary not found — run Reinstall Doctor to build it (Step 10 of setup.sh)"
        fi

        # Re-register utility MCP servers
        claude mcp add context7        -s user -- npx -y @upstash/context7-mcp 2>&1
        claude mcp add chrome-devtools -s user -- npx -y chrome-devtools-mcp@latest 2>&1
        claude mcp add obsidian        -s user -- npx @mauricio.wolff/mcp-obsidian@latest "\(projectRoot)" 2>&1

        echo "MCP_REWIRE_DONE"
        """

        let (ok, _) = await runShellScript(rewireScript)
        if ok {
            log("✓ Harness MCP services re-wired into Claude — restart Claude to activate")
        } else {
            log("⚠ MCP re-wire had errors — check Terminal tab. Some servers may need manual 'claude mcp add'.")
        }

        // Gap 2 + 3 + 5 — wire Kimi + Antigravity configs + register the control-plane LaunchAgent
        await wireKimiMCP()
        await wireAntigravityMCP()
        await registerA2AServer()
    }

    private func installKimi() async {
        if commandExists("kimi") {
            let v = shellOutput("kimi", "--version") ?? "installed"
            kimiStatus = .success
            log("✓ Kimi Code already installed: \(v)")
            return
        }

        kimiStatus = .running
        log("→ Installing Kimi Code 3.5 CLI…")

        // Kimi install script honours KIMI_INSTALL_DIR env var
        let installDirLine: String
        let pathAddition: String
        if kimiInstallDir.isEmpty {
            installDirLine = ""  // unset = default (~/.kimi/bin)
            pathAddition = "$HOME/.kimi/bin:$HOME/.local/bin"
            log("  curl -fsSL code.kimi.com/install.sh | bash (default: ~/.kimi/bin)")
        } else {
            installDirLine = "export KIMI_INSTALL_DIR=\"\(kimiInstallDir)\""
            pathAddition = "\(kimiInstallDir):$HOME/.local/bin"
            log("  curl -fsSL code.kimi.com/install.sh | bash → \(kimiInstallDir)")
        }

        let script = """
        \(installDirLine)
        curl -fsSL code.kimi.com/install.sh | bash
        export PATH="\(pathAddition):$PATH"
        """
        let (ok, msg) = await runShellScript(script)
        kimiStatus = ok ? .success : .failed(msg)
        if ok {
            let dest = kimiInstallDir.isEmpty ? "~/.kimi/bin" : kimiInstallDir
            log("✓ Kimi Code installed to \(dest) — run 'kimi login' to authenticate")
            if !kimiInstallDir.isEmpty {
                log("  Add \"\(kimiInstallDir)\" to your PATH to use 'kimi' globally")
            }
            // Gap 2 — wire harness MCP servers into Kimi after fresh install
            log("→ Wiring harness MCP servers into Kimi…")
            await wireKimiMCP()
        }
    }

    // MARK: - API Keys

    /// Saves entered API keys to ~/.ggas/env as shell exports, then re-wires
    /// gg-agent-bridge so ANTHROPIC_API_KEY + MOONSHOT_API_KEY are available
    /// to the ClaudePool and KimiPool workers at runtime.
    func saveAPIKeys() async {
        apiKeysStatus = .running
        let envDir  = NSHomeDirectory() + "/.ggas"
        let envFile = envDir + "/env"

        // Build env file contents — preserve existing lines, overwrite our keys
        var lines: [String] = []
        if let existing = try? String(contentsOfFile: envFile, encoding: .utf8) {
            lines = existing.split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter {
                    !$0.hasPrefix("export ANTHROPIC_API_KEY=")
                    && !$0.hasPrefix("export MOONSHOT_API_KEY=")
                    && !$0.hasPrefix("export OPENAI_API_KEY=")
                    && !$0.hasPrefix("export GEMINI_API_KEY=")
                }
        }

        if !anthropicAPIKey.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("export ANTHROPIC_API_KEY=\"\(anthropicAPIKey.trimmingCharacters(in: .whitespaces))\"")
            log("✓ ANTHROPIC_API_KEY saved to ~/.ggas/env")
        }
        if !moonshotAPIKey.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("export MOONSHOT_API_KEY=\"\(moonshotAPIKey.trimmingCharacters(in: .whitespaces))\"")
            log("✓ MOONSHOT_API_KEY saved to ~/.ggas/env")
        }
        if !openAIAPIKey.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("export OPENAI_API_KEY=\"\(openAIAPIKey.trimmingCharacters(in: .whitespaces))\"")
            log("✓ OPENAI_API_KEY saved to ~/.ggas/env")
        }
        if !geminiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("export GEMINI_API_KEY=\"\(geminiAPIKey.trimmingCharacters(in: .whitespaces))\"")
            log("✓ GEMINI_API_KEY saved to ~/.ggas/env")
        }

        try? FileManager.default.createDirectory(atPath: envDir, withIntermediateDirectories: true)
        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(toFile: envFile, atomically: true, encoding: .utf8)

        // Persist to UserDefaults so ConfigView can read them back (keys marked, values stored)
        APIKeyStore.shared.save(
            anthropic: anthropicAPIKey.trimmingCharacters(in: .whitespaces),
            moonshot:  moonshotAPIKey.trimmingCharacters(in: .whitespaces),
            openAI:    openAIAPIKey.trimmingCharacters(in: .whitespaces),
            gemini:    geminiAPIKey.trimmingCharacters(in: .whitespaces)
        )

        // Re-wire gg-agent-bridge with API keys injected as env vars
        let projectRoot = ProjectSettings.shared.projectRoot
        let ggBridge    = projectRoot + "/mcp-servers/gg-agent-bridge/dist/index.js"
        let controlPlaneURL = ProjectSettings.shared.normalizedControlPlaneBaseURL
        if !projectRoot.isEmpty && !anthropicAPIKey.isEmpty && FileManager.default.fileExists(atPath: ggBridge) {
            let rewireScript = """
            claude mcp remove gg-agent-bridge -s user 2>/dev/null || true
            claude mcp add gg-agent-bridge -s user \\
              -e A2A_HTTP_URL="\(controlPlaneURL)" \\
              -e KIMI_BINARY="$HOME/.local/bin/kimi" \\
              -e PROJECT_ROOT="\(projectRoot)" \\
              -e ANTHROPIC_API_KEY="\(anthropicAPIKey.trimmingCharacters(in: .whitespaces))" \\
              -e MOONSHOT_API_KEY="\(moonshotAPIKey.trimmingCharacters(in: .whitespaces))" \\
              -- node "\(ggBridge)" 2>&1
            echo "KEY_REWIRE_DONE"
            """
            let (ok, _) = await runShellScript(rewireScript)
            log(ok ? "✓ gg-agent-bridge re-wired with API keys" : "⚠ gg-agent-bridge rewire had errors — keys saved to ~/.ggas/env")
        }

        apiKeysStatus = .success
    }

    // MARK: - Gap 4: Build MCP Servers

    /// Runs npm install + npm run build on all three MCP servers so dist/ exists
    /// before Claude/Kimi try to load them. Safe to re-run — npm skips unchanged modules.
    private func buildMCPServers() async {
        let projectRoot = ProjectSettings.shared.projectRoot
        guard !projectRoot.isEmpty else { return }

        let candidateServers: [(label: String, path: String)] = [
            ("gg-agent-bridge", projectRoot + "/mcp-servers/gg-agent-bridge"),
            ("gg-skills", projectRoot + "/mcp-servers/gg-skills"),
            ("gg-control-plane-server", projectRoot + "/packages/gg-control-plane-server")
        ]
        let servers = candidateServers.filter { FileManager.default.fileExists(atPath: $0.path) }

        for server in servers where FileManager.default.fileExists(atPath: server.path) {
            log("→ Building \(server.label)…")
            let script = """
            cd "\(server.path)"
            npm install --silent 2>&1 | tail -1
            # Remove corrupted typescript if present
            if node node_modules/.bin/tsc --version 2>&1 | grep -q 'Cannot find'; then
              rm -rf node_modules/typescript && npm install --silent
            fi
            npm run build 2>&1 | tail -3
            """
            let (ok, _) = await runShellScript(script)
            log(ok ? "✓ \(server.label) built" : "⚠ \(server.label) build failed — check Terminal tab")
        }
    }

    // MARK: - Gap 2: Wire Kimi MCP

    /// Merges repo-scoped MCP services into ~/.kimi/mcp.json.
    /// Kimi reads this file at every invocation — no restart required.
    private func wireKimiMCP() async {
        let home = NSHomeDirectory()
        let projectRoot = ProjectSettings.shared.projectRoot
        guard !projectRoot.isEmpty else {
            log("⚠ Project root not configured — skipping Kimi MCP wiring")
            return
        }
        let kimiMCPPath = home + "/.kimi/mcp.json"
        let controlPlaneURL = ProjectSettings.shared.normalizedControlPlaneBaseURL

        // Build JSON string for the repo-scoped services
        let bridgePath  = projectRoot + "/mcp-servers/gg-agent-bridge/dist/index.js"
        let skillsPath  = projectRoot + "/mcp-servers/gg-skills/dist/index.js"
        let agentSkills = projectRoot + "/.agent/skills"
        let agentFlows  = projectRoot + "/.agent/workflows"

        let script = """
        KIMI_MCP="\(kimiMCPPath)"
        [ -f "$KIMI_MCP" ] || echo '{"mcpServers":{}}' > "$KIMI_MCP"
        python3 -c "
        import json, pathlib
        p = pathlib.Path('\(kimiMCPPath)')
        try:
            cfg = json.loads(p.read_text())
        except Exception:
            cfg = {}
        cfg.setdefault('mcpServers', {})
        if pathlib.Path('\(bridgePath)').exists():
            cfg['mcpServers']['gg-agent-bridge'] = {
                'command': 'node',
                'args': ['\(bridgePath)'],
                'env': {
                    'PROJECT_ROOT': '\(projectRoot)',
                    'KIMI_BINARY': '\(home)/.local/bin/kimi',
                    'A2A_HTTP_URL': '\(controlPlaneURL)'
                }
            }
        else:
            cfg['mcpServers'].pop('gg-agent-bridge', None)
        cfg['mcpServers']['gg-skills'] = {
            'command': 'node',
            'args': ['\(skillsPath)'],
            'env': {
                'SKILLS_DIR': '\(agentSkills)',
                'WORKFLOWS_DIR': '\(agentFlows)'
            }
        }
        cfg['mcpServers']['filesystem'] = {
            'command': 'npx',
            'args': ['-y', '@modelcontextprotocol/server-filesystem',
                     '\(projectRoot)', '/tmp']
        }
        p.write_text(json.dumps(cfg, indent=2))
        print('OK: kimi mcp.json updated, servers:', list(cfg['mcpServers'].keys()))
        "
        """
        let (ok, _) = await runShellScript(script)
        log(ok ? "✓ Kimi MCP config updated (~/.kimi/mcp.json)" : "⚠ Kimi MCP wiring failed — check Terminal tab")
    }

    // MARK: - Gap 3: Wire Antigravity MCP

    /// Merges repo-scoped harness services into ~/.gemini/antigravity/mcp_config.json
    /// so the Antigravity VS Code extension has the bridge tools on next session start.
    private func wireAntigravityMCP() async {
        let home = NSHomeDirectory()
        let projectRoot = ProjectSettings.shared.projectRoot
        guard !projectRoot.isEmpty else {
            log("⚠ Project root not configured — skipping Antigravity MCP wiring")
            return
        }
        let configPath  = home + "/.gemini/antigravity/mcp_config.json"
        let bridgePath  = projectRoot + "/mcp-servers/gg-agent-bridge/dist/index.js"
        let skillsPath  = projectRoot + "/mcp-servers/gg-skills/dist/index.js"
        let agentSkills = projectRoot + "/.agent/skills"
        let agentFlows  = projectRoot + "/.agent/workflows"
        let controlPlaneURL = ProjectSettings.shared.normalizedControlPlaneBaseURL

        let script = """
        [ -f "\(configPath)" ] || echo '{"mcpServers":{}}' > "\(configPath)"
        python3 -c "
        import json, pathlib
        p = pathlib.Path('\(configPath)')
        try:
            cfg = json.loads(p.read_text())
        except Exception:
            cfg = {}
        cfg.setdefault('mcpServers', {})
        if pathlib.Path('\(bridgePath)').exists():
            cfg['mcpServers']['gg-agent-bridge'] = {
                'command': 'node',
                'args': ['\(bridgePath)'],
                'env': {
                    'PROJECT_ROOT': '\(projectRoot)',
                    'KIMI_BINARY': '\(home)/.local/bin/kimi',
                    'A2A_HTTP_URL': '\(controlPlaneURL)'
                },
                'alwaysAllow': [
                    'spawn_kimi_agent','send_kimi_message','get_kimi_output',
                    'kill_kimi_session','spawn_kimi_swarm','retry_kimi_agent',
                    'dispatch_to_a2a','append_run_log'
                ]
            }
        else:
            cfg['mcpServers'].pop('gg-agent-bridge', None)
        cfg['mcpServers']['gg-skills'] = {
            'command': 'node',
            'args': ['\(skillsPath)'],
            'env': {
                'SKILLS_DIR': '\(agentSkills)',
                'WORKFLOWS_DIR': '\(agentFlows)'
            },
            'alwaysAllow': ['use_skill','find_skills','list_skills','list_workflows','use_workflow']
        }
        p.write_text(json.dumps(cfg, indent=2))
        print('OK: antigravity config updated, servers:', len(cfg['mcpServers']))
        "
        """
        let (ok, _) = await runShellScript(script)
        log(ok ? "✓ Antigravity MCP config updated (~/.gemini/antigravity/mcp_config.json)" : "⚠ Antigravity MCP wiring failed")
    }

    // MARK: - Gap 5: Register Control-Plane Server as LaunchAgent

    /// Installs a macOS LaunchAgent so the harness control-plane starts automatically
    /// at login and stays running in the background on the configured port.
    private func registerA2AServer() async {
        let home        = NSHomeDirectory()
        let projectRoot = ProjectSettings.shared.projectRoot
        guard !projectRoot.isEmpty else {
            log("⚠ Project root not configured — skipping LaunchAgent registration")
            return
        }
        let serverPath  = projectRoot + "/packages/gg-control-plane-server"
        let serverDist  = serverPath + "/dist/index.js"
        let launchAgent = home + "/Library/LaunchAgents/com.geargrind.control-plane.plist"
        let logOut      = home + "/Library/Logs/gg-control-plane.log"
        let logErr      = home + "/Library/Logs/gg-control-plane.err.log"
        let nodeExe     = "/usr/local/bin/node"  // fallback; script resolves via which
        let controlPlanePort = String(ProjectSettings.shared.controlPlanePort)
        let controlPlaneURL = ProjectSettings.shared.normalizedControlPlaneBaseURL

        let script = """
        NODE_BIN=$(which node 2>/dev/null || echo "\(nodeExe)")
        SERVER_DIST="\(serverDist)"

        # Only install if the server binary exists
        if [ ! -f "$SERVER_DIST" ]; then
          echo "⚠ Harness control-plane not built yet — run Setup again after build completes"
          exit 0
        fi

        cat > "\(launchAgent)" <<PLIST
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>             <string>com.geargrind.control-plane</string>
          <key>ProgramArguments</key>
          <array>
            <string>$NODE_BIN</string>
            <string>$SERVER_DIST</string>
          </array>
          <key>EnvironmentVariables</key>
          <dict>
            <key>HARNESS_CONTROL_PLANE_PORT</key> <string>\(controlPlanePort)</string>
            <key>PROJECT_ROOT</key>               <string>\(projectRoot)</string>
            <key>PATH</key>          <string>/usr/local/bin:/opt/homebrew/bin:$HOME/.local/bin:/usr/bin:/bin</string>
          </dict>
          <key>RunAtLoad</key>          <true/>
          <key>KeepAlive</key>          <true/>
          <key>StandardOutPath</key>    <string>\(logOut)</string>
          <key>StandardErrorPath</key>  <string>\(logErr)</string>
          <key>WorkingDirectory</key>   <string>\(serverPath)</string>
        </dict>
        </plist>
        PLIST

        # Load (or reload) the agent
        launchctl unload "\(launchAgent)" 2>/dev/null || true
        launchctl load -w "\(launchAgent)"
        sleep 1
        curl -sf "\(controlPlaneURL)/health" && echo "✓ Harness control-plane running" || echo "⚠ Harness control-plane started but /health is not responding yet"
        """
        let (ok, _) = await runShellScript(script)
        log(ok ? "✓ Harness control-plane LaunchAgent installed — starts automatically at login" : "⚠ Harness control-plane LaunchAgent install failed")
    }

    // MARK: - Install into Other Projects

    /// Runs kit/install-to-project.sh for each entry in targetProjects.
    /// If targetProjects is empty, logs a note and marks success (nothing to do).
    private func runInstallIntoProjects() async {
        guard !targetProjects.isEmpty else {
            installProjectsStatus = .success
            log("ℹ No additional projects selected — skipping install-into-projects step")
            return
        }

        installProjectsStatus = .running
        let projectRoot  = ProjectSettings.shared.projectRoot
        let installScript = projectRoot + "/kit/install-to-project.sh"

        guard FileManager.default.fileExists(atPath: installScript) else {
            installProjectsStatus = .failed("kit/install-to-project.sh not found")
            log("✗ kit/install-to-project.sh not found — is the project root set correctly?", error: true)
            return
        }

        let forceFlag = installForce ? " --force" : ""
        var anyError = false

        for target in targetProjects {
            log("→ Installing agentic layer into: \(target)\(installForce ? " (--force)" : "")…")
            let script = """
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            export PATH="$HOME/.local/bin:$HOME/.kimi/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
            bash "\(installScript)" "\(target)"\(forceFlag) 2>&1
            """
            let (ok, _) = await runShellScript(script)
            if ok {
                log("✓ Installed into \(target)")
            } else {
                log("⚠ Install into \(target) had errors — check logs above", error: true)
                anyError = true
            }
        }

        installProjectsStatus = anyError ? .failed("One or more installs had errors") : .success
        if !anyError {
            log("✓ Agentic layer installed into \(targetProjects.count) project(s) — restart IDE to load new MCP servers")
        }
    }

    /// Opens NSOpenPanel and appends the chosen directory to targetProjects.
    func addTargetProject() {
        let panel = NSOpenPanel()
        panel.title            = "Choose Target Project Folder"
        panel.message          = "Select the root of a project you want to install the GearGrind agentic layer into."
        panel.canChooseFiles   = false
        panel.canChooseDirectories  = true
        panel.canCreateDirectories  = false
        panel.allowsMultipleSelection = true
        panel.directoryURL     = URL(fileURLWithPath: NSHomeDirectory() + "/Documents")
        if panel.runModal() == .OK {
            for url in panel.urls {
                let path = url.path
                if !targetProjects.contains(path) {
                    targetProjects.append(path)
                }
            }
        }
    }

    /// Opens NSOpenPanel for the user to pick a custom CLI install directory.
    func chooseInstallDir(for tool: String) {
        let panel = NSOpenPanel()
        panel.title = "Choose Install Directory for \(tool)"
        panel.message = "Select the directory where \(tool) binaries should be installed (e.g. /usr/local/bin, ~/bin, or a custom folder)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        if panel.runModal() == .OK, let url = panel.url {
            if tool == "Claude" { claudeInstallDir = url.path }
            else if tool == "Kimi"  { kimiInstallDir  = url.path }
        }
    }

    // MARK: - Helpers

    private func commandExists(_ cmd: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [cmd]
        proc.standardOutput = Pipe(); proc.standardError = Pipe()
        try? proc.run(); proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    private func shellOutput(_ cmd: String, _ flag: String) -> String? {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [cmd, flag]
        proc.standardOutput = pipe; proc.standardError = Pipe()
        try? proc.run(); proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").first
    }

    private func runShellScript(_ script: String) async -> (Bool, String) {
        await Task.detached(priority: .userInitiated) { [weak self] in
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ggas_setup_\(UUID().uuidString).sh")
            let fullScript = "#!/bin/bash\nset -euo pipefail\n" + script
            try? fullScript.write(to: tmp, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)

            let outPipe = Pipe(); let errPipe = Pipe()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [tmp.path]
            proc.standardOutput = outPipe
            proc.standardError  = errPipe

            // Stream output in real time
            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; guard !d.isEmpty else { return }
                if let txt = String(data: d, encoding: .utf8) {
                    let lines = txt.components(separatedBy: "\n").filter { !$0.isEmpty }
                    Task { @MainActor [weak self] in
                        lines.forEach { self?.log($0, error: false) }
                    }
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; guard !d.isEmpty else { return }
                if let txt = String(data: d, encoding: .utf8) {
                    let lines = txt.components(separatedBy: "\n").filter { !$0.isEmpty }
                    Task { @MainActor [weak self] in
                        lines.forEach { self?.log($0, error: true) }
                    }
                }
            }

            try? proc.run(); proc.waitUntilExit()
            try? FileManager.default.removeItem(at: tmp)
            let errOut = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            return (proc.terminationStatus == 0, errOut)
        }.value
    }

    private func log(_ text: String, error: Bool = false) {
        if output.count >= 500 { output.removeFirst(50) }
        output.append(CLILine(text: text, isError: error))
    }
}

// MARK: - Wizard View

struct SetupWizardView: View {
    @StateObject private var vm = SetupWizardVM()
    @Binding var showWizard: Bool

    // Show/hide toggles for API key fields (SecureField blocks ⌘V on macOS)
    @State private var showAnthropicKey = false
    @State private var showMoonshotKey  = false
    @State private var showOpenAIKey    = false
    @State private var showGeminiKey    = false

    var body: some View {
        VStack(spacing: 0) {

            // Header
            VStack(spacing: 8) {
                Image(systemName: vm.currentStep.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                    .symbolEffect(.bounce, value: vm.currentStep)
                Text(vm.currentStep.title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)

            // Step progress indicators
            HStack(spacing: 8) {
                ForEach(WizardStep.allCases, id: \.rawValue) { step in
                    stepDot(step)
                }
            }
            .padding(.bottom, 16)

            Divider()

            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if vm.output.isEmpty && vm.currentStep == .welcome {
                            Text("Installation logs will appear here…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary).padding(8)
                        }
                        ForEach(vm.output) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.isError ? Color.red : Color.green)
                                .textSelection(.enabled)
                                .id(line.id).padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.vertical, 4)
                }
                .background(Color.black.opacity(0.9))
                .onChange(of: vm.output.count) { _, _ in
                    if let last = vm.output.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .frame(minHeight: 180, maxHeight: 280)

            // Project folder picker card (only visible on that step)
            if vm.currentStep == .projectFolder {
                let ps = ProjectSettings.shared
                VStack(alignment: .leading, spacing: 10) {
                    if ps.isConfigured {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Project folder detected").font(.caption.bold())
                                Text(ps.projectRoot)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Change…") { ps.chooseFolder() }.buttonStyle(.bordered).font(.caption)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.questionmark").foregroundStyle(.orange)
                            Text("No project folder found — choose the folder that contains .agent/, AGENTS/, CLAUDE.md…")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Choose Folder") { ps.chooseFolder() }.buttonStyle(.borderedProminent).font(.caption)
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16).padding(.top, 8)
            }

            if vm.currentStep == .welcome || vm.currentStep == .apiKeys {
                runtimeAuditCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // Install directory picker — shown on Claude and Kimi steps
            if vm.currentStep == .claude || vm.currentStep == .kimi {
                let tool       = vm.currentStep == .claude ? "Claude" : "Kimi"
                let dirValue   = vm.currentStep == .claude ? vm.claudeInstallDir : vm.kimiInstallDir
                let defaultLbl = vm.currentStep == .claude ? "npm global default" : "~/.kimi/bin (default)"

                VStack(alignment: .leading, spacing: 6) {
                    Label("Advanced: Custom Install Directory", systemImage: "folder.badge.gearshape")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if dirValue.isEmpty {
                            Image(systemName: "folder").foregroundStyle(.secondary).font(.caption)
                            Text(defaultLbl)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue).font(.caption)
                            Text(dirValue)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(1).truncationMode(.middle)
                            Button("Clear") {
                                if vm.currentStep == .claude { vm.claudeInstallDir = "" }
                                else { vm.kimiInstallDir = "" }
                            }
                            .buttonStyle(.borderless).font(.caption).foregroundStyle(.red)
                        }
                        Spacer()
                        Button("Choose\u{2026}") { vm.chooseInstallDir(for: tool) }
                            .buttonStyle(.bordered).font(.caption)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16).padding(.top, 8)
            }

            // API Keys input card — shown on apiKeys step
            if vm.currentStep == .apiKeys {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Enter API keys to enable autonomous agent workers", systemImage: "key.fill")
                        .font(.caption.bold()).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anthropic API Key (Claude)").font(.caption.bold())
                        HStack(spacing: 6) {
                            Group {
                                if showAnthropicKey {
                                    TextField("sk-ant-…", text: $vm.anthropicAPIKey)
                                } else {
                                    SecureField("sk-ant-…", text: $vm.anthropicAPIKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            Button {
                                showAnthropicKey.toggle()
                            } label: {
                                Image(systemName: showAnthropicKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(showAnthropicKey ? "Hide key" : "Show key")
                            if let url = URL(string: "https://console.anthropic.com/settings/keys") {
                                Link("Get ↗", destination: url).font(.caption2).foregroundStyle(.blue)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Moonshot API Key (Kimi)").font(.caption.bold())
                        HStack(spacing: 6) {
                            Group {
                                if showMoonshotKey {
                                    TextField("sk-…", text: $vm.moonshotAPIKey)
                                } else {
                                    SecureField("sk-…", text: $vm.moonshotAPIKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            Button {
                                showMoonshotKey.toggle()
                            } label: {
                                Image(systemName: showMoonshotKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(showMoonshotKey ? "Hide key" : "Show key")
                            if let url = URL(string: "https://platform.moonshot.cn/console/api-keys") {
                                Link("Get ↗", destination: url).font(.caption2).foregroundStyle(.blue)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("OpenAI API Key (Codex)").font(.caption.bold())
                        HStack(spacing: 6) {
                            Group {
                                if showOpenAIKey {
                                    TextField("sk-proj-…", text: $vm.openAIAPIKey)
                                } else {
                                    SecureField("sk-proj-…", text: $vm.openAIAPIKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            Button {
                                showOpenAIKey.toggle()
                            } label: {
                                Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            if let url = URL(string: "https://platform.openai.com/api-keys") {
                                Link("Get ↗", destination: url).font(.caption2).foregroundStyle(.blue)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gemini API Key").font(.caption.bold())
                        HStack(spacing: 6) {
                            Group {
                                if showGeminiKey {
                                    TextField("AIza…", text: $vm.geminiAPIKey)
                                } else {
                                    SecureField("AIza…", text: $vm.geminiAPIKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            Button {
                                showGeminiKey.toggle()
                            } label: {
                                Image(systemName: showGeminiKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            if let url = URL(string: "https://aistudio.google.com/apikey") {
                                Link("Get ↗", destination: url).font(.caption2).foregroundStyle(.blue)
                            }
                        }
                    }

                    Text("Keys are saved to ~/.ggas/env. Local OAuth CLI sessions still take precedence when available, and you can update all credentials later in Config → Credentials.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16).padding(.top, 8)
            }

            // Install into Projects card — shown on installIntoProjects step
            if vm.currentStep == .installIntoProjects {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Target Projects", systemImage: "tray.and.arrow.down.fill")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Overwrite existing files (--force)", isOn: $vm.installForce)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                    }

                    if vm.targetProjects.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary).font(.caption)
                            Text("No projects added yet. Click + to select project folders.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        VStack(spacing: 4) {
                            ForEach(vm.targetProjects, id: \.self) { path in
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.blue).font(.caption)
                                    Text(path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        vm.targetProjects.removeAll { $0 == path }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }

                    HStack {
                        Button {
                            vm.addTargetProject()
                        } label: {
                            Label("Add Project Folder", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        if !vm.targetProjects.isEmpty {
                            Text("\(vm.targetProjects.count) project(s) queued")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    Text("Skills, workflows, rules, GEMINI.md, and .mcp.json will be installed. Existing files are skipped unless --force is enabled.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16).padding(.top, 8)
            }

            Divider()

            // Footer buttons
            HStack {
                // Hide Skip on .projectFolder — folder selection is required
                if vm.currentStep != .welcome && vm.currentStep != .done && vm.currentStep != .projectFolder {
                    Button("Skip This Step") { vm.skipStep() }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                Spacer()
                if vm.currentStep == .done {
                    Button("Launch GearGrind") {
                        // Mark setup as done
                        UserDefaults.standard.set(true, forKey: "setupComplete")
                        showWizard = false
                    }.buttonStyle(.borderedProminent)
                } else if isStepRunning {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button(actionLabel) { Task { await vm.advance() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.currentStep == .projectFolder && !ProjectSettings.shared.isConfigured)
                }
            }
            .padding(16)
        }
        .frame(width: 560, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .task { await vm.refreshRuntimeDiscovery() }
    }

    private var subtitle: String {
        switch vm.currentStep {
        case .welcome:             return "This wizard will install Node.js, Claude Code, and Kimi Code.\nThis is a one-time setup — your data is never touched during updates."
        case .projectFolder:       return "This tells the app where your agentic project lives so it can install skills, workflows, agent personas, and MCP servers in the right place."
        case .nodejs:              return "Node.js 20 LTS is required to run the harness control-plane and macOS control surface."
        case .claude:              return "Claude Code CLI is Anthropic's AI coding agent used to coordinate tasks."
        case .kimi:                return "Kimi Code 3.5 CLI is Moonshot AI's coding agent used for parallel swarms."
        case .apiKeys:             return "Local authenticated CLIs are preferred. Add API keys here only for direct-provider fallback or unattended runs where no OAuth session exists."
        case .setup:               return "Building MCP servers, generating config files, and installing the agent constitution (CLAUDE.md, KIMI.md, AGENTS.md) into your project. Runs after Claude/Kimi installs to avoid overwriting MCP registrations."
        case .installIntoProjects: return "Optionally install the GearGrind agentic layer (skills, workflows, rules, GEMINI.md, .mcp.json) into other projects on this machine so they benefit from the same agent tooling."
        case .done:                return "All dependencies installed. Click Launch to start using GearGrind Agentic System."
        }
    }

    private var actionLabel: String {
        switch vm.currentStep {
        case .welcome:             return "Begin Setup"
        case .projectFolder:       return ProjectSettings.shared.isConfigured ? "Confirm & Continue" : "Choose Folder to Continue"
        case .nodejs:              return "Install Node.js"
        case .claude:              return "Install Claude Code"
        case .kimi:                return "Install Kimi Code"
        case .apiKeys:
            return vm.anthropicAPIKey.isEmpty
                && vm.moonshotAPIKey.isEmpty
                && vm.openAIAPIKey.isEmpty
                && vm.geminiAPIKey.isEmpty
                ? "Skip & Wire Project"
                : "Save Keys & Wire Project"
        case .setup:               return "Wire Project"
        case .installIntoProjects: return vm.targetProjects.isEmpty ? "Skip — No Projects Selected" : "Install into \(vm.targetProjects.count) Project(s)"
        case .done:                return "Launch GearGrind"
        }
    }

    private var isStepRunning: Bool {
        switch vm.currentStep {
        case .nodejs:              if case .running = vm.nodeStatus            { return true }
        case .setup:               if case .running = vm.setupStatus           { return true }
        case .claude:              if case .running = vm.claudeStatus          { return true }
        case .kimi:                if case .running = vm.kimiStatus            { return true }
        case .apiKeys:             if case .running = vm.apiKeysStatus         { return true }
        case .installIntoProjects: if case .running = vm.installProjectsStatus { return true }
        default: break
        }
        return false
    }

    @ViewBuilder
    private func stepDot(_ step: WizardStep) -> some View {
        let status = stepStatus(step)
        Circle()
            .fill(dotColor(status, isCurrent: step == vm.currentStep))
            .frame(width: step == vm.currentStep ? 10 : 8, height: step == vm.currentStep ? 10 : 8)
            .overlay(
                step == vm.currentStep
                    ? Circle().stroke(Color.blue.opacity(0.4), lineWidth: 3)
                    : nil
            )
    }

    private func stepStatus(_ step: WizardStep) -> StepStatus {
        switch step {
        case .projectFolder:       return ProjectSettings.shared.isConfigured ? .success : .pending
        case .nodejs:              return vm.nodeStatus
        case .setup:               return vm.setupStatus
        case .claude:              return vm.claudeStatus
        case .kimi:                return vm.kimiStatus
        case .apiKeys:             return vm.apiKeysStatus
        case .installIntoProjects: return vm.installProjectsStatus
        default:                   return .pending
        }
    }

    private func dotColor(_ status: StepStatus, isCurrent: Bool) -> Color {
        if isCurrent { return .blue }
        switch status {
        case .success:    return .green
        case .skipped:    return .orange
        case .failed:     return .red
        case .running:    return .yellow
        case .pending:    return .secondary.opacity(0.4)
        }
    }

    @ViewBuilder
    private var runtimeAuditCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Detected Runtime Access", systemImage: "checklist")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if let discovery = vm.runtimeDiscovery {
                Text("Auto coordinator: \(discovery.coordinatorSelection.selected.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(discovery.discoveries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: runtimeIcon(entry.runtime))
                            .foregroundStyle(entry.authenticated ? .green : .orange)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.runtime.capitalized)
                                .font(.caption.bold())
                            Text(entry.summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if !entry.sources.isEmpty {
                                Text(entry.sources.prefix(2).map { $0.detail }.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        Text(entry.localCliAuth ? "OAuth / CLI" : entry.directApiAvailable ? "API fallback" : "Needs setup")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(entry.localCliAuth ? .green : entry.directApiAvailable ? .blue : .orange)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Scanning installed CLIs and credential stores…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func runtimeIcon(_ runtime: String) -> String {
        switch runtime.lowercased() {
        case "claude": return "sparkles"
        case "codex": return "circle.hexagonpath.fill"
        case "kimi": return "bolt.fill"
        default: return "cpu"
        }
    }
}

// RecommendedTools.swift — curated CLI tools + MCP servers with 1-click install

import Foundation
import SwiftUI

// MARK: - Tool Category

enum RecommendedCategory: String {
    case cli  = "CLI Tools"
    case mcp  = "MCP Servers"
}

// MARK: - Model

struct RecommendedTool: Identifiable {
    let id: String              // stable key used for UserDefaults
    let name: String
    let description: String
    let icon: String
    let iconColor: Color
    let category: RecommendedCategory
    let installScript: String   // bash — called to install
    let uninstallScript: String // bash — called to uninstall
    let checkScript: String     // bash — exit 0 if installed
    let preInstalled: Bool      // register automatically on first launch
}

// MARK: - Catalogue (single source of truth)

extension RecommendedTool {
    static let catalogue: [RecommendedTool] = [

        // ── CLI Tools ─────────────────────────────────────────────────────

        RecommendedTool(
            id: "gcloud",
            name: "Google Cloud CLI",
            description: "gcloud · gsutil · bq — full Google Cloud SDK",
            icon: "cloud.fill",
            iconColor: .blue,
            category: .cli,
            installScript: """
            curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts
            source "$HOME/.bashrc" 2>/dev/null || source "$HOME/.zshrc" 2>/dev/null || true
            gcloud --version
            """,
            uninstallScript: """
            CLOUDSDK_ROOT=$(gcloud info --format="value(installation.sdk_root)" 2>/dev/null)
            if [ -n "$CLOUDSDK_ROOT" ]; then
              rm -rf "$CLOUDSDK_ROOT"
              echo "✓ Google Cloud SDK removed from $CLOUDSDK_ROOT"
            else
              echo "⚠ gcloud not found"
            fi
            """,
            checkScript: "which gcloud",
            preInstalled: false
        ),

        RecommendedTool(
            id: "firebase",
            name: "Firebase CLI",
            description: "Deploy and manage Firebase projects",
            icon: "flame.fill",
            iconColor: .orange,
            category: .cli,
            installScript: """
            curl -sL https://firebase.tools | bash
            firebase --version
            """,
            uninstallScript: """
            npm uninstall -g firebase-tools 2>/dev/null || true
            echo "✓ Firebase CLI uninstalled"
            """,
            checkScript: "which firebase",
            preInstalled: false
        ),

        RecommendedTool(
            id: "mongosh",
            name: "MongoDB Shell",
            description: "mongosh — interactive MongoDB shell",
            icon: "leaf.fill",
            iconColor: .green,
            category: .cli,
            installScript: """
            source ~/.nvm/nvm.sh 2>/dev/null || true
            export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            npm install -g mongosh
            mongosh --version
            """,
            uninstallScript: """
            source ~/.nvm/nvm.sh 2>/dev/null || true
            export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            npm uninstall -g mongosh
            echo "✓ mongosh uninstalled"
            """,
            checkScript: "which mongosh",
            preInstalled: false
        ),

        RecommendedTool(
            id: "atlas",
            name: "Atlas CLI",
            description: "MongoDB Atlas CLI — manage clusters from the terminal",
            icon: "cylinder.split.1x2.fill",
            iconColor: Color(red: 0.0, green: 0.6, blue: 0.3),
            category: .cli,
            installScript: """
            ARCH=$(uname -m)
            if [ "$ARCH" = "arm64" ]; then ATLAS_ARCH="arm64"; else ATLAS_ARCH="x86_64"; fi
            TMPDIR=$(mktemp -d)
            echo "→ Downloading Atlas CLI for macOS $ATLAS_ARCH…"
            # Use latest release API
            LATEST=$(curl -sSf https://api.github.com/repos/mongodb/mongodb-atlas-cli/releases/latest | grep '"tag_name"' | sed 's/.*"v\\([^"]*\\)".*/\\1/')
            curl -sSfL "https://fastdl.mongodb.org/mongocli/atlascli_${LATEST}_macos_${ATLAS_ARCH}.zip" -o "$TMPDIR/atlas.zip"
            unzip -q "$TMPDIR/atlas.zip" -d "$TMPDIR/atlas"
            DEST="$HOME/.local/bin"
            mkdir -p "$DEST"
            mv "$TMPDIR/atlas/bin/atlas" "$DEST/atlas"
            chmod +x "$DEST/atlas"
            rm -rf "$TMPDIR"
            export PATH="$DEST:$PATH"
            atlas --version
            echo "✓ Atlas CLI installed to $DEST/atlas"
            echo "  Add '$DEST' to your PATH if not already present"
            """,
            uninstallScript: """
            rm -f "$HOME/.local/bin/atlas" 2>/dev/null
            rm -f /usr/local/bin/atlas 2>/dev/null
            echo "✓ Atlas CLI removed"
            """,
            checkScript: "which atlas",
            preInstalled: false
        ),

        // ── MCP Servers ───────────────────────────────────────────────────

        RecommendedTool(
            id: "docker-mcp",
            name: "Docker MCP",
            description: "Official Docker MCP server — manage containers via Claude",
            icon: "shippingbox.fill",
            iconColor: .cyan,
            category: .mcp,
            installScript: """
            source ~/.nvm/nvm.sh 2>/dev/null || true
            export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            export PATH="$HOME/.kimi/bin:$HOME/.local/bin:$PATH"
            claude mcp remove docker -s user 2>/dev/null || true
            claude mcp add docker -s user -- npx -y @docker/mcp-servers docker
            echo "✓ Docker MCP registered with Claude"
            """,
            uninstallScript: """
            export PATH="$HOME/.kimi/bin:$HOME/.local/bin:$PATH"
            claude mcp remove docker -s user 2>/dev/null || true
            echo "✓ Docker MCP deregistered from Claude"
            """,
            checkScript: """
            export PATH="$HOME/.kimi/bin:$HOME/.local/bin:$PATH"
            claude mcp list 2>/dev/null | grep -q "^docker"
            """,
            preInstalled: true
        ),

        RecommendedTool(
            id: "github-mcp",
            name: "GitHub MCP",
            description: "Official GitHub MCP server — repositories, PRs, issues via Claude",
            icon: "chevron.left.forwardslash.chevron.right",
            iconColor: .primary,
            category: .mcp,
            installScript: """
            source ~/.nvm/nvm.sh 2>/dev/null || true
            export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
            export PATH="$HOME/.kimi/bin:$HOME/.local/bin:$PATH"
            claude mcp remove github -s user 2>/dev/null || true
            claude mcp add github -s user -- npx -y @modelcontextprotocol/server-github
            echo "✓ GitHub MCP registered with Claude"
            echo "  Run: claude config set env.GITHUB_PERSONAL_ACCESS_TOKEN <your-token>"
            """,
            uninstallScript: """
            export PATH="$HOME/.kimi/bin:$HOME/.local/bin:$PATH"
            claude mcp remove github -s user 2>/dev/null || true
            echo "✓ GitHub MCP deregistered from Claude"
            """,
            checkScript: """
            export PATH="$HOME/.kimi/bin:$HOME/.local/bin:$PATH"
            claude mcp list 2>/dev/null | grep -q "^github"
            """,
            preInstalled: true
        ),
    ]
}

// MARK: - Manager

@MainActor
final class RecommendedToolManager: ObservableObject {
    static let shared = RecommendedToolManager()

    /// Set of tool IDs currently marked installed (persisted in UserDefaults)
    @Published private(set) var installedIDs: Set<String> = []
    @Published var busyID: String? = nil

    private let udKey    = "gg_recommended_installed"
    private let primeKey = "gg_recommended_preinstalled_done"

    private init() {
        let saved = UserDefaults.standard.array(forKey: udKey) as? [String] ?? []
        installedIDs = Set(saved)
    }

    // MARK: - Pre-install

    /// Call once on app launch — installs Docker MCP + GitHub MCP if not already done.
    func preInstallIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: primeKey) else { return }
        let tools = RecommendedTool.catalogue.filter(\.preInstalled)
        guard !tools.isEmpty else { return }
        Task {
            PackageManager.shared.appendLog("→ Pre-installing MCP servers: \(tools.map(\.name).joined(separator: ", "))…")
            for tool in tools {
                await runInstall(tool)
            }
            UserDefaults.standard.set(true, forKey: primeKey)
            PackageManager.shared.appendLog("✓ Pre-install complete")
        }
    }

    // MARK: - Install / Uninstall

    func install(_ tool: RecommendedTool) async {
        busyID = tool.id
        PackageManager.shared.appendLog("→ Installing \(tool.name)…")
        await runInstall(tool)
        busyID = nil
    }

    func uninstall(_ tool: RecommendedTool) async {
        busyID = tool.id
        PackageManager.shared.appendLog("→ Uninstalling \(tool.name)…")
        let (ok, err) = await shell(tool.uninstallScript)
        if ok {
            markUninstalled(tool.id)
            PackageManager.shared.appendLog("✓ \(tool.name) uninstalled")
        } else {
            PackageManager.shared.appendLog("✗ \(tool.name) uninstall failed: \(err)", error: true)
        }
        busyID = nil
    }

    /// Refresh installed state by running checkScript for all tools.
    func refreshStatus() {
        Task {
            for tool in RecommendedTool.catalogue {
                let (ok, _) = await shell(tool.checkScript)
                if ok { markInstalled(tool.id) } else { markUninstalled(tool.id) }
            }
        }
    }

    func isInstalled(_ id: String) -> Bool { installedIDs.contains(id) }

    // MARK: - Internals

    private func runInstall(_ tool: RecommendedTool) async {
        let (ok, err) = await shell(tool.installScript)
        if ok {
            markInstalled(tool.id)
            PackageManager.shared.appendLog("✓ \(tool.name) installed")
        } else {
            PackageManager.shared.appendLog("✗ \(tool.name) install failed: \(err)", error: true)
        }
    }

    private func markInstalled(_ id: String) {
        installedIDs.insert(id)
        persist()
    }

    private func markUninstalled(_ id: String) {
        installedIDs.remove(id)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(installedIDs), forKey: udKey)
    }

    // MARK: - Shell runner (mirrors PackageManager.shell)

    private func shell(_ script: String) async -> (Bool, String) {
        let logOut: @Sendable (String) -> Void = { text in
            Task { @MainActor in PackageManager.shared.appendLog(text) }
        }
        return await Task.detached(priority: .userInitiated) {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("gg_rec_\(UUID().uuidString).sh")
            let full = "#!/bin/bash\nset -uo pipefail\nsource ~/.nvm/nvm.sh 2>/dev/null || true\nexport NVM_DIR=\"$HOME/.nvm\"; [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"\nexport PATH=\"$HOME/.kimi/bin:$HOME/.local/bin:$PATH\"\n" + script
            try? full.write(to: tmp, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)

            let out = Pipe(); let err = Pipe()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [tmp.path]
            proc.standardOutput = out; proc.standardError = err
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; guard !d.isEmpty else { return }
                if let t = String(data: d, encoding: .utf8) {
                    t.components(separatedBy: "\n").filter { !$0.isEmpty }.forEach(logOut)
                }
            }
            try? proc.run(); proc.waitUntilExit()
            try? FileManager.default.removeItem(at: tmp)
            let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (proc.terminationStatus == 0, errStr)
        }.value
    }
}

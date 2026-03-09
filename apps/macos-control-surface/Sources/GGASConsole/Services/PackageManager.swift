// PackageManager.swift — clone, sync assets, register with Claude + Kimi

import Foundation
import SwiftUI

// MARK: - Log entry

struct PackageLogLine: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

// MARK: - Manager

@MainActor
final class PackageManager: ObservableObject {
    static let shared = PackageManager()
    private let registry = PackageRegistry.shared

    @Published var log: [PackageLogLine] = []
    @Published var isBusy = false
    @Published var busyLabel = ""

    private init() {}

    // MARK: - Project root

    /// Always reads from ProjectSettings — portable across any user's machine.
    private var projectRoot: String { ProjectSettings.shared.projectRoot }

    // MARK: - Public API

    func install(url: String) async {
        guard let (owner, repo) = PackageRegistry.parse(url: url) else {
            appendLog("✗ Invalid URL format. Expected: github.com/owner/repo", error: true)
            return
        }
        if registry.packages.contains(where: { $0.id == "\(owner)/\(repo)" }) {
            appendLog("⚠ \(owner)/\(repo) is already installed. Use Update instead.", error: false)
            return
        }

        isBusy = true
        busyLabel = "Installing \(repo)…"
        appendLog("→ Installing \(owner)/\(repo)…")

        let cloneDir = NSHomeDirectory() + "/.ggas/packages/\(owner)/\(repo)"
        let cloneURL = "https://github.com/\(owner)/\(repo).git"

        let cloneScript = """
        mkdir -p "\(NSHomeDirectory())/.ggas/packages/\(owner)"
        if [ -d "\(cloneDir)" ]; then
          echo "→ Repo already cloned — pulling latest"
          git -C "\(cloneDir)" pull --rebase --quiet
        else
          git clone --depth=1 "\(cloneURL)" "\(cloneDir)"
        fi
        """
        let (cloneOK, cloneErr) = await shell(cloneScript)
        guard cloneOK else {
            appendLog("✗ Clone failed: \(cloneErr)", error: true)
            isBusy = false
            return
        }
        appendLog("✓ Cloned to \(cloneDir)")

        // Read optional manifest
        let manifest = readManifest(cloneDir: cloneDir)

        // Sync assets
        var pkg = GGASPackage(
            owner: owner, repo: repo, url: url,
            installedAt: .now, lastUpdated: .now,
            manifest: manifest, installedFiles: InstalledFiles()
        )
        await syncAssets(pkg: &pkg, cloneDir: cloneDir, isUpdate: false)

        registry.add(pkg)
        appendLog("✓ \(repo) installed successfully")
        isBusy = false
        busyLabel = ""
    }

    func update(pkg: GGASPackage) async {
        isBusy = true
        busyLabel = "Updating \(pkg.repo)…"
        appendLog("→ Updating \(pkg.id)…")

        let cloneDir = pkg.clonePath
        let pullScript = """
        git -C "\(cloneDir)" fetch --quiet
        git -C "\(cloneDir)" pull --rebase --quiet
        """
        let (ok, err) = await shell(pullScript)
        if !ok { appendLog("⚠ Git pull had errors: \(err)", error: true) }

        // Remove old installed files before re-syncing
        removeInstalledAssets(pkg.installedFiles)

        var updated = pkg
        updated.lastUpdated = .now
        updated.manifest = readManifest(cloneDir: cloneDir)
        updated.installedFiles = InstalledFiles()
        await syncAssets(pkg: &updated, cloneDir: cloneDir, isUpdate: true)

        registry.update(updated)
        appendLog("✓ \(pkg.repo) updated")
        isBusy = false
        busyLabel = ""
    }

    func uninstall(pkg: GGASPackage) async {
        isBusy = true
        busyLabel = "Uninstalling \(pkg.repo)…"
        appendLog("→ Uninstalling \(pkg.id)…")

        removeInstalledAssets(pkg.installedFiles)
        await deregisterMCP(names: pkg.installedFiles.mcpServers)

        // Remove clone
        let (_, _) = await shell("rm -rf \"\(pkg.clonePath)\"")
        appendLog("✓ Clone removed")

        registry.remove(pkg)
        appendLog("✓ \(pkg.repo) uninstalled")
        isBusy = false
        busyLabel = ""
    }

    func reinstall(pkg: GGASPackage) async {
        appendLog("→ Reinstalling \(pkg.id)…")
        await uninstall(pkg: pkg)
        await install(url: pkg.url)
    }

    // MARK: - LM Studio model install

    /// Download a model from HuggingFace via `lms get <hfRepo>/<file>`.
    /// - Parameters:
    ///   - hfRepo: HuggingFace repo path, e.g. "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF"
    ///   - file:   Specific GGUF file to download, e.g. "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"
    ///             Pass empty string to let LM Studio pick the recommended quantization.
    func installModel(hfRepo: String, file: String = "") async {
        guard !hfRepo.isEmpty else {
            appendLog("✗ installModel: hfRepo cannot be empty", error: true)
            return
        }

        let target = file.isEmpty ? hfRepo : "\(hfRepo)/\(file)"
        let shortName = hfRepo.components(separatedBy: "/").last ?? hfRepo

        isBusy = true
        busyLabel = "Downloading \(shortName)…"
        appendLog("→ Downloading model: \(target)")

        // Check lms CLI availability
        guard let lmsBin = LMStudioCLI.shared.binaryPath else {
            appendLog("✗ lms CLI not found. Install LM Studio first.", error: true)
            isBusy = false
            busyLabel = ""
            return
        }
        guard FileManager.default.fileExists(atPath: lmsBin) else {
            appendLog("✗ lms CLI not found at \(lmsBin). Install LM Studio first.", error: true)
            isBusy = false
            busyLabel = ""
            return
        }

        let script: String
        if file.isEmpty {
            script = "\"\(lmsBin)\" get \"\(hfRepo)\" 2>&1"
        } else {
            script = "\"\(lmsBin)\" get \"\(hfRepo)\" --file \"\(file)\" 2>&1"
        }

        let (ok, errOut) = await shell(script)
        if ok {
            appendLog("✓ Model downloaded: \(shortName)")
        } else {
            appendLog("✗ Download failed for \(shortName): \(errOut)", error: true)
        }

        isBusy = false
        busyLabel = ""
    }

    // MARK: - Core sync

    private func syncAssets(pkg: inout GGASPackage, cloneDir: String, isUpdate: Bool) async {
        let root = projectRoot
        let m = pkg.manifest

        // 1. Skills
        let skillsSrc = cloneDir + "/" + m.skillsDir
        let skillsDst = root + "/.agent/skills"
        let installedSkills = copyDir(src: skillsSrc, dst: skillsDst, label: "skills")
        pkg.installedFiles.skills = installedSkills
        if !installedSkills.isEmpty { appendLog("✓ \(installedSkills.count) skill(s) installed") }

        // 2. Workflows
        let wfSrc = cloneDir + "/" + m.workflowsDir
        let wfDst = root + "/.agent/workflows"
        let installedWF = copyDir(src: wfSrc, dst: wfDst, label: "workflows")
        pkg.installedFiles.workflows = installedWF
        if !installedWF.isEmpty { appendLog("✓ \(installedWF.count) workflow(s) installed") }

        // 3. Agents/personas
        let agentsSrc = cloneDir + "/" + m.agentsDir
        let agentsDst = root + "/.agent/agents"
        let installedAgents = copyDir(src: agentsSrc, dst: agentsDst, label: "agents")
        pkg.installedFiles.agents = installedAgents
        if !installedAgents.isEmpty { appendLog("✓ \(installedAgents.count) agent persona(s) installed") }

        // 4. MCP servers — build + register with Claude + Kimi
        let mcpSrc = cloneDir + "/" + m.mcpDir
        if FileManager.default.fileExists(atPath: mcpSrc) {
            await installMCPServers(pkg: &pkg, mcpSrc: mcpSrc, cloneDir: cloneDir)
        }

        // 5. Register gg-skills env update (skills dir may have new items)
        await refreshGGSkillsEnv()
    }

    // MARK: - File copy helpers

    private func copyDir(src: String, dst: String, label: String) -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src) else { return [] }
        try? fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        var installed: [String] = []
        let items = (try? fm.contentsOfDirectory(atPath: src)) ?? []
        for item in items where !item.hasPrefix(".") {
            let srcItem = src + "/" + item
            let dstItem = dst + "/" + item
            try? fm.removeItem(atPath: dstItem)
            do {
                try fm.copyItem(atPath: srcItem, toPath: dstItem)
                installed.append(item)
            } catch {
                appendLog("⚠ Could not copy \(label)/\(item): \(error.localizedDescription)", error: true)
            }
        }
        return installed
    }

    private func removeInstalledAssets(_ files: InstalledFiles) {
        let root = projectRoot
        let fm = FileManager.default

        for name in files.skills    { try? fm.removeItem(atPath: root + "/.agent/skills/\(name)") }
        for name in files.workflows { try? fm.removeItem(atPath: root + "/.agent/workflows/\(name)") }
        for name in files.agents    { try? fm.removeItem(atPath: root + "/.agent/agents/\(name)") }

        if !files.skills.isEmpty    { appendLog("✓ \(files.skills.count) skill(s) removed") }
        if !files.workflows.isEmpty { appendLog("✓ \(files.workflows.count) workflow(s) removed") }
        if !files.agents.isEmpty    { appendLog("✓ \(files.agents.count) agent persona(s) removed") }
    }

    // MARK: - MCP server handling

    private func installMCPServers(pkg: inout GGASPackage, mcpSrc: String, cloneDir: String) async {
        let fm = FileManager.default
        let servers = (try? fm.contentsOfDirectory(atPath: mcpSrc)) ?? []
        var registeredNames: [String] = []

        for server in servers where !server.hasPrefix(".") {
            let serverDir = mcpSrc + "/" + server
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: serverDir, isDirectory: &isDir), isDir.boolValue else { continue }

            let pkgJson = serverDir + "/package.json"
            guard fm.fileExists(atPath: pkgJson) else { continue }

            appendLog("→ Building MCP server: \(server)…")
            let buildScript = """
            cd "\(serverDir)"
            npm install --silent 2>&1
            if [ -f "tsconfig.json" ]; then
              npx tsc --noEmit 2>/dev/null && npm run build --silent 2>&1 || true
            fi
            """
            let (buildOK, buildErr) = await shell(buildScript)
            if !buildOK { appendLog("⚠ Build issues for \(server): \(buildErr)", error: true) }

            // Find entry point
            let distIndex = serverDir + "/dist/index.js"
            let srcIndex  = serverDir + "/src/index.js"
            let rootIndex = serverDir + "/index.js"
            let entryPoint: String
            if fm.fileExists(atPath: distIndex) { entryPoint = distIndex }
            else if fm.fileExists(atPath: srcIndex) { entryPoint = srcIndex }
            else if fm.fileExists(atPath: rootIndex) { entryPoint = rootIndex }
            else { appendLog("⚠ No entry point found for \(server) — skipping MCP registration", error: true); continue }

            // Register with Claude
            let claudeScript = """
            claude mcp remove "\(server)" -s user 2>/dev/null || true
            claude mcp add "\(server)" -s user -- node "\(entryPoint)" 2>&1
            """
            let (claudeOK, _) = await shell(claudeScript)
            if claudeOK {
                appendLog("✓ Claude MCP: \(server) registered")
                registeredNames.append(server)
            } else {
                appendLog("⚠ Claude MCP registration failed for \(server)", error: true)
            }

            // Register with Kimi (.mcp.kimi.json)
            await addToKimiMCP(name: server, entryPoint: entryPoint)
        }

        pkg.installedFiles.mcpServers = registeredNames
    }

    private func deregisterMCP(names: [String]) async {
        guard !names.isEmpty else { return }
        let removeLines = names.map { "claude mcp remove \"\($0)\" -s user 2>/dev/null || true" }.joined(separator: "\n")
        let (_, _) = await shell(removeLines)
        appendLog("✓ \(names.count) MCP server(s) deregistered from Claude")
        await removeFromKimiMCP(names: names)
    }

    // MARK: - Kimi .mcp.kimi.json management

    private func addToKimiMCP(name: String, entryPoint: String) async {
        let kimiConfigPath = projectRoot + "/.mcp.kimi.json"
        guard var json = readJSON(kimiConfigPath),
              var servers = json["mcpServers"] as? [String: Any] else { return }

        servers[name] = [
            "command": "node",
            "args": [entryPoint],
            "description": "Package: \(name)"
        ]
        json["mcpServers"] = servers
        writeJSON(json, to: kimiConfigPath)
        appendLog("✓ Kimi MCP: \(name) registered")
    }

    private func removeFromKimiMCP(names: [String]) async {
        let kimiConfigPath = projectRoot + "/.mcp.kimi.json"
        guard var json = readJSON(kimiConfigPath),
              var servers = json["mcpServers"] as? [String: Any] else { return }
        for name in names { servers.removeValue(forKey: name) }
        json["mcpServers"] = servers
        writeJSON(json, to: kimiConfigPath)
        appendLog("✓ \(names.count) server(s) removed from Kimi config")
    }

    // MARK: - GG-Skills env refresh

    private func refreshGGSkillsEnv() async {
        // Re-register gg-skills with updated SKILLS_DIR so it picks up new skills
        let root = projectRoot
        let ggSkills = root + "/mcp-servers/gg-skills/dist/index.js"
        let skills   = root + "/.agent/skills"
        let flows    = root + "/.agent/workflows"
        guard FileManager.default.fileExists(atPath: ggSkills) else { return }
        let script = """
        claude mcp remove gg-skills -s user 2>/dev/null || true
        claude mcp add gg-skills -s user \\
          -e SKILLS_DIR="\(skills)" \\
          -e WORKFLOWS_DIR="\(flows)" \\
          -- node "\(ggSkills)" 2>&1
        """
        let (ok, _) = await shell(script)
        if ok { appendLog("✓ gg-skills MCP refreshed with new skills/workflows") }
    }

    // MARK: - Manifest reading

    private func readManifest(cloneDir: String) -> PackageManifest {
        let path = cloneDir + "/ggas-package.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let decoded = try? JSONDecoder().decode(PackageManifest.self, from: data)
        else { return PackageManifest() }
        return decoded
    }

    // MARK: - JSON helpers

    private func readJSON(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private func writeJSON(_ json: [String: Any], to path: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    // MARK: - Shell helper

    private func shell(_ script: String) async -> (Bool, String) {
        // Capture log callbacks as Sendable closures to avoid Swift 6 captured-var warnings
        let logOut: @Sendable (String) -> Void = { text in
            Task { @MainActor in
                PackageManager.shared.appendLog(text)
            }
        }
        let logErr: @Sendable (String) -> Void = { text in
            Task { @MainActor in
                PackageManager.shared.appendLog(text, error: true)
            }
        }
        return await Task.detached(priority: .userInitiated) {
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ggas_pkg_\(UUID().uuidString).sh")
            let full = "#!/bin/bash\nset -uo pipefail\nsource ~/.nvm/nvm.sh 2>/dev/null || true\nexport NVM_DIR=\"$HOME/.nvm\"; [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"\nexport PATH=\"$HOME/.kimi/bin:$HOME/.local/bin:$PATH\"\n" + script
            try? full.write(to: tmp, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)

            let outPipe = Pipe(); let errPipe = Pipe()
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/bash")
            proc.arguments = [tmp.path]
            proc.standardOutput = outPipe
            proc.standardError  = errPipe

            outPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; guard !d.isEmpty else { return }
                if let text = String(data: d, encoding: .utf8) {
                    text.components(separatedBy: "\n").filter { !$0.isEmpty }.forEach(logOut)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData; guard !d.isEmpty else { return }
                if let text = String(data: d, encoding: .utf8) {
                    text.components(separatedBy: "\n").filter { !$0.isEmpty }.forEach(logErr)
                }
            }

            try? proc.run(); proc.waitUntilExit()
            try? FileManager.default.removeItem(at: tmp)
            let errOut = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (proc.terminationStatus == 0, errOut)
        }.value
    }

    // MARK: - Log helpers

    func appendLog(_ text: String, error: Bool = false) {
        if log.count >= 1000 { log.removeFirst(100) }
        log.append(PackageLogLine(text: text, isError: error))
    }

    func clearLog() { log.removeAll() }
}

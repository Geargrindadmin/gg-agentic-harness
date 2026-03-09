// ProjectSettings.swift — portable project root configuration

import Foundation
import AppKit

/// Owns the single "active project root" — persisted in UserDefaults.
/// Imported control-surface code should resolve repo paths through this type
/// instead of hardcoding legacy repo names.
@MainActor
final class ProjectSettings: ObservableObject {
    struct JCodeLaunchProfile: Codable, Equatable {
        var useWrapper: Bool = true
        var provider: String = "auto"
        var model: String = ""
        var workingDirectory: String = ""
        var resumeSession: String = ""
        var launchMode: String = "interactive" // interactive | run
        var runMessage: String = ""
    }

    static let shared = ProjectSettings()

    private let key = "gg_project_root"
    private let launchProfileKey = "gg_jcode_launch_profile"
    private let controlPlaneURLKey = "gg_control_plane_base_url"

    /// The user-configured (or auto-detected) project root path.
    @Published var projectRoot: String = "" {
        didSet {
            UserDefaults.standard.set(projectRoot, forKey: key)
        }
    }

    @Published var controlPlaneBaseURL: String = "http://127.0.0.1:7891" {
        didSet {
            UserDefaults.standard.set(controlPlaneBaseURL, forKey: controlPlaneURLKey)
        }
    }

    @Published var jcodeLaunchProfile: JCodeLaunchProfile = .init() {
        didSet {
            guard let data = try? JSONEncoder().encode(jcodeLaunchProfile) else { return }
            UserDefaults.standard.set(data, forKey: launchProfileKey)
        }
    }

    /// True when we have a valid, confirmed project root.
    var isConfigured: Bool {
        !projectRoot.isEmpty && FileManager.default.fileExists(atPath: projectRoot)
    }

    private init() {
        if let stored = UserDefaults.standard.data(forKey: launchProfileKey),
           let decoded = try? JSONDecoder().decode(JCodeLaunchProfile.self, from: stored) {
            jcodeLaunchProfile = decoded
        }

        if let storedControlPlaneURL = UserDefaults.standard.string(forKey: controlPlaneURLKey),
           !storedControlPlaneURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            controlPlaneBaseURL = storedControlPlaneURL
        }

        // 1. Restore from UserDefaults
        if let saved = UserDefaults.standard.string(forKey: key),
           !saved.isEmpty,
           FileManager.default.fileExists(atPath: saved) {
            projectRoot = saved
            return
        }
        // 2. Auto-detect from common locations
        if let detected = autoDetect() {
            projectRoot = detected
            UserDefaults.standard.set(detected, forKey: key)
        }
    }

    // MARK: - Auto-detection

    /// Walk candidate directories looking for a likely harness project root.
    private func autoDetect() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()

        if let compileTimeRoot = compileTimeRepoRoot(), isLikelyProjectRoot(compileTimeRoot) {
            return compileTimeRoot
        }

        // Candidate roots to search inside
        let searchRoots = [
            home + "/Documents",
            home + "/Developer",
            home + "/Projects",
            home + "/Code",
            home
        ]

        // Marker files that indicate a harness project root.
        let markers = [".agent", "AGENTS.md", "CLAUDE.md", "package.json", "mcp-servers", "packages"]

        for searchRoot in searchRoots {
            guard let subdirs = try? fm.contentsOfDirectory(atPath: searchRoot) else { continue }
            for subdir in subdirs {
                let candidate = searchRoot + "/" + subdir
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue else { continue }
                let markerCount = markers.filter { fm.fileExists(atPath: candidate + "/" + $0) }.count
                if markerCount >= 3 {
                    return candidate
                }
            }
        }
        return nil
    }

    private func isLikelyProjectRoot(_ path: String) -> Bool {
        let fm = FileManager.default
        let markers = [".agent", "AGENTS.md", "CLAUDE.md", "package.json", "mcp-servers", "packages"]
        let markerCount = markers.filter { fm.fileExists(atPath: path + "/" + $0) }.count
        return markerCount >= 3
    }

    private func compileTimeRepoRoot() -> String? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
        }
        let candidate = url.path
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    // MARK: - Folder picker

    /// Opens a macOS open-panel so the user can choose their project root manually.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Your Harness Project Folder"
        panel.message = "Select the root folder of your agentic project (the one containing AGENTS.md, .agent/, CLAUDE.md, package.json, etc.)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Documents")

        if panel.runModal() == .OK, let url = panel.url {
            projectRoot = url.path
        }
    }

    // MARK: - Convenience paths

    var normalizedControlPlaneBaseURL: String {
        let trimmed = controlPlaneBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = "http://127.0.0.1:7891"
        let base = trimmed.isEmpty ? fallback : trimmed
        return base.hasSuffix("/") ? String(base.dropLast()) : base
    }

    var controlPlaneAPIBaseURL: String { normalizedControlPlaneBaseURL + "/api" }

    var controlPlanePort: Int {
        URL(string: normalizedControlPlaneBaseURL)?.port ?? 7891
    }

    var skillsDir:    String { projectRoot + "/.agent/skills" }
    var workflowsDir: String { projectRoot + "/.agent/workflows" }
    var agentsDir:    String { projectRoot + "/.agent/agents" }
    var kimiConfig:   String { projectRoot + "/.mcp.kimi.json" }

    var ggSkillsEntry: String {
        let local = projectRoot + "/mcp-servers/gg-skills/dist/index.js"
        if FileManager.default.fileExists(atPath: local) { return local }

        // Legacy fallback for machines still carrying the older repo split.
        let parent = URL(fileURLWithPath: projectRoot).deletingLastPathComponent().path
        let sibling = parent + "/GearGrind-Agentic-System/mcp-servers/gg-skills/dist/index.js"
        if FileManager.default.fileExists(atPath: sibling) { return sibling }
        return local
    }
}

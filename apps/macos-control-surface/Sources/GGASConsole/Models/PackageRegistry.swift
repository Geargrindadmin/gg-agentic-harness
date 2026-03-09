// PackageRegistry.swift — tracks installed GitHub extension packages

import Foundation

// MARK: - Models

struct GGASPackage: Codable, Identifiable {
    var id: String { "\(owner)/\(repo)" }
    let owner:       String
    let repo:        String
    let url:         String
    var installedAt: Date
    var lastUpdated: Date
    var manifest:    PackageManifest
    var installedFiles: InstalledFiles

    /// Local clone path: ~/.ggas/packages/<owner>/<repo>
    var clonePath: String {
        NSHomeDirectory() + "/.ggas/packages/\(owner)/\(repo)"
    }

    var displayName: String { manifest.name.isEmpty ? repo : manifest.name }
    var version: String     { manifest.version.isEmpty ? "—" : manifest.version }
}

/// Optional ggas-package.json in the repo root
struct PackageManifest: Codable {
    var name: String        = ""
    var version: String     = ""
    var description: String = ""
    var author: String      = ""
    /// Directories to scan — defaults applied if empty
    var skillsDir:    String = ".agent/skills"
    var workflowsDir: String = ".agent/workflows"
    var agentsDir:    String = ".agent/agents"
    var mcpDir:       String = "mcp-servers"
}

/// Records exactly what files were installed so we can fully clean up
struct InstalledFiles: Codable {
    var skills:     [String] = []   // basenames installed into project .agent/skills/
    var workflows:  [String] = []   // basenames installed into project .agent/workflows/
    var agents:     [String] = []   // basenames installed into project .agent/agents/
    var mcpServers: [String] = []   // server names registered with 'claude mcp add'
    var kimiMCPs:   [String] = []   // server entries added to .mcp.kimi.json
}

// MARK: - Registry

@MainActor
final class PackageRegistry: ObservableObject {
    static let shared = PackageRegistry()

    @Published var packages: [GGASPackage] = []

    private var registryURL: URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/.ggas/packages")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("registry.json")
    }

    private init() { load() }

    func load() {
        guard FileManager.default.fileExists(atPath: registryURL.path),
              let data = try? Data(contentsOf: registryURL),
              let decoded = try? JSONDecoder().decode([GGASPackage].self, from: data)
        else { return }
        packages = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(packages) else { return }
        try? data.write(to: registryURL, options: .atomic)
    }

    func add(_ pkg: GGASPackage) {
        packages.removeAll { $0.id == pkg.id }
        packages.append(pkg)
        save()
    }

    func remove(_ pkg: GGASPackage) {
        packages.removeAll { $0.id == pkg.id }
        save()
    }

    func update(_ pkg: GGASPackage) {
        if let idx = packages.firstIndex(where: { $0.id == pkg.id }) {
            packages[idx] = pkg
            save()
        }
    }

    static func parse(url: String) -> (owner: String, repo: String)? {
        // Accept: https://github.com/owner/repo  or  github.com/owner/repo  or  owner/repo
        var clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        clean = clean.replacingOccurrences(of: "https://", with: "")
        clean = clean.replacingOccurrences(of: "http://", with: "")
        clean = clean.replacingOccurrences(of: "github.com/", with: "")
        clean = clean.replacingOccurrences(of: ".git", with: "")
        let parts = clean.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1])
    }
}

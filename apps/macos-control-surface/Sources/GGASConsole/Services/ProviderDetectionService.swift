// ProviderDetectionService.swift — dynamic provider/model catalog for macOS app
// Sources provider metadata from `jcode providers --json` (fallbacks included).

import Foundation
import Combine

// MARK: - Catalog models

struct ProviderCatalogEntry: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let displayName: String
    let authKind: String
    let recommended: Bool
    let aliases: [String]
    let defaultModel: String?
    let modelHints: [String]

    var icon: String {
        switch id {
        case "claude": return "sparkles"
        case "copilot": return "chevron.left.forwardslash.chevron.right"
        case "openai": return "circle.hexagonpath.fill"
        case "openrouter": return "arrow.triangle.branch"
        case "cursor": return "cursorarrow.rays"
        case "antigravity": return "wand.and.stars"
        case "google": return "envelope.badge"
        default: return "cpu"
        }
    }

    var models: [String] {
        var seen = Set<String>()
        var values: [String] = []
        if let defaultModel, !defaultModel.isEmpty {
            seen.insert(defaultModel)
            values.append(defaultModel)
        }
        for hint in modelHints where !hint.isEmpty && !seen.contains(hint) {
            seen.insert(hint)
            values.append(hint)
        }
        return values
    }
}

private struct ProviderCatalogResponse: Decodable {
    let providers: [ProviderCatalogEntry]
}

// MARK: - Config stored in ~/.ggas/config.json

struct GGASConfig: Codable {
    var selectedProvider: String?
    var selectedModel: String?

    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ggas/config.json")

    static func load() -> GGASConfig {
        guard let data = try? Data(contentsOf: path),
              let cfg = try? JSONDecoder().decode(GGASConfig.self, from: data)
        else { return GGASConfig() }
        return cfg
    }

    func save() {
        try? JSONEncoder().encode(self).write(to: GGASConfig.path)
    }
}

// MARK: - Service

@MainActor
final class ProviderDetectionService: ObservableObject {
    static let shared = ProviderDetectionService()

    @Published var availableProviders: [ProviderCatalogEntry] = []
    @Published var selectedProvider: ProviderCatalogEntry? = nil
    @Published var selectedModel: String = ""

    private var config = GGASConfig.load()
    private let hd = FileManager.default.homeDirectoryForCurrentUser

    private init() {
        refresh()
    }

    // MARK: - Public

    func refresh() {
        let discovered = loadCatalogProviders()
        availableProviders = discovered

        if let selectedId = config.selectedProvider,
           let match = discovered.first(where: { $0.id == selectedId }) {
            selectedProvider = match
        } else {
            selectedProvider = discovered.first
        }

        if selectedModel.isEmpty {
            selectedModel = config.selectedModel ?? selectedProvider?.models.first ?? ""
        }

        if let selected = selectedProvider,
           !selectedModel.isEmpty,
           !selected.models.isEmpty,
           !selected.models.contains(selectedModel) {
            selectedModel = selected.models.first ?? ""
        }
    }

    func select(provider: ProviderCatalogEntry, model: String) {
        selectedProvider = provider
        selectedModel = model
        config.selectedProvider = provider.id
        config.selectedModel = model
        config.save()
        writeEnvOverrides()
    }

    // MARK: - Private

    private func loadCatalogProviders() -> [ProviderCatalogEntry] {
        if let dynamic = queryJCodeCatalog(), !dynamic.providers.isEmpty {
            return dynamic.providers
        }
        return fallbackCatalog()
    }

    private func queryJCodeCatalog() -> ProviderCatalogResponse? {
        let candidates = commandCandidates()
        for candidate in candidates {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: candidate.executable)
            proc.arguments = candidate.arguments + ["providers", "--json"]
            if let cwd = candidate.cwd {
                proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
            }

            let out = Pipe()
            let err = Pipe()
            proc.standardOutput = out
            proc.standardError = err

            do {
                try proc.run()
                proc.waitUntilExit()
                guard proc.terminationStatus == 0 else { continue }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                guard !data.isEmpty else { continue }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let catalog = try? decoder.decode(ProviderCatalogResponse.self, from: data) {
                    return catalog
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func commandCandidates() -> [(executable: String, arguments: [String], cwd: String?)] {
        var candidates: [(String, [String], String?)] = []
        let projectRoot = ProjectSettings.shared.projectRoot

        let wrapperPath = projectRoot + "/tools/gg-cli/gg-cli.sh"
        if FileManager.default.isExecutableFile(atPath: wrapperPath) {
            candidates.append((wrapperPath, [], projectRoot.isEmpty ? nil : projectRoot))
        }

        let jcodeCandidates = [
            projectRoot + "/tools/gg-cli/target/release/jcode",
            NSHomeDirectory() + "/.local/bin/jcode",
            "/opt/homebrew/bin/jcode",
            "/usr/local/bin/jcode",
        ]
        for path in jcodeCandidates where FileManager.default.isExecutableFile(atPath: path) {
            candidates.append((path, [], projectRoot.isEmpty ? nil : projectRoot))
        }
        return candidates
    }

    private func fallbackCatalog() -> [ProviderCatalogEntry] {
        [
            ProviderCatalogEntry(
                id: "claude",
                displayName: "Anthropic/Claude",
                authKind: "OAuth",
                recommended: true,
                aliases: ["anthropic"],
                defaultModel: "claude-opus-4-6",
                modelHints: ["claude-sonnet-4-6", "claude-haiku-4-5"]
            ),
            ProviderCatalogEntry(
                id: "openai",
                displayName: "OpenAI",
                authKind: "OAuth",
                recommended: true,
                aliases: [],
                defaultModel: "gpt-5.4",
                modelHints: ["gpt-5.3-codex", "gpt-5"]
            ),
            ProviderCatalogEntry(
                id: "openrouter",
                displayName: "OpenRouter",
                authKind: "API key",
                recommended: false,
                aliases: [],
                defaultModel: "anthropic/claude-sonnet-4",
                modelHints: ["moonshotai/kimi-k2", "openai/gpt-5"]
            ),
            ProviderCatalogEntry(
                id: "copilot",
                displayName: "GitHub Copilot",
                authKind: "Device code",
                recommended: false,
                aliases: [],
                defaultModel: "claude-sonnet-4-6",
                modelHints: ["gpt-5.3-codex", "gpt-5.1"]
            ),
        ]
    }

    /// Writes selected model overrides to ~/.ggas/agent-model-override.env.
    private func writeEnvOverrides() {
        guard let provider = selectedProvider else { return }
        var lines = ["# Auto-generated by GGAS macOS app — do not edit manually"]

        switch provider.id {
        case "claude":
            lines.append("export JCODE_ANTHROPIC_MODEL=\"\(selectedModel)\"")
        case "openai":
            lines.append("export JCODE_OPENAI_MODEL=\"\(selectedModel)\"")
        case "openrouter":
            lines.append("export JCODE_OPENROUTER_MODEL=\"\(selectedModel)\"")
        case "copilot":
            lines.append("export JCODE_COPILOT_MODEL=\"\(selectedModel)\"")
        case "cursor":
            lines.append("export JCODE_CURSOR_MODEL=\"\(selectedModel)\"")
        case "antigravity":
            lines.append("export JCODE_ANTIGRAVITY_MODEL=\"\(selectedModel)\"")
        case "opencode", "opencode-go", "zai", "chutes", "cerebras", "openai-compatible":
            lines.append("export JCODE_OPENAI_COMPAT_DEFAULT_MODEL=\"\(selectedModel)\"")
        default:
            lines.append("# No provider-specific model override required")
        }

        let envFile = hd.appendingPathComponent(".ggas/agent-model-override.env")
        try? lines.joined(separator: "\n").data(using: .utf8)?.write(to: envFile)
    }
}

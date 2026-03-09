// APIKeyStore.swift — Persists ANTHROPIC_API_KEY + MOONSHOT_API_KEY
// Keys are written to ~/.ggas/env for consumption by shell scripts and MCP servers.
// UserDefaults stores redacted presence flags (never the raw keys) for UI state.

import Foundation

@MainActor
final class APIKeyStore: ObservableObject {
    static let shared = APIKeyStore()

    // Published flags — true = key is set (non-empty), false = not set
    @Published var hasAnthropicKey = false
    @Published var hasMoonshotKey  = false
    @Published var hasOpenAIKey    = false
    @Published var hasGeminiKey    = false

    private let envDir  = NSHomeDirectory() + "/.ggas"
    private var envFile: String { envDir + "/env" }

    private init() { reload() }

    // MARK: - Read

    /// Returns the current raw value of a key from ~/.ggas/env, or nil if absent.
    func currentValue(for prefix: String) -> String? {
        guard let content = try? String(contentsOfFile: envFile, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("export \(prefix)=\"") {
                let inner = line
                    .dropFirst("export \(prefix)=\"".count)
                    .dropLast(line.hasSuffix("\"") ? 1 : 0)
                return inner.isEmpty ? nil : String(inner)
            }
        }
        return nil
    }

    func reload() {
        hasAnthropicKey = currentValue(for: "ANTHROPIC_API_KEY") != nil
        hasMoonshotKey  = currentValue(for: "MOONSHOT_API_KEY")  != nil
        hasOpenAIKey    = currentValue(for: "OPENAI_API_KEY")    != nil
        hasGeminiKey    = currentValue(for: "GEMINI_API_KEY")    != nil
    }

    // MARK: - Write

    func save(anthropic: String, moonshot: String, openAI: String = "", gemini: String = "") {
        try? FileManager.default.createDirectory(atPath: envDir, withIntermediateDirectories: true)

        var lines: [String] = []
        if let existing = try? String(contentsOfFile: envFile, encoding: .utf8) {
            lines = existing.components(separatedBy: "\n")
                .filter {
                    !$0.hasPrefix("export ANTHROPIC_API_KEY=")
                    && !$0.hasPrefix("export MOONSHOT_API_KEY=")
                    && !$0.hasPrefix("export OPENAI_API_KEY=")
                    && !$0.hasPrefix("export GEMINI_API_KEY=")
                }
                .filter { !$0.isEmpty }
        }
        if !anthropic.isEmpty { lines.append("export ANTHROPIC_API_KEY=\"\(anthropic)\"") }
        if !moonshot.isEmpty  { lines.append("export MOONSHOT_API_KEY=\"\(moonshot)\"")  }
        if !openAI.isEmpty    { lines.append("export OPENAI_API_KEY=\"\(openAI)\"") }
        if !gemini.isEmpty    { lines.append("export GEMINI_API_KEY=\"\(gemini)\"") }

        let content = lines.joined(separator: "\n") + "\n"
        try? content.write(toFile: envFile, atomically: true, encoding: .utf8)
        reload()
    }

    func clear(_ key: String) {
        guard let existing = try? String(contentsOfFile: envFile, encoding: .utf8) else { return }
        let lines = existing.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("export \(key)=") }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: envFile, atomically: true, encoding: .utf8)
        reload()
    }
}

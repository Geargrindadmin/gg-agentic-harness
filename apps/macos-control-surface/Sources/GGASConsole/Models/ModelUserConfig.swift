// ModelUserConfig.swift — Per-model user configuration.
// Persisted to ~/.ggas/model-configs.json.

import Foundation
import SwiftUI

// MARK: - Config model

struct ModelUserConfig: Codable, Identifiable {
    var id: String                          // LM Studio model id (primary key)
    var alias: String = ""                  // friendly name override; empty = use model id
    var temperature: Double = 0.3
    var maxTokens: Int = 2048
    var topP: Double = 0.95
    var contextWindowOverride: Int = 0      // 0 = use model default
    var systemPromptOverride: String = ""   // empty = use engine default
    var assignedCoordinatorId: String?      // UUID string; nil = unassigned
    var notes: String = ""
    var tags: [String] = []
    var isFavorite: Bool = false
    var lastUsedAt: Date?

    /// Returns alias if set, otherwise the short segment of the model id.
    var displayName: String {
        alias.isEmpty
            ? (id.components(separatedBy: "/").last ?? id)
            : alias
    }
}

// MARK: - Store

@MainActor
final class ModelUserConfigStore: ObservableObject {
    static let shared = ModelUserConfigStore()

    @Published private(set) var configs: [String: ModelUserConfig] = [:]

    private let storePath = URL(fileURLWithPath:
        NSHomeDirectory() + "/.ggas/model-configs.json")

    private init() { load() }

    // MARK: - CRUD

    func config(for modelId: String) -> ModelUserConfig {
        configs[modelId] ?? ModelUserConfig(id: modelId)
    }

    func save(_ config: ModelUserConfig) {
        configs[config.id] = config
        persist()
    }

    func touch(modelId: String) {
        var c = config(for: modelId)
        c.lastUsedAt = Date()
        save(c)
    }

    func setFavorite(modelId: String, _ value: Bool) {
        var c = config(for: modelId)
        c.isFavorite = value
        save(c)
    }

    func assignCoordinator(modelId: String, coordinatorId: UUID?) {
        var c = config(for: modelId)
        c.assignedCoordinatorId = coordinatorId?.uuidString
        save(c)
    }

    func delete(modelId: String) {
        configs.removeValue(forKey: modelId)
        persist()
    }

    var favorites: [ModelUserConfig] {
        configs.values.filter(\.isFavorite).sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
    }

    var recentlyUsed: [ModelUserConfig] {
        configs.values
            .filter { $0.lastUsedAt != nil }
            .sorted { $0.lastUsedAt! > $1.lastUsedAt! }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storePath),
              let decoded = try? JSONDecoder().decode([String: ModelUserConfig].self, from: data)
        else { return }
        configs = decoded
    }

    private func persist() {
        try? FileManager.default.createDirectory(
            at: storePath.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(configs) else { return }
        try? data.write(to: storePath, options: .atomic)
    }
}

// MARK: - Config Drawer View

/// Embeddable config panel for a single model.
struct ModelConfigDrawer: View {
    let modelId: String
    @State private var config: ModelUserConfig
    @ObservedObject private var store = ModelUserConfigStore.shared
    @ObservedObject private var coordMgr = CoordinatorManager.shared

    init(modelId: String) {
        self.modelId = modelId
        _config = State(initialValue: ModelUserConfigStore.shared.config(for: modelId))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ── Identity ─────────────────────────────────────────────
                section("Identity") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Alias", systemImage: "tag").font(.caption).foregroundStyle(.secondary)
                        TextField("Friendly name (optional)", text: $config.alias)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))

                        if !config.alias.isEmpty {
                            Text("Will appear as \"\(config.alias)\" throughout the app.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Toggle("Favorite", isOn: $config.isFavorite)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                        }

                        Label("Notes", systemImage: "note.text").font(.caption).foregroundStyle(.secondary)
                        CommandTextEditor(
                            text: $config.notes,
                            placeholder: "Notes about this model"
                        )
                            .frame(height: 60)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))

                        Label("Tags (comma-separated)", systemImage: "tag.stack")
                            .font(.caption).foregroundStyle(.secondary)
                        TextField("swift, coding, local", text: Binding(
                            get: { config.tags.joined(separator: ", ") },
                            set: { config.tags = $0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    }
                }

                // ── Inference Parameters ─────────────────────────────────
                section("Inference Parameters") {
                    VStack(alignment: .leading, spacing: 10) {
                        paramSlider("Temperature", value: $config.temperature,
                                    in: 0...2, format: "%.2f",
                                    help: "Higher = more creative, lower = more deterministic")
                        paramSlider("Top-P", value: $config.topP,
                                    in: 0...1, format: "%.2f",
                                    help: "Nucleus sampling threshold")

                        HStack {
                            Label("Max Tokens", systemImage: "number").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Stepper("\(config.maxTokens)",
                                    value: $config.maxTokens,
                                    in: 256...32768,
                                    step: 256)
                            .font(.system(size: 11))
                        }

                        HStack {
                            Label("Context Window Override", systemImage: "arrow.left.and.right")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Stepper(config.contextWindowOverride == 0
                                    ? "Model default"
                                    : "\(config.contextWindowOverride / 1024)K",
                                    value: $config.contextWindowOverride,
                                    in: 0...131072,
                                    step: 4096)
                            .font(.system(size: 11))
                        }
                    }
                }

                // ── System Prompt ────────────────────────────────────────
                section("System Prompt Override") {
                    CommandTextEditor(
                        text: $config.systemPromptOverride,
                        placeholder: "Override the default system prompt for this model"
                    )
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.3)))
                    Text("Leave empty to use the default GGAS coordinator prompt.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }

                // ── Coordinator Assignment ───────────────────────────────
                section("Coordinator Assignment") {
                    Picker("Assign to coordinator", selection: Binding(
                        get: { config.assignedCoordinatorId },
                        set: { config.assignedCoordinatorId = $0 }
                    )) {
                        Text("None (manual selection)").tag(String?.none)
                        ForEach(coordMgr.coordinators) { coord in
                            Text(coord.label).tag(String?.some(coord.id.uuidString))
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 12))

                    if config.assignedCoordinatorId != nil {
                        Text("This model will be automatically selected when the assigned coordinator is active.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }

                // ── Save ─────────────────────────────────────────────────
                Button(action: saveConfig) {
                    Label("Save Configuration", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(16)
        }
    }

    // MARK: - Helpers

    private func saveConfig() {
        store.save(config)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.10)))
    }

    @ViewBuilder
    private func paramSlider(_ label: String, value: Binding<Double>,
                              in range: ClosedRange<Double>, format: String,
                              help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(label, systemImage: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            Slider(value: value, in: range)
            Text(help).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}

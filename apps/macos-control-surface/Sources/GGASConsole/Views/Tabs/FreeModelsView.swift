import SwiftUI
import AppKit

struct FreeModelsView: View {
    @EnvironmentObject private var shell: AppShellState
    @State private var catalog: FreeModelsCatalogModel?
    @State private var filter = ""
    @State private var isLoading = false
    @State private var error: String?

    private var filteredProviders: [FreeModelProviderModel] {
        guard let catalog else { return [] }
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return catalog.providers }
        return catalog.providers.compactMap { provider in
            let models = provider.models.filter {
                $0.label.localizedCaseInsensitiveContains(trimmed)
                    || $0.id.localizedCaseInsensitiveContains(trimmed)
                    || provider.name.localizedCaseInsensitiveContains(trimmed)
            }
            guard !models.isEmpty || provider.name.localizedCaseInsensitiveContains(trimmed) else {
                return nil
            }
            return FreeModelProviderModel(
                key: provider.key,
                name: provider.name,
                signupUrl: provider.signupUrl,
                modelCount: models.isEmpty ? provider.modelCount : models.count,
                tiers: provider.tiers,
                models: models.isEmpty ? provider.models : models
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let catalog {
                        summary(catalog)
                        ForEach(filteredProviders) { provider in
                            providerSection(provider)
                        }
                    } else if isLoading {
                        ProgressView("Loading free model catalog…")
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ContentUnavailableView(
                            "Free Models Unavailable",
                            systemImage: "globe.americas",
                            description: Text(error ?? "The free model catalog could not be loaded.")
                        )
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Free Models")
        .task {
            await refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free Coding Models")
                        .font(.headline.bold())
                    Text("Track free provider offerings and jump directly into LM Studio search for models that look useful.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                }
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            AppTextField(
                text: $filter,
                placeholder: "Filter providers or models",
                font: .systemFont(ofSize: 12)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(16)
        .background(.bar)
    }

    private func summary(_ catalog: FreeModelsCatalogModel) -> some View {
        HStack(spacing: 16) {
            summaryChip("Providers", value: "\(catalog.totalProviders)")
            summaryChip("Models", value: "\(catalog.totalModels)")
            summaryChip("Filtered", value: "\(filteredProviders.reduce(0) { $0 + $1.models.count })")
        }
    }

    private func providerSection(_ provider: FreeModelProviderModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(provider.modelCount) model\(provider.modelCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Provider") {
                    if let url = URL(string: provider.signupUrl) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            }

            FlowLayout(spacing: 6) {
                ForEach(provider.tiers, id: \.self) { tier in
                    Text(tier)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }

            ForEach(provider.models.prefix(8)) { model in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.label)
                            .font(.system(size: 12, weight: .medium))
                        Text("\(model.id) • SWE: \(model.sweScore) • Context: \(model.context)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Find in LM Studio") {
                        shell.openLMStudioCatalog(query: model.label)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }

            if provider.models.count > 8 {
                Text("+ \(provider.models.count - 8) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func summaryChip(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
        )
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            catalog = try await A2AClient.shared.fetchFreeModelsCatalog()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

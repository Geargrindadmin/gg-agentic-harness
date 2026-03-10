import SwiftUI
import AppKit

struct FreeModelsView: View {
    @EnvironmentObject private var shell: AppShellState
    @State private var catalog: FreeModelsCatalogModel?
    @State private var fitSnapshot: ModelFitSnapshotModel?
    @State private var filter = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var pendingLaunchDecision: FreeModelLaunchDecision?

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
        .confirmationDialog(
            pendingLaunchDecision?.title ?? "Model Fit Warning",
            isPresented: Binding(
                get: { pendingLaunchDecision != nil },
                set: { if !$0 { pendingLaunchDecision = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingLaunchDecision {
                Button("Open in LLM Studio Anyway") {
                    shell.openLMStudioCatalog(query: pendingLaunchDecision.query, autoDownload: true)
                    self.pendingLaunchDecision = nil
                }
                Button("Open Model Fit") {
                    shell.selectTab(.modelFit)
                    self.pendingLaunchDecision = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingLaunchDecision = nil
            }
        } message: {
            Text(pendingLaunchDecision?.message ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free Coding Models")
                        .font(.headline.bold())
                    Text("Track free provider offerings and send promising models into LLM Studio with a local fit check before download.")
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
                modelRow(model)
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

    @ViewBuilder
    private func modelRow(_ model: FreeModelEntryModel) -> some View {
        let fitAssessment = assessFit(for: model)
        let actionButton = Button(fitAssessment.requiresConfirmation ? "Review Fit" : "Open in LLM Studio") {
            handleStudioLaunch(for: model, assessment: fitAssessment)
        }
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.label)
                    .font(.system(size: 12, weight: .medium))
                Text("\(model.id) • SWE: \(model.sweScore) • Context: \(model.context)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(fitAssessment.summary)
                    .font(.caption2)
                    .foregroundStyle(fitAssessment.color)
            }
            Spacer()
            fitBadge(fitAssessment)
            if fitAssessment.requiresConfirmation {
                actionButton
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                actionButton
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
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

    @ViewBuilder
    private func fitBadge(_ assessment: FreeModelFitAssessment) -> some View {
        Text(assessment.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(assessment.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(assessment.color.opacity(0.10), in: Capsule())
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let catalogTask = A2AClient.shared.fetchFreeModelsCatalog()
            async let fitTask = A2AClient.shared.fetchModelFitRecommendations(limit: 24)
            catalog = try await catalogTask
            fitSnapshot = try? await fitTask
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handleStudioLaunch(for model: FreeModelEntryModel, assessment: FreeModelFitAssessment) {
        let launchQuery = bestFitRecommendation(for: model)?.lmStudioQuery ?? model.label
        if assessment.requiresConfirmation {
            pendingLaunchDecision = FreeModelLaunchDecision(
                title: "Model Fit Review",
                query: launchQuery,
                message: assessment.warningMessage
            )
        } else {
            shell.openLMStudioCatalog(query: launchQuery, autoDownload: true)
        }
    }

    private func assessFit(for model: FreeModelEntryModel) -> FreeModelFitAssessment {
        if let recommendation = bestFitRecommendation(for: model) {
            let fitLevel = recommendation.fitLevel.lowercased()
            let summary = "\(recommendation.shortName) • \(recommendation.fitLevel.capitalized) fit • \(String(format: "%.1f", recommendation.memoryRequiredGb)) GB needed / \(String(format: "%.1f", recommendation.memoryAvailableGb)) GB available"
            if ["excellent", "great", "good", "okay"].contains(fitLevel) {
                return FreeModelFitAssessment(
                    label: recommendation.fitLevel.capitalized,
                    summary: summary,
                    color: fitLevel == "okay" ? .orange : .green,
                    requiresConfirmation: false,
                    warningMessage: summary
                )
            }
            return FreeModelFitAssessment(
                label: "Review Fit",
                summary: summary,
                color: .orange,
                requiresConfirmation: true,
                warningMessage: "\(summary)\n\nIf you are planning to split this model across multiple Firewire or networked machines, hold off on the local download for now. Multi-machine split loading is planned for a later release."
            )
        }

        return FreeModelFitAssessment(
            label: "Unverified",
            summary: "No local llmfit recommendation yet. Review the fit before downloading in LLM Studio.",
            color: .secondary,
            requiresConfirmation: true,
            warningMessage: "This model is not currently matched to a local llmfit recommendation on this machine.\n\nOpen Model Fit if you want to review local hardware guidance first. Multi-machine split loading over Firewire/networked machines is planned for a later release."
        )
    }

    private func bestFitRecommendation(for model: FreeModelEntryModel) -> ModelFitRecommendationModel? {
        guard let fitSnapshot else { return nil }
        let modelTokens = normalizedSearchTokens([model.label, model.id])
        return fitSnapshot.recommendations.first(where: { recommendation in
            let recTokens = normalizedSearchTokens([recommendation.name, recommendation.shortName, recommendation.lmStudioQuery])
            return !modelTokens.isDisjoint(with: recTokens)
        })
    }

    private func normalizedSearchTokens(_ values: [String]) -> Set<String> {
        var tokens = Set<String>()
        for value in values {
            let normalized = value.lowercased()
                .replacingOccurrences(of: "/", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
            for token in normalized.split(separator: " ") where token.count >= 3 {
                tokens.insert(String(token))
            }
        }
        return tokens
    }
}

private struct FreeModelLaunchDecision: Identifiable {
    let title: String
    let query: String
    let message: String

    var id: String { query }
}

private struct FreeModelFitAssessment {
    let label: String
    let summary: String
    let color: Color
    let requiresConfirmation: Bool
    let warningMessage: String
}

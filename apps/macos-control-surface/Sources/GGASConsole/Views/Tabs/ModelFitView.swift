import SwiftUI

struct ModelFitView: View {
    @EnvironmentObject private var shell: AppShellState
    @State private var snapshot: ModelFitSnapshotModel?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let snapshot {
                        systemSummary(snapshot)
                        recommendationsList(snapshot)
                    } else if isLoading {
                        ProgressView("Analyzing local hardware fit…")
                            .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ContentUnavailableView(
                            "Model Fit Unavailable",
                            systemImage: "slider.horizontal.below.rectangle",
                            description: Text(error ?? "Install `llmfit` to evaluate which local models fit this machine.")
                        )
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Model Fit")
        .task {
            await refresh()
        }
        .alert("Model Fit Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Fit")
                    .font(.headline.bold())
                Text("Use local hardware fit analysis to decide which coding models belong in LLM Studio and which coordinator/runtime path makes sense.")
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
        .padding(16)
        .background(.bar)
    }

    private func systemSummary(_ snapshot: ModelFitSnapshotModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("System Summary")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if let binaryPath = snapshot.binaryPath {
                    Text(binaryPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            let system = snapshot.system
            HStack(spacing: 16) {
                metricCard("Available RAM", value: formatted(system?.availableRamGb, suffix: "GB"))
                metricCard("GPU", value: gpuLabel(system))
                metricCard("Cores", value: system?.cpuCores.map(String.init) ?? "—")
                metricCard("Backend", value: system?.backend ?? "—")
            }

            if let error = snapshot.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func recommendationsList(_ snapshot: ModelFitSnapshotModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recommended Coding Models")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(snapshot.recommendations.count) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(snapshot.recommendations) { recommendation in
                recommendationRow(recommendation)
            }
        }
    }

    private func recommendationRow(_ recommendation: ModelFitRecommendationModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.shortName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(recommendation.name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(recommendation.fitLevel.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(fitColor(recommendation.fitLevel).opacity(0.12), in: Capsule())
                    .foregroundStyle(fitColor(recommendation.fitLevel))
            }

            HStack(spacing: 16) {
                metricCard("Score", value: String(format: "%.0f", recommendation.score))
                metricCard("Runtime", value: recommendation.runtimeLabel.isEmpty ? recommendation.runtime : recommendation.runtimeLabel)
                metricCard("Best Quant", value: recommendation.bestQuant)
                metricCard("Context", value: "\(recommendation.contextLength / 1024)K")
                metricCard("TPS", value: recommendation.estimatedTps > 0 ? String(format: "%.1f", recommendation.estimatedTps) : "—")
            }

            if !recommendation.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(recommendation.notes, id: \.self) { note in
                        Text("• \(note)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Find in LLM Studio") {
                    shell.openLMStudioCatalog(query: recommendation.lmStudioQuery)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Text("LLM Studio query: \(recommendation.lmStudioQuery)")
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

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fitColor(_ fitLevel: String) -> Color {
        switch fitLevel.lowercased() {
        case "excellent", "great", "good":
            return .green
        case "okay", "limited":
            return .orange
        default:
            return .secondary
        }
    }

    private func formatted(_ value: Double?, suffix: String) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f %@", value, suffix)
    }

    private func gpuLabel(_ system: ModelFitSystemModel?) -> String {
        guard let system else { return "—" }
        if let name = system.gpuName, !name.isEmpty {
            if let vram = system.gpuVramGb {
                return "\(name) • \(String(format: "%.1f GB", vram))"
            }
            return name
        }
        return (system.hasGpu ?? false) ? "Available" : "None"
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            snapshot = try await A2AClient.shared.fetchModelFitRecommendations(limit: 14)
            error = snapshot?.error
        } catch {
            self.error = error.localizedDescription
        }
    }
}

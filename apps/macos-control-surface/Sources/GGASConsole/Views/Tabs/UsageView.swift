import SwiftUI

private func usageColor(_ name: String) -> Color {
    switch name {
    case "green": return .green
    case "orange": return .orange
    case "red": return .red
    case "blue": return .blue
    case "purple": return .purple
    default: return .secondary
    }
}

struct UsageView: View {
    @State private var snapshot: UsageSnapshotModel?
    @State private var governor: GovernorStatus?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let governor {
                    governorCard(governor)
                }

                if let snapshot {
                    if snapshot.providers.isEmpty {
                        emptyState("No provider usage data is available yet.")
                    } else {
                        ForEach(snapshot.providers) { provider in
                            UsageProviderCard(provider: provider)
                        }
                    }
                } else if loading {
                    ProgressView("Loading usage…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    emptyState(error ?? "Usage data has not been loaded yet.")
                }
            }
            .padding(16)
        }
        .navigationTitle("Usage")
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Provider Usage")
                    .font(.headline.bold())
                Text("Harness-native provider probes inspired by OpenUsage, without vendoring upstream code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading)
        }
    }

    private func governorCard(_ governor: GovernorStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Harness Capacity", systemImage: "memorychip.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Agents \(governor.activeWorkers)/\(governor.allowedAgents)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(governor.activeWorkers), total: Double(max(governor.allowedAgents, 1)))

            HStack(spacing: 14) {
                UsageMetricChip(label: "Available RAM", value: String(format: "%.1f GB", governor.availableRamGb), color: .blue)
                UsageMetricChip(label: "CPU Pressure", value: String(format: "%.0f%%", governor.cpuPressure), color: governor.cpuPaused ? .red : .green)
                UsageMetricChip(label: "Queue", value: "\(governor.queuedWorkers)", color: .orange)
            }

            Text(governor.note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
        )
    }

    private func emptyState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Usage unavailable", systemImage: "gauge.with.dots.needle.67percent")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            async let usageTask = A2AClient.shared.fetchUsageSnapshot()
            async let governorTask = A2AClient.shared.fetchGovernorStatus()
            snapshot = try await usageTask
            governor = try await governorTask
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct UsageProviderCard: View {
    let provider: UsageProviderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name)
                        .font(.title3.weight(.semibold))
                    Text(provider.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let plan = provider.plan, !plan.isEmpty {
                        Text(plan)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                Spacer()
                Text(provider.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(usageColor(provider.statusColor).opacity(0.14), in: Capsule())
                    .foregroundStyle(usageColor(provider.statusColor))
            }

            if !provider.windows.isEmpty {
                VStack(spacing: 10) {
                    ForEach(provider.windows) { window in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(window.label)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(String(format: "%.1f%%", window.usedPercent))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: window.usedPercent, total: 100)
                            Text(window.detail + resetSuffix(window.resetAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let credits = provider.credits {
                HStack(spacing: 12) {
                    UsageMetricChip(label: credits.label, value: creditValue(credits), color: .purple)
                }
            }

            if let source = provider.source, !source.isEmpty {
                Text(source)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }

            if let error = provider.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(usageColor(provider.statusColor).opacity(0.16), lineWidth: 1)
        )
    }

    private func creditValue(_ credits: UsageProviderCreditModel) -> String {
        if let limit = credits.limit, limit > 0 {
            return String(format: "%.2f / %.2f %@", credits.balance, limit, credits.unit)
        }
        return String(format: "%.2f %@", credits.balance, credits.unit)
    }

    private func resetSuffix(_ resetAt: String?) -> String {
        guard let resetAt, !resetAt.isEmpty else { return "" }
        return " • resets \(resetAt)"
    }
}

private struct UsageMetricChip: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

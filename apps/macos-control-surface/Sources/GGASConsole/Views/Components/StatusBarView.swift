// StatusBarView.swift — Bottom status bar: CPU, RAM, GPU, Network
// Displayed across all tabs

import SwiftUI

struct StatusBarView: View {
    @StateObject private var svc = SystemMetricsService.shared
    @StateObject private var usage = UsageStatusService.shared

    var body: some View {
        HStack(spacing: 0) {
            chip(icon: "cpu.fill",          label: cpuLabel,     value: svc.metrics.cpuPct / 100, color: metricColor(svc.metrics.cpuPct))
            divider()
            chip(icon: "memorychip.fill",   label: ramLabel,     value: ramFraction,               color: metricColor(ramFraction * 100))
            divider()
            chip(icon: "square.3.layers.3d.fill", label: gpuLabel, value: svc.metrics.gpuPct / 100, color: metricColor(svc.metrics.gpuPct))
            divider()
            netChip()
            Spacer()
            ForEach(usage.providerChips.prefix(3)) { chip in
                divider()
                providerUsageChip(chip)
            }
        }
        .frame(height: 22)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
        .task {
            svc.start()
            usage.start()
        }
    }

    // MARK: – Labels

    private var cpuLabel: String {
        String(format: "CPU %.0f%%", svc.metrics.cpuPct)
    }

    private var ramLabel: String {
        String(format: "RAM %.1f/%.0fGB", svc.metrics.ramUsedGB, svc.metrics.ramTotalGB)
    }

    private var gpuLabel: String {
        svc.metrics.gpuPct > 0
            ? String(format: "GPU %.0f%%", svc.metrics.gpuPct)
            : "GPU –"
    }

    private var ramFraction: Double {
        guard svc.metrics.ramTotalGB > 0 else { return 0 }
        return svc.metrics.ramUsedGB / svc.metrics.ramTotalGB
    }

    // MARK: – Sub-views

    private func chip(icon: String, label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.primary)
            MiniBar(fraction: value, color: color)
                .frame(width: 28, height: 4)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func netChip() -> some View {
        let inLabel  = formatKBs(svc.metrics.netInKBs)
        let outLabel = formatKBs(svc.metrics.netOutKBs)
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.cyan)
            Text(inLabel)
                .font(.system(size: 9.5, design: .monospaced))
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(.mint)
            Text(outLabel)
                .font(.system(size: 9.5, design: .monospaced))
        }
        .padding(.horizontal, 8)
    }

    private func divider() -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 14)
    }

    @ViewBuilder
    private func providerUsageChip(_ chip: ProviderUsageChip) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(chip.color)
                .frame(width: 7, height: 7)
            Text(chip.label)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.primary)
            if let reset = chip.resetLabel {
                Text(reset)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: – Helpers

    private func metricColor(_ pct: Double) -> Color {
        switch pct {
        case ..<50:  return .green
        case ..<80:  return .orange
        default:     return .red
        }
    }

    private func formatKBs(_ kbs: Double) -> String {
        if kbs > 1_000_000 { return String(format: "%.1f GB/s", kbs / 1_048_576) }
        if kbs > 1_000     { return String(format: "%.1f MB/s", kbs / 1_024) }
        return String(format: "%.0f KB/s", kbs)
    }
}

@MainActor
final class UsageStatusService: ObservableObject {
    static let shared = UsageStatusService()

    @Published private(set) var snapshot: UsageSnapshotModel?

    private var pollingTask: Task<Void, Never>?

    var providerChips: [ProviderUsageChip] {
        guard let snapshot else {
            return [
                ProviderUsageChip(id: "usage-loading", label: "Models loading", resetLabel: nil, color: .secondary)
            ]
        }
        return snapshot.providers.compactMap { provider in
            guard let window = provider.windows.first else { return nil }
            return ProviderUsageChip(
                id: provider.id + ":" + window.id,
                label: "\(shortProviderName(provider.name)) \(Int(window.usedPercent.rounded()))%",
                resetLabel: relativeReset(window.resetAt),
                color: usageStatusColor(provider.statusColor)
            )
        }
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func refresh() async {
        snapshot = try? await A2AClient.shared.fetchUsageSnapshot()
    }

    private func relativeReset(_ resetAt: String?) -> String? {
        guard
            let resetAt,
            let date = ISO8601DateFormatter().date(from: resetAt)
        else {
            return nil
        }

        let interval = max(0, date.timeIntervalSinceNow)
        if interval < 60 {
            return "soon"
        }
        if interval < 3600 {
            return "\(Int(interval / 60))m"
        }
        if interval < 86_400 {
            return "\(Int(interval / 3600))h"
        }
        return "\(Int(interval / 86_400))d"
    }

    private func usageStatusColor(_ status: String) -> Color {
        switch status {
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "blue": return .blue
        case "purple": return .purple
        default: return .secondary
        }
    }

    private func shortProviderName(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("Claude") { return "Claude" }
        if name.localizedCaseInsensitiveContains("Codex") { return "Codex" }
        if name.localizedCaseInsensitiveContains("Kimi") { return "Kimi" }
        if name.localizedCaseInsensitiveContains("Gemini") { return "Gemini" }
        return name
    }
}

struct ProviderUsageChip: Identifiable {
    let id: String
    let label: String
    let resetLabel: String?
    let color: Color
}

// MARK: – Mini progress bar

struct MiniBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.1))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.85))
                    .frame(width: geo.size.width * CGFloat(min(fraction, 1)))
            }
        }
    }
}

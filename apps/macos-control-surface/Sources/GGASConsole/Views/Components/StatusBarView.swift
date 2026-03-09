// StatusBarView.swift — Bottom status bar: CPU, RAM, GPU, Network
// Displayed across all tabs

import SwiftUI

struct StatusBarView: View {
    @StateObject private var svc = SystemMetricsService.shared

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
        }
        .frame(height: 22)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
        .task { svc.start() }
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

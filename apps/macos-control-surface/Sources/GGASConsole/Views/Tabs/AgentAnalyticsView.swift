import SwiftUI
import Charts

struct AgentAnalyticsView: View {
    @State private var summary: AgentAnalyticsSummary?
    @State private var coordinators: [AgentAnalyticsMetric] = []
    @State private var workerRuntimes: [AgentAnalyticsMetric] = []
    @State private var personas: [AgentAnalyticsMetric] = []
    @State private var roles: [AgentAnalyticsMetric] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let summary {
                    summaryCards(summary)
                }

                analyticsSection(
                    title: "Coordinator Runtime Usage",
                    color: .blue,
                    metrics: coordinators
                )

                analyticsSection(
                    title: "Sub-Agent Runtime Usage",
                    color: .green,
                    metrics: workerRuntimes
                )

                analyticsSection(
                    title: "Persona Usage",
                    color: .purple,
                    metrics: personas
                )

                analyticsTable(
                    title: "Role Breakdown",
                    metrics: roles
                )
            }
            .padding()
        }
        .overlay {
            if loading {
                ProgressView()
            }
        }
        .navigationTitle("Agent Analytics")
        .task { await load() }
    }

    private func summaryCards(_ summary: AgentAnalyticsSummary) -> some View {
        HStack(spacing: 12) {
            metricCard("Runs", "\(summary.totalRuns)", .blue)
            metricCard("Workers", "\(summary.totalWorkers)", .green)
            metricCard("Active", "\(summary.activeWorkers)", .orange)
            metricCard("Failed", "\(summary.failedWorkers)", .red)
            metricCard("Personas", "\(summary.distinctPersonas)", .purple)
            metricCard("Runtimes", "\(summary.distinctRuntimes)", .secondary)
        }
    }

    private func metricCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    private func analyticsSection(title: String, color: Color, metrics: [AgentAnalyticsMetric]) -> some View {
        GroupBox(title) {
            if metrics.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Chart(metrics.prefix(8)) { metric in
                        BarMark(
                            x: .value("Metric", metric.label),
                            y: .value("Calls", metric.calls)
                        )
                        .foregroundStyle(color.gradient)
                    }
                    .frame(height: 220)

                    analyticsTable(title: "Details", metrics: metrics)
                }
                .padding(.top, 8)
            }
        }
    }

    private func analyticsTable(title: String, metrics: [AgentAnalyticsMetric]) -> some View {
        GroupBox(title) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text("Name").bold()
                    Text("Calls").bold()
                    Text("Active").bold()
                    Text("Failed").bold()
                    Text("Avg ms").bold()
                }
                Divider()
                ForEach(metrics.prefix(12)) { metric in
                    GridRow {
                        Text(metric.label)
                            .font(.system(size: 12, design: .monospaced))
                        Text("\(metric.calls)")
                        Text("\(metric.active)")
                            .foregroundStyle(metric.active > 0 ? .orange : .secondary)
                        Text("\(metric.failures)")
                            .foregroundStyle(metric.failures > 0 ? .red : .secondary)
                        Text(metric.avgDurationMs.map { String(format: "%.0f", $0) } ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func load() async {
        defer { loading = false }
        guard let analytics = try? await A2AClient.shared.fetchAgentAnalytics() else {
            return
        }
        summary = analytics.summary
        coordinators = analytics.coordinators
        workerRuntimes = analytics.workerRuntimes
        personas = analytics.personas
        roles = analytics.roles
    }
}

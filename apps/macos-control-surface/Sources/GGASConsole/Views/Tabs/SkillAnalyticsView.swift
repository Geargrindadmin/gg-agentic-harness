// SkillAnalyticsView.swift — skill call stats

import SwiftUI
import Charts

struct SkillAnalyticsView: View {
    @State private var stats: [SkillStats] = []
    @State private var loading = true

    var sorted: [SkillStats] { stats.sorted { $0.calls > $1.calls } }

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if stats.isEmpty {
                VStack {
                    Image(systemName: "chart.bar.fill").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No skill data yet").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Bar chart: call count per skill
                        GroupBox("Call Count by Skill") {
                            Chart(sorted) { s in
                                BarMark(
                                    x: .value("Skill", abbreviate(s.skill)),
                                    y: .value("Calls", s.calls)
                                )
                                .foregroundStyle(Color.blue.gradient)
                            }
                            .frame(height: 220)
                            .padding(.top, 8)
                        }

                        // Table
                        GroupBox("Skill Details") {
                            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 4) {
                                GridRow {
                                    Text("Skill").bold()
                                    Text("Calls").bold()
                                    Text("Success").bold()
                                    Text("Fail").bold()
                                    Text("Avg ms").bold()
                                }
                                Divider()
                                ForEach(sorted, id: \.skill) { s in
                                    GridRow {
                                        Text(s.skill).font(.system(size: 12, design: .monospaced))
                                        Text("\(s.calls)").foregroundStyle(.blue)
                                        Text("\(s.calls - s.failures)").foregroundStyle(.green)
                                        Text("\(s.failures)").foregroundStyle(s.failures > 0 ? .red : .secondary)
                                        Text(s.avgDurationMs.map { String(format: "%.0f", $0) } ?? "—").foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 12))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Skill Analytics")
        .task { await load() }
    }

    private func load() async {
        if let s = try? await A2AClient.shared.fetchSkillStats() { stats = s }
        loading = false
    }

    private func abbreviate(_ name: String) -> String {
        name.replacingOccurrences(of: "gg-", with: "")
    }
}

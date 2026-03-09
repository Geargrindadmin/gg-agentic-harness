// TraceView.swift — JSONL agent execution trace

import SwiftUI
import AppKit

struct TraceView: View {
    @State private var runs: [AgentRun] = []
    @State private var selectedRunId: String?
    @State private var trace: [TraceEntry] = []
    @State private var loading = false
    @State private var providerFilter: String = "Any"
    @State private var coordinatorModelFilter: String = "Any"
    @State private var workerBackendFilter: String = "Any"
    @State private var workerModelFilter: String = "Any"

    var body: some View {
        HSplitView {
            // Run picker
            VStack(alignment: .leading, spacing: 0) {
                Text("Select Run").font(.caption).foregroundStyle(.secondary).padding(10)
                Divider()
                traceFilters
                Divider()
                List(filteredRuns, id: \.runId, selection: $selectedRunId) { run in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(run.task).lineLimit(2).font(.caption)
                        HStack {
                            StatusDot(status: run.status)
                            Text(run.runId.prefix(8)).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let provider = run.coordinatorProvider {
                            let coordinatorModel = run.coordinatorModel ?? run.model ?? "n/a"
                            Text("\(provider) · \(coordinatorModel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let backend = run.workerBackend {
                            let workerModel = run.workerModel ?? "n/a"
                            Text("\(backend) · \(workerModel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .frame(minWidth: 200, maxWidth: 260)

            // Trace timeline
            VStack(alignment: .leading, spacing: 0) {
                if let run = selectedRun {
                    TraceHeaderView(run: run)
                    Divider()
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if selectedRun == nil {
                    VStack {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("Select a run").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if trace.isEmpty {
                    VStack {
                        Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No trace data available").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(trace) { entry in
                                TraceRow(entry: entry)
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Trace")
        .task { await loadRuns() }
        .onChange(of: selectedRunId) { _, runId in
            if let runId { Task { await loadTrace(runId: runId) } }
        }
    }

    private func loadRuns() async {
        runs = (try? await A2AClient.shared.fetchRuns()) ?? []
    }

    private func loadTrace(runId: String) async {
        loading = true
        trace = (try? await A2AClient.shared.fetchTrace(runId: runId)) ?? []
        loading = false
    }

    private var filteredRuns: [AgentRun] {
        runs.filter { run in
            matchesFilter(run.coordinatorProvider, providerFilter) &&
            matchesFilter(run.coordinatorModel ?? run.model, coordinatorModelFilter) &&
            matchesFilter(run.workerBackend, workerBackendFilter) &&
            matchesFilter(run.workerModel, workerModelFilter)
        }
    }

    private var traceFilters: some View {
        HStack(spacing: 10) {
            Text("Filters:").font(.caption).foregroundStyle(.secondary)
            DropdownFilter(label: "Provider", options: traceProviderOptions, selection: $providerFilter)
            DropdownFilter(label: "Coordinator", options: traceCoordinatorModelOptions, selection: $coordinatorModelFilter)
            DropdownFilter(label: "Worker", options: traceWorkerBackendOptions, selection: $workerBackendFilter)
            DropdownFilter(label: "Worker model", options: traceWorkerModelOptions, selection: $workerModelFilter)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var selectedRun: AgentRun? {
        guard let id = selectedRunId else { return nil }
        return runs.first(where: { $0.runId == id })
    }

    private var traceProviderOptions: [String] {
        filterOptions(from: runs.map { $0.coordinatorProvider })
    }

    private var traceCoordinatorModelOptions: [String] {
        filterOptions(from: runs.map { $0.coordinatorModel ?? $0.model })
    }

    private var traceWorkerBackendOptions: [String] {
        filterOptions(from: runs.map { $0.workerBackend })
    }

    private var traceWorkerModelOptions: [String] {
        filterOptions(from: runs.map { $0.workerModel })
    }

    private func filterOptions(from values: [String?]) -> [String] {
        let unique = Set(values.compactMap { $0 })
        return ["Any"] + unique.sorted()
    }

    private func matchesFilter(_ value: String?, _ filter: String) -> Bool {
        filter == "Any" || value == filter
    }
}

struct TraceHeaderView: View {
    let run: AgentRun

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusDot(status: run.status)
                Text(run.task).font(.headline)
                Spacer()
                Text(run.startedAt.prefix(16)).font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Text(run.source).font(.caption2).foregroundStyle(.secondary)
                Text(run.mode).font(.caption2).foregroundStyle(.secondary)
            }
            RunMetadataBanner(run: run)
        }
        .padding(12)
        .background(.bar)
    }
}

struct TraceRow: View {
    let entry: TraceEntry
    var actionColor: Color {
        switch entry.action.lowercased() {
        case "write": return .blue
        case "read":  return .green
        case "exec":  return .orange
        default:      return .primary
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Circle().fill(actionColor).frame(width: 8, height: 8).padding(.top, 6)
                Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.agentId).font(.caption).bold()
                    Text("·").foregroundStyle(.secondary)
                    Text(entry.action.uppercased())
                        .font(.caption2).foregroundStyle(actionColor)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(actionColor.opacity(0.12)).cornerRadius(4)
                    Spacer()
                    Text(entry.timestamp.suffix(8)).font(.caption2).foregroundStyle(.tertiary)
                }
                if let target = entry.target {
                    Text(target).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if let summary = entry.summary {
                    Text(summary).font(.caption).lineLimit(3)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 12)
    }
}

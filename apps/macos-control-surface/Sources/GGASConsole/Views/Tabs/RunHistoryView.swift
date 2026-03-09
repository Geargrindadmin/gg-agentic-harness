// RunHistoryView.swift — mirrors the React RunHistory component

import SwiftUI
import AppKit

struct RunHistoryView: View {
    @State private var serverRuns: [AgentRun] = []
    @ObservedObject private var coordinator = CoordinatorManager.shared
    @State private var loading = true
    @State private var offline = false
    @State private var selected: AgentRun?
    @State private var providerFilter: String = "Any"
    @State private var coordinatorModelFilter: String = "Any"
    @State private var workerBackendFilter: String = "Any"
    @State private var workerModelFilter: String = "Any"

    // Merge local (LM Studio) + server runs, sorted by startedAt descending
    private var allRuns: [AgentRun] {
        let merged = coordinator.localRuns + serverRuns
        return merged.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        HSplitView {
            // Left: run list
            VStack(alignment: .leading, spacing: 0) {
                statsRow

                Divider()

                if loading && allRuns.isEmpty {
                    offlineOrLoading
                } else if offline && allRuns.isEmpty {
                    offlineOrLoading
                } else if allRuns.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        runFilters
                        Divider()
                        List(filteredRuns, selection: $selected) { run in
                            RunRow(run: run)
                        }
                    }
                }
            }
            .frame(minWidth: 380)

            // Right: log detail
            if let run = selected {
                RunDetailView(run: run)
            } else {
                Text("Select a run to view logs")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Run History")
        .task {
            await loadRuns()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await loadRuns()
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 24) {
            StatBadge(label: "Total",    value: allRuns.count,                                   color: .blue)
            StatBadge(label: "Running",  value: allRuns.filter { $0.status == .running }.count,  color: .yellow)
            StatBadge(label: "Complete", value: allRuns.filter { $0.status == .complete }.count, color: .green)
            StatBadge(label: "Failed",   value: allRuns.filter { $0.status == .failed }.count,   color: .red)
            Spacer()
            Button(action: { Task { await loadRuns() } }) {
                Image(systemName: "arrow.clockwise")
            }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var runFilters: some View {
        HStack(spacing: 12) {
            Text("Filters:").font(.caption).foregroundStyle(.secondary)
            DropdownFilter(label: "Provider", options: providerFilterOptions, selection: $providerFilter)
            DropdownFilter(label: "Coordinator", options: coordinatorModelFilterOptions, selection: $coordinatorModelFilter)
            DropdownFilter(label: "Worker", options: workerBackendFilterOptions, selection: $workerBackendFilter)
            DropdownFilter(label: "Worker model", options: workerModelFilterOptions, selection: $workerModelFilter)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var filteredRuns: [AgentRun] {
        allRuns.filter { run in
            matchesFilter(run.coordinatorProvider, providerFilter) &&
            matchesFilter(run.coordinatorModel ?? run.model, coordinatorModelFilter) &&
            matchesFilter(run.workerBackend, workerBackendFilter) &&
            matchesFilter(run.workerModel, workerModelFilter)
        }
    }

    private var providerFilterOptions: [String] {
        filterOptions(from: allRuns.map { $0.coordinatorProvider })
    }

    private var coordinatorModelFilterOptions: [String] {
        filterOptions(from: allRuns.map { $0.coordinatorModel ?? $0.model })
    }

    private var workerBackendFilterOptions: [String] {
        filterOptions(from: allRuns.map { $0.workerBackend })
    }

    private var workerModelFilterOptions: [String] {
        filterOptions(from: allRuns.map { $0.workerModel })
    }

    private func filterOptions(from values: [String?]) -> [String] {
        let unique = Set(values.compactMap { $0 })
        return ["Any"] + unique.sorted()
    }

    private func matchesFilter(_ value: String?, _ filter: String) -> Bool {
        filter == "Any" || value == filter
    }

    private var offlineOrLoading: some View {
        VStack(spacing: 10) {
            if offline {
                Image(systemName: "wifi.slash").font(.largeTitle).foregroundStyle(.secondary)
                Text("Backend offline").foregroundStyle(.secondary)
                Text("Start the harness control-plane on \(ProjectSettings.shared.normalizedControlPlaneBaseURL)").font(.caption).foregroundStyle(.tertiary)
                Text("LM Studio runs still appear above.").font(.caption2).foregroundStyle(.quaternary)
            } else {
                ProgressView("Connecting to backend…")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.largeTitle).foregroundStyle(.secondary)
            Text("No runs yet").foregroundStyle(.secondary)
            Text("Dispatch a command from the Control tab to create a run.")
                .font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadRuns() async {
        do {
            let fetched = try await A2AClient.shared.fetchRuns()
            serverRuns = fetched
            loading = false
            offline = false
        } catch {
            loading = false
            offline = serverRuns.isEmpty
        }
    }
}

struct RunRow: View {
    let run: AgentRun
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                StatusDot(status: run.status)
                Text(run.task).font(.body).lineLimit(1)
                Spacer()
                Text(run.durationFormatted).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(run.mode).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15)).cornerRadius(4)
                Text(run.source).font(.caption).foregroundStyle(.secondary)
                if let provider = run.coordinatorProvider {
                    Text(provider).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15)).cornerRadius(4)
                }
                if let model = run.coordinatorModel ?? run.model {
                    Text(model).font(.caption2).lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                if let backend = run.workerBackend {
                    Text(backend).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.15)).cornerRadius(4)
                }
                if let workerModel = run.workerModel {
                    Text(workerModel).font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                }
                Spacer()
                Text(run.startedAt.prefix(16)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RunDetailView: View {
    let run: AgentRun
    @State private var logs: [LogLine] = []
    @State private var polling: Task<Void, Never>?

    /// Local runs (LM Studio) have their log embedded in run.log — no A2A streaming needed
    private var isLocalRun: Bool { run.runId.hasPrefix("local-") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(run.task).font(.headline)
                    Text("Run ID: \(run.runId)").font(.caption2).foregroundStyle(.secondary)
                    RunMetadataBanner(run: run)
                }
                Spacer()
                if let pr = run.prUrl {
                    Link("View PR ↗", destination: URL(string: pr)!)
                        .font(.caption).buttonStyle(.borderless)
                }
            }
            .padding()
            .background(.bar)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logs) { line in
                            LogLineRow(line: line).id(line.id)
                        }
                    }.padding(8)
                }
                .onChange(of: logs.count) { _, _ in
                    if let last = logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .task { loadLogs() }
        .onChange(of: run.runId) { _, _ in
            polling?.cancel()
            loadLogs()
        }
        .onDisappear { polling?.cancel() }
    }

    private func loadLogs() {
        if isLocalRun {
            // Show embedded log directly — no server roundtrip needed
            logs = run.log.enumerated().map { idx, line in
                LogLine(id: "\(run.runId)-\(idx)", ts: run.startedAt,
                        level: line.hasPrefix("❌") ? "error" : "info",
                        msg: line, runId: run.runId)
            }
        } else {
            polling = A2AClient.shared.streamLogs(runId: run.runId) { lines in
                DispatchQueue.main.async { self.logs = lines }
            }
        }
    }
}

struct DropdownFilter: View {
    let label: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) { selection = option }
            }
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(selection).font(.caption).foregroundStyle(.primary)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
    }
}

struct RunMetadataBanner: View {
    let run: AgentRun

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(runDispatchSummary).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                MetadataChip(label: "Coordinator", value: run.coordinatorProvider ?? "n/a")
                MetadataChip(label: "Coord model", value: run.coordinatorModel ?? run.model ?? "n/a")
                MetadataChip(label: "Worker", value: run.workerBackend ?? "n/a")
                MetadataChip(label: "Worker model", value: run.workerModel ?? "n/a")
                if let path = run.dispatchPath {
                    MetadataChip(label: "Dispatch", value: path)
                }
            }
        }
    }

    private var runDispatchSummary: String {
        "Coordinator \(run.coordinator ?? "n/a") · Worker \(run.workerBackend ?? "n/a")"
    }
}

struct MetadataChip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 2) {
            Text("\(label):").font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption2).foregroundStyle(.primary)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(5)
    }
}

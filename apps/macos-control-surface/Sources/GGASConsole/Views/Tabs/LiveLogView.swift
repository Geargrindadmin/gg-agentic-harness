// LiveLogView.swift — real-time log stream

import SwiftUI

struct LiveLogView: View {
    @EnvironmentObject private var workflow: WorkflowContextStore
    @State private var logs: [LogLine] = []
    @State private var filterLevel = "all"
    @State private var searchText = ""
    @State private var polling: Task<Void, Never>?
    @State private var autoscroll = true

    private let levels = ["all", "info", "warn", "error", "debug"]

    private var filtered: [LogLine] {
        logs.filter { line in
            let levelOk = filterLevel == "all" || line.level.lowercased() == filterLevel
            let textOk = searchText.isEmpty || line.msg.localizedCaseInsensitiveContains(searchText)
            return levelOk && textOk
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            if logs.isEmpty {
                VStack {
                    ProgressView("Waiting for logs…")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(filtered) { line in
                                LogLineRow(line: line).id(line.id)
                            }
                        }
                        .padding(8)
                        .fontDesign(.monospaced)
                        .font(.system(size: 12))
                    }
                    .onChange(of: filtered.count) { _, _ in
                        if autoscroll, let last = filtered.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .navigationTitle("Live Log")
        .task {
            polling?.cancel()
            polling = A2AClient.shared.streamLogs(runId: workflow.selectedRunId) { lines in
                self.logs = lines
            }
        }
        .task(id: workflow.selectedRunId) {
            polling?.cancel()
            polling = A2AClient.shared.streamLogs(runId: workflow.selectedRunId) { lines in
                self.logs = lines
            }
        }
        .onDisappear { polling?.cancel() }
    }

    private var toolbar: some View {
        HStack {
            Picker("Level", selection: $filterLevel) {
                ForEach(levels, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)

            SearchField(text: $searchText, placeholder: "Filter logs…")

            Spacer()

            if let runId = workflow.selectedRunId, !runId.isEmpty {
                Text(String(runId.prefix(12)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $autoscroll) { Text("Auto-scroll") }.toggleStyle(.switch)

            Button("Clear") { logs = [] }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            AppTextField(text: $text, placeholder: placeholder)
                .frame(height: 20)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1)).cornerRadius(6)
        .frame(maxWidth: 240)
    }
}

struct LogLineRow: View {
    let line: LogLine
    var levelColor: Color {
        switch line.level.lowercased() {
        case "error": return .red
        case "warn":  return .orange
        case "debug": return .secondary
        default:      return .primary
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(String(line.ts.suffix(12))).foregroundStyle(.tertiary).frame(width: 90, alignment: .leading)
            Text(runLabel).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
            Text(line.level.uppercased()).foregroundStyle(levelColor).frame(width: 42, alignment: .leading)
            Text(line.msg).foregroundStyle(levelColor).textSelection(.enabled)
            Spacer()
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
    }

    private var runLabel: String {
        guard let runId = line.runId, !runId.isEmpty else { return "—" }
        return String(runId.prefix(12))
    }
}

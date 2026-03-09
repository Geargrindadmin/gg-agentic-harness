import SwiftUI
import AppKit

struct ReplaysView: View {
    @State private var sources: [ReplaySourceModel] = []
    @State private var sessions: [ReplaySessionModel] = []
    @State private var filter = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var renderingSessionId: String?

    private var filteredSessions: [ReplaySessionModel] {
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.localizedCaseInsensitiveContains(trimmed)
                || session.path.localizedCaseInsensitiveContains(trimmed)
                || session.source.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sourcesSidebar
                Divider()
                sessionsList
            }
        }
        .navigationTitle("Replays")
        .task {
            await refresh()
        }
        .alert("Replay Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conversation Replays")
                        .font(.headline.bold())
                    Text("Re-open Claude Code and Cursor transcript sessions and render them into readable replay pages.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                AppTextField(
                    text: $filter,
                    placeholder: "Filter sessions by title, path, or source",
                    font: .systemFont(ofSize: 12)
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )

                Text("\(filteredSessions.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.bar)
    }

    private var sourcesSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(source.available ? Color.green : Color.secondary.opacity(0.45))
                            .frame(width: 8, height: 8)
                        Text(source.label)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }

                    Text(source.root)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.06))
                )
            }

            Spacer()
        }
        .frame(minWidth: 250, idealWidth: 250, maxWidth: 250, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.35))
    }

    private var sessionsList: some View {
        Group {
            if filteredSessions.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No replay sessions",
                    systemImage: "movieclapper",
                    description: Text("No local transcript sessions were found in the supported roots.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredSessions) { session in
                            replayRow(session)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func replayRow(_ session: ReplaySessionModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(session.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(session.source.capitalized)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.10), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            HStack(spacing: 12) {
                metaPill(label: "Format", value: session.format.uppercased())
                metaPill(label: "Turns", value: "\(session.turnCount)")
                metaPill(label: "Updated", value: relativeDate(session.modifiedAt))
                metaPill(label: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(session.sizeBytes), countStyle: .file))
            }

            HStack(spacing: 8) {
                Button {
                    Task { await render(session) }
                } label: {
                    Label(renderingSessionId == session.id ? "Rendering…" : "Render & Open", systemImage: "play.rectangle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(renderingSessionId == session.id)

                Button("Open Transcript") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: session.path))
                }
                .buttonStyle(.bordered)
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

    private func metaPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let replaySources = A2AClient.shared.fetchReplaySources()
            async let replaySessions = A2AClient.shared.fetchReplaySessions(limit: 120)
            sources = try await replaySources
            sessions = try await replaySessions
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func render(_ session: ReplaySessionModel) async {
        renderingSessionId = session.id
        defer { renderingSessionId = nil }
        do {
            let replay = try await A2AClient.shared.renderReplay(path: session.path)
            NSWorkspace.shared.open(URL(fileURLWithPath: replay.outputPath))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func relativeDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

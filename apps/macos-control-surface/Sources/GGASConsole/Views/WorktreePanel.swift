// WorktreePanel.swift — Floating NSPanel showing a live agent worktree file tree.
// Tap any SwarmDotView → WorktreePanelController.open(agentId:path:) is called.

import AppKit
import SwiftUI

// MARK: - Data model

struct WorktreeFile: Identifiable, Decodable {
    var id: String { relativePath }
    let name: String
    let relativePath: String
    let size: Int
    let modifiedAt: String
    let isDir: Bool
    let depth: Int
    /// Absolute path — relativePath from the server is already an absolute path.
    var path: String { relativePath }
}

struct WorktreeInfo: Decodable {
    let path: String
    let files: [WorktreeFile]
    let totalFiles: Int
    let totalSize: Int
}

// MARK: - ViewModel

@MainActor
final class WorktreeViewModel: ObservableObject {
    @Published var files: [WorktreeFile] = []
    @Published var totalFiles = 0
    @Published var totalSize  = 0
    @Published var isLoading  = true
    @Published var error: String?

    let agentId: String
    let worktreePath: String

    private var pollTask: Task<Void, Never>?
    private let session: URLSession
    private let controlPlaneAPIBaseURL: String

    private static func makeDefaultSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 3
        cfg.timeoutIntervalForResource = 5
        return URLSession(configuration: cfg)
    }

    init(
        agentId: String,
        worktreePath: String,
        session: URLSession? = nil,
        controlPlaneAPIBaseURL: String? = nil,
        autoStart: Bool = true
    ) {
        self.agentId = agentId
        self.worktreePath = worktreePath
        self.session = session ?? WorktreeViewModel.makeDefaultSession()
        self.controlPlaneAPIBaseURL = controlPlaneAPIBaseURL ?? ProjectSettings.shared.controlPlaneAPIBaseURL
        if autoStart {
            startPolling()
        }
    }

    deinit { pollTask?.cancel() }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func refresh() async {
        let encodedPath = worktreePath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "\(controlPlaneAPIBaseURL)/worktree?path=\(encodedPath)") else { return }
        do {
            let (data, resp) = try await session.data(from: url)
            if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
                self.files      = []
                self.totalFiles = 0
                self.totalSize  = 0
                self.isLoading  = false
                self.error      = "Worktree not created yet"
                return
            }
            let info = try JSONDecoder.ggasDecoder.decode(WorktreeInfo.self, from: data)
            self.files      = info.files
            self.totalFiles = info.totalFiles
            self.totalSize  = info.totalSize
            self.isLoading  = false
            self.error      = nil
        } catch {
            if self.files.isEmpty { self.isLoading = false }
            self.error = error.localizedDescription
        }
    }
}

// MARK: - SwiftUI body

struct WorktreeView: View {
    @ObservedObject var vm: WorktreeViewModel

    private let now = Date()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if vm.isLoading {
                Spacer()
                ProgressView().padding()
                Spacer()
            } else if let err = vm.error {
                Spacer()
                if err.contains("not created") {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 36)).foregroundColor(.secondary.opacity(0.45))
                        Text("Worktree not created yet")
                            .font(.callout.weight(.medium)).foregroundColor(.secondary)
                        Text("The agent hasn't started writing files here")
                            .font(.caption).foregroundColor(.secondary.opacity(0.6))
                    }.padding()
                } else {
                    Text(err).foregroundColor(.red).font(.caption).padding()
                }
                Spacer()
            } else if vm.files.isEmpty {
                Spacer()
                Text("No files yet…").foregroundColor(.secondary).font(.callout).padding()
                Spacer()
            } else {
                fileList
            }
            statusBar
        }
        .frame(minWidth: 320, minHeight: 260)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: Sub-views

    private var headerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.0, green: 0.88, blue: 0.45))
                .frame(width: 8, height: 8)
            Text(vm.agentId)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
            Spacer()
            Text(vm.worktreePath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var fileList: some View {
        List(vm.files) { file in
            WorktreeFileRow(file: file)
                .listRowInsets(.init(top: 2, leading: fileLeadingPad(file), bottom: 2, trailing: 8))
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    // fileRow kept as no-op — rendering is now done by WorktreeFileRow struct below

    private var statusBar: some View {
        HStack {
            Text("\(vm.totalFiles) files")
            Text("•").foregroundColor(.secondary)
            Text(formatSize(vm.totalSize))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
    }

    // MARK: Helpers

    private func fileLeadingPad(_ file: WorktreeFile) -> CGFloat {
        8 + CGFloat(max(0, file.depth - 1)) * 14
    }

    private func ageSeconds(_ iso: String) -> Double {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return 9999 }
        return Date().timeIntervalSince(d)
    }

    private func ageDotColor(_ age: Double) -> Color {
        if age < 5   { return Color(red: 0.0, green: 0.88, blue: 0.45) } // vivid green = active
        if age < 30  { return Color(red: 0.2, green: 0.55, blue: 1.0)  } // blue = recent
        if age < 120 { return Color(white: 0.55)                        } // gray = cold
        return .clear
    }

    private func fileIcon(_ file: WorktreeFile) -> String {
        if file.isDir { return "folder" }
        let ext = (file.name as NSString).pathExtension.lowercased()
        switch ext {
        case "ts", "tsx": return "swift"
        case "json":      return "curlybraces"
        case "md":        return "doc.text"
        case "prisma":    return "cylinder"
        case "sql":       return "tablecells"
        case "env":       return "lock"
        case "sh":        return "terminal"
        case "png", "jpg", "webp": return "photo"
        default:          return "doc"
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024   { return "\(bytes)B" }
        if bytes < 1024*1024 { return String(format: "%.1fK", Double(bytes)/1024) }
        return String(format: "%.1fM", Double(bytes)/1024/1024)
    }

    private func formatAge(_ age: Double) -> String {
        if age < 5  { return "now" }
        if age < 60 { return "\(Int(age))s ago" }
        return "\(Int(age/60))m ago"
    }
}

// MARK: - Clickable file row

private struct WorktreeFileRow: View {
    let file: WorktreeFile
    @State private var hovered = false

    private var age: Double {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: file.modifiedAt) else { return 9999 }
        return Date().timeIntervalSince(d)
    }

    private func ageDotColor(_ a: Double) -> Color {
        if a < 5   { return Color(red: 0.0, green: 0.88, blue: 0.45) }
        if a < 30  { return Color(red: 0.2, green: 0.55, blue: 1.0) }
        if a < 120 { return Color(white: 0.55) }
        return .clear
    }

    private func fileIcon() -> String {
        if file.isDir { return "folder" }
        switch (file.name as NSString).pathExtension.lowercased() {
        case "ts", "tsx": return "swift"
        case "json":      return "curlybraces"
        case "md":        return "doc.text"
        case "sh":        return "terminal"
        case "png", "jpg", "webp": return "photo"
        case "env":       return "lock"
        default:          return "doc"
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024       { return "\(bytes)B" }
        if bytes < 1024*1024  { return String(format: "%.1fK", Double(bytes)/1024) }
        return String(format: "%.1fM", Double(bytes)/1024/1024)
    }

    private func formatAge(_ a: Double) -> String {
        if a < 5  { return "now" }
        if a < 60 { return "\(Int(a))s ago" }
        return "\(Int(a/60))m ago"
    }

    var body: some View {
        let a = age
        HStack(spacing: 6) {
            // Activity dot (hidden when old)
            Circle()
                .fill(ageDotColor(a))
                .frame(width: 5, height: 5)
                .opacity(a < 120 ? 1 : 0)

            // Icon
            Image(systemName: fileIcon())
                .font(.system(size: 10))
                .foregroundColor(file.isDir ? Color(red: 0.94, green: 0.72, blue: 0.18) : .secondary)

            // Name
            Text(file.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(hovered ? .primary : .primary.opacity(0.85))
                .lineLimit(1)

            Spacer()

            // Size (files only)
            if !file.isDir && file.size > 0 {
                Text(formatSize(file.size))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Age badge
            if a < 120 {
                Text(formatAge(a))
                    .font(.system(size: 9))
                    .foregroundColor(ageDotColor(a))
            }
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
        .background(hovered ? Color(white: 0.18) : Color.clear)
        .cornerRadius(3)
        .contentShape(Rectangle())
        .onHover { over in
            hovered = over
            if over { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            let url = URL(fileURLWithPath: file.path)
            if file.isDir {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: file.path)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        .animation(.easeOut(duration: 0.1), value: hovered)
    }
}

// MARK: - NSPanel controller (singleton map: agentId → panel)


@MainActor
final class WorktreePanelController {

    static let shared = WorktreePanelController()
    private var panels: [String: NSPanel] = [:]

    private init() {}

    func open(agentId: String, worktreePath: String) {
        // Bring existing panel to front if already open
        if let existing = panels[agentId] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let vm = WorktreeViewModel(agentId: agentId, worktreePath: worktreePath)
        let content = WorktreeView(vm: vm)
        let hosting = NSHostingView(rootView: content)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Worktree — \(agentId)"
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        // Position: cascade from center
        let offset = CGFloat(panels.count) * 24
        panel.center()
        panel.setFrameOrigin(NSPoint(
            x: panel.frame.origin.x + offset,
            y: panel.frame.origin.y - offset
        ))

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panels[agentId] = panel

        // Remove from map when closed
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: panel, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panels.removeValue(forKey: agentId)
            }
        }
    }
}

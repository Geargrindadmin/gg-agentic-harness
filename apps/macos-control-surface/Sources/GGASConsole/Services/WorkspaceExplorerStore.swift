import Foundation

struct WorkspaceFileNode: Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [WorkspaceFileNode]?
    let size: Int64
    let modifiedAt: Date?

    var id: String { path }
    var fileExtension: String { URL(fileURLWithPath: path).pathExtension.lowercased() }
}

@MainActor
final class WorkspaceExplorerStore: ObservableObject {
    static let shared = WorkspaceExplorerStore()

    @Published var rootPath: String = ""
    @Published var nodes: [WorkspaceFileNode] = []
    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    func load(rootPath: String) async {
        let normalized = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            self.rootPath = ""
            self.nodes = []
            self.error = "Choose a workspace root to browse files."
            self.isLoading = false
            return
        }

        guard FileManager.default.fileExists(atPath: normalized) else {
            self.rootPath = normalized
            self.nodes = []
            self.error = "Workspace path not found."
            self.isLoading = false
            return
        }

        self.rootPath = normalized
        self.isLoading = true
        self.error = nil

        do {
            let builtNodes = try await Task.detached(priority: .userInitiated) {
                try Self.buildNodes(for: normalized)
            }.value
            self.nodes = builtNodes
            self.isLoading = false
        } catch {
            self.nodes = []
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }

    private nonisolated static func buildNodes(for rootPath: String) throws -> [WorkspaceFileNode] {
        let fm = FileManager.default
        let entries = try fm.contentsOfDirectory(
            at: URL(fileURLWithPath: rootPath),
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        )

        return try entries
            .filter { shouldInclude(url: $0) }
            .map { try buildNode(at: $0) }
            .sorted(by: sortNodes)
    }

    private nonisolated static func buildNode(at url: URL) throws -> WorkspaceFileNode {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
        let isDirectory = values.isDirectory ?? false
        let children: [WorkspaceFileNode]?
        if isDirectory {
            children = try buildNodes(for: url.path)
        } else {
            children = nil
        }
        return WorkspaceFileNode(
            name: url.lastPathComponent,
            path: url.path,
            isDirectory: isDirectory,
            children: children,
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate
        )
    }

    private nonisolated static func sortNodes(left: WorkspaceFileNode, right: WorkspaceFileNode) -> Bool {
        if left.isDirectory != right.isDirectory {
            return left.isDirectory && !right.isDirectory
        }
        return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
    }

    private nonisolated static func shouldInclude(url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") && name != ".agent" {
            return false
        }
        let excluded = [
            ".git",
            ".build",
            "DerivedData",
            "node_modules",
            "dist",
            "build"
        ]
        return !excluded.contains(name)
    }
}

@MainActor
final class DocumentViewerStore: ObservableObject {
    struct RelatedDocument: Equatable {
        let path: String
        let label: String
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case source = "Source"
        case preview = "Preview"
        case diff = "Diff"

        var id: String { rawValue }
    }

    @Published var content: String = ""
    @Published var diffContent: String = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var isTruncated = false
    @Published var hasDiff = false
    @Published var relatedDocument: RelatedDocument?
    @Published var mode: ViewMode = .source
    @Published var isDirty = false
    @Published var isEditable = false

    let path: String
    private(set) var sourceLabel: String
    private(set) var workspaceRootPath: String
    private(set) var selectedRunRootPath: String?
    private var persistedContent: String = ""
    private var hasLoadedOnce = false

    init(path: String, sourceLabel: String, workspaceRootPath: String, selectedRunRootPath: String?) {
        self.path = path
        self.sourceLabel = sourceLabel
        self.workspaceRootPath = workspaceRootPath
        self.selectedRunRootPath = selectedRunRootPath
        primeFromDiskIfAvailable()
    }

    var isMarkdown: Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["md", "markdown", "mdx"].contains(ext)
    }

    var availableModes: [ViewMode] {
        var modes: [ViewMode] = [.source]
        if isMarkdown {
            modes.append(.preview)
        }
        if hasDiff {
            modes.append(.diff)
        }
        return modes
    }

    func configure(
        sourceLabel: String,
        workspaceRootPath: String,
        selectedRunRootPath: String?
    ) {
        self.sourceLabel = sourceLabel
        self.workspaceRootPath = workspaceRootPath
        self.selectedRunRootPath = selectedRunRootPath
    }

    func load(forceReplacingDraft: Bool = false) async {
        isLoading = true
        error = nil
        do {
            let path = self.path
            let related = Self.relatedDocument(for: path, workspaceRootPath: workspaceRootPath, selectedRunRootPath: selectedRunRootPath)
            let result = try await Task.detached(priority: .userInitiated) {
                let source = try Self.read(path: path)
                let diff = try related.map { try Self.buildDiff(sourcePath: path, targetPath: $0.path) }
                return (source, diff, related)
            }.value
            let loadedContent = result.0.content
            if forceReplacingDraft || !hasLoadedOnce || !isDirty {
                content = loadedContent
                persistedContent = loadedContent
                isDirty = false
            } else if persistedContent.isEmpty {
                persistedContent = loadedContent
            }
            isTruncated = result.0.truncated
            isEditable = !result.0.truncated
            diffContent = result.1 ?? ""
            relatedDocument = result.2
            hasDiff = !(result.1 ?? "").isEmpty
            if !availableModes.contains(mode) {
                mode = preferredMode
            }
            hasLoadedOnce = true
            isLoading = false
        } catch let loadError {
            content = ""
            diffContent = ""
            isTruncated = false
            isEditable = false
            isDirty = false
            persistedContent = ""
            relatedDocument = nil
            hasDiff = false
            mode = .source
            error = loadError.localizedDescription
            isLoading = false
        }
    }

    func replaceContent(_ nextContent: String) {
        ensureLoadedForImmediateEdit()
        guard isEditable else { return }
        content = nextContent
        isDirty = content != persistedContent
    }

    func save() async throws {
        guard isEditable else { return }
        let path = self.path
        let snapshot = self.content
        try await Task.detached(priority: .userInitiated) {
            try snapshot.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        }.value
        persistedContent = snapshot
        isDirty = false
        await load(forceReplacingDraft: true)
    }

    func revert() async {
        await load(forceReplacingDraft: true)
    }

    private var preferredMode: ViewMode {
        isMarkdown ? .preview : .source
    }

    private func ensureLoadedForImmediateEdit() {
        guard !hasLoadedOnce else { return }
        do {
            let loaded = try Self.read(path: path)
            content = loaded.content
            persistedContent = loaded.content
            isTruncated = loaded.truncated
            isEditable = !loaded.truncated
            relatedDocument = Self.relatedDocument(
                for: path,
                workspaceRootPath: workspaceRootPath,
                selectedRunRootPath: selectedRunRootPath
            )
            hasLoadedOnce = true
            error = nil
        } catch {
            self.error = error.localizedDescription
            isEditable = false
        }
    }

    private func primeFromDiskIfAvailable() {
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard let primed = try? Self.read(path: path) else { return }
        content = primed.content
        persistedContent = primed.content
        isTruncated = primed.truncated
        isEditable = !primed.truncated
        isDirty = false
        hasLoadedOnce = true
    }

    private nonisolated static func read(path: String) throws -> (content: String, truncated: Bool) {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let maxBytes = 512 * 1024
        let truncated = data.count > maxBytes
        let slice = truncated ? data.prefix(maxBytes) : data[...]
        guard let text = String(data: Data(slice), encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (text, truncated)
    }

    private nonisolated static func relatedDocument(
        for path: String,
        workspaceRootPath: String,
        selectedRunRootPath: String?
    ) -> RelatedDocument? {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedWorkspace = URL(fileURLWithPath: workspaceRootPath).standardizedFileURL.path
        let normalizedRun = selectedRunRootPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }

        if let normalizedRun,
           normalizedPath.hasPrefix(normalizedRun + "/") {
            let relative = String(normalizedPath.dropFirst(normalizedRun.count + 1))
            let counterpart = normalizedWorkspace + "/" + relative
            guard FileManager.default.fileExists(atPath: counterpart) else { return nil }
            return RelatedDocument(path: counterpart, label: "Workspace counterpart")
        }

        if normalizedPath.hasPrefix(normalizedWorkspace + "/"),
           let normalizedRun {
            let relative = String(normalizedPath.dropFirst(normalizedWorkspace.count + 1))
            let counterpart = normalizedRun + "/" + relative
            guard FileManager.default.fileExists(atPath: counterpart) else { return nil }
            return RelatedDocument(path: counterpart, label: "Selected run counterpart")
        }

        return nil
    }

    private nonisolated static func buildDiff(sourcePath: String, targetPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["diff", "--no-index", "--no-color", "--", sourcePath, targetPath]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus == 0 || process.terminationStatus == 1 {
            return text
        }
        throw CocoaError(.fileReadUnknown)
    }
}

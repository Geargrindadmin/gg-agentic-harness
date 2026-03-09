import Foundation

enum UIActionBusControlPlaneError: LocalizedError {
    case missingField(String)
    case invalidValue(field: String, value: String)
    case unsupportedCommand(String)

    var errorDescription: String? {
        switch self {
        case .missingField(let field):
            return "Missing required field '\(field)'."
        case .invalidValue(let field, let value):
            return "Invalid value '\(value)' for field '\(field)'."
        case .unsupportedCommand(let type):
            return "Unsupported UI action command '\(type)'."
        }
    }
}

struct UIActionBusCommandEnvelope: Codable, Equatable, Identifiable {
    let id: String
    let type: String
    let tab: String?
    let runId: String?
    let title: String?
    let runtime: String?
    let text: String?
    let path: String?
    let sourceLabel: String?
    let worktreePath: String?
    let worktreeLabel: String?
    let panel: String?
    let explorerRoot: String?
    let preset: String?
    let workingDirectory: String?
    let destination: String?

    init(
        id: String,
        type: String,
        tab: String? = nil,
        runId: String? = nil,
        title: String? = nil,
        runtime: String? = nil,
        text: String? = nil,
        path: String? = nil,
        sourceLabel: String? = nil,
        worktreePath: String? = nil,
        worktreeLabel: String? = nil,
        panel: String? = nil,
        explorerRoot: String? = nil,
        preset: String? = nil,
        workingDirectory: String? = nil,
        destination: String? = nil
    ) {
        self.id = id
        self.type = type
        self.tab = tab
        self.runId = runId
        self.title = title
        self.runtime = runtime
        self.text = text
        self.path = path
        self.sourceLabel = sourceLabel
        self.worktreePath = worktreePath
        self.worktreeLabel = worktreeLabel
        self.panel = panel
        self.explorerRoot = explorerRoot
        self.preset = preset
        self.workingDirectory = workingDirectory
        self.destination = destination
    }

    func resolvedAction() throws -> UIActionBusAction {
        switch normalized(type) {
        case "selecttab":
            guard let tab, let resolved = ConsoleTab.controlIdentifier(tab) else {
                throw UIActionBusControlPlaneError.invalidValue(field: "tab", value: tab ?? "")
            }
            return .selectTab(resolved)
        case "selectrun":
            guard let runId = required(runId, field: "runId") else {
                throw UIActionBusControlPlaneError.missingField("runId")
            }
            return .selectRun(runId: runId, title: title, runtime: runtime)
        case "clearworkflowselection", "clearselection":
            return .clearWorkflowSelection
        case "replaceactivedocumentcontent", "setactivedocumentcontent", "writeactivedocument":
            guard let text else {
                throw UIActionBusControlPlaneError.missingField("text")
            }
            return .replaceActiveDocumentContent(text)
        case "saveactivedocument":
            return .saveActiveDocument
        case "revertactivedocument", "reloadactivedocument":
            return .revertActiveDocument
        case "opendocument":
            guard let path = required(path, field: "path") else {
                throw UIActionBusControlPlaneError.missingField("path")
            }
            guard let sourceLabel = required(sourceLabel, field: "sourceLabel") else {
                throw UIActionBusControlPlaneError.missingField("sourceLabel")
            }
            return .openDocument(path: path, sourceLabel: sourceLabel)
        case "closeactivedocument":
            return .closeActiveDocument
        case "focusworktree":
            guard let worktreePath = required(worktreePath, field: "worktreePath") else {
                throw UIActionBusControlPlaneError.missingField("worktreePath")
            }
            guard let worktreeLabel = required(worktreeLabel, field: "worktreeLabel") else {
                throw UIActionBusControlPlaneError.missingField("worktreeLabel")
            }
            return .focusWorktree(path: worktreePath, label: worktreeLabel)
        case "revealinspector":
            guard let panel, let resolved = IDEPanelTab.controlIdentifier(panel) else {
                throw UIActionBusControlPlaneError.invalidValue(field: "panel", value: panel ?? "")
            }
            return .revealInspector(resolved)
        case "setexplorerroot":
            guard let explorerRoot, let resolved = ExplorerRootMode.controlIdentifier(explorerRoot) else {
                throw UIActionBusControlPlaneError.invalidValue(field: "explorerRoot", value: explorerRoot ?? "")
            }
            return .setExplorerRoot(resolved)
        case "launchterminal":
            let resolvedPreset = TerminalSessionPreset.controlIdentifier(preset ?? "") ?? .zsh
            let resolvedDestination = TerminalLaunchDestination.controlIdentifier(destination ?? "") ?? .workspaceDock
            return .launchTerminal(
                preset: resolvedPreset,
                workingDirectory: workingDirectory,
                title: title,
                destination: resolvedDestination
            )
        default:
            throw UIActionBusControlPlaneError.unsupportedCommand(type)
        }
    }

    private func required(_ value: String?, field: String) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        _ = field
        return trimmed
    }
}

struct UIActionBusErrorRecord: Codable, Equatable {
    let commandFile: String
    let message: String
}

@MainActor
final class UIActionBusControlPlane: ObservableObject {
    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("GGHarnessControlSurface", isDirectory: true)
            .appendingPathComponent("ui-action-bus", isDirectory: true)
    }

    let rootURL: URL
    let commandsDirectoryURL: URL
    let snapshotURL: URL
    let lastErrorURL: URL

    @Published private(set) var lastProcessedCommandId: String?
    @Published private(set) var lastErrorMessage: String?

    private let fileManager: FileManager
    private var shell: AppShellState?
    private var workflow: WorkflowContextStore?
    private var pollTask: Task<Void, Never>?
    private var lastSnapshotData: Data?

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil
    ) {
        self.fileManager = fileManager
        let resolvedRoot = rootURL ?? Self.defaultRootURL(fileManager: fileManager)
        self.rootURL = resolvedRoot
        self.commandsDirectoryURL = resolvedRoot.appendingPathComponent("commands", isDirectory: true)
        self.snapshotURL = resolvedRoot.appendingPathComponent("snapshot.json")
        self.lastErrorURL = resolvedRoot.appendingPathComponent("last-error.json")
    }

    deinit {
        pollTask?.cancel()
    }

    func bind(shell: AppShellState, workflow: WorkflowContextStore) {
        self.shell = shell
        self.workflow = workflow
    }

    func start(pollIntervalNanoseconds: UInt64 = 750_000_000) {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                _ = try? await self.syncNow()
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    @discardableResult
    func syncNow() async throws -> [String] {
        guard let shell, let workflow else { return [] }

        try ensureDirectories()
        let commandURLs = try fileManager.contentsOfDirectory(
            at: commandsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var processed: [String] = []
        for url in commandURLs {
            do {
                let command = try JSONDecoder().decode(UIActionBusCommandEnvelope.self, from: Data(contentsOf: url))
                let action = try command.resolvedAction()
                try await UIActionBus.performAsync(action, shell: shell, workflow: workflow)
                processed.append(command.id)
                lastProcessedCommandId = command.id
                try fileManager.removeItem(at: url)
            } catch {
                lastErrorMessage = error.localizedDescription
                try record(error: error, for: url)
                try? fileManager.removeItem(at: url)
            }
        }

        try writeSnapshot(shell: shell, workflow: workflow)
        return processed
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: commandsDirectoryURL, withIntermediateDirectories: true)
    }

    private func writeSnapshot(
        shell: AppShellState,
        workflow: WorkflowContextStore
    ) throws {
        let snapshot = UIActionBus.snapshot(shell: shell, workflow: workflow)
        let data = try JSONEncoder.pretty.encode(snapshot)
        guard data != lastSnapshotData else { return }
        try data.write(to: snapshotURL, options: .atomic)
        lastSnapshotData = data
    }

    private func record(error: Error, for commandURL: URL) throws {
        let payload = UIActionBusErrorRecord(
            commandFile: commandURL.lastPathComponent,
            message: error.localizedDescription
        )
        let data = try JSONEncoder.pretty.encode(payload)
        try data.write(to: lastErrorURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private func normalized(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
}

private extension ConsoleTab {
    static func controlIdentifier(_ value: String) -> ConsoleTab? {
        switch normalized(value) {
        case "planner", "tasks": return .tasks
        case "swarm": return .swarm
        case "notes": return .notes
        case "replays": return .replays
        case "modelfit": return .modelFit
        case "freemodels": return .freeModels
        case "agents", "agenttaskbar": return .agentTaskBar
        case "agentanalytics": return .agentAnalytics
        case "terminal": return .terminal
        case "llmstudio": return .llmStudio
        case "dispatch": return .dispatch
        case "packages": return .packages
        case "skills", "skillanalytics": return .skills
        case "trace": return .trace
        case "livelog": return .liveLog
        case "runhistory": return .runHistory
        case "config": return .config
        default: return nil
        }
    }
}

private extension IDEPanelTab {
    static func controlIdentifier(_ value: String) -> IDEPanelTab? {
        switch normalized(value) {
        case "explorer": return .explorer
        case "worktrees": return .worktrees
        case "context": return .context
        case "extensions": return .extensions
        default: return nil
        }
    }
}

private extension ExplorerRootMode {
    static func controlIdentifier(_ value: String) -> ExplorerRootMode? {
        switch normalized(value) {
        case "workspace": return .workspace
        case "gitworktrees", "worktrees": return .gitWorktrees
        case "focusedtree", "focusedworktree": return .focusedWorktree
        case "selectedrun", "run": return .selectedRun
        default: return nil
        }
    }
}

private extension TerminalSessionPreset {
    static func controlIdentifier(_ value: String) -> TerminalSessionPreset? {
        switch normalized(value) {
        case "zsh": return .zsh
        case "bash": return .bash
        case "tmux": return .tmux
        case "agent": return .agent
        default: return nil
        }
    }
}

private extension TerminalLaunchDestination {
    static func controlIdentifier(_ value: String) -> TerminalLaunchDestination? {
        switch normalized(value) {
        case "terminal", "terminaltab": return .terminalTab
        case "dock", "workspacedock", "ideterminaldock": return .workspaceDock
        default: return nil
        }
    }
}

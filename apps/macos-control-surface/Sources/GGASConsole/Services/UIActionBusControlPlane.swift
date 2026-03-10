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
    let agentId: String?
    let title: String?
    let runtime: String?
    let text: String?
    let patch: String?
    let reason: String?
    let dryRun: Bool?
    let problemId: String?
    let problemAction: String?
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
        agentId: String? = nil,
        title: String? = nil,
        runtime: String? = nil,
        text: String? = nil,
        patch: String? = nil,
        reason: String? = nil,
        dryRun: Bool? = nil,
        problemId: String? = nil,
        problemAction: String? = nil,
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
        self.agentId = agentId
        self.title = title
        self.runtime = runtime
        self.text = text
        self.patch = patch
        self.reason = reason
        self.dryRun = dryRun
        self.problemId = problemId
        self.problemAction = problemAction
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
        case "selectproblem":
            guard let problemId = required(problemId, field: "problemId") else {
                throw UIActionBusControlPlaneError.missingField("problemId")
            }
            return .selectProblem(id: problemId)
        case "performproblemaction":
            guard let problemId = required(problemId, field: "problemId") else {
                throw UIActionBusControlPlaneError.missingField("problemId")
            }
            guard let problemAction = required(problemAction, field: "problemAction"),
                  let capability = IDEProblemActionCapability.controlIdentifier(problemAction) else {
                throw UIActionBusControlPlaneError.invalidValue(field: "problemAction", value: problemAction ?? "")
            }
            return .performProblemAction(
                problemId: problemId,
                capability: capability,
                text: required(text, field: "text"),
                dryRun: dryRun ?? false
            )
        case "clearworkflowselection", "clearselection":
            return .clearWorkflowSelection
        case "replaceactivedocumentcontent", "setactivedocumentcontent", "writeactivedocument":
            guard let text else {
                throw UIActionBusControlPlaneError.missingField("text")
            }
            return .replaceActiveDocumentContent(text)
        case "stagepatchforactivedocument", "queueactivedocumentpatch", "setactivedocumentpatch":
            guard let patch = required(patch ?? text, field: "patch") else {
                throw UIActionBusControlPlaneError.missingField("patch")
            }
            return .stagePatchForActiveDocument(patch)
        case "applystagedpatchtoactivedocument", "applyactivedocumentpatch":
            return .applyStagedPatchToActiveDocument
        case "discardstagedpatchforactivedocument", "clearactivedocumentpatch":
            return .discardStagedPatchForActiveDocument
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
        case "sendworkerguidance", "messageworker":
            guard let runId = required(runId, field: "runId") else {
                throw UIActionBusControlPlaneError.missingField("runId")
            }
            guard let agentId = required(agentId, field: "agentId") else {
                throw UIActionBusControlPlaneError.missingField("agentId")
            }
            guard let text = required(text, field: "text") else {
                throw UIActionBusControlPlaneError.missingField("text")
            }
            return .sendWorkerGuidance(runId: runId, agentId: agentId, message: text)
        case "retryworker":
            guard let runId = required(runId, field: "runId") else {
                throw UIActionBusControlPlaneError.missingField("runId")
            }
            guard let agentId = required(agentId, field: "agentId") else {
                throw UIActionBusControlPlaneError.missingField("agentId")
            }
            return .retryWorker(runId: runId, agentId: agentId, dryRun: dryRun ?? false)
        case "retaskworker":
            guard let runId = required(runId, field: "runId") else {
                throw UIActionBusControlPlaneError.missingField("runId")
            }
            guard let agentId = required(agentId, field: "agentId") else {
                throw UIActionBusControlPlaneError.missingField("agentId")
            }
            guard let text = required(text, field: "text") else {
                throw UIActionBusControlPlaneError.missingField("text")
            }
            return .retaskWorker(
                runId: runId,
                agentId: agentId,
                taskSummary: text,
                dryRun: dryRun ?? false
            )
        case "terminateworker":
            guard let runId = required(runId, field: "runId") else {
                throw UIActionBusControlPlaneError.missingField("runId")
            }
            guard let agentId = required(agentId, field: "agentId") else {
                throw UIActionBusControlPlaneError.missingField("agentId")
            }
            return .terminateWorker(runId: runId, agentId: agentId, reason: required(reason ?? text, field: "reason"))
        case "openproblemdocument":
            return try resolvedProblemAction(.openDocument)
        case "revealproblempanel":
            return try resolvedProblemAction(.revealInspector)
        case "focusproblemworktree":
            return try resolvedProblemAction(.focusWorktree)
        case "saveproblemdocument":
            return try resolvedProblemAction(.saveDocument)
        case "revertproblemdocument":
            return try resolvedProblemAction(.revertDocument)
        case "applyproblempatch":
            return try resolvedProblemAction(.applyStagedPatch)
        case "discardproblempatch":
            return try resolvedProblemAction(.discardStagedPatch)
        case "messageproblemworker", "sendguidancetoproblemworker":
            return try resolvedProblemAction(.sendWorkerGuidance, text: required(text, field: "text"))
        case "retryproblemworker":
            return try resolvedProblemAction(.retryWorker, dryRun: dryRun ?? false)
        case "retaskproblemworker":
            return try resolvedProblemAction(.retaskWorker, text: required(text, field: "text"), dryRun: dryRun ?? false)
        case "terminateproblemworker":
            return try resolvedProblemAction(.terminateWorker, text: required(reason ?? text, field: "reason"))
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

    private func resolvedProblemAction(
        _ capability: IDEProblemActionCapability,
        text: String? = nil,
        dryRun: Bool = false
    ) throws -> UIActionBusAction {
        guard let problemId = required(problemId, field: "problemId") else {
            throw UIActionBusControlPlaneError.missingField("problemId")
        }
        return .performProblemAction(
            problemId: problemId,
            capability: capability,
            text: text,
            dryRun: dryRun
        )
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
        let snapshot = UIActionBus.snapshot(
            shell: shell,
            workflow: workflow,
            controlPlaneError: lastErrorMessage
        )
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
        case "usage": return .usage
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

private extension IDEProblemActionCapability {
    static func controlIdentifier(_ value: String) -> IDEProblemActionCapability? {
        switch normalized(value) {
        case "opendocument", "openproblemdocument": return .openDocument
        case "revealinspector", "revealproblempanel": return .revealInspector
        case "focusworktree", "focusproblemworktree": return .focusWorktree
        case "savedocument", "saveactivedocument", "saveproblemdocument": return .saveDocument
        case "revertdocument", "revertactivedocument", "reloadactivedocument", "revertproblemdocument": return .revertDocument
        case "applystagedpatch", "applyproblempatch", "applyactivedocumentpatch": return .applyStagedPatch
        case "discardstagedpatch", "discardproblempatch", "clearactivedocumentpatch": return .discardStagedPatch
        case "sendworkerguidance", "messageworker", "messageproblemworker", "sendguidancetoproblemworker": return .sendWorkerGuidance
        case "retryworker", "retryproblemworker": return .retryWorker
        case "retaskworker", "retaskproblemworker": return .retaskWorker
        case "terminateworker", "terminateproblemworker": return .terminateWorker
        default: return nil
        }
    }
}

private extension IDEPanelTab {
    static func controlIdentifier(_ value: String) -> IDEPanelTab? {
        switch normalized(value) {
        case "explorer": return .explorer
        case "problems", "problem": return .problems
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

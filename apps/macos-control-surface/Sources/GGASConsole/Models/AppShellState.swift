import Foundation

enum TerminalSessionPreset: String, Equatable {
    case zsh
    case bash
    case tmux
    case agent
}

enum TerminalLaunchDestination: String, Equatable {
    case terminalTab
    case workspaceDock
}

struct TerminalLaunchRequest: Identifiable, Equatable {
    let id = UUID()
    let preset: TerminalSessionPreset
    let workingDirectory: String?
    let titleOverride: String?
    let destination: TerminalLaunchDestination
}

enum IDEPanelTab: String, CaseIterable, Identifiable {
    case explorer = "Explorer"
    case problems = "Problems"
    case worktrees = "Worktrees"
    case context = "Context"
    case extensions = "Extensions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .explorer: return "folder"
        case .problems: return "exclamationmark.triangle"
        case .worktrees: return "square.stack.3d.down.forward"
        case .context: return "scope"
        case .extensions: return "puzzlepiece.extension"
        }
    }
}

enum ExplorerRootMode: String, CaseIterable, Identifiable {
    case workspace = "Workspace"
    case gitWorktrees = "Git Worktrees"
    case focusedWorktree = "Focused Tree"
    case selectedRun = "Selected Run"

    var id: String { rawValue }
}

struct IDEDocumentContext: Identifiable, Equatable {
    let path: String
    let sourceLabel: String

    var id: String { path }
    var title: String { URL(fileURLWithPath: path).lastPathComponent }
}

@MainActor
final class AppShellState: ObservableObject {
    private static let sidebarCollapsedKey = "gg_sidebar_collapsed"
    private static let rightInspectorCollapsedKey = "gg_right_inspector_collapsed"

    @Published var selectedTab: ConsoleTab = .tasks
    @Published var lmStudioCatalogQuery = ""
    @Published var lmStudioAutoDownload = false
    @Published var idePanelTab: IDEPanelTab = .explorer
    @Published var explorerRootMode: ExplorerRootMode = .gitWorktrees
    @Published var focusedWorktreePath: String?
    @Published var focusedWorktreeLabel: String = "Focused Worktree"
    @Published var selectedProblemId: String?
    @Published var openDocuments: [IDEDocumentContext] = []
    @Published var activeDocumentId: String?
    @Published var pendingTerminalLaunch: TerminalLaunchRequest?
    @Published var ideTerminalDockVisible = false
    @Published var rightInspectorCollapsed: Bool = false {
        didSet {
            UserDefaults.standard.set(rightInspectorCollapsed, forKey: Self.rightInspectorCollapsedKey)
        }
    }
    @Published var sidebarCollapsed: Bool = UserDefaults.standard.bool(forKey: sidebarCollapsedKey) {
        didSet {
            UserDefaults.standard.set(sidebarCollapsed, forKey: Self.sidebarCollapsedKey)
        }
    }

    init() {
        rightInspectorCollapsed = UserDefaults.standard.bool(forKey: Self.rightInspectorCollapsedKey)
    }

    var activeDocument: IDEDocumentContext? {
        guard let activeDocumentId else { return nil }
        return openDocuments.first(where: { $0.id == activeDocumentId })
    }

    func openLMStudioCatalog(query: String = "", autoDownload: Bool = false) {
        lmStudioCatalogQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        lmStudioAutoDownload = autoDownload
        selectTab(.llmStudio)
    }

    func selectTab(_ tab: ConsoleTab) {
        selectedTab = tab
        activeDocumentId = nil
        rightInspectorCollapsed = true
    }

    func openUsage() {
        selectTab(.usage)
    }

    func openDocument(path: String, sourceLabel: String) {
        let document = IDEDocumentContext(path: path, sourceLabel: sourceLabel)
        if !openDocuments.contains(document) {
            openDocuments.append(document)
        }
        activeDocumentId = document.id
    }

    func selectProblem(id: String?) {
        selectedProblemId = id
        idePanelTab = .problems
        rightInspectorCollapsed = false
    }

    func selectDocument(_ document: IDEDocumentContext) {
        activeDocumentId = document.id
    }

    func closeDocument(_ document: IDEDocumentContext) {
        openDocuments.removeAll { $0.id == document.id }
        if activeDocumentId == document.id {
            activeDocumentId = openDocuments.last?.id
        }
    }

    func closeDocument() {
        guard let document = activeDocument else { return }
        closeDocument(document)
    }

    func toggleSidebarCollapsed() {
        sidebarCollapsed.toggle()
    }

    func toggleRightInspectorCollapsed() {
        rightInspectorCollapsed.toggle()
    }

    func focusWorktree(path: String, label: String) {
        focusedWorktreePath = path
        focusedWorktreeLabel = label
        explorerRootMode = .focusedWorktree
        idePanelTab = .explorer
        rightInspectorCollapsed = false
    }

    func launchTerminal(
        preset: TerminalSessionPreset = .zsh,
        workingDirectory: String? = nil,
        title: String? = nil,
        destination: TerminalLaunchDestination = .terminalTab
    ) {
        pendingTerminalLaunch = TerminalLaunchRequest(
            preset: preset,
            workingDirectory: workingDirectory,
            titleOverride: title,
            destination: destination
        )
        switch destination {
        case .terminalTab:
            selectTab(.terminal)
        case .workspaceDock:
            ideTerminalDockVisible = true
        }
    }

    func showIDETerminalDock() {
        ideTerminalDockVisible = true
    }

    func hideIDETerminalDock() {
        ideTerminalDockVisible = false
    }

    func toggleIDETerminalDock() {
        ideTerminalDockVisible.toggle()
    }
}

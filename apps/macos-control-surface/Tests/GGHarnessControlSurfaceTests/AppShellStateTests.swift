import Testing
@testable import GGHarnessControlSurface

struct AppShellStateTests {
    @MainActor
    @Test
    func tabSelectionPreservesSidebarStateAndCollapsesInspector() {
        let shell = AppShellState()
        shell.sidebarCollapsed = false
        shell.rightInspectorCollapsed = false

        shell.selectTab(.usage)

        #expect(shell.selectedTab == .usage)
        #expect(shell.sidebarCollapsed == false)
        #expect(shell.rightInspectorCollapsed == true)
    }

    @MainActor
    @Test
    func tabSelectionClearsActiveDocumentButKeepsOpenTabs() {
        let shell = AppShellState()
        shell.openDocument(path: "/tmp/AGENTS.md", sourceLabel: "Workspace")

        shell.selectTab(.trace)

        #expect(shell.selectedTab == .trace)
        #expect(shell.activeDocumentId == nil)
        #expect(shell.openDocuments.count == 1)
    }

    @MainActor
    @Test
    func openUsageRoutesThroughMainNavigation() {
        let shell = AppShellState()
        shell.selectedTab = .tasks

        shell.openUsage()

        #expect(shell.selectedTab == .usage)
    }

    @MainActor
    @Test
    func openLMStudioCatalogClearsActiveDocument() {
        let shell = AppShellState()
        shell.openDocument(path: "/tmp/AGENTS.md", sourceLabel: "Workspace")

        shell.openLMStudioCatalog(query: "qwen", autoDownload: true)

        #expect(shell.selectedTab == .llmStudio)
        #expect(shell.activeDocumentId == nil)
        #expect(shell.lmStudioCatalogQuery == "qwen")
        #expect(shell.lmStudioAutoDownload == true)
    }

    @MainActor
    @Test
    func workspaceDockLaunchKeepsCurrentTabAndShowsDock() {
        let shell = AppShellState()
        shell.selectedTab = .swarm

        shell.launchTerminal(
            preset: .zsh,
            workingDirectory: "/tmp",
            title: "zsh • tmp",
            destination: .workspaceDock
        )

        #expect(shell.selectedTab == .swarm)
        #expect(shell.ideTerminalDockVisible == true)
        #expect(shell.pendingTerminalLaunch?.destination == .workspaceDock)
        #expect(shell.pendingTerminalLaunch?.workingDirectory == "/tmp")
    }

    @MainActor
    @Test
    func standaloneLaunchStillSelectsTerminalTab() {
        let shell = AppShellState()
        shell.selectedTab = .tasks
        shell.openDocument(path: "/tmp/Task.md", sourceLabel: "Workspace")

        shell.launchTerminal(
            preset: .agent,
            workingDirectory: "/tmp/run-123",
            title: "agent • run-123",
            destination: .terminalTab
        )

        #expect(shell.selectedTab == .terminal)
        #expect(shell.activeDocumentId == nil)
        #expect(shell.pendingTerminalLaunch?.destination == .terminalTab)
        #expect(shell.pendingTerminalLaunch?.preset == .agent)
    }
}

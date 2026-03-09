import Testing
@testable import GGHarnessControlSurface

struct AppShellStateTests {
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

        shell.launchTerminal(
            preset: .agent,
            workingDirectory: "/tmp/run-123",
            title: "agent • run-123",
            destination: .terminalTab
        )

        #expect(shell.selectedTab == .terminal)
        #expect(shell.pendingTerminalLaunch?.destination == .terminalTab)
        #expect(shell.pendingTerminalLaunch?.preset == .agent)
    }
}

import Testing
@testable import GGHarnessControlSurface

struct TerminalSurfaceModelTests {
    @MainActor
    @Test
    func activatingDockSplitCreatesSecondaryPaneAndKeepsPrimarySelection() {
        let model = TerminalSurfaceModel(
            launchDestination: .workspaceDock,
            seedsDefaultShell: false
        )

        model.addZshTab(workingDirectory: "/tmp", titleOverride: "zsh • primary")
        let primary = model.activeId

        model.activateSplit(.right, projectSettings: ProjectSettings.shared)

        #expect(model.splitMode == .right)
        #expect(model.activeId == primary)
        #expect(model.secondaryActiveId != nil)
        #expect(model.secondaryActiveId != primary)
        #expect(model.tabs.count == 2)
    }

    @MainActor
    @Test
    func removingSecondaryPaneClearsSplitWhenNoReplacementExists() {
        let model = TerminalSurfaceModel(
            launchDestination: .workspaceDock,
            seedsDefaultShell: false
        )

        model.addZshTab(titleOverride: "zsh • primary")
        model.activateSplit(.down, projectSettings: ProjectSettings.shared)

        let secondary = model.secondaryActiveId
        #expect(secondary != nil)

        if let secondary {
            model.removeTab(secondary)
        }

        #expect(model.splitMode == .none)
        #expect(model.secondaryActiveId == nil)
        #expect(model.tabs.count == 1)
    }
}

// GGASConsoleApp.swift — App entry point

import SwiftUI
import AppKit

@main
struct GGASConsoleApp: App {

    @StateObject private var client   = A2AClient()
    @StateObject private var forge    = ForgeStore()
    @StateObject private var launcher = LaunchManager()
    @StateObject private var shell    = AppShellState()
    @StateObject private var workflow = WorkflowContextStore.shared
    @StateObject private var uiControlPlane = UIActionBusControlPlane()
    @StateObject private var uiRPCService = UIActionBusRPCService()

    /// The imported app defaults to viewer/control-surface mode.
    /// Legacy setup flows are still available from the menu while backend migration continues.
    @State private var showSetup = false

    @MainActor
    private func activateMainWindow() async {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        for attempt in 0..<6 {
            if let window = NSApp.windows.first(where: { $0.canBecomeKey }) ?? NSApp.keyWindow ?? NSApp.mainWindow {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }

            if attempt < 5 {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
                .environmentObject(forge)
                .environmentObject(launcher)
                .environmentObject(shell)
                .environmentObject(workflow)
                .environmentObject(uiControlPlane)
                .environmentObject(uiRPCService)
                .task { await launcher.start() }
                .task { AgentMonitorService.shared.startPolling() }  // single-source bus polling (Phase 2)
                .task {
                    await activateMainWindow()
                }
                .task {
                    uiControlPlane.bind(shell: shell, workflow: workflow)
                    uiControlPlane.start()
                }
                .task {
                    uiRPCService.bind(shell: shell, workflow: workflow)
                    uiRPCService.start()
                }
                .sheet(isPresented: $showSetup) {
                    SetupWizardView(showWizard: $showSetup)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("IDE") {
                Button("Save File") {
                    Task {
                        try? await UIActionBus.performAsync(
                            .saveActiveDocument,
                            shell: shell,
                            workflow: workflow
                        )
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(shell.activeDocument == nil)

                Button("Revert File") {
                    Task {
                        try? await UIActionBus.performAsync(
                            .revertActiveDocument,
                            shell: shell,
                            workflow: workflow
                        )
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(shell.activeDocument == nil)

                Button("Close File") {
                    UIActionBus.perform(
                        .closeActiveDocument,
                        shell: shell,
                        workflow: workflow
                    )
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(shell.activeDocument == nil)

                Divider()

                Button(shell.ideTerminalDockVisible ? "Hide Terminal Dock" : "Show Terminal Dock") {
                    shell.toggleIDETerminalDock()
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])

                Menu("New Terminal Session") {
                    Button("zsh") {
                        UIActionBus.perform(
                            .launchTerminal(
                                preset: .zsh,
                                workingDirectory: nil,
                                title: nil,
                                destination: .workspaceDock
                            ),
                            shell: shell,
                            workflow: workflow
                        )
                    }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                    Button("bash") {
                        UIActionBus.perform(
                            .launchTerminal(
                                preset: .bash,
                                workingDirectory: nil,
                                title: nil,
                                destination: .workspaceDock
                            ),
                            shell: shell,
                            workflow: workflow
                        )
                    }

                    Button("tmux") {
                        UIActionBus.perform(
                            .launchTerminal(
                                preset: .tmux,
                                workingDirectory: nil,
                                title: nil,
                                destination: .workspaceDock
                            ),
                            shell: shell,
                            workflow: workflow
                        )
                    }

                    Button("Agent Session") {
                        UIActionBus.perform(
                            .launchTerminal(
                                preset: .agent,
                                workingDirectory: nil,
                                title: nil,
                                destination: .workspaceDock
                            ),
                            shell: shell,
                            workflow: workflow
                        )
                    }
                }
            }
            CommandMenu("Harness") {
                Button("Refresh") { forge.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Restart Services") { Task { await launcher.restart() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Open Setup Wizard…") {
                    showSetup = true
                }
            }
        }
    }
}

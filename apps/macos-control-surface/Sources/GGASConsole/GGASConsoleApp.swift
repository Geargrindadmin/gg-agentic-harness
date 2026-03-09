// GGASConsoleApp.swift — App entry point

import SwiftUI

@main
struct GGASConsoleApp: App {

    @StateObject private var client   = A2AClient()
    @StateObject private var forge    = ForgeStore()
    @StateObject private var launcher = LaunchManager()

    /// The imported app defaults to viewer/control-surface mode.
    /// Legacy setup flows are still available from the menu while backend migration continues.
    @State private var showSetup = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(client)
                .environmentObject(forge)
                .environmentObject(launcher)
                .task { await launcher.start() }
                .task { AgentMonitorService.shared.startPolling() }  // single-source bus polling (Phase 2)
                .sheet(isPresented: $showSetup) {
                    SetupWizardView(showWizard: $showSetup)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
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

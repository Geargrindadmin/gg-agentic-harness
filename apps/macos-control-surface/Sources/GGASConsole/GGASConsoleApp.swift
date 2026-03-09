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
                .task { await launcher.start() }
                .task { AgentMonitorService.shared.startPolling() }  // single-source bus polling (Phase 2)
                .task {
                    await activateMainWindow()
                }
                .task {
                    uiControlPlane.bind(shell: shell, workflow: workflow)
                    uiControlPlane.start()
                }
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

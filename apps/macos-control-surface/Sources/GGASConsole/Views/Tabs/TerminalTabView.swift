// TerminalTabView.swift — Embedded terminal using SwiftTerm
//
// SwiftTerm provides a real PTY-backed terminal emulator (NSView).
// TUI apps like jcode render correctly — full ANSI/cursor-positioning support.
// Each tab = one LocalProcessTerminalView running jcode (or zsh for manual control).

import SwiftUI
import AppKit
import SwiftTerm

// MARK: - Persistent NSView store
//
// Keeps LocalProcessTerminalView instances alive independent of SwiftUI view lifecycle.
// Primary persistence comes from ContentView always mounting TerminalTabView;
// this store is a safety net for any edge cases where the view IS recreated.

@MainActor
final class TerminalSessionStore {
    static let shared = TerminalSessionStore()
    private var views: [UUID: TerminalContainerView] = [:]

    func view(for id: UUID, make: @MainActor () -> TerminalContainerView) -> TerminalContainerView {
        if let existing = views[id] { return existing }
        let v = make()
        views[id] = v
        return v
    }

    func remove(_ id: UUID) {
        views.removeValue(forKey: id)
    }
}

// MARK: - Focus-forwarding container view
//
// LocalProcessTerminalView is not marked `open`, so overriding mouseDown/acceptsFirstResponder
// from outside the SwiftTerm module is illegal. We wrap it in a plain NSView instead.
// The container intercepts viewDidMoveToWindow and mouseDown at the NSView level,
// then tells the window to make the inner terminal first responder for keyboard input.

final class TerminalContainerView: NSView {
    let terminal: LocalProcessTerminalView

    init(terminal: LocalProcessTerminalView) {
        self.terminal = terminal
        super.init(frame: .zero)
        addSubview(terminal)
        terminal.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func focusTerminal() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            w.makeFirstResponder(self.terminal)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        focusTerminal()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        focusTerminal()
    }
}

// MARK: - NSViewRepresentable wrapper

struct EmbeddedTerminal: NSViewRepresentable {
    let tabId: UUID
    let executable: String
    let args: [String]

    init(tabId: UUID, executable: String = jcodeExecutable(), args: [String] = []) {
        self.tabId = tabId
        self.executable = executable
        self.args = args
    }

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalSessionStore.shared.view(for: tabId) {
            let tv = LocalProcessTerminalView(frame: .zero)
            tv.processDelegate = context.coordinator

            let home    = NSHomeDirectory()
            let newPath = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/sbin"
            var env     = ProcessInfo.processInfo.environment
            env["PATH"]      = newPath
            env["TERM"]      = "xterm-256color"
            env["COLORTERM"] = "truecolor"

            tv.startProcess(executable: executable, args: args, environment: buildEnvArray(env))
            return TerminalContainerView(terminal: tv)
        }
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        // Focus is handled by TerminalContainerView itself via viewDidMoveToWindow/mouseDown.
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }

    private func buildEnvArray(_ dict: [String: String]) -> [String] {
        dict.map { "\($0.key)=\($0.value)" }
    }
}

/// Find the jcode binary path.
private func jcodeExecutable(projectRoot: String = "") -> String {
    let trimmedProjectRoot = projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidates: [String] = []
    if !trimmedProjectRoot.isEmpty {
        candidates.append(trimmedProjectRoot + "/tools/gg-cli/target/release/jcode")
    }
    candidates.append(contentsOf: [
        NSHomeDirectory() + "/.local/bin/jcode",
        "/opt/homebrew/bin/jcode",
        "/usr/local/bin/jcode",
    ])
    for path in candidates {
        if FileManager.default.isExecutableFile(atPath: path) { return path }
    }
    // Fallback to zsh so the tab isn't blank
    return "/bin/zsh"
}

// MARK: - Tab model

struct TermTab: Identifiable {
    let id = UUID()
    var title: String
    var executable: String
    var args: [String]
}

// MARK: - Root view

struct TerminalTabView: View {
    @EnvironmentObject var launcher: LaunchManager
    @ObservedObject private var projectSettings = ProjectSettings.shared
    @State private var tabs: [TermTab] = []
    @State private var activeId: UUID? = nil
    @State private var showLaunchProfile = false

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .background(Color.black)
        .onAppear {
            if tabs.isEmpty { addJcodeTab() }
        }   // open one jcode tab automatically
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs) { t in tabPill(t) }
                }
            }
            // "+" = new jcode session
            Button {
                addJcodeTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .help("New jcode terminal")

            Button {
                showLaunchProfile = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
            .help("Edit jcode launch profile")
            .popover(isPresented: $showLaunchProfile) {
                TerminalLaunchProfileView(
                    profile: Binding(
                        get: { projectSettings.jcodeLaunchProfile },
                        set: { projectSettings.jcodeLaunchProfile = $0 }
                    ),
                    projectRoot: projectSettings.projectRoot
                )
                .frame(width: 460)
                .padding(14)
            }

            // Shell tab (plain zsh, useful for manual commands)
            Button {
                addShellTab()
            } label: {
                Text("zsh")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .help("New plain shell tab")
        }
        .frame(height: 34)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func tabPill(_ t: TermTab) -> some View {
        let active = t.id == activeId
        HStack(spacing: 5) {
            Text(t.title)
                .font(.system(size: 11, weight: active ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(active ? .white : .secondary)

            Button {
                removeTab(t.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: 8))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(active ? Color.white.opacity(0.08) : Color.clear)
        .overlay(alignment: .bottom) {
            if active { Rectangle().fill(Color.green).frame(height: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture { activeId = t.id }
    }

    // MARK: Content

    @ViewBuilder
    private var tabContent: some View {
        if let t = tabs.first(where: { $0.id == activeId }) {
            EmbeddedTerminal(tabId: t.id, executable: t.executable, args: t.args)
        } else {
            ZStack {
                Color.black
                Text("Press + to open jcode")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Tab management

    private func addJcodeTab() {
        let profile = projectSettings.jcodeLaunchProfile
        let (exe, args) = jcodeLaunchCommand(profile: profile, projectRoot: projectSettings.projectRoot)
        let n    = tabs.filter { $0.executable == exe }.count + 1
        let isJCode = exe.hasSuffix("jcode") || exe.hasSuffix("gg-cli.sh")
        let name = isJCode ? "jcode \(n)" : "shell \(n)"
        let t    = TermTab(title: name, executable: exe, args: args)
        tabs.append(t)
        activeId = t.id
    }

    private func addShellTab() {
        let n = tabs.filter { $0.executable == "/bin/zsh" }.count + 1
        let t = TermTab(title: "zsh \(n)", executable: "/bin/zsh", args: ["-l"])
        tabs.append(t)
        activeId = t.id
    }

    private func removeTab(_ id: UUID) {
        TerminalSessionStore.shared.remove(id)  // release the NSView and kill the process
        tabs.removeAll { $0.id == id }
        if activeId == id { activeId = tabs.last?.id }
    }

    private func jcodeLaunchCommand(
        profile: ProjectSettings.JCodeLaunchProfile,
        projectRoot: String
    ) -> (String, [String]) {
        let wrapperPath = projectRoot + "/tools/gg-cli/gg-cli.sh"
        let canUseWrapper = profile.useWrapper && FileManager.default.isExecutableFile(atPath: wrapperPath)
        let jcodePath = jcodeExecutable(projectRoot: projectRoot)

        if !canUseWrapper && !jcodePath.hasSuffix("jcode") {
            return ("/bin/zsh", ["-l"])
        }

        var args: [String] = []

        if let cwd = resolvedWorkingDirectory(profile: profile, projectRoot: projectRoot) {
            args += ["-C", cwd]
        }

        let provider = profile.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        if !provider.isEmpty { args += ["--provider", provider] }

        let model = profile.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { args += ["--model", model] }

        let resume = profile.resumeSession.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resume.isEmpty { args += ["--resume", resume] }

        if profile.launchMode == "run" {
            let message = profile.runMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty { args += ["run", message] }
        }

        return (canUseWrapper ? wrapperPath : jcodePath, args)
    }

    private func resolvedWorkingDirectory(
        profile: ProjectSettings.JCodeLaunchProfile,
        projectRoot: String
    ) -> String? {
        let preferred = profile.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferred.isEmpty, FileManager.default.fileExists(atPath: preferred) {
            return preferred
        }

        let fallback = projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty, FileManager.default.fileExists(atPath: fallback) {
            return fallback
        }

        return nil
    }
}

private struct TerminalLaunchProfileView: View {
    @Binding var profile: ProjectSettings.JCodeLaunchProfile
    let projectRoot: String
    @ObservedObject private var providerSvc = ProviderDetectionService.shared

    private var wrapperPath: String {
        projectRoot + "/tools/gg-cli/gg-cli.sh"
    }

    private var wrapperAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: wrapperPath)
    }

    private var selectedProviderEntry: ProviderCatalogEntry? {
        let explicitProvider = profile.provider.trimmingCharacters(in: .whitespacesAndNewlines)
        if explicitProvider.isEmpty || explicitProvider == "auto" {
            return providerSvc.selectedProvider
        }
        return providerSvc.availableProviders.first(where: { $0.id == explicitProvider })
    }

    private var suggestedModels: [String] {
        selectedProviderEntry?.models ?? []
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: {
                let value = profile.provider.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? "auto" : value
            },
            set: { newValue in
                profile.provider = newValue
                guard let entry = providerSvc.availableProviders.first(where: { $0.id == newValue }) else { return }
                if profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !entry.models.contains(profile.model) {
                    profile.model = entry.defaultModel ?? entry.models.first ?? profile.model
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("jcode Launch Profile")
                .font(.headline)

            Toggle("Use gg-cli wrapper first", isOn: $profile.useWrapper)

            HStack(spacing: 10) {
                Label("Wrapper", systemImage: wrapperAvailable ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(wrapperAvailable ? .green : .orange)
                Text(wrapperPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            if providerSvc.availableProviders.isEmpty {
                TextField("Provider (auto, claude, openai, ...)", text: $profile.provider)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("Provider", selection: providerBinding) {
                    Text("auto").tag("auto")
                    ForEach(providerSvc.availableProviders) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                TextField("Model (optional)", text: $profile.model)
                    .textFieldStyle(.roundedBorder)

                if !suggestedModels.isEmpty {
                    Menu {
                        ForEach(suggestedModels, id: \.self) { model in
                            Button(model) { profile.model = model }
                        }
                    } label: {
                        Label("Suggested", systemImage: "sparkles")
                    }
                    .fixedSize()
                }
            }
            TextField("Working directory (optional)", text: $profile.workingDirectory)
                .textFieldStyle(.roundedBorder)
            if profile.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !projectRoot.isEmpty {
                Text("Defaults to project root: \(projectRoot)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            TextField("Resume session ID (optional)", text: $profile.resumeSession)
                .textFieldStyle(.roundedBorder)

            Picker("Launch mode", selection: $profile.launchMode) {
                Text("interactive").tag("interactive")
                Text("run").tag("run")
            }
            .pickerStyle(.segmented)

            if profile.launchMode == "run" {
                TextField("Run message", text: $profile.runMessage)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .task { providerSvc.refresh() }
    }
}

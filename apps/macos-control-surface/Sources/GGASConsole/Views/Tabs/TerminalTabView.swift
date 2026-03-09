// TerminalTabView.swift — Embedded terminal using SwiftTerm
//
// SwiftTerm provides a real PTY-backed terminal emulator (NSView).
// Each tab = one LocalProcessTerminalView running a shell or an agent/runtime CLI session.

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

    init(tabId: UUID, executable: String = "/bin/zsh", args: [String] = ["-l"]) {
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

private func tmuxExecutable() -> String? {
    let candidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/usr/bin/tmux"
    ]
    return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
}

// MARK: - Tab model

struct TermTab: Identifiable {
    let id = UUID()
    var title: String
    var executable: String
    var args: [String]
}

@MainActor
final class TerminalSurfaceModel: ObservableObject {
    let launchDestination: TerminalLaunchDestination
    let seedsDefaultShell: Bool

    @Published var tabs: [TermTab] = []
    @Published var activeId: UUID?
    @Published var showLaunchProfile = false

    private var lastConsumedLaunchId: UUID?

    init(
        launchDestination: TerminalLaunchDestination,
        seedsDefaultShell: Bool
    ) {
        self.launchDestination = launchDestination
        self.seedsDefaultShell = seedsDefaultShell
    }

    var tmuxAvailable: Bool {
        tmuxExecutable() != nil
    }

    func ensureReady(shell: AppShellState, projectSettings: ProjectSettings) {
        if tabs.isEmpty, !consumePendingLaunch(from: shell, projectSettings: projectSettings), seedsDefaultShell {
            addZshTab()
        }
    }

    @discardableResult
    func consumePendingLaunch(
        from shell: AppShellState,
        projectSettings: ProjectSettings
    ) -> Bool {
        guard let request = shell.pendingTerminalLaunch else { return false }
        guard request.destination == launchDestination else { return false }
        guard request.id != lastConsumedLaunchId else { return false }

        lastConsumedLaunchId = request.id
        switch request.preset {
        case .zsh:
            addZshTab(workingDirectory: request.workingDirectory, titleOverride: request.titleOverride)
        case .bash:
            addBashTab(workingDirectory: request.workingDirectory, titleOverride: request.titleOverride)
        case .tmux:
            addTmuxTab(workingDirectory: request.workingDirectory, titleOverride: request.titleOverride)
        case .agent:
            addAgentSessionTab(
                projectSettings: projectSettings,
                workingDirectory: request.workingDirectory,
                titleOverride: request.titleOverride
            )
        }
        shell.pendingTerminalLaunch = nil
        return true
    }

    func addAgentSessionTab(
        projectSettings: ProjectSettings,
        workingDirectory: String? = nil,
        titleOverride: String? = nil
    ) {
        let profile = projectSettings.jcodeLaunchProfile
        let (exe, args) = terminalJcodeLaunchCommand(
            profile: profile,
            projectRoot: projectSettings.projectRoot,
            workingDirectoryOverride: workingDirectory
        )
        let count = tabs.filter { $0.executable == exe }.count + 1
        let tab = TermTab(title: titleOverride ?? "agent \(count)", executable: exe, args: args)
        tabs.append(tab)
        activeId = tab.id
    }

    func addZshTab(workingDirectory: String? = nil, titleOverride: String? = nil) {
        let count = tabs.filter { $0.executable == "/bin/zsh" }.count + 1
        let tab = TermTab(
            title: titleOverride ?? terminalShellTitle(prefix: "zsh", index: count, workingDirectory: workingDirectory),
            executable: "/bin/zsh",
            args: terminalShellArgs(for: "/bin/zsh", workingDirectory: workingDirectory)
        )
        tabs.append(tab)
        activeId = tab.id
    }

    func addBashTab(workingDirectory: String? = nil, titleOverride: String? = nil) {
        let count = tabs.filter { $0.executable == "/bin/bash" }.count + 1
        let tab = TermTab(
            title: titleOverride ?? terminalShellTitle(prefix: "bash", index: count, workingDirectory: workingDirectory),
            executable: "/bin/bash",
            args: terminalShellArgs(for: "/bin/bash", workingDirectory: workingDirectory)
        )
        tabs.append(tab)
        activeId = tab.id
    }

    func addTmuxTab(workingDirectory: String? = nil, titleOverride: String? = nil) {
        guard let tmux = tmuxExecutable() else { return }
        let count = tabs.filter { $0.title.hasPrefix("tmux") }.count + 1
        let sessionName = "gg-ide-\(count)"
        var args = ["new-session", "-A", "-s", sessionName]
        if let workingDirectory,
           FileManager.default.fileExists(atPath: workingDirectory) {
            args += ["-c", workingDirectory]
        }
        let tab = TermTab(
            title: titleOverride ?? terminalShellTitle(prefix: "tmux", index: count, workingDirectory: workingDirectory),
            executable: tmux,
            args: args
        )
        tabs.append(tab)
        activeId = tab.id
    }

    func removeTab(_ id: UUID) {
        TerminalSessionStore.shared.remove(id)
        tabs.removeAll { $0.id == id }
        if activeId == id {
            activeId = tabs.last?.id
        }
    }
}

private struct TerminalSurfaceView: View {
    @EnvironmentObject private var shell: AppShellState
    @ObservedObject private var projectSettings = ProjectSettings.shared
    @ObservedObject var model: TerminalSurfaceModel
    let showsLaunchProfileControl: Bool
    let emptyStateText: String

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            tabContent
        }
        .background(Color.black)
        .onAppear {
            model.ensureReady(shell: shell, projectSettings: projectSettings)
        }
        .onChange(of: shell.pendingTerminalLaunch?.id) { _, _ in
            _ = model.consumePendingLaunch(from: shell, projectSettings: projectSettings)
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.tabs) { tab in tabPill(tab) }
                }
            }
            Button {
                model.addZshTab()
            } label: {
                Label("zsh", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .help("New zsh shell")

            Menu {
                Button("New zsh Shell") { model.addZshTab() }
                Button("New bash Shell") { model.addBashTab() }
                Button("New tmux Session") { model.addTmuxTab() }
                    .disabled(!model.tmuxAvailable)
                Divider()
                Button("New Agent Session") {
                    model.addAgentSessionTab(projectSettings: projectSettings)
                }
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(8)
            }
            .menuStyle(.borderlessButton)
            .help("Open shell and runtime session options")

            if showsLaunchProfileControl {
                Button {
                    model.showLaunchProfile = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .help("Edit agent session profile")
                .popover(isPresented: $model.showLaunchProfile) {
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
            }

            if !model.tmuxAvailable {
                Text("tmux unavailable")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
        .frame(height: 34)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func tabPill(_ t: TermTab) -> some View {
        let active = t.id == model.activeId
        HStack(spacing: 5) {
            Text(t.title)
                .font(.system(size: 11, weight: active ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(active ? .white : .secondary)

            Button {
                model.removeTab(t.id)
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
        .onTapGesture { model.activeId = t.id }
    }

    // MARK: Content

    @ViewBuilder
    private var tabContent: some View {
        if let t = model.tabs.first(where: { $0.id == model.activeId }) {
            EmbeddedTerminal(tabId: t.id, executable: t.executable, args: t.args)
        } else {
            ZStack {
                Color.black
                Text(emptyStateText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TerminalTabView: View {
    @StateObject private var model = TerminalSurfaceModel(
        launchDestination: .terminalTab,
        seedsDefaultShell: true
    )

    var body: some View {
        TerminalSurfaceView(
            model: model,
            showsLaunchProfileControl: true,
            emptyStateText: "Open a shell session to start working"
        )
    }
}

struct IDETerminalCollapsedBar: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore

    let workspaceRootPath: String
    let selectedRunRootPath: String?

    var body: some View {
        HStack(spacing: 10) {
            Label("Terminal Dock", systemImage: "rectangle.bottomthird.inset.filled")
                .font(.system(size: 12, weight: .semibold))

            Text(contextSummary)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            dockButton("Workspace", systemImage: "terminal") {
                launchDockTerminal(preset: .zsh, workingDirectory: validatedPath(workspaceRootPath), title: "zsh • workspace")
            }

            if let selectedRunRootPath = validatedPath(selectedRunRootPath) {
                dockButton("Run", systemImage: "play.circle") {
                    launchDockTerminal(preset: .zsh, workingDirectory: selectedRunRootPath, title: "zsh • run")
                }

                dockButton("Agent", systemImage: "sparkles") {
                    launchDockTerminal(preset: .agent, workingDirectory: selectedRunRootPath, title: "agent • run")
                }
            }

            Button("Terminal Page") {
                shell.selectedTab = .terminal
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(Color(white: 0.05))
    }

    private var contextSummary: String {
        if let runId = workflow.selectedRunId, !runId.isEmpty {
            return "Selected run: \(runId)"
        }
        if let task = workflow.selectedTaskTitle, !task.isEmpty {
            return task
        }
        return "Open a workspace, run, or agent session without leaving the current pane."
    }

    private func dockButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func launchDockTerminal(
        preset: TerminalSessionPreset,
        workingDirectory: String?,
        title: String
    ) {
        UIActionBus.perform(
            .launchTerminal(
                preset: preset,
                workingDirectory: workingDirectory,
                title: title,
                destination: .workspaceDock
            ),
            shell: shell,
            workflow: workflow
        )
    }

    private func validatedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct IDETerminalDockView: View {
    @EnvironmentObject private var shell: AppShellState
    @EnvironmentObject private var workflow: WorkflowContextStore
    @StateObject private var model = TerminalSurfaceModel(
        launchDestination: .workspaceDock,
        seedsDefaultShell: false
    )

    let workspaceRootPath: String
    let selectedRunRootPath: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalSurfaceView(
                model: model,
                showsLaunchProfileControl: false,
                emptyStateText: "Launch a workspace, run, or agent session from the dock controls."
            )
        }
        .background(Color(white: 0.04))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Terminal Dock", systemImage: "rectangle.bottomthird.inset.filled")
                .font(.system(size: 12, weight: .semibold))

            if let runId = workflow.selectedRunId, !runId.isEmpty {
                contextBadge("Run \(runId)")
            }
            if let task = workflow.selectedTaskTitle, !task.isEmpty {
                contextBadge(task)
            }
            if let focusedWorktree = validatedPath(shell.focusedWorktreePath) {
                contextBadge(URL(fileURLWithPath: focusedWorktree).lastPathComponent)
            }

            Spacer()

            dockButton("Workspace", systemImage: "terminal") {
                launchDockTerminal(preset: .zsh, workingDirectory: validatedPath(workspaceRootPath), title: "zsh • workspace")
            }

            if let selectedRunRootPath = validatedPath(selectedRunRootPath) {
                dockButton("Run", systemImage: "play.circle") {
                    launchDockTerminal(preset: .zsh, workingDirectory: selectedRunRootPath, title: "zsh • run")
                }
                dockButton("Agent", systemImage: "sparkles") {
                    launchDockTerminal(preset: .agent, workingDirectory: selectedRunRootPath, title: "agent • run")
                }
            }

            if let focusedWorktree = validatedPath(shell.focusedWorktreePath) {
                dockButton("Focused Tree", systemImage: "square.stack.3d.down.forward") {
                    launchDockTerminal(
                        preset: .zsh,
                        workingDirectory: focusedWorktree,
                        title: "zsh • \(URL(fileURLWithPath: focusedWorktree).lastPathComponent)"
                    )
                }
            }

            Button("Terminal Page") {
                shell.selectedTab = .terminal
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)

            Button {
                shell.hideIDETerminalDock()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Hide terminal dock")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.05))
    }

    private func contextBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
            )
    }

    private func dockButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func launchDockTerminal(
        preset: TerminalSessionPreset,
        workingDirectory: String?,
        title: String
    ) {
        UIActionBus.perform(
            .launchTerminal(
                preset: preset,
                workingDirectory: workingDirectory,
                title: title,
                destination: .workspaceDock
            ),
            shell: shell,
            workflow: workflow
        )
    }

    private func validatedPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func terminalJcodeLaunchCommand(
    profile: ProjectSettings.JCodeLaunchProfile,
    projectRoot: String,
    workingDirectoryOverride: String? = nil
) -> (String, [String]) {
    let wrapperPath = projectRoot + "/tools/gg-cli/gg-cli.sh"
    let canUseWrapper = profile.useWrapper && FileManager.default.isExecutableFile(atPath: wrapperPath)
    let jcodePath = jcodeExecutable(projectRoot: projectRoot)

    if !canUseWrapper && !jcodePath.hasSuffix("jcode") {
        return ("/bin/zsh", ["-l"])
    }

    var args: [String] = []

    if let cwd = terminalResolvedWorkingDirectory(
        profile: profile,
        projectRoot: projectRoot,
        workingDirectoryOverride: workingDirectoryOverride
    ) {
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

private func terminalResolvedWorkingDirectory(
    profile: ProjectSettings.JCodeLaunchProfile,
    projectRoot: String,
    workingDirectoryOverride: String? = nil
) -> String? {
    let override = workingDirectoryOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !override.isEmpty, FileManager.default.fileExists(atPath: override) {
        return override
    }

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

private func terminalShellArgs(for executable: String, workingDirectory: String?) -> [String] {
    guard let workingDirectory,
          FileManager.default.fileExists(atPath: workingDirectory) else {
        return ["-l"]
    }
    let escaped = terminalShellEscape(workingDirectory)
    return ["-lc", "cd -- '\(escaped)'; exec \(executable) -l"]
}

private func terminalShellEscape(_ value: String) -> String {
    value.replacingOccurrences(of: "'", with: "'\"'\"'")
}

private func terminalShellTitle(prefix: String, index: Int, workingDirectory: String?) -> String {
    guard let workingDirectory,
          !workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return "\(prefix) \(index)"
    }
    let leaf = URL(fileURLWithPath: workingDirectory).lastPathComponent
    return leaf.isEmpty ? "\(prefix) \(index)" : "\(prefix) • \(leaf)"
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
            Text("Agent Session Profile")
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

// PackagesTabView.swift — GitHub repo package manager + recommended tools

import SwiftUI

struct PackagesTabView: View {
    @StateObject private var pm       = PackageManager.shared
    @StateObject private var registry = PackageRegistry.shared
    @StateObject private var rtm      = RecommendedToolManager.shared

    @State private var inputURL       = ""
    @State private var isInstalling   = false
    @State private var confirmUninstall: GGASPackage? = nil
    @State private var searchText     = ""

    private var filteredPackages: [GGASPackage] {
        guard !searchText.isEmpty else { return registry.packages }
        return registry.packages.filter {
            $0.id.localizedCaseInsensitiveContains(searchText) ||
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.manifest.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VSplitView {
            // ── Top: installed repos + recommended tools ──────────────────
            ScrollView {
                VStack(spacing: 0) {
                    installBar
                    Divider()

                    // Installed repo packages
                    if registry.packages.isEmpty {
                        emptyState
                    } else {
                        repoSection
                    }

                    Divider().padding(.vertical, 4)

                    // Recommended packages section
                    recommendedSection
                }
            }
            .frame(minHeight: 280)

            // ── Bottom: activity log ─────────────────────────────────────
            logPanel
                .frame(minHeight: 140, maxHeight: 260)
        }
        .alert("Uninstall \(confirmUninstall?.displayName ?? "")?",
               isPresented: .constant(confirmUninstall != nil)) {
            Button("Uninstall", role: .destructive) {
                guard let pkg = confirmUninstall else { return }
                confirmUninstall = nil
                Task { await pm.uninstall(pkg: pkg) }
            }
            Button("Cancel", role: .cancel) { confirmUninstall = nil }
        } message: {
            Text("This will remove all installed skills, workflows, agent personas, and MCP servers from this package.")
        }
        .task {
            // Pre-install Docker MCP + GitHub MCP on first launch
            rtm.preInstallIfNeeded()
            // Refresh installed status for all recommended tools
            rtm.refreshStatus()
        }
    }

    // MARK: - Install bar

    private var installBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(.blue)

            TextField("github.com/owner/repo  or  owner/repo", text: $inputURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { triggerInstall() }
                .autocorrectionDisabled()

            Button {
                triggerInstall()
            } label: {
                if pm.isBusy {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.7)
                        Text(pm.busyLabel).font(.caption)
                    }
                } else {
                    Label("Install", systemImage: "arrow.down.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pm.isBusy)
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Installed repos section

    private var repoSection: some View {
        VStack(spacing: 0) {
            // Search + count
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter packages", text: $searchText).textFieldStyle(.plain)
                Spacer()
                Text("\(registry.packages.count) installed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ForEach(filteredPackages) { pkg in
                packageRow(pkg)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                Divider().padding(.leading, 56)
            }
        }
    }

    @ViewBuilder
    private func packageRow(_ pkg: GGASPackage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 36, height: 36)
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.blue).font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pkg.displayName).font(.system(size: 13, weight: .semibold))
                    Text(pkg.id).font(.caption).foregroundStyle(.secondary)
                }
                if !pkg.manifest.description.isEmpty {
                    Text(pkg.manifest.description)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    if !pkg.installedFiles.skills.isEmpty    { badge("\(pkg.installedFiles.skills.count) skills",    color: .purple) }
                    if !pkg.installedFiles.workflows.isEmpty { badge("\(pkg.installedFiles.workflows.count) workflows", color: .blue) }
                    if !pkg.installedFiles.agents.isEmpty    { badge("\(pkg.installedFiles.agents.count) agents",    color: .green) }
                    if !pkg.installedFiles.mcpServers.isEmpty{ badge("\(pkg.installedFiles.mcpServers.count) MCP",   color: .orange) }
                }.padding(.top, 2)
                Text("Installed \(pkg.installedAt.formatted(.relative(presentation: .named))) · Updated \(pkg.lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.caption2).foregroundStyle(.tertiary).padding(.top, 1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Button { Task { await pm.update(pkg: pkg) } }
                    label: { Label("Update", systemImage: "arrow.clockwise").font(.caption) }
                    .buttonStyle(.bordered).disabled(pm.isBusy)
                Button { Task { await pm.reinstall(pkg: pkg) } }
                    label: { Label("Reinstall", systemImage: "arrow.2.circlepath").font(.caption) }
                    .buttonStyle(.bordered).disabled(pm.isBusy)
                Button(role: .destructive) { confirmUninstall = pkg }
                    label: { Label("Uninstall", systemImage: "trash").font(.caption) }
                    .buttonStyle(.bordered).disabled(pm.isBusy)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recommended section

    private var recommendedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                Text("Recommended Packages")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button { rtm.refreshStatus() } label: {
                    Image(systemName: "arrow.clockwise").font(.caption2)
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Refresh install status")
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Group by category
            let categories: [RecommendedCategory] = [.cli, .mcp]
            ForEach(categories, id: \.rawValue) { cat in
                let tools = RecommendedTool.catalogue.filter { $0.category == cat }

                // Category label
                Text(cat.rawValue.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)

                ForEach(tools) { tool in
                    recommendedRow(tool)
                    Divider().padding(.leading, 56)
                }
            }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func recommendedRow(_ tool: RecommendedTool) -> some View {
        let installed = rtm.isInstalled(tool.id)
        let busy      = rtm.busyID == tool.id

        HStack(alignment: .center, spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tool.iconColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: tool.icon)
                    .foregroundStyle(tool.iconColor)
                    .font(.system(size: 15))
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.name).font(.system(size: 13, weight: .semibold))
                    if tool.preInstalled {
                        badge("pre-installed", color: .blue)
                    }
                    if tool.category == .mcp {
                        badge("MCP", color: .orange)
                    }
                }
                Text(tool.description)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }

            Spacer()

            // Status + actions
            if busy {
                ProgressView().scaleEffect(0.7)
            } else if installed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption)
                    Button(role: .destructive) {
                        Task { await rtm.uninstall(tool) }
                    } label: {
                        Text("Uninstall").font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    Task { await rtm.install(tool) }
                } label: {
                    Label("Install", systemImage: "arrow.down.circle").font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(rtm.busyID != nil)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    // MARK: - Badge helper

    @ViewBuilder
    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48)).foregroundStyle(.quaternary)
            Text("No Packages Installed").font(.title3.bold())
            Text("Paste a GitHub URL above to install an extension package.\nSkills, workflows, agents, and MCP servers are installed automatically.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Divider().frame(maxWidth: 300)
            VStack(alignment: .leading, spacing: 4) {
                label("github.com/owner/repo")
                label("owner/repo")
                label("https://github.com/owner/repo.git")
            }
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
    }

    @ViewBuilder
    private func label(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption2)
            Text(text)
        }
    }

    // MARK: - Log panel

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal.fill").foregroundStyle(.secondary).font(.caption)
                Text("Activity Log").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { pm.clearLog() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(pm.log) { line in
                            Text(line.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.isError ? Color.red : Color.green)
                                .textSelection(.enabled)
                                .id(line.id)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                        }
                    }.padding(.vertical, 4)
                }
                .background(Color.black.opacity(0.88))
                .onChange(of: pm.log.count) { _, _ in
                    if let last = pm.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Helpers

    private func triggerInstall() {
        let url = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, !pm.isBusy else { return }
        isInstalling = true
        Task {
            await pm.install(url: url)
            inputURL = ""
            isInstalling = false
        }
    }
}

// MARK: - Sidebar nav item shim

extension PackagesTabView {
    static var navItem: (label: String, icon: String, tag: String) {
        ("Packages", "shippingbox.fill", "packages")
    }
}

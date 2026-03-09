// LMStudioManagerView.swift — Full LM Studio model management panel.
// 4-tab layout: Loaded | Library | Browse (live catalog) | Settings

import SwiftUI

// MARK: - ViewModel

@MainActor
final class LMStudioManagerVM: ObservableObject {

    // Tab
    enum Tab: String, CaseIterable {
        case loaded  = "Loaded"
        case library = "Library"
        case browse  = "Browse"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .loaded:   return "memorychip"
            case .library:  return "internaldrive"
            case .browse:   return "globe"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    @Published var activeTab: Tab = .library
    @Published var loadedModels: [LMStudioModel] = []
    @Published var libraryModels: [LMStudioModel] = []
    @Published var activeDownloads: [DownloadProgress] = []
    @Published var isRefreshing = false
    @Published var isStartingServer = false
    @Published var error: String?

    // Browse tab
    @Published var searchQuery: String = ""
    @Published var categoryFilter: CatalogModel.Category? = nil
    @Published var selectedModel: CatalogModel?
    @Published var showConfigDrawer = false
    @Published var configDrawerModelId: String = ""

    // Delete confirm
    @Published var modelToDelete: LMStudioModel?
    @Published var showDeleteConfirm = false

    // URL paste
    @Published var urlPasteText: String = ""

    private var endpoint: String {
        CoordinatorManager.shared.coordinators
            .first { $0.type == .lmStudio }?.endpoint ?? "http://localhost:1234"
    }

    func refresh() async {
        isRefreshing = true
        error = nil
        let all = await LMStudioEngine.shared.listModels(endpoint: endpoint)
        loadedModels  = all.filter { $0.isLoaded }
        libraryModels = all.filter { !$0.isLoaded }
        isRefreshing  = false
    }

    func startServer() async {
        isStartingServer = true
        defer { isStartingServer = false }
        let started = await LMStudioEngine.shared.startLocalServer(endpoint: endpoint)
        if !started {
            error = "Unable to start LM Studio automatically. Launch it manually or install the lms CLI."
            return
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await refresh()
    }

    func loadModel(_ id: String) async {
        do {
            try await LMStudioEngine.shared.loadModel(id: id, endpoint: endpoint)
            await refresh()
            CoordinatorManager.shared.updateLMStudioModel(id: id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unloadModel(_ id: String) async {
        do {
            try await LMStudioEngine.shared.unloadModel(id: id, endpoint: endpoint)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func confirmDelete(_ model: LMStudioModel) {
        modelToDelete = model
        showDeleteConfirm = true
    }

    func deleteModel() async {
        guard let model = modelToDelete else { return }
        do {
            try await LMStudioEngine.shared.deleteModel(id: model.id, endpoint: endpoint)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
        modelToDelete = nil
        showDeleteConfirm = false
    }

    func downloadCatalogModel(_ model: CatalogModel) async {
        let key = model.id
        var prog = DownloadProgress(id: key, modelName: model.name,
                                    fraction: 0, statusText: "Starting…",
                                    isComplete: false, error: nil)
        activeDownloads.append(prog)

        do {
            try await ModelManagementService.shared.download(model: model) { [weak self] update in
                guard let self else { return }
                if let idx = self.activeDownloads.firstIndex(where: { $0.id == key }) {
                    self.activeDownloads[idx] = update
                }
                if update.isComplete {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        self.activeDownloads.removeAll { $0.id == key }
                        await self.refresh()
                    }
                }
            }
        } catch {
            prog.error = error.localizedDescription
            prog.statusText = "Failed"
            if let idx = activeDownloads.firstIndex(where: { $0.id == key }) {
                activeDownloads[idx] = prog
            }
            self.error = error.localizedDescription
        }
    }

    func downloadFromURL() async {
        let text = urlPasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let model = LMStudioCatalogService.shared.parseURL(text) {
            await downloadCatalogModel(model)
            urlPasteText = ""
        } else {
            error = "Could not parse URL. Paste a HuggingFace model URL."
        }
    }

    func openConfig(modelId: String) {
        configDrawerModelId = modelId
        showConfigDrawer = true
    }

    func useModel(_ id: String) {
        CoordinatorManager.shared.updateLMStudioModel(id: id)
    }

    var filteredBrowseResults: [CatalogModel] {
        let catalog = LMStudioCatalogService.shared
        let base = searchQuery.isEmpty ? catalog.featuredModels : catalog.searchResults
        guard let cat = categoryFilter else { return base }
        return base.filter { $0.category == cat }
    }

    var endpoint_: String { endpoint }
}

// MARK: - Main View

struct LMStudioManagerView: View {
    let initialSearchQuery: String?
    @StateObject private var vm = LMStudioManagerVM()
    @ObservedObject private var catalog = LMStudioCatalogService.shared
    @ObservedObject private var mgmt = ModelManagementService.shared
    @Environment(\.dismiss) private var dismiss

    init(initialSearchQuery: String? = nil) {
        self.initialSearchQuery = initialSearchQuery
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                Divider()
                contentArea
                if vm.showConfigDrawer {
                    Divider()
                    configPanel
                }
            }
            if !vm.activeDownloads.isEmpty {
                downloadStrip
            }
        }
        .frame(width: vm.showConfigDrawer ? 900 : 680, height: 560)
        .background(Color(white: 0.08))
        .foregroundStyle(.primary)
        .confirmationDialog(
            "Delete \"\(vm.modelToDelete?.shortName ?? "")\"?",
            isPresented: $vm.showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete from Disk", role: .destructive) {
                Task { await vm.deleteModel() }
            }
            Button("Cancel", role: .cancel) {
                vm.modelToDelete = nil
            }
        } message: {
            Text("This permanently removes the model file from your disk. This cannot be undone.")
        }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("OK", role: .cancel) { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
        .task {
            await vm.refresh()
            await catalog.fetchFeatured()
            mgmt.startStatsPolling(endpoint: vm.endpoint_)
            if let initialSearchQuery,
               !initialSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                vm.activeTab = .browse
                vm.searchQuery = initialSearchQuery
                catalog.search(query: initialSearchQuery)
            }
        }
        .onDisappear { mgmt.stopStatsPolling() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.94, green: 0.72, blue: 0.18))
            Text("LM Studio Models")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            // VRAM indicator
            if let stats = mgmt.systemStats, stats.gpuVramTotalMB > 0 {
                VRAMBadge(stats: stats)
            }
            Button {
                Task { await vm.refresh() }
            } label: {
                Image(systemName: vm.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .rotationEffect(vm.isRefreshing ? .degrees(360) : .zero)
                    .animation(vm.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: vm.isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Refresh model list")

            Button {
                Task { await vm.startServer() }
            } label: {
                Image(systemName: vm.isStartingServer ? "play.circle.fill" : "play.circle")
            }
            .buttonStyle(.plain)
            .disabled(vm.isStartingServer)
            .help("Start LM Studio explicitly")

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Sidebar tabs

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(LMStudioManagerVM.Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
            Spacer()
            // Catalog cache status
            VStack(alignment: .leading, spacing: 3) {
                Text("CATALOG")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Button("Refresh Cache") {
                    LMStudioCatalogService.shared.clearCache()
                    Task { await LMStudioCatalogService.shared.fetchFeatured() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(width: 130)
    }

    private func tabButton(_ tab: LMStudioManagerVM.Tab) -> some View {
        Button {
            vm.activeTab = tab
            if tab == .browse && catalog.featuredModels.isEmpty {
                Task { await catalog.fetchFeatured() }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .frame(width: 16)
                Text(tab.rawValue)
                    .font(.system(size: 12))
                Spacer()
                if tab == .loaded {
                    let count = vm.loadedModels.count
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(
                                Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.2)))
                            .foregroundStyle(Color(red: 0.94, green: 0.72, blue: 0.18))
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(vm.activeTab == tab ? Color(white: 0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(vm.activeTab == tab ? .primary : .secondary)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch vm.activeTab {
        case .loaded:   loadedTab
        case .library:  libraryTab
        case .browse:   browseTab
        case .settings: settingsTab
        }
    }

    // MARK: - Loaded Tab

    private var loadedTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let stats = mgmt.systemStats, stats.gpuVramTotalMB > 0 {
                VRAMBar(stats: stats)
                    .padding(14)
                Divider()
            }
            if vm.loadedModels.isEmpty {
                emptyState(icon: "memorychip", title: "No models loaded",
                           message: "Load a model from the Library tab to use it.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(vm.loadedModels) { model in
                            LoadedModelRow(model: model,
                                          onUnload: { Task { await vm.unloadModel(model.id) } },
                                          onUse: { vm.useModel(model.id) },
                                          onConfigure: { vm.openConfig(modelId: model.id) })
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Library Tab

    private var libraryTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            if vm.libraryModels.isEmpty && !vm.isRefreshing {
                emptyState(icon: "internaldrive", title: "No models downloaded",
                           message: "Use the Browse tab to download models from LM Studio or HuggingFace.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(vm.libraryModels) { model in
                            LibraryModelRow(model: model,
                                            onLoad: { Task { await vm.loadModel(model.id) } },
                                            onDelete: { vm.confirmDelete(model) },
                                            onConfigure: { vm.openConfig(modelId: model.id) })
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Browse Tab

    private var browseTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search + URL paste bar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search models (e.g. Qwen, Llama, DeepSeek…)", text: $vm.searchQuery)
                        .textFieldStyle(.plain)
                        .onChange(of: vm.searchQuery) { _, q in
                            catalog.search(query: q)
                        }
                    if !vm.searchQuery.isEmpty {
                        Button { vm.searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                    if catalog.isSearching {
                        ProgressView().scaleEffect(0.6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))

                // URL paste
                HStack(spacing: 8) {
                    Image(systemName: "link").foregroundStyle(.secondary).font(.system(size: 11))
                    TextField("Paste HuggingFace or LM Studio model URL…", text: $vm.urlPasteText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    Button("Download") {
                        Task { await vm.downloadFromURL() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(vm.urlPasteText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.10)))

                if let message = catalog.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(red: 0.94, green: 0.72, blue: 0.18))
                            .font(.system(size: 11))
                        Text(message)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Button("Retry") {
                            Task { await catalog.fetchFeatured() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.30), lineWidth: 1)
                    )
                }
            }
            .padding(12)
            Divider()

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(nil, label: "All")
                    ForEach(CatalogModel.Category.allCases, id: \.self) { cat in
                        categoryChip(cat, label: cat.rawValue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            Divider()

            // Results
            if catalog.isLoading {
                ProgressView("Loading catalog…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filteredBrowseResults.isEmpty {
                emptyState(icon: "globe", title: "No results",
                           message: !vm.searchQuery.isEmpty
                                ? "Try a different search term."
                                : "Catalog is loading. Check your internet connection if this persists.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(vm.filteredBrowseResults) { model in
                            CatalogModelRow(
                                model: model,
                                isInstalled: vm.libraryModels.contains(where: { installed in
                                    installed.id.localizedCaseInsensitiveContains(model.id)
                                        || installed.id.localizedCaseInsensitiveContains(model.filename)
                                        || installed.id.localizedCaseInsensitiveContains(model.repo)
                                }),
                                isDownloading: vm.activeDownloads.contains(where: { $0.id == model.id }),
                                onDownload: { Task { await vm.downloadCatalogModel(model) } }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ── System Resources (HardwareTopologyService) ─────────────────
                systemResourcesSection

                // ── Global Inference Defaults ──────────────────────────────────
                Text("GLOBAL INFERENCE DEFAULTS")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)

                Group {
                    let mgr = CoordinatorManager.shared
                    paramSlider("Temperature", value: Binding(
                        get: { mgr.lmSettings.temperature },
                        set: { mgr.lmSettings.temperature = $0 }
                    ), in: 0...2, format: "%.2f")
                    paramSlider("Top-P", value: Binding(
                        get: { mgr.lmSettings.topP },
                        set: { mgr.lmSettings.topP = $0 }
                    ), in: 0...1, format: "%.2f")
                    HStack {
                        Label("Max Tokens", systemImage: "number").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Stepper("\(mgr.lmSettings.maxTokens)",
                                value: Binding(
                                    get: { mgr.lmSettings.maxTokens },
                                    set: { mgr.lmSettings.maxTokens = $0 }
                                ),
                                in: 256...32768, step: 256)
                        .font(.system(size: 11))
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.10)))

                Text("SYSTEM PROMPT OVERRIDE")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.top, 4)

                CommandTextEditor(text: Binding(
                    get: { CoordinatorManager.shared.lmSettings.systemPromptOverride },
                    set: { CoordinatorManager.shared.lmSettings.systemPromptOverride = $0 }
                ), placeholder: "Leave empty to use GGAS default prompt")
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

                Text("ENDPOINT")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.top, 4)

                if let idx = CoordinatorManager.shared.coordinators.firstIndex(where: { $0.type == .lmStudio }) {
                    TextField("http://localhost:1234",
                              text: Binding(
                                get: { CoordinatorManager.shared.coordinators[idx].endpoint },
                                set: { CoordinatorManager.shared.coordinators[idx].endpoint = $0 }
                              ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                }
            }
            .padding(16)
        }
    }

    // MARK: - System Resources Panel

    @ObservedObject private var hwTopology = HardwareTopologyService.shared

    private var systemResourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("SYSTEM RESOURCES", systemImage: "cpu")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await HardwareTopologyService.shared.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            // RAM bars
            VStack(alignment: .leading, spacing: 8) {
                ramBar(label: "Total RAM",
                       usedGB: hwTopology.totalRAMGB - hwTopology.availableRAMGB,
                       totalGB: hwTopology.totalRAMGB,
                       color: .secondary)
                ramBar(label: "Available RAM",
                       usedGB: hwTopology.availableRAMGB,
                       totalGB: hwTopology.totalRAMGB,
                       color: Color(red: 0.0, green: 0.88, blue: 0.45))
            }

            Divider().opacity(0.4)

            // Agent capacity
            let cap = hwTopology.maxConcurrentAgents()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAX CONCURRENT AGENTS")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(cap.maxConcurrentAgents)")
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(capacityColor(cap.maxConcurrentAgents))
                        Text("agents")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(cap.note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    capacityMetric("Available", String(format: "%.1f GB", cap.availableRAMGB))
                    capacityMetric("Reserved", String(format: "%.1f GB", cap.reservedRAMGB))
                    capacityMetric("Per-Agent", String(format: "%.1f GB", cap.perAgentRAMGB))
                }
            }

            // Thunderbolt / network interfaces
            if !hwTopology.interfaces.isEmpty {
                Divider().opacity(0.4)
                Text("NETWORK INTERFACES")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    ForEach(hwTopology.interfaces) { iface in
                        interfaceBadge(iface)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.10)))
    }

    private func ramBar(label: String, usedGB: Double, totalGB: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f / %.1f GB", usedGB, totalGB))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.18)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: totalGB > 0
                               ? geo.size.width * CGFloat(min(usedGB / totalGB, 1.0))
                               : 0, height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    private func capacityMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
    }

    private func capacityColor(_ n: Int) -> Color {
        if n >= 10 { return Color(red: 0.0, green: 0.88, blue: 0.45) }
        if n >= 4  { return Color(red: 0.94, green: 0.72, blue: 0.18) }
        return .red
    }

    private func interfaceBadge(_ iface: NetworkInterface) -> some View {
        let color: Color = iface.isThunderbolt
            ? Color(red: 0.94, green: 0.72, blue: 0.18)
            : iface.isWifi ? Color(red: 0.20, green: 0.75, blue: 1.00) : .secondary
        let icon = iface.isThunderbolt ? "bolt.fill"
            : iface.isWifi ? "wifi" : "network"
        return Label(iface.displayName, systemImage: icon)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }



    private func paramSlider(_ label: String, value: Binding<Double>,
                              in range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: - Config Panel

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Configure Model")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { vm.showConfigDrawer = false } label: {
                    Image(systemName: "xmark").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(12)
            Divider()
            ModelConfigDrawer(modelId: vm.configDrawerModelId)
        }
        .frame(width: 220)
        .background(Color(white: 0.10))
    }

    // MARK: - Download Strip

    private var downloadStrip: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.activeDownloads) { prog in
                        DownloadCard(progress: prog)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(Color(white: 0.06))
        }
    }

    // MARK: - Helper components

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.4))
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func categoryChip(_ category: CatalogModel.Category?, label: String) -> some View {
        Button {
            vm.categoryFilter = category
        } label: {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(vm.categoryFilter == category
                        ? Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.25)
                        : Color(white: 0.16))
                )
                .overlay(Capsule().stroke(
                    vm.categoryFilter == category
                        ? Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.5)
                        : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(vm.categoryFilter == category ? Color(red: 0.94, green: 0.72, blue: 0.18) : .secondary)
    }
}

// MARK: - Loaded Model Row

struct LoadedModelRow: View {
    let model: LMStudioModel
    let onUnload: () -> Void
    let onUse: () -> Void
    let onConfigure: () -> Void

    @ObservedObject private var coordMgr = CoordinatorManager.shared
    private var isActive: Bool {
        coordMgr.coordinators.first { $0.type == .lmStudio }?.model == model.id
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.typeIcon)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.0, green: 0.88, blue: 0.45))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ModelUserConfigStore.shared.config(for: model.id).displayName)
                        .font(.system(size: 12, weight: .semibold))
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.2)))
                            .foregroundStyle(Color(red: 0.94, green: 0.72, blue: 0.18))
                    }
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
                if let ctx = model.contextLabel {
                    Text(ctx + " context").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Button("Use") { onUse() }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(isActive)
                Button("Configure") { onConfigure() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Unload") { onUnload() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.7))
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
    }
}

// MARK: - Library Model Row

struct LibraryModelRow: View {
    let model: LMStudioModel
    let onLoad: () -> Void
    let onDelete: () -> Void
    let onConfigure: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.typeIcon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelUserConfigStore.shared.config(for: model.id).displayName)
                    .font(.system(size: 12, weight: .semibold))
                if let ctx = model.contextLabel {
                    Text(ctx + " context · " + (model.publisher ?? ""))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Button("Configure") { onConfigure() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button { onDelete() } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete from disk")
                Button("Load") { onLoad() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.85))
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.10)))
    }
}

// MARK: - Catalog Model Row

struct CatalogModelRow: View {
    let model: CatalogModel
    let isInstalled: Bool
    let isDownloading: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.category.icon)
                .font(.system(size: 13))
                .foregroundStyle(categoryColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.paramCount)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(categoryColor.opacity(0.15)))
                        .foregroundStyle(categoryColor)
                    Text(model.quantization)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Text(model.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Label(model.sizeLabel, systemImage: "internaldrive")
                    if model.contextK > 0 {
                        Label("\(model.contextK)K ctx", systemImage: "arrow.left.and.right")
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(Color.secondary.opacity(0.7))
            }
            Spacer()
            VStack(spacing: 4) {
                if isInstalled {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                } else if isDownloading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Button("Download") { onDownload() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.94, green: 0.72, blue: 0.18).opacity(0.9))
                        .controlSize(.small)
                }
                Text(model.sizeLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.10)))
    }

    private var categoryColor: Color {
        switch model.category {
        case .coding:     return Color(red: 0.20, green: 0.75, blue: 1.00)
        case .general:    return Color(red: 0.0, green: 0.88, blue: 0.45)
        case .reasoning:  return Color(red: 0.94, green: 0.72, blue: 0.18)
        case .multimodal: return Color(red: 0.73, green: 0.53, blue: 1.00)
        case .embedding:  return Color(red: 0.90, green: 0.45, blue: 0.20)
        case .tools:      return Color(red: 0.50, green: 0.85, blue: 0.50)
        }
    }
}

// MARK: - VRAM Bar

struct VRAMBadge: View {
    let stats: LMSystemStats
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "memorychip")
                .font(.system(size: 10))
                .foregroundStyle(vramColor)
            Text("GPU \(stats.vramLabel)")
                .font(.system(size: 10))
                .foregroundStyle(vramColor)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(vramColor.opacity(0.12)))
    }
    private var vramColor: Color {
        stats.vramFraction > 0.85 ? .red
            : stats.vramFraction > 0.60 ? Color(red: 0.94, green: 0.72, blue: 0.18)
            : Color(red: 0.0, green: 0.88, blue: 0.45)
    }
}

struct VRAMBar: View {
    let stats: LMSystemStats
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if stats.gpuVramTotalMB > 0 {
                resourceBar("GPU VRAM", fraction: stats.vramFraction,
                             valueLabel: stats.vramLabel,
                             color: stats.vramFraction > 0.85 ? .red
                                : stats.vramFraction > 0.60 ? Color(red: 0.94, green: 0.72, blue: 0.18)
                                : Color(red: 0.0, green: 0.88, blue: 0.45))
            }
            if stats.systemRamTotalMB > 0 {
                resourceBar("System RAM", fraction: stats.ramFraction,
                             valueLabel: stats.ramLabel,
                             color: .secondary)
            }
        }
    }

    private func resourceBar(_ title: String, fraction: Double, valueLabel: String = "",
                               color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(valueLabel).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.18)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(fraction, 1.0)), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Download Card

struct DownloadCard: View {
    let progress: DownloadProgress
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(progress.modelName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(progress.error ?? progress.statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(progress.error != nil ? .red : .secondary)
            }
            VStack(alignment: .trailing, spacing: 3) {
                if progress.isComplete {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if progress.error != nil {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                } else {
                    ProgressView(value: progress.fraction)
                        .frame(width: 80)
                    Text("\(Int(progress.fraction * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.13)))
        .frame(minWidth: 200)
    }
}

// MARK: - FlowLayout (wrapping HStack for interface badges)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

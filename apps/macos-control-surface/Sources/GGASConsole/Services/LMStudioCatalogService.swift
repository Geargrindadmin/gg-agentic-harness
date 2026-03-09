// LMStudioCatalogService.swift — Live model catalog from lms search CLI + lmstudio.ai website.
// Replaces the static ModelCatalogEntry.catalog hardcoded array.

import Foundation

// MARK: - Catalog Model

struct CatalogModel: Identifiable, Codable, Hashable {
    let id: String              // HuggingFace "repo/file" path used by `lms get`
    let name: String            // Display name
    let description: String
    let repo: String            // HuggingFace repo, e.g. "lmstudio-community/Qwen2.5-Coder-7B-GGUF"
    let filename: String        // GGUF filename
    let sizeGB: Double
    let paramCount: String      // "7B", "32B", etc.
    let category: Category
    let contextK: Int           // context window in K tokens
    let quantization: String    // "Q4_K_M", "Q8_0", etc.
    let downloadCount: Int?     // popularity metric (from lmstudio.ai if available)
    let publisher: String?      // e.g. "lmstudio-community"
    var downloadRef: String? = nil  // direct `lms get` reference when available

    enum Category: String, Codable, CaseIterable {
        case coding     = "Coding"
        case general    = "General"
        case reasoning  = "Reasoning"
        case multimodal = "Multimodal"
        case embedding  = "Embedding"
        case tools      = "Tool Use"

        var icon: String {
            switch self {
            case .coding:     return "chevron.left.forwardslash.chevron.right"
            case .general:    return "brain"
            case .reasoning:  return "lightbulb.fill"
            case .multimodal: return "photo.fill"
            case .embedding:  return "waveform"
            case .tools:      return "wrench.and.screwdriver.fill"
            }
        }
    }

    var sizeLabel: String { String(format: "%.1f GB", sizeGB) }
    var hfRef: String { downloadRef ?? "\(repo)/\(filename)" }
}

// MARK: - Service

@MainActor
final class LMStudioCatalogService: ObservableObject {
    static let shared = LMStudioCatalogService()

    @Published var featuredModels: [CatalogModel] = []
    @Published var searchResults: [CatalogModel] = []
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var lastError: String?

    private let cacheURL = URL(fileURLWithPath:
        NSHomeDirectory() + "/.ggas/lms-catalog-cache.json")
    private let cacheTTL: TimeInterval = 24 * 60 * 60  // 24h
    private var searchTask: Task<Void, Never>?
    private var lmsSearchSupport: Bool?

    private init() {
        // Load cache on init to show models immediately on first open
        if let cached = loadCache(allowExpired: true) {
            featuredModels = cached
        }
    }

    // MARK: - Public API

    /// Fetch featured / top models. Tries lms CLI first, falls back to lmstudio.ai API.
    func fetchFeatured() async {
        // Show cache immediately (even when stale), then revalidate in background.
        if let cached = loadCache(allowExpired: true), !cached.isEmpty {
            featuredModels = cached
        }

        isLoading = true
        lastError = nil

        // 1. Try lms search with popular queries
        let lmsResults = dedupeModels(await fetchViaLMSCLI(query: ""))
        if !lmsResults.isEmpty {
            featuredModels = lmsResults
            saveCache(lmsResults)
            isLoading = false
            return
        }

        // 2. Fall back to lmstudio.ai website catalog
        let webResults = dedupeModels(await fetchFromLMStudioAI())
        if !webResults.isEmpty {
            featuredModels = webResults
            saveCache(webResults)
        } else if featuredModels.isEmpty {
            // Last resort: use built-in seed data so the UI isn't empty
            featuredModels = seedCatalog
            lastError = "Unable to refresh LLM Studio catalog. Showing built-in defaults."
        } else {
            lastError = "Unable to refresh LLM Studio catalog. Showing cached results."
        }

        isLoading = false
    }

    /// Search with debounce (call on every keystroke — internally debounced 300ms).
    func search(query: String) {
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            isSearching = true
            let results = await performSearch(query: query)
            guard !Task.isCancelled else { return }
            searchResults = results
            isSearching = false
        }
    }

    func resolveSearchCandidate(query: String) async -> CatalogModel? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let results = await performSearch(query: trimmed)
        guard !results.isEmpty else { return nil }

        let normalized = trimmed.lowercased()
        if let exact = results.first(where: {
            $0.name.lowercased() == normalized
            || $0.id.lowercased() == normalized
            || $0.hfRef.lowercased() == normalized
        }) {
            return exact
        }

        if let repoMatch = results.first(where: { $0.repo.lowercased().contains(normalized) }) {
            return repoMatch
        }

        if let nameMatch = results.first(where: { $0.name.lowercased().contains(normalized) }) {
            return nameMatch
        }

        return results.first
    }

    /// Parse a direct HuggingFace or lmstudio.ai URL into a CatalogModel for immediate download.
    func parseURL(_ urlString: String) -> CatalogModel? {
        // Handle direct HF refs, huggingface URLs, and lmstudio.ai model URLs.
        guard let (repo, filename) = extractRepoAndFilename(from: urlString) else { return nil }
        let parts = repo.components(separatedBy: "/")

        return CatalogModel(
            id: "\(repo)/\(filename)",
            name: filename.replacingOccurrences(of: ".gguf", with: ""),
            description: "Custom model from \(repo)",
            repo: repo, filename: filename,
            sizeGB: 0, paramCount: "?",
            category: .general, contextK: 0,
            quantization: extractQuantization(from: filename),
            downloadCount: nil, publisher: parts[0]
        )
    }

    // MARK: - LMS CLI fetch

    private func fetchViaLMSCLI(query: String) async -> [CatalogModel] {
        guard LMStudioCLI.shared.isAvailable else { return [] }
        guard await supportsLMSSearch() else { return [] }
        let args = query.isEmpty ? ["search", "--limit", "40"] : ["search", query, "--limit", "30"]
        let output = await runLMS(args: args)
        return parseLMSSearchOutput(output)
    }

    private func supportsLMSSearch() async -> Bool {
        if let supported = lmsSearchSupport {
            return supported
        }
        let help = await runLMS(args: ["--help"])
        let supported = help.localizedCaseInsensitiveContains("search")
        lmsSearchSupport = supported
        return supported
    }

    private func performSearch(query: String) async -> [CatalogModel] {
        // Try CLI first
        let cliResults = await fetchViaLMSCLI(query: query)
        if !cliResults.isEmpty { return cliResults }
        // Fall back to filtering cached models
        return featuredModels.filter { model in
            model.name.localizedCaseInsensitiveContains(query) ||
            model.description.localizedCaseInsensitiveContains(query) ||
            model.repo.localizedCaseInsensitiveContains(query) ||
            model.paramCount.localizedCaseInsensitiveContains(query)
        }
    }

    private func runLMS(args: [String]) async -> String {
        guard let bin = LMStudioCLI.shared.binaryPath else { return "" }
        return await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: bin)
            proc.arguments = args
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                          encoding: .utf8) ?? ""
        }.value
    }

    /// Parse `lms search` text output into CatalogModel array.
    /// LMS search output format (approximate):
    ///   lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF (7B, 4.7 GB)
    ///     Qwen2.5 Coder 7B Instruct - Fast coding model
    private func parseLMSSearchOutput(_ raw: String) -> [CatalogModel] {
        var results: [CatalogModel] = []
        let lines = raw.components(separatedBy: "\n").filter { !$0.isEmpty }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            // Match lines that look like "owner/repo-name"
            let repoPattern = #"^([a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+)"#
            guard let repoRange = line.range(of: repoPattern, options: .regularExpression) else {
                i += 1; continue
            }
            let repo = String(line[repoRange])
            let desc = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : ""

            // Extract size and params from the line
            let sizeGB = extractSize(from: line)
            let params = extractParams(from: line + " " + repo)
            let quant = extractQuantization(from: line)
            let category = inferCategory(from: repo + " " + desc)

            // Try to extract filename from the line
            let filename = extractFilename(from: line) ?? "\(repo.components(separatedBy: "/").last ?? "model")-\(quant).gguf"

            let model = CatalogModel(
                id: "\(repo)/\(filename)",
                name: formatModelName(repo: repo),
                description: desc,
                repo: repo, filename: filename,
                sizeGB: sizeGB, paramCount: params,
                category: category, contextK: 128,
                quantization: quant,
                downloadCount: nil,
                publisher: repo.components(separatedBy: "/").first
            )
            results.append(model)
            i += desc.isEmpty ? 1 : 2
        }
        return dedupeModels(results)
    }

    // MARK: - lmstudio.ai web fetch

    private func fetchFromLMStudioAI() async -> [CatalogModel] {
        // Preferred: artifacts API currently backs the public model catalog.
        if let artifacts = await fetchLMStudioArtifactsAPI(), !artifacts.isEmpty {
            return artifacts
        }
        // Try the undocumented models API endpoint first
        if let models = await fetchLMStudioAPI() { return models }
        // Fallback: fetch HTML and parse model cards
        return await fetchLMStudioHTML()
    }

    private func fetchLMStudioArtifactsAPI() async -> [CatalogModel]? {
        let endpoints = [
            "https://lmstudio.ai/api/v1/artifacts?type=model&limit=200",
            "https://lmstudio.ai/api/v1/artifacts/?type=model&limit=200"
        ]

        struct ArtifactsResponse: Codable {
            struct Artifact: Codable {
                struct Current: Codable {
                    let sizeBytes: Int?
                    let artifactUrl: String?
                    let downloadCount: Int?

                    enum CodingKeys: String, CodingKey {
                        case sizeBytes
                        case artifactUrl
                        case downloadCount
                    }
                }

                let identifier: String?
                let owner: String?
                let name: String?
                let description: String?
                let downloadCount: Int?
                let current: Current?
            }

            let publicArtifacts: [Artifact]?
            let artifacts: [Artifact]?
        }

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("GGASConsole/1.0", forHTTPHeaderField: "User-Agent")

            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(ArtifactsResponse.self, from: data)
            else { continue }

            let artifacts = decoded.publicArtifacts ?? decoded.artifacts ?? []
            let mapped = artifacts.compactMap { artifact -> CatalogModel? in
                guard let identifier = artifact.identifier, identifier.contains("/") else { return nil }
                let owner = artifact.owner ?? identifier.components(separatedBy: "/").first
                let modelName = artifact.name ?? identifier.components(separatedBy: "/").last ?? identifier
                let description = artifact.description ?? "Model from LM Studio catalog"
                let params = extractParams(from: "\(modelName) \(identifier)")
                let quant = extractQuantization(from: modelName)
                let bytes = artifact.current?.sizeBytes ?? 0
                let sizeGB = bytes > 0 ? Double(bytes) / 1_000_000_000 : estimatedSize(params: params)

                return CatalogModel(
                    id: identifier,
                    name: formatModelName(repo: identifier),
                    description: description,
                    repo: identifier,
                    filename: "\(modelName).gguf",
                    sizeGB: sizeGB,
                    paramCount: params,
                    category: inferCategory(from: "\(identifier) \(description)"),
                    contextK: 128,
                    quantization: quant,
                    downloadCount: artifact.downloadCount ?? artifact.current?.downloadCount,
                    publisher: owner,
                    downloadRef: identifier
                )
            }

            if !mapped.isEmpty {
                return dedupeModels(mapped)
            }
        }

        return nil
    }

    private func fetchLMStudioAPI() async -> [CatalogModel]? {
        let endpoints = [
            "https://lmstudio.ai/api/models?limit=200",
            "https://lmstudio.ai/api/v1/models?limit=200",
            "https://lmstudio.ai/api/models"
        ]

        for endpoint in endpoints {
            guard let url = URL(string: endpoint) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("GGASConsole/1.0", forHTTPHeaderField: "User-Agent")

            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { continue }

            let decoded = parseKnownLMStudioAPI(data)
            if !decoded.isEmpty { return dedupeModels(decoded) }

            let flexible = parseFlexibleLMStudioAPI(data)
            if !flexible.isEmpty { return dedupeModels(flexible) }
        }
        return nil
    }

    private func fetchLMStudioHTML() async -> [CatalogModel] {
        guard let url = URL(string: "https://lmstudio.ai/models") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let html = String(data: data, encoding: .utf8) else { return [] }

        // Extract JSON-LD or next.js __NEXT_DATA__ embedded model data
        return parseHTMLForModels(html)
    }

    private func parseHTMLForModels(_ html: String) -> [CatalogModel] {
        // Look for JSON data embedded in the page (common in Next.js apps)
        var results: [CatalogModel] = []

        // Pattern: find repo references like "owner/ModelName-GGUF"
        let repoPattern = #"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+-GGUF)"#
        let regex = try? NSRegularExpression(pattern: repoPattern)
        let matches = regex?.matches(in: html,
                                     range: NSRange(html.startIndex..., in: html)) ?? []
        var seenRepos = Set<String>()
        for match in matches {
            guard let range = Range(match.range, in: html) else { continue }
            let repo = String(html[range])
            guard !seenRepos.contains(repo) else { continue }
            seenRepos.insert(repo)

            let modelName = formatModelName(repo: repo)
            let params = extractParams(from: repo)
            let model = CatalogModel(
                id: "\(repo)/\(modelName)-Q4_K_M.gguf",
                name: modelName,
                description: "Available on LM Studio",
                repo: repo,
                filename: "\(modelName)-Q4_K_M.gguf",
                sizeGB: estimatedSize(params: params),
                paramCount: params,
                category: inferCategory(from: repo),
                contextK: 128,
                quantization: "Q4_K_M",
                downloadCount: nil,
                publisher: repo.components(separatedBy: "/").first
            )
            results.append(model)
        }
        return dedupeModels(results)
    }

    // MARK: - Cache

    private func loadCache(allowExpired: Bool = false) -> [CatalogModel]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let wrapper = try? JSONDecoder().decode(CacheWrapper.self, from: data)
        else { return nil }
        if !allowExpired && Date().timeIntervalSince(wrapper.cachedAt) >= cacheTTL {
            return nil
        }
        return dedupeModels(wrapper.models)
    }

    private func saveCache(_ models: [CatalogModel]) {
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let wrapper = CacheWrapper(models: models, cachedAt: Date())
        guard let data = try? JSONEncoder().encode(wrapper) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        featuredModels = seedCatalog
    }

    private struct CacheWrapper: Codable {
        let models: [CatalogModel]
        let cachedAt: Date
    }

    // MARK: - Helpers

    private func formatModelName(repo: String) -> String {
        let name = repo.components(separatedBy: "/").last ?? repo
        return name.replacingOccurrences(of: "-GGUF", with: "")
                   .replacingOccurrences(of: "-Instruct", with: "")
                   .replacingOccurrences(of: "-", with: " ")
    }

    private func extractSize(from text: String) -> Double {
        let pattern = #"(\d+\.?\d*)\s*GB"#
        guard let range = text.range(of: pattern, options: .regularExpression),
              let val = Double(text[range].replacingOccurrences(of: "GB", with: "")
                                         .trimmingCharacters(in: .whitespaces))
        else { return 0 }
        return val
    }

    private func extractParams(from text: String) -> String {
        let pattern = #"(\d+(?:\.\d+)?)[Bb]"#
        guard let range = text.range(of: pattern, options: .regularExpression)
        else { return "?" }
        return String(text[range]).uppercased()
    }

    private func extractQuantization(from text: String) -> String {
        let quants = ["Q8_0", "Q6_K", "Q5_K_M", "Q5_K_S", "Q4_K_M", "Q4_K_S",
                      "Q3_K_M", "Q2_K", "IQ4_NL", "IQ3_M", "F16"]
        return quants.first { text.contains($0) } ?? "Q4_K_M"
    }

    private func extractFilename(from text: String) -> String? {
        let pattern = #"[\w.-]+\.gguf"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        return String(text[range])
    }

    private func inferCategory(from text: String) -> CatalogModel.Category {
        let lower = text.lowercased()
        if lower.contains("coder") || lower.contains("code") || lower.contains("deepseek-coder") { return .coding }
        if lower.contains("r1") || lower.contains("reasoning") || lower.contains("think") { return .reasoning }
        if lower.contains("llava") || lower.contains("vision") || lower.contains("vlm") || lower.contains("pixtral") { return .multimodal }
        if lower.contains("embed") || lower.contains("nomic") || lower.contains("bge") { return .embedding }
        if lower.contains("tool") || lower.contains("function") || lower.contains("hermes") { return .tools }
        return .general
    }

    private func estimatedSize(params: String) -> Double {
        let num = Double(params.replacingOccurrences(of: "B", with: "")
                               .replacingOccurrences(of: "b", with: "")) ?? 7
        // Q4_K_M is roughly 0.65 bytes/param
        return (num * 1e9 * 0.65) / 1e9
    }

    private func parseKnownLMStudioAPI(_ data: Data) -> [CatalogModel] {
        struct APIResponse: Codable {
            struct Model: Codable {
                let id: String?
                let name: String?
                let description: String?
                let repo: String?
                let hfRepo: String?
                let filename: String?
                let file: String?
                let sizeGb: Double?
                let sizeGB: Double?
                let parameterCount: String?
                let parameters: String?
                let type: String?
                let modelType: String?
                let publisher: String?
                let downloadCount: Int?

                enum CodingKeys: String, CodingKey {
                    case id, name, description, repo, filename, file, type, publisher
                    case hfRepo = "hf_repo"
                    case sizeGb
                    case sizeGB
                    case parameterCount
                    case parameters
                    case modelType = "model_type"
                    case downloadCount
                }
            }

            let models: [Model]?
            let data: [Model]?
            let results: [Model]?
            let items: [Model]?
        }

        guard let decoded = try? JSONDecoder().decode(APIResponse.self, from: data) else {
            return []
        }
        let raw = decoded.models ?? decoded.data ?? decoded.results ?? decoded.items ?? []
        return dedupeModels(raw.compactMap { m in
            let repoHint = m.repo ?? m.hfRepo
            let fileHint = m.filename ?? m.file
            let parsed = normalizeRepoAndFilename(repo: repoHint, filename: fileHint)
                ?? (m.id.flatMap { extractRepoAndFilename(from: $0) })
            guard let (repo, filename) = parsed else { return nil }

            let name = (m.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? filename.replacingOccurrences(of: ".gguf", with: "")
            let params = m.parameterCount ?? m.parameters ?? extractParams(from: "\(repo) \(filename)")
            let typeHint = [m.type, m.modelType].compactMap { $0 }.joined(separator: " ")
            return CatalogModel(
                id: "\(repo)/\(filename)",
                name: name,
                description: m.description ?? "",
                repo: repo,
                filename: filename,
                sizeGB: m.sizeGb ?? m.sizeGB ?? 0,
                paramCount: params,
                category: inferCategory(from: "\(typeHint) \(repo)"),
                contextK: 128,
                quantization: extractQuantization(from: filename),
                downloadCount: m.downloadCount,
                publisher: m.publisher ?? repo.components(separatedBy: "/").first
            )
        })
    }

    private func parseFlexibleLMStudioAPI(_ data: Data) -> [CatalogModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              !data.isEmpty else { return [] }
        let objects = flattenJSONObjectTree(json)
        let models = objects.compactMap { dict -> CatalogModel? in
            let repoHint = firstStringValue(in: dict, keys: [
                "repo", "hf_repo", "huggingface_repo", "model_repo", "repository"
            ])
            let fileHint = firstStringValue(in: dict, keys: [
                "filename", "file", "gguf", "model_file", "filename_gguf"
            ])
            let idHint = firstStringValue(in: dict, keys: [
                "id", "hf_ref", "path", "model_id", "modelRef", "model_ref", "url"
            ])

            let parsed = normalizeRepoAndFilename(repo: repoHint, filename: fileHint)
                ?? (idHint.flatMap { extractRepoAndFilename(from: $0) })
                ?? (repoHint.flatMap { extractRepoAndFilename(from: $0) })
            guard let (repo, filename) = parsed else { return nil }

            let name = firstStringValue(in: dict, keys: ["name", "title", "label"])
                ?? filename.replacingOccurrences(of: ".gguf", with: "")
            let description = firstStringValue(in: dict, keys: ["description", "summary", "subtitle"]) ?? ""
            let typeHint = firstStringValue(in: dict, keys: ["type", "model_type", "category"]) ?? ""
            let params = firstStringValue(in: dict, keys: ["parameterCount", "parameters", "params"])
                ?? extractParams(from: "\(repo) \(filename) \(name)")
            let sizeGB = firstDoubleValue(in: dict, keys: ["sizeGb", "sizeGB", "size_gb"]) ?? 0
            let downloads = firstIntValue(in: dict, keys: ["downloadCount", "downloads", "num_downloads"])

            return CatalogModel(
                id: "\(repo)/\(filename)",
                name: name,
                description: description,
                repo: repo,
                filename: filename,
                sizeGB: sizeGB,
                paramCount: params,
                category: inferCategory(from: "\(typeHint) \(repo) \(description)"),
                contextK: 128,
                quantization: extractQuantization(from: filename),
                downloadCount: downloads,
                publisher: firstStringValue(in: dict, keys: ["publisher", "owner", "author"])
                    ?? repo.components(separatedBy: "/").first
            )
        }
        return dedupeModels(models)
    }

    private func flattenJSONObjectTree(_ value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            var out: [[String: Any]] = []
            if dict["repo"] != nil || dict["filename"] != nil || dict["id"] != nil || dict["hf_ref"] != nil {
                out.append(dict)
            }
            for child in dict.values {
                out.append(contentsOf: flattenJSONObjectTree(child))
            }
            return out
        }
        if let array = value as? [Any] {
            return array.flatMap { flattenJSONObjectTree($0) }
        }
        return []
    }

    private func normalizeRepoAndFilename(repo: String?, filename: String?) -> (String, String)? {
        guard let repo, let filename else { return nil }
        let cleanRepo = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanFilename = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanFilename.lowercased().hasSuffix(".gguf") else { return nil }
        if let parsed = extractRepoAndFilename(from: "\(cleanRepo)/\(cleanFilename)") {
            return parsed
        }
        guard cleanRepo.contains("/") else { return nil }
        return (cleanRepo, cleanFilename)
    }

    private func extractRepoAndFilename(from reference: String) -> (String, String)? {
        let cleaned = reference
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "#").first?
            .components(separatedBy: "?").first?
            .replacingOccurrences(of: "https://huggingface.co/", with: "")
            .replacingOccurrences(of: "/blob/main/", with: "/")
            .replacingOccurrences(of: "https://lmstudio.ai/models/", with: "") ?? reference

        let parts = cleaned.components(separatedBy: "/").filter { !$0.isEmpty }
        guard parts.count >= 3 else { return nil }
        let repo = "\(parts[0])/\(parts[1])"
        let filename = parts[2...].joined(separator: "/")
        guard filename.lowercased().hasSuffix(".gguf") else { return nil }
        return (repo, filename)
    }

    private func firstStringValue(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func firstDoubleValue(in dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dict[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = dict[key] as? String {
                let trimmed = value.replacingOccurrences(of: "GB", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Double(trimmed) {
                    return parsed
                }
            }
        }
        return nil
    }

    private func firstIntValue(in dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dict[key] as? NSNumber {
                return value.intValue
            }
            if let value = dict[key] as? String {
                let digits = value.filter(\.isNumber)
                if let parsed = Int(digits) {
                    return parsed
                }
            }
        }
        return nil
    }

    private func dedupeModels(_ models: [CatalogModel]) -> [CatalogModel] {
        var seen = Set<String>()
        var deduped: [CatalogModel] = []
        for model in models {
            let key = model.id.lowercased()
            if seen.insert(key).inserted {
                deduped.append(model)
            }
        }
        return deduped
    }

    // MARK: - Seed catalog (shown when offline and cache empty)

    private let seedCatalog: [CatalogModel] = [
        CatalogModel(id: "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF/Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf",
                     name: "Qwen2.5 Coder 7B", description: "Best small coding model",
                     repo: "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF",
                     filename: "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf",
                     sizeGB: 4.7, paramCount: "7B", category: .coding, contextK: 128,
                     quantization: "Q4_K_M", downloadCount: nil, publisher: "lmstudio-community"),
        CatalogModel(id: "lmstudio-community/Qwen2.5-Coder-32B-Instruct-GGUF/Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf",
                     name: "Qwen2.5 Coder 32B", description: "GPT-4o quality coding",
                     repo: "lmstudio-community/Qwen2.5-Coder-32B-Instruct-GGUF",
                     filename: "Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf",
                     sizeGB: 19.8, paramCount: "32B", category: .coding, contextK: 128,
                     quantization: "Q4_K_M", downloadCount: nil, publisher: "lmstudio-community"),
        CatalogModel(id: "lmstudio-community/Meta-Llama-3.2-8B-Instruct-GGUF/Meta-Llama-3.2-8B-Instruct-Q4_K_M.gguf",
                     name: "Llama 3.2 8B", description: "Meta flagship — great all-rounder",
                     repo: "lmstudio-community/Meta-Llama-3.2-8B-Instruct-GGUF",
                     filename: "Meta-Llama-3.2-8B-Instruct-Q4_K_M.gguf",
                     sizeGB: 5.0, paramCount: "8B", category: .general, contextK: 128,
                     quantization: "Q4_K_M", downloadCount: nil, publisher: "lmstudio-community"),
        CatalogModel(id: "lmstudio-community/DeepSeek-R1-Distill-Qwen-7B-GGUF/DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf",
                     name: "DeepSeek-R1 7B", description: "Chain-of-thought reasoning",
                     repo: "lmstudio-community/DeepSeek-R1-Distill-Qwen-7B-GGUF",
                     filename: "DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf",
                     sizeGB: 4.9, paramCount: "7B", category: .reasoning, contextK: 128,
                     quantization: "Q4_K_M", downloadCount: nil, publisher: "lmstudio-community"),
        CatalogModel(id: "lmstudio-community/phi-4-GGUF/phi-4-Q4_K_M.gguf",
                     name: "Phi-4 14B", description: "Microsoft — punches above its size",
                     repo: "lmstudio-community/phi-4-GGUF",
                     filename: "phi-4-Q4_K_M.gguf",
                     sizeGB: 8.5, paramCount: "14B", category: .general, contextK: 16,
                     quantization: "Q4_K_M", downloadCount: nil, publisher: "lmstudio-community"),
        CatalogModel(id: "lmstudio-community/gemma-3-12b-it-GGUF/gemma-3-12b-it-Q4_K_M.gguf",
                     name: "Gemma 3 12B", description: "Google — multilingual, long context",
                     repo: "lmstudio-community/gemma-3-12b-it-GGUF",
                     filename: "gemma-3-12b-it-Q4_K_M.gguf",
                     sizeGB: 7.8, paramCount: "12B", category: .general, contextK: 128,
                     quantization: "Q4_K_M", downloadCount: nil, publisher: "lmstudio-community"),
        CatalogModel(id: "lmstudio-community/DeepSeek-R1-Distill-Qwen-32B-GGUF/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf",
                     name: "DeepSeek-R1 32B", description: "Competition-level reasoning",
                     repo: "lmstudio-community/DeepSeek-R1-Distill-Qwen-32B-GGUF",
                     filename: "DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf",
                     sizeGB: 19.4, paramCount: "32B", category: .reasoning, contextK: 128,
                     quantization: "Q4_K_M", downloadCount: nil, publisher: "lmstudio-community"),
        CatalogModel(id: "lmstudio-community/Mistral-7B-Instruct-v0.3-GGUF/Mistral-7B-Instruct-v0.3-Q4_K_M.gguf",
                     name: "Mistral 7B v0.3", description: "Speed-optimised instruction following",
                     repo: "lmstudio-community/Mistral-7B-Instruct-v0.3-GGUF",
                     filename: "Mistral-7B-Instruct-v0.3-Q4_K_M.gguf",
                     sizeGB: 4.4, paramCount: "7B", category: .general, contextK: 32,
                     quantization: "Q4_K_M", downloadCount: nil, publisher: "lmstudio-community"),
    ]
}

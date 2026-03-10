import Foundation

struct GitWorktreeSummary: Identifiable, Equatable {
    let path: String
    let label: String
    let branch: String?
    let head: String?
    let detached: Bool
    let prunable: Bool
    let isMain: Bool
    let runId: String?
    let agentId: String?
    let runtime: String?
    let role: String?
    let aheadCount: Int?
    let behindCount: Int?
    let changedFilesCount: Int
    let untrackedFilesCount: Int
    let changedFilesList: [String]

    var id: String { path }
}

struct GitWorktreeGroup: Identifiable, Equatable {
    let title: String
    let subtitle: String?
    let worktrees: [GitWorktreeSummary]

    var id: String { title }
}

@MainActor
final class GitWorktreeStore: ObservableObject {
    static let shared = GitWorktreeStore()

    @Published var groups: [GitWorktreeGroup] = []
    @Published var isLoading = false
    @Published var error: String?

    private init() {}

    func refresh(projectRoot: String) async {
        let normalizedRoot = projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRoot.isEmpty else {
            groups = []
            error = "Project root is not configured."
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        do {
            let statuses = AgentMonitorService.shared.busStatuses
            let groups = try await Task.detached(priority: .userInitiated) {
                try Self.loadGroups(projectRoot: normalizedRoot, statuses: statuses)
            }.value
            self.groups = groups
            self.isLoading = false
        } catch {
            self.groups = []
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }

    func summary(for path: String) -> GitWorktreeSummary? {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        return groups.lazy
            .flatMap(\.worktrees)
            .first(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == normalized })
    }

    func changedFiles(for path: String) -> [String] {
        summary(for: path)?.changedFilesList ?? []
    }

    private nonisolated static func loadGroups(projectRoot: String, statuses: [BusRunStatus]) throws -> [GitWorktreeGroup] {
        let rootURL = URL(fileURLWithPath: projectRoot).standardizedFileURL
        let worktrees = try parseWorktreeList(runGit(args: ["-C", projectRoot, "worktree", "list", "--porcelain"]), projectRoot: projectRoot)
        let metadata = buildMetadataMap(projectRoot: projectRoot, statuses: statuses)
        let summaries = worktrees.map { raw in
            buildSummary(raw: raw, rootURL: rootURL, metadata: metadata)
        }
        return groupSummaries(summaries)
    }

    private nonisolated static func buildSummary(
        raw: RawWorktree,
        rootURL: URL,
        metadata: [String: WorktreeMetadata]
    ) -> GitWorktreeSummary {
        let normalizedPath = URL(fileURLWithPath: raw.path).standardizedFileURL.path
        let meta = metadata[normalizedPath]
        let status = readStatus(path: normalizedPath)
        let tracking = readTracking(path: normalizedPath)
        let isMain = normalizedPath == rootURL.path
        let components = normalizedPath.components(separatedBy: "/")
        let inferredRunId = components.dropLast().last(where: { $0.hasPrefix("run-") })
        let inferredAgentId = components.last

        return GitWorktreeSummary(
            path: normalizedPath,
            label: meta?.agentId ?? (isMain ? "Workspace Root" : URL(fileURLWithPath: normalizedPath).lastPathComponent),
            branch: raw.branch,
            head: raw.head,
            detached: raw.detached,
            prunable: raw.prunable,
            isMain: isMain,
            runId: meta?.runId ?? inferredRunId,
            agentId: meta?.agentId ?? (isMain ? nil : inferredAgentId),
            runtime: meta?.runtime,
            role: meta?.role,
            aheadCount: tracking.ahead,
            behindCount: tracking.behind,
            changedFilesCount: status.changedCount,
            untrackedFilesCount: status.untrackedCount,
            changedFilesList: status.changedFiles
        )
    }

    private nonisolated static func groupSummaries(_ summaries: [GitWorktreeSummary]) -> [GitWorktreeGroup] {
        let grouped = Dictionary(grouping: summaries) { summary -> String in
            if summary.isMain { return "Workspace" }
            if let runId = summary.runId { return runId }
            return "Detached / Other"
        }

        return grouped.keys.sorted { left, right in
            if left == "Workspace" { return true }
            if right == "Workspace" { return false }
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }.map { key in
            let items = (grouped[key] ?? []).sorted { left, right in
                if left.isMain != right.isMain { return left.isMain }
                return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
            }
            let subtitle: String?
            if key == "Workspace" {
                subtitle = "Primary repository checkout"
            } else if key.hasPrefix("run-") {
                subtitle = "\(items.count) worktree\(items.count == 1 ? "" : "s")"
            } else {
                subtitle = nil
            }
            return GitWorktreeGroup(title: key, subtitle: subtitle, worktrees: items)
        }
    }

    private nonisolated static func buildMetadataMap(projectRoot: String, statuses: [BusRunStatus]) -> [String: WorktreeMetadata] {
        var result: [String: WorktreeMetadata] = [:]
        let base = URL(fileURLWithPath: projectRoot).standardizedFileURL.path
        for run in statuses {
            for (agentId, worker) in run.workers {
                let rawPath = worker.worktreePath ?? "\(base)/.agent/control-plane/worktrees/\(run.runId)/\(agentId)"
                let normalized = URL(fileURLWithPath: rawPath).standardizedFileURL.path
                result[normalized] = WorktreeMetadata(
                    runId: run.runId,
                    agentId: agentId,
                    runtime: worker.runtime,
                    role: worker.role
                )
            }
        }
        return result
    }

    private nonisolated static func readStatus(path: String) -> (changedCount: Int, untrackedCount: Int, changedFiles: [String]) {
        guard FileManager.default.fileExists(atPath: path) else {
            return (0, 0, [])
        }
        let output = (try? runGit(args: ["-C", path, "status", "--porcelain"])) ?? ""
        if output.isEmpty {
            return (0, 0, [])
        }
        var changed = 0
        var untracked = 0
        var files: [String] = []
        for line in output.split(separator: "\n") {
            guard line.count >= 3 else { continue }
            let prefix = String(line.prefix(2))
            let file = String(line.dropFirst(3))
            if prefix == "??" {
                untracked += 1
            } else {
                changed += 1
            }
            files.append(URL(fileURLWithPath: path).appendingPathComponent(file).path)
        }
        return (changed, untracked, files)
    }

    private nonisolated static func readTracking(path: String) -> (ahead: Int?, behind: Int?) {
        guard FileManager.default.fileExists(atPath: path) else {
            return (nil, nil)
        }

        let output = try? runGit(args: ["-C", path, "rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
        let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return (nil, nil)
        }

        let components = trimmed
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0) }
        guard components.count >= 2 else {
            return (nil, nil)
        }
        return (components[0], components[1])
    }

    private nonisolated static func runGit(args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        if process.terminationStatus == 0 {
            return text
        }
        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "Git worktree command failed." : text])
    }

    nonisolated static func parseWorktreeList(_ output: String, projectRoot: String) throws -> [RawWorktree] {
        var results: [RawWorktree] = []
        var current = RawWorktree(path: "", head: nil, branch: nil, detached: false, prunable: false)
        let flush: () -> Void = {
            if !current.path.isEmpty {
                results.append(current)
            }
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty {
                flush()
                current = RawWorktree(path: "", head: nil, branch: nil, detached: false, prunable: false)
                continue
            }
            if line.hasPrefix("worktree ") {
                current.path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                current.head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                current.branch = String(line.dropFirst("branch ".count)).replacingOccurrences(of: "refs/heads/", with: "")
            } else if line == "detached" {
                current.detached = true
            } else if line.hasPrefix("prunable") {
                current.prunable = true
            }
        }
        flush()
        return results
    }
}

struct RawWorktree: Equatable {
    var path: String
    var head: String?
    var branch: String?
    var detached: Bool
    var prunable: Bool
}

private struct WorktreeMetadata {
    let runId: String?
    let agentId: String?
    let runtime: String?
    let role: String?
}

import Foundation

enum IDEProblemSeverity: String, Codable, Comparable {
    case error
    case warning
    case info

    private var rank: Int {
        switch self {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }

    static func < (lhs: IDEProblemSeverity, rhs: IDEProblemSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum IDEProblemActionCapability: String, Codable, CaseIterable {
    case openDocument
    case revealInspector
    case focusWorktree
    case saveDocument
    case revertDocument
    case applyStagedPatch
    case discardStagedPatch
    case sendWorkerGuidance
    case retryWorker
    case retaskWorker
    case terminateWorker
}

struct IDEProblem: Identifiable, Equatable, Codable {
    let id: String
    let severity: IDEProblemSeverity
    let title: String
    let message: String
    let path: String?
    let panel: IDEPanelTab?
    let runId: String?
    let agentId: String?
    let worktreePath: String?
    let workerTarget: IDEWorkerTarget?
    let actionCapabilities: [IDEProblemActionCapability]

    func supports(_ capability: IDEProblemActionCapability) -> Bool {
        actionCapabilities.contains(capability)
    }
}

enum IDEProblemCollector {
    @MainActor
    static func collect(
        activeDocument: IDEDocumentContext?,
        activeSession: DocumentViewerStore?,
        selectedRunId: String?,
        selectedRunStatus: BusRunStatus?,
        monitorLastError: String?,
        controlPlaneLastError: String?,
        explorerError: String?,
        worktreeError: String?
    ) -> [IDEProblem] {
        var problems: [IDEProblem] = []

        if let activeDocument, let activeSession, let message = activeSession.error?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            problems.append(
                IDEProblem(
                    id: "document-load-error:\(activeDocument.path)",
                    severity: .error,
                    title: "Open file failed",
                    message: message,
                    path: activeDocument.path,
                    panel: .explorer,
                    runId: selectedRunId,
                    agentId: nil,
                    worktreePath: nil,
                    workerTarget: nil,
                    actionCapabilities: [.openDocument, .revealInspector]
                )
            )
        }

        if let activeDocument, let activeSession, let message = activeSession.stagedPatchError?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            problems.append(
                IDEProblem(
                    id: "patch-error:\(activeDocument.path)",
                    severity: .error,
                    title: "Patch stage failed",
                    message: message,
                    path: activeDocument.path,
                    panel: .problems,
                    runId: selectedRunId,
                    agentId: nil,
                    worktreePath: nil,
                    workerTarget: nil,
                    actionCapabilities: [.openDocument, .revealInspector, .discardStagedPatch]
                )
            )
        }

        if let message = controlPlaneLastError?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            problems.append(
                IDEProblem(
                    id: "control-plane-error",
                    severity: .error,
                    title: "UI control command failed",
                    message: message,
                    path: nil,
                    panel: .context,
                    runId: nil,
                    agentId: nil,
                    worktreePath: nil,
                    workerTarget: nil,
                    actionCapabilities: [.revealInspector]
                )
            )
        }

        if let message = monitorLastError?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            problems.append(
                IDEProblem(
                    id: "agent-monitor-error",
                    severity: .error,
                    title: "Harness monitor degraded",
                    message: message,
                    path: nil,
                    panel: .context,
                    runId: selectedRunId,
                    agentId: nil,
                    worktreePath: nil,
                    workerTarget: nil,
                    actionCapabilities: [.revealInspector]
                )
            )
        }

        if let message = worktreeError?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            problems.append(
                IDEProblem(
                    id: "worktree-error",
                    severity: .error,
                    title: "Worktree refresh failed",
                    message: message,
                    path: nil,
                    panel: .worktrees,
                    runId: selectedRunId,
                    agentId: nil,
                    worktreePath: nil,
                    workerTarget: nil,
                    actionCapabilities: [.revealInspector]
                )
            )
        }

        if let message = explorerError?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            problems.append(
                IDEProblem(
                    id: "explorer-error",
                    severity: .error,
                    title: "Explorer refresh failed",
                    message: message,
                    path: nil,
                    panel: .explorer,
                    runId: selectedRunId,
                    agentId: nil,
                    worktreePath: nil,
                    workerTarget: nil,
                    actionCapabilities: [.revealInspector]
                )
            )
        }

        if let activeDocument, let activeSession {
            if activeSession.isDirty {
                problems.append(
                    IDEProblem(
                        id: "document-dirty:\(activeDocument.path)",
                        severity: .warning,
                        title: "Unsaved changes",
                        message: "The active document has edits that are not written to disk yet.",
                        path: activeDocument.path,
                        panel: .problems,
                        runId: selectedRunId,
                        agentId: nil,
                        worktreePath: nil,
                        workerTarget: nil,
                        actionCapabilities: [.openDocument, .saveDocument, .revertDocument]
                    )
                )
            }

            if activeSession.hasStagedPatch {
                problems.append(
                    IDEProblem(
                        id: "document-staged-patch:\(activeDocument.path)",
                        severity: .warning,
                        title: "Staged patch pending",
                        message: "Review and apply or discard the staged patch before saving the active document.",
                        path: activeDocument.path,
                        panel: .problems,
                        runId: selectedRunId,
                        agentId: nil,
                        worktreePath: nil,
                        workerTarget: nil,
                        actionCapabilities: [.openDocument, .applyStagedPatch, .discardStagedPatch]
                    )
                )
            }

            if activeSession.isTruncated {
                problems.append(
                    IDEProblem(
                        id: "document-truncated:\(activeDocument.path)",
                        severity: .warning,
                        title: "File preview truncated",
                        message: "The in-app preview is limited to 512 KB. Open the file in a full editor for larger content.",
                        path: activeDocument.path,
                        panel: .problems,
                        runId: selectedRunId,
                        agentId: nil,
                        worktreePath: nil,
                        workerTarget: nil,
                        actionCapabilities: [.openDocument]
                    )
                )
            }
        }

        if let selectedRunStatus {
            if let activeDocument {
                let normalizedDocumentPath = URL(fileURLWithPath: activeDocument.path).standardizedFileURL.path
                if let lockOwner = selectedRunStatus.activeLocks.first(where: {
                    URL(fileURLWithPath: $0.key).standardizedFileURL.path == normalizedDocumentPath
                })?.value {
                    problems.append(
                        IDEProblem(
                            id: "file-lock:\(normalizedDocumentPath)",
                            severity: .warning,
                            title: "Active document locked",
                            message: "The selected run currently reports a file lock on this document.",
                            path: activeDocument.path,
                            panel: .problems,
                            runId: selectedRunStatus.runId,
                            agentId: lockOwner,
                            worktreePath: nil,
                            workerTarget: IDEWorkerTarget(runId: selectedRunStatus.runId, agentId: lockOwner),
                            actionCapabilities: [.openDocument, .sendWorkerGuidance]
                        )
                    )
                }
            }

            for (agentId, worker) in selectedRunStatus.workers.sorted(by: { $0.key < $1.key }) {
                guard worker.status == "failed" || worker.executionStatus == "failed" else { continue }
                let message = [
                    worker.currentTask,
                    worker.lastSummary,
                    worker.executionStatus,
                    worker.status
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "The worker reported a failure without a detailed summary."

                problems.append(
                    IDEProblem(
                        id: "worker-failure:\(selectedRunStatus.runId):\(agentId)",
                        severity: .error,
                        title: "Worker \(agentId) failed",
                        message: message,
                        path: nil,
                        panel: .worktrees,
                        runId: selectedRunStatus.runId,
                        agentId: agentId,
                        worktreePath: worker.worktreePath,
                        workerTarget: IDEWorkerTarget(runId: selectedRunStatus.runId, agentId: agentId),
                        actionCapabilities: {
                            var actions: [IDEProblemActionCapability] = [
                                .revealInspector,
                                .sendWorkerGuidance,
                                .retryWorker,
                                .retaskWorker,
                                .terminateWorker
                            ]
                            if worker.worktreePath != nil {
                                actions.insert(.focusWorktree, at: 0)
                            }
                            return actions
                        }()
                    )
                )
            }
        }

        return problems.sorted(by: sortProblems)
    }

    @MainActor
    static func collect(
        shell: AppShellState,
        workflow: WorkflowContextStore,
        controlPlaneError: String? = nil
    ) -> [IDEProblem] {
        let activeDocument = shell.activeDocument
        let activeSession = activeDocument.flatMap { document in
            DocumentSessionStore.shared.sessionIfLoaded(path: document.path)
        }
        let selectedRunStatus = workflow.selectedRunId.flatMap { runId in
            AgentMonitorService.shared.busStatuses.first(where: { $0.runId == runId })
        }

        return collect(
            activeDocument: activeDocument,
            activeSession: activeSession,
            selectedRunId: workflow.selectedRunId,
            selectedRunStatus: selectedRunStatus,
            monitorLastError: AgentMonitorService.shared.lastError,
            controlPlaneLastError: controlPlaneError,
            explorerError: WorkspaceExplorerStore.shared.error,
            worktreeError: GitWorktreeStore.shared.error
        )
    }

    private static func sortProblems(left: IDEProblem, right: IDEProblem) -> Bool {
        if left.severity != right.severity {
            return left.severity < right.severity
        }
        if left.runId != right.runId {
            return (left.runId ?? "") < (right.runId ?? "")
        }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
}

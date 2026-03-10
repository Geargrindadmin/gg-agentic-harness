import Foundation
import Testing
@testable import GGHarnessControlSurface

struct IDEProblemCollectorTests {
    @MainActor
    @Test
    func collectSurfacesRunFailuresLocksAndDocumentIssues() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ide-problems-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = rootURL.appendingPathComponent("main.swift")
        try "print(\"hello\")\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let document = IDEDocumentContext(path: fileURL.path, sourceLabel: "Workspace")
        let session = DocumentViewerStore(
            path: fileURL.path,
            sourceLabel: "Workspace",
            workspaceRootPath: rootURL.path,
            selectedRunRootPath: nil
        )
        await session.load()
        session.replaceContent("print(\"draft\")\n")

        let runStatus = BusRunStatus(
            runId: "run-123",
            totalMessages: 14,
            workers: [
                "builder-1": BusWorkerState(
                    status: "failed",
                    progressPct: 82,
                    lastHeartbeat: "2026-03-09T18:00:00Z",
                    currentTask: "Apply planner patch",
                    worktreePath: rootURL.path,
                    runtime: "codex",
                    role: "builder",
                    personaId: nil,
                    launchTransport: nil,
                    executionStatus: "failed",
                    lastSummary: "Patch conflict"
                )
            ],
            activeLocks: [fileURL.path: "reviewer-2"],
            telemetry: nil
        )

        let problems = IDEProblemCollector.collect(
            activeDocument: document,
            activeSession: session,
            selectedRunId: "run-123",
            selectedRunStatus: runStatus,
            monitorLastError: "Event stream disconnected — retrying…",
            controlPlaneLastError: "Unsupported UI action command 'boom'.",
            explorerError: nil,
            worktreeError: "Git worktree command failed."
        )

        #expect(problems.count >= 5)
        #expect(problems.first?.severity == .error)
        let workerFailure = problems.first(where: { $0.title == "Worker builder-1 failed" })
        #expect(workerFailure?.runId == "run-123")
        #expect(workerFailure?.workerTarget == IDEWorkerTarget(runId: "run-123", agentId: "builder-1"))
        #expect(workerFailure?.actionCapabilities.contains(.retryWorker) == true)
        #expect(workerFailure?.actionCapabilities.contains(.retaskWorker) == true)
        #expect(workerFailure?.actionCapabilities.contains(.terminateWorker) == true)

        let fileLock = problems.first(where: { $0.title == "Active document locked" })
        #expect(fileLock?.agentId == "reviewer-2")
        #expect(fileLock?.workerTarget == IDEWorkerTarget(runId: "run-123", agentId: "reviewer-2"))
        #expect(fileLock?.actionCapabilities.contains(.sendWorkerGuidance) == true)

        let dirtyDocument = problems.first(where: { $0.title == "Unsaved changes" })
        #expect(dirtyDocument?.path == fileURL.path)
        #expect(dirtyDocument?.actionCapabilities.contains(.saveDocument) == true)
        #expect(dirtyDocument?.actionCapabilities.contains(.revertDocument) == true)

        #expect(problems.contains(where: { $0.title == "UI control command failed" && $0.panel == .context }))
        #expect(problems.contains(where: { $0.title == "Worktree refresh failed" && $0.panel == .worktrees }))
    }
}

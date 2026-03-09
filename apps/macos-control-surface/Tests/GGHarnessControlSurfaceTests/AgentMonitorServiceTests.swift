import Foundation
import Testing
@testable import GGHarnessControlSurface

@MainActor
struct AgentMonitorServiceTests {
    @Test
    func visibleStatusesDropsStaleCompletedRunsButKeepsRecentActiveRuns() {
        let service = AgentMonitorService.shared
        service.resetTransientState()
        let now = Date(timeIntervalSince1970: 1_741_520_000)

        let visible = BusRunStatus(
            runId: "run-visible",
            totalMessages: 4,
            workers: [
                "builder-1": BusWorkerState(
                    status: "running",
                    progressPct: 50,
                    lastHeartbeat: isoString(now.addingTimeInterval(-30)),
                    currentTask: "Build planner",
                    worktreePath: nil,
                    runtime: "codex",
                    role: "builder",
                    personaId: nil,
                    launchTransport: nil,
                    executionStatus: nil,
                    lastSummary: nil
                )
            ],
            activeLocks: [:],
            telemetry: nil
        )

        let staleCompleted = BusRunStatus(
            runId: "run-stale",
            totalMessages: 2,
            workers: [
                "builder-2": BusWorkerState(
                    status: "complete",
                    progressPct: 100,
                    lastHeartbeat: isoString(now.addingTimeInterval(-600)),
                    currentTask: "Done",
                    worktreePath: nil,
                    runtime: "kimi",
                    role: "builder",
                    personaId: nil,
                    launchTransport: nil,
                    executionStatus: nil,
                    lastSummary: nil
                )
            ],
            activeLocks: [:],
            telemetry: nil
        )

        let filtered = service.visibleStatuses(from: [visible, staleCompleted], now: now)

        #expect(filtered.map(\.runId) == ["run-visible"])
    }

    @Test
    func mergeNewLinksDeduplicatesPerRun() {
        let service = AgentMonitorService.shared
        service.resetTransientState()

        let first = service.mergeNewLinks(for: "run-fixture", links: [
            (from: "builder-1", to: "planner-1"),
            (from: "builder-1", to: "planner-1"),
            (from: "reviewer-1", to: "planner-1")
        ])

        let second = service.mergeNewLinks(for: "run-fixture", links: [
            (from: "builder-1", to: "planner-1"),
            (from: "builder-2", to: "planner-1")
        ])

        #expect(first.count == 2)
        #expect(second.count == 1)
        #expect(second.first?.from == "builder-2")
    }

    private func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

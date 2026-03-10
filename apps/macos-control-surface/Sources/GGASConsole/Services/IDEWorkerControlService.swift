import Foundation

struct IDEWorkerTarget: Equatable, Codable {
    let runId: String
    let agentId: String
}

@MainActor
final class IDEWorkerControlService {
    static let shared = IDEWorkerControlService()

    typealias SendGuidanceHandler = (IDEWorkerTarget, String) async throws -> Void
    typealias RetryHandler = (IDEWorkerTarget, Bool) async throws -> Void
    typealias RetaskHandler = (IDEWorkerTarget, String, Bool) async throws -> Void
    typealias TerminateHandler = (IDEWorkerTarget, String?) async throws -> Void

    private let sendGuidanceHandler: SendGuidanceHandler
    private let retryHandler: RetryHandler
    private let retaskHandler: RetaskHandler
    private let terminateHandler: TerminateHandler

    init(
        sendGuidanceHandler: @escaping SendGuidanceHandler = { target, message in
            try await A2AClient.shared.sendWorkerGuidance(
                runId: target.runId,
                agentId: target.agentId,
                message: message
            )
        },
        retryHandler: @escaping RetryHandler = { target, dryRun in
            try await A2AClient.shared.retryWorker(
                runId: target.runId,
                agentId: target.agentId,
                dryRun: dryRun
            )
        },
        retaskHandler: @escaping RetaskHandler = { target, summary, dryRun in
            try await A2AClient.shared.retaskWorker(
                runId: target.runId,
                agentId: target.agentId,
                taskSummary: summary,
                dryRun: dryRun
            )
        },
        terminateHandler: @escaping TerminateHandler = { target, reason in
            try await A2AClient.shared.terminateWorker(
                runId: target.runId,
                agentId: target.agentId,
                reason: reason
            )
        }
    ) {
        self.sendGuidanceHandler = sendGuidanceHandler
        self.retryHandler = retryHandler
        self.retaskHandler = retaskHandler
        self.terminateHandler = terminateHandler
    }

    func sendGuidance(to target: IDEWorkerTarget, message: String) async throws {
        try await sendGuidanceHandler(target, message)
    }

    func retry(target: IDEWorkerTarget, dryRun: Bool = false) async throws {
        try await retryHandler(target, dryRun)
    }

    func retask(target: IDEWorkerTarget, summary: String, dryRun: Bool = false) async throws {
        try await retaskHandler(target, summary, dryRun)
    }

    func terminate(target: IDEWorkerTarget, reason: String? = nil) async throws {
        try await terminateHandler(target, reason)
    }
}

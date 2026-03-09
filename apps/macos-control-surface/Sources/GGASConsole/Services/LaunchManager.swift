// LaunchManager.swift — starts harness backend services on app launch
//
// Starts the harness control-plane from the configured repo root.
// Captures stdout/stderr and publishes them as live log lines.
// Polls A2AClient.ping() until the server responds, then publishes online=true.

import Foundation
import SwiftUI

@MainActor
final class LaunchManager: ObservableObject {

    enum State {
        case idle           // never attempted
        case starting       // start.sh launched, waiting for ping
        case online         // A2A responded
        case offline        // ping failed after N retries
        case noScript       // start.sh not found
    }

    @Published var state: State = .idle
    @Published var statusMessage = ""
    @Published var cliOutput: [CLILine] = []   // live terminal lines
    @Published var compatibility: ControlPlaneCompatibility? = nil

    private var serverProcess: Process?

    struct CLILine: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    // Attempt auto-start on first call; idempotent after that.
    func start() async {
        guard state == .idle else { return }

        // Fast check — maybe services are already up
        let existingCompatibility = await A2AClient.shared.probeControlPlaneCompatibility()
        compatibility = existingCompatibility
        if existingCompatibility.compatible {
            state = .online
            let version = existingCompatibility.meta?.version ?? "unknown"
            statusMessage = "Services already running (v\(version))"
            appendLine("✓ Harness control-plane already online", error: false)
            return
        }
        if existingCompatibility.reachable {
            state = .offline
            statusMessage = existingCompatibility.message ?? "Running control-plane is incompatible"
            appendLine("⚠ \(existingCompatibility.message ?? "Running control-plane is incompatible with this app build.")", error: true)
            return
        }

        let projectRoot = ProjectSettings.shared.projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !projectRoot.isEmpty, FileManager.default.fileExists(atPath: projectRoot) else {
            state = .noScript
            statusMessage = "Project root not configured"
            appendLine("✗ Choose the harness project folder before starting services", error: true)
            return
        }

        state = .starting
        statusMessage = "Starting control-plane…"
        appendLine("→ Running: npm run control-plane:start", error: false)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["npm", "run", "control-plane:start"]
        proc.currentDirectoryURL = URL(fileURLWithPath: projectRoot)
        var env = ProcessInfo.processInfo.environment
        env["PROJECT_ROOT"] = projectRoot
        env["HARNESS_CONTROL_PLANE_PORT"] = String(ProjectSettings.shared.controlPlanePort)
        proc.environment = env

        // Capture stdout
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError  = stderrPipe

        // Stream stdout lines as they arrive
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            Task { @MainActor [weak self] in
                lines.forEach { self?.appendLine($0, error: false) }
            }
        }

        // Stream stderr lines
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
            Task { @MainActor [weak self] in
                lines.forEach { self?.appendLine($0, error: true) }
            }
        }

        do {
            try proc.run()
            serverProcess = proc
        } catch {
            state = .offline
            statusMessage = "Failed to launch control-plane: \(error.localizedDescription)"
            appendLine("✗ \(error.localizedDescription)", error: true)
            return
        }

        // Poll until online (up to 30s × 2s intervals = ~15 checks)
        for attempt in 1...15 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            statusMessage = "Waiting for control-plane… (\(attempt * 2)s)"
            let probe = await A2AClient.shared.probeControlPlaneCompatibility()
            compatibility = probe
            if probe.compatible {
                state = .online
                let version = probe.meta?.version ?? "unknown"
                statusMessage = "Services online ✓ (v\(version))"
                appendLine("✓ Harness control-plane is online", error: false)
                return
            }
            if probe.reachable, let message = probe.message {
                state = .offline
                statusMessage = message
                appendLine("✗ \(message)", error: true)
                return
            }
            if proc.isRunning == false {
                break
            }
        }

        // Timed out — services may still be starting, don't block the user
        state = .offline
        statusMessage = "Services taking longer than expected — check logs below"
        appendLine("⚠ Timed out waiting for the harness control-plane. Check npm output below.", error: true)
    }

    func restart() async {
        if let proc = serverProcess, proc.isRunning {
            proc.terminate()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        serverProcess = nil
        state = .idle
        cliOutput.removeAll()
        compatibility = nil
        await start()
    }

    func clearLog() {
        cliOutput.removeAll()
    }

    // MARK: - Private

    private func appendLine(_ text: String, error: Bool) {
        // Cap at 500 lines to avoid unbounded growth
        if cliOutput.count >= 500 { cliOutput.removeFirst(50) }
        cliOutput.append(CLILine(text: text, isError: error))
    }
}

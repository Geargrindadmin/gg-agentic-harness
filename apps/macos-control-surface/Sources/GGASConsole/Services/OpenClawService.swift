// OpenClawService.swift — OpenClaw local gateway daemon management

import AppKit
import Foundation
import Combine

// MARK: - OpenClaw channel status

struct OpenClawChannel: Identifiable {
    let id: String
    let label: String
    let icon: String
    var connected: Bool
}

// MARK: - Service

@MainActor
final class OpenClawService: ObservableObject {
    static let shared = OpenClawService()

    @Published var isRunning = false
    @Published var channels: [OpenClawChannel] = [
        OpenClawChannel(id: "telegram",  label: "Telegram",  icon: "paperplane.fill",   connected: false),
        OpenClawChannel(id: "whatsapp",  label: "WhatsApp",  icon: "message.fill",       connected: false),
        OpenClawChannel(id: "discord",   label: "Discord",   icon: "gamecontroller.fill", connected: false),
    ]
    @Published var lastError: String? = nil

    private let port = 18789
    private var process: Process? = nil
    private var pollTask: Task<Void, Never>? = nil

    // Dedicated ephemeral session — avoids CFXCookieStorage SIGSEGV crash
    // that occurs when URLSession.shared resolves cookies for localhost URLs
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest  = 3
        cfg.timeoutIntervalForResource = 5
        return URLSession(configuration: cfg)
    }()

    private init() {
        // Delay polling start so SwiftUI window is fully initialised before
        // any URLSession activity (immediate use during init crashes CFNetwork)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 s
            self?.startPolling()
        }
    }

    // MARK: - Public

    func start() {
        guard !isRunning else { return }
        lastError = nil

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["npx", "openclaw", "gateway", "--port", "\(port)"]
        p.environment = ProcessInfo.processInfo.environment

        do {
            try p.run()
            process = p
        } catch {
            lastError = "Failed to start OpenClaw: \(error.localizedDescription)"
        }
    }

    func stop() {
        process?.interrupt()
        process = nil
        isRunning = false
    }

    func openBrowser() {
        guard let url = URL(string: "http://127.0.0.1:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await checkHealth()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func checkHealth() async {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/health") else { return }
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run { isRunning = false }
                return
            }
            var newChannels = channels
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let chans = json["channels"] as? [String: Bool] {
                for i in newChannels.indices {
                    newChannels[i].connected = chans[newChannels[i].id] ?? false
                }
            }
            await MainActor.run {
                isRunning = true
                lastError = nil
                channels = newChannels
            }
        } catch {
            await MainActor.run { isRunning = false }
        }
    }
}

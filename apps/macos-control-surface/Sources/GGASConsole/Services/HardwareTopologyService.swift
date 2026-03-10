// HardwareTopologyService.swift — Detects network topology and calculates safe agent capacity.
// Architecture inspired by exo-explore/exo HardwareTopologyDetector (Apache 2.0).
// Pattern: NetworkInterface enumeration via `networksetup`, capacity math via host RAM.
// All detection is best-effort (silent failure if CLI unavailable).

import Foundation
import Darwin   // sysctl for RAM

// MARK: - Network interface

struct NetworkInterface: Identifiable {
    let id: String              // e.g. "en0"
    let displayName: String     // e.g. "Thunderbolt Bridge"
    let isThunderbolt: Bool
    let isWifi: Bool
    let isEthernet: Bool
}

// MARK: - Capacity result

struct AgentCapacity {
    let maxConcurrentAgents: Int
    let availableRAMGB: Double
    let reservedRAMGB: Double   // 20% safety margin
    let perAgentRAMGB: Double   // estimated RAM per agent
    let note: String
}

// MARK: - Service

@MainActor
final class HardwareTopologyService: ObservableObject {

    static let shared = HardwareTopologyService()

    @Published private(set) var interfaces: [NetworkInterface] = []
    @Published private(set) var totalRAMGB: Double = 0
    @Published private(set) var availableRAMGB: Double = 0
    @Published private(set) var hasThunderboltBridge: Bool = false
    @Published private(set) var lastCapacity: AgentCapacity?

    private init() {
        Task { await refresh() }
    }

    // MARK: - Refresh

    func refresh() async {
        totalRAMGB     = readTotalRAMGB()
        availableRAMGB = readAvailableRAMGB()
        interfaces     = await detectInterfaces()
        hasThunderboltBridge = interfaces.contains { $0.isThunderbolt }
        lastCapacity = calculateCapacity(
            totalRAMGB: totalRAMGB,
            availableRAMGB: availableRAMGB,
            modelVRAMGB: 0,
            perAgentOverheadGB: 0.5
        )
    }

    // MARK: - Capacity calculation (conservative — 80% of available RAM)
    //
    // Formula (board directive: conservative, prevent OOM):
    //   maxAgents = floor( availableRAM * 0.80 / perAgentRAM )
    //   clamped to [0, 64]
    //
    // Parameters:
    //   modelVRAMGB: estimated VRAM/RAM the model itself occupies
    //   perAgentOverheadGB: per-agent process overhead (default: 0.5 GB)

    func maxConcurrentAgents(modelVRAMGB: Double = 0,
                              perAgentOverheadGB: Double = 0.5) -> AgentCapacity {
        calculateCapacity(
            totalRAMGB: totalRAMGB,
            availableRAMGB: availableRAMGB,
            modelVRAMGB: modelVRAMGB,
            perAgentOverheadGB: perAgentOverheadGB
        )
    }

    private func calculateCapacity(
        totalRAMGB: Double,
        availableRAMGB: Double,
        modelVRAMGB: Double,
        perAgentOverheadGB: Double
    ) -> AgentCapacity {
        let reserved       = max(2.0, totalRAMGB * 0.20)  // 20% floor or 2 GB
        let afterModel     = max(0, availableRAMGB - modelVRAMGB)  // subtract loaded model footprint
        let usable         = max(0, afterModel - reserved)
        let perAgent       = max(0.1, perAgentOverheadGB)
        let raw            = usable / perAgent
        let clamped        = max(0, min(64, Int(raw.rounded(.down))))

        let note: String
        if clamped == 0 {
            note = "Insufficient free memory — pause spawns or reduce local model load"
        } else if clamped >= 30 {
            note = "High capacity — system can run large swarms"
        } else if clamped >= 10 {
            note = "Medium capacity — standard swarms supported"
        } else {
            note = "Low capacity — limit spawning, close other apps"
        }

        return AgentCapacity(
            maxConcurrentAgents: clamped,
            availableRAMGB: availableRAMGB,
            reservedRAMGB: reserved,
            perAgentRAMGB: perAgent,
            note: note
        )
    }

    // MARK: - Thunderbolt detection

    private func detectInterfaces() async -> [NetworkInterface] {
        // `networksetup -listallhardwareports` is available on all macOS versions
        let output = await runShell("networksetup -listallhardwareports 2>/dev/null")
        guard !output.isEmpty else { return [] }

        var result: [NetworkInterface] = []
        let blocks = output.components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            var portName = ""
            var device   = ""
            for line in lines {
                if line.hasPrefix("Hardware Port:") {
                    portName = line.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Device:") {
                    device = line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
            guard !portName.isEmpty, !device.isEmpty else { continue }
            let lower = portName.lowercased()
            result.append(NetworkInterface(
                id: device,
                displayName: portName,
                isThunderbolt: lower.contains("thunderbolt") || lower.contains("usb-c"),
                isWifi: lower.contains("wi-fi") || lower.contains("airport"),
                isEthernet: lower.contains("ethernet") || lower.contains("lan")
            ))
        }
        return result
    }

    // MARK: - RAM reads (sysctl — no entitlements needed)

    private func readTotalRAMGB() -> Double {
        var size: UInt64 = 0
        var sizeLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &sizeLen, nil, 0)
        return Double(size) / (1024 * 1024 * 1024)
    }

    private func readAvailableRAMGB() -> Double {
        // Approximation: total - wired - active pages
        var vmStats = vm_statistics64()
        var count   = mach_msg_type_number_t(MemoryLayout.size(ofValue: vmStats) / MemoryLayout<integer_t>.size)
        let result  = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return totalRAMGB * 0.5 }
        let pageSize    = UInt64(vm_kernel_page_size)
        let freePages   = UInt64(vmStats.free_count) + UInt64(vmStats.inactive_count)
        return Double(freePages * pageSize) / (1024 * 1024 * 1024)
    }

    // MARK: - Shell helper

    private func runShell(_ cmd: String) async -> String {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/bin/bash")
                proc.arguments = ["-c", cmd]
                let pipe = Pipe()
                proc.standardOutput = pipe
                proc.standardError  = Pipe()
                try? proc.run()
                proc.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }
}

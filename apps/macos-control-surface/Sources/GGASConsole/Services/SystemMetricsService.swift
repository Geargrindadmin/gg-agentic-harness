// SystemMetricsService.swift — Native IOKit/host_statistics system metrics
// Inspired by exelban/stats (MIT) methodology — pure Swift, no external deps

import Foundation
import IOKit
import Network
import Darwin

// MARK: - Published metrics model

struct SystemMetrics {
    var cpuPct: Double    = 0   // 0–100
    var ramUsedGB: Double = 0
    var ramTotalGB: Double = 0
    var netInKBs: Double  = 0   // KB/s download
    var netOutKBs: Double = 0   // KB/s upload
    var gpuPct: Double    = 0   // 0–100 (best-effort via IOKit accelerator)
}

// MARK: - Service

@MainActor
final class SystemMetricsService: ObservableObject {
    static let shared = SystemMetricsService()

    @Published var metrics = SystemMetrics()

    private var timer: Timer?

    // CPU tick tracking — we own this memory between calls
    private var prevCPUInfo: processor_info_array_t?
    private var prevNumCPUInfo: mach_msg_type_number_t = 0

    // Network byte tracking
    private var prevNetIn:  UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var prevNetTime: Date  = .now

    private init() {}

    func start() {
        guard timer == nil else { return }
        refreshMetrics()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshMetrics() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshMetrics() {
        var m = SystemMetrics()
        m.cpuPct     = readCPU()
        (m.ramUsedGB, m.ramTotalGB) = readRAM()
        (m.netInKBs, m.netOutKBs) = readNet()
        m.gpuPct     = readGPUPct()
        metrics = m
    }

    // MARK: CPU — host_processor_info

    private func readCPU() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &numCPUs, &cpuInfo, &numCPUInfo)
        guard result == KERN_SUCCESS, let cpuInfo else { return 0 }
        // IMPORTANT: No defer here — cpuInfo ownership is transferred to prevCPUInfo.
        // A defer block would free the memory before we can store it, causing a
        // use-after-free (SIGSEGV) on the next invocation when we read prevCPUInfo.

        // Use signed Int64 to avoid UInt64 arithmetic overflow on counter reset
        var userDiff: Int64 = 0; var sysDiff: Int64 = 0
        var idleDiff: Int64 = 0; var niceDiff: Int64 = 0

        let statesPerCPU = Int(CPU_STATE_MAX)
        let availableCPUSlots = Int(numCPUInfo) / statesPerCPU
        let currentCPUCount = min(Int(numCPUs), availableCPUSlots)
        let previousCPUSlots = Int(prevNumCPUInfo) / statesPerCPU

        for i in 0..<currentCPUCount {
            let base = statesPerCPU * i
            let user   = Int64(cpuInfo[base + Int(CPU_STATE_USER)])
            let system = Int64(cpuInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle   = Int64(cpuInfo[base + Int(CPU_STATE_IDLE)])
            let nice   = Int64(cpuInfo[base + Int(CPU_STATE_NICE)])

            if let prev = prevCPUInfo, i < previousCPUSlots {
                let pu = Int64(prev[base + Int(CPU_STATE_USER)])
                let ps = Int64(prev[base + Int(CPU_STATE_SYSTEM)])
                let pi = Int64(prev[base + Int(CPU_STATE_IDLE)])
                let pn = Int64(prev[base + Int(CPU_STATE_NICE)])
                // Guard against counter reset: negative diff = skip (contribute 0)
                userDiff += max(0, user - pu)
                sysDiff  += max(0, system - ps)
                idleDiff += max(0, idle - pi)
                niceDiff += max(0, nice - pn)
            }
        }

        let totalDiff = userDiff + sysDiff + idleDiff + niceDiff
        let busyDiff  = userDiff + sysDiff + niceDiff
        let pct = totalDiff > 0 ? Double(busyDiff) / Double(totalDiff) * 100 : 0

        // Free the PREVIOUS snapshot, then take ownership of the CURRENT one.
        if let prev = prevCPUInfo {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: prev),
                          vm_size_t(prevNumCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        prevCPUInfo    = cpuInfo
        prevNumCPUInfo = numCPUInfo

        return pct
    }

    // MARK: RAM — host_vm_info64

    private func readRAM() -> (Double, Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }

        let pageSize = Double(vm_page_size)
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        return (used / 1_073_741_824, total / 1_073_741_824)  // bytes → GB
    }

    // MARK: Network — getifaddrs

    private func readNet() -> (Double, Double) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0

        var ptr = ifaddr
        while let addr = ptr {
            let name = String(cString: addr.pointee.ifa_name)
            // Include physical & WiFi interfaces, skip loopback/tunnels
            if !name.hasPrefix("lo") && !name.hasPrefix("utun") && !name.hasPrefix("llw") {
                if addr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                    let data = unsafeBitCast(addr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                    inBytes  += UInt64(data.pointee.ifi_ibytes)
                    outBytes += UInt64(data.pointee.ifi_obytes)
                }
            }
            ptr = addr.pointee.ifa_next
        }

        let now = Date.now
        let dt  = now.timeIntervalSince(prevNetTime)
        // Guard against counter reset (e.g. after sleep) which would underflow UInt64
        let inKBs  = dt > 0 && prevNetIn  > 0 && inBytes  >= prevNetIn  ? Double(inBytes  - prevNetIn)  / dt / 1024 : 0
        let outKBs = dt > 0 && prevNetOut > 0 && outBytes >= prevNetOut ? Double(outBytes - prevNetOut) / dt / 1024 : 0

        prevNetIn   = inBytes
        prevNetOut  = outBytes
        prevNetTime = now

        return (max(0, inKBs), max(0, outKBs))
    }

    // MARK: GPU — IOKit IOAccelerator

    private func readGPUPct() -> Double {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }

        var maxUtil = 0.0
        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }

            var propsRaw: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &propsRaw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = propsRaw?.takeRetainedValue() as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any] {
                let util = (stats["Device Utilization %"] as? Double)
                    ?? (stats["GPU Core Utilization"] as? Double).map { $0 / 10_000_000 }
                    ?? 0
                if util > maxUtil { maxUtil = util }
            }
        }
        return min(maxUtil, 100)
    }
}

//
//  SystemMonitor.swift
//  MyWallpaperX
//
//  状态栏指标 — 应用 CPU / 内存，系统网络 / GPU
//  本文件遵循 macOS26 设计规范，尽量调用原生接口实现
//

import Foundation
import Darwin
import IOKit

// MARK: - 数据模型

struct SystemStats {
    /// 本应用、登记的播放进程及其子进程 CPU；1.0 表示占用一个核心。首次采样无差值。
    var cpuUsage: Double?
    /// 本应用、登记的播放进程及其子进程物理内存占用（字节）。
    var memUsed: UInt64?
    /// 网络上行字节/秒
    var netUpBytesPerSec: Double = 0
    /// 网络下行字节/秒
    var netDownBytesPerSec: Double = 0
    /// GPU 使用率 0.0 ~ 1.0，nil 表示读取失败
    var gpuUsage: Double? = nil
}

// MARK: - SystemMonitor

/// 轻量系统指标采集器。
/// 调用 `refreshRuntimeStats()` 更新 `stats`，由外部驱动（菜单打开时 / 定时器）。
/// 网速计算需要两次采样差值，第一次调用时速率显示为 0。
final class SystemMonitor {

    static let shared = SystemMonitor()

    private(set) var stats = SystemStats()

    // 网络上次采样
    private var lastNetUp: UInt64 = 0
    private var lastNetDown: UInt64 = 0
    private var lastNetSampleTime: Date?

    private var processSamples: [Int32: (started: UInt64, cpuTicks: Double)] = [:]
    private var lastProcessSampleTime: TimeInterval?
    private let processSecondsPerTick: Double? = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return nil }
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    private init() {}

    // MARK: - 主入口

    /// 刷新状态栏运行时指标。
    func refreshRuntimeStats(includeNetwork: Bool = false) {
        if includeNetwork { readNetwork(into: &stats) }
        stats.gpuUsage = readGPUUsage()
    }

    func endNetworkSampling() {
        lastNetSampleTime = nil
        stats.netUpBytesPerSec = 0
        stats.netDownBytesPerSec = 0
    }

    /// Called on the existing status clock only while the panel is visible.
    /// Passing no processes ends that visible sampling session. Discover children
    /// of the App and its live playback roots only on this existing sampling clock.
    func refreshApplicationStats(processIdentifiers: [Int32]) {
        let now = ProcessInfo.processInfo.systemUptime
        var next: [Int32: (started: UInt64, cpuTicks: Double)] = [:]
        var footprint: UInt64 = 0
        var elapsedTicks: Double = 0
        var matchedProcesses = 0
        for pid in applicationProcessIdentifiers(roots: processIdentifiers) {
            var usage = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard result == 0 else { continue }
            let ticks = Double(usage.ri_user_time) + Double(usage.ri_system_time)
            next[pid] = (usage.ri_proc_start_abstime, ticks)
            footprint += usage.ri_phys_footprint
            if let previous = processSamples[pid], previous.started == usage.ri_proc_start_abstime {
                elapsedTicks += ticks - previous.cpuTicks
                matchedProcesses += 1
            }
        }
        if let last = lastProcessSampleTime, now > last, let secondsPerTick = processSecondsPerTick,
           matchedProcesses > 0 {
            stats.cpuUsage = elapsedTicks * secondsPerTick / (now - last)
        } else { stats.cpuUsage = nil }
        stats.memUsed = next.isEmpty ? nil : footprint
        processSamples = next
        lastProcessSampleTime = next.isEmpty ? nil : now
    }

    /// Unregistered workers (Steam acquisition, shader compilation, nested helpers)
    /// belong to the App through their parent, not through an executable name.
    private func applicationProcessIdentifiers(roots: [Int32]) -> [Int32] {
        var processes: [Int32] = []
        var seen = Set<Int32>()
        for pid in roots where pid > 0 && seen.insert(pid).inserted { processes.append(pid) }
        var index = 0
        while index < processes.count {
            let parent = processes[index]
            index += 1
            let count = proc_listchildpids(parent, nil, 0)
            guard count > 0 else { continue }
            var children = [Int32](repeating: 0, count: Int(count))
            let returned = children.withUnsafeMutableBytes {
                proc_listchildpids(parent, $0.baseAddress, Int32($0.count))
            }
            for pid in children.prefix(Int(max(0, returned))) where pid > 0 && seen.insert(pid).inserted {
                processes.append(pid)
            }
        }
        return processes
    }

    // MARK: - 网络速率

    private func readNetwork(into s: inout SystemStats) {
        let (up, down) = rawNetworkBytes()
        let now = Date()
        if let previous = lastNetSampleTime, now.timeIntervalSince(previous) > 0.1 {
            let elapsed = now.timeIntervalSince(previous)
            let dUp   = up   >= lastNetUp   ? up   - lastNetUp   : 0
            let dDown = down >= lastNetDown ? down - lastNetDown : 0
            s.netUpBytesPerSec   = Double(dUp)   / elapsed
            s.netDownBytesPerSec = Double(dDown) / elapsed
        }

        lastNetUp         = up
        lastNetDown       = down
        lastNetSampleTime = now
    }

    private func rawNetworkBytes() -> (up: UInt64, down: UInt64) {
        var up: UInt64 = 0
        var down: UInt64 = 0
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddrPtr) == 0, let base = ifaddrPtr else { return (0, 0) }
        defer { freeifaddrs(base) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = base
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard ifa.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            // 跳过回环和虚拟接口，只统计物理网卡
            let skip = name.hasPrefix("lo") || name.hasPrefix("utun") ||
                       name.hasPrefix("ipsec") || name.hasPrefix("gif") ||
                       name.hasPrefix("stf") || name.hasPrefix("XHC") ||
                       name.hasPrefix("bridge") || name.hasPrefix("p2p")
            guard !skip else { continue }

            if let dataPtr = ifa.pointee.ifa_data {
                let ifData = dataPtr.load(as: if_data.self)
                up   &+= UInt64(ifData.ifi_obytes)
                down &+= UInt64(ifData.ifi_ibytes)
            }
        }
        return (up, down)
    }

    // MARK: - GPU 使用率（IOAccelerator，沙盒可用）

    private func readGPUUsage() -> Double? {
        let matchDict = IOServiceMatching("IOAccelerator") as NSMutableDictionary
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var maxUsage: Double? = nil
        var service = IOIteratorNext(iter)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }
            var props: Unmanaged<CFMutableDictionary>? = nil
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }

            // Apple Silicon / AMD: PerformanceStatistics 字典内含 GPU Core Utilization
            if let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                // Apple Silicon
                if let util = perfStats["GPU Core Utilization"] as? Double {
                    let pct = util / 1_000_000.0   // 单位是 millipercent (1e-6)
                    maxUsage = max(maxUsage ?? 0, min(1.0, pct))
                } else if let util = perfStats["Device Utilization %"] as? Double {
                    maxUsage = max(maxUsage ?? 0, min(1.0, util / 100.0))
                } else if let util = perfStats["Accelerator Utilization"] as? Int {
                    maxUsage = max(maxUsage ?? 0, min(1.0, Double(util) / 100.0))
                }
            }
        }
        return maxUsage
    }
}

// MARK: - 格式化工具

extension SystemStats {
    /// CPU 百分比字符串，如 "12%"
    var cpuUsageString: String {
        guard let cpuUsage else { return "–" }
        return String(format: "%d%%", Int((cpuUsage * 100).rounded()))
    }

    /// GPU 百分比字符串，如 "34%"，读不到时返回 "–"
    var gpuUsageString: String {
        guard let g = gpuUsage else { return "–" }
        return String(format: "%d%%", Int((g * 100).rounded()))
    }

    /// 已用内存字符串，如 "6.8 GB"
    var memUsedString: String { memUsed.map { formatBytes($0, style: .memory) } ?? "–" }

    /// 网络上行速率，如 "2.1 MB/s"
    var netUpString: String { formatBytes(UInt64(netUpBytesPerSec), style: .speed) }

    /// 网络下行速率，如 "850 KB/s"
    var netDownString: String { formatBytes(UInt64(netDownBytesPerSec), style: .speed) }

    private enum FormatStyle { case memory, speed }

    private func formatBytes(_ bytes: UInt64, style: FormatStyle) -> String {
        let suffix = style == .speed ? "/s" : ""
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        let gb = mb / 1024
        if gb >= 1 { return String(format: "%.1f GB", gb) + suffix }
        if mb >= 1 { return String(format: "%.1f MB", mb) + suffix }
        if kb >= 1 { return String(format: "%.0f KB", kb) + suffix }
        return "\(bytes) B" + suffix
    }
}

//
//  SystemMonitor.swift
//  MyWallpaperX
//
//  系统状态监控 — CPU、内存、网络速率、GPU 使用率
//  本文件遵循 macOS26 设计规范，尽量调用原生接口实现
//

import Foundation
import Darwin
import IOKit

// MARK: - 数据模型

struct SystemStats {
    /// CPU 总使用率 0.0 ~ 1.0
    var cpuUsage: Double = 0
    /// 已用物理内存（字节）
    var memUsed: UInt64 = 0
    /// 总物理内存（字节）
    var memTotal: UInt64 = 0
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
    private var lastNetSampleTime: Date = .distantPast

    // CPU 上次采样的 ticks
    private var lastCPUTicks: (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32) = (0, 0, 0, 0)

    private init() {}

    // MARK: - 主入口

    /// 刷新状态栏运行时指标。
    func refreshRuntimeStats() {
        stats.cpuUsage  = readCPUUsage()
        readMemory(into: &stats)
        readNetwork(into: &stats)
        stats.gpuUsage  = readGPUUsage()
    }

    // MARK: - CPU 使用率

    private func readCPUUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return stats.cpuUsage }

        let user = info.cpu_ticks.0
        let sys  = info.cpu_ticks.1
        let idle = info.cpu_ticks.2
        let nice = info.cpu_ticks.3

        // Mach ticks wrap at their native 32-bit width; widen only the deltas.
        let dUser  = UInt64(user &- lastCPUTicks.user)
        let dSys   = UInt64(sys  &- lastCPUTicks.sys)
        let dIdle  = UInt64(idle &- lastCPUTicks.idle)
        let dNice  = UInt64(nice &- lastCPUTicks.nice)
        let dTotal = dUser + dSys + dIdle + dNice

        lastCPUTicks = (user, sys, idle, nice)
        guard dTotal > 0 else { return stats.cpuUsage }
        return Double(dUser + dSys + dNice) / Double(dTotal)
    }

    // MARK: - 内存

    private func readMemory(into s: inout SystemStats) {
        s.memTotal = ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let page       = UInt64(vm_page_size)
        let wired      = UInt64(vmStats.wire_count)            * page
        let active     = UInt64(vmStats.active_count)          * page
        let compressed = UInt64(vmStats.compressor_page_count) * page
        s.memUsed = wired + active + compressed
    }

    // MARK: - 网络速率

    private func readNetwork(into s: inout SystemStats) {
        let (up, down) = rawNetworkBytes()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastNetSampleTime)

        if elapsed > 0.1 && (lastNetUp > 0 || lastNetDown > 0) {
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
        String(format: "%d%%", Int((cpuUsage * 100).rounded()))
    }

    /// GPU 百分比字符串，如 "34%"，读不到时返回 "–"
    var gpuUsageString: String {
        guard let g = gpuUsage else { return "–" }
        return String(format: "%d%%", Int((g * 100).rounded()))
    }

    /// 已用内存字符串，如 "6.8 GB"
    var memUsedString: String { formatBytes(memUsed, style: .memory) }

    /// 总内存字符串，如 "16 GB"
    var memTotalString: String { formatBytes(memTotal, style: .memory) }

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

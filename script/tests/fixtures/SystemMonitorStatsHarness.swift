import Darwin
import Foundation

// ACTUAL_SYSTEM_STATS
// ACTUAL_FORMATTING

// Only the OS clock / native rusage read and timebase answer are controlled.
// Production identity matching, baseline lifetime, tick conversion and totals run unchanged.
@MainActor private enum MonitorProcessRead {
    static var now: TimeInterval = 0
    static var usages: [Int32: rusage_info_v4] = [:]
    static var calls: [Int32] = []
    static var children: [Int32: [Int32]] = [:]
    static var childQueries: [Int32] = []
    static var useNativeTree = false
    static func listChildren(_ parent: Int32, _ output: UnsafeMutableRawPointer?, _ capacity: Int32) -> Int32 {
        if useNativeTree { return proc_listchildpids(parent, output, capacity) }
        guard let output else {
            childQueries.append(parent)
            return Int32(children[parent]?.count ?? 0)
        }
        let values = Array((children[parent] ?? []).prefix(Int(capacity) / MemoryLayout<Int32>.stride))
        values.withUnsafeBytes { bytes in output.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count) }
        return Int32(values.count)
    }
    static var timebaseCalls = 0
    static var timebaseAvailable = true
    static func timebase(_ output: UnsafeMutablePointer<mach_timebase_info_data_t>) -> kern_return_t {
        timebaseCalls += 1
        output.pointee = mach_timebase_info_data_t(numer: 125, denom: 3)
        return timebaseAvailable ? KERN_SUCCESS : KERN_FAILURE
    }
    static func read(_ pid: Int32, _ flavor: Int32, _ output: UnsafeMutablePointer<rusage_info_t?>) -> Int32 {
        calls.append(pid)
        precondition(flavor == RUSAGE_INFO_V4)
        if useNativeTree || pid == getpid() { return proc_pid_rusage(pid, flavor, output) }
        guard let usage = usages[pid] else { return -1 }
        UnsafeMutableRawPointer(output).assumingMemoryBound(to: rusage_info_v4.self).pointee = usage
        return 0
    }
    static func usage(started: UInt64, user: UInt64, system: UInt64, footprint: UInt64) -> rusage_info_v4 {
        var usage = rusage_info_v4()
        usage.ri_proc_start_abstime = started
        usage.ri_user_time = user
        usage.ri_system_time = system
        usage.ri_phys_footprint = footprint
        return usage
    }
}

@MainActor private enum MonitorRuntimeRead {
    static var now = Date(timeIntervalSince1970: 0)
    static var bytes: (up: UInt64, down: UInt64) = (0, 0)
    static var networkReads = 0, gpuReads = 0
}

@MainActor private final class SystemMonitor {
    // ACTUAL_PROCESS_STATE
    // ACTUAL_PROCESS_SAMPLER
    // ACTUAL_RUNTIME_STATE
    // ACTUAL_RUNTIME_SAMPLER
    private func rawNetworkBytes() -> (up: UInt64, down: UInt64) {
        MonitorRuntimeRead.networkReads += 1
        return MonitorRuntimeRead.bytes
    }
    private func readGPUUsage() -> Double? { MonitorRuntimeRead.gpuReads += 1; return 0.25 }
    var sampledPIDs: Set<Int32> { Set(processSamples.keys) }
}

@main private enum SystemMonitorStatsChecks {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ value: Bool) { precondition(value, name); checks[name] = value }
        func near(_ actual: Double?, _ expected: Double) -> Bool {
            actual.map { abs($0 - expected) < 0.000_000_1 } == true
        }
        func sample(_ monitor: SystemMonitor, at time: Double, pids: [Int32], expectedReadPIDs: [Int32]? = nil) {
            MonitorProcessRead.now = time
            MonitorProcessRead.calls = []
            monitor.refreshApplicationStats(processIdentifiers: pids)
            check("one-native-read-per-requested-pid-at-\(time)", MonitorProcessRead.calls == (expectedReadPIDs ?? pids))
        }
        let monitor = SystemMonitor()
        check("unavailable-until-native-sample", monitor.stats.cpuUsage == nil && monitor.stats.memUsed == nil)
        MonitorProcessRead.usages = [
            1: MonitorProcessRead.usage(started: 10, user: 100_000_000, system: 20_000_000, footprint: 100),
            2: MonitorProcessRead.usage(started: 20, user: 50_000_000, system: 10_000_000, footprint: 200)]
        sample(monitor, at: 0, pids: [1, 2])
        check("first-visible-sample-has-no-cpu-history", monitor.stats.cpuUsage == nil && monitor.stats.memUsed == 300)
        MonitorProcessRead.usages[1]!.ri_user_time += 12_000_000
        MonitorProcessRead.usages[1]!.ri_system_time += 12_000_000
        MonitorProcessRead.usages[2]!.ri_user_time += 24_000_000
        sample(monitor, at: 2, pids: [1, 2])
        check("mach-timebase-and-all-process-cpu-are-summed", near(monitor.stats.cpuUsage, 1))
        check("timebase-is-queried-once-not-every-sample", MonitorProcessRead.timebaseCalls == 1)
        MonitorProcessRead.usages[3] = MonitorProcessRead.usage(started: 30, user: 9_000_000_000, system: 0, footprint: 400)
        MonitorProcessRead.usages[1]!.ri_user_time += 24_000_000
        sample(monitor, at: 4, pids: [1, 3])
        check("new-helper-starts-a-baseline-without-historical-spike", near(monitor.stats.cpuUsage, 0.5))
        check("removed-helper-leaves-memory-and-cpu-baselines", monitor.stats.memUsed == 500 && monitor.sampledPIDs == [1, 3])
        MonitorProcessRead.usages[1] = MonitorProcessRead.usage(started: 11, user: 90_000_000_000, system: 0, footprint: 150)
        MonitorProcessRead.usages[3]!.ri_system_time += 12_000_000
        sample(monitor, at: 6, pids: [1, 3])
        check("pid-reuse-cannot-count-previous-process-history", near(monitor.stats.cpuUsage, 0.25) && monitor.stats.memUsed == 550)
        MonitorProcessRead.usages[1]!.ri_user_time += 48_000_000
        sample(monitor, at: 8, pids: [1, 99])
        check("one-ended-process-does-not-hide-live-process-metrics", near(monitor.stats.cpuUsage, 1) && monitor.stats.memUsed == 150)
        sample(monitor, at: 10, pids: [99])
        check("all-failed-reads-show-unavailable-without-stale-values", monitor.stats.cpuUsage == nil
            && monitor.stats.memUsed == nil && monitor.sampledPIDs.isEmpty)
        sample(monitor, at: 12, pids: [1])
        check("new-readable-session-rebaselines", monitor.stats.cpuUsage == nil && monitor.stats.memUsed == 150)
        sample(monitor, at: 14, pids: [])
        check("closing-panel-does-no-native-reads-and-drops-baselines", monitor.stats.cpuUsage == nil
            && monitor.stats.memUsed == nil && monitor.sampledPIDs.isEmpty)
        MonitorProcessRead.usages[1]!.ri_user_time += 9_000_000_000
        sample(monitor, at: 3600, pids: [1])
        check("reopening-does-not-average-hidden-time", monitor.stats.cpuUsage == nil)
        MonitorProcessRead.usages[1]!.ri_system_time += 72_000_000
        sample(monitor, at: 3602, pids: [1])
        check("multicore-cpu-is-not-clamped-to-one-core", near(monitor.stats.cpuUsage, 1.5) && monitor.stats.cpuUsageString == "150%")
        sample(monitor, at: 3604, pids: [1])
        check("idle-process-cpu-is-zero", monitor.stats.cpuUsage == 0)
        MonitorProcessRead.timebaseAvailable = false
        let unavailableTimebase = SystemMonitor()
        sample(unavailableTimebase, at: 3606, pids: [1])
        sample(unavailableTimebase, at: 3608, pids: [1])
        check("failed-timebase-does-not-fabricate-cpu", unavailableTimebase.stats.cpuUsage == nil
            && unavailableTimebase.stats.cpuUsageString == "–" && unavailableTimebase.stats.memUsed == 150)
        MonitorProcessRead.timebaseAvailable = true
        let native = SystemMonitor()
        sample(native, at: 3610, pids: [getpid()])
        check("real-native-process-footprint-is-readable", (native.stats.memUsed ?? 0) > 0)
        sample(native, at: 3612, pids: [getpid()])
        check("real-native-cpu-sample-is-nonnegative", native.stats.cpuUsage.map { $0 >= 0 } == true)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["10"]
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        MonitorProcessRead.useNativeTree = true
        sample(native, at: 3614, pids: [getpid()], expectedReadPIDs: [getpid(), child.processIdentifier])
        check("real-child-process-is-discovered-and-sampled", native.sampledPIDs == [getpid(), child.processIdentifier]
            && (native.stats.memUsed ?? 0) > 0)
        MonitorProcessRead.useNativeTree = false

        MonitorProcessRead.usages = Dictionary(uniqueKeysWithValues: (1...6).map {
            (Int32($0), MonitorProcessRead.usage(started: UInt64($0), user: 100_000, system: 0, footprint: UInt64($0 * 100)))
        })
        MonitorProcessRead.children = [1: [2, 3], 2: [4], 3: [5], 99: [6]]
        MonitorProcessRead.childQueries = []
        let family = SystemMonitor()
        sample(family, at: 4000, pids: [1, 2, 1, 0, -1], expectedReadPIDs: [1, 2, 3, 4, 5])
        check("registered-roots-and-nested-workers-are-counted-once", family.sampledPIDs == [1, 2, 3, 4, 5]
            && family.stats.memUsed == 1_500 && MonitorProcessRead.childQueries == [1, 2, 3, 4, 5])
        check("unrelated-process-tree-is-never-enumerated", !MonitorProcessRead.childQueries.contains(99)
            && !family.sampledPIDs.contains(6))
        MonitorProcessRead.usages[1]!.ri_user_time += 24_000_000
        MonitorProcessRead.usages[5]!.ri_system_time += 24_000_000
        sample(family, at: 4002, pids: [1, 2], expectedReadPIDs: [1, 2, 3, 4, 5])
        check("nested-worker-cpu-joins-the-same-monotonic-total", near(family.stats.cpuUsage, 1))
        MonitorProcessRead.children = [1: [2]]
        MonitorProcessRead.usages[1]!.ri_user_time += 24_000_000
        sample(family, at: 4004, pids: [1], expectedReadPIDs: [1, 2])
        check("ended-worker-tree-leaves-current-totals", family.sampledPIDs == [1, 2]
            && family.stats.memUsed == 300 && near(family.stats.cpuUsage, 0.5))
        let queriesBeforeClose = MonitorProcessRead.childQueries
        sample(family, at: 4006, pids: [])
        check("closing-does-not-enumerate-processes", MonitorProcessRead.childQueries == queriesBeforeClose
            && family.sampledPIDs.isEmpty && family.stats.memUsed == nil && family.stats.cpuUsage == nil)

        var formatting = SystemStats()
        check("missing-process-values-format-as-unavailable", formatting.cpuUsageString == "–" && formatting.memUsedString == "–")
        formatting.memUsed = 2_147_483_648
        check("process-memory-has-no-system-total-denominator", formatting.memUsedString == "2.0 GB")
        let runtime = SystemMonitor()
        for _ in 0..<3 { runtime.refreshRuntimeStats() }
        check("closed-panel-keeps-gpu-icon-with-zero-network-reads", MonitorRuntimeRead.gpuReads == 3
            && MonitorRuntimeRead.networkReads == 0 && runtime.stats.gpuUsage == 0.25)
        MonitorRuntimeRead.bytes = (1_000, 2_000)
        runtime.refreshRuntimeStats(includeNetwork: true)
        check("opening-network-session-primes-without-a-fabricated-rate", MonitorRuntimeRead.networkReads == 1
            && runtime.stats.netUpBytesPerSec == 0 && runtime.stats.netDownBytesPerSec == 0)
        MonitorRuntimeRead.now = Date(timeIntervalSince1970: 2)
        MonitorRuntimeRead.bytes = (1_200, 2_600)
        runtime.refreshRuntimeStats(includeNetwork: true)
        check("visible-network-samples-use-the-current-session-difference", runtime.stats.netUpBytesPerSec == 100
            && runtime.stats.netDownBytesPerSec == 300)
        runtime.endNetworkSampling()
        MonitorRuntimeRead.now = Date(timeIntervalSince1970: 3_600)
        MonitorRuntimeRead.bytes = (1_000_000, 2_000_000)
        runtime.refreshRuntimeStats()
        check("ending-network-session-does-no-read-and-drops-the-rate", MonitorRuntimeRead.networkReads == 2
            && runtime.stats.netUpBytesPerSec == 0 && runtime.stats.netDownBytesPerSec == 0)
        runtime.refreshRuntimeStats(includeNetwork: true)
        check("reopening-never-averages-traffic-from-hidden-time", runtime.stats.netUpBytesPerSec == 0
            && runtime.stats.netDownBytesPerSec == 0)
        MonitorRuntimeRead.now = Date(timeIntervalSince1970: 3_602)
        MonitorRuntimeRead.bytes = (1_000_100, 2_000_400)
        runtime.refreshRuntimeStats(includeNetwork: true)
        check("reopened-network-session-reports-only-visible-traffic", runtime.stats.netUpBytesPerSec == 50
            && runtime.stats.netDownBytesPerSec == 200 && MonitorRuntimeRead.networkReads == 4)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}

import Darwin
import Foundation

// ACTUAL_SYSTEM_STATS

private typealias NativeTicks = (user: natural_t, sys: natural_t, idle: natural_t, nice: natural_t)

// Only the host_statistics read is controlled. Its native Mach buffer, tick
// types, the production reader, and both production state fields are retained.
@MainActor private enum MonitorHostRead {
    static var ticks: NativeTicks = (0, 0, 0, 0)
    static var result: kern_return_t = KERN_SUCCESS
    static var calls = 0
    static func read(_ host: host_t, _ flavor: host_flavor_t, _ output: UnsafeMutablePointer<integer_t>,
                     _ count: UnsafeMutablePointer<mach_msg_type_number_t>) -> kern_return_t {
        calls += 1
        precondition(flavor == HOST_CPU_LOAD_INFO)
        precondition(Int(count.pointee) == MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        guard result == KERN_SUCCESS else { return result }
        for (offset, value) in [ticks.user, ticks.sys, ticks.idle, ticks.nice].enumerated() {
            output[offset] = integer_t(bitPattern: value)
        }
        return result
    }
}

@MainActor private final class SystemMonitor {
    // ACTUAL_CPU_STATE
    // ACTUAL_CPU_READER
    func sample() -> Double { stats.cpuUsage = readCPUUsage(); return stats.cpuUsage }
    var tickState: [natural_t] { [lastCPUTicks.user, lastCPUTicks.sys, lastCPUTicks.idle, lastCPUTicks.nice] }
}

@main private enum SystemMonitorStatsChecks {
    @MainActor static func main() throws {
        var checks: [String: Bool] = [:]
        func check(_ name: String, _ value: Bool) { precondition(value, name); checks[name] = value }
        func sample(_ monitor: SystemMonitor, _ ticks: NativeTicks, result: kern_return_t = KERN_SUCCESS) -> Double {
            MonitorHostRead.ticks = ticks; MonitorHostRead.result = result
            let before = MonitorHostRead.calls
            let value = monitor.sample()
            check("one-native-read-per-sample-\(before)", MonitorHostRead.calls == before + 1)
            return value
        }
        check("native-mach-ticks-are-32-bit", MemoryLayout<natural_t>.size == MemoryLayout<UInt32>.size)
        let ordinary = SystemMonitor()
        check("initial-published-and-counter-state-unchanged", ordinary.stats.cpuUsage == 0 && ordinary.tickState == [0, 0, 0, 0])
        check("first-sample-keeps-original-cumulative-ratio", sample(ordinary, (20, 10, 60, 10)) == 40.0 / 100.0)
        check("ordinary-deltas-include-user-system-and-nice", sample(ordinary, (24, 16, 70, 12)) == 12.0 / 22.0)
        check("ordinary-ticks-publish-after-success", ordinary.tickState == [24, 16, 70, 12])
        let previous = ordinary.stats.cpuUsage
        check("zero-delta-retains-last-published-value", sample(ordinary, (24, 16, 70, 12)) == previous
            && ordinary.tickState == [24, 16, 70, 12])
        check("failed-read-retains-value-and-counter-baseline", sample(ordinary, (100, 100, 100, 100), result: KERN_FAILURE) == previous
            && ordinary.tickState == [24, 16, 70, 12])
        check("success-after-failure-diffs-last-success", sample(ordinary, (26, 17, 77, 12)) == 3.0 / 10.0)

        let userWrap = SystemMonitor()
        _ = sample(userWrap, (natural_t.max - 2, 0, 0, 0))
        check("single-user-counter-wrap-is-native-width", sample(userWrap, (5, 10, 20, 0)) == 18.0 / 38.0)
        check("wrapped-counter-becomes-next-baseline", sample(userWrap, (7, 12, 26, 0)) == 4.0 / 10.0)
        let idleWrap = SystemMonitor()
        _ = sample(idleWrap, (100, 50, natural_t.max - 2, 0))
        check("single-idle-counter-wrap-preserves-busy-ratio", sample(idleWrap, (104, 56, 5, 0)) == 10.0 / 18.0)

        let doubleWrap = SystemMonitor()
        _ = sample(doubleWrap, (natural_t.max - 2, 100, natural_t.max - 1, 20))
        check("two-wrapped-counters-do-not-overflow-total", sample(doubleWrap, (5, 103, 4, 22)) == 13.0 / 19.0)
        let allWrap = SystemMonitor()
        _ = sample(allWrap, (natural_t.max - 9, natural_t.max - 9, natural_t.max - 9, natural_t.max - 9))
        check("all-counters-wrap-independently", sample(allWrap, (20, 30, 40, 50)) == 130.0 / 180.0)
        let wideTotal = SystemMonitor()
        let counters: NativeTicks = (natural_t.max - 1, natural_t.max - 2, natural_t.max - 3, natural_t.max - 4)
        let busy = UInt64(counters.user) + UInt64(counters.sys) + UInt64(counters.nice)
        let total = busy + UInt64(counters.idle)
        check("native-deltas-widen-before-summing", total > UInt64(UInt32.max)
            && sample(wideTotal, counters) == Double(busy) / Double(total))
        let firstFailure = SystemMonitor()
        check("first-failed-read-retains-original-zero", sample(firstFailure, (1, 2, 3, 4), result: KERN_FAILURE) == 0
            && firstFailure.tickState == [0, 0, 0, 0])
        check("first-success-after-failure-keeps-original-initial-semantics", sample(firstFailure, (1, 2, 5, 2)) == 5.0 / 10.0)
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}

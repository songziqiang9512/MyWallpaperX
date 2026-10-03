#if DEBUG
import Darwin

enum DebugSceneProcessCPUTime {
    struct Timebase: Equatable {
        let numerator: UInt32
        let denominator: UInt32
    }

    enum Failure: String, Error {
        case processSampleUnavailable = "process-sample-unavailable"
        case resourceUsageUnavailable = "resource-usage-unavailable"
        case rawTickSumOverflow = "raw-tick-sum-overflow"
        case tickCounterRegressed = "tick-counter-regressed"
        case timebaseUnavailable = "timebase-unavailable"
        case timebaseInvalid = "timebase-invalid"
        case conversionOverflow = "conversion-overflow"
    }

    static func combinedMachTicks(
        userMachTicks: UInt64,
        systemMachTicks: UInt64
    ) -> Result<UInt64, Failure> {
        let (combinedMachTicks, overflow) = userMachTicks.addingReportingOverflow(
            systemMachTicks
        )
        guard !overflow else { return .failure(.rawTickSumOverflow) }
        return .success(combinedMachTicks)
    }

    static func currentTimebase() -> Result<Timebase, Failure> {
        var info = mach_timebase_info_data_t()
        let status = mach_timebase_info(&info)
        return validatedTimebase(
            status: status,
            numerator: info.numer,
            denominator: info.denom
        )
    }

    static func validatedTimebase(
        status: kern_return_t,
        numerator: UInt32,
        denominator: UInt32
    ) -> Result<Timebase, Failure> {
        guard status == KERN_SUCCESS else { return .failure(.timebaseUnavailable) }
        guard numerator > 0, denominator > 0 else { return .failure(.timebaseInvalid) }
        return .success(Timebase(numerator: numerator, denominator: denominator))
    }

    static func elapsedMilliseconds(
        firstMachTicks: UInt64,
        latestMachTicks: UInt64,
        timebase: Timebase
    ) -> Result<Double, Failure> {
        let (deltaMachTicks, regressed) = latestMachTicks.subtractingReportingOverflow(
            firstMachTicks
        )
        guard !regressed else { return .failure(.tickCounterRegressed) }

        let denominator = UInt64(timebase.denominator)
        let numerator = UInt64(timebase.numerator)
        guard denominator > 0, numerator > 0 else { return .failure(.timebaseInvalid) }

        let wholeTicks = deltaMachTicks / denominator
        let remainderTicks = deltaMachTicks % denominator
        let (wholeNanoseconds, wholeOverflow) = wholeTicks.multipliedReportingOverflow(
            by: numerator
        )
        let (remainderProduct, remainderOverflow) = remainderTicks
            .multipliedReportingOverflow(by: numerator)
        guard !wholeOverflow, !remainderOverflow else {
            return .failure(.conversionOverflow)
        }
        let remainderNanoseconds = remainderProduct / denominator
        let (nanoseconds, sumOverflow) = wholeNanoseconds.addingReportingOverflow(
            remainderNanoseconds
        )
        guard !sumOverflow else { return .failure(.conversionOverflow) }

        let milliseconds = Double(nanoseconds) / 1_000_000
        guard milliseconds.isFinite else { return .failure(.conversionOverflow) }
        return .success(milliseconds)
    }
}
#endif

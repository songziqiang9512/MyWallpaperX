import Foundation
import Metal

// CPU-only checks of the real diagnostic's assessment and lifecycle values.
// This fixture creates no Metal device, command buffer, encoder, or sample.
@main
enum SceneGPUStageTimestampChecks {
    static func row(
        _ draw: String = "yes", fragment: Bool = true, kind: String = "render"
    ) -> SceneGPUStageTimestampRow {
        var value = SceneGPUStageTimestampRow(
            ordinal: 0, kind: kind, role: "counterexample", base: 0,
            count: kind == "render" ? 4 : 2, drawPresence: draw,
            facts: [:], target: [:], attachments: [:]
        )
        value.created = true
        value.expectsFragment = fragment
        return value
    }

    static func assess(
        _ row: SceneGPUStageTimestampRow, _ samples: [UInt64],
        initialGPU: UInt64 = 100, finalGPU: UInt64 = 200
    ) -> (complete: Bool, rows: [[String: Any]]) {
        SceneGPUStageTimestampAssessment.assess(
            rows: [row], samples: samples,
            initialCPU: 1_000, initialGPU: initialGPU,
            finalCPU: 101_000, finalGPU: finalGPU
        )
    }

    static func main() throws {
        var facts: [String: Bool] = [:]
        func check(_ name: String, _ value: Bool) { facts[name] = value }

        let good = assess(row(), [110, 120, 130, 150])
        check("valid-draw-stage", good.complete)
        check("clock-ratio-units", good.rows[0]["vertexUS"] as? Double == 10
            && good.rows[0]["fragmentUS"] as? Double == 20)
        check("render-sentinel-rejected", !assess(
            row(), [110, 120, 130, MTLCounterErrorValue]
        ).complete)
        check("reverse-rejected", !assess(row(), [120, 110, 130, 150]).complete)
        check("outside-calibration-rejected", !assess(row(), [99, 120, 130, 150]).complete)
        check("truncated-rejected", !assess(row(), [110, 120, 130]).complete)
        check("unknown-draw-rejected", !assess(row("unknown"), [110, 120, 130, 150]).complete)

        let clear = assess(row("no"), [0, MTLCounterErrorValue, 0, MTLCounterErrorValue])
        check("clear-gap-explicit", clear.complete
            && clear.rows[0]["timingState"] as? String == "no-draw-attachment-cost-uncovered")
        check("clear-not-zero-cost", clear.rows[0]["vertexUS"] == nil
            && clear.rows[0]["fragmentUS"] == nil)
        check("zero-not-sdk-sentinel", SceneGPUStageTimestampAssessment.interval(
            0, 0, initialCPU: 0, initialGPU: 0, finalCPU: 1_000, finalGPU: 100
        ) == 0)
        check("zero-cannot-prove-no-draw", !assess(
            row("unknown"), [0, 0, 0, 0], initialGPU: 0, finalGPU: 100
        ).complete)
        check("vertex-only-explicit", assess(
            row(fragment: false), [110, 120, MTLCounterErrorValue, MTLCounterErrorValue]
        ).complete)
        check("fragment-required-neighbor", !assess(
            row(fragment: true), [110, 120, MTLCounterErrorValue, MTLCounterErrorValue]
        ).complete)
        check("blit-stage", assess(row("no", kind: "blit"), [110, 120]).complete)
        check("no-calibration-span", SceneGPUStageTimestampAssessment.interval(
            110, 120, initialCPU: 0, initialGPU: 100, finalCPU: 1_000, finalGPU: 100
        ) == nil)
        let large: UInt64 = 1 << 63
        check("subtract-before-double", SceneGPUStageTimestampAssessment.interval(
            large + 10, large + 20, initialCPU: large, initialGPU: large,
            finalCPU: large + 100_000, finalGPU: large + 100
        ) == 10)

        var normal = SceneGPUStageTimestampValidity()
        check("submit-once", normal.submit() && !normal.submit())
        check("completion-once", normal.complete(succeeded: true)
            && !normal.complete(succeeded: true))
        var canceled = SceneGPUStageTimestampValidity()
        canceled.cancel("unsubmitted")
        check("cancel-no-submit-or-completion", !canceled.submit()
            && !canceled.complete(succeeded: true))
        var stale = SceneGPUStageTimestampValidity()
        _ = stale.submit()
        stale.invalidate("epoch-reset")
        check("inflight-stale-not-qualified", !stale.complete(succeeded: true)
            && stale.invalidations == ["epoch-reset"])
        var failed = SceneGPUStageTimestampValidity()
        _ = failed.submit()
        check("gpu-failure-not-qualified", !failed.complete(succeeded: false))

        var ranges = SceneGPUStageTimestampSampleRanges()
        check("range-dense", ranges.reserve(4) == 0 && ranges.reserve(2) == 4)
        check("range-overflow-preserves-prefix", ranges.reserve(1_020) == nil && ranges.used == 6)
        check("range-exact-capacity", ranges.reserve(1_018) == 6 && ranges.used == 1_024
            && ranges.reserve(1) == nil)
        check("range-invalid-count", ranges.reserve(0) == nil && ranges.reserve(-1) == nil)
        check("disabled-no-device-path", !SceneGPUStageTimestampHook.enabled)

        let passed = facts.values.allSatisfy { $0 }
        let data = try JSONSerialization.data(withJSONObject: [
            "facts": facts, "passed": passed,
            "scope": "CPU-only real telemetry/helper; no Metal device, CB, encoder, sample or App.",
        ], options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if !passed { exit(1) }
    }
}

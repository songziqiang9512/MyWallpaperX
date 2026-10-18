#if DEBUG
import Foundation
import QuartzCore

/// Launch-only aggregate profile of the per-variant compilation segments.
/// The capability catalog resets it once per construction and logs one
/// summary after its parallel workers finish; ordinary frames never touch it.
/// Durations include failed attempts and sum overlapping worker intervals.
nonisolated enum SceneResolvedMaterialVariantCompileProfile {
    private static let lock = NSLock()
    private static var prepareMs: Double = 0
    private static var canonicalizeMs: Double = 0
    private static var analysisMs: Double = 0
    private static var artifactMs: Double = 0
    private static var variants = 0
    private static var totalMs: Double = 0

    static func reset() {
        lock.withLock {
            prepareMs = 0
            canonicalizeMs = 0
            analysisMs = 0
            artifactMs = 0
            variants = 0
            totalMs = 0
        }
    }

    static func beginVariant() -> Double {
        CACurrentMediaTime()
    }

    static func endVariant(startedAt: Double) {
        // Each parallel worker owns its start; these durations are summed
        // work intervals, not the capability catalog's wall-clock interval.
        let elapsedMs = (CACurrentMediaTime() - startedAt) * 1000
        lock.withLock {
            totalMs += elapsedMs
            variants += 1
        }
    }

    static func add(
        prepare: Double = 0, canonicalize: Double = 0,
        analysis: Double = 0, artifact: Double = 0
    ) {
        lock.withLock {
            prepareMs += prepare
            canonicalizeMs += canonicalize
            analysisMs += analysis
            artifactMs += artifact
        }
    }

    static func logSummaryIfMeasured() {
        let (count, prepare, canonicalize, analysis, artifact, total) =
            lock.withLock {
                (
                    variants, prepareMs, canonicalizeMs, analysisMs,
                    artifactMs, totalMs
                )
            }
        guard count > 0 else { return }
        NSLog(
            "MWX LAUNCH-STAGE: capability-detail variants=%d totalMs=%.0f prepareMs=%.0f canonicalizeMs=%.0f analysisMs=%.0f artifactMs=%.0f restMs=%.0f",
            count, total, prepare, canonicalize, analysis, artifact,
            total - prepare - canonicalize - analysis - artifact
        )
    }
}
#endif

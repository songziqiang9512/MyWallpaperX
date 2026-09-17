import Foundation

/// Device-relative logical residency limit for the single offscreen target
/// pool. Allocation remains lazy, and the frame preflight remains responsible
/// for rejecting an atomic target set that does not fit this limit.
enum SceneOffscreenTextureResidentBudgetPolicy {
    private static let minimumBytes = 192 * 1_024 * 1_024

    // Bound this pool even when Metal reports a large recommended working set.
    // The proportional share admits legitimate concurrent graph targets; a
    // frame target set above the result still fails before allocation.
    private static let maximumBytes = 1_536 * 1_024 * 1_024

    static func automatic(recommendedMaxWorkingSetSize: UInt64) -> Int {
        let proposed = min(
            recommendedMaxWorkingSetSize / 16,
            UInt64(maximumBytes)
        )
        return max(Int(proposed), minimumBytes)
    }
}

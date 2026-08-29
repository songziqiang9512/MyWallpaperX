import simd

nonisolated struct SceneSurfacePointerState: Equatable, Sendable {
    var current: SIMD2<Float> = .zero
    var previous: SIMD2<Float> = .zero
    var sceneScriptCurrent: SIMD2<Float> = .zero
    var isInside = false
    var isPrimaryButtonDown = false
    var sceneScriptPrimaryButtonIsDown = false
}

nonisolated struct SceneSurfacePointerEvent: Equatable, Sendable {
    let normalizedPosition: SIMD2<Float>
    let isInside: Bool
    let primaryButtonIsDown: Bool
}

nonisolated struct SceneSurfacePointerEventBatch: Equatable, Sendable {
    let events: [SceneSurfacePointerEvent]
    let overflowed: Bool
}

/// Main-run-loop buffer for AppKit pointer samples that may begin and end
/// between two render frames. Overflow rejects the complete event batch so a
/// partial press/release sequence can never synthesize a click.
nonisolated struct SceneSurfacePointerEventBuffer: Sendable {
    static let maximumEventCount = 512

    private var events: [SceneSurfacePointerEvent] = []
    private var overflowed = false

    mutating func append(_ event: SceneSurfacePointerEvent) {
        guard !overflowed else { return }
        guard events.count < Self.maximumEventCount else {
            events.removeAll(keepingCapacity: true)
            overflowed = true
            return
        }
        events.append(event)
    }

    mutating func drain() -> SceneSurfacePointerEventBatch {
        let batch = SceneSurfacePointerEventBatch(
            events: overflowed ? [] : events,
            overflowed: overflowed
        )
        events.removeAll(keepingCapacity: true)
        overflowed = false
        return batch
    }
}

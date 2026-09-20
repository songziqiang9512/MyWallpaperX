import CoreGraphics
import simd

/// One producer sample. Frame history is deliberately absent: `previous` is
/// owned by the submitted-frame transaction, not by AppKit or debug inputs.
nonisolated struct SceneSurfacePointerInput: Equatable, Sendable {
    var current: SIMD2<Float> = .zero
    var isInside = false
    var isPrimaryButtonDown = false
}

nonisolated struct SceneSurfacePointerState: Equatable, Sendable {
    var current: SIMD2<Float> = .zero
    var previous: SIMD2<Float> = .zero
    var sceneScriptCurrent: SIMD2<Float> = .zero
    var isInside = false
    var isPrimaryButtonDown = false
    var sceneScriptPrimaryButtonIsDown = false

    /// Applies producer state without overwriting submitted-frame history.
    /// Returns whether the SceneScript event-facing input changed.
    mutating func apply(_ input: SceneSurfacePointerInput) -> Bool {
        let changed = sceneScriptCurrent != input.current
            || isInside != input.isInside
            || sceneScriptPrimaryButtonIsDown != input.isPrimaryButtonDown
        current = input.current
        sceneScriptCurrent = input.current
        isInside = input.isInside
        isPrimaryButtonDown = input.isPrimaryButtonDown
        sceneScriptPrimaryButtonIsDown = input.isPrimaryButtonDown
        return changed
    }
}

nonisolated struct SceneSurfacePointerEvent: Equatable, Sendable {
    let normalizedPosition: SIMD2<Float>
    let isInside: Bool
    let primaryButtonIsDown: Bool

    /// AppKit local coordinates -> shared Y-up NDC. Desktop edge pixels must
    /// remain inside, while genuinely outside points retain their position
    /// for captured drags. Do not clamp them into synthetic inside events.
    static func sample(
        localPosition: CGPoint, bounds: CGRect, primaryButtonIsDown: Bool
    ) -> Self? {
        guard bounds.width.isFinite, bounds.height.isFinite,
              bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width > 0, bounds.height > 0,
              localPosition.x.isFinite, localPosition.y.isFinite else { return nil }
        let position = SIMD2<Float>(
            Float((localPosition.x - bounds.minX) / bounds.width * 2 - 1),
            Float((localPosition.y - bounds.minY) / bounds.height * 2 - 1)
        )
        guard position.x.isFinite, position.y.isFinite else { return nil }
        return Self(
            normalizedPosition: position,
            isInside: localPosition.x >= bounds.minX && localPosition.x <= bounds.maxX
                && localPosition.y >= bounds.minY && localPosition.y <= bounds.maxY,
            primaryButtonIsDown: primaryButtonIsDown
        )
    }
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

    /// Re-inserts a drained batch for a frame that was not submitted. Events
    /// are prepended to preserve FIFO order relative to any events appended
    /// after the drain; a rejected overflowed batch re-arms the overflow flag
    /// so the next drain keeps failing closed instead of synthesizing a
    /// partial press/release sequence.
    mutating func restore(_ batch: SceneSurfacePointerEventBatch) {
        guard !batch.events.isEmpty || batch.overflowed else { return }
        if batch.overflowed {
            events.removeAll(keepingCapacity: true)
            overflowed = true
            return
        }
        events.insert(contentsOf: batch.events, at: 0)
        if events.count > Self.maximumEventCount {
            events.removeAll(keepingCapacity: true)
            overflowed = true
        }
    }
}

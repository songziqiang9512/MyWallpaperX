import Foundation

nonisolated struct SceneParticleTrailRenderPlan: Equatable, Sendable {
    private let length: Double
    private let minimumStretch: Double
    private let maximumStretch: Double

    nonisolated init?(
        length: Double?,
        minimumLength: Double?,
        maximumLength: Double?,
        hasMalformedFields: Bool = false
    ) {
        // Resolve each omitted field independently; orientation-only requires
        // authored equal bounds, not merely absent bounds.
        let length = length ?? 0.05
        guard !hasMalformedFields,
              length.isFinite,
              length >= 0 else {
            return nil
        }

        let minimumLength = minimumLength ?? 0
        let maximumLength = maximumLength ?? 10
        guard minimumLength.isFinite,
              maximumLength.isFinite,
              minimumLength >= 0,
              maximumLength >= 0,
              maximumLength >= minimumLength else {
            return nil
        }

        self.length = length
        self.minimumStretch = minimumLength
        self.maximumStretch = maximumLength
    }

    /// The velocity is expressed in the coordinate system that owns the bounds.
    nonisolated func geometry(for velocity: SIMD3<Double>) -> (direction: SIMD3<Float>, stretch: Float) {
        guard velocity.x.isFinite,
              velocity.y.isFinite,
              velocity.z.isFinite else { return (.zero, Float(minimumStretch)) }
        let maximumMagnitude = max(abs(velocity.x), max(abs(velocity.y), abs(velocity.z)))
        guard maximumMagnitude > 0 else { return (.zero, Float(minimumStretch)) }
        let scaled = velocity / maximumMagnitude
        let magnitude = hypot(hypot(scaled.x, scaled.y), scaled.z)
        let direction = SIMD3(
            Float(scaled.x / magnitude),
            Float(scaled.y / magnitude),
            Float(scaled.z / magnitude)
        )
        let stretch = (maximumMagnitude * length) * magnitude
        return (direction, Float(min(max(stretch, minimumStretch), maximumStretch)))
    }
}

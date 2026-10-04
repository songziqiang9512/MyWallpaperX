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

    /// Normalize before narrowing to Float so every finite nonzero velocity
    /// keeps its direction, including very slow motion and large magnitudes.
    nonisolated func direction(for velocity: SIMD3<Double>) -> SIMD3<Float> {
        guard velocity.x.isFinite,
              velocity.y.isFinite,
              velocity.z.isFinite else { return .zero }
        let maximumMagnitude = max(abs(velocity.x), max(abs(velocity.y), abs(velocity.z)))
        guard maximumMagnitude > 0 else { return .zero }
        let scaled = velocity / maximumMagnitude
        let magnitude = hypot(hypot(scaled.x, scaled.y), scaled.z)
        return SIMD3(
            Float(scaled.x / magnitude),
            Float(scaled.y / magnitude),
            Float(scaled.z / magnitude)
        )
    }

    nonisolated func stretch(for velocity: SIMD3<Double>) -> Float {
        guard velocity.x.isFinite,
              velocity.y.isFinite,
              velocity.z.isFinite else {
            return Float(minimumStretch)
        }

        let speed = hypot(hypot(velocity.x, velocity.y), velocity.z)
        let authoredStretch = speed * length
        let clampedStretch = min(
            max(authoredStretch, minimumStretch),
            maximumStretch
        )
        return Float(clampedStretch)
    }
}

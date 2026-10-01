import Foundation

nonisolated struct SceneParticleTrailRenderPlan: Equatable, Sendable {
    /// Sprite Trail orientation samples this many recent fixed-step positions
    /// per particle. The simulator records the path chord (oldest retained
    /// sample to current position) as a conservative approximation of the
    /// ribbon tangent; full ribbon geometry remains a separate effort.
    static let historySampleCapacity = 8

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

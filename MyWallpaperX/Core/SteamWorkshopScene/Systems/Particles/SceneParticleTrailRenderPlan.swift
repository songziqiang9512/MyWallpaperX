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
        // Stock Sprite Trail definitions can omit length; keep that form bounded
        // to orientation-only scale when the min/max fields are omitted as well.
        let length = length ?? 1
        guard !hasMalformedFields,
              length.isFinite,
              length >= 0 else {
            return nil
        }

        let minimumLength = minimumLength ?? 1
        let maximumLength = maximumLength ?? 1
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

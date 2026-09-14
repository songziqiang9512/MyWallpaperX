import simd

nonisolated struct SceneDynamicCameraTransform: Equatable, Sendable {
    let origin: SIMD3<Float>
    let zoom: Float

    nonisolated static let identity = SceneDynamicCameraTransform(origin: .zero, zoom: 1)
}

/// A small immutable projection of camera-bound values from the existing
/// dynamic snapshot.  Nil means that no valid typed producer exists for that
/// field, so camera consumers keep the descriptor's authored value.
nonisolated struct SceneDynamicCameraPropertyProjection: Equatable, Sendable {
    let parallaxEnabled: Bool?
    let parallaxAmount: Float?
    let parallaxDelay: Float?
    let parallaxMouseInfluence: Float?
    let shakeEnabled: Bool?
    let shakeAmplitude: Float?
    let shakeRoughness: Float?
    let shakeSpeed: Float?
}

extension SceneDynamicSnapshot {
    /// Converts the typed snapshot into the bounded render-camera payload. Double values that
    /// cannot be represented by Metal's Float matrices fail closed to the identity component.
    nonisolated func cameraTransform() -> SceneDynamicCameraTransform {
        let origin: SIMD3<Float> = {
            guard let resolved = self[.camera(.origin)],
                  case let .vector3(x, y, z) = resolved.value else { return .zero }
            let value = SIMD3<Float>(Float(x), Float(y), Float(z))
            return value.x.isFinite && value.y.isFinite && value.z.isFinite ? value : .zero
        }()
        let zoom: Float = {
            guard let resolved = self[.camera(.zoom)],
                  case let .scalar(value) = resolved.value else { return 1 }
            let result = Float(value)
            return result.isFinite && result > 0 ? result : 1
        }()
        return SceneDynamicCameraTransform(origin: origin, zoom: zoom)
    }

    nonisolated func cameraPropertyProjection()
        -> SceneDynamicCameraPropertyProjection {
        SceneDynamicCameraPropertyProjection(
            parallaxEnabled: cameraBoolean(.parallaxEnabled),
            parallaxAmount: cameraScalar(.parallaxAmount),
            parallaxDelay: cameraScalar(.parallaxDelay),
            parallaxMouseInfluence: cameraScalar(.parallaxMouseInfluence),
            shakeEnabled: cameraBoolean(.shakeEnabled),
            shakeAmplitude: cameraScalar(.shakeAmplitude),
            shakeRoughness: cameraScalar(.shakeRoughness),
            shakeSpeed: cameraScalar(.shakeSpeed)
        )
    }

    private nonisolated func cameraBoolean(
        _ field: SceneDynamicCameraField
    ) -> Bool? {
        guard let resolved = self[.camera(field)],
              case let .bool(value) = resolved.value else { return nil }
        return value
    }

    private nonisolated func cameraScalar(
        _ field: SceneDynamicCameraField
    ) -> Float? {
        guard let resolved = self[.camera(field)],
              case let .scalar(value) = resolved.value else { return nil }
        let result = Float(value)
        return result.isFinite ? result : nil
    }
}

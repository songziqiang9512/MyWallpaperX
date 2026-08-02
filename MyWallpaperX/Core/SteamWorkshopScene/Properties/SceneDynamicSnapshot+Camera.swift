import simd

nonisolated struct SceneDynamicCameraTransform: Equatable, Sendable {
    let origin: SIMD3<Float>
    let zoom: Float

    nonisolated static let identity = SceneDynamicCameraTransform(origin: .zero, zoom: 1)
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
}

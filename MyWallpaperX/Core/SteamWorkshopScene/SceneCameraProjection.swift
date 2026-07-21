import CoreGraphics
import simd

enum SceneCameraProjection {
    nonisolated static func coverHalfExtents(
        orthoWidth: Float,
        orthoHeight: Float,
        viewportSize: CGSize,
        centerOffset: SIMD3<Float>
    ) -> SIMD2<Float> {
        let availableHalfWidth = max(1, orthoWidth * 0.5 - abs(centerOffset.x))
        let availableHalfHeight = max(1, orthoHeight * 0.5 - abs(centerOffset.y))
        let drawableAspect = Float(viewportSize.width / viewportSize.height)
        let availableAspect = availableHalfWidth / availableHalfHeight
        if drawableAspect > availableAspect {
            return SIMD2(availableHalfWidth, availableHalfWidth / drawableAspect)
        }
        return SIMD2(availableHalfHeight * drawableAspect, availableHalfHeight)
    }
}

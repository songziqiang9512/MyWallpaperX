import CoreGraphics
import simd

enum SceneCameraProjection {
    static func viewProjection(
        camera: SceneRenderDescriptor.CameraDescriptor,
        viewportSize: CGSize
    ) -> simd_float4x4 {
        let orthoWidth = camera.orthoWidth ?? Float(viewportSize.width)
        let orthoHeight = camera.orthoHeight ?? Float(viewportSize.height)
        guard orthoWidth > 0, orthoHeight > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return SceneMatrix.identity()
        }

        let cameraDepth: Float = max(1, camera.nearZ * 10)
        let sceneCenter = SIMD3<Float>(orthoWidth / 2, orthoHeight / 2, cameraDepth)
        let eyeOffset = SIMD3<Float>(camera.eye, fill: 0)
        let centerOffset = SIMD3<Float>(camera.center, fill: 0)
        let upDirection = SIMD3<Float>(camera.up, fill: 0)
        let view = SceneMatrix.lookAt(
            eye: sceneCenter + eyeOffset,
            center: sceneCenter + centerOffset,
            up: upDirection
        )
        let halfExtents = coverHalfExtents(
            orthoWidth: orthoWidth,
            orthoHeight: orthoHeight,
            viewportSize: viewportSize,
            centerOffset: centerOffset
        )
        let projection = SceneMatrix.ortho(
            left: -halfExtents.x,
            right: halfExtents.x,
            bottom: halfExtents.y,
            top: -halfExtents.y,
            near: camera.nearZ,
            far: camera.farZ
        )
        return projection * view
    }

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

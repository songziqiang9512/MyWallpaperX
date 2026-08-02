import CoreGraphics
import simd

enum SceneCameraProjection {
    static func viewProjection(
        camera: SceneRenderDescriptor.CameraDescriptor,
        viewportSize: CGSize,
        cameraOrigin: SIMD3<Float> = .zero,
        cameraZoom: Float = 1
    ) -> simd_float4x4 {
        let orthoWidth = camera.orthoWidth ?? Float(viewportSize.width)
        let orthoHeight = camera.orthoHeight ?? Float(viewportSize.height)
        guard orthoWidth > 0, orthoHeight > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return SceneMatrix.identity()
        }

        // Authored camera eye/center/up are editor-viewport state; Wallpaper
        // Engine renders the wallpaper centered on the canvas regardless
        // (official previews and desktop playback of samples whose saved eye
        // is far off-center, e.g. eye=(94, 753) on a 3840x2160 canvas).
        let safeOrigin = cameraOrigin.x.isFinite && cameraOrigin.y.isFinite
            && cameraOrigin.z.isFinite ? cameraOrigin : .zero
        let authoredDepth = safeOrigin.z > camera.nearZ
            ? safeOrigin.z : max(1, camera.nearZ * 10)
        let sceneCenter = SIMD3<Float>(
            orthoWidth / 2 + safeOrigin.x,
            orthoHeight / 2 + safeOrigin.y,
            authoredDepth
        )
        let view = SceneMatrix.lookAt(
            eye: sceneCenter,
            center: SIMD3(sceneCenter.x, sceneCenter.y, sceneCenter.z - 1),
            up: SIMD3(0, 1, 0)
        )
        let halfExtents = coverHalfExtents(
            orthoWidth: orthoWidth,
            orthoHeight: orthoHeight,
            viewportSize: viewportSize,
            zoom: cameraZoom
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
        zoom: Float = 1
    ) -> SIMD2<Float> {
        let availableHalfWidth = max(1, orthoWidth * 0.5)
        let availableHalfHeight = max(1, orthoHeight * 0.5)
        let drawableAspect = Float(viewportSize.width / viewportSize.height)
        let availableAspect = availableHalfWidth / availableHalfHeight
        let extents = drawableAspect > availableAspect
            ? SIMD2(availableHalfWidth, availableHalfWidth / drawableAspect)
            : SIMD2(availableHalfHeight * drawableAspect, availableHalfHeight)
        let safeZoom = zoom.isFinite && zoom > 0 ? zoom : 1
        return extents / safeZoom
    }
}

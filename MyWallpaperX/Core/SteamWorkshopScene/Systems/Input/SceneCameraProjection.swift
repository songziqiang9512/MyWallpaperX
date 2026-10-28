import CoreGraphics
import simd

nonisolated enum SceneCameraProjection {
    nonisolated static func imageCardYDirection(
        usesPerspective: Bool, sceneOrthoHeight: Float?
    ) -> Float {
        // Perspective on an orthographic canvas retains its Y-down world.
        // Only native perspective scenes use Y-up model coordinates.
        usesPerspective && (sceneOrthoHeight ?? 0) <= 0 ? 1 : -1
    }

    static func viewProjection(
        camera: SceneRenderDescriptor.CameraDescriptor,
        viewportSize: CGSize,
        cameraOrigin: SIMD3<Float> = .zero,
        cameraZoom: Float = 1,
        staticView: simd_float4x4? = nil
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
        // The orthographic canvas is the center of its authored depth span,
        // not one unit behind the near plane. A typed X/Y rotation must be
        // able to move a 2D card to either side of that plane without clipping
        // ordinary text/image geometry. Camera Z translates the same span.
        let authoredDepth = safeOrigin.z + (camera.nearZ + camera.farZ) * 0.5
        // Canvas fitting follows the static view. Rotating the saved editor
        // viewport around the canvas center would move ordinary world points.
        let canvasView = SceneMatrix.translation(SIMD3(
            -orthoWidth / 2 - safeOrigin.x,
            -orthoHeight / 2 - safeOrigin.y,
            -authoredDepth
        ))
        let view = staticView.map { canvasView * $0 } ?? canvasView
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

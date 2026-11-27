import CoreGraphics
import simd

nonisolated enum SceneCameraProjection {
    enum Layout: Equatable, Sendable {
        case cover, fit, stretch, center, free
    }

    struct Adjustment: Equatable, Sendable {
        var position = 50
        var zoom = 100
        var layout: Layout = .cover
        var horizontalPosition = 50
        var verticalPosition = 50

        func framing(camera: SceneRenderDescriptor.CameraDescriptor,
                     viewportSize: CGSize, zoomScale: Float)
            -> (halfExtents: SIMD2<Float>, clipOffset: SIMD2<Float>) {
            let viewport = SIMD2(Float(viewportSize.width), Float(viewportSize.height))
            let width = camera.orthoWidth ?? viewport.x
            let height = camera.orthoHeight ?? viewport.y
            guard width.isFinite, height.isFinite, width > 0, height > 0,
                  viewport.x.isFinite, viewport.y.isFinite,
                  viewport.x > 0, viewport.y > 0 else { return (.zero, .zero) }

            let authoredCanvas = camera.orthoWidth != nil && camera.orthoHeight != nil
            let effectiveLayout = authoredCanvas ? layout : .cover
            let canvas = SIMD2(max(1, width * 0.5), max(1, height * 0.5))
            switch effectiveLayout {
            case .cover, .fit:
                let cover = SceneCameraProjection.coverHalfExtents(
                    orthoWidth: width, orthoHeight: height, viewportSize: viewportSize)
                let halfExtents = cover / zoomScale
                guard effectiveLayout == .cover, authoredCanvas, position != 50 else {
                    return (halfExtents, .zero)
                }
                let travel = (canvas - cover) / halfExtents
                return (halfExtents, SIMD2(-travel.x, travel.y) * (Float(position) / 50 - 1))
            case .stretch:
                return (canvas / zoomScale, .zero)
            case .center:
                return (viewport * (0.5 / zoomScale), .zero)
            case .free:
                let halfExtents = viewport * (0.5 / zoomScale)
                let travel = canvas / halfExtents + 1
                let position = SIMD2(Float(horizontalPosition) / 50 - 1, 1 - Float(verticalPosition) / 50)
                return (halfExtents, travel * position)
            }
        }
    }

    static func fittedCanvasRect(
        in bounds: CGRect, orthoWidth: Float?, orthoHeight: Float?
    ) -> CGRect {
        guard let orthoWidth, let orthoHeight,
              orthoWidth.isFinite, orthoHeight.isFinite, orthoWidth > 0, orthoHeight > 0
        else { return bounds }
        let aspect = CGFloat(orthoWidth) / CGFloat(orthoHeight)
        let width = min(bounds.width, bounds.height * aspect)
        let height = min(bounds.height, bounds.width / aspect)
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                      width: width, height: height)
    }

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
        staticView: simd_float4x4? = nil,
        visibleHalfExtents: SIMD2<Float>? = nil
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
        let halfExtents = visibleHalfExtents ?? coverHalfExtents(
            orthoWidth: orthoWidth,
            orthoHeight: orthoHeight,
            viewportSize: viewportSize,
            zoom: cameraZoom
        )
        guard halfExtents.x > 0, halfExtents.y > 0 else { return SceneMatrix.identity() }
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

import CoreGraphics
import QuartzCore
import simd

extension SceneMetalView {
    /// Uses the same cover camera, authored world frames and quad inverse as
    /// rendering. Hidden transparent interaction owners remain hit-testable;
    /// visibility is intentionally not consulted here.
    func hoveredOriginOwnerLayerIDs(
        program: SceneHoverOriginTransitionProgram,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> Set<Int> {
        originInteractionOwnerLayerIDs(
            Set(program.cohorts.map(\.ownerLayerID)),
            timing: timing,
            dynamicValues: dynamicValues
        )
    }

    /// Dispatches cursorClick only to an admitted master owner under the
    /// pointer. The runtime owns edge detection and flag lifetime per surface.
    func launchOriginInteractionOwnerLayerIDs(
        program: SceneLaunchOriginTransitionProgram,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> Set<Int> {
        let owners = Set(program.cohorts.compactMap { cohort -> Int? in
            guard case let .layer(layerID, .origin) = cohort.masterTarget else {
                return nil
            }
            return layerID
        })
        return originInteractionOwnerLayerIDs(
            owners,
            timing: timing,
            dynamicValues: dynamicValues
        )
    }

    private func originInteractionOwnerLayerIDs(
        _ ownerLayerIDs: Set<Int>,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> Set<Int> {
        guard pointerState.isInside,
              metalLayer.drawableSize.width > 0,
              metalLayer.drawableSize.height > 0,
              !ownerLayerIDs.isEmpty else { return [] }
        let frameContext = makeFrameContext(
            timing: timing,
            dynamicValues: dynamicValues,
            parallax: .zero,
            audioSpectrum: .silent
        )
        let cameraFrame = renderer.makeCameraFrame(frameContext: frameContext)
        let worldFrames = SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: renderer.renderDescriptor,
            byID: renderer.layersByID,
            snapshot: dynamicValues,
            staticFrames: renderer.worldFramesByLayerID
        )
        let parallax = renderer.parallaxConfiguration(
            cameraFrame: cameraFrame,
            viewportSize: frameContext.screenSize
        )
        var hovered: Set<Int> = []
        for ownerLayerID in ownerLayerIDs {
            guard let layer = renderer.layersByID[ownerLayerID] else { continue }
            let model = renderer.imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFrames,
                parallaxMouseNormalized: .zero,
                configuration: parallax,
                visibleHalfExtents: cameraFrame.coverHalfExtents
            )
            guard let uv = SceneLayerCursorGeometry.layerUV(
                mouseNormalized: pointerState.current,
                modelViewProjection: cameraFrame.orthographicViewProjection * model
            ), uv.x >= 0, uv.x <= 1, uv.y >= 0, uv.y <= 1 else { continue }
            hovered.insert(ownerLayerID)
        }
        return hovered
    }
}

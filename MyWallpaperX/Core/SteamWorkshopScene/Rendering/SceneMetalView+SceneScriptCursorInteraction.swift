import CoreGraphics
import QuartzCore
import simd

extension SceneMetalView {
    /// Uses the same cover camera, authored world frames and quad inverse as
    /// rendering. Hidden transparent interaction owners remain hit-testable;
    /// visibility is intentionally not consulted here.
    func sceneScriptCursorHits(
        ownerLayerIDs: Set<Int>,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> [Int: SceneScriptCursorHit] {
        originInteractionHits(
            ownerLayerIDs,
            timing: timing,
            dynamicValues: dynamicValues
        )
    }

    private func originInteractionHits(
        _ ownerLayerIDs: Set<Int>,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> [Int: SceneScriptCursorHit] {
        guard pointerState.isInside,
              metalLayer.drawableSize.width > 0,
              metalLayer.drawableSize.height > 0,
              !ownerLayerIDs.isEmpty else { return [:] }
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
        var hits: [Int: SceneScriptCursorHit] = [:]
        for ownerLayerID in ownerLayerIDs {
            guard let layer = renderer.layersByID[ownerLayerID] else { continue }
            let model = renderer.imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFrames,
                parallaxMouseNormalized: .zero,
                configuration: parallax,
                visibleHalfExtents: cameraFrame.coverHalfExtents
            )
            let modelViewProjection = cameraFrame.orthographicViewProjection * model
            guard let local = SceneLayerCursorGeometry.layerPoint(
                mouseNormalized: pointerState.current,
                modelViewProjection: modelViewProjection
            ), local.x >= -0.5, local.x <= 0.5,
               local.y >= -0.5, local.y <= 0.5 else { continue }
            let projectedWorld = model * SIMD4(local.x, local.y, local.z, 1)
            guard projectedWorld.w.isFinite, abs(projectedWorld.w) > 1e-8 else {
                continue
            }
            let world = SIMD3(
                projectedWorld.x, projectedWorld.y, projectedWorld.z
            ) / projectedWorld.w
            guard world.x.isFinite, world.y.isFinite, world.z.isFinite else {
                continue
            }
            hits[ownerLayerID] = .init(
                layerID: ownerLayerID,
                worldPosition: SIMD3(
                    Double(world.x), Double(world.y), Double(world.z)
                ),
                localPosition: SIMD3(
                    Double(local.x), Double(local.y), Double(local.z)
                )
            )
        }
        return hits
    }
}

import CoreGraphics
import QuartzCore
import simd

extension SceneMetalView {
    /// Publishes one immutable callback snapshot from the same surface camera
    /// and pointer state used by rendering. The host only calls this when a
    /// scene has exactly one output surface, so no screen identity is guessed.
    func sceneScriptSurfaceInput(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> SceneScriptSurfaceInput? {
        sceneScriptSurfaceInput(
            pointer: .init(
                normalizedPosition: pointerState.sceneScriptCurrent,
                isInside: pointerState.isInside,
                primaryButtonIsDown: pointerState.sceneScriptPrimaryButtonIsDown
            ),
            timing: timing,
            dynamicValues: dynamicValues
        )
    }

    private func sceneScriptSurfaceInput(
        pointer: SceneSurfacePointerEvent,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> SceneScriptSurfaceInput? {
        guard metalLayer.drawableSize.width > 0,
              metalLayer.drawableSize.height > 0 else { return nil }
        let frameContext = makeFrameContext(
            timing: timing,
            dynamicValues: dynamicValues,
            parallax: .zero,
            audioSpectrum: .silent
        )
        let cameraFrame = renderer.makeCameraFrame(frameContext: frameContext)
        guard let world = SceneLayerCursorGeometry.layerPoint(
            mouseNormalized: pointer.normalizedPosition,
            modelViewProjection: cameraFrame.orthographicViewProjection
        ) else { return nil }
        let screenWidth = Double(frameContext.screenSize.width)
        let screenHeight = Double(frameContext.screenSize.height)
        let canvasWidth = Double(frameContext.canvasSize.width)
        let canvasHeight = Double(frameContext.canvasSize.height)
        let cursorScreen = SIMD2<Double>(
            (Double(pointer.normalizedPosition.x) + 1) * 0.5 * screenWidth,
            (1 - Double(pointer.normalizedPosition.y)) * 0.5 * screenHeight
        )
        guard screenWidth.isFinite, screenWidth > 0,
              screenHeight.isFinite, screenHeight > 0,
              canvasWidth.isFinite, canvasWidth > 0,
              canvasHeight.isFinite, canvasHeight > 0,
              cursorScreen.x.isFinite, cursorScreen.y.isFinite else { return nil }
        return SceneScriptSurfaceInput(
            canvasSize: SIMD2(canvasWidth, canvasHeight),
            screenSize: SIMD2(screenWidth, screenHeight),
            cursorWorldPosition: SIMD3(
                Double(world.x), Double(world.y), Double(world.z)
            ),
            cursorScreenPosition: cursorScreen,
            cursorLeftDown: pointer.primaryButtonIsDown
        )
    }

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
            pointer: .init(
                normalizedPosition: pointerState.current,
                isInside: pointerState.isInside,
                primaryButtonIsDown: pointerState.isPrimaryButtonDown
            ),
            timing: timing,
            dynamicValues: dynamicValues
        )
    }

    func sceneScriptCursorFrameBatch(
        ownerLayerIDs: Set<Int>,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> SceneScriptCursorFrameBatch {
        let drained = drainSceneScriptPointerEvents()
        let current = SceneSurfacePointerEvent(
            normalizedPosition: pointerState.sceneScriptCurrent,
            isInside: pointerState.isInside,
            primaryButtonIsDown: pointerState.sceneScriptPrimaryButtonIsDown
        )
        var events = drained.events
        if events.last != current { events.append(current) }
        if events.isEmpty { events = [current] }
        return .init(
            samples: events.map { pointer in
                .init(
                    hits: originInteractionHits(
                        ownerLayerIDs,
                        pointer: pointer,
                        timing: timing,
                        dynamicValues: dynamicValues
                    ),
                    pointerPosition: pointer.normalizedPosition,
                    primaryButtonIsDown: pointer.primaryButtonIsDown,
                    surface: sceneScriptSurfaceInput(
                        pointer: pointer,
                        timing: timing,
                        dynamicValues: dynamicValues
                    )
                )
            },
            overflowed: drained.overflowed
        )
    }

    private func originInteractionHits(
        _ ownerLayerIDs: Set<Int>,
        pointer: SceneSurfacePointerEvent,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> [Int: SceneScriptCursorHit] {
        guard pointer.isInside,
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
                mouseNormalized: pointer.normalizedPosition,
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

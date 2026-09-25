import CoreGraphics
import QuartzCore
import simd

#if DEBUG
/// Owners already logged by the one-shot cursor-bounds calibration probe.
private var sceneScriptCursorBoundsLoggedLayerIDs: Set<Int> = []
#endif

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
        let authoredWorld = SceneLayerCursorGeometry.authoredWorldPosition(
            world,
            sceneOrthoHeight: renderer.renderDescriptor.camera.orthoHeight
        )
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
                Double(authoredWorld.x),
                Double(authoredWorld.y),
                Double(authoredWorld.z)
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
        capturedOwnerLayerIDs: Set<Int>,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        puppetAttachmentFrames: ScenePuppetAttachmentFrameSnapshot = .empty,
        drainedEvents: SceneSurfacePointerEventBatch
    ) -> SceneScriptCursorFrameBatch {
        let current = SceneSurfacePointerEvent(
            normalizedPosition: pointerState.sceneScriptCurrent,
            isInside: pointerState.isInside,
            primaryButtonIsDown: pointerState.sceneScriptPrimaryButtonIsDown
        )
        var events = drainedEvents.events
        if events.last != current { events.append(current) }
        if events.isEmpty { events = [current] }
        var captureCandidates = capturedOwnerLayerIDs
        var samples: [SceneScriptCursorFrameSample] = []
        samples.reserveCapacity(events.count)
        for pointer in events {
            let projectedOwnerLayerIDs = pointer.isInside
                ? ownerLayerIDs : captureCandidates
            let projections = originInteractionProjections(
                projectedOwnerLayerIDs,
                pointer: pointer,
                timing: timing,
                dynamicValues: dynamicValues,
                puppetAttachmentFrames: puppetAttachmentFrames
            )
            let hits = originInteractionHits(
                projections,
                pointerIsInside: pointer.isInside
            )
            samples.append(.init(
                hits: hits,
                ownerProjections: projections,
                pointerPosition: pointer.normalizedPosition,
                primaryButtonIsDown: pointer.primaryButtonIsDown,
                surface: sceneScriptSurfaceInput(
                    pointer: pointer,
                    timing: timing,
                    dynamicValues: dynamicValues
                )
            ))
            if pointer.primaryButtonIsDown {
                captureCandidates.formUnion(hits.keys)
            } else {
                captureCandidates = []
            }
        }
        return .init(
            samples: samples,
            overflowed: drainedEvents.overflowed
        )
    }

    func restoreSceneScriptPointerEvents(_ batch: SceneSurfacePointerEventBatch) {
        sceneScriptPointerEvents.restore(batch)
    }

    private func originInteractionHits(
        _ ownerLayerIDs: Set<Int>,
        pointer: SceneSurfacePointerEvent,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        puppetAttachmentFrames: ScenePuppetAttachmentFrameSnapshot = .empty
    ) -> [Int: SceneScriptCursorHit] {
        guard pointer.isInside else { return [:] }
        return originInteractionHits(
            originInteractionProjections(
                ownerLayerIDs,
                pointer: pointer,
                timing: timing,
                dynamicValues: dynamicValues,
                puppetAttachmentFrames: puppetAttachmentFrames
            ),
            pointerIsInside: pointer.isInside
        )
    }

    private func originInteractionHits(
        _ projections: [Int: SceneScriptCursorHit],
        pointerIsInside: Bool
    ) -> [Int: SceneScriptCursorHit] {
        guard pointerIsInside else { return [:] }
        return projections.filter { _, hit in
            hit.localPosition.x >= -0.5 && hit.localPosition.x <= 0.5
                && hit.localPosition.y >= -0.5 && hit.localPosition.y <= 0.5
        }
    }

#if DEBUG
    /// One-shot calibration aid. The hit test unprojects the pointer's
    /// normalized position through this layer's MVP and keeps it inside the
    /// local half-extent box, so a layer's own hit rectangle is recovered by
    /// projecting that box back to normalized coordinates. Logs each owner
    /// once per process. Retire together with the `3692` diagnostics when the
    /// cursor calibration and capture-chain items close.
    private static func logCursorNormalizedBoundsIfNeeded(
        layerID: Int,
        modelViewProjection: simd_float4x4
    ) {
        guard !sceneScriptCursorBoundsLoggedLayerIDs.contains(layerID) else {
            return
        }
        var minimum = SIMD2<Float>(0, 0)
        var maximum = SIMD2<Float>(0, 0)
        var isFirst = true
        for x in [Float(-0.5), 0.5] {
            for y in [Float(-0.5), 0.5] {
                let clip = modelViewProjection * SIMD4(x, y, 0, 1)
                guard clip.w.isFinite, abs(clip.w) > 1e-8 else { return }
                let normalized = SIMD2(clip.x / clip.w, clip.y / clip.w)
                guard normalized.x.isFinite, normalized.y.isFinite else {
                    return
                }
                minimum = isFirst ? normalized : simd_min(minimum, normalized)
                maximum = isFirst ? normalized : simd_max(maximum, normalized)
                isFirst = false
            }
        }
        guard !isFirst else { return }
        sceneScriptCursorBoundsLoggedLayerIDs.insert(layerID)
        NSLog(
            "MWX DEBUG SCENE: phase=cursor-normalized-bounds layer=%d min=%.6f,%.6f max=%.6f,%.6f",
            layerID, minimum.x, minimum.y, maximum.x, maximum.y
        )
    }
#endif

    private func originInteractionProjections(
        _ ownerLayerIDs: Set<Int>,
        pointer: SceneSurfacePointerEvent,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        puppetAttachmentFrames: ScenePuppetAttachmentFrameSnapshot = .empty
    ) -> [Int: SceneScriptCursorHit] {
        guard metalLayer.drawableSize.width > 0,
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
            staticFrames: renderer.worldFramesByLayerID,
            puppetAttachmentFrames: puppetAttachmentFrames
        )
        let parallax = renderer.parallaxConfiguration(

            viewportSize: frameContext.screenSize,
            dynamicValues: dynamicValues
        )
        var hits: [Int: SceneScriptCursorHit] = [:]
        for ownerLayerID in ownerLayerIDs {
            guard let layer = renderer.layersByID[ownerLayerID] else { continue }
            let model = renderer.imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFrames,
                parallaxMouseNormalized: .zero,
                configuration: parallax,
                visibleHalfExtents: cameraFrame.coverHalfExtents,
                usesPerspective: cameraFrame.resolvesPerspective(for: layer)
            )
            let modelViewProjection = cameraFrame.viewProjection(for: layer)
                * model
#if DEBUG
            Self.logCursorNormalizedBoundsIfNeeded(
                layerID: ownerLayerID,
                modelViewProjection: modelViewProjection
            )
#endif
            guard let local = SceneLayerCursorGeometry.layerPoint(
                mouseNormalized: pointer.normalizedPosition,
                modelViewProjection: modelViewProjection
            ) else { continue }
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
            let authoredWorld = SceneLayerCursorGeometry.authoredWorldPosition(
                world,
                sceneOrthoHeight: renderer.renderDescriptor.camera.orthoHeight
            )
            hits[ownerLayerID] = .init(
                layerID: ownerLayerID,
                worldPosition: SIMD3(
                    Double(authoredWorld.x),
                    Double(authoredWorld.y),
                    Double(authoredWorld.z)
                ),
                localPosition: SIMD3(
                    Double(local.x), Double(local.y), Double(local.z)
                )
            )
        }
        return hits
    }
}

import AppKit
import QuartzCore

extension SceneDesktopWallpaperHost {
    struct SceneScriptCursorBatchPreparation {
        let batch: SceneScriptCursorFrameBatch
        let drainedPointerBatches:
            [CGDirectDisplayID: SceneSurfacePointerEventBatch]
    }

    /// Builds the frame cursor batch while remembering which pointer events
    /// were drained from each surface. The caller restores both the drained
    /// batches and the cursor program edge state when the frame is not
    /// submitted, so a deferred/dropped frame never consumes press/release/
    /// click edges for input that was never displayed.
    func prepareSceneScriptCursorBatch(
        launchContext: SceneDesktopWallpaperLaunchContext,
        timing: SceneFrameTiming,
        preliminaryForSceneScript: SceneDynamicSnapshot,
        puppetAttachmentFrames: ScenePuppetAttachmentFrameSnapshot,
        layerSnapshotFailure: SceneScriptScalarRuntimeFailure?
    ) -> SceneScriptCursorBatchPreparation {
        let cursorBatch: SceneScriptCursorFrameBatch
        var drainedPointerBatches: [CGDirectDisplayID: SceneSurfacePointerEventBatch] = [:]
        if layerSnapshotFailure != nil {
            cursorBatch = .init(samples: [], overflowed: false)
        } else if surfaces.count == 1,
                  let (displayID, surface) = surfaces.first {
            let drained = surface.metalView.drainSceneScriptPointerEvents()
            drainedPointerBatches[displayID] = drained
            cursorBatch = surface.metalView.sceneScriptCursorFrameBatch(
                ownerLayerIDs: launchContext.sceneScriptCursorProgram.ownerLayerIDs,
                capturedOwnerLayerIDs:
                    launchContext.sceneScriptCursorProgram.capturedOwnerLayerIDs,
                timing: timing,
                dynamicValues: preliminaryForSceneScript,
                puppetAttachmentFrames: puppetAttachmentFrames,
                drainedEvents: drained
            )
        } else {
            var cursorHits: [Int: SceneScriptCursorHit] = [:]
            for (displayID, surface) in surfaces {
                drainedPointerBatches[displayID] =
                    surface.metalView.drainSceneScriptPointerEvents()
                cursorHits.merge(surface.metalView.sceneScriptCursorHits(
                    ownerLayerIDs: launchContext.sceneScriptCursorProgram.ownerLayerIDs,
                    timing: timing,
                    dynamicValues: preliminaryForSceneScript
                )) { existing, _ in existing }
            }
            cursorBatch = .init(
                samples: [.init(
                    hits: cursorHits,
                    primaryButtonIsDown: surfaces.values.contains {
                        $0.metalView.pointerState.isPrimaryButtonDown
                    }
                )],
                overflowed: false
            )
        }
        return .init(
            batch: cursorBatch,
            drainedPointerBatches: drainedPointerBatches
        )
    }
}

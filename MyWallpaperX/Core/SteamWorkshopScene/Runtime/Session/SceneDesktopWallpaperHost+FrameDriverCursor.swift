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
        guard layerSnapshotFailure == nil else {
            return .init(batch: .init(samples: [], overflowed: false), drainedPointerBatches: [:])
        }
        let program = launchContext.sceneScriptCursorProgram
        let edge = program.edgeStateSnapshot()
        let displayIDs = surfaces.keys.sorted()
        var drainedPointerBatches: [CGDirectDisplayID: SceneSurfacePointerEventBatch] = [:]
        var groups: [Double: [CGDirectDisplayID: SceneSurfacePointerEvent]] = [:]
        var current: [CGDirectDisplayID: SceneSurfacePointerEvent] = [:]
        var overflowed = false
        for displayID in displayIDs {
            guard let view = surfaces[displayID]?.metalView else { continue }
            let drained = view.drainSceneScriptPointerEvents()
            drainedPointerBatches[displayID] = drained
            overflowed = overflowed || drained.overflowed
            for event in drained.events {
                groups[event.timestamp, default: [:]][displayID] = event
            }
            let pointer = view.pointerState
            current[displayID] = .init(
                normalizedPosition: pointer.sceneScriptCurrent,
                isInside: pointer.isInside,
                primaryButtonIsDown: pointer.sceneScriptPrimaryButtonIsDown
            )
        }
        overflowed = overflowed || groups.count > SceneSurfacePointerEventBuffer.maximumEventCount
        // A native event is projected once per surface at ingress with the same
        // timestamp. Replay one ordered physical stream, including its final
        // state. Any lost surface queue rejects the whole physical batch.
        let ordered = (overflowed ? [] : groups.keys.sorted().compactMap { groups[$0] }) + [current]
        var capturedSurfaceID = edge.capturedSurfaceID
        var captureCandidates = Set(edge.capturedHits.keys)
        var previousSurfaceID = edge.previousSurfaceID
        var wasDown = edge.previousPrimaryButtonIsDown
        var samples: [SceneScriptCursorFrameSample] = []
        var previousInput: SceneSurfacePointerEvent?
        for group in ordered {
            let displayID = capturedSurfaceID.flatMap { group[$0] != nil ? $0 : nil }
                ?? displayIDs.first { group[$0]?.isInside == true }
                ?? previousSurfaceID.flatMap { group[$0] != nil ? $0 : nil }
                ?? displayIDs.first { group[$0] != nil }
            guard let displayID, let pointer = group[displayID],
                  let view = surfaces[displayID]?.metalView else { continue }
            var input = pointer
            input.timestamp = 0
            if previousInput == input && previousSurfaceID == displayID { continue }
            previousInput = input
            let leavingSurface = previousSurfaceID.flatMap { previousID -> SceneScriptSurfaceInput? in
                guard previousID != displayID, let previousPointer = group[previousID],
                      let previousView = surfaces[previousID]?.metalView else { return nil }
                return previousView.sceneScriptSurfaceInput(
                    pointer: previousPointer, timing: timing,
                    dynamicValues: preliminaryForSceneScript
                )
            }
            let sample = view.sceneScriptCursorFrameSample(
                pointer: pointer, surfaceID: displayID,
                leavingSurface: leavingSurface,
                ownerLayerIDs: program.ownerLayerIDs,
                capturedOwnerLayerIDs: captureCandidates,
                timing: timing,
                dynamicValues: preliminaryForSceneScript,
                puppetAttachmentFrames: puppetAttachmentFrames
            )
            samples.append(sample)
            if pointer.primaryButtonIsDown && !wasDown && !sample.hits.isEmpty {
                capturedSurfaceID = displayID
                captureCandidates = Set(sample.hits.keys)
            } else if !pointer.primaryButtonIsDown {
                capturedSurfaceID = nil
                captureCandidates = []
            }
            wasDown = pointer.primaryButtonIsDown
            previousSurfaceID = displayID
        }
        return .init(
            batch: .init(samples: samples, overflowed: overflowed),
            drainedPointerBatches: drainedPointerBatches
        )
    }
}

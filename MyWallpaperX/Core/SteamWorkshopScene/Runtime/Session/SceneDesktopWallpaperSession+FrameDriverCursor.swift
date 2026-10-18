import AppKit
import QuartzCore
import simd

extension SceneDesktopWallpaperSession {
    /// Drain physical input once for this simulation frame. Presentation retry
    /// consumes the evaluated frame and cannot replay its cursor callbacks.
    func prepareSceneScriptCursorBatch(
        launchContext: SceneDesktopWallpaperLaunchContext,
        timing: SceneFrameTiming,
        preliminaryForSceneScript: SceneDynamicSnapshot,
        puppetAttachmentFramesBySurface: [CGDirectDisplayID: ScenePuppetAttachmentFrameSnapshot],
        worldFramesBySurface: inout [CGDirectDisplayID: [Int: simd_float4x4]],
        layerSnapshotFailure: SceneScriptScalarRuntimeFailure?
    ) -> SceneScriptCursorFrameBatch {
        guard layerSnapshotFailure == nil else {
            return .init(samples: [], overflowed: false)
        }
        let program = launchContext.sceneScriptCursorProgram
        let edge = program.edgeStateSnapshot()
        let displayIDs = surfaces.keys.sorted()
        var groups: [Double: [CGDirectDisplayID: SceneSurfacePointerEvent]] = [:]
        var current: [CGDirectDisplayID: SceneSurfacePointerEvent] = [:]
        var overflowed = false
        for displayID in displayIDs {
            guard let view = surfaces[displayID]?.metalView else { continue }
            let drained = view.drainSceneScriptPointerEvents()
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
        // All input consumers share the caller's pre-script phase. Resolve a
        // demanded surface once, including a camera-only leaving surface.
        func worldFrames(
            for displayID: CGDirectDisplayID,
            view: SceneMetalView,
            requiresOwnerProjections: Bool
        ) -> [Int: simd_float4x4] {
            if worldFramesBySurface[displayID] == nil,
               view.requiresSceneScriptCameraWorldFrames || requiresOwnerProjections {
                worldFramesBySurface[displayID] = view.sceneScriptCursorWorldFrames(
                    dynamicValues: preliminaryForSceneScript,
                    puppetAttachmentFrames: puppetAttachmentFramesBySurface[displayID] ?? .empty)
            }
            return worldFramesBySurface[displayID] ?? [:]
        }
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
                    dynamicValues: preliminaryForSceneScript,
                    worldFrames: worldFrames(
                        for: previousID, view: previousView,
                        requiresOwnerProjections: false)
                )
            }
            let sample = view.sceneScriptCursorFrameSample(
                pointer: pointer, surfaceID: displayID,
                leavingSurface: leavingSurface,
                ownerLayerIDs: program.ownerLayerIDs,
                capturedOwnerLayerIDs: captureCandidates,
                timing: timing,
                dynamicValues: preliminaryForSceneScript,
                worldFrames: worldFrames(
                    for: displayID, view: view,
                    requiresOwnerProjections:
                        !(pointer.isInside ? program.ownerLayerIDs : captureCandidates).isEmpty)
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
        return .init(samples: samples, overflowed: overflowed)
    }
}

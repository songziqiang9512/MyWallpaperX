import Foundation
import simd

struct ScenePuppetScriptPoseFrame {
    static let empty = ScenePuppetScriptPoseFrame(
        posesByLayerID: [:],
        attachmentFrames: .empty,
        worldFrames: [:]
    )

    let posesByLayerID: [Int: ScenePuppetPlaybackState.PoseConfiguration]
    let attachmentFrames: ScenePuppetAttachmentFrameSnapshot
    let worldFrames: [Int: simd_float4x4]
}

extension SceneMetalView {
    /// Prepares the current animated hierarchy once before SceneScript. The
    /// resulting typed frame is also the attachment authority for layer world
    /// matrices and cursor collision in this callback snapshot.
    func prepareSceneScriptPuppetPoseFrame(
        timing: SceneFrameTiming,
        puppetAnimationFrame: ScenePuppetAnimationPlaybackRuntime.FrameSnapshot,
        dynamicValues: SceneDynamicSnapshot
    ) -> ScenePuppetScriptPoseFrame {
        guard !puppetPlaybackStates.isEmpty else { return .empty }
        var posesByLayerID: [Int: ScenePuppetPlaybackState.PoseConfiguration] = [:]
        var framesByParentLayerID: [Int: [String: simd_float4x4]] = [:]
        posesByLayerID.reserveCapacity(puppetPlaybackStates.count)
        framesByParentLayerID.reserveCapacity(puppetPlaybackStates.count)
        let frame = makeFrameContext(timing: timing, dynamicValues: dynamicValues,
            parallax: .zero, audioSpectrum: .silent)
        let camera = renderer.makeCameraFrame(frameContext: frame, worldFrames: renderer.worldFramesByLayerID)
        let parallax = renderer.parallaxConfiguration(cameraFrame: camera,
            viewportSize: frame.screenSize, dynamicValues: dynamicValues)
        let prepareAttachments: (SceneRenderDescriptor.Layer, [Int: simd_float4x4]) -> [String: simd_float4x4]? = { layer, worlds in
            let layerID = layer.id
            guard let playback = self.puppetPlaybackStates[layerID],
                  let samples = puppetAnimationFrame[layerID] else { return nil }
            let model = layer.staticModelPath != nil
                ? self.renderer.staticModelWorld(for: layerID, worldFrames: worlds)
                : self.renderer.geometryModelMatrix(for: layer, worldFramesByLayerID: worlds,
                    authoredSize: SIMD2<Float>(layer.renderSizeWH ?? [], fill: 0),
                    parallaxMouseNormalized: .zero, configuration: parallax,
                    visibleHalfExtents: camera.coverHalfExtents,
                    usesPerspective: camera.resolvesPerspective(for: layer))
            let meshToWorld = SceneLayerCursorGeometry.authoredWorldTransform(
                model, sceneOrthoHeight: self.renderer.renderDescriptor.camera.orthoHeight)
            playback.advanceBonePhysics(
                animationFrame: samples, deltaTime: timing.simulationFrameTime,
                frameIndex: timing.frameIndex, meshToWorld: meshToWorld
            )
            guard let pose = playback.poseConfiguration(
                animationFrame: samples, meshToWorld: meshToWorld
            ) else { return nil }
            posesByLayerID[layerID] = pose
            if !pose.attachmentFrames.isEmpty {
                framesByParentLayerID[layerID] = pose.attachmentFrames
            }
            return pose.attachmentFrames
        }
        let worldFrames: [Int: simd_float4x4]
        if puppetPlaybackStates.values.contains(where: { $0.hasTranslationPhysics || $0.hasAttachments }) {
            worldFrames = SceneLayerDynamicWorldFrameResolver.resolve(
                descriptor: renderer.renderDescriptor, byID: renderer.layersByID,
                snapshot: dynamicValues, staticFrames: renderer.worldFramesByLayerID,
                prepareLayerAttachments: prepareAttachments)
        } else {
            // Ordinary static rigs retain the cached hierarchy path.
            worldFrames = sceneScriptCursorWorldFrames(dynamicValues: dynamicValues,
                puppetAttachmentFrames: .empty)
            for layerID in puppetPlaybackStates.keys {
                if let layer = renderer.layersByID[layerID] {
                    _ = prepareAttachments(layer, worldFrames)
                }
            }
        }
        return ScenePuppetScriptPoseFrame(
            posesByLayerID: posesByLayerID,
            attachmentFrames: .init(
                framesByParentLayerID: framesByParentLayerID
            ),
            worldFrames: worldFrames
        )
    }

    /// Publishes bones through the same current layer/attachment world frames
    /// already installed in the SceneScript layer snapshot. No asset parsing
    /// or second hierarchy evaluation occurs here.
    func publishSceneScriptPuppetPoseFrame(
        _ poseFrame: ScenePuppetScriptPoseFrame,
        context: SceneDesktopWallpaperLaunchContext,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot,
        worldFrames: [Int: simd_float4x4]
    ) throws {
        guard !poseFrame.posesByLayerID.isEmpty else { return }
#if DEBUG
        let frame = makeFrameContext(timing: timing, dynamicValues: dynamicValues,
            parallax: .zero, audioSpectrum: .silent)
        let camera = renderer.makeCameraFrame(frameContext: frame, worldFrames: worldFrames)
#endif
        for (layerID, pose) in poseFrame.posesByLayerID {
            guard let layer = renderer.layersByID[layerID] else { continue }
            let bones = pose.bones
            let meshToWorld = pose.meshToWorld
            let transform = [meshToWorld.columns.0, meshToWorld.columns.1,
                             meshToWorld.columns.2, meshToWorld.columns.3]
                .flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
            let configured = try context.configurePuppetBones(
                layerID: layerID, localMatrices: pose.queryLocalMatrices,
                renderLocalMatrices: bones.localMatrices,
                // Names were installed at launch; frame refresh never reallocates them.
                names: [], parents: bones.parentIndices.map(Int32.init),
                layerToWorld: transform)
#if DEBUG
            if configured, SceneDesktopWallpaperHost.usesDebugEvidenceWindow,
               recordedPuppetPoseLayerIDs.insert(layerID).inserted,
               bones.worldMatrices.count >= 16 {
                let root = meshToWorld * SIMD4(Float(bones.worldMatrices[12]),
                    Float(bones.worldMatrices[13]), Float(bones.worldMatrices[14]), 1)
                NSLog("MWX DEBUG SCENE: phase=puppet-owner-pose layer=%d bones=%d rootWorld=%.6f,%.6f,%.6f frame=%llu",
                    layerID, bones.parentIndices.count, root.x, root.y, root.z, timing.frameIndex)
                if ScenePuppetBoneEvidence.isEnabled(for: layerID) {
                    // Qualification only: project the already-published pose,
                    // without exposing names or evaluating another hierarchy.
                    let model = SceneLayerCursorGeometry.authoredWorldTransform(meshToWorld,
                        sceneOrthoHeight: renderer.renderDescriptor.camera.orthoHeight)
                    let projection = camera.viewProjection(for: layer) * model
                    let count = min(bones.parentIndices.count, bones.worldMatrices.count / 16)
                    for index in 0..<count {
                        let offset = index * 16
                        let origin = SIMD4(
                            Float(bones.worldMatrices[offset + 12]),
                            Float(bones.worldMatrices[offset + 13]),
                            Float(bones.worldMatrices[offset + 14]), 1)
                        let world = meshToWorld * origin
                        let clip = projection * origin
                        guard [world.x, world.y, world.z, clip.x, clip.y, clip.z, clip.w]
                            .allSatisfy(\.isFinite), abs(clip.w) > 1e-8 else {
                            NSLog("MWX DEBUG SCENE: phase=puppet-bone-origin layer=%d bone=%d frame=%llu finite=false inViewport=false projectionDomain=layer-render",
                                layerID, index, timing.frameIndex)
                            continue
                        }
                        let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
                        guard ndc.x.isFinite, ndc.y.isFinite, ndc.z.isFinite else {
                            NSLog("MWX DEBUG SCENE: phase=puppet-bone-origin layer=%d bone=%d frame=%llu finite=false inViewport=false projectionDomain=layer-render",
                                layerID, index, timing.frameIndex)
                            continue
                        }
                        let inViewport = clip.w > 0
                            && (-1...1).contains(ndc.x) && (-1...1).contains(ndc.y)
                            && (0...1).contains(ndc.z)
                        NSLog("MWX DEBUG SCENE: phase=puppet-bone-origin layer=%d bone=%d frame=%llu world=%.6f,%.6f,%.6f ndc=%.6f,%.6f,%.6f finite=true inViewport=%@ projectionDomain=layer-render",
                            layerID, index, timing.frameIndex,
                            world.x, world.y, world.z, ndc.x, ndc.y, ndc.z,
                            inViewport ? "true" : "false")
                    }
                }
            }
#endif
        }
    }
}

import Foundation
import simd

struct ScenePuppetScriptPoseFrame {
    static let empty = ScenePuppetScriptPoseFrame(
        posesByLayerID: [:],
        attachmentFrames: .empty
    )

    let posesByLayerID: [Int: ScenePuppetPlaybackState.PoseConfiguration]
    let attachmentFrames: ScenePuppetAttachmentFrameSnapshot
}

extension SceneMetalView {
    /// Prepares the current animated hierarchy once before SceneScript. The
    /// resulting typed frame is also the attachment authority for layer world
    /// matrices and cursor collision in this callback snapshot.
    func prepareSceneScriptPuppetPoseFrame(
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) -> ScenePuppetScriptPoseFrame {
        guard !puppetPlaybackStates.isEmpty else { return .empty }
        var posesByLayerID: [Int: ScenePuppetPlaybackState.PoseConfiguration] = [:]
        var framesByParentLayerID: [Int: [String: simd_float4x4]] = [:]
        posesByLayerID.reserveCapacity(puppetPlaybackStates.count)
        framesByParentLayerID.reserveCapacity(puppetPlaybackStates.count)
        for (layerID, playback) in puppetPlaybackStates {
            playback.advanceBonePhysics(
                sceneTime: timing.sceneTime,
                deltaTime: timing.simulationFrameTime,
                dynamicValues: dynamicValues
            )
            guard let pose = playback.poseConfiguration(
                sceneTime: timing.sceneTime,
                dynamicValues: dynamicValues
            ) else { continue }
            posesByLayerID[layerID] = pose
            if !pose.attachmentFrames.isEmpty {
                framesByParentLayerID[layerID] = pose.attachmentFrames
            }
        }
        return ScenePuppetScriptPoseFrame(
            posesByLayerID: posesByLayerID,
            attachmentFrames: .init(
                framesByParentLayerID: framesByParentLayerID
            )
        )
    }

    /// Publishes bones through the same current layer/attachment world frames
    /// already installed in the SceneScript layer snapshot. No asset parsing
    /// or second hierarchy evaluation occurs here.
    func publishSceneScriptPuppetPoseFrame(
        _ poseFrame: ScenePuppetScriptPoseFrame,
        context: SceneDesktopWallpaperLaunchContext,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) throws {
        guard !poseFrame.posesByLayerID.isEmpty else { return }
        let frame = makeFrameContext(timing: timing, dynamicValues: dynamicValues,
            parallax: .zero, audioSpectrum: .silent)
        let camera = renderer.makeCameraFrame(frameContext: frame)
        let worlds = SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: renderer.renderDescriptor, byID: renderer.layersByID,
            snapshot: dynamicValues,
            staticFrames: renderer.worldFramesByLayerID,
            puppetAttachmentFrames: poseFrame.attachmentFrames
        )
        let parallax = renderer.parallaxConfiguration(
            viewportSize: frame.screenSize,
            dynamicValues: dynamicValues)
        for (layerID, pose) in poseFrame.posesByLayerID {
            guard let layer = renderer.layersByID[layerID] else { continue }
            let bones = pose.bones
            let authoredSize = SIMD2<Float>(layer.renderSizeWH ?? [], fill: 0)
            let model = renderer.geometryModelMatrix(
                for: layer, worldFramesByLayerID: worlds,
                authoredSize: authoredSize,
                parallaxMouseNormalized: .zero, configuration: parallax,
                visibleHalfExtents: camera.coverHalfExtents,
                usesPerspective: camera.resolvesPerspective(for: layer))
            let meshToWorld = model
            let transform = [meshToWorld.columns.0, meshToWorld.columns.1,
                             meshToWorld.columns.2, meshToWorld.columns.3]
                .flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
            let configured = try context.configurePuppetBones(
                layerID: layerID, worldMatrices: bones.worldMatrices,
                localMatrices: bones.localMatrices,
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
            }
#endif
        }
    }
}

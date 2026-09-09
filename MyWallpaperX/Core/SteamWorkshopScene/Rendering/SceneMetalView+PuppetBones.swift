import Foundation
import simd

extension SceneMetalView {
    /// Refresh the existing VM owners from the same current pose and image
    /// transform used by skinning and cursor geometry. No assets are parsed.
    func refreshSceneScriptPuppetBones(
        context: SceneDesktopWallpaperLaunchContext,
        timing: SceneFrameTiming,
        dynamicValues: SceneDynamicSnapshot
    ) throws {
        guard !puppetPlaybackStates.isEmpty else { return }
        let frame = makeFrameContext(timing: timing, dynamicValues: dynamicValues,
            parallax: .zero, audioSpectrum: .silent)
        let camera = renderer.makeCameraFrame(frameContext: frame)
        let worlds = SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: renderer.renderDescriptor, byID: renderer.layersByID,
            snapshot: dynamicValues, staticFrames: renderer.worldFramesByLayerID)
        let parallax = renderer.parallaxConfiguration(
            cameraFrame: camera, viewportSize: frame.screenSize)
        for (layerID, playback) in puppetPlaybackStates {
            guard let layer = renderer.layersByID[layerID],
                  let bones = playback.boneConfiguration(
                    sceneTime: timing.sceneTime, dynamicValues: dynamicValues)
            else { continue }
            let coverage = playback.meshCoverageSize
            let model = renderer.imageModelMatrix(
                for: layer, worldFramesByLayerID: worlds,
                renderSizeOverride: [coverage.x, coverage.y],
                parallaxMouseNormalized: .zero, configuration: parallax,
                visibleHalfExtents: camera.coverHalfExtents,
                usesPerspective: camera.resolvesPerspective(for: layer))
            let meshToWorld = model * SceneMatrix.scale(
                SIMD3(1 / coverage.x, 1 / coverage.y, 1))
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

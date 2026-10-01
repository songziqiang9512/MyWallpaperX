import Metal

#if DEBUG
extension SceneMetalRenderer {
    /// DEBUG-only evidence for the static-model light path: one snapshot
    /// line at compositor-seal time and one completion line when the shared
    /// command buffer lands, mirroring this frame's point-lit encode
    /// decisions. Compiled out of Release builds together with its caller.
    func logStaticModelLightExecutionEvidence(
        frameContext: SceneFrameContext,
        frameLightSnapshot: SceneLightSnapshot,
        encodedLayerIDs: [Int],
        commandBuffer: MTLCommandBuffer
    ) {
        let encodedLayerIDText = encodedLayerIDs
            .map(String.init).joined(separator: ",")
        let encodedLayerCount = encodedLayerIDs.count
        NSLog(
            "MWX DEBUG SCENE: phase=static-model-light-snapshot frame=%llu directional=%d point=%d spot=%d overflow=%d pointLitEncoded=%d layers=%@",
            frameContext.frameIndex,
            frameLightSnapshot.directional.count,
            frameLightSnapshot.point.count,
            frameLightSnapshot.spot.count,
            frameLightSnapshot.overflowCount,
            encodedLayerCount,
            encodedLayerIDText
        )
        commandBuffer.addCompletedHandler { buffer in
            NSLog(
                "MWX DEBUG SCENE: phase=static-model-light-completion frame=%llu status=%@ error=%@ pointLitEncoded=%d layers=%@",
                frameContext.frameIndex,
                String(describing: buffer.status),
                buffer.error.map(String.init(describing:)) ?? "none",
                encodedLayerCount,
                encodedLayerIDText
            )
        }
    }
}
#endif

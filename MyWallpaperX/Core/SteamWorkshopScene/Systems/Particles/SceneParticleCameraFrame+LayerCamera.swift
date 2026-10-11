import simd

extension SceneParticleCameraFrame {
    /// A camera layer owns the working native-perspective view when present;
    /// the scene-level Eye/Center/Up remains the no-camera fallback. Camera-path
    /// origin/zoom is already published through the shared dynamic camera target.
    static func nativePerspectiveOverride(
        descriptor: SceneRenderDescriptor,
        layersByID: [Int: SceneRenderDescriptor.Layer],
        worldFrames: [Int: simd_float4x4],
        dynamicValues: SceneDynamicSnapshot
    ) -> SceneParticleCameraFrame.NativePerspectiveOverride? {
        let fallbackCamera = descriptor.camera
        guard fallbackCamera.orthoWidth == nil,
              fallbackCamera.orthoHeight == nil else { return nil }
        guard let layer = descriptor.renderOrderLayerIDs.reversed()
            .compactMap({ layersByID[$0] })
            .first(where: {
                SceneLayerVisibility.isEffectivelyVisible(
                    layerID: $0.id,
                    in: descriptor,
                    layersByID: layersByID,
                    snapshot: dynamicValues
                )
                    && $0.cameraPath?.camera.lowercased() == "default"
            }),
              let cameraPath = layer.cameraPath,
              let worldFrame = worldFrames[layer.id] else { return nil }
        let fov = cameraPath.fov.map(Float.init) ?? fallbackCamera.fovDegrees
        guard let fov else { return nil }
        return SceneParticleCameraFrame.NativePerspectiveOverride(
            worldFrame: worldFrame,
            fovDegrees: fov
        )
    }

}

import CoreGraphics
import simd

extension SceneMetalRenderer {
    func makeCameraFrame(
        frameContext: SceneFrameContext
    ) -> SceneParticleCameraFrame {
        let camera = renderDescriptor.camera
        let dynamic = frameContext.dynamicValues.cameraTransform()
        let admission = SceneCameraShake.admission(camera)
        let orthographicShake = SceneCameraShake.orthographicOffset(
            admission: admission,
            sceneTime: frameContext.sceneTime
        )
        return SceneParticleCameraFrame(
            camera: camera,
            viewportSize: frameContext.screenSize,
            cameraOrigin: dynamic.origin + SIMD3(
                orthographicShake.x,
                orthographicShake.y,
                0
            ),
            cameraZoom: dynamic.zoom,
            nativePerspectiveOverride: activeNativePerspectiveCamera(
                dynamicValues: frameContext.dynamicValues
            )
        )
    }

    /// A camera layer owns the working native-perspective view when present;
    /// the scene-level Eye/Center/Up remains the no-camera fallback. Camera-path
    /// origin/zoom is already published through the shared dynamic camera target.
    private func activeNativePerspectiveCamera(
        dynamicValues: SceneDynamicSnapshot
    ) -> SceneParticleCameraFrame.NativePerspectiveOverride? {
        let fallbackCamera = renderDescriptor.camera
        guard fallbackCamera.orthoWidth == nil,
              fallbackCamera.orthoHeight == nil else { return nil }
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: renderDescriptor,
            snapshot: dynamicValues
        )
        guard let layer = renderDescriptor.renderOrderLayerIDs.reversed()
            .compactMap({ layersByID[$0] })
            .first(where: {
                visibleLayerIDs.contains($0.id)
                    && $0.cameraPath?.camera.lowercased() == "default"
            }),
              let cameraPath = layer.cameraPath,
              let worldFrame = worldFramesByLayerID[layer.id] else { return nil }
        let fov = cameraPath.fov.map(Float.init) ?? fallbackCamera.fovDegrees
        guard let fov else { return nil }
        return SceneParticleCameraFrame.NativePerspectiveOverride(
            worldFrame: worldFrame,
            fovDegrees: fov
        )
    }

    func parallaxConfiguration(
        cameraFrame: SceneParticleCameraFrame,
        viewportSize: CGSize
    ) -> SceneLayerParallax.Configuration {
        let camera = renderDescriptor.camera
        let orthoSize = SIMD2<Float>(
            camera.orthoWidth ?? Float(viewportSize.width),
            camera.orthoHeight ?? Float(viewportSize.height)
        )
        return SceneLayerParallax.Configuration(
            enabled: camera.parallaxEnabled,
            amount: camera.parallaxAmount,
            mouseInfluence: camera.parallaxMouseInfluence,
            orthoSize: orthoSize,
            cameraPosition: orthoSize * 0.5 + SIMD2(
                cameraFrame.cameraOrigin.x,
                cameraFrame.cameraOrigin.y
            )
        )
    }
}

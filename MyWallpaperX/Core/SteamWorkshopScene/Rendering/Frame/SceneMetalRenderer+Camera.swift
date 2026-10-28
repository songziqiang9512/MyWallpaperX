import CoreGraphics
import simd

extension SceneMetalRenderer {
    func makeCameraFrame(
        frameContext: SceneFrameContext,
        worldFrames: [Int: simd_float4x4]
    ) -> SceneParticleCameraFrame {
        let camera = renderDescriptor.camera
        // Visibility controls consumption, not Timeline playback. Hidden paths
        // keep evaluating on SceneClock; showing one does not imply a replay.
        let consumesPath = camera.default2DInputLayerID.map {
            SceneLayerVisibility.isEffectivelyVisible(layerID: $0,
                in: renderDescriptor, layersByID: layersByID,
                snapshot: frameContext.dynamicValues)
        } ?? true
        let dynamic = frameContext.dynamicValues.cameraTransform()
        let property = frameContext.dynamicValues.cameraPropertyProjection()
        let shake = SceneRenderDescriptor.CameraDescriptor.ShakeDescriptor(
            enabled: property.shakeEnabled ?? camera.shake.enabled,
            amplitude: property.shakeAmplitude ?? camera.shake.amplitude,
            roughness: property.shakeRoughness ?? camera.shake.roughness,
            speed: property.shakeSpeed ?? camera.shake.speed
        )
        let admission = SceneCameraShake.admission(camera, shake: shake)
        let orthographicShake = SceneCameraShake.orthographicOffset(
            admission: admission,
            sceneTime: frameContext.sceneTime
        )
        return SceneParticleCameraFrame(
            camera: camera,
            viewportSize: frameContext.screenSize,
            cameraOrigin: (consumesPath ? dynamic.origin : .zero) + SIMD3(
                orthographicShake.x,
                orthographicShake.y,
                0
            ),
            cameraZoom: consumesPath && (camera.orthoWidth != nil || camera.orthoHeight != nil)
                ? dynamic.zoom : 1,
            staticEye: dynamic.eye,
            staticCenter: dynamic.center,
            staticUp: dynamic.up,
            nativePerspectiveOverride: SceneParticleCameraFrame.nativePerspectiveOverride(
                descriptor: renderDescriptor, layersByID: layersByID,
                worldFrames: worldFrames, dynamicValues: frameContext.dynamicValues
            ),
            dynamicValues: frameContext.dynamicValues
        )
    }

    func parallaxConfiguration(
        cameraFrame: SceneParticleCameraFrame,
        viewportSize: CGSize,
        dynamicValues: SceneDynamicSnapshot
    ) -> SceneLayerParallax.Configuration {
        let camera = renderDescriptor.camera
        let property = dynamicValues.cameraPropertyProjection()
        let orthoSize = SIMD2<Float>(
            camera.orthoWidth ?? Float(viewportSize.width),
            camera.orthoHeight ?? Float(viewportSize.height)
        )
        return SceneLayerParallax.Configuration(
            enabled: property.parallaxEnabled ?? camera.parallaxEnabled,
            amount: property.parallaxAmount ?? camera.parallaxAmount,
            mouseInfluence:
                property.parallaxMouseInfluence
                    ?? camera.parallaxMouseInfluence,
            orthoSize: orthoSize,
            cameraPosition: orthoSize * 0.5 + SIMD2(
                cameraFrame.cameraOrigin.x,
                cameraFrame.cameraOrigin.y
            ),
            worldYDown: (camera.orthoHeight ?? 0) > 0
        )
    }
}

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
            cameraZoom: dynamic.zoom
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

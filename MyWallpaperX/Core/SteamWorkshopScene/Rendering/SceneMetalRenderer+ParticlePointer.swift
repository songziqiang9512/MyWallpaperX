import Foundation
import simd

extension SceneMetalRenderer {
    func particlePointerLocalPositions(
        frameContext: SceneFrameContext
    ) -> [Int: SIMD3<Double>] {
        guard frameContext.pointer.isInside else { return [:] }
        let viewportSize = frameContext.screenSize
        let cameraFrame = SceneParticleCameraFrame(
            camera: renderDescriptor.camera,
            viewportSize: viewportSize
        )
        let camera = renderDescriptor.camera
        let configuration = SceneLayerParallax.Configuration(
            enabled: camera.parallaxEnabled,
            amount: camera.parallaxAmount,
            mouseInfluence: camera.parallaxMouseInfluence,
            orthoSize: SIMD2(
                camera.orthoWidth ?? Float(viewportSize.width),
                camera.orthoHeight ?? Float(viewportSize.height)
            )
        )
        return Dictionary(uniqueKeysWithValues: renderDescriptor.layers.compactMap {
            layer -> (Int, SIMD3<Double>)? in
            guard layer.contentKind == "particle" else { return nil }
            let model = particleModelMatrix(
                for: layer,
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: configuration
            )
            let mvp = cameraFrame.orthographicViewProjection * model
            guard let position = SceneParticlePointerProjection.localPosition(
                mouseNormalized: frameContext.pointer.current,
                isInside: frameContext.pointer.isInside,
                modelViewProjection: mvp
            ) else { return nil }
            return (layer.id, position)
        })
    }
}

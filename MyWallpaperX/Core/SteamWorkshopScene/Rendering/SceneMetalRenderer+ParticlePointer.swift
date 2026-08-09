import Foundation
import simd

extension SceneMetalRenderer {
    func particlePointerLocalPositions(
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame
    ) -> [Int: SIMD3<Double>] {
        guard frameContext.pointer.isInside else { return [:] }
        let viewportSize = frameContext.screenSize
        let configuration = parallaxConfiguration(
            cameraFrame: cameraFrame,
            viewportSize: viewportSize
        )
        let frameWorldFrames = SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: renderDescriptor, byID: layersByID,
            snapshot: frameContext.dynamicValues, staticFrames: worldFramesByLayerID
        )
        return Dictionary(uniqueKeysWithValues: renderDescriptor.layers.compactMap {
            layer -> (Int, SIMD3<Double>)? in
            guard layer.contentKind == "particle" else { return nil }
            let model = particleModelMatrix(
                for: layer,
                worldFramesByLayerID: frameWorldFrames,
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

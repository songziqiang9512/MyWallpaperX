import Foundation
import simd

extension SceneMetalRenderer {
    func particlePointerLocalPositions(
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        frameProjection: SceneMetalRendererFrameWorldProjection,
        demandedLayerIDs: Set<Int>
    ) -> [Int: SIMD3<Double>] {
        guard frameContext.pointer.isInside, !demandedLayerIDs.isEmpty else { return [:] }
        let viewportSize = frameContext.screenSize
        let configuration = parallaxConfiguration(
            cameraFrame: cameraFrame,

            viewportSize: viewportSize,
            dynamicValues: frameContext.dynamicValues
        )
        return Dictionary(uniqueKeysWithValues: demandedLayerIDs.compactMap { layerID in
            guard let layer = frameProjection.layersByID[layerID] else { return nil }
            guard layer.contentKind == "particle" else { return nil }
            let model = particleModelMatrix(
                for: layer,
                worldFramesByLayerID: frameProjection.worldFrames,
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

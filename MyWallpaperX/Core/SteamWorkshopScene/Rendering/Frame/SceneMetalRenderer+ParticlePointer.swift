import Foundation
import simd

extension SceneMetalRenderer {
    func particlePointerLocalPositions<Demands: Collection>(
        frameContext: SceneFrameContext,
        cameraFrame: SceneParticleCameraFrame,
        frameProjection: SceneMetalRendererFrameWorldProjection,
        demands: Demands
    ) -> [Int: SIMD3<Double>] where Demands.Element == (key: Int, value: SceneParticlePointerDemand) {
        guard frameContext.pointer.isInside, !demands.isEmpty else { return [:] }
        let viewportSize = frameContext.screenSize
        let configuration = parallaxConfiguration(
            cameraFrame: cameraFrame,

            viewportSize: viewportSize,
            dynamicValues: frameContext.dynamicValues
        )
        return Dictionary(uniqueKeysWithValues: demands.compactMap { layerID, demand in
            guard let layer = frameProjection.layersByID[layerID] else { return nil }
            guard layer.contentKind == "particle" else { return nil }
            let model = particleModelMatrix(
                for: layer,
                worldFramesByLayerID: frameProjection.worldFrames,
                parallaxMouseNormalized: frameContext.cameraParallaxPosition,
                configuration: configuration,
                referenceWorldFrame: demand.referenceWorldFrame
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

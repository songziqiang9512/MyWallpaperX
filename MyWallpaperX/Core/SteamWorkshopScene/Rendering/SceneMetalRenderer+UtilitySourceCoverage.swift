import simd

extension SceneMetalRenderer {
    func hasOpaqueFullViewportUtilitySource(
        route: SceneUtilityLayerSourceRoute.Resolution,
        imageTextures: SceneBaseImageTextureSnapshot,
        frameContext: SceneFrameContext,
        worldFramesByLayerID: [Int: simd_float4x4],
        cameraFrame: SceneParticleCameraFrame,
        parallaxConfiguration: SceneLayerParallax.Configuration
    ) -> Bool {
        let framePairs: [
            (Int, SceneUtilityLayerSourceCoverage.LayerFrame)
        ] = route.orderedCompositionSubtreeLayerIDs.compactMap { layerID in
            guard visibleLayerIDs.contains(layerID),
                  let layer = layersByID[layerID],
                  let texture = imageTextures[layerID] else {
                return nil
            }
            let candidate = imageTextures.candidate(
                for: layerID,
                matching: texture
            ) ?? imageTextures.explicitLayerSourcePublication(
                for: layerID,
                matching: texture
            )?.candidate
            guard let content = candidate?.content else { return nil }
            let model = imageModelMatrix(
                for: layer,
                worldFramesByLayerID: worldFramesByLayerID,
                parallaxMouseNormalized:
                    frameContext.cameraParallaxPosition,
                configuration: parallaxConfiguration,
                visibleHalfExtents: cameraFrame.coverHalfExtents
            )
            return (
                layerID,
                SceneUtilityLayerSourceCoverage.LayerFrame(
                    content: content,
                    alpha: SceneDynamicLayerValues.alpha(
                        layerID: layerID,
                        authoredValue: layer.alpha,
                        snapshot: frameContext.dynamicValues
                    ),
                    modelViewProjection:
                        cameraFrame.orthographicViewProjection * model
                )
            )
        }
        let framesByLayerID = Dictionary(uniqueKeysWithValues: framePairs)
        return SceneUtilityLayerSourceCoverage.hasOpaqueFullViewportSource(
            route: route,
            descriptor: renderDescriptor,
            framesByLayerID: framesByLayerID,
            viewportSize: frameContext.screenSize
        )
    }
}

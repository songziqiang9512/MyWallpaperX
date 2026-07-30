import simd

extension SceneMetalRenderer {
    func effectMasks(
        for layerID: Int,
        in store: SceneLayerEffectTextureStore
    ) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            iris: store.irisMasks[layerID],
            opacity: store.opacityMasks[layerID],
            water: store.waterMasks[layerID],
            waterUVScale: store.waterUVScales[layerID] ?? SIMD2(repeating: 1),
            foliage: store.foliageMasks[layerID],
            foliageUVScale: store.foliageUVScales[layerID] ?? SIMD2(repeating: 1),
            waterRippleNormal: store.waterRippleNormals[layerID],
            foliageSwayEffects: store.foliageSwayEffects,
            waterRippleEffects: store.waterRippleEffects,
            depthParallaxEffects: store.depthParallaxEffects,
            blendEffects: store.blendEffects,
            shakeEffects: store.shakeEffects,
            filmGrainEffects: store.filmGrainEffects,
            standardBlurEffects: store.standardBlurEffects,
            waterFlowEffects: store.waterFlowEffects,
            waterWavesEffects: store.waterWavesEffects,
            cursorRippleEffects: store.cursorRippleEffects,
            opacityEffects: store.opacityEffects,
            pulseEffects: store.pulseEffects,
            tintEffects: store.tintEffects,
            godraysEffects: store.godraysEffects,
            shineEffects: store.shineEffects,
            xRay: store.xRayEffects[layerID]
        )
    }
}

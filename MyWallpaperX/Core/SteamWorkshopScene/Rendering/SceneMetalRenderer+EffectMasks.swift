extension SceneMetalRenderer {
    func effectMasks(
        for layerID: Int,
        in store: SceneLayerEffectTextureStore
    ) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            foliageSwayEffects: store.foliageSwayEffects,
            waterRippleEffects: store.waterRippleEffects,
            depthParallaxEffects: store.depthParallaxEffects,
            blendEffects: store.blendEffects,
            shakeEffects: store.shakeEffects,
            filmGrainEffects: store.filmGrainEffects,
            standardBlurEffects: store.standardBlurEffects,
            waterFlowEffects: store.waterFlowEffects,
            waterWavesEffects: store.waterWavesEffects,
            waterCausticsEffects: store.waterCausticsEffects,
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

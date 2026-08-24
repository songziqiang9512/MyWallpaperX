extension SceneMetalRenderer {
    func effectMasks(
        for layerID: Int,
        in store: SceneLayerEffectTextureStore
    ) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            blendEffects: store.blendEffects,
            standardBlurEffects: store.standardBlurEffects,
            waterWavesEffects: store.waterWavesEffects,
            waterCausticsEffects: store.waterCausticsEffects,
            pulseEffects: store.pulseEffects,
            godraysEffects: store.godraysEffects,
            shineEffects: store.shineEffects,
            xRay: store.xRayEffects[layerID]
        )
    }
}

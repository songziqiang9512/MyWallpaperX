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
            xRay: store.xRayEffects[layerID]
        )
    }
}

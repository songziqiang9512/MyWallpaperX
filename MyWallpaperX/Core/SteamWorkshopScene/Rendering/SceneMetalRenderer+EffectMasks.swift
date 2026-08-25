extension SceneMetalRenderer {
    func effectMasks(
        for layerID: Int,
        in store: SceneLayerEffectTextureStore
    ) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            blendEffects: store.blendEffects,
            standardBlurEffects: store.standardBlurEffects,
            pulseEffects: store.pulseEffects,
            xRay: store.xRayEffects[layerID]
        )
    }
}

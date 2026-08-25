extension SceneMetalRenderer {
    func effectMasks(
        for layerID: Int,
        in store: SceneLayerEffectTextureStore
    ) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            standardBlurEffects: store.standardBlurEffects,
            pulseEffects: store.pulseEffects,
            xRay: store.xRayEffects[layerID]
        )
    }
}

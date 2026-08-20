extension SceneMetalRenderer {
    func effectMasks(
        for layerID: Int,
        in store: SceneLayerEffectTextureStore
    ) -> SceneImageLayerMasks {
        SceneImageLayerMasks(
            waterRippleEffects: store.waterRippleEffects,
            depthParallaxEffects: store.depthParallaxEffects,
            blendEffects: store.blendEffects,
            shakeEffects: store.shakeEffects,
            standardBlurEffects: store.standardBlurEffects,
            waterFlowEffects: store.waterFlowEffects,
            waterWavesEffects: store.waterWavesEffects,
            waterCausticsEffects: store.waterCausticsEffects,
            cursorRippleEffects: store.cursorRippleEffects,
            pulseEffects: store.pulseEffects,
            godraysEffects: store.godraysEffects,
            shineEffects: store.shineEffects,
            lightShaftsEffects: store.lightShaftsEffects,
            xRay: store.xRayEffects[layerID]
        )
    }
}

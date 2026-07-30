import Metal

extension SceneLayerEffectTextureLoader {
    /// Derive per-instance resource requests only from stages that will execute.
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        stages: [SceneAuthoredEffectExecutionPlan],
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        userPropertyTextures: [String: MTLTexture],
        preservedUserPropertyTextures: [String: MTLTexture]
    ) -> SceneLayerEffectTextures {
        load(
            for: layer,
            resolver: resolver,
            loader: loader,
            device: device,
            blendEffectIDs: Set(stages.compactMap { $0.blend?.effectKey.descriptorID }),
            shakeEffectIDs: Set(stages.compactMap { $0.shake?.effectKey.descriptorID }),
            filmGrainEffectIDs: Set(stages.compactMap { $0.filmGrain?.effectKey.descriptorID }),
            standardBlurEffectIDs: Set(stages.compactMap {
                $0.standardBlur?.effectDescriptorID
            }),
            lightShaftsEffectIDs: Set(
                stages.compactMap { $0.lightShafts?.effectKey.descriptorID }
            ),
            waterFlowEffectIDs: Set(stages.compactMap { $0.waterFlow?.effectKey.descriptorID }),
            waterWavesEffectIDs: Set(stages.compactMap { $0.waterWaves?.effectKey.descriptorID }),
            foliageSwayEffectIDs: Set(
                stages.compactMap { $0.foliageSway?.effectKey.descriptorID }
            ),
            waterRippleEffectIDs: Set(
                stages.compactMap { $0.waterRipple?.effectKey.descriptorID }
            ),
            cursorRippleEffectIDs: Set(
                stages.compactMap { $0.cursorRipple?.effectKey.descriptorID }
            ),
            tintEffectIDs: Set(stages.compactMap { $0.tint?.effectKey.descriptorID }),
            godraysEffectIDs: Set(stages.compactMap { $0.godrays?.effectKey.descriptorID }),
            shineEffectIDs: Set(stages.compactMap { $0.shine?.effectKey.descriptorID }),
            userPropertyTextures: userPropertyTextures,
            preservedUserPropertyTextures: preservedUserPropertyTextures
        )
    }
}

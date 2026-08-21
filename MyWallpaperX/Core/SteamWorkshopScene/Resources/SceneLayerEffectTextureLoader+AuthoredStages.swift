import Metal

extension SceneLayerEffectTextureLoader {
    /// Derive per-instance resource requests only from stages that will execute.
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        stages: [SceneEffectStageExecutionPlan],
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        userPropertyTextures: [String: MTLTexture],
        userPropertyTextureStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ],
        straightAlbedoUserPropertyTextures: [String: MTLTexture],
        preservedUserPropertyTextures: [String: MTLTexture]
    ) -> SceneLayerEffectTextures {
        load(
            for: layer,
            resolver: resolver,
            loader: loader,
            device: device,
            blendEffectIDs: Set(stages.compactMap { $0.blend?.effectKey.descriptorID }),
            standardBlurEffectIDs: Set(stages.compactMap {
                $0.standardBlur?.effectDescriptorID
            }),
            waterFlowEffectIDs: Set(stages.compactMap { $0.waterFlow?.effectKey.descriptorID }),
            waterWavesEffectIDs: Set(stages.compactMap { $0.waterWaves?.effectKey.descriptorID }),
            waterCausticsPlans: stages.compactMap(\.waterCaustics),
            depthParallaxEffectIDs: Set(
                stages.compactMap { $0.depthParallax?.effectKey.descriptorID }
            ),
            cursorRippleEffectIDs: Set(
                stages.compactMap { $0.cursorRipple?.effectKey.descriptorID }
            ),
            godraysEffectIDs: Set(stages.compactMap { $0.godrays?.effectKey.descriptorID }),
            shineEffectIDs: Set(stages.compactMap { $0.shine?.effectKey.descriptorID }),
            userPropertyTextures: userPropertyTextures,
            userPropertyTextureStates: userPropertyTextureStates,
            straightAlbedoUserPropertyTextures: straightAlbedoUserPropertyTextures,
            preservedUserPropertyTextures: preservedUserPropertyTextures
        )
    }
}

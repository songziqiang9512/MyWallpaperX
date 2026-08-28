import Metal

extension SceneLayerEffectTextureLoader {
    /// Derive per-instance resource requests only from stages that will execute.
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        stages: [SceneEffectStageExecutionPlan],
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneLayerEffectTextures {
        load(
            for: layer,
            resolver: resolver,
            loader: loader,
            device: device,
            standardBlurEffectIDs: Set(stages.compactMap {
                $0.standardBlur?.effectDescriptorID
            })
        )
    }
}

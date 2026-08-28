import Metal
import simd

enum SceneLayerEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        standardBlurEffectIDs: Set<String> = []
    ) -> SceneLayerEffectTextures {
        let standardBlur = SceneStandardBlurEffectTextureLoader.load(
            for: layer,
            effectIDs: standardBlurEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        let pulseEffects = ScenePulseEffectTextureLoader.load(
            for: layer,
            resolver: resolver,
            loader: loader,
            device: device
        )
        return SceneLayerEffectTextures(
            standardBlurEffects: standardBlur.textures,
            pulseEffects: pulseEffects.textures,
            message: [
                standardBlur.message,
                pulseEffects.message,
            ].joined()
        )
    }

}

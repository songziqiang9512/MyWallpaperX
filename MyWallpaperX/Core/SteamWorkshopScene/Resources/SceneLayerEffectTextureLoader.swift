import Metal
import simd

enum SceneLayerEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        standardBlurEffectIDs: Set<String> = [],
        straightAlbedoUserPropertyTextures: [String: MTLTexture] = [:],
        preservedUserPropertyTextures: [String: MTLTexture] = [:]
    ) -> SceneLayerEffectTextures {
        let standardBlur = SceneStandardBlurEffectTextureLoader.load(
            for: layer,
            effectIDs: standardBlurEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        let xRay = SceneXRayEffectTextureLoader.load(
            for: layer,
            resolver: resolver,
            loader: loader,
            device: device,
            straightAlbedoUserPropertyTextures: straightAlbedoUserPropertyTextures,
            preservedUserPropertyTextures: preservedUserPropertyTextures
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
            xRay: xRay.textures,
            message: [
                standardBlur.message,
                pulseEffects.message,
                xRay.message,
            ].joined()
        )
    }

}

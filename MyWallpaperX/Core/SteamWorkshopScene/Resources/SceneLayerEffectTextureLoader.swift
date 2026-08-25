import Metal
import simd

enum SceneLayerEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        blendEffectIDs: Set<String> = [],
        standardBlurEffectIDs: Set<String> = [],
        userPropertyTextures: [String: MTLTexture] = [:],
        userPropertyTextureStates: [
            SceneUserPropertyTextureIdentity: SceneTextureProviderState
        ] = [:],
        straightAlbedoUserPropertyTextures: [String: MTLTexture] = [:],
        preservedUserPropertyTextures: [String: MTLTexture] = [:]
    ) -> SceneLayerEffectTextures {
        let blend = SceneBlendEffectTextureLoader.load(
            for: layer, effectIDs: blendEffectIDs, resolver: resolver, loader: loader,
            device: device,
            userPropertyTextureStates: userPropertyTextureStates
        )
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
            blendEffects: blend.textures,
            standardBlurEffects: standardBlur.textures,
            pulseEffects: pulseEffects.textures,
            xRay: xRay.textures,
            message: [
                blend.message,
                standardBlur.message,
                pulseEffects.message,
                xRay.message,
            ].joined()
        )
    }

}

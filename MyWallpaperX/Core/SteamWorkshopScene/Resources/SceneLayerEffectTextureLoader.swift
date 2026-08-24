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
        waterWavesEffectIDs: Set<String> = [],
        waterCausticsPlans: [SceneWaterCausticsExecutionPlan] = [],
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
        let waterWaves = SceneWaterWavesEffectTextureLoader.load(
            for: layer,
            effectIDs: waterWavesEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        let waterCaustics = SceneWaterCausticsEffectTextureLoader.load(
            for: layer,
            plans: waterCausticsPlans,
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
            waterWavesEffects: waterWaves.textures,
            waterCausticsEffects: waterCaustics.textures,
            pulseEffects: pulseEffects.textures,
            xRay: xRay.textures,
            message: [
                blend.message,
                standardBlur.message,
                waterWaves.message,
                waterCaustics.message,
                pulseEffects.message,
                xRay.message,
            ].joined()
        )
    }

}

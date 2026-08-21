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
        waterFlowEffectIDs: Set<String> = [],
        waterWavesEffectIDs: Set<String> = [],
        waterCausticsPlans: [SceneWaterCausticsExecutionPlan] = [],
        depthParallaxEffectIDs: Set<String> = [],
        cursorRippleEffectIDs: Set<String> = [],
        godraysEffectIDs: Set<String> = [],
        shineEffectIDs: Set<String> = [],
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
        let waterFlow = SceneWaterFlowEffectTextureLoader.load(
            for: layer,
            effectIDs: waterFlowEffectIDs,
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
        let cursorRipple = SceneCursorRippleEffectTextureLoader.load(
            for: layer,
            effectIDs: cursorRippleEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        let depthParallax = SceneDepthParallaxEffectTextureLoader.load(
            for: layer,
            effectIDs: depthParallaxEffectIDs,
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
        let godraysEffects = SceneGodraysEffectTextureLoader.load(
            for: layer,
            effectIDs: godraysEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        let shineEffects = SceneShineEffectTextureLoader.load(
            for: layer,
            effectIDs: shineEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        return SceneLayerEffectTextures(
            depthParallaxEffects: depthParallax.textures,
            blendEffects: blend.textures,
            standardBlurEffects: standardBlur.textures,
            waterFlowEffects: waterFlow.textures,
            waterWavesEffects: waterWaves.textures,
            waterCausticsEffects: waterCaustics.textures,
            cursorRippleEffects: cursorRipple.textures,
            pulseEffects: pulseEffects.textures,
            godraysEffects: godraysEffects.textures,
            shineEffects: shineEffects.textures,
            xRay: xRay.textures,
            message: [
                blend.message,
                standardBlur.message,
                waterFlow.message, waterWaves.message, cursorRipple.message,
                waterCaustics.message,
                depthParallax.message,
                pulseEffects.message, godraysEffects.message,
                shineEffects.message,
                xRay.message,
            ].joined()
        )
    }

}

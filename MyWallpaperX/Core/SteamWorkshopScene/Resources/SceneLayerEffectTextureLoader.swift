import Metal
import simd

enum SceneLayerEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        blendEffectIDs: Set<String> = [],
        shakeEffectIDs: Set<String> = [],
        filmGrainEffectIDs: Set<String> = [],
        standardBlurEffectIDs: Set<String> = [],
        lightShaftsEffectIDs: Set<String> = [],
        waterFlowEffectIDs: Set<String> = [],
        waterWavesEffectIDs: Set<String> = [],
        waterCausticsPlans: [SceneWaterCausticsExecutionPlan] = [],
        waterRippleEffectIDs: Set<String> = [],
        depthParallaxEffectIDs: Set<String> = [],
        cursorRippleEffectIDs: Set<String> = [],
        tintEffectIDs: Set<String> = [],
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
        let shake = SceneShakeEffectTextureLoader.load(
            for: layer,
            effectIDs: shakeEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        let filmGrain = SceneFilmGrainEffectTextureLoader.load(
            for: layer,
            effectIDs: filmGrainEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        let standardBlur = SceneStandardBlurEffectTextureLoader.load(
            for: layer,
            effectIDs: standardBlurEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        let lightShafts = SceneLightShaftsEffectTextureLoader.load(
            for: layer,
            effectIDs: lightShaftsEffectIDs,
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
        let waterRipple = SceneWaterRippleEffectTextureLoader.load(
            for: layer,
            effectIDs: waterRippleEffectIDs,
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
        let opacityEffects = SceneOpacityEffectTextureLoader.load(
            for: layer,
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
        let tintEffects = SceneTintEffectTextureLoader.load(
            for: layer,
            effectIDs: tintEffectIDs,
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
            waterRippleEffects: waterRipple.textures,
            depthParallaxEffects: depthParallax.textures,
            blendEffects: blend.textures,
            shakeEffects: shake.textures,
            filmGrainEffects: filmGrain.textures,
            standardBlurEffects: standardBlur.textures,
            lightShaftsEffects: lightShafts.textures,
            waterFlowEffects: waterFlow.textures,
            waterWavesEffects: waterWaves.textures,
            waterCausticsEffects: waterCaustics.textures,
            cursorRippleEffects: cursorRipple.textures,
            opacityEffects: opacityEffects.textures,
            pulseEffects: pulseEffects.textures,
            tintEffects: tintEffects.textures,
            godraysEffects: godraysEffects.textures,
            shineEffects: shineEffects.textures,
            xRay: xRay.textures,
            message: [
                blend.message, shake.message, filmGrain.message,
                standardBlur.message,
                lightShafts.message,
                waterFlow.message, waterWaves.message, cursorRipple.message,
                waterCaustics.message,
                waterRipple.message, depthParallax.message,
                opacityEffects.message,
                pulseEffects.message, tintEffects.message, godraysEffects.message,
                shineEffects.message,
                xRay.message,
            ].joined()
        )
    }

}

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
        foliageSwayEffectIDs: Set<String> = [],
        waterRippleEffectIDs: Set<String> = [],
        cursorRippleEffectIDs: Set<String> = [],
        tintEffectIDs: Set<String> = [],
        godraysEffectIDs: Set<String> = [],
        shineEffectIDs: Set<String> = [],
        userPropertyTextures: [String: MTLTexture] = [:],
        preservedUserPropertyTextures: [String: MTLTexture] = [:]
    ) -> SceneLayerEffectTextures {
        let iris = loadTexture(
            url: resolveFirstTexture(for: layer, effectFragment: "iris", resolver: resolver),
            label: "iris mask",
            purpose: .mask,
            loader: loader,
            device: device
        )
        let opacity = loadTexture(
            url: resolveFirstTexture(for: layer, effectFragment: "opacity", resolver: resolver),
            label: "opacity mask",
            purpose: .mask,
            loader: loader,
            device: device
        )
        let legacyWaterEffectFragments = waterWavesEffectIDs.isEmpty
            ? ["waterwaves", "waterripple"]
            : ["waterripple"]
        let waterURL = resolveMaskedTexture(
            for: layer,
            effectFragments: legacyWaterEffectFragments,
            resolver: resolver
        )
        let water = loadTexture(
            url: waterURL,
            label: "water mask",
            purpose: .mask,
            loader: loader,
            device: device
        )
        let foliageURL = resolveMaskedTexture(
            for: layer,
            effectFragments: ["foliagesway"],
            resolver: resolver
        )
        let foliage = loadTexture(
            url: foliageURL,
            label: "foliage mask",
            purpose: .mask,
            loader: loader,
            device: device
        )
        let normal = loadTexture(
            url: resolveTextureSlot(
                for: layer,
                effectFragment: "waterripple",
                slot: 2,
                resolver: resolver
            ),
            label: "waterripple normal",
            purpose: .normal,
            loader: loader,
            device: device
        )
        let blend = SceneBlendEffectTextureLoader.load(
            for: layer, effectIDs: blendEffectIDs, resolver: resolver, loader: loader,
            device: device, userPropertyTextures: userPropertyTextures
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
        let cursorRipple = SceneCursorRippleEffectTextureLoader.load(
            for: layer,
            effectIDs: cursorRippleEffectIDs,
            resolver: resolver,
            loader: loader,
            device: device
        )
        let foliageSway = SceneFoliageSwayEffectTextureLoader.load(
            for: layer,
            effectIDs: foliageSwayEffectIDs,
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
        let xRay = SceneXRayEffectTextureLoader.load(
            for: layer,
            resolver: resolver,
            loader: loader,
            device: device,
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
        let foliageUVScale = mappedUVScale(for: foliageURL, texture: foliage.texture)
        let foliageScaleMessage = foliage.texture == nil || foliageUVScale == SIMD2(repeating: 1)
            ? ""
            : String(
                format: "; foliage mapped UV scale=(%.6f, %.6f)",
                foliageUVScale.x,
                foliageUVScale.y
            )
        return SceneLayerEffectTextures(
            irisMask: iris.texture,
            opacityMask: opacity.texture,
            waterMask: water.texture,
            waterUVScale: mappedUVScale(for: waterURL, texture: water.texture),
            foliageMask: foliage.texture,
            foliageUVScale: foliageUVScale,
            waterRippleNormal: normal.texture,
            foliageSwayEffects: foliageSway.textures,
            waterRippleEffects: waterRipple.textures,
            blendEffects: blend.textures,
            shakeEffects: shake.textures,
            filmGrainEffects: filmGrain.textures,
            standardBlurEffects: standardBlur.textures,
            lightShaftsEffects: lightShafts.textures,
            waterFlowEffects: waterFlow.textures,
            waterWavesEffects: waterWaves.textures,
            cursorRippleEffects: cursorRipple.textures,
            opacityEffects: opacityEffects.textures,
            pulseEffects: pulseEffects.textures,
            tintEffects: tintEffects.textures,
            godraysEffects: godraysEffects.textures,
            shineEffects: shineEffects.textures,
            xRay: xRay.textures,
            message: [
                iris.message, opacity.message, water.message, foliage.message,
                foliageScaleMessage, normal.message, blend.message, shake.message, filmGrain.message,
                standardBlur.message,
                lightShafts.message,
                waterFlow.message, waterWaves.message, cursorRipple.message,
                foliageSway.message, waterRipple.message,
                opacityEffects.message,
                pulseEffects.message, tintEffects.message, godraysEffects.message,
                shineEffects.message,
                xRay.message,
            ].joined()
        )
    }

    private static func resolveFirstTexture(
        for layer: SceneRenderDescriptor.Layer,
        effectFragment: String,
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for effect in layer.effects where effect.visible != false
            && effect.file.localizedLowercase.contains(effectFragment) {
            for path in effect.passes.flatMap(\.texturePaths) {
                if let url = resolver.resolveTextureFile(named: path) { return url }
            }
        }
        return nil
    }

    private static func resolveMaskedTexture(
        for layer: SceneRenderDescriptor.Layer,
        effectFragments: [String],
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for effect in layer.effects where effect.visible != false {
            guard effectFragments.contains(where: effect.file.localizedLowercase.contains) else { continue }
            for pass in effect.passes {
                if let path = SceneEffectMaskSemantics.maskPath(in: pass),
                   let url = resolver.resolveTextureFile(named: path) {
                    return url
                }
            }
        }
        return nil
    }

    private static func resolveTextureSlot(
        for layer: SceneRenderDescriptor.Layer,
        effectFragment: String,
        slot: Int,
        resolver: SceneTexturePathResolver
    ) -> URL? {
        for effect in layer.effects where effect.visible != false
            && effect.file.localizedLowercase.contains(effectFragment) {
            for pass in effect.passes where pass.textureSlots.indices.contains(slot) {
                if let path = pass.textureSlots[slot],
                   let url = resolver.resolveTextureFile(named: path) {
                    return url
                }
            }
        }
        return nil
    }

}

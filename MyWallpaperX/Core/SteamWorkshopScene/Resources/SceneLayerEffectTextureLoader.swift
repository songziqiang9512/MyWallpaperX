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
            purpose: .preservedChannels,
            loader: loader,
            device: device
        )
        let opacity = loadTexture(
            url: resolveFirstTexture(for: layer, effectFragment: "opacity", resolver: resolver),
            label: "opacity mask",
            purpose: .preservedChannels,
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
            purpose: .preservedChannels,
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
            purpose: .preservedChannels,
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
            purpose: .preservedChannels,
            loader: loader,
            device: device
        )
        let blend = SceneBlendEffectTextureLoader.load(
            for: layer, effectIDs: blendEffectIDs, resolver: resolver, loader: loader,
            device: device, userPropertyTextures: userPropertyTextures
        )
        let shake = loadShakeEffects(
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

    private static func loadShakeEffects(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneShakeEffectTextures], message: String) {
        var textures: [String: SceneShakeEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard effect.file.replacingOccurrences(of: "\\", with: "/").lowercased()
                    == "effects/shake/effect.json",
                  effect.passes.count == 1,
                  let pass = effect.passes.first,
                  (2 ... 4).contains(pass.textureSlots.count),
                  pass.textureSlots[0] == nil,
                  let flowPath = pass.textureSlots[1] else {
                continue
            }
            // legacy 实例显式写 shader 默认 `util/white` 时按缺省处理（等价 nil，
            // 走 pipeline 内置 R8 白回退），与 planner 的归一保持一致。
            let rawPhasePath = pass.textureSlots.indices.contains(2)
                ? pass.textureSlots[2]
                : nil
            let phasePath = rawPhasePath.flatMap { path -> String? in
                path.replacingOccurrences(of: "\\", with: "/").lowercased()
                    == "util/white" ? nil : path
            }
            let maskPath = pass.textureSlots.indices.contains(3)
                ? pass.textureSlots[3]
                : nil
            let flowURL = resolver.resolveTextureFile(named: flowPath)
            let phaseURL = phasePath.flatMap(resolver.resolveTextureFile(named:))
            let maskURL = maskPath.flatMap(resolver.resolveTextureFile(named:))
            let flow = loadTexture(
                url: flowURL,
                label: "shake flow",
                purpose: .preservedChannels,
                loader: loader,
                device: device
            )
            let phase = loadTexture(
                url: phaseURL,
                label: "shake phase",
                purpose: .preservedChannels,
                loader: loader,
                device: device
            )
            let mask = loadTexture(
                url: maskURL,
                label: "shake mask",
                purpose: .preservedChannels,
                loader: loader,
                device: device
            )
            textures[effect.id] = SceneShakeEffectTextures(
                flow: flow.texture,
                phase: phase.texture,
                mask: mask.texture,
                flowUVScale: mappedUVScale(for: flowURL, texture: flow.texture),
                maskUVScale: mappedUVScale(for: maskURL, texture: mask.texture),
                flowPath: flowPath,
                phasePath: phasePath,
                maskPath: maskPath
            )
            messages.append(flowURL == nil
                ? "; shake flow missing \(flowPath)"
                : flow.message)
            if let phasePath {
                messages.append(phaseURL == nil
                    ? "; shake phase missing \(phasePath)"
                    : phase.message)
            } else {
                messages.append("; shake phase authored-white fallback")
            }
            if let maskPath {
                messages.append(maskURL == nil
                    ? "; shake mask missing \(maskPath)"
                    : mask.message)
            }
        }
        return (textures, messages.joined())
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

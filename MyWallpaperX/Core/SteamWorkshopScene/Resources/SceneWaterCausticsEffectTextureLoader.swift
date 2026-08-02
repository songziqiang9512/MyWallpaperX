import Metal
import simd

struct SceneWaterCausticsEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?
    let pattern: MTLTexture?
    let patternPath: String
    let glow: MTLTexture?
    let glowPath: String
    let noise: MTLTexture?
    let noisePath: String
    let offset: MTLTexture?
    let offsetPath: String

    func matches(_ plan: SceneWaterCausticsExecutionPlan) -> Bool {
        (plan.maskTexturePath == nil || mask != nil)
            && normalized(maskPath) == normalized(plan.maskTexturePath)
            && pattern != nil && normalized(patternPath) == normalized(plan.patternTexturePath)
            && glow != nil && normalized(glowPath) == normalized(plan.glowTexturePath)
            && noise != nil && normalized(noisePath) == normalized(plan.noiseTexturePath)
            && offset != nil && normalized(offsetPath) == normalized(plan.offsetTexturePath)
    }

    private func normalized(_ path: String?) -> String? {
        path?.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneWaterCausticsEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        plans: [SceneWaterCausticsExecutionPlan],
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        stockResolver: SceneStockTextureResolver? = SceneStockTextureResolver
            .defaultBundleRoot()
            .flatMap { SceneStockTextureResolver(bundleRoot: $0) }
    ) -> (textures: [String: SceneWaterCausticsEffectTextures], message: String) {
        var textures: [String: SceneWaterCausticsEffectTextures] = [:]
        var messages: [String] = []
        for plan in plans where plan.layerID == layer.id {
            let maskURL = plan.maskTexturePath.flatMap(resolver.resolveTextureFile(named:))
            let mask = load(
                url: maskURL, label: "water caustics mask", purpose: .mask,
                loader: loader, device: device
            )
            let pattern = loadStockOrLocal(
                plan.patternTexturePath, label: "water caustics pattern",
                resolver: resolver, stockResolver: stockResolver, loader: loader, device: device
            )
            let glow = loadStockOrLocal(
                plan.glowTexturePath, label: "water caustics glow",
                resolver: resolver, stockResolver: stockResolver, loader: loader, device: device
            )
            let noise = loadStockOrLocal(
                plan.noiseTexturePath, label: "water caustics noise",
                resolver: resolver, stockResolver: stockResolver, loader: loader, device: device
            )
            let offset = loadStockOrLocal(
                plan.offsetTexturePath, label: "water caustics offset",
                resolver: resolver, stockResolver: stockResolver, loader: loader, device: device
            )
            textures[plan.effectKey.descriptorID] = SceneWaterCausticsEffectTextures(
                mask: mask.texture,
                maskUVScale: SceneLayerEffectTextureLoader.mappedUVScale(
                    for: maskURL, texture: mask.texture
                ),
                maskPath: plan.maskTexturePath,
                pattern: pattern.texture,
                patternPath: plan.patternTexturePath,
                glow: glow.texture,
                glowPath: plan.glowTexturePath,
                noise: noise.texture,
                noisePath: plan.noiseTexturePath,
                offset: offset.texture,
                offsetPath: plan.offsetTexturePath
            )
            if plan.maskTexturePath != nil { messages.append(mask.message) }
            messages.append(contentsOf: [pattern.message, glow.message, noise.message, offset.message])
        }
        return (textures, messages.joined())
    }

    private static func loadStockOrLocal(
        _ path: String,
        label: String,
        resolver: SceneTexturePathResolver,
        stockResolver: SceneStockTextureResolver?,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneEffectTextureLoadResult {
        let url = resolver.resolveTextureFile(named: path)
            ?? stockResolver?.textureURL(for: "materials/" + path)
        return load(url: url, label: label, purpose: .noise, loader: loader, device: device)
    }

    private static func load(
        url: URL?,
        label: String,
        purpose: SceneTextureLoadPurpose,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> SceneEffectTextureLoadResult {
        SceneLayerEffectTextureLoader.loadTexture(
            url: url, label: label, purpose: purpose, loader: loader, device: device
        )
    }
}

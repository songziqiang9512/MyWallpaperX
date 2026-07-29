import Metal
import simd

struct SceneFoliageSwayEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String
    let noise: MTLTexture?
    let noisePath: String

    func matches(_ plan: SceneFoliageSwayExecutionPlan) -> Bool {
        mask != nil
            && noise != nil
            && normalized(maskPath) == normalized(plan.maskTexturePath)
            && normalized(noisePath) == normalized(plan.noiseTexturePath)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneFoliageSwayEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneFoliageSwayEffectTextures], message: String) {
        var textures: [String: SceneFoliageSwayEffectTextures] = [:]
        var messages: [String] = []
        var noiseCache: [String: MTLTexture] = [:]

        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard normalized(effect.file) == "effects/foliagesway/effect.json",
                  effect.passes.count == 1,
                  let pass = effect.passes.first,
                  let maskPath = SceneEffectMaskSemantics.maskPath(in: pass)
            else {
                continue
            }
            let noisePath = pass.textureSlots.indices.contains(2)
                ? pass.textureSlots[2] ?? SceneAuthoredFoliageSwayPlanner.noiseAssetPath
                : SceneAuthoredFoliageSwayPlanner.noiseAssetPath

            let maskURL = resolver.resolveTextureFile(named: maskPath)
            let loadedMask = SceneLayerEffectTextureLoader.loadTexture(
                url: maskURL,
                label: "foliagesway effect mask",
                purpose: .preservedChannels,
                loader: loader,
                device: device
            )
            let noiseTexture: MTLTexture?
            if let cached = noiseCache[noisePath] {
                noiseTexture = cached
            } else {
                let noiseURL = resolver.resolveTextureFile(named: noisePath)
                    ?? SceneStockTextureResolver.defaultBundleRoot()
                    .flatMap { SceneStockTextureResolver(bundleRoot: $0) }?
                    .textureURL(for: "materials/" + noisePath)
                let loadedNoise = SceneLayerEffectTextureLoader.loadTexture(
                    url: noiseURL,
                    label: "foliagesway noise",
                    purpose: .preservedChannels,
                    loader: loader,
                    device: device
                )
                noiseTexture = loadedNoise.texture
                if let texture = loadedNoise.texture {
                    noiseCache[noisePath] = texture
                }
                messages.append(noiseURL == nil
                    ? "; foliagesway noise missing \(noisePath)"
                    : loadedNoise.message)
            }
            textures[effect.id] = SceneFoliageSwayEffectTextures(
                mask: loadedMask.texture,
                maskUVScale: SceneLayerEffectTextureLoader.mappedUVScale(
                    for: maskURL,
                    texture: loadedMask.texture
                ),
                maskPath: maskPath,
                noise: noiseTexture,
                noisePath: noisePath
            )
            messages.append(maskURL == nil
                ? "; foliagesway effect mask missing \(maskPath)"
                : loadedMask.message)
        }
        return (textures, messages.joined())
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

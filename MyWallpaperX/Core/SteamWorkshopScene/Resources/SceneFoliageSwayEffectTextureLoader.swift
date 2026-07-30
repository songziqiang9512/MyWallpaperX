import Metal
import simd

struct SceneFoliageSwayEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?
    let noise: MTLTexture?
    let noisePath: String

    func matches(_ plan: SceneFoliageSwayExecutionPlan) -> Bool {
        noise != nil
            && maskMatches(plan.maskTexturePath)
            && normalized(noisePath) == normalized(plan.noiseTexturePath)
    }

    private func maskMatches(_ planPath: String?) -> Bool {
        guard let planPath else { return mask == nil && maskPath == nil }
        guard let maskPath else { return false }
        return mask != nil && normalized(maskPath) == normalized(planPath)
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
                  let pass = effect.passes.first
            else {
                continue
            }
            let maskPath = SceneEffectMaskSemantics.maskPath(in: pass)
            let noisePath = pass.textureSlots.indices.contains(2)
                ? pass.textureSlots[2] ?? SceneAuthoredFoliageSwayPlanner.noiseAssetPath
                : SceneAuthoredFoliageSwayPlanner.noiseAssetPath

            let maskURL = maskPath.flatMap(resolver.resolveTextureFile)
            var maskTexture: MTLTexture?
            var maskMessage = ""
            if maskPath != nil {
                let loadedMask = SceneLayerEffectTextureLoader.loadTexture(
                    url: maskURL,
                    label: "foliagesway effect mask",
                    purpose: .preservedChannels,
                    loader: loader,
                    device: device
                )
                maskTexture = loadedMask.texture
                maskMessage = loadedMask.message
            }
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
                mask: maskTexture,
                maskUVScale: maskPath == nil
                    ? .zero
                    : SceneLayerEffectTextureLoader.mappedUVScale(
                        for: maskURL,
                        texture: maskTexture
                    ),
                maskPath: maskPath,
                noise: noiseTexture,
                noisePath: noisePath
            )
            if let maskPath {
                messages.append(maskURL == nil
                    ? "; foliagesway effect mask missing \(maskPath)"
                    : maskMessage)
            }
        }
        return (textures, messages.joined())
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

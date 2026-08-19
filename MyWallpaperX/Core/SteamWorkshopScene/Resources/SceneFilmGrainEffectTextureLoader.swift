import Metal

struct SceneFilmGrainEffectTextures {
    let noise: MTLTexture?
    let noisePath: String

    func matches(_ plan: SceneFilmGrainExecutionPlan) -> Bool {
        noise != nil && normalized(noisePath) == normalized(plan.noiseTexturePath)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

/// Film Grain omits shader-default `util/noise` from the instance pass.
/// Resolve a sample-local override first, then the stock bundle asset.
enum SceneFilmGrainEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        stockResolver: SceneStockTextureResolver? = SceneStockTextureResolver
            .defaultBundleRoot()
            .flatMap { SceneStockTextureResolver(bundleRoot: $0) }
    ) -> (textures: [String: SceneFilmGrainEffectTextures], message: String) {
        guard !effectIDs.isEmpty else { return ([:], "") }
        let noisePath = SceneAuthoredFilmGrainPlanner.noiseTexturePath
        let noiseURL = resolver.resolveTextureFile(named: noisePath)
            ?? stockResolver?.textureURL(for: "materials/" + noisePath)
        let loaded = SceneLayerEffectTextureLoader.loadTexture(
            url: noiseURL,
            label: "film grain noise",
            purpose: .noise,
            loader: loader,
            device: device
        )
        let pairs: [(String, SceneFilmGrainEffectTextures)] = layer.effects.compactMap { effect in
            guard effectIDs.contains(effect.id),
                  effect.file.replacingOccurrences(of: "\\", with: "/").lowercased()
                    == "effects/filmgrain/effect.json" else {
                return nil
            }
            return (effect.id, SceneFilmGrainEffectTextures(
                noise: loaded.texture,
                noisePath: noisePath
            ))
        }
        let textures = Dictionary(uniqueKeysWithValues: pairs)
        let message = noiseURL == nil
            ? "; film grain noise missing \(noisePath)"
            : loaded.message
        return (textures, message)
    }
}

import Metal

struct SceneLightShaftsEffectTextures {
    let noise: MTLTexture?
    let gradient: MTLTexture?
    let noisePath: String
    let gradientPath: String

    func matches(_ plan: SceneLightShaftsExecutionPlan) -> Bool {
        noise != nil
            && gradient != nil
            && normalized(noisePath) == normalized(plan.noiseTexturePath)
            && normalized(gradientPath) == normalized(plan.gradientTexturePath)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

/// Light Shafts omits its shader-default textures from the authored pass.
/// A project-local asset wins; the project-owned stock bundle is the fallback.
enum SceneLightShaftsEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        stockResolver: SceneStockTextureResolver? = SceneStockTextureResolver
            .defaultBundleRoot()
            .flatMap { SceneStockTextureResolver(bundleRoot: $0) }
    ) -> (textures: [String: SceneLightShaftsEffectTextures], message: String) {
        guard !effectIDs.isEmpty else { return ([:], "") }
        let noisePath = SceneAuthoredLightShaftsPlanner.noiseTexturePath
        let gradientPath = SceneAuthoredLightShaftsPlanner.gradientTexturePath
        let noiseURL = resolver.resolveTextureFile(named: noisePath)
            ?? stockResolver?.textureURL(for: noisePath)
        let gradientURL = resolver.resolveTextureFile(named: gradientPath)
            ?? stockResolver?.textureURL(for: gradientPath)
        let noise = SceneLayerEffectTextureLoader.loadTexture(
            url: noiseURL,
            label: "light shafts noise",
            purpose: .preservedChannels,
            loader: loader,
            device: device
        )
        let gradient = SceneLayerEffectTextureLoader.loadTexture(
            url: gradientURL,
            label: "light shafts gradient",
            purpose: .preservedChannels,
            loader: loader,
            device: device
        )
        let pairs: [(String, SceneLightShaftsEffectTextures)] = layer.effects.compactMap {
            effect in
            guard effectIDs.contains(effect.id),
                  normalized(effect.file) == "effects/lightshafts/effect.json" else {
                return nil
            }
            return (
                effect.id,
                .init(
                    noise: noise.texture,
                    gradient: gradient.texture,
                    noisePath: noisePath,
                    gradientPath: gradientPath
                )
            )
        }
        var messages = [noise.message, gradient.message]
        if noiseURL == nil { messages.append("; light shafts noise missing \(noisePath)") }
        if gradientURL == nil {
            messages.append("; light shafts gradient missing \(gradientPath)")
        }
        return (Dictionary(uniqueKeysWithValues: pairs), messages.joined())
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

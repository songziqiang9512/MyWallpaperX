import Metal
import simd

struct SceneStandardBlurEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskSampling: SceneTextureSampling
    let maskPath: String

    func matches(_ plan: SceneStandardBlurPlan) -> Bool {
        mask != nil
            && normalized(maskPath) == plan.maskTexturePath.map(normalized)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneStandardBlurEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneStandardBlurEffectTextures], message: String) {
        var textures: [String: SceneStandardBlurEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard normalized(effect.file) == "effects/blur/effect.json",
                  effect.passes.count == 4,
                  let combinePass = effect.passes.last,
                  let maskPath = SceneEffectMaskSemantics.maskPath(in: combinePass) else {
                continue
            }
            let maskURL = resolver.resolveTextureFile(named: maskPath)
            let loaded = SceneLayerEffectTextureLoader.loadTexture(
                url: maskURL,
                label: "standard blur mask",
                purpose: .preservedChannels,
                loader: loader,
                device: device
            )
            textures[effect.id] = SceneStandardBlurEffectTextures(
                mask: loaded.texture,
                maskUVScale: loaded.mappedUVScale,
                maskSampling: loaded.sampling,
                maskPath: maskPath
            )
            messages.append(maskURL == nil
                ? "; standard blur mask missing \(maskPath)"
                : loaded.message)
        }
        return (textures, messages.joined())
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

import Metal
import simd

struct SceneGodraysEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?
    /// `util/clouds_256` 噪声（NOISE=1 恒需要）；加载失败时 matches 拒绝。
    let noise: MTLTexture?

    func matches(_ plan: SceneGodraysPlan) -> Bool {
        guard noise != nil else { return false }
        guard let planPath = plan.maskTexturePath else { return maskPath == nil }
        return mask != nil && maskPath.map(normalized) == normalized(planPath)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

/// godrays pass 0 的遮罩挂在 effect 实例上，按 descriptorID 分开存；
/// `util/clouds_256` 是 stock 资产（样本包通常不携带），同层多实例共享一次加载。
enum SceneGodraysEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneGodraysEffectTextures], message: String) {
        var textures: [String: SceneGodraysEffectTextures] = [:]
        var messages: [String] = []
        var sharedNoise: MTLTexture?
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard effect.file.replacingOccurrences(of: "\\", with: "/").lowercased()
                == "effects/godrays/effect.json",
                effect.passes.count == 5,
                let pass = effect.passes.first
            else {
                continue
            }
            if sharedNoise == nil {
                let noiseURL = resolver.resolveTextureFile(
                    named: SceneAuthoredGodraysPlanner.noiseAssetPath
                ) ?? SceneStockTextureResolver.defaultBundleRoot()
                    .flatMap { SceneStockTextureResolver(bundleRoot: $0) }?
                    .textureURL(
                        for: "materials/" + SceneAuthoredGodraysPlanner.noiseAssetPath
                    )
                let loaded = SceneLayerEffectTextureLoader.loadTexture(
                    url: noiseURL,
                    label: "godrays noise",
                    purpose: .noise,
                    loader: loader,
                    device: device
                )
                sharedNoise = loaded.texture
                messages.append(noiseURL == nil
                    ? "; godrays noise missing \(SceneAuthoredGodraysPlanner.noiseAssetPath)"
                    : loaded.message)
            }
            let maskPath = pass.textureSlots.indices.contains(1)
                ? pass.textureSlots[1]
                : nil
            var maskTexture: MTLTexture?
            var maskUVScale = SIMD2<Float>(repeating: 1)
            if let maskPath {
                let maskURL = resolver.resolveTextureFile(named: maskPath)
                let loaded = SceneLayerEffectTextureLoader.loadTexture(
                    url: maskURL,
                    label: "godrays effect mask",
                    purpose: .mask,
                    loader: loader,
                    device: device
                )
                maskTexture = loaded.texture
                maskUVScale = SceneLayerEffectTextureLoader.mappedUVScale(
                    for: maskURL,
                    texture: loaded.texture
                )
                messages.append(maskURL == nil
                    ? "; godrays effect mask missing \(maskPath)"
                    : loaded.message)
            }
            textures[effect.id] = SceneGodraysEffectTextures(
                mask: maskTexture,
                maskUVScale: maskUVScale,
                maskPath: maskPath,
                noise: sharedNoise
            )
        }
        return (textures, messages.joined())
    }
}

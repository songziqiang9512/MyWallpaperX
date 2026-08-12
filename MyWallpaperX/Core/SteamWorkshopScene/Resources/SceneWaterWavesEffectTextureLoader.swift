import Metal
import simd

struct SceneWaterWavesEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    /// nil 表示 v1 实例未绑遮罩（等价 mask=1）。
    let maskPath: String?

    func matches(_ plan: SceneWaterWavesExecutionPlan) -> Bool {
        guard let planPath = plan.maskTexturePath else { return maskPath == nil }
        return mask != nil && maskPath.map(normalized) == normalized(planPath)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneWaterWavesEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneWaterWavesEffectTextures], message: String) {
        var textures: [String: SceneWaterWavesEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard SceneWaterWavesAssetFamily(definitionPath: effect.file) != nil,
                effect.passes.count == 1,
                let pass = effect.passes.first
            else {
                continue
            }
            // v1 profile 允许未绑遮罩（等价 mask=1），也要建 entry 供 renderer 命中。
            guard let maskPath = SceneEffectMaskSemantics.maskPath(in: pass) else {
                textures[effect.id] = SceneWaterWavesEffectTextures(
                    mask: nil,
                    maskUVScale: SIMD2(repeating: 1),
                    maskPath: nil
                )
                continue
            }
            // v1 shader 声明的 default `util/white` 是 stock 资产，样本包通常不携带。
            let maskURL = resolver.resolveTextureFile(named: maskPath)
                ?? SceneStockTextureResolver.defaultBundleRoot()
                .flatMap { SceneStockTextureResolver(bundleRoot: $0) }?
                .textureURL(for: "materials/" + maskPath)
            let loaded = SceneLayerEffectTextureLoader.loadTexture(
                url: maskURL,
                label: "waterwaves mask",
                purpose: .mask,
                loader: loader,
                device: device
            )
            textures[effect.id] = SceneWaterWavesEffectTextures(
                mask: loaded.texture,
                maskUVScale: SceneLayerEffectTextureLoader.mappedUVScale(
                    for: maskURL,
                    texture: loaded.texture
                ),
                maskPath: maskPath
            )
            messages.append(maskURL == nil
                ? "; waterwaves mask missing \(maskPath)"
                : loaded.message)
        }
        return (textures, messages.joined())
    }
}

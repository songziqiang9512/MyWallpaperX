import Metal
import simd

struct ScenePulseEffectTextures {
    let noise: MTLTexture?
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?

    func matches(_ plan: ScenePulseExecutionPlan) -> Bool {
        let maskSatisfied = plan.maskTexturePath.map { path in
            mask != nil && normalized(maskPath ?? "") == normalized(path)
        } ?? true
        let noiseSatisfied = !plan.requiresNoiseTexture || noise != nil
        return maskSatisfied && noiseSatisfied
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

/// 官方 pulse.frag 的 `g_Texture1` 默认 `util/noise`（stock 资产，样本包通常不携带），
/// `g_Texture2` 遮罩挂在 effect 实例上，与 Opacity 同理按 descriptorID 分开存。
/// noise 先查样本包（作者可自带同名资产），缺失再读 `SceneStockAssets.bundle`；
/// 同层多个 pulse 实例共享同一次 noise 加载。
enum ScenePulseEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        stockResolver: SceneStockTextureResolver? = SceneStockTextureResolver
            .defaultBundleRoot()
            .flatMap { SceneStockTextureResolver(bundleRoot: $0) }
    ) -> (textures: [String: ScenePulseEffectTextures], message: String) {
        var textures: [String: ScenePulseEffectTextures] = [:]
        var messages: [String] = []
        var sharedNoise: MTLTexture?
        for effect in layer.effects where effect.visible != false {
            guard effect.file.replacingOccurrences(of: "\\", with: "/").lowercased()
                == "effects/pulse/effect.json",
                effect.passes.count == 1,
                let pass = effect.passes.first
            else {
                continue
            }
            if sharedNoise == nil {
                let noiseURL = resolver.resolveTextureFile(
                    named: SceneAuthoredPulsePlanner.noiseAssetPath
                ) ?? stockResolver?.textureURL(
                    for: "materials/" + SceneAuthoredPulsePlanner.noiseAssetPath
                )
                let loaded = SceneLayerEffectTextureLoader.loadTexture(
                    url: noiseURL,
                    label: "pulse noise",
                    purpose: .preservedChannels,
                    loader: loader,
                    device: device
                )
                sharedNoise = loaded.texture
                messages.append(noiseURL == nil
                    ? "; pulse noise missing \(SceneAuthoredPulsePlanner.noiseAssetPath)"
                    : loaded.message)
            }
            let maskPath = pass.textureSlots.indices.contains(2)
                ? pass.textureSlots[2]
                : nil
            var maskTexture: MTLTexture?
            var maskUVScale = SIMD2<Float>(repeating: 1)
            if let maskPath {
                let maskURL = resolver.resolveTextureFile(named: maskPath)
                let loaded = SceneLayerEffectTextureLoader.loadTexture(
                    url: maskURL,
                    label: "pulse effect mask",
                    purpose: .preservedChannels,
                    loader: loader,
                    device: device
                )
                maskTexture = loaded.texture
                maskUVScale = SceneLayerEffectTextureLoader.mappedUVScale(
                    for: maskURL,
                    texture: loaded.texture
                )
                messages.append(maskURL == nil
                    ? "; pulse effect mask missing \(maskPath)"
                    : loaded.message)
            }
            textures[effect.id] = ScenePulseEffectTextures(
                noise: sharedNoise,
                mask: maskTexture,
                maskUVScale: maskUVScale,
                maskPath: maskPath
            )
        }
        return (textures, messages.joined())
    }
}

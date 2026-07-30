import Metal
import simd

struct SceneOpacityEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String

    func matches(_ plan: SceneOpacityExecutionPlan) -> Bool {
        mask != nil && normalized(maskPath) == plan.maskTexturePath.map(normalized)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

/// 官方 `opacity.frag` 在 MASK 分支下是 `albedo.a *= mask * g_UserAlpha`，遮罩属于 effect
/// 实例而不是 layer：去重语料（52 包 / 54 份 scene.json）里 78 个绑遮罩的 layer 有 30 个在
/// 同一层挂了多个 stock opacity，各自绑不同的遮罩图，因此不能沿用 per-layer 的
/// `opacityMasks`，必须按 descriptorID 分开存。
enum SceneOpacityEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneOpacityEffectTextures], message: String) {
        var textures: [String: SceneOpacityEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effect.visible != false {
            guard effect.file.replacingOccurrences(of: "\\", with: "/").lowercased()
                == "effects/opacity/effect.json",
                effect.passes.count == 1,
                let pass = effect.passes.first,
                let maskPath = SceneEffectMaskSemantics.maskPath(in: pass)
            else {
                continue
            }
            let maskURL = resolver.resolveTextureFile(named: maskPath)
            let loaded = SceneLayerEffectTextureLoader.loadTexture(
                url: maskURL,
                label: "opacity effect mask",
                purpose: .mask,
                loader: loader,
                device: device
            )
            textures[effect.id] = SceneOpacityEffectTextures(
                mask: loaded.texture,
                maskUVScale: SceneLayerEffectTextureLoader.mappedUVScale(
                    for: maskURL,
                    texture: loaded.texture
                ),
                maskPath: maskPath
            )
            messages.append(maskURL == nil
                ? "; opacity effect mask missing \(maskPath)"
                : loaded.message)
        }
        return (textures, messages.joined())
    }
}

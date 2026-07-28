import Metal
import simd

struct SceneCursorRippleEffectTextures {
    let mask: MTLTexture?
    let maskUVScale: SIMD2<Float>
    let maskPath: String?

    func matches(_ plan: SceneCursorRippleExecutionPlan) -> Bool {
        guard let expected = plan.maskTexturePath else { return maskPath == nil }
        return mask != nil
            && maskPath.map(normalized) == normalized(expected)
            && maskUVScale.x > 0
            && maskUVScale.y > 0
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneCursorRippleEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneCursorRippleEffectTextures], message: String) {
        var textures: [String: SceneCursorRippleEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard normalized(effect.file) == "effects/cursorripple/effect.json",
                  effect.passes.count == 3 else {
                continue
            }
            let pass = effect.passes[1]
            guard pass.passIndex == 1 else { continue }
            guard let maskPath = SceneEffectMaskSemantics.maskPath(in: pass) else {
                textures[effect.id] = SceneCursorRippleEffectTextures(
                    mask: nil,
                    maskUVScale: SIMD2(repeating: 1),
                    maskPath: nil
                )
                continue
            }
            let maskURL = resolver.resolveTextureFile(named: maskPath)
            let loaded = SceneLayerEffectTextureLoader.loadTexture(
                url: maskURL,
                label: "cursor ripple collision mask",
                loader: loader,
                device: device
            )
            textures[effect.id] = SceneCursorRippleEffectTextures(
                mask: loaded.texture,
                maskUVScale: SceneLayerEffectTextureLoader.mappedUVScale(
                    for: maskURL,
                    texture: loaded.texture
                ),
                maskPath: maskPath
            )
            messages.append(maskURL == nil
                ? "; cursor ripple collision mask missing \(maskPath)"
                : loaded.message)
        }
        return (textures, messages.joined())
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

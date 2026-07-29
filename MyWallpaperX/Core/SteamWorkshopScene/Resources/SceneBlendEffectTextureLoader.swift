import Metal
import simd

struct SceneBlendEffectTextures {
    let texture: MTLTexture
    let uvScale: SIMD2<Float>
    let assetPath: String
    let propertyKey: String?

    func matches(_ plan: SceneBlendExecutionPlan) -> Bool {
        normalized(assetPath) == normalized(plan.assetTexturePath)
            && propertyKey == plan.userPropertyKey
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneBlendEffectTextureLoader {
    private struct Selection {
        let assetPath: String
        let propertyKey: String?
    }

    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice,
        userPropertyTextures: [String: MTLTexture]
    ) -> (textures: [String: SceneBlendEffectTextures], message: String) {
        var textures: [String: SceneBlendEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard effect.visible != false,
                  normalized(effect.file) == definitionPath,
                  effect.passes.count == 1,
                  let pass = effect.passes.first,
                  pass.passIndex == 0,
                  let selection = selection(from: pass) else {
                continue
            }

            if let propertyKey = selection.propertyKey,
               let propertyTexture = userPropertyTextures[propertyKey] {
                textures[effect.id] = SceneBlendEffectTextures(
                    texture: propertyTexture,
                    uvScale: SIMD2(repeating: 1),
                    assetPath: selection.assetPath,
                    propertyKey: propertyKey
                )
                messages.append("; blend property texture OK \(propertyKey)")
                continue
            }

            let assetURL = resolver.resolveTextureFile(named: selection.assetPath)
            let loaded = SceneLayerEffectTextureLoader.loadTexture(
                url: assetURL,
                label: "blend effect texture",
                purpose: .premultipliedColor,
                loader: loader,
                device: device
            )
            guard let texture = loaded.texture else {
                messages.append(assetURL == nil
                    ? "; blend effect texture missing \(selection.assetPath)"
                    : loaded.message)
                continue
            }
            textures[effect.id] = SceneBlendEffectTextures(
                texture: texture,
                uvScale: SceneLayerEffectTextureLoader.mappedUVScale(
                    for: assetURL,
                    texture: texture
                ),
                assetPath: selection.assetPath,
                propertyKey: selection.propertyKey
            )
            messages.append(loaded.message)
        }
        return (textures, messages.joined())
    }

    private static func selection(
        from pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Selection? {
        guard pass.textureSlots.count == 2,
              pass.textureSlots[0] == nil,
              let assetPath = pass.textureSlots[1],
              !assetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pass.texturePaths == [assetPath] else {
            return nil
        }
        if pass.userTextureInputs.isEmpty {
            return Selection(assetPath: assetPath, propertyKey: nil)
        }
        guard pass.userTextureInputs.count == 2,
              pass.userTextureInputs[0] == nil,
              let input = pass.userTextureInputs[1],
              input.kind == .property,
              !input.value.isEmpty else {
            return nil
        }
        return Selection(assetPath: assetPath, propertyKey: input.value)
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static let definitionPath = "effects/blend/effect.json"
}

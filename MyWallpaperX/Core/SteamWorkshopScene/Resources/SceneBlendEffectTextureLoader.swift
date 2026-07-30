import Metal
import simd

struct SceneBlendEffectTextures {
    struct ResolvedArguments {
        let blend: SceneTextureSlotBinding
        let uvScale: SIMD2<Float>
    }

    let blendBinding: SceneTextureSlotBinding?
    let assetPath: String
    let propertyKey: String?

    func resolvedArguments(
        for plan: SceneBlendExecutionPlan
    ) -> ResolvedArguments? {
        guard normalized(assetPath) == normalized(plan.assetTexturePath),
              propertyKey == plan.userPropertyKey,
              let blendBinding,
              let uvScale = blendBinding.axisAlignedUVScale(
                  expectedSlotIndex: 1,
                  expectedPurpose: .premultipliedColor,
                  allowedPixelFormats: [.rgba8Unorm, .bgra8Unorm]
              ) else {
            return nil
        }
        return ResolvedArguments(blend: blendBinding, uvScale: uvScale)
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
        userPropertyTextureCandidates: [String: SceneTextureCandidate]
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

            let assetURL = resolver.resolveTextureFile(named: selection.assetPath)
            let loaded = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: assetURL,
                label: "blend effect texture",
                purpose: .premultipliedColor,
                loader: loader,
                device: device
            )
            let propertyCandidate = selection.propertyKey.flatMap {
                userPropertyTextureCandidates[$0]
            }
            guard let binding = SceneTextureSlotBinding.resolveFinalCandidate(
                slotIndex: 1,
                candidates: [loaded.candidate, propertyCandidate]
            ) else {
                messages.append(assetURL == nil
                    ? "; blend effect texture missing \(selection.assetPath)"
                    : loaded.message)
                continue
            }
            textures[effect.id] = SceneBlendEffectTextures(
                blendBinding: binding,
                assetPath: selection.assetPath,
                propertyKey: selection.propertyKey
            )
            if let propertyKey = selection.propertyKey,
               propertyCandidate?.texture === binding.texture {
                messages.append("; blend property texture OK \(propertyKey)")
            } else {
                messages.append(loaded.message)
            }
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

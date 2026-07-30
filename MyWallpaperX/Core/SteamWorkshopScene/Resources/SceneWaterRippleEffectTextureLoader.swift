import Metal
import simd

struct SceneWaterRippleEffectTextures {
    struct ResolvedArguments {
        let mask: SceneTextureSlotBinding
        let normal: SceneTextureSlotBinding
        let maskUVScale: SIMD2<Float>
    }

    let maskBinding: SceneTextureSlotBinding?
    let maskPath: String
    let normalBinding: SceneTextureSlotBinding?
    let normalPath: String

    func resolvedArguments(
        for plan: SceneWaterRippleExecutionPlan
    ) -> ResolvedArguments? {
        guard normalized(maskPath) == normalized(plan.maskTexturePath),
              normalized(normalPath) == normalized(plan.normalTexturePath),
              let maskBinding,
              let maskUVScale = maskBinding.axisAlignedUVScale(
                  expectedSlotIndex: 1,
                  expectedPurpose: .mask,
                  allowedPixelFormats: [
                      .r8Unorm, .rg8Unorm, .rgba8Unorm, .bgra8Unorm,
                  ]
              ),
              let normalBinding,
              normalBinding.axisAlignedUVScale(
                  expectedSlotIndex: 2,
                  expectedPurpose: .normal,
                  allowedPixelFormats: [.rgba8Unorm, .bgra8Unorm],
                  requiresIdentityUV: true
              ) != nil else {
            return nil
        }
        return ResolvedArguments(
            mask: maskBinding,
            normal: normalBinding,
            maskUVScale: maskUVScale
        )
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneWaterRippleEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneWaterRippleEffectTextures], message: String) {
        var textures: [String: SceneWaterRippleEffectTextures] = [:]
        var messages: [String] = []
        var normalCache: [String: SceneTextureSlotBinding] = [:]

        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard normalized(effect.file) == "effects/waterripple/effect.json",
                  effect.passes.count == 1,
                  let pass = effect.passes.first,
                  pass.textureSlots.count == 3,
                  let maskPath = pass.textureSlots[1],
                  let normalPath = pass.textureSlots[2]
            else {
                continue
            }
            let maskURL = resolver.resolveTextureFile(named: maskPath)
            let loadedMask = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: maskURL,
                label: "waterripple effect mask",
                purpose: .mask,
                loader: loader,
                device: device
            )
            let maskBinding = loadedMask.candidate.flatMap {
                SceneTextureSlotBinding(slotIndex: 1, candidate: $0)
            }
            let normalBinding: SceneTextureSlotBinding?
            if let cached = normalCache[normalPath] {
                normalBinding = cached
            } else {
                let normalURL = resolver.resolveTextureFile(named: normalPath)
                    ?? SceneStockTextureResolver.defaultBundleRoot()
                    .flatMap { SceneStockTextureResolver(bundleRoot: $0) }?
                    .textureURL(for: "materials/" + normalPath)
                let loadedNormal = SceneLayerEffectTextureLoader.loadTextureCandidate(
                    url: normalURL,
                    label: "waterripple effect normal",
                    purpose: .normal,
                    loader: loader,
                    device: device
                )
                normalBinding = loadedNormal.candidate.flatMap {
                    SceneTextureSlotBinding(slotIndex: 2, candidate: $0)
                }
                if let normalBinding {
                    normalCache[normalPath] = normalBinding
                }
                messages.append(normalURL == nil
                    ? "; waterripple normal missing \(normalPath)"
                    : loadedNormal.message)
            }
            textures[effect.id] = SceneWaterRippleEffectTextures(
                maskBinding: maskBinding,
                maskPath: maskPath,
                normalBinding: normalBinding,
                normalPath: normalPath
            )
            messages.append(maskURL == nil
                ? "; waterripple effect mask missing \(maskPath)"
                : loadedMask.message)
        }
        return (textures, messages.joined())
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

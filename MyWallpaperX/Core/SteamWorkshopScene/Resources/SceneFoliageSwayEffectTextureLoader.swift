import Metal
import simd

struct SceneFoliageSwayEffectTextures {
    struct ResolvedArguments {
        let mask: SceneTextureSlotBinding?
        let noise: SceneTextureSlotBinding
        let maskUVScale: SIMD2<Float>
    }

    let maskBinding: SceneTextureSlotBinding?
    let maskPath: String?
    let noiseBinding: SceneTextureSlotBinding?
    let noisePath: String

    func resolvedArguments(
        for plan: SceneFoliageSwayExecutionPlan
    ) -> ResolvedArguments? {
        guard normalized(maskPath) == normalized(plan.maskTexturePath),
              normalized(noisePath) == normalized(plan.noiseTexturePath),
              let noiseBinding,
              noiseBinding.axisAlignedUVScale(
                  expectedSlotIndex: 2,
                  expectedPurpose: .noise,
                  allowedPixelFormats: [
                      .rg8Unorm, .rgba8Unorm, .bgra8Unorm,
                  ],
                  requiresIdentityUV: true
              ) != nil else {
            return nil
        }

        let maskUVScale: SIMD2<Float>
        if plan.maskTexturePath == nil {
            guard maskBinding == nil else { return nil }
            maskUVScale = SIMD2(repeating: 1)
        } else {
            guard let maskBinding,
                  let scale = maskBinding.axisAlignedUVScale(
                      expectedSlotIndex: 1,
                      expectedPurpose: .mask,
                      allowedPixelFormats: [
                          .r8Unorm, .rg8Unorm, .rgba8Unorm, .bgra8Unorm,
                      ]
                  ) else {
                return nil
            }
            maskUVScale = scale
        }
        return ResolvedArguments(
            mask: maskBinding,
            noise: noiseBinding,
            maskUVScale: maskUVScale
        )
    }

    private func normalized(_ path: String?) -> String? {
        path?.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneFoliageSwayEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneFoliageSwayEffectTextures], message: String) {
        var textures: [String: SceneFoliageSwayEffectTextures] = [:]
        var messages: [String] = []
        var noiseCache: [String: SceneTextureSlotBinding] = [:]

        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard normalized(effect.file) == "effects/foliagesway/effect.json",
                  effect.passes.count == 1,
                  let pass = effect.passes.first
            else {
                continue
            }
            let maskPath = SceneEffectMaskSemantics.maskPath(in: pass)
            let noisePath = pass.textureSlots.indices.contains(2)
                ? pass.textureSlots[2] ?? SceneAuthoredFoliageSwayPlanner.noiseAssetPath
                : SceneAuthoredFoliageSwayPlanner.noiseAssetPath

            let maskURL = maskPath.flatMap(resolver.resolveTextureFile)
            var maskBinding: SceneTextureSlotBinding?
            var maskMessage = ""
            if maskPath != nil {
                let loadedMask = SceneLayerEffectTextureLoader.loadTextureCandidate(
                    url: maskURL,
                    label: "foliagesway effect mask",
                    purpose: .mask,
                    loader: loader,
                    device: device
                )
                maskBinding = loadedMask.candidate.flatMap {
                    SceneTextureSlotBinding(slotIndex: 1, candidate: $0)
                }
                maskMessage = loadedMask.message
            }
            let noiseBinding: SceneTextureSlotBinding?
            if let cached = noiseCache[noisePath] {
                noiseBinding = cached
            } else {
                let noiseURL = resolver.resolveTextureFile(named: noisePath)
                    ?? SceneStockTextureResolver.defaultBundleRoot()
                    .flatMap { SceneStockTextureResolver(bundleRoot: $0) }?
                    .textureURL(for: "materials/" + noisePath)
                let loadedNoise = SceneLayerEffectTextureLoader.loadTextureCandidate(
                    url: noiseURL,
                    label: "foliagesway noise",
                    purpose: .noise,
                    loader: loader,
                    device: device
                )
                noiseBinding = loadedNoise.candidate.flatMap {
                    SceneTextureSlotBinding(slotIndex: 2, candidate: $0)
                }
                if let noiseBinding {
                    noiseCache[noisePath] = noiseBinding
                }
                messages.append(noiseURL == nil
                    ? "; foliagesway noise missing \(noisePath)"
                    : loadedNoise.message)
            }
            textures[effect.id] = SceneFoliageSwayEffectTextures(
                maskBinding: maskBinding,
                maskPath: maskPath,
                noiseBinding: noiseBinding,
                noisePath: noisePath
            )
            if let maskPath {
                messages.append(maskURL == nil
                    ? "; foliagesway effect mask missing \(maskPath)"
                    : maskMessage)
            }
        }
        return (textures, messages.joined())
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

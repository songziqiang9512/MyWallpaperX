import Metal
import simd

struct SceneDepthParallaxEffectTextures {
    struct ResolvedArguments {
        let depth: SceneTextureSlotBinding
        let depthUVScale: SIMD2<Float>
    }

    let depthBinding: SceneTextureSlotBinding?
    let depthPath: String

    func resolvedArguments(
        for plan: SceneDepthParallaxExecutionPlan
    ) -> ResolvedArguments? {
        guard normalized(depthPath) == normalized(plan.depthTexturePath),
              let depthBinding,
              let depthUVScale = depthBinding.axisAlignedUVScale(
                  expectedSlotIndex: 1,
                  expectedPurpose: .depth,
                  allowedPixelFormats: [.r8Unorm]
              ) else {
            return nil
        }
        return ResolvedArguments(
            depth: depthBinding,
            depthUVScale: depthUVScale
        )
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneDepthParallaxEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneDepthParallaxEffectTextures], message: String) {
        var textures: [String: SceneDepthParallaxEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard normalized(effect.file) == "effects/depthparallax/effect.json",
                  effect.passes.count == 1,
                  let pass = effect.passes.first,
                  pass.textureSlots.count == 2,
                  let depthPath = pass.textureSlots[1] else {
                continue
            }
            let depthURL = resolver.resolveTextureFile(named: depthPath)
            let loaded = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: depthURL,
                label: "depthparallax depth",
                purpose: .depth,
                loader: loader,
                device: device
            )
            let binding = loaded.candidate.flatMap {
                SceneTextureSlotBinding(slotIndex: 1, candidate: $0)
            }
            textures[effect.id] = SceneDepthParallaxEffectTextures(
                depthBinding: binding,
                depthPath: depthPath
            )
            messages.append(
                depthURL == nil
                    ? "; depthparallax depth missing \(depthPath)"
                    : loaded.message
            )
        }
        return (textures, messages.joined())
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

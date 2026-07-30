import Metal
import simd

struct SceneShakeEffectTextures {
    struct ResolvedArguments {
        let flow: SceneTextureSlotBinding
        let phase: SceneTextureSlotBinding?
        let mask: SceneTextureSlotBinding?
        let flowUVScale: SIMD2<Float>
        let maskUVScale: SIMD2<Float>
    }

    let flowBinding: SceneTextureSlotBinding?
    let phaseBinding: SceneTextureSlotBinding?
    let maskBinding: SceneTextureSlotBinding?
    let flowPath: String
    let phasePath: String?
    let maskPath: String?

    func resolvedArguments(
        for plan: SceneShakeExecutionPlan
    ) -> ResolvedArguments? {
        guard normalized(flowPath) == normalized(plan.flowTexturePath),
              normalized(phasePath) == normalized(plan.phaseTexturePath),
              normalized(maskPath) == normalized(plan.maskTexturePath),
              let flowBinding,
              let flowUVScale = flowBinding.axisAlignedUVScale(
                  expectedSlotIndex: 1,
                  expectedPurpose: .flow,
                  allowedPixelFormats: [.rg8Unorm, .rgba8Unorm, .bgra8Unorm]
              ) else {
            return nil
        }

        if plan.phaseTexturePath == nil {
            guard phaseBinding == nil else { return nil }
        } else {
            guard let phaseBinding,
                  let phaseUVScale = phaseBinding.axisAlignedUVScale(
                      expectedSlotIndex: 2,
                      expectedPurpose: .phase,
                      allowedPixelFormats: [.r8Unorm]
                  ),
                  near(phaseUVScale, flowUVScale) else {
                return nil
            }
        }

        let maskUVScale: SIMD2<Float>
        if plan.maskTexturePath == nil {
            guard maskBinding == nil else { return nil }
            maskUVScale = SIMD2(repeating: 1)
        } else {
            guard let maskBinding,
                  let scale = maskBinding.axisAlignedUVScale(
                      expectedSlotIndex: 3,
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
            flow: flowBinding,
            phase: phaseBinding,
            mask: maskBinding,
            flowUVScale: flowUVScale,
            maskUVScale: maskUVScale
        )
    }

    private func normalized(_ path: String?) -> String? {
        path?.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private func near(_ lhs: SIMD2<Float>, _ rhs: SIMD2<Float>) -> Bool {
        abs(lhs.x - rhs.x) <= 0.000_001
            && abs(lhs.y - rhs.y) <= 0.000_001
    }
}

enum SceneShakeEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneShakeEffectTextures], message: String) {
        var textures: [String: SceneShakeEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard normalized(effect.file) == "effects/shake/effect.json",
                  effect.passes.count == 1,
                  let pass = effect.passes.first,
                  (2 ... 4).contains(pass.textureSlots.count),
                  pass.textureSlots[0] == nil,
                  let flowPath = pass.textureSlots[1] else {
                continue
            }
            let phasePath = normalizedPhasePath(
                pass.textureSlots.indices.contains(2)
                    ? pass.textureSlots[2]
                    : nil
            )
            let maskPath = pass.textureSlots.indices.contains(3)
                ? pass.textureSlots[3]
                : nil
            let flowURL = resolver.resolveTextureFile(named: flowPath)
            let phaseURL = phasePath.flatMap(resolver.resolveTextureFile(named:))
            let maskURL = maskPath.flatMap(resolver.resolveTextureFile(named:))
            let flow = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: flowURL,
                label: "shake flow",
                purpose: .flow,
                loader: loader,
                device: device
            )
            let phase = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: phaseURL,
                label: "shake phase",
                purpose: .phase,
                loader: loader,
                device: device
            )
            let mask = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: maskURL,
                label: "shake mask",
                purpose: .mask,
                loader: loader,
                device: device
            )
            textures[effect.id] = SceneShakeEffectTextures(
                flowBinding: flow.candidate.flatMap {
                    SceneTextureSlotBinding(slotIndex: 1, candidate: $0)
                },
                phaseBinding: phase.candidate.flatMap {
                    SceneTextureSlotBinding(slotIndex: 2, candidate: $0)
                },
                maskBinding: mask.candidate.flatMap {
                    SceneTextureSlotBinding(slotIndex: 3, candidate: $0)
                },
                flowPath: flowPath,
                phasePath: phasePath,
                maskPath: maskPath
            )
            messages.append(flowURL == nil
                ? "; shake flow missing \(flowPath)"
                : flow.message)
            if let phasePath {
                messages.append(phaseURL == nil
                    ? "; shake phase missing \(phasePath)"
                    : phase.message)
            } else {
                messages.append("; shake phase authored-white fallback")
            }
            if let maskPath {
                messages.append(maskURL == nil
                    ? "; shake mask missing \(maskPath)"
                    : mask.message)
            }
        }
        return (textures, messages.joined())
    }

    private static func normalizedPhasePath(_ path: String?) -> String? {
        guard let path else { return nil }
        return normalized(path) == "util/white" ? nil : path
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

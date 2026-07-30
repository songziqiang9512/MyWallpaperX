import CoreGraphics
import Metal
import simd

struct SceneWaterFlowEffectTextures {
    let flowCandidate: SceneTextureCandidate?
    let phaseCandidate: SceneTextureCandidate?
    let flowPath: String
    let phasePath: String

    func matches(_ plan: SceneWaterFlowExecutionPlan) -> Bool {
        guard let flowCandidate,
              let phaseCandidate,
              flowCandidate.axisAlignedMappedUVScale(expectedPurpose: .flow) != nil,
              let phaseUVScale = phaseCandidate.axisAlignedMappedUVScale(
                  expectedPurpose: .phase
              ),
              phaseUVScale == SIMD2(repeating: 1) else {
            return false
        }
        return flowCandidate.texture.width > 0
            && phaseCandidate.texture.width > 0
            && normalized(flowPath) == normalized(plan.flowTexturePath)
            && normalized(phasePath) == normalized(plan.phaseTexturePath)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneWaterFlowEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneWaterFlowEffectTextures], message: String) {
        var textures: [String: SceneWaterFlowEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard effect.file.replacingOccurrences(of: "\\", with: "/").lowercased()
                    == "effects/waterflow/effect.json",
                  effect.passes.count == 1,
                  let pass = effect.passes.first,
                  pass.textureSlots.count == 3,
                  let flowPath = pass.textureSlots[1],
                  let phasePath = pass.textureSlots[2] else {
                continue
            }
            let flowURL = resolver.resolveTextureFile(named: flowPath)
            let phaseURL = resolver.resolveTextureFile(named: phasePath)
            let flow = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: flowURL,
                label: "waterflow flow",
                purpose: .flow,
                loader: loader,
                device: device
            )
            let phase = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: phaseURL,
                label: "waterflow phase",
                purpose: .phase,
                loader: loader,
                device: device
            )
            let builtInPhase = phaseURL == nil
                ? SceneWaterFlowBuiltInPhaseTexture.make(path: phasePath, device: device)
                : nil
            let builtInPhaseCandidate = builtInPhase.map {
                SceneTextureCandidate(
                    texture: $0,
                    identity: .builtIn(name: phasePath),
                    generation: .immutable(revision: 1),
                    purpose: .phase,
                    physicalSize: CGSize(width: $0.width, height: $0.height),
                    mappedSize: CGSize(width: $0.width, height: $0.height),
                    uvTransform: .identity,
                    sampling: .linearClamp
                )
            }
            textures[effect.id] = SceneWaterFlowEffectTextures(
                flowCandidate: flow.candidate,
                phaseCandidate: phase.candidate ?? builtInPhaseCandidate,
                flowPath: flowPath,
                phasePath: phasePath
            )
            messages.append(flowURL == nil
                ? "; waterflow flow missing \(flowPath)"
                : flow.message)
            messages.append(phaseURL == nil
                ? builtInPhase.map {
                    "; waterflow phase built-in \(phasePath) → \($0.width)×\($0.height)"
                } ?? "; waterflow phase missing \(phasePath)"
                : phase.message)
        }
        return (textures, messages.joined())
    }
}

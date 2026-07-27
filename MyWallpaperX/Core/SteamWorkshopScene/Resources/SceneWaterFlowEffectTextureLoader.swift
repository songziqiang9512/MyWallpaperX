import Metal
import simd

struct SceneWaterFlowEffectTextures {
    let flow: MTLTexture?
    let phase: MTLTexture?
    let flowUVScale: SIMD2<Float>
    let flowPath: String
    let phasePath: String

    func matches(_ plan: SceneWaterFlowExecutionPlan) -> Bool {
        flow != nil
            && phase != nil
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
            let flow = SceneLayerEffectTextureLoader.loadTexture(
                url: flowURL,
                label: "waterflow flow",
                loader: loader,
                device: device
            )
            let phase = SceneLayerEffectTextureLoader.loadTexture(
                url: phaseURL,
                label: "waterflow phase",
                loader: loader,
                device: device
            )
            let builtInPhase = phaseURL == nil
                ? SceneWaterFlowBuiltInPhaseTexture.make(path: phasePath, device: device)
                : nil
            textures[effect.id] = SceneWaterFlowEffectTextures(
                flow: flow.texture,
                phase: phase.texture ?? builtInPhase,
                flowUVScale: SceneLayerEffectTextureLoader.mappedUVScale(
                    for: flowURL,
                    texture: flow.texture
                ),
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

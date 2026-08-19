import Foundation
import Metal
import simd

struct SceneTintEffectTextures {
    let binding: SceneEffectTextureBinding

    var mask: MTLTexture? { binding.texture }
    var maskUVScale: SIMD2<Float> { binding.mappedUVScale }
    var maskPath: String? { binding.path }
    var state: SceneEffectTextureBinding.State { binding.state }
    var generation: SceneTextureResourceGeneration? { binding.generation }

    func matches(_ plan: SceneTintExecutionPlan) -> Bool {
        binding.purpose == .mask
            && binding.matches(path: plan.maskTexturePath)
            && mask === binding.texture
    }
}

/// 官方 tint.frag 的遮罩挂在 effect 实例的槽位 1 上，与 Opacity 同理按 descriptorID
/// 分开存；同一层可以有多个 tint 各绑不同遮罩。声明了遮罩却取不到贴图时渲染层
/// 整段拒绝，不静默降级成无遮罩。
enum SceneTintEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneTintEffectTextures], message: String) {
        var textures: [String: SceneTintEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            // `effectIDs` only contains stages accepted by SceneAuthoredTintPlanner. Do not
            // reclassify the asset by a stock path here; only revalidate the exact instance
            // pass shape before loading its optional mask.
            guard effect.passes.count == 1,
                let pass = effect.passes.first,
                pass.passIndex == 0,
                pass.userTextureInputs.isEmpty
            else {
                continue
            }
            if pass.texturePaths.isEmpty && pass.textureSlots.isEmpty {
                textures[effect.id] = SceneTintEffectTextures(
                    binding: .absent(purpose: .mask)
                )
                continue
            }
            guard pass.textureSlots.count == 2,
                  pass.textureSlots[0] == nil,
                  let maskPath = pass.textureSlots[1],
                  !maskPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  pass.texturePaths == [maskPath] else {
                continue
            }
            let maskURL = resolver.resolveTextureFile(named: maskPath)
            let loaded = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: maskURL,
                label: "tint effect mask",
                purpose: .mask,
                loader: loader,
                device: device
            )
            textures[effect.id] = SceneTintEffectTextures(
                binding: SceneEffectTextureBinding(
                    path: maskPath,
                    purpose: .mask,
                    loadResult: loaded
                )
            )
            messages.append(maskURL == nil
                ? "; tint effect mask missing \(maskPath)"
                : loaded.message)
        }
        return (textures, messages.joined())
    }
}

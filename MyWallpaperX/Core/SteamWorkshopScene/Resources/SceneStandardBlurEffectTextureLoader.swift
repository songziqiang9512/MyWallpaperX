import Metal
import simd

struct SceneStandardBlurEffectTextures {
    let maskCandidate: SceneTextureCandidate?
    let maskPath: String

    func matches(_ plan: SceneStandardBlurPlan) -> Bool {
        maskCandidate?.axisAlignedMappedUVScale(expectedPurpose: .mask) != nil
            && normalized(maskPath) == plan.maskTexturePath.map(normalized)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

enum SceneStandardBlurEffectTextureLoader {
    static func load(
        for layer: SceneRenderDescriptor.Layer,
        effectIDs: Set<String>,
        resolver: SceneTexturePathResolver,
        loader: SceneTextureLoader,
        device: MTLDevice
    ) -> (textures: [String: SceneStandardBlurEffectTextures], message: String) {
        var textures: [String: SceneStandardBlurEffectTextures] = [:]
        var messages: [String] = []
        for effect in layer.effects where effectIDs.contains(effect.id) {
            guard normalized(effect.file) == "effects/blur/effect.json",
                  effect.passes.count == 4,
                  let combinePass = effect.passes.last,
                  let maskPath = SceneEffectMaskSemantics.maskPath(in: combinePass) else {
                continue
            }
            let maskURL = resolver.resolveTextureFile(named: maskPath)
            let loaded = SceneLayerEffectTextureLoader.loadTextureCandidate(
                url: maskURL,
                label: "standard blur mask",
                purpose: .mask,
                loader: loader,
                device: device
            )
            textures[effect.id] = SceneStandardBlurEffectTextures(
                maskCandidate: loaded.candidate,
                maskPath: maskPath
            )
            messages.append(maskURL == nil
                ? "; standard blur mask missing \(maskPath)"
                : loaded.message)
        }
        return (textures, messages.joined())
    }

    private static func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

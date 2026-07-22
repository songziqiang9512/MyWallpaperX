import Foundation

enum SceneEffectMaskSemantics {
    nonisolated static func declaresMask(
        in effect: SceneRenderDescriptor.EffectDescriptor
    ) -> Bool {
        effect.passes.contains { declaresMask(in: $0) }
    }

    nonisolated static func declaresMask(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Bool {
        maskPath(in: pass) != nil || combo("MASK", in: pass) == 1
    }

    nonisolated static func maskPath(
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> String? {
        guard pass.textureSlots.indices.contains(1) else { return nil }
        return pass.textureSlots[1]
    }

    private nonisolated static func combo(
        _ name: String,
        in pass: SceneRenderDescriptor.EffectDescriptor.PassDescriptor
    ) -> Int? {
        pass.combos.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

import Foundation

enum SceneInlineEffectRuntime {
    static func flags(
        for layer: SceneRenderDescriptor.Layer,
        usesNormalWaterRipple: Bool,
        hasWaterMask: Bool,
        hasFoliageMask: Bool
    ) -> SceneEffectFlags {
        var flags: SceneEffectFlags = []
        for effect in layer.effects where effect.visible != false {
            let path = effect.file.localizedLowercase
            if path.contains("foliagesway") && canRunMaskedEffect(effect, maskAvailable: hasFoliageMask) {
                flags.insert(.foliagesway)
            }
            if path.contains("waterwaves")
                || (path.contains("waterripple") && !usesNormalWaterRipple),
               canRunMaskedEffect(effect, maskAvailable: hasWaterMask) {
                flags.insert(.waterwaves)
            }
            if path.contains("cursorripple") && canRunMaskedEffect(effect, maskAvailable: hasFoliageMask) {
                flags.insert(.cursorripple)
            }
            if path.contains("chromaticaberration") {
                flags.insert(.chromaticaberration)
            }
        }
        return flags
    }

    private static func canRunMaskedEffect(
        _ effect: SceneRenderDescriptor.EffectDescriptor,
        maskAvailable: Bool
    ) -> Bool {
        !SceneEffectMaskSemantics.declaresMask(in: effect) || maskAvailable
    }

    static func summary(
        for layer: SceneRenderDescriptor.Layer,
        hasWaterMask: Bool
    ) -> String? {
        let count = layer.effects.filter {
            $0.visible != false
                && $0.file.localizedLowercase.contains("waterwaves")
                && canRunMaskedEffect($0, maskAvailable: hasWaterMask)
        }.count
        guard count > 0 else { return nil }
        return "effect runtime waterwaves-legacy; \(count) visible declaration(s)"
    }
}

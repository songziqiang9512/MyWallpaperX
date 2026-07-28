import Foundation

enum SceneInlineEffectRuntime {
    static func flags(
        for layer: SceneRenderDescriptor.Layer,
        usesNormalWaterRipple: Bool,
        hasWaterMask: Bool,
        hasFoliageMask: Bool,
        handlesWaterWaves: Bool = false
    ) -> SceneEffectFlags {
        var flags: SceneEffectFlags = []
        if !handlesWaterWaves,
           legacyWaterWavesEffect(for: layer, hasWaterMask: hasWaterMask) != nil {
            flags.insert(.waterwaves)
        }
        for effect in layer.effects where effect.visible != false {
            let path = effect.file.localizedLowercase
            if path.contains("foliagesway") && canRunMaskedEffect(effect, maskAvailable: hasFoliageMask) {
                flags.insert(.foliagesway)
            }
            if path.contains("waterripple") && !usesNormalWaterRipple,
               canRunMaskedEffect(effect, maskAvailable: hasWaterMask) {
                flags.insert(.waterwaves)
            }
            if SceneEffectRuntimeSupport.isChromaticAberration(path) {
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
        hasWaterMask: Bool,
        handlesWaterWaves: Bool = false
    ) -> String? {
        guard !handlesWaterWaves else { return nil }
        guard legacyWaterWavesEffect(for: layer, hasWaterMask: hasWaterMask) != nil else {
            return nil
        }
        return "effect runtime waterwaves-legacy; 1 visible declaration(s)"
    }

    private static func legacyWaterWavesEffect(
        for layer: SceneRenderDescriptor.Layer,
        hasWaterMask: Bool
    ) -> SceneRenderDescriptor.EffectDescriptor? {
        let visibleEffects = layer.effects.filter { $0.visible != false }
        guard visibleEffects.count == 1,
              let effect = visibleEffects.first,
              effect.file.localizedLowercase.contains("waterwaves"),
              canRunMaskedEffect(effect, maskAvailable: hasWaterMask) else {
            return nil
        }
        return effect
    }
}

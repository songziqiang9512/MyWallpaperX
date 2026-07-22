import Foundation

enum SceneInlineEffectRuntime {
    static func flags(
        for layer: SceneRenderDescriptor.Layer,
        usesNormalWaterRipple: Bool
    ) -> SceneEffectFlags {
        var flags: SceneEffectFlags = []
        for effect in layer.effects where effect.visible != false {
            let path = effect.file.localizedLowercase
            if path.contains("foliagesway") {
                flags.insert(.foliagesway)
            }
            if path.contains("waterwaves")
                || (path.contains("waterripple") && !usesNormalWaterRipple) {
                flags.insert(.waterwaves)
            }
            if path.contains("cursorripple") {
                flags.insert(.cursorripple)
            }
            if path.contains("chromaticaberration") {
                flags.insert(.chromaticaberration)
            }
        }
        return flags
    }

    static func summary(for layer: SceneRenderDescriptor.Layer) -> String? {
        let count = layer.effects.filter {
            $0.visible != false && $0.file.localizedLowercase.contains("waterwaves")
        }.count
        guard count > 0 else { return nil }
        return "effect runtime waterwaves-legacy; \(count) visible declaration(s)"
    }
}

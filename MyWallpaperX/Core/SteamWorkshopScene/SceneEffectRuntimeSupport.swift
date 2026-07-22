import Foundation

enum SceneEffectRuntimeSupport {
    nonisolated static func supportsUtilityCapture(
        _ effect: SceneRenderDescriptor.EffectDescriptor
    ) -> Bool {
        let path = effect.file.localizedLowercase
        if path.contains("/blur/effect.json")
            || path.contains("/blurprecise/")
            || path.contains("bloom")
            || path.contains("chromaticaberration") {
            return true
        }
        if path.contains("foliagesway")
            || path.contains("waterwaves")
            || path.contains("waterripple") {
            return !SceneEffectMaskSemantics.declaresMask(in: effect)
        }
        return false
    }
}

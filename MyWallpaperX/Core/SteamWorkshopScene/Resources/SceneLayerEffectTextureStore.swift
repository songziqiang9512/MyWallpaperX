import Metal
import simd

struct SceneLayerEffectTextures {
    let standardBlurEffects: [String: SceneStandardBlurEffectTextures]
    let pulseEffects: [String: ScenePulseEffectTextures]
    let message: String
}

struct SceneLayerEffectTextureStore {
    var standardBlurEffects: [String: SceneStandardBlurEffectTextures] = [:]
    var pulseEffects: [String: ScenePulseEffectTextures] = [:]

    mutating func merge(layerID: Int, textures: SceneLayerEffectTextures) {
        standardBlurEffects.merge(textures.standardBlurEffects) { _, incoming in incoming }
        pulseEffects.merge(textures.pulseEffects) { _, incoming in incoming }
    }
}

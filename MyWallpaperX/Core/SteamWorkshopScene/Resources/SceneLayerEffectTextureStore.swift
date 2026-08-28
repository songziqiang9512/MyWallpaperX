import Metal
import simd

struct SceneLayerEffectTextures {
    let standardBlurEffects: [String: SceneStandardBlurEffectTextures]
    let message: String
}

struct SceneLayerEffectTextureStore {
    var standardBlurEffects: [String: SceneStandardBlurEffectTextures] = [:]

    mutating func merge(layerID: Int, textures: SceneLayerEffectTextures) {
        standardBlurEffects.merge(textures.standardBlurEffects) { _, incoming in incoming }
    }
}

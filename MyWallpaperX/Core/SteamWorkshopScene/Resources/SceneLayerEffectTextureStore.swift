import Metal
import simd

struct SceneLayerEffectTextures {
    let standardBlurEffects: [String: SceneStandardBlurEffectTextures]
    let pulseEffects: [String: ScenePulseEffectTextures]
    let xRay: SceneXRayEffectTextures?
    let message: String
}

struct SceneLayerEffectTextureStore {
    var standardBlurEffects: [String: SceneStandardBlurEffectTextures] = [:]
    var pulseEffects: [String: ScenePulseEffectTextures] = [:]
    var xRayEffects: [Int: SceneXRayEffectTextures] = [:]

    mutating func merge(layerID: Int, textures: SceneLayerEffectTextures) {
        standardBlurEffects.merge(textures.standardBlurEffects) { _, incoming in incoming }
        pulseEffects.merge(textures.pulseEffects) { _, incoming in incoming }
        xRayEffects[layerID] = textures.xRay
    }
}

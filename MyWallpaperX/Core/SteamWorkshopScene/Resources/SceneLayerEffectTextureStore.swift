import Metal
import simd

struct SceneLayerEffectTextures {
    let blendEffects: [String: SceneBlendEffectTextures]
    let standardBlurEffects: [String: SceneStandardBlurEffectTextures]
    let pulseEffects: [String: ScenePulseEffectTextures]
    let xRay: SceneXRayEffectTextures?
    let message: String
}

struct SceneLayerEffectTextureStore {
    var blendEffects: [String: SceneBlendEffectTextures] = [:]
    var standardBlurEffects: [String: SceneStandardBlurEffectTextures] = [:]
    var pulseEffects: [String: ScenePulseEffectTextures] = [:]
    var xRayEffects: [Int: SceneXRayEffectTextures] = [:]

    mutating func merge(layerID: Int, textures: SceneLayerEffectTextures) {
        blendEffects.merge(textures.blendEffects) { _, incoming in incoming }
        standardBlurEffects.merge(textures.standardBlurEffects) { _, incoming in incoming }
        pulseEffects.merge(textures.pulseEffects) { _, incoming in incoming }
        xRayEffects[layerID] = textures.xRay
    }
}

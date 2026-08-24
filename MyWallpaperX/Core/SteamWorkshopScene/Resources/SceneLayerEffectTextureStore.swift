import Metal
import simd

struct SceneLayerEffectTextures {
    let blendEffects: [String: SceneBlendEffectTextures]
    let standardBlurEffects: [String: SceneStandardBlurEffectTextures]
    let waterWavesEffects: [String: SceneWaterWavesEffectTextures]
    let waterCausticsEffects: [String: SceneWaterCausticsEffectTextures]
    let pulseEffects: [String: ScenePulseEffectTextures]
    let godraysEffects: [String: SceneGodraysEffectTextures]
    let shineEffects: [String: SceneShineEffectTextures]
    let xRay: SceneXRayEffectTextures?
    let message: String
}

struct SceneLayerEffectTextureStore {
    var blendEffects: [String: SceneBlendEffectTextures] = [:]
    var standardBlurEffects: [String: SceneStandardBlurEffectTextures] = [:]
    var waterWavesEffects: [String: SceneWaterWavesEffectTextures] = [:]
    var waterCausticsEffects: [String: SceneWaterCausticsEffectTextures] = [:]
    var pulseEffects: [String: ScenePulseEffectTextures] = [:]
    var godraysEffects: [String: SceneGodraysEffectTextures] = [:]
    var shineEffects: [String: SceneShineEffectTextures] = [:]
    var xRayEffects: [Int: SceneXRayEffectTextures] = [:]

    mutating func merge(layerID: Int, textures: SceneLayerEffectTextures) {
        blendEffects.merge(textures.blendEffects) { _, incoming in incoming }
        standardBlurEffects.merge(textures.standardBlurEffects) { _, incoming in incoming }
        waterWavesEffects.merge(textures.waterWavesEffects) { _, incoming in incoming }
        waterCausticsEffects.merge(textures.waterCausticsEffects) { _, incoming in incoming }
        pulseEffects.merge(textures.pulseEffects) { _, incoming in incoming }
        godraysEffects.merge(textures.godraysEffects) { _, incoming in incoming }
        shineEffects.merge(textures.shineEffects) { _, incoming in incoming }
        xRayEffects[layerID] = textures.xRay
    }
}

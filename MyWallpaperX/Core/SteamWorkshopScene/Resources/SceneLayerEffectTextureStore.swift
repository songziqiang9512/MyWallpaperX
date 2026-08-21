import Metal
import simd

struct SceneLayerEffectTextures {
    let waterRippleEffects: [String: SceneWaterRippleEffectTextures]
    let depthParallaxEffects: [String: SceneDepthParallaxEffectTextures]
    let blendEffects: [String: SceneBlendEffectTextures]
    let standardBlurEffects: [String: SceneStandardBlurEffectTextures]
    let waterFlowEffects: [String: SceneWaterFlowEffectTextures]
    let waterWavesEffects: [String: SceneWaterWavesEffectTextures]
    let waterCausticsEffects: [String: SceneWaterCausticsEffectTextures]
    let cursorRippleEffects: [String: SceneCursorRippleEffectTextures]
    let pulseEffects: [String: ScenePulseEffectTextures]
    let godraysEffects: [String: SceneGodraysEffectTextures]
    let shineEffects: [String: SceneShineEffectTextures]
    let xRay: SceneXRayEffectTextures?
    let message: String
}

struct SceneLayerEffectTextureStore {
    var waterRippleEffects: [String: SceneWaterRippleEffectTextures] = [:]
    var depthParallaxEffects: [String: SceneDepthParallaxEffectTextures] = [:]
    var blendEffects: [String: SceneBlendEffectTextures] = [:]
    var standardBlurEffects: [String: SceneStandardBlurEffectTextures] = [:]
    var waterFlowEffects: [String: SceneWaterFlowEffectTextures] = [:]
    var waterWavesEffects: [String: SceneWaterWavesEffectTextures] = [:]
    var waterCausticsEffects: [String: SceneWaterCausticsEffectTextures] = [:]
    var cursorRippleEffects: [String: SceneCursorRippleEffectTextures] = [:]
    var pulseEffects: [String: ScenePulseEffectTextures] = [:]
    var godraysEffects: [String: SceneGodraysEffectTextures] = [:]
    var shineEffects: [String: SceneShineEffectTextures] = [:]
    var xRayEffects: [Int: SceneXRayEffectTextures] = [:]

    mutating func merge(layerID: Int, textures: SceneLayerEffectTextures) {
        waterRippleEffects.merge(textures.waterRippleEffects) { _, incoming in incoming }
        depthParallaxEffects.merge(textures.depthParallaxEffects) { _, incoming in
            incoming
        }
        blendEffects.merge(textures.blendEffects) { _, incoming in incoming }
        standardBlurEffects.merge(textures.standardBlurEffects) { _, incoming in incoming }
        waterFlowEffects.merge(textures.waterFlowEffects) { _, incoming in incoming }
        waterWavesEffects.merge(textures.waterWavesEffects) { _, incoming in incoming }
        waterCausticsEffects.merge(textures.waterCausticsEffects) { _, incoming in incoming }
        cursorRippleEffects.merge(textures.cursorRippleEffects) { _, incoming in incoming }
        pulseEffects.merge(textures.pulseEffects) { _, incoming in incoming }
        godraysEffects.merge(textures.godraysEffects) { _, incoming in incoming }
        shineEffects.merge(textures.shineEffects) { _, incoming in incoming }
        xRayEffects[layerID] = textures.xRay
    }
}

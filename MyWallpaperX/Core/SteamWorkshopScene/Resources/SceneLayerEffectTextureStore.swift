import Metal
import simd

struct SceneLayerEffectTextures {
    let waterRippleEffects: [String: SceneWaterRippleEffectTextures]
    let depthParallaxEffects: [String: SceneDepthParallaxEffectTextures]
    let blendEffects: [String: SceneBlendEffectTextures]
    let shakeEffects: [String: SceneShakeEffectTextures]
    let standardBlurEffects: [String: SceneStandardBlurEffectTextures]
    let lightShaftsEffects: [String: SceneLightShaftsEffectTextures]
    let waterFlowEffects: [String: SceneWaterFlowEffectTextures]
    let waterWavesEffects: [String: SceneWaterWavesEffectTextures]
    let waterCausticsEffects: [String: SceneWaterCausticsEffectTextures]
    let cursorRippleEffects: [String: SceneCursorRippleEffectTextures]
    let opacityEffects: [String: SceneOpacityEffectTextures]
    let pulseEffects: [String: ScenePulseEffectTextures]
    let tintEffects: [String: SceneTintEffectTextures]
    let godraysEffects: [String: SceneGodraysEffectTextures]
    let shineEffects: [String: SceneShineEffectTextures]
    let xRay: SceneXRayEffectTextures?
    let message: String
}

struct SceneLayerEffectTextureStore {
    var waterRippleEffects: [String: SceneWaterRippleEffectTextures] = [:]
    var depthParallaxEffects: [String: SceneDepthParallaxEffectTextures] = [:]
    var blendEffects: [String: SceneBlendEffectTextures] = [:]
    var shakeEffects: [String: SceneShakeEffectTextures] = [:]
    var standardBlurEffects: [String: SceneStandardBlurEffectTextures] = [:]
    var lightShaftsEffects: [String: SceneLightShaftsEffectTextures] = [:]
    var waterFlowEffects: [String: SceneWaterFlowEffectTextures] = [:]
    var waterWavesEffects: [String: SceneWaterWavesEffectTextures] = [:]
    var waterCausticsEffects: [String: SceneWaterCausticsEffectTextures] = [:]
    var cursorRippleEffects: [String: SceneCursorRippleEffectTextures] = [:]
    var opacityEffects: [String: SceneOpacityEffectTextures] = [:]
    var pulseEffects: [String: ScenePulseEffectTextures] = [:]
    var tintEffects: [String: SceneTintEffectTextures] = [:]
    var godraysEffects: [String: SceneGodraysEffectTextures] = [:]
    var shineEffects: [String: SceneShineEffectTextures] = [:]
    var xRayEffects: [Int: SceneXRayEffectTextures] = [:]

    mutating func merge(layerID: Int, textures: SceneLayerEffectTextures) {
        waterRippleEffects.merge(textures.waterRippleEffects) { _, incoming in incoming }
        depthParallaxEffects.merge(textures.depthParallaxEffects) { _, incoming in
            incoming
        }
        blendEffects.merge(textures.blendEffects) { _, incoming in incoming }
        shakeEffects.merge(textures.shakeEffects) { _, incoming in incoming }
        standardBlurEffects.merge(textures.standardBlurEffects) { _, incoming in incoming }
        lightShaftsEffects.merge(textures.lightShaftsEffects) { _, incoming in incoming }
        waterFlowEffects.merge(textures.waterFlowEffects) { _, incoming in incoming }
        waterWavesEffects.merge(textures.waterWavesEffects) { _, incoming in incoming }
        waterCausticsEffects.merge(textures.waterCausticsEffects) { _, incoming in incoming }
        cursorRippleEffects.merge(textures.cursorRippleEffects) { _, incoming in incoming }
        opacityEffects.merge(textures.opacityEffects) { _, incoming in incoming }
        pulseEffects.merge(textures.pulseEffects) { _, incoming in incoming }
        tintEffects.merge(textures.tintEffects) { _, incoming in incoming }
        godraysEffects.merge(textures.godraysEffects) { _, incoming in incoming }
        shineEffects.merge(textures.shineEffects) { _, incoming in incoming }
        xRayEffects[layerID] = textures.xRay
    }
}

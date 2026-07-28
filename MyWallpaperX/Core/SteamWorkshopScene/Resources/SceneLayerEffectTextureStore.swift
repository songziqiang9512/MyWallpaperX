import Metal
import simd

struct SceneShakeEffectTextures {
    let flow: MTLTexture?
    let phase: MTLTexture?
    let flowUVScale: SIMD2<Float>
    let flowPath: String
    let phasePath: String?

    func matches(_ plan: SceneShakeExecutionPlan) -> Bool {
        flow != nil
            && normalized(flowPath) == normalized(plan.flowTexturePath)
            && normalized(phasePath) == normalized(plan.phaseTexturePath)
            && (plan.phaseTexturePath == nil || phase != nil)
    }

    private func normalized(_ path: String?) -> String? {
        path?.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

struct SceneLayerEffectTextures {
    let irisMask: MTLTexture?
    let opacityMask: MTLTexture?
    let waterMask: MTLTexture?
    let waterUVScale: SIMD2<Float>
    let foliageMask: MTLTexture?
    let foliageUVScale: SIMD2<Float>
    let waterRippleNormal: MTLTexture?
    let blendEffects: [String: SceneBlendEffectTextures]
    let shakeEffects: [String: SceneShakeEffectTextures]
    let filmGrainEffects: [String: SceneFilmGrainEffectTextures]
    let lightShaftsEffects: [String: SceneLightShaftsEffectTextures]
    let waterFlowEffects: [String: SceneWaterFlowEffectTextures]
    let waterWavesEffects: [String: SceneWaterWavesEffectTextures]
    let cursorRippleEffects: [String: SceneCursorRippleEffectTextures]
    let opacityEffects: [String: SceneOpacityEffectTextures]
    let pulseEffects: [String: ScenePulseEffectTextures]
    let tintEffects: [String: SceneTintEffectTextures]
    let godraysEffects: [String: SceneGodraysEffectTextures]
    let xRay: SceneXRayEffectTextures?
    let message: String
}

struct SceneLayerEffectTextureStore {
    var irisMasks: [Int: MTLTexture] = [:]
    var opacityMasks: [Int: MTLTexture] = [:]
    var waterMasks: [Int: MTLTexture] = [:]
    var waterUVScales: [Int: SIMD2<Float>] = [:]
    var foliageMasks: [Int: MTLTexture] = [:]
    var foliageUVScales: [Int: SIMD2<Float>] = [:]
    var waterRippleNormals: [Int: MTLTexture] = [:]
    var blendEffects: [String: SceneBlendEffectTextures] = [:]
    var shakeEffects: [String: SceneShakeEffectTextures] = [:]
    var filmGrainEffects: [String: SceneFilmGrainEffectTextures] = [:]
    var lightShaftsEffects: [String: SceneLightShaftsEffectTextures] = [:]
    var waterFlowEffects: [String: SceneWaterFlowEffectTextures] = [:]
    var waterWavesEffects: [String: SceneWaterWavesEffectTextures] = [:]
    var cursorRippleEffects: [String: SceneCursorRippleEffectTextures] = [:]
    var opacityEffects: [String: SceneOpacityEffectTextures] = [:]
    var pulseEffects: [String: ScenePulseEffectTextures] = [:]
    var tintEffects: [String: SceneTintEffectTextures] = [:]
    var godraysEffects: [String: SceneGodraysEffectTextures] = [:]
    var xRayEffects: [Int: SceneXRayEffectTextures] = [:]

    mutating func merge(layerID: Int, textures: SceneLayerEffectTextures) {
        irisMasks[layerID] = textures.irisMask
        opacityMasks[layerID] = textures.opacityMask
        waterMasks[layerID] = textures.waterMask
        waterUVScales[layerID] = textures.waterUVScale
        foliageMasks[layerID] = textures.foliageMask
        foliageUVScales[layerID] = textures.foliageUVScale
        waterRippleNormals[layerID] = textures.waterRippleNormal
        blendEffects.merge(textures.blendEffects) { _, incoming in incoming }
        shakeEffects.merge(textures.shakeEffects) { _, incoming in incoming }
        filmGrainEffects.merge(textures.filmGrainEffects) { _, incoming in incoming }
        lightShaftsEffects.merge(textures.lightShaftsEffects) { _, incoming in incoming }
        waterFlowEffects.merge(textures.waterFlowEffects) { _, incoming in incoming }
        waterWavesEffects.merge(textures.waterWavesEffects) { _, incoming in incoming }
        cursorRippleEffects.merge(textures.cursorRippleEffects) { _, incoming in incoming }
        opacityEffects.merge(textures.opacityEffects) { _, incoming in incoming }
        pulseEffects.merge(textures.pulseEffects) { _, incoming in incoming }
        tintEffects.merge(textures.tintEffects) { _, incoming in incoming }
        godraysEffects.merge(textures.godraysEffects) { _, incoming in incoming }
        xRayEffects[layerID] = textures.xRay
    }
}

/// Lazy pipeline view passed through the ordered authored-effect executor.
struct SceneAuthoredEffectPipelineSet {
    let repository: SceneImageEffectPipelineRepository

    var gaussianBlur: SceneGaussianBlurPipeline? { repository.gaussianBlur() }
    var standardBlur: SceneStandardBlurPipeline? { repository.standardBlur() }
    var localContrast: SceneLocalContrastPipeline? { repository.localContrast() }
    var opacity: SceneOpacityPipeline? { repository.opacity() }
    var colorKey: SceneColorKeyPipeline? { repository.colorKey() }
    var shiftHue: SceneWorkshopShiftHuePipeline? { repository.shiftHue() }
    var audioBars: SceneWorkshopAudioBarsPipeline? { repository.audioBars() }
    var simpleAudioBars: SceneWorkshopSimpleAudioBarsPipeline? {
        repository.simpleAudioBars()
    }
    var workshopGradient: SceneWorkshopGradientPipeline? {
        repository.workshopGradient()
    }
    var workshopShadow: SceneWorkshopShadowPipeline? { repository.workshopShadow() }
    var spin: SceneSpinPipeline? { repository.spin() }
    var proceduralNoise: SceneProceduralNoisePipeline? { repository.proceduralNoise() }
    var filmGrain: SceneFilmGrainPipeline? { repository.filmGrain() }
    var shake: SceneShakePipeline? { repository.shake() }
    var waterFlow: SceneWaterFlowPipeline? { repository.waterFlow() }
    var waterWaves: SceneWaterWavesPipeline? { repository.waterWaves() }
    var cursorRipple: SceneCursorRipplePipeline? { repository.cursorRipple() }
    var waterRipple: SceneWaterRipplePipeline? { repository.waterRipple() }
    var xRay: SceneXRayPipeline? { repository.xRay() }
    var blend: SceneBlendPipeline? { repository.blend() }
    var tint: SceneTintPipeline? { repository.tint() }
    var pulse: ScenePulsePipeline? { repository.pulse() }
    var godrays: SceneGodraysPipeline? { repository.godrays() }
    var authoredShader: SceneAuthoredShaderPipelineCache? { repository.authoredShader() }
}

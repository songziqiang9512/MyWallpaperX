/// Lazy pipeline view passed through the ordered authored-effect executor.
struct SceneAuthoredEffectPipelineSet {
    let repository: SceneImageEffectPipelineRepository

    var gaussianBlur: SceneGaussianBlurPipeline? { repository.gaussianBlur() }
    var standardBlur: SceneStandardBlurPipeline? { repository.standardBlur() }
    var localContrast: SceneLocalContrastPipeline? { repository.localContrast() }
    var opacity: SceneOpacityPipeline? { repository.opacity() }
    var colorGrading: SceneColorGradingPipeline? { repository.colorGrading() }
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
    var waterCaustics: SceneWaterCausticsPipeline? { repository.waterCaustics() }
    var cursorRipple: SceneCursorRipplePipeline? { repository.cursorRipple() }
    var foliageSway: SceneFoliageSwayPipeline? { repository.foliageSway() }
    var waterRipple: SceneWaterRipplePipeline? { repository.waterRipple() }
    var depthParallax: SceneDepthParallaxPipeline? { repository.depthParallax() }
    var xRay: SceneXRayPipeline? { repository.xRay() }
    var blend: SceneBlendPipeline? { repository.blend() }
    var tint: SceneTintPipeline? { repository.tint() }
    var fisheyeZeroDistortion: SceneFisheyeZeroDistortionPipeline? {
        repository.fisheyeZeroDistortion()
    }
    var pulse: ScenePulsePipeline? { repository.pulse() }
    var godrays: SceneGodraysPipeline? { repository.godrays() }
    var shine: SceneShinePipeline? { repository.shine() }
}

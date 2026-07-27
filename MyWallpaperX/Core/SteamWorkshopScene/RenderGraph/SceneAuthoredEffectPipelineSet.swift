/// Pipeline bundle passed through the ordered authored-effect executor.
/// The compositor still owns lifecycle; this only keeps the stage dispatcher signature bounded.
struct SceneAuthoredEffectPipelineSet {
    let gaussianBlur: SceneGaussianBlurPipeline
    let standardBlur: SceneStandardBlurPipeline
    let localContrast: SceneLocalContrastPipeline
    let opacity: SceneOpacityPipeline
    let colorKey: SceneColorKeyPipeline
    let shiftHue: SceneWorkshopShiftHuePipeline
    let audioBars: SceneWorkshopAudioBarsPipeline
    let workshopGradient: SceneWorkshopGradientPipeline
    let workshopShadow: SceneWorkshopShadowPipeline
    let spin: SceneSpinPipeline
    let proceduralNoise: SceneProceduralNoisePipeline
    let filmGrain: SceneFilmGrainPipeline
    let shake: SceneShakePipeline
    let waterFlow: SceneWaterFlowPipeline
    let waterWaves: SceneWaterWavesPipeline
    let waterRipple: SceneWaterRipplePipeline
    let xRay: SceneXRayPipeline
    let tint: SceneTintPipeline
    let pulse: ScenePulsePipeline
    let godrays: SceneGodraysPipeline
}

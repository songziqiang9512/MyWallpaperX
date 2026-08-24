/// Lazy pipeline view passed through the ordered authored-effect executor.
struct SceneAuthoredEffectPipelineSet {
    let repository: SceneImageEffectPipelineRepository

    var gaussianBlur: SceneGaussianBlurPipeline? { repository.gaussianBlur() }
    var standardBlur: SceneStandardBlurPipeline? { repository.standardBlur() }
    var waterWaves: SceneWaterWavesPipeline? { repository.waterWaves() }
    var xRay: SceneXRayPipeline? { repository.xRay() }
    var blend: SceneBlendPipeline? { repository.blend() }
    var pulse: ScenePulsePipeline? { repository.pulse() }
}

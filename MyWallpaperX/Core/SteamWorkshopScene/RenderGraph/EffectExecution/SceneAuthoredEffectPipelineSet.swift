/// Lazy pipeline view passed through the ordered authored-effect executor.
struct SceneAuthoredEffectPipelineSet {
    let repository: SceneImageEffectPipelineRepository

    var standardBlur: SceneStandardBlurPipeline? { repository.standardBlur() }
    var xRay: SceneXRayPipeline? { repository.xRay() }
    var pulse: ScenePulsePipeline? { repository.pulse() }
}

/// Lazy pipeline view passed through the ordered authored-effect executor.
struct SceneAuthoredEffectPipelineSet {
    let repository: SceneImageEffectPipelineRepository

    var standardBlur: SceneStandardBlurPipeline? { repository.standardBlur() }
    var pulse: ScenePulsePipeline? { repository.pulse() }
}

import Foundation

nonisolated struct SceneEffectStageExecutionPlan {
    let layerID: Int
    let renderGraph: SceneAuthoredEffectRenderPlan
    let backend: Backend
    let materialNodeCount: Int
    let logicalRenderTargetCount: Int
    let inputRole: SceneAuthoredEffectInputRole

    init(
        layerID: Int,
        renderGraph: SceneAuthoredEffectRenderPlan,
        backend: Backend,
        materialNodeCount: Int,
        logicalRenderTargetCount: Int,
        inputRole: SceneAuthoredEffectInputRole = .layerSource
    ) {
        self.layerID = layerID
        self.renderGraph = renderGraph
        self.backend = backend
        self.materialNodeCount = materialNodeCount
        self.logicalRenderTargetCount = logicalRenderTargetCount
        self.inputRole = inputRole
    }
}

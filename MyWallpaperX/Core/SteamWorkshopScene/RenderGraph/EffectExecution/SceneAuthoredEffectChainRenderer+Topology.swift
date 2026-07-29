import Foundation

extension SceneAuthoredEffectChainRenderer {
    static func validTopology(
        chain: SceneAuthoredEffectExecutionChain,
        targets: [SceneGraphRenderTargetTable]
    ) -> Bool {
        var previousOutput: SceneAuthoredEffectRenderPlan.TextureIdentity?
        for index in chain.stages.indices {
            let stage = chain.stages[index]
            let table = targets[index]
            guard stage.layerID == chain.layerID,
                  table.plan.layerID == chain.layerID,
                  table.plan.inputRole == stage.inputRole,
                  table.plan.input == stage.renderGraph.effects.first?.input,
                  table.plan.output == stage.renderGraph.finalOutput else {
                return false
            }
            if index == chain.stages.startIndex {
                guard stage.inputRole == .layerSource else { return false }
            } else {
                guard stage.inputRole == .priorEffectOutput,
                      stage.renderGraph.effects.first?.input == previousOutput else {
                    return false
                }
            }
            previousOutput = stage.renderGraph.finalOutput
        }
        return previousOutput == chain.renderGraph.finalOutput
    }
}

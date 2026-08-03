import Metal
import simd

enum SceneLightShaftsLayerRenderer {
    static func draw(
        plan: SceneLightShaftsExecutionPlan,
        resources: SceneLightShaftsEffectTextures,
        model: simd_float4x4,
        viewProjection: simd_float4x4,
        time: Float,
        alpha: Float,
        pipeline: SceneLightShaftsPipeline,
        mainPass: SceneMainPassEncoder,
        executionTrace: SceneEffectExecutionFrameTrace
    ) -> Bool {
        guard let encoder = mainPass.encoder() else {
            executionTrace.recordRouteOperation(
                layerID: plan.effectKey.layerID,
                origin: .quad,
                operation: "light-shafts-main-pass",
                outcome: .failed(reasonCode: "encoder-unavailable")
            )
            return false
        }
        let encoded = pipeline.draw(
            plan: plan,
            resources: resources,
            mvp: viewProjection * model,
            time: time,
            alpha: alpha,
            encoder: encoder
        )
        let key = plan.effectKey
        executionTrace.recordExact(
            identity: SceneEffectExecutionIdentity(
                layerID: key.layerID,
                effectIndex: key.effectIndex,
                descriptorID: key.descriptorID
            ),
            origin: .quad,
            family: "light-shafts",
            backend: "light-shafts",
            outcome: encoded
                ? .encodedOutput
                : .failed(reasonCode: "backend-returned-false")
        )
        return encoded
    }
}

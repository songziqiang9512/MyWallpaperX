import Foundation

extension SceneLegacyEffectPlanningDecision {
    func recordInlineExecution(
        trace: SceneEffectExecutionFrameTrace?,
        origin: SceneEffectExecutionOrigin,
        backend: String,
        outcome: SceneEffectCPUInvocationOutcome
    ) {
        recordExecution(
            exactKind: .legacyExactInline,
            aggregateKind: .legacyCoalescedInline,
            family: nil,
            trace: trace,
            origin: origin,
            backend: backend,
            outcome: outcome
        )
    }

    func recordOffscreenExecution(
        family: String,
        trace: SceneEffectExecutionFrameTrace?,
        origin: SceneEffectExecutionOrigin,
        backend: String,
        outcome: SceneEffectCPUInvocationOutcome
    ) {
        recordExecution(
            exactKind: .legacyExactOffscreen,
            aggregateKind: .legacyCoalescedOffscreen,
            family: family,
            trace: trace,
            origin: origin,
            backend: backend,
            outcome: outcome
        )
    }

    private func recordExecution(
        exactKind: SceneEffectStageRuntimeDisposition.Kind,
        aggregateKind: SceneEffectStageRuntimeDisposition.Kind,
        family: String?,
        trace: SceneEffectExecutionFrameTrace?,
        origin: SceneEffectExecutionOrigin,
        backend: String,
        outcome: SceneEffectCPUInvocationOutcome
    ) {
        guard let trace else { return }
        for disposition in dispositions where family == nil
            || disposition.family == family {
            guard let dispositionFamily = disposition.family else { continue }
            if disposition.kind == exactKind {
                trace.recordExact(
                    identity: SceneEffectExecutionIdentity(
                        layerID: disposition.key.layerID,
                        effectIndex: disposition.key.effectIndex,
                        descriptorID: disposition.key.descriptorID
                    ),
                    origin: origin,
                    family: dispositionFamily,
                    backend: backend,
                    outcome: outcome
                )
            } else if disposition.kind == aggregateKind {
                trace.recordAggregate(
                    layerID: disposition.key.layerID,
                    family: dispositionFamily,
                    origin: origin,
                    backend: backend,
                    outcome: outcome
                )
            }
        }
    }
}

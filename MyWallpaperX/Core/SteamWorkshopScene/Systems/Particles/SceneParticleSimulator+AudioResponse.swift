import Foundation

nonisolated extension SceneParticleSimulator {
    func emissionAudioScale(
        for plan: SceneParticleEmitterSpawnPlan,
        emitterIndex: Int
    ) -> Double? {
        guard plan.audioResponseEnabled else { return 1 }
        guard let responsePlan = plan.audioResponsePlan else { return nil }
        return evaluateAudioResponse(
            responsePlan,
            componentKind: .emitter,
            componentIndex: emitterIndex
        )
    }

    nonisolated func evaluateAudioResponse(
        _ plan: SceneParticleAudioResponsePlan,
        componentKind: SceneParticleAudioComponentKind,
        componentIndex: Int
    ) -> Double {
#if DEBUG
        let identity = SceneParticleAudioComponentIdentity(
            kind: componentKind,
            index: componentIndex
        )
        guard audioInput.generation > 0,
              !observedNonSilentAudioComponents.contains(identity) else {
            return plan.evaluate(audioInput)
        }
        let evaluation = plan.evaluateForExecutionObservation(audioInput)
        guard evaluation.selectedNonZeroInputCount > 0 else {
            return evaluation.response
        }
        observedNonSilentAudioComponents.insert(identity)
        pendingAudioEvaluationObservations.append(.init(
            componentKind: componentKind,
            componentIndex: componentIndex,
            generation: audioInput.generation,
            channel: plan.channel.rawValue,
            frequencyStart: plan.frequencies.lowerBound,
            frequencyEnd: plan.frequencies.upperBound,
            selectedNonZeroInputCount: evaluation.selectedNonZeroInputCount
        ))
        return evaluation.response
#else
        return plan.evaluate(audioInput)
#endif
    }

#if DEBUG
    func observeSelectedRenderer(typedIndex: Int?) {
        guard componentObservation != nil else { return }
        let origin = componentObservation?.origin
        componentObservation?.origin = "prepared"
        if definition.rendererWasImplicit {
            componentObservation?.pending.append(.init(category: "renderer", componentIndex: -1,
                kind: "sprite", stage: "prepared-executable", reason: "implicit-default-selected",
                origin: "prepared", simulationTime: simulationTime, particleID: nil))
        } else {
            for index in definition.renderers.indices {
                componentObservation?.record("renderer", index, index == typedIndex ? "prepared-executable" : "not-selected",
                    reason: index == typedIndex ? "selected-renderer" : "another-renderer-selected", time: simulationTime)
            }
        }
        if let origin { componentObservation?.origin = origin }
    }

    func consumeComponentObservations() -> [SceneParticleComponentObservation] {
        guard componentObservation != nil else { return [] }
        defer { componentObservation?.pending.removeAll(keepingCapacity: true) }
        return componentObservation?.pending ?? []
    }

    nonisolated func consumeAudioEvaluationObservations()
        -> [SceneParticleAudioEvaluationObservation] {
        defer { pendingAudioEvaluationObservations.removeAll(keepingCapacity: true) }
        return pendingAudioEvaluationObservations
    }

    /// Child runtimes reuse one prepared template across short-lived simulator
    /// instances. Suppress component identities already observed by that
    /// template before advancing a new instance, so playback-level dedup does
    /// not leave recurring band scans and pending allocations in the hot path.
    nonisolated func suppressAudioEvaluationObservations(
        for identities: Set<SceneParticleAudioComponentIdentity>
    ) {
        guard !identities.isEmpty,
              !identities.isSubset(of: observedNonSilentAudioComponents) else {
            return
        }
        observedNonSilentAudioComponents.formUnion(identities)
        if !pendingAudioEvaluationObservations.isEmpty {
            pendingAudioEvaluationObservations.removeAll {
                identities.contains(.init(
                    kind: $0.componentKind,
                    index: $0.componentIndex
                ))
            }
        }
    }

#endif
}

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

    func admitsAudioExecution(_ value: SceneParticleOperator) -> Bool {
        !value.audioResponse.isEnabled || value.hasBoundedAudioResponse
    }

    func audioPhaseFactor(_ response: SceneParticleAudioResponse) -> Double {
        guard response.isEnabled,
              let plan = SceneParticleAudioResponsePlan(response) else { return 1 }
        return 1 + plan.evaluate(audioInput)
    }

}

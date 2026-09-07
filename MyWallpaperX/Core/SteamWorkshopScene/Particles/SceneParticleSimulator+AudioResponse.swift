import Foundation

nonisolated extension SceneParticleSimulator {
    func emissionAudioScale(for plan: SceneParticleEmitterSpawnPlan) -> Double? {
        guard plan.audioResponseEnabled else { return 1 }
        return plan.audioResponsePlan?.evaluate(audioInput)
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

import Foundation

nonisolated extension SceneParticleSimulator {
    func emissionAudioScale(for emitter: SceneParticleEmitter) -> Double? {
        guard emitter.audioResponse.isEnabled else { return 1 }
        return emitter.boundedAudioResponsePlan?.evaluate(audioInput)
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

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
}

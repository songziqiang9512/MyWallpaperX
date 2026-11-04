import Foundation

nonisolated extension SceneParticleSimulator {
    func applyPositionBetweenControlPoints(
        _ plan: SceneParticlePositionBetweenControlPointsPlan,
        to particle: inout SceneParticleState,
        emitterControlPointOrigin: SIMD3<Double>
    ) -> Bool {
        guard let start = controlPointLocalPosition(plan.controlPointStart),
              let end = controlPointLocalPosition(plan.controlPointEnd) else { return false }
        let sequence = plan.sequence(particleID: particle.id, countScale: effectiveCountOverride)
        let phase = plan.bounds.x + (plan.bounds.y - plan.bounds.x) * sequence
        let envelope = 4 * phase * (1 - phase)
        // Remove only the emitter's CP translation; its own origin and authored
        // initializer noise remain relative to the mapped path.
        let relative = particle.position - emitterControlPointOrigin
        particle.position = start + (end - start) * phase
            + relative * (plan.rawFlags & 1 != 0 ? envelope : 1)
        if plan.rawFlags & 2 != 0 { particle.velocity *= envelope }
        if plan.rawFlags & 4 != 0, let amount = plan.sizeReductionAmount {
            particle.size *= 1 - amount * (1 - envelope)
        }
        return true
    }
}

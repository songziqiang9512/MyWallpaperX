import Foundation

nonisolated enum SceneParticleChildLifecycle {
    nonisolated static func supportsEmitterProfile(
        _ definition: SceneParticleDefinition
    ) -> Bool {
        !definition.emitters.isEmpty && definition.emitters.allSatisfy { emitter in
            let supportedKind: Bool = switch emitter.kind {
            case .sphereRandom, .boxRandom: true
            case .layerImage, .unsupported: false
            }
            let rate = emitter.rate ?? 5
            let count = emitter.instantaneousCount ?? 0
            let duration = emitter.duration ?? 0
            return supportedKind && emitter.rawFlags & ~2 == 0
                && !emitter.audioResponse.isEnabled
                && rate.isFinite && rate >= 0 && count >= 0
                && duration.isFinite && duration >= 0 && (rate > 0 || count > 0)
        }
    }

    /// Existing event policy: rate-only emitters run for at most the child's
    /// maximum particle lifetime, measured after each emitter's initial delay.
    /// Explicit authored durations are kept by the simulator. This fallback
    /// remains a project policy pending an official event-window golden.
    nonisolated static func maximumParticleLifetime(
        _ definition: SceneParticleDefinition
    ) -> Double {
        var maximum = 0.0
        for initializer in definition.initializers where initializer.kind == .lifetime {
            let upper = SceneParticleSimulationMath.vector(
                initializer.maximum, fallback: SIMD3(repeating: 1)
            )
            maximum = max(maximum, max(upper.x, max(upper.y, upper.z)))
        }
        // Simulator seeds particles with lifetime 1 when no initializer overrides it.
        let fallback = 1.0
        let bounded = maximum > 0 ? maximum : fallback
        return bounded.isFinite ? bounded : fallback
    }

    nonisolated static func accepts(
        event: SceneParticleState,
        template: SceneParticleChildTemplate,
        scopeID: UInt64?
    ) -> Bool {
        guard template.probability < 1 else { return true }
        var random = SceneParticleRandomGenerator(
            state: event.id ^ UInt64(template.index &+ 1) &* 0x94D0_49BB_1331_11EB
                ^ (scopeID ?? 0) &* 0xBF58_476D_1CE4_E5B9
        )
        return random.unit() < template.probability
    }
}

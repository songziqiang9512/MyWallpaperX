import Foundation

nonisolated enum SceneParticleChildLifecycle {
    nonisolated static func supportsEmitterProfile(
        _ definition: SceneParticleDefinition
    ) -> Bool {
        !definition.emitters.isEmpty && definition.emitters.allSatisfy { emitter in
            let supportedKind: Bool = switch emitter.kind {
            case .sphereRandom, .boxRandom: true
            case .unsupported: false
            }
            let rate = emitter.rate ?? 5
            let count = emitter.instantaneousCount ?? 0
            let duration = emitter.duration ?? 0
            return supportedKind && emitter.rawFlags & ~1 == 0
                && !emitter.audioResponse.isEnabled
                && rate.isFinite && rate >= 0 && count >= 0
                && duration.isFinite && duration >= 0 && (rate > 0 || count > 0)
        }
    }

    nonisolated static func emissionCompletionTime(
        _ definition: SceneParticleDefinition
    ) -> Double? {
        var completionTime = 0.0
        for emitter in definition.emitters {
            let rate = emitter.rate ?? 5
            guard rate.isFinite, rate > 0 else { continue }
            guard let duration = emitter.duration,
                  duration.isFinite,
                  duration > 0 else { return nil }
            completionTime = max(completionTime, duration)
        }
        return completionTime
    }

    /// Event-triggered (spawn/death) child systems must not emit forever: authored
    /// rate-only children like rain splashes or flare sparks describe one bounded
    /// burst per event, and an unbounded emitter would accumulate systems until the
    /// depth budget saturates the frame to white. Without a Windows golden for the
    /// exact window, bound rate emission by the child's own maximum particle
    /// lifetime (so rate x lifetime keeps its authored burst size); emitters with
    /// an authored duration keep it.
    nonisolated static func eventEmissionWindow(
        _ definition: SceneParticleDefinition
    ) -> Double {
        if let completion = emissionCompletionTime(definition) { return completion }
        return maximumParticleLifetime(definition)
    }

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
}

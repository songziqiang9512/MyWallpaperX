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
                && (emitter.audioProcessingMode ?? 0) == 0
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
}

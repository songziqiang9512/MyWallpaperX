import Foundation

/// Launch-stable inputs for the alpha fade operator. Lifetime remains a live
/// per-particle value; only the authored fade window is prepared once.
nonisolated struct SceneParticleAlphaFadePlan: Sendable {
    let fadeIn: Double
    let fadeOut: Double

    nonisolated init(_ value: SceneParticleOperator) {
        fadeIn = max(0, value.fadeInTime ?? 0.5)
        fadeOut = min(max(value.fadeOutTime ?? 0.5, 0), 1)
    }
}

/// Launch-stable scalar endpoints for Alpha Change and Size Change. The
/// lifetime-normalized amount remains particle-local and is evaluated live.
nonisolated struct SceneParticleScalarChangePlan: Sendable {
    let start: Double
    let end: Double
    let startTime: Double?
    let endTime: Double?

    nonisolated init(_ value: SceneParticleOperator) {
        start = SceneParticleSimulationMath.scalar(value.startValue, fallback: 1)
        end = SceneParticleSimulationMath.scalar(value.endValue, fallback: 0)
        startTime = value.startTime
        endTime = value.endTime
    }

    nonisolated func value(at life: Double) -> Double {
        start + (end - start) * SceneParticleSimulationMath.changeAmount(
            life, startTime, endTime
        )
    }
}

/// Launch-stable vector endpoints for Color Change. Only the lifetime amount
/// is dynamic, so authored vector projection stays out of each particle loop.
nonisolated struct SceneParticleColorChangePlan: Sendable {
    let start: SIMD3<Double>
    let end: SIMD3<Double>
    let startTime: Double?
    let endTime: Double?

    nonisolated init(_ value: SceneParticleOperator) {
        start = SceneParticleSimulationMath.vector(
            value.startValue, fallback: SIMD3(repeating: 1)
        )
        end = SceneParticleSimulationMath.vector(
            value.endValue, fallback: .zero
        )
        startTime = value.startTime
        endTime = value.endTime
    }

    nonisolated func value(at life: Double) -> SIMD3<Double> {
        let amount = SceneParticleSimulationMath.changeAmount(
            life, startTime, endTime
        )
        return start + (end - start) * amount
    }
}

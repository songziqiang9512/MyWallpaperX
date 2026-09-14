import Foundation
import simd

/// A value owned by Puppet playback, integrated before the script override.
/// Uses the closed-form damped oscillator so a long display frame cannot
/// destabilize a stiff spring. No asset parsing or wall clock lives here.
struct ScenePuppetTranslationMotion: Equatable {
    var velocity: SIMD3<Float> = .zero
    var previousTarget: SIMD3<Float>?

    mutating func advance(
        position: SIMD3<Float>, target: SIMD3<Float>, deltaTime: Double,
        configuration: SceneMdlPuppetRig.TranslationPhysics
    ) -> SIMD3<Float> {
        guard deltaTime.isFinite, deltaTime > 0,
              position.x.isFinite, position.y.isFinite, position.z.isFinite,
              target.x.isFinite, target.y.isFinite, target.z.isFinite else { return position }
        let previous = self
        let dt = min(deltaTime, 0.25)
        var current = position
        if let previousTarget {
            // Increasing inertia reduces displacement induced by animation.
            current += (target - previousTarget) *
                (configuration.inertia / (1 + configuration.inertia))
        }
        previousTarget = target
        let x = SIMD3<Double>(current - target)
        let v = SIMD3<Double>(velocity)
        let damping = Double(configuration.friction) / 2
        let stiffness = configuration.spring ? Double(configuration.stiffness) : 0
        let discriminant = damping * damping - stiffness
        let nextX: SIMD3<Double>
        let nextV: SIMD3<Double>
        if abs(discriminant) < 1e-10 {
            let b = v + damping * x
            let decay = exp(-damping * dt)
            nextX = (x + b * dt) * decay
            nextV = (v - damping * b * dt) * decay
        } else if discriminant < 0 {
            let frequency = sqrt(-discriminant)
            let c = cos(frequency * dt), s = sin(frequency * dt)
            let decay = exp(-damping * dt)
            nextX = (x * c + (v + damping * x) * (s / frequency)) * decay
            nextV = (v * c - (damping * v + stiffness * x) * (s / frequency)) * decay
        } else {
            let root = sqrt(discriminant)
            let r1 = -damping + root, r2 = -damping - root
            let a = (v - r2 * x) / (r1 - r2)
            let b = x - a
            let e1 = exp(r1 * dt), e2 = exp(r2 * dt)
            nextX = a * e1 + b * e2
            nextV = a * (r1 * e1) + b * (r2 * e2)
        }
        let limit = Double(Float.greatestFiniteMagnitude)
        guard (0..<3).allSatisfy({ nextX[$0].isFinite && nextV[$0].isFinite
            && abs(nextX[$0]) <= limit && abs(nextV[$0]) <= limit }) else {
            self = previous
            return position
        }
        var displacement = SIMD3<Float>(nextX)
        velocity = SIMD3<Float>(nextV)
        let length = simd_length(displacement)
        if length > configuration.maxDistance {
            let normal = displacement / length
            displacement = normal * configuration.maxDistance
            velocity -= normal * max(0, simd_dot(velocity, normal))
        }
        if configuration.spring, simd_length_squared(displacement) < 0.000001,
           simd_length_squared(velocity) < 0.000001 {
            displacement = .zero
            velocity = .zero
        }
        return target + displacement
    }
}

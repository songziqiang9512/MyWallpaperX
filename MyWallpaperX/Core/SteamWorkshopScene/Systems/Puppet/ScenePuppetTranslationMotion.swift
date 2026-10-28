import Foundation
import simd

/// A value owned by Puppet playback, integrated before the script override.
/// Uses the closed-form damped oscillator so a long display frame cannot
/// destabilize a stiff spring. No asset parsing or wall clock lives here.
struct ScenePuppetTranslationMotion: Equatable {
    var velocity: SIMD3<Float> = .zero
    var previousTarget: SIMD3<Float>?
    private var worldPosition: SIMD3<Float>?
    private var pendingImpulse: SIMD3<Double> = .zero

    mutating func addImpulse(_ impulse: SIMD3<Float>) {
        pendingImpulse += SIMD3<Double>(impulse)
    }

    /// A later setter supersedes preceding impulses in the admitted journal.
    mutating func reset() {
        worldPosition = nil
        velocity = .zero
        pendingImpulse = .zero
    }

    mutating func advance(
        position: SIMD3<Float>, target: SIMD3<Float>, deltaTime: Double,
        configuration: SceneMdlPuppetRig.TranslationPhysics,
        parentToWorld: simd_float4x4 = matrix_identity_float4x4
    ) -> SIMD3<Float> {
        guard deltaTime.isFinite, deltaTime > 0,
              position.x.isFinite, position.y.isFinite, position.z.isFinite,
              target.x.isFinite, target.y.isFinite, target.z.isFinite else { return position }
        let previous = self
        let determinant = simd_determinant(parentToWorld)
        guard determinant.isFinite, determinant != 0 else { return position }
        let worldToParent = simd_inverse(parentToWorld)
        let dt = min(deltaTime, 0.25)
        let transformedPosition = parentToWorld * SIMD4(position, 1)
        let transformedTarget = parentToWorld * SIMD4(target, 1)
        let worldTarget = SIMD3(transformedTarget.x, transformedTarget.y, transformedTarget.z)
        var current = worldPosition ?? SIMD3(transformedPosition.x, transformedPosition.y, transformedPosition.z)
        if let previousTarget {
            // Increasing inertia reduces displacement induced by animation.
            current += (worldTarget - previousTarget) *
                (configuration.inertia / (1 + configuration.inertia))
        }
        previousTarget = worldTarget
        let x = SIMD3<Double>(current - worldTarget)
        // One kick enters the same stable spring/friction step as existing
        // momentum, rather than splitting its displacement and velocity phases.
        let v = SIMD3<Double>(velocity) + pendingImpulse
        let damping = Double(configuration.friction) / 2
        let stiffness = configuration.spring ? Double(configuration.stiffness) : 0
        let discriminant = damping * damping - stiffness
        let hasGravity = configuration.gravity != .zero
        // Evaluate the constant-input response without subtracting a/k from
        // the position: that loses small displacements as stiffness tends to 0.
        var forceQ: Double?
        if hasGravity {
            let f = 2 * damping * dt, k = stiffness * dt * dt
            if f + sqrt(k) < 0.01 {
                let c2 = f * f - k
                let c3 = -f * c2 + k * f
                let c4 = -f * c3 - k * c2
                forceQ = dt * dt * (0.5 - f / 6 + c2 / 24 + c3 / 120 + c4 / 720)
            }
        }
        var nextX: SIMD3<Double>
        var nextV: SIMD3<Double>
        var forceH = 0.0
        if abs(discriminant) < 1e-10 {
            let b = v + damping * x
            let decay = exp(-damping * dt)
            nextX = (x + b * dt) * decay
            nextV = (v - damping * b * dt) * decay
            if hasGravity {
                forceH = dt * decay
                forceQ = forceQ ?? (-expm1(-damping * dt) - damping * dt * decay)
                    / (damping * damping)
            }
        } else if discriminant < 0 {
            let frequency = sqrt(-discriminant)
            let c = cos(frequency * dt), s = sin(frequency * dt)
            let decay = exp(-damping * dt)
            nextX = (x * c + (v + damping * x) * (s / frequency)) * decay
            nextV = (v * c - (damping * v + stiffness * x) * (s / frequency)) * decay
            if hasGravity {
                forceH = decay * s / frequency
                let halfSine = sin(frequency * dt / 2)
                forceQ = forceQ ?? (-expm1(-damping * dt)
                    + 2 * decay * halfSine * halfSine - damping * forceH) / stiffness
            }
        } else {
            let root = sqrt(discriminant)
            let r1 = -stiffness / (damping + root), r2 = -damping - root
            let a = (v - r2 * x) / (r1 - r2)
            let b = x - a
            let e1 = exp(r1 * dt), e2 = exp(r2 * dt)
            nextX = a * e1 + b * e2
            nextV = a * (r1 * e1) + b * (r2 * e2)
            if hasGravity {
                forceH = e1 * -expm1((r2 - r1) * dt) / (r1 - r2)
                forceQ = forceQ ?? dt * dt * (r1 * Self.phi2(r1 * dt)
                    - r2 * Self.phi2(r2 * dt)) / (r1 - r2)
            }
        }
        if let forceQ {
            let gravity = SIMD3<Double>(configuration.gravity)
            nextX += gravity * forceQ
            nextV += gravity * forceH
        }
        let limit = Double(Float.greatestFiniteMagnitude)
        guard (0..<3).allSatisfy({ nextX[$0].isFinite && nextV[$0].isFinite
            && abs(nextX[$0]) <= limit && abs(nextV[$0]) <= limit }) else {
            self = previous
            pendingImpulse = .zero
            return position
        }
        pendingImpulse = .zero
        let localDisplacement = worldToParent * SIMD4(SIMD3<Float>(nextX), 0)
        var displacement = SIMD3(localDisplacement.x, localDisplacement.y, localDisplacement.z)
        let localVelocity = worldToParent * SIMD4(SIMD3<Float>(nextV), 0)
        var constrainedVelocity = SIMD3(localVelocity.x, localVelocity.y, localVelocity.z)
        let length = simd_length(displacement)
        if length > configuration.maxDistance {
            let normal = displacement / length
            displacement = normal * configuration.maxDistance
            constrainedVelocity -= normal * max(0, simd_dot(constrainedVelocity, normal))
        }
        if configuration.spring, !hasGravity, simd_length_squared(displacement) < 0.000001,
           simd_length_squared(constrainedVelocity) < 0.000001 {
            displacement = .zero
            constrainedVelocity = .zero
        }
        let worldVelocity = parentToWorld * SIMD4(constrainedVelocity, 0)
        velocity = SIMD3(worldVelocity.x, worldVelocity.y, worldVelocity.z)
        let world = parentToWorld * SIMD4(target + displacement, 1)
        guard (0..<3).allSatisfy({ displacement[$0].isFinite && velocity[$0].isFinite && world[$0].isFinite }) else {
            self = previous
            pendingImpulse = .zero
            return position
        }
        worldPosition = SIMD3(world.x, world.y, world.z)
        return target + displacement
    }

    /// Second exponential remainder, including its well-conditioned zero limit.
    private static func phi2(_ z: Double) -> Double {
        if abs(z) < 0.01 {
            return 0.5 + z * (1 / 6.0 + z * (1 / 24.0 + z * (1 / 120.0 + z / 720)))
        }
        return (expm1(z) - z) / (z * z)
    }
}

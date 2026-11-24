import Foundation

nonisolated extension SceneParticleSimulator {
    func applyVortex(
        plan: SceneParticleVortexPlan?,
        duration: Double,
        audioScale: Double?,
        controlPointParticleSpace: SceneParticleControlPointParticleSpace? = nil
    ) {
        guard let plan else { return }
        let audioScale = audioScale ?? 1
        let speedScale = effectiveSpeedOverride
        guard speedScale.isFinite else { return }
        if plan.controlPoint == 0 && !vortexOriginIsActive { return }

        var center = SIMD3<Double>.zero
        var axis = plan.axis
        var worldFrame: SceneParticleWorldSpaceFrame?
        let usesOrientedPoint = (plan.controlPoint ?? 0) != 0
        if let point = plan.controlPoint, usesOrientedPoint {
            guard let position = controlPointLocalPosition(point) else { return }
            center = position
            let angles: SIMD3<Double>
            if let dynamic = dynamicControlPointAngles[point] {
                angles = dynamic
            } else if let bound = activeInstanceOverride?.controlPointAngles[point] {
                guard let value = bound.boundedVectorSeed else { return }
                angles = value
            } else {
                angles = plan.defaultControlPointAngles
            }
            axis = SceneParticleSimulationMath.rotateXYZ(
                axis, sine: SIMD3(sin(angles.x), sin(angles.y), sin(angles.z)),
                cosine: SIMD3(cos(angles.x), cos(angles.y), cos(angles.z))
            )
            if definition.flags.isWorldSpace {
                guard controlPointParticleSpace == nil, let frame = activeWorldSpaceFrame else { return }
                worldFrame = frame
                axis = frame.worldParticleDirection(axis)
            }
        }
        let axisLength = SceneParticleSimulationMath.length(axis)
        guard axisLength.isFinite, axisLength > 1e-12 else { return }
        // The scaled axis contributes to the impulse. Projection onto the
        // radial plane uses only its direction.
        let unitAxis = axis / axisLength
        let rootCenter = center + referencePositionOffset
        let pinsOriginRadius = plan.pinsOriginRadius
        let distanceSpan = plan.distanceOuter - plan.distanceInner
        let speedSpan = plan.speedOuter - plan.speedInner
        let impulseScale = speedScale * audioScale * duration
        particles.withUnsafeMutableBufferPointer { buffer in
            for index in buffer.indices {
                let particleCenter = controlPointParticleSpace.map {
                    center + positionReferenceOffset(for: buffer[index], space: $0)
                } ?? rootCenter
                let localRelative = buffer[index].position - particleCenter
                let relative = worldFrame?.worldParticleDirection(localRelative) ?? localRelative
                let radial = relative - unitAxis * dot(relative, unitAxis)
                let radialLength = SceneParticleSimulationMath.length(radial)
                guard radialLength.isFinite, radialLength > 1e-12 else { continue }
                let distance = plan.usesInfiniteAxis ? radialLength : SceneParticleSimulationMath.length(relative)
                guard distance.isFinite else { continue }
                let amount = distanceSpan > 0 ? min(max((distance - plan.distanceInner) / distanceSpan, 0), 1) : 0
                let speed = plan.speedInner + speedSpan * amount
                let tangent = cross(radial, axis) / (usesOrientedPoint ? distance : radialLength)
                var impulse = tangent * (speed * impulseScale)
                if plan.maintainsRadius {
                    let unit = usesOrientedPoint ? relative / distance : radial / radialLength
                    let localVelocity = buffer[index].velocity
                    let velocity = worldFrame?.worldParticleDirection(localVelocity) ?? localVelocity
                    impulse -= unit * dot(velocity, unit)
                }
                let velocity = buffer[index].velocity + (worldFrame?.localParticleDirection(impulse) ?? impulse)
                guard SceneParticleSimulationMath.isGPUFinite(velocity) else { continue }
                buffer[index].velocity = velocity
                if pinsOriginRadius && buffer[index].vortexRadius == nil {
                    buffer[index].vortexRadius = radialLength
                }
            }
        }
    }

    /// Shared dynamic admission for the force and the preceding Movement.
    var vortexOriginIsActive: Bool {
        let angle = activeInstanceOverride?.controlPointAngles[0]?.value
        return (dynamicControlPointAngles[0] ?? .zero) == .zero
            && (angle == nil || angle == .vector([0, 0, 0]))
            && controlPointPosition(0, offset: .zero) == .zero
    }

    /// Movement remains the only position integrator. Exact rotation avoids
    /// the energy/radius drift of Euler centripetal acceleration or projection.
    func vortexMovement(
        particlePosition: SIMD3<Double>, vortexRadius: Double?,
        velocity: SIMD3<Double>, duration: Double
    ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        guard let radius = vortexRadius else {
            return (particlePosition + velocity * duration, velocity)
        }
        let radial = SIMD3(particlePosition.x, particlePosition.y, 0)
        let length = SceneParticleSimulationMath.length(radial)
        guard length > 1e-12 else { return (particlePosition, velocity) }
        let unit = radial / length
        let tangent = SIMD3(unit.y, -unit.x, 0)
        let speed = dot(velocity, tangent)
        let angle = speed * duration / radius
        let nextUnit = unit * cos(angle) + tangent * sin(angle)
        let position = SIMD3(nextUnit.x * radius, nextUnit.y * radius,
                             particlePosition.z + velocity.z * duration)
        let nextVelocity = SIMD3(nextUnit.y * speed, -nextUnit.x * speed, velocity.z)
        return (position, nextVelocity)
    }

    private func dot(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private func cross(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            lhs.y * rhs.z - lhs.z * rhs.y,
            lhs.z * rhs.x - lhs.x * rhs.z,
            lhs.x * rhs.y - lhs.y * rhs.x
        )
    }
}

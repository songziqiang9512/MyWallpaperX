import Foundation

nonisolated enum SceneParticleSimulationDiagnosticKind: String, Hashable, Sendable {
    case unsupportedEmitter
    case unsupportedInitializer
    case colorListBounded
    case colorListUnsupported
    case positionOffsetBounded
    case positionOffsetUnsupported
    case unsupportedOperator
    case boidsBounded
    case boidsUnsupported
    case vortexBounded
    case vortexUnsupported
    case capVelocityBounded
    case capVelocityUnsupported
    case controlPointForceBounded
    case controlPointForceUnsupported
    case unsupportedRenderer
    case trailRendererIgnored
    case childSystemsIgnored
    case dynamicOverrideIgnored
    case audioResponseBounded
    case audioResponseIgnored
    case periodicEmissionBounded
    case periodicEmissionUnsupported
    case emitterDelayBounded
    case emitterDelayUnsupported
    case controlPointEmitterBounded
    case controlPointEmitterUnsupported
    case controlPointEmitterAnglesBounded
    case controlPointEmitterAnglesUnsupported
    case emitterSpeedBounded
    case emitterSpeedUnsupported
    case emitterShapeBounded
    case emitterShapeUnsupported
    case pointerControlPointBounded
    case pointerControlPointUnsupported
}

nonisolated struct SceneParticleSimulationDiagnostic: Hashable, Sendable {
    let kind: SceneParticleSimulationDiagnosticKind
    let componentName: String?
}

extension SceneParticleInitializer {
    nonisolated var boundedColorList: [SIMD3<Double>]? {
        guard case .colorList = kind, !hasMalformedColorList,
              let colors, (1 ... 10).contains(colors.count) else { return nil }
        var result: [SIMD3<Double>] = []
        result.reserveCapacity(colors.count)
        for color in colors {
            guard case let .vector(values) = color, values.count == 3,
                  values.allSatisfy({ $0.isFinite && (0 ... 1).contains($0) }) else {
                return nil
            }
            result.append(SIMD3(values[0], values[1], values[2]))
        }
        return result
    }
}

extension SceneParticleSimulationMath {
    nonisolated static func diagnostics(
        _ definition: SceneParticleDefinition,
        _ instanceOverride: SceneParticleInstanceOverride?
    ) -> [SceneParticleSimulationDiagnostic] {
        var result = audioDiagnostics(definition)
        func add(_ kind: SceneParticleSimulationDiagnosticKind, _ name: String? = nil) {
            let value = SceneParticleSimulationDiagnostic(kind: kind, componentName: name)
            if !result.contains(value) { result.append(value) }
        }

        for emitter in definition.emitters {
            if case let .unsupported(name) = emitter.kind { add(.unsupportedEmitter, name) }
            switch emitter.initialDelayAdmission {
            case .supported:
                add(.emitterDelayBounded, "initial")
            case .unsupported:
                add(.emitterDelayUnsupported, "initial")
            case .disabled:
                break
            }
            switch emitter.periodicEmissionAdmission {
            case .supported where instanceOverride?.rate != nil || instanceOverride?.count != nil:
                add(.periodicEmissionUnsupported, "instanceoverride")
            case .supported:
                add(.periodicEmissionBounded, "randomperiodic")
            case .unsupported:
                add(.periodicEmissionUnsupported, "randomperiodic")
            case .disabled:
                break
            }
        }
        let controlPointEmitters = definition.emitters.filter { $0.controlPoint != nil }
        if !controlPointEmitters.isEmpty {
            if controlPointEmitters.allSatisfy({ emitter in
                definition.emitterControlPointFrame(
                    for: emitter, instanceOverride: instanceOverride,
                    dynamicControlPoints: [:]
                ) != nil
            }) {
                add(.controlPointEmitterBounded, "sources=\(controlPointEmitters.count)")
            } else {
                add(.controlPointEmitterUnsupported, "admission")
            }
            let angledEmitters = controlPointEmitters.filter {
                definition.hasAuthoredEmitterAngles($0, instanceOverride: instanceOverride)
            }
            if !angledEmitters.isEmpty {
                let supported = angledEmitters.allSatisfy {
                    definition.emitterControlPointFrame(
                        for: $0, instanceOverride: instanceOverride,
                        dynamicControlPoints: [:]
                    ) != nil
                }
                add(supported ? .controlPointEmitterAnglesBounded
                              : .controlPointEmitterAnglesUnsupported,
                    "sources=\(angledEmitters.count)")
            }
        }
        let speedEmitters = definition.emitters.filter {
            $0.speedMinimum != nil || $0.speedMaximum != nil
        }
        if !speedEmitters.isEmpty {
            if speedEmitters.allSatisfy({ $0.boundedSpeedRange != nil }) {
                add(.emitterSpeedBounded, "sources=\(speedEmitters.count)")
            } else {
                add(.emitterSpeedUnsupported, "range")
            }
        }
        let shapeEmitters = definition.emitters.filter {
            $0.directions != nil || $0.sign != nil || $0.hasMalformedDirectionsOrSign
        }
        if !shapeEmitters.isEmpty {
            if shapeEmitters.allSatisfy(\.hasBoundedDirectionsAndSign) {
                add(.emitterShapeBounded, "sources=\(shapeEmitters.count)")
            } else {
                add(.emitterShapeUnsupported, "directionsOrSign")
            }
        }
        for initializer in definition.initializers {
            switch initializer.kind {
            case .colorList:
                add(initializer.boundedColorList == nil
                    ? .colorListUnsupported : .colorListBounded, "colorlist")
            case .turbulentVelocity:
                break
            case .positionOffset:
                add(initializer.boundedPositionOffset == nil
                    ? .positionOffsetUnsupported : .positionOffsetBounded,
                    "positionoffsetrandom")
            case let .unsupported(name):
                add(.unsupportedInitializer, name)
            default:
                break
            }
        }
        for value in definition.operators {
            switch value.kind {
            case .controlPointAttract:
                add(definition.supportsBoundedControlPointForce(value) ? .controlPointForceBounded : .controlPointForceUnsupported, "controlpointattract")
            case .turbulence:
                break
            case .boids:
                add(definition.boidsPlan(for: value) == nil ? .boidsUnsupported : .boidsBounded, "boids")
            case .vortex:
                add(value.hasBoundedVortexExecution
                    ? .vortexBounded : .vortexUnsupported, "vortex")
            case .capVelocity:
                add(value.capVelocityPlan == nil
                    ? .capVelocityUnsupported : .capVelocityBounded, "capvelocity")
            case let .unsupported(name):
                add(name.contains("controlpoint") ? .controlPointForceUnsupported : .unsupportedOperator, name)
            default:
                break
            }
        }
        for renderer in definition.renderers {
            switch renderer.kind {
            case .sprite:
                break
            case .spriteTrail:
                break
            case .rope:
                break
            case .ropeTrail:
                break
            case let .unsupported(name):
                add(.unsupportedRenderer, name)
            }
        }
        if !definition.children.isEmpty { add(.childSystemsIgnored, "children") }
        let pointerPoints = definition.controlPoints.filter(\.followsPointer)
        if !pointerPoints.isEmpty {
            add(pointerPoints.allSatisfy(\.hasBoundedPointerInput) ? .pointerControlPointBounded : .pointerControlPointUnsupported, "sources=\(pointerPoints.count)")
        }

        let scalarValues = [instanceOverride?.alpha, instanceOverride?.size,
                            instanceOverride?.lifetime, instanceOverride?.rate,
                            instanceOverride?.speed, instanceOverride?.count,
                            instanceOverride?.brightness].compactMap { $0 }
        let unsupportedScalarBinding = scalarValues.contains {
            $0.hasScript || ($0.userPropertyKey != nil && $0.hasAnimation)
        }
        let unsupportedColorBinding = [instanceOverride?.color].compactMap { $0 }.contains {
            $0.userPropertyKey != nil || $0.hasScript || $0.hasAnimation
        } || [instanceOverride?.normalizedColor].compactMap { $0 }.contains {
            $0.hasScript || $0.hasAnimation
        }
        let unsupportedControlPointBindings = instanceOverride?.controlPoints.values.contains {
            $0.userPropertyKey != nil || $0.hasScript || $0.hasAnimation
        } ?? false || instanceOverride?.controlPointAngles.values.contains {
            $0.userPropertyKey != nil || $0.hasScript || $0.hasAnimation
        } ?? false
        if unsupportedScalarBinding || unsupportedColorBinding || unsupportedControlPointBindings {
            add(.dynamicOverrideIgnored, "instanceoverride")
        }
        return result
    }
}

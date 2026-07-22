import Foundation

nonisolated enum SceneParticleSimulationDiagnosticKind: String, Hashable, Sendable {
    case unsupportedEmitter
    case unsupportedInitializer
    case unsupportedOperator
    case controlPointForceIgnored
    case unsupportedRenderer
    case trailRendererIgnored
    case childSystemsIgnored
    case dynamicOverrideIgnored
    case audioResponseIgnored
    case pointerControlPointIgnored
}

nonisolated struct SceneParticleSimulationDiagnostic: Hashable, Sendable {
    let kind: SceneParticleSimulationDiagnosticKind
    let componentName: String?
}

nonisolated struct SceneParticleState: Equatable, Sendable {
    let id: UInt64
    var position: SIMD3<Double>
    var velocity: SIMD3<Double>
    var color: SIMD3<Double>
    var alpha: Double
    var size: Double
    var rotation: SIMD3<Double>
    var angularVelocity: SIMD3<Double>
    var age: Double
    var lifetime: Double

    var initialColor: SIMD3<Double>
    var initialAlpha: Double
    var initialSize: Double
}

nonisolated struct SceneParticleRandomGenerator: Sendable {
    var state: UInt64

    mutating func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func value(_ first: Double, _ second: Double) -> Double {
        let lower = min(first, second)
        return lower + unit() * (max(first, second) - lower)
    }
}

nonisolated enum SceneParticleSimulationMath {
    static func scalar(_ value: SceneParticleNumericValue?, fallback: Double) -> Double {
        switch value {
        case let .scalar(number): number
        case let .vector(values): values.first ?? fallback
        case nil: fallback
        }
    }

    static func vector(
        _ value: SceneParticleNumericValue?,
        fallback: SIMD3<Double>
    ) -> SIMD3<Double> {
        switch value {
        case let .scalar(number):
            SIMD3(repeating: number)
        case let .vector(values):
            SIMD3(
                values.indices.contains(0) ? values[0] : fallback.x,
                values.indices.contains(1) ? values[1] : fallback.y,
                values.indices.contains(2) ? values[2] : fallback.z
            )
        case nil:
            fallback
        }
    }

    static func length(_ value: SIMD3<Double>) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }

    static func changeAmount(
        _ life: Double,
        _ rawStart: Double?,
        _ rawEnd: Double?
    ) -> Double {
        let start = rawStart ?? 0
        let end = rawEnd ?? 1
        guard end > start else { return life > end ? 1 : 0 }
        return min(max((life - start) / (end - start), 0), 1)
    }

    static func diagnostics(
        _ definition: SceneParticleDefinition,
        _ instanceOverride: SceneParticleInstanceOverride?
    ) -> [SceneParticleSimulationDiagnostic] {
        var result: [SceneParticleSimulationDiagnostic] = []
        func add(_ kind: SceneParticleSimulationDiagnosticKind, _ name: String? = nil) {
            let value = SceneParticleSimulationDiagnostic(kind: kind, componentName: name)
            if !result.contains(value) { result.append(value) }
        }

        for emitter in definition.emitters {
            if case let .unsupported(name) = emitter.kind { add(.unsupportedEmitter, name) }
            if (emitter.audioProcessingMode ?? 0) != 0 { add(.audioResponseIgnored, "emitter") }
        }
        for initializer in definition.initializers {
            switch initializer.kind {
            case .turbulentVelocity:
                add(.unsupportedInitializer, "turbulentvelocityrandom")
                if (initializer.turbulentVelocity?.audioProcessingMode ?? 0) != 0 {
                    add(.audioResponseIgnored, "turbulentvelocityrandom")
                }
            case let .unsupported(name):
                add(.unsupportedInitializer, name)
            default:
                break
            }
        }
        for value in definition.operators {
            switch value.kind {
            case .controlPointAttract:
                add(.controlPointForceIgnored, "controlpointattract")
            case .turbulence:
                add(.unsupportedOperator, "turbulence")
            case .vortex:
                add(.unsupportedOperator, "vortex")
            case let .unsupported(name):
                add(name.contains("controlpoint") ? .controlPointForceIgnored : .unsupportedOperator, name)
            default:
                break
            }
        }
        for renderer in definition.renderers {
            switch renderer.kind {
            case .sprite:
                break
            case .spriteTrail:
                add(.trailRendererIgnored, "spritetrail")
            case .rope:
                add(.unsupportedRenderer, "rope")
            case .ropeTrail:
                add(.trailRendererIgnored, "ropetrail")
            case let .unsupported(name):
                add(.unsupportedRenderer, name)
            }
        }
        if !definition.children.isEmpty { add(.childSystemsIgnored, "children") }
        if definition.controlPoints.contains(where: \.followsPointer) {
            add(.pointerControlPointIgnored, "controlpoint")
        }

        var boundValues = [instanceOverride?.alpha, instanceOverride?.size,
                           instanceOverride?.lifetime, instanceOverride?.rate,
                           instanceOverride?.speed, instanceOverride?.count,
                           instanceOverride?.brightness, instanceOverride?.color,
                           instanceOverride?.normalizedColor].compactMap { $0 }
        boundValues += instanceOverride?.controlPoints.values.map { $0 } ?? []
        boundValues += instanceOverride?.controlPointAngles.values.map { $0 } ?? []
        if boundValues.contains(where: {
            $0.userPropertyKey != nil || $0.hasScript || $0.hasAnimation
        }) {
            add(.dynamicOverrideIgnored, "instanceoverride")
        }
        return result
    }
}

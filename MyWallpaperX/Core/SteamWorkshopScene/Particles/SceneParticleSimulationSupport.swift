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

    static func addFinite(
        _ delta: SIMD3<Double>,
        to value: inout SIMD3<Double>
    ) {
        let result = value + delta
        if result.x.isFinite && result.y.isFinite && result.z.isFinite {
            value = result
        }
    }

    static func turbulentVelocity(
        _ value: SceneParticleTurbulentVelocity?,
        _ position: SIMD3<Double>,
        _ time: Double,
        _ random: inout SceneParticleRandomGenerator
    ) -> SIMD3<Double> {
        guard let value, !value.audioResponse.isEnabled else { return .zero }
        let phase = random.value(value.phaseMinimum ?? 0, value.phaseMaximum ?? 2 * .pi)
        let timeScale = value.timeScale ?? 1
        let directionalOffset = value.offset ?? 0
        guard phase.isFinite, time.isFinite, timeScale.isFinite,
              directionalOffset.isFinite,
              position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            return .zero
        }
        let noiseTime = phase + time * timeScale
        // Author positions select a coherent field; scale controls angular spread, not frequency.
        let point = position * 0.001 + SIMD3(noiseTime, 0, 0)
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { return .zero }
        let turnNoise = gradientNoise(point, seed: 0xBF58476D1CE4E5B9)
        let planeNoise = gradientNoise(
            point + SIMD3(59.19, 71.41, 89.97), seed: 0x94D049BB133111EB
        )
        let forward = vector(value.forward, fallback: SIMD3(0, 1, 0))
        let normal = vector(value.right, fallback: SIMD3(0, 0, 1))
        let up = vector(value.up, fallback: .zero)
        let forwardLength = length(forward)
        guard forwardLength.isFinite, forwardLength > 1e-9 else { return .zero }
        let base = forward / forwardLength
        let adjustedNormal = normal + up * planeNoise
        let tangentValue = SIMD3(
            adjustedNormal.y * base.z - adjustedNormal.z * base.y,
            adjustedNormal.z * base.x - adjustedNormal.x * base.z,
            adjustedNormal.x * base.y - adjustedNormal.y * base.x
        )
        let tangentLength = length(tangentValue)
        guard tangentLength.isFinite, tangentLength > 1e-9 else { return .zero }
        let tangent = tangentValue / tangentLength
        let angularScale = max(value.scale ?? 1, 0)
        guard angularScale.isFinite else { return .zero }
        let turn = directionalOffset + angularScale * Double.pi * turnNoise
        var direction = base * cos(turn) + tangent * sin(turn)
        var directionLength = length(direction)
        if !directionLength.isFinite || directionLength <= 1e-9 {
            direction = base
            directionLength = length(direction)
        }
        guard directionLength.isFinite, directionLength > 1e-9 else { return .zero }
        let minimumSpeed = max(value.speedMinimum ?? 0, 0)
        let maximumSpeed = max(value.speedMaximum ?? 100, minimumSpeed)
        return direction / directionLength * random.value(minimumSpeed, maximumSpeed)
    }

    private static func gradientNoise(_ point: SIMD3<Double>, seed: UInt64) -> Double {
        let baseX = Int(floor(point.x))
        let baseY = Int(floor(point.y))
        let baseZ = Int(floor(point.z))
        let local = SIMD3(point.x - Double(baseX), point.y - Double(baseY), point.z - Double(baseZ))
        let fade = SIMD3(noiseFade(local.x), noiseFade(local.y), noiseFade(local.z))
        var corners = Array(repeating: 0.0, count: 8)
        for z in 0...1 {
            for y in 0...1 {
                for x in 0...1 {
                    let offset = SIMD3(local.x - Double(x), local.y - Double(y), local.z - Double(z))
                    let gradient = noiseGradient(baseX + x, baseY + y, baseZ + z, seed: seed)
                    corners[x + y * 2 + z * 4] = gradient.x * offset.x
                        + gradient.y * offset.y + gradient.z * offset.z
                }
            }
        }
        let lower = noiseLerp(
            noiseLerp(corners[0], corners[1], fade.x),
            noiseLerp(corners[2], corners[3], fade.x),
            fade.y
        )
        let upper = noiseLerp(
            noiseLerp(corners[4], corners[5], fade.x),
            noiseLerp(corners[6], corners[7], fade.x),
            fade.y
        )
        return noiseLerp(lower, upper, fade.z)
    }

    private static func noiseGradient(_ x: Int, _ y: Int, _ z: Int, seed: UInt64) -> SIMD3<Double> {
        var hash = seed
        hash ^= UInt64(bitPattern: Int64(x)) &* 0x9E3779B185EBCA87
        hash ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F
        hash ^= UInt64(bitPattern: Int64(z)) &* 0x165667B19E3779F9
        hash ^= hash >> 29
        hash &*= 0x9FB21C651E98DF25
        hash ^= hash >> 32
        let signs = SIMD3(
            (hash & 1) == 0 ? 1.0 : -1.0,
            (hash & 2) == 0 ? 1.0 : -1.0,
            (hash & 4) == 0 ? 1.0 : -1.0
        )
        switch Int((hash >> 3) % 3) {
        case 0: return SIMD3(signs.x, signs.y, 0)
        case 1: return SIMD3(signs.x, 0, signs.z)
        default: return SIMD3(0, signs.y, signs.z)
        }
    }

    private static func noiseFade(_ value: Double) -> Double {
        value * value * value * (value * (value * 6 - 15) + 10)
    }

    private static func noiseLerp(_ first: Double, _ second: Double, _ amount: Double) -> Double {
        first + (second - first) * amount
    }

    static func turbulenceDirection(
        position: SIMD3<Double>,
        time: Double,
        phase: Double,
        scale: Double,
        timeScale: Double,
        mask: SIMD3<Double>
    ) -> SIMD3<Double> {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
              time.isFinite, phase.isFinite, scale.isFinite, timeScale.isFinite,
              mask.x.isFinite, mask.y.isFinite, mask.z.isFinite else { return .zero }
        let noiseTime = phase + time * timeScale
        // De-correlate one project-owned coherent field across its three sample axes.
        let point = position * scale + SIMD3(
            noiseTime,
            noiseTime * 0.754_877_666,
            noiseTime * 1.324_717_957
        )
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite,
              abs(point.x) < 1e12, abs(point.y) < 1e12, abs(point.z) < 1e12 else {
            return .zero
        }
        let turn = gradientNoise(point, seed: 0xD6E8FEB86659FD93) * 2 * Double.pi
        var direction = SIMD3(cos(turn), sin(turn), 0.0)
        if abs(mask.z) > 1e-9 {
            direction.z = gradientNoise(
                point + SIMD3(47.17, 73.31, 101.03),
                seed: 0xA0761D6478BD642F
            )
            let directionLength = length(direction)
            guard directionLength.isFinite, directionLength > 1e-9 else { return .zero }
            direction /= directionLength
        }
        return direction * mask
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
            if emitter.audioResponse.isEnabled { add(.audioResponseIgnored, "emitter") }
        }
        for `operator` in definition.operators {
            // operator 的 audio 调制此前不产生诊断，启用后会静默按无音频路径模拟。
            if `operator`.audioResponse.isEnabled { add(.audioResponseIgnored, "operator") }
        }
        for initializer in definition.initializers {
            switch initializer.kind {
            case .turbulentVelocity:
                if initializer.turbulentVelocity?.audioResponse.isEnabled == true {
                    add(.unsupportedInitializer, "turbulentvelocityrandom")
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
                if value.audioResponse.isEnabled {
                    add(.unsupportedOperator, "turbulence")
                }
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
                break
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

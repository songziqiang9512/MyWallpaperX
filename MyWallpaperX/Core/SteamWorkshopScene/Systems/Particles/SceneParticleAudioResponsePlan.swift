import Foundation

/// Sanitized 16-band input consumed by the particle simulator.
/// One value is created from the frame snapshot and reused by every fixed step in that frame.
nonisolated struct SceneParticleAudioInput: Equatable, Sendable {
    static let bandCount = 16
    static let silent = SceneParticleAudioInput(
        left: Array(repeating: 0, count: bandCount),
        right: Array(repeating: 0, count: bandCount),
        generation: 0
    )

    let left: [Float]
    let right: [Float]
    /// Generation of the shared typed snapshot used by this simulation frame.
    /// Zero remains the stable sentinel for silence and synthetic callers that
    /// do not claim a live publication identity.
    let generation: UInt64

    nonisolated init(left: [Float], right: [Float], generation: UInt64 = 0) {
        self.left = Self.sanitized(left)
        self.right = Self.sanitized(right)
        self.generation = generation
    }

    private nonisolated static func sanitized(_ values: [Float]) -> [Float] {
        guard values.count == bandCount else {
            return Array(repeating: 0, count: bandCount)
        }
        return values.map { value in
            value.isFinite && value > 0 ? value : 0
        }
    }
}

/// Project-owned clean-room approximation of particle audio response.
///
/// Public author documentation defines channel selection, 16 frequency bands, bounds and
/// exponent behavior, but does not publish the particle runtime formula. This plan therefore
/// uses a deliberately simple contract: mean the selected bands, normalize linearly inside
/// the authored bounds, then apply the exponent. It is independent from the stock effect
/// shader evaluator and does not claim Wallpaper Engine numeric parity.
nonisolated struct SceneParticleAudioResponsePlan: Equatable, Sendable {
    nonisolated enum Channel: Int, Equatable, Sendable {
        case left = 1
        case right = 2
        case center = 3
    }

    let channel: Channel
    let bounds: ClosedRange<Double>
    let exponent: Double
    let frequencies: ClosedRange<Int>

    nonisolated init?(_ declaration: SceneParticleAudioResponse) {
        guard declaration.isEnabled,
              let mode = declaration.mode,
              let channel = Channel(rawValue: mode) else { return nil }

        let bounds: ClosedRange<Double>
        switch declaration.bounds {
        case let .vector(values)? where values.count == 2:
            guard values[0].isFinite, values[1].isFinite,
                  values[0] >= 0, values[0] < values[1], values[1] <= 1 else {
                return nil
            }
            bounds = values[0] ... values[1]
        case nil:
            // Mode-only declarations occur in the current Workshop corpus. The public
            // documentation uses 0...1 as the neutral full-range example.
            bounds = 0 ... 1
        default:
            return nil
        }

        let exponent = declaration.exponent ?? 2
        guard exponent.isFinite, exponent > 0, exponent <= 16 else { return nil }

        let first = declaration.frequencyStart ?? 0
        let last = declaration.frequencyEnd ?? 1
        guard (0..<SceneParticleAudioInput.bandCount).contains(first),
              (0..<SceneParticleAudioInput.bandCount).contains(last) else { return nil }

        self.channel = channel
        self.bounds = bounds
        self.exponent = exponent
        self.frequencies = min(first, last) ... max(first, last)
    }

    nonisolated func evaluate(_ input: SceneParticleAudioInput) -> Double {
        var total = 0.0
        for index in frequencies {
            switch channel {
            case .left:
                total += Double(input.left[index])
            case .right:
                total += Double(input.right[index])
            case .center:
                total += Double(input.left[index]) + Double(input.right[index])
            }
        }
        return boundedResponse(total: total)
    }

    /// Evaluates the authored response and counts positive selected inputs in
    /// the same ordered traversal. Execution observation calls this only while
    /// an identity is still unreported, avoiding a second scan of the bands.
    nonisolated func evaluateForExecutionObservation(
        _ input: SceneParticleAudioInput
    ) -> (response: Double, selectedNonZeroInputCount: Int) {
        var total = 0.0
        var selectedNonZeroInputCount = 0
        for index in frequencies {
            switch channel {
            case .left:
                let value = input.left[index]
                total += Double(value)
                if value > 0 { selectedNonZeroInputCount += 1 }
            case .right:
                let value = input.right[index]
                total += Double(value)
                if value > 0 { selectedNonZeroInputCount += 1 }
            case .center:
                let left = input.left[index]
                let right = input.right[index]
                total += Double(left) + Double(right)
                if left > 0 { selectedNonZeroInputCount += 1 }
                if right > 0 { selectedNonZeroInputCount += 1 }
            }
        }
        return (
            boundedResponse(total: total),
            selectedNonZeroInputCount
        )
    }

    private nonisolated func boundedResponse(total: Double) -> Double {
        let channelCount = channel == .center ? 2 : 1
        let count = Double(frequencies.count * channelCount)
        guard count > 0 else { return 0 }
        let mean = total / count
        let normalized = min(max(
            (mean - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound),
            0
        ), 1)
        let response = pow(normalized, exponent)
        return response.isFinite ? min(max(response, 0), 1) : 0
    }
}

nonisolated enum SceneParticleAudioComponentKind: String, Hashable, Sendable {
    case emitter
    case initializer
    case `operator`
}

/// Payload-free proof that one prepared particle component evaluated its own
/// authored band selection against a non-silent typed publication.
nonisolated struct SceneParticleAudioEvaluationObservation: Hashable, Sendable {
    let componentKind: SceneParticleAudioComponentKind
    let componentIndex: Int
    let generation: UInt64
    let channel: Int
    let frequencyStart: Int
    let frequencyEnd: Int
    let selectedNonZeroInputCount: Int
}

nonisolated struct SceneParticleAudioComponentIdentity: Hashable, Sendable {
    let kind: SceneParticleAudioComponentKind
    let index: Int
}

/// Launch-stable execution inputs for the turbulence operator.
///
/// Particle position, simulation time, audio input and speed overrides remain
/// frame-varying. Everything else comes from the authored definition and is
/// prepared once with the simulator.
nonisolated struct SceneParticleTurbulencePlan: Sendable {
    let scale: Double
    let timeScale: Double
    let mask: SIMD3<Double>
    let minimumSpeed: Double
    let maximumSpeed: Double
    let phaseMinimum: Double
    let phaseMaximum: Double
    let hasBlendIn: Bool
    let blendInStart: Double
    let blendInEnd: Double
    let hasBlendOut: Bool
    let blendOutStart: Double
    let blendOutEnd: Double
    let audioResponse: SceneParticleAudioResponsePlan?

    nonisolated init?(_ value: SceneParticleOperator) {
        guard case .turbulence = value.kind else { return nil }
        let scale = SceneParticleSimulationMath.scalar(value.scale, fallback: 0.005)
        let timeScale = value.timeScale ?? 0.01
        let mask = SceneParticleSimulationMath.vector(
            value.mask, fallback: SIMD3(1, 1, 0)
        )
        let rawMinimumSpeed = value.speedMinimum ?? 500
        let rawMaximumSpeed = value.speedMaximum ?? 1_000
        guard scale.isFinite, timeScale.isFinite,
              rawMinimumSpeed.isFinite, rawMaximumSpeed.isFinite else {
            return nil
        }
        self.scale = scale
        self.timeScale = timeScale
        self.mask = mask
        self.minimumSpeed = max(rawMinimumSpeed, 0)
        self.maximumSpeed = max(rawMaximumSpeed, self.minimumSpeed)
        self.phaseMinimum = value.phaseMinimum ?? 0
        self.phaseMaximum = value.phaseMaximum ?? 0
        self.hasBlendIn = value.blendInStart != nil || value.blendInEnd != nil
        self.blendInStart = value.blendInStart ?? 0
        self.blendInEnd = value.blendInEnd ?? 0
        self.hasBlendOut = value.blendOutStart != nil || value.blendOutEnd != nil
        self.blendOutStart = value.blendOutStart ?? 1
        self.blendOutEnd = value.blendOutEnd ?? 1
        self.audioResponse = SceneParticleAudioResponsePlan(value.audioResponse)
    }

    nonisolated func blendAmount(_ life: Double) -> Double {
        var result = 1.0
        if hasBlendIn {
            result *= SceneParticleSimulationMath.changeAmount(
                life, blendInStart, blendInEnd
            )
        }
        if hasBlendOut {
            result *= 1 - SceneParticleSimulationMath.changeAmount(
                life, blendOutStart, blendOutEnd
            )
        }
        return result
    }
}

nonisolated extension SceneParticleEmitter {
    /// Audio emission currently admits the common root Sphere/Box rate profile only.
    /// Delay, duration, periodic, burst, Layer Image and unknown flag interactions remain
    /// fail closed until they receive their own timing contracts.
    var boundedAudioResponsePlan: SceneParticleAudioResponsePlan? {
        guard let plan = SceneParticleAudioResponsePlan(audioResponse) else { return nil }
        let supportedKind: Bool = switch kind {
        case .sphereRandom, .boxRandom: true
        case .layerImage, .unsupported: false
        }
        let authoredRate = rate ?? 5
        guard supportedKind, rawFlags & ~2 == 0,
              authoredRate.isFinite, authoredRate >= 0,
              (instantaneousCount ?? 0) == 0,
              (duration ?? 0) == 0,
              !usesRandomPeriodicEmission,
              case .disabled = initialDelayAdmission else { return nil }
        return plan
    }
}

nonisolated extension SceneParticleDefinition {
    var hasBoundedAudioConsumer: Bool {
        emitters.contains { $0.boundedAudioResponsePlan != nil }
            || initializers.contains {
                $0.turbulentVelocity.flatMap {
                    SceneParticleAudioResponsePlan($0.audioResponse)
                } != nil
            }
            || operators.contains { value in
                value.hasBoundedAudioResponse
            }
    }
}

nonisolated extension SceneParticleOperator {
    var hasBoundedAudioResponse: Bool {
        guard SceneParticleAudioResponsePlan(audioResponse) != nil else {
            return false
        }
        return switch kind {
        case .turbulence: true
        case .vortex: vortexPlan != nil
        default: false
        }
    }

    var hasBoundedVortexExecution: Bool {
        guard vortexPlan != nil else { return false }
        return !audioResponse.isEnabled || hasBoundedAudioResponse
    }
}

nonisolated extension SceneParticleSimulationMath {
    static func audioDiagnostics(
        _ definition: SceneParticleDefinition
    ) -> [SceneParticleSimulationDiagnostic] {
        var result: [SceneParticleSimulationDiagnostic] = []
        func add(_ kind: SceneParticleSimulationDiagnosticKind, _ name: String) {
            let value = SceneParticleSimulationDiagnostic(kind: kind, componentName: name)
            if !result.contains(value) { result.append(value) }
        }
        for emitter in definition.emitters where emitter.audioResponse.isEnabled {
            add(
                emitter.boundedAudioResponsePlan == nil
                    ? .audioResponseIgnored : .audioResponseBounded,
                "emitter"
            )
        }
        for value in definition.operators where value.audioResponse.isEnabled {
            add(
                value.hasBoundedAudioResponse
                    ? .audioResponseBounded : .audioResponseIgnored,
                "operator"
            )
            if case .turbulence = value.kind, !value.hasBoundedAudioResponse {
                add(.unsupportedOperator, "turbulence")
            }
        }
        for initializer in definition.initializers
        where initializer.turbulentVelocity?.audioResponse.isEnabled == true {
            let supported = initializer.turbulentVelocity.flatMap {
                SceneParticleAudioResponsePlan($0.audioResponse)
            } != nil
            add(
                supported ? .audioResponseBounded : .audioResponseIgnored,
                "turbulentvelocityrandom"
            )
            if !supported { add(.unsupportedInitializer, "turbulentvelocityrandom") }
        }
        return result
    }
}

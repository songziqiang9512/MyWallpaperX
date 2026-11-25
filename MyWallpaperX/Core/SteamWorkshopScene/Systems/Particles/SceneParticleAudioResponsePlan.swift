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

/// The prepared response chooses peak/smoothstep or mean/linear sampling.
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
    private let usesPeakResponse: Bool

    nonisolated init?(_ declaration: SceneParticleAudioResponse, usesPeakResponse: Bool = false) {
        guard let mode = declaration.mode,
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
        guard exponent.isFinite, exponent > 0,
              usesPeakResponse || exponent <= 16 else { return nil }

        let first = declaration.frequencyStart ?? 0
        let last = declaration.frequencyEnd ?? 1
        guard (0..<SceneParticleAudioInput.bandCount).contains(first),
              (0..<SceneParticleAudioInput.bandCount).contains(last) else { return nil }

        self.channel = channel
        self.bounds = bounds
        self.exponent = exponent
        self.frequencies = min(first, last) ... max(first, last)
        self.usesPeakResponse = usesPeakResponse
    }

    nonisolated func evaluate(_ input: SceneParticleAudioInput) -> Double {
        evaluate(input, countSelected: false).response
    }

#if DEBUG
    nonisolated func evaluateForExecutionObservation(
        _ input: SceneParticleAudioInput
    ) -> (response: Double, selectedNonZeroInputCount: Int) {
        evaluate(input, countSelected: true)
    }
#endif

    @inline(__always)
    private nonisolated func evaluate(
        _ input: SceneParticleAudioInput, countSelected: Bool
    ) -> (response: Double, selectedNonZeroInputCount: Int) {
        var level = 0.0
        var selectedNonZeroInputCount = 0
        for index in frequencies {
            let band: Double
            switch channel {
            case .left:
                let value = input.left[index]
                band = Double(value)
                if countSelected && value > 0 { selectedNonZeroInputCount += 1 }
            case .right:
                let value = input.right[index]
                band = Double(value)
                if countSelected && value > 0 { selectedNonZeroInputCount += 1 }
            case .center:
                let left = input.left[index]
                let right = input.right[index]
                band = Double(left) + Double(right)
                if countSelected {
                    if left > 0 { selectedNonZeroInputCount += 1 }
                    if right > 0 { selectedNonZeroInputCount += 1 }
                }
            }
            level = usesPeakResponse ? max(level, band) : level + band
        }
        let channelCount = channel == .center ? 2 : 1
        let count = usesPeakResponse ? channelCount : frequencies.count * channelCount
        let normalized = min(max(
            (level / Double(count) - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound),
            0
        ), 1)
        let base = usesPeakResponse ? min(normalized * normalized * (3 - 2 * normalized), 1) : normalized
        return (pow(base, exponent), selectedNonZeroInputCount)
    }
}

nonisolated enum SceneParticleAudioComponentKind: String, Hashable, Sendable {
    case emitter
    case initializer
    case `operator`
}

/// Payload-free proof that one prepared particle component evaluated its own
/// authored band selection against a non-silent typed publication.
#if DEBUG
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
#endif

nonisolated extension SceneParticleEmitter {
    /// Audio emission currently admits the common root Sphere/Box rate profile only.
    /// Delay, duration, periodic, burst, Layer Image and unknown flag interactions remain
    /// fail closed until they receive their own timing contracts.
    var boundedAudioResponsePlan: SceneParticleAudioResponsePlan? {
        guard let plan = SceneParticleAudioResponsePlan(audioResponse, usesPeakResponse: true) else { return nil }
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

nonisolated extension SceneParticleTurbulentVelocity {
    var peakAudioResponsePlan: SceneParticleAudioResponsePlan? {
        SceneParticleAudioResponsePlan(audioResponse, usesPeakResponse: true)
    }
}

nonisolated extension SceneParticleDefinition {
    var hasBoundedAudioConsumer: Bool {
        emitters.contains { $0.boundedAudioResponsePlan != nil }
            || initializers.contains {
                $0.turbulentVelocity.flatMap {
                    $0.peakAudioResponsePlan
                } != nil
            }
            || operators.contains { value in
                value.hasBoundedAudioResponse
            }
    }
}

nonisolated extension SceneParticleOperator {
    var hasBoundedAudioResponse: Bool {
        switch kind {
        case .turbulence:
            SceneParticleAudioResponsePlan(audioResponse, usesPeakResponse: true) != nil
        case .vortex:
            vortexPlan != nil && SceneParticleAudioResponsePlan(audioResponse) != nil
        default:
            false
        }
    }

    var hasBoundedVortexExecution: Bool {
        guard vortexPlan != nil else { return false }
        return !audioResponse.isEnabled || hasBoundedAudioResponse
    }
}

#if DEBUG
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
                $0.peakAudioResponsePlan
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
#endif

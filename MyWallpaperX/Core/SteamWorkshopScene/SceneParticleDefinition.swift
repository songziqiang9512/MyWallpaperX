import Foundation

nonisolated enum SceneParticleNumericValue: Codable, Equatable, Sendable {
    case scalar(Double)
    case vector([Double])

    nonisolated var scalarValue: Double? {
        guard case let .scalar(value) = self else { return nil }
        return value
    }

    nonisolated var vectorValue: [Double]? {
        guard case let .vector(value) = self else { return nil }
        return value
    }
}

nonisolated struct SceneParticleSystemFlags: Equatable, Sendable {
    let rawValue: Int

    nonisolated var isWorldSpace: Bool { rawValue & 1 != 0 }
    nonisolated var disablesFrameBlending: Bool { rawValue & 2 != 0 }
    nonisolated var usesPerspective: Bool { rawValue & 4 != 0 }
}

nonisolated enum SceneParticleEmitterKind: Equatable, Sendable {
    case sphereRandom
    case boxRandom
    case unsupported(String)
}

nonisolated struct SceneParticleEmitter: Equatable, Sendable {
    let id: Int?
    let kind: SceneParticleEmitterKind
    let origin: SceneParticleNumericValue?
    let directions: SceneParticleNumericValue?
    let sign: SceneParticleNumericValue?
    let distanceMinimum: SceneParticleNumericValue?
    let distanceMaximum: SceneParticleNumericValue?
    let rate: Double?
    let instantaneousCount: Int?
    let speedMinimum: Double?
    let speedMaximum: Double?
    let duration: Double?
    let controlPoint: Int?
    let audioProcessingMode: Int?
    let audioAmount: Double?
    let audioExponent: Double?
    let audioFrequency: SceneParticleNumericValue?
    let audioProcessingBounds: SceneParticleNumericValue?
    let rawFlags: Int

    nonisolated var limitsToOnePerFrame: Bool { rawFlags & 1 != 0 }
}

nonisolated enum SceneParticleInitializerKind: Equatable, Sendable {
    case lifetime
    case size
    case velocity
    case color
    case alpha
    case rotation
    case angularVelocity
    case turbulentVelocity
    case unsupported(String)
}

nonisolated struct SceneParticleTurbulentVelocity: Equatable, Sendable {
    let forward: SceneParticleNumericValue?
    let right: SceneParticleNumericValue?
    let up: SceneParticleNumericValue?
    let offset: Double?
    let phaseMaximum: Double?
    let scale: Double?
    let speedMinimum: Double?
    let speedMaximum: Double?
    let timeScale: Double?
    let audioProcessingMode: Int?
    let audioAmount: Double?
    let audioExponent: Double?
    let audioFrequency: SceneParticleNumericValue?
    let audioProcessingBounds: SceneParticleNumericValue?
}

nonisolated struct SceneParticleInitializer: Equatable, Sendable {
    let id: Int?
    let kind: SceneParticleInitializerKind
    let minimum: SceneParticleNumericValue?
    let maximum: SceneParticleNumericValue?
    let exponent: Double?
    let turbulentVelocity: SceneParticleTurbulentVelocity?
}

nonisolated enum SceneParticleOperatorKind: Equatable, Sendable {
    case movement
    case alphaFade
    case alphaChange
    case sizeChange
    case colorChange
    case angularMovement
    case oscillatePosition
    case oscillateAlpha
    case oscillateSize
    case controlPointAttract
    case turbulence
    case vortex
    case unsupported(String)
}

nonisolated struct SceneParticleOperator: Equatable, Sendable {
    let id: Int?
    let kind: SceneParticleOperatorKind
    let rawFlags: Int
    let gravity: SceneParticleNumericValue?
    let drag: Double?
    let force: SceneParticleNumericValue?
    let fadeInTime: Double?
    let fadeOutTime: Double?
    let startTime: Double?
    let endTime: Double?
    let startValue: SceneParticleNumericValue?
    let endValue: SceneParticleNumericValue?
    let frequencyMinimum: Double?
    let frequencyMaximum: Double?
    let scaleMinimum: SceneParticleNumericValue?
    let scaleMaximum: SceneParticleNumericValue?
    let phaseMinimum: Double?
    let phaseMaximum: Double?
    let mask: SceneParticleNumericValue?
    let blendInStart: Double?
    let blendInEnd: Double?
    let blendOutStart: Double?
    let blendOutEnd: Double?
    let controlPoint: Int?
    let origin: SceneParticleNumericValue?
    let scale: SceneParticleNumericValue?
    let threshold: Double?
    let speedMinimum: Double?
    let speedMaximum: Double?
    let audioProcessingMode: Int?
    let audioProcessingBounds: SceneParticleNumericValue?
}

nonisolated enum SceneParticleRendererKind: Equatable, Sendable {
    case sprite
    case spriteTrail
    case rope
    case ropeTrail
    case unsupported(String)
}

nonisolated struct SceneParticleRenderer: Equatable, Sendable {
    let id: Int?
    let kind: SceneParticleRendererKind
    let orientation: String?
    let axis: SceneParticleNumericValue?
    let rawFlags: Int
    let length: Double?
    let minimumLength: Double?
    let maximumLength: Double?
    let segments: Int?
    let subdivision: Double?

    nonisolated var isWorldSpace: Bool { rawFlags & 1 != 0 }
}

nonisolated struct SceneParticleControlPoint: Equatable, Sendable {
    let id: Int?
    let rawFlags: Int
    let offset: SceneParticleNumericValue?
    let angles: SceneParticleNumericValue?

    nonisolated var followsPointer: Bool { rawFlags & 1 != 0 }
    nonisolated var isWorldSpace: Bool { rawFlags & 2 != 0 }
}

nonisolated struct SceneParticleChild: Equatable, Sendable {
    let id: Int?
    let path: String?
    let type: String?
    let maximumCount: Int?
    let controlPointStartIndex: Int?
    let probability: Double?
    let origin: SceneParticleNumericValue?
    let scale: SceneParticleNumericValue?
    let angles: SceneParticleNumericValue?
    let rawFlags: Int
}

nonisolated enum SceneParticleDiagnosticKind: String, Equatable, Sendable {
    case missingRequiredField
    case malformedComponent
    case unsupportedEmitter
    case unsupportedInitializer
    case unsupportedOperator
    case unsupportedRenderer
}

nonisolated struct SceneParticleDiagnostic: Equatable, Sendable {
    let kind: SceneParticleDiagnosticKind
    let path: String
    let componentName: String?
}

nonisolated struct SceneParticleDefinition: Equatable, Sendable {
    let materialPath: String?
    let maximumCount: Int?
    let startTime: Double?
    let flags: SceneParticleSystemFlags
    let animationMode: String?
    let sequenceMultiplier: Double?
    let emitters: [SceneParticleEmitter]
    let initializers: [SceneParticleInitializer]
    let operators: [SceneParticleOperator]
    let renderers: [SceneParticleRenderer]
    let rendererWasImplicit: Bool
    let controlPoints: [SceneParticleControlPoint]
    let children: [SceneParticleChild]
    let diagnostics: [SceneParticleDiagnostic]
}

nonisolated struct SceneParticleBoundValue: Codable, Equatable, Sendable {
    let value: SceneParticleNumericValue?
    let userPropertyKey: String?
    let hasScript: Bool
    let hasAnimation: Bool
}

nonisolated struct SceneParticleInstanceOverride: Codable, Equatable, Sendable {
    let id: Int?
    let alpha: SceneParticleBoundValue?
    let size: SceneParticleBoundValue?
    let lifetime: SceneParticleBoundValue?
    let rate: SceneParticleBoundValue?
    let speed: SceneParticleBoundValue?
    let count: SceneParticleBoundValue?
    let brightness: SceneParticleBoundValue?
    let color: SceneParticleBoundValue?
    let normalizedColor: SceneParticleBoundValue?
    let controlPoints: [Int: SceneParticleBoundValue]
    let controlPointAngles: [Int: SceneParticleBoundValue]
}

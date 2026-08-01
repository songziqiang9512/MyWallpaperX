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
    nonisolated var disablesColorOverrides: Bool { rawValue & 8 != 0 }
    nonisolated var disablesSpeedOverrides: Bool { rawValue & 16 != 0 }
    nonisolated var disablesCountOverrides: Bool { rawValue & 32 != 0 }
    nonisolated var disablesLifetimeOverrides: Bool { rawValue & 64 != 0 }
    nonisolated var disablesSizeOverrides: Bool { rawValue & 128 != 0 }
}

nonisolated enum SceneParticleEmitterKind: Equatable, Sendable {
    case sphereRandom
    case boxRandom
    case layerImage
    case unsupported(String)
}

/// 粒子组件的 audio response 声明。
///
/// 粒子与 effect 是两套独立 schema，不能混用字段名：effect 侧走
/// `audiobounds`/`audioamount`/`audioexponent` 加 `frequencymin`/`frequencymax`
/// 的 shader constant，粒子侧只有下面这一组 `audioprocessing*` 字段，且**没有**
/// amount。45 样本语料中启用 audio 的 11 处粒子组件全部只出现
/// `audioprocessingmode`（11）、`audioprocessingbounds`（6）与
/// `audioprocessingfrequencyend`（1），未出现任何 effect 侧字段名。
///
/// 证据等级：字段名来自真实样本与第三方播放器 parser 交叉验证；
/// **默认值与求值公式官方均未公开**，因此这里只做 loss-preserving 保存，
/// 不内置默认值、不做求值。升级到执行所缺的证据见粒子组件覆盖表 E15。
nonisolated struct SceneParticleAudioResponse: Equatable, Sendable {
    let mode: Int?
    let bounds: SceneParticleNumericValue?
    let exponent: Double?
    let frequencyStart: Int?
    let frequencyEnd: Int?

    static let none = SceneParticleAudioResponse(
        mode: nil,
        bounds: nil,
        exponent: nil,
        frequencyStart: nil,
        frequencyEnd: nil
    )

    /// 作者是否启用。`mode` 缺省或 0 表示关闭。
    nonisolated var isEnabled: Bool { (mode ?? 0) != 0 }
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
    let audioResponse: SceneParticleAudioResponse
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
    let phaseMinimum: Double?
    let phaseMaximum: Double?
    let scale: Double?
    let speedMinimum: Double?
    let speedMaximum: Double?
    let timeScale: Double?
    let audioResponse: SceneParticleAudioResponse
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
    let timeScale: Double?
    let threshold: Double?
    let speedMinimum: Double?
    let speedMaximum: Double?
    let audioResponse: SceneParticleAudioResponse

    nonisolated var isWorldSpaceMovement: Bool {
        kind == .movement && rawFlags & 1 != 0
    }
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
    let fadesAlpha: Bool?
    let fadesSize: Bool?
    let uvScale: Double?
    let smoothsUV: Bool?
    let scrollsUV: Bool?
    let hasMalformedFields: Bool
    let unsupportedFieldNames: [String]

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

    nonisolated var isStaticZeroScalar: Bool {
        guard !hasScript, !hasAnimation,
              let scalar = value?.scalarValue,
              scalar.isFinite else {
            return false
        }
        return scalar <= 0
    }
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

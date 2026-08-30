import Foundation

/// A source-pair proof that an inactive texture-resolution uniform only
/// normalizes coordinates consumed by one different, active texture slot.
nonisolated struct SceneAuthoredShaderNeutralTextureResolutionFact: Hashable {
    let resolutionSlot: Int
    let coordinateTextureSlot: Int
    let varyingName: String
    let sourceComponents: String
    let targetComponents: String

    var resolutionUniformName: String {
        "g_Texture\(resolutionSlot)Resolution"
    }
}

nonisolated struct SceneAuthoredShaderFrontendDiagnostic: Equatable {
    enum Code: String {
        case invalidEncoding
        case sourceTooLarge
        case tokenBudgetExceeded
        case unterminatedComment
        case unterminatedDirective
        case unsupportedDirective
        case malformedDefine
        case invalidToken
        case unbalancedDelimiter
        case unsupportedDeclaration
        case duplicateDeclaration
        case stageLinkMismatch
        case missingMain
        case duplicateMain
        case unsupportedControlFlow
        case dynamicLoop
        case loopBudgetExceeded
        case recursiveFunction
        case unsupportedAttribute
        case unsupportedSampler
        case unsupportedType
        case invalidUniformLayout
    }

    let code: Code
    let message: String
    let stage: SceneShaderContract.StageKind?
    let line: Int?
    let column: Int?
}

/// One stage-qualified immutable scalar producer. The executable integer and
/// Float32 bits are both retained: admission consumes the integer while cache
/// and diagnostic owners can distinguish values whose authored encodings differ.
nonisolated struct SceneAuthoredShaderExactScalarFact: Codable, Hashable, Sendable {
    let stage: SceneShaderContract.StageKind
    let uniformName: String
    let producerName: String
    let value: Int
    let float32BitPattern: UInt32
    let producerValueKind: String
    let producerBindingKeys: [String]
    let shaderBindingKeys: [String]
    let sourcePath: String
    let declarationLine: Int
}

/// Exact scalar facts proven from the resolved runtime producer domain. These
/// facts admit bounded control flow only; the Metal emitter never rewrites or
/// clamps the authored uniform from this projection.
nonisolated struct SceneAuthoredShaderRuntimeLoopBounds: Codable, Hashable, Sendable {
    let vertex: [String: SceneAuthoredShaderExactScalarFact]
    let fragment: [String: SceneAuthoredShaderExactScalarFact]

    static let none = Self(vertex: [:], fragment: [:])

    func values(
        for stage: SceneShaderContract.StageKind
    ) -> [String: SceneAuthoredShaderExactScalarFact] {
        switch stage {
        case .vertex: vertex
        case .fragment: fragment
        }
    }

    /// Test-only/source-frontend convenience. Production material compilation
    /// publishes fully sourced facts through the resolved material resolver.
    init(vertex: [String: Int], fragment: [String: Int]) {
        func facts(
            _ values: [String: Int],
            stage: SceneShaderContract.StageKind
        ) -> [String: SceneAuthoredShaderExactScalarFact] {
            values.mapValues { value in
                .init(
                    stage: stage,
                    uniformName: "test",
                    producerName: "test",
                    value: value,
                    float32BitPattern: Float(value).bitPattern,
                    producerValueKind: "test",
                    producerBindingKeys: [],
                    shaderBindingKeys: [],
                    sourcePath: "test",
                    declarationLine: 0
                )
            }
        }
        self.vertex = Dictionary(uniqueKeysWithValues: facts(vertex, stage: .vertex).map {
            ($0.key, .init(
                stage: $0.value.stage,
                uniformName: $0.key,
                producerName: $0.key,
                value: $0.value.value,
                float32BitPattern: $0.value.float32BitPattern,
                producerValueKind: $0.value.producerValueKind,
                producerBindingKeys: [], shaderBindingKeys: [],
                sourcePath: "test", declarationLine: 0
            ))
        })
        self.fragment = Dictionary(uniqueKeysWithValues: facts(fragment, stage: .fragment).map {
            ($0.key, .init(
                stage: $0.value.stage,
                uniformName: $0.key,
                producerName: $0.key,
                value: $0.value.value,
                float32BitPattern: $0.value.float32BitPattern,
                producerValueKind: $0.value.producerValueKind,
                producerBindingKeys: [], shaderBindingKeys: [],
                sourcePath: "test", declarationLine: 0
            ))
        })
    }

    init(
        vertexFacts: [String: SceneAuthoredShaderExactScalarFact],
        fragmentFacts: [String: SceneAuthoredShaderExactScalarFact]
    ) {
        vertex = vertexFacts
        fragment = fragmentFacts
    }
}

nonisolated enum SceneAuthoredShaderValueType: String, CaseIterable, Codable, Hashable, Sendable {
    case bool
    case int
    case uint
    case float
    case int2
    case int3
    case int4
    case uint2
    case uint3
    case uint4
    case float2
    case float3
    case float4
    case float2x2
    case float3x3
    case float4x4

    init?(authoredName: String) {
        let mappings: [String: Self] = [
            "bool": .bool,
            "int": .int,
            "uint": .uint,
            "float": .float,
            "ivec2": .int2,
            "ivec3": .int3,
            "ivec4": .int4,
            "uvec2": .uint2,
            "uvec3": .uint3,
            "uvec4": .uint4,
            "vec2": .float2,
            "vec3": .float3,
            "vec4": .float4,
            "mat2": .float2x2,
            "mat3": .float3x3,
            "mat4": .float4x4,
            "float2": .float2,
            "float3": .float3,
            "float4": .float4,
        ]
        guard let value = mappings[authoredName] else { return nil }
        self = value
    }

    var metalName: String { rawValue }

    var alignment: Int {
        switch self {
        case .bool, .int, .uint, .float:
            4
        case .int2, .uint2, .float2, .float2x2:
            8
        case .int3, .int4, .uint3, .uint4, .float3, .float4,
             .float3x3, .float4x4:
            16
        }
    }

    var byteSize: Int {
        switch self {
        case .bool, .int, .uint, .float:
            4
        case .int2, .uint2, .float2:
            8
        case .int3, .int4, .uint3, .uint4, .float3, .float4:
            16
        case .float2x2:
            16
        case .float3x3:
            48
        case .float4x4:
            64
        }
    }
}

nonisolated struct SceneAuthoredShaderUniformLayout: Codable, Equatable, Hashable, Sendable {
    struct Field: Codable, Equatable, Hashable, Sendable {
        /// Metal ABI name. It is stage-qualified only when the authored name
        /// is declared by both stages and therefore denotes two stage-local
        /// constant bindings.
        let name: String
        let authoredName: String
        let stage: SceneShaderContract.StageKind?
        let type: SceneAuthoredShaderValueType
        /// Fixed-size host arrays keep their element type while preserving
        /// the authored declaration shape in the uniform ABI.
        let arrayCount: Int?
        let offset: Int

        init(
            name: String,
            authoredName: String? = nil,
            stage: SceneShaderContract.StageKind? = nil,
            type: SceneAuthoredShaderValueType,
            arrayCount: Int? = nil,
            offset: Int
        ) {
            self.name = name
            self.authoredName = authoredName ?? name
            self.stage = stage
            self.type = type
            self.arrayCount = arrayCount
            self.offset = offset
        }

        var storageByteSize: Int {
            type.byteSize * (arrayCount ?? 1)
        }
    }

    let fields: [Field]
    let byteSize: Int
}

nonisolated struct SceneAuthoredShaderUniformDeclaration {
    let authoredName: String
    let fieldName: String
    let type: SceneAuthoredShaderValueType
    let arrayCount: Int?
    let stage: SceneShaderContract.StageKind

    static func fieldNames(
        in declarations: [Self],
        for stage: SceneShaderContract.StageKind
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: declarations.filter {
            $0.stage == stage
        }.map { ($0.authoredName, $0.fieldName) })
    }
}

nonisolated enum SceneShaderColorTransfer: Codable, Equatable, Hashable, Sendable {
    case passthrough(textureSlot: Int)
    /// Scalar interpolation of two or more sampled colors. Finalization proves
    /// that every listed slot carries one common resolved representation.
    case interpolatedColor(textureSlots: [Int])
    case straightAlphaPreserving(textureSlot: Int)
    case straightAlpha(textureSlot: Int)
    /// A single straight-RGBA source is filtered with bounded whole-vector
    /// affine math, clamped to the UNorm attachment domain, then premultiplied.
    case straightAlphaUNorm(textureSlot: Int)
    /// One resolved color source enters authored math in straight RGB while
    /// the authored terminal write proves opaque alpha.
    case opaqueFromStraightColor(textureSlot: Int)
    case independentAlphaSignal(textureSlot: Int)
    case independentAlphaSignalPreserving(textureSlot: Int)
    case independentAlphaSignalCompositing(signalSlot: Int, colorSlot: Int)
    /// Authored source generates straight RGBA without sampling a color
    /// carrier. Both shader backends premultiply the terminal value exactly
    /// once before the shared compositor boundary.
    case generatedStraightAlpha
    case premultipliedAlpha
    case opaque
    case unresolved
}

nonisolated struct SceneAuthoredShaderProgram: Codable {
    enum Backend: String, Codable, Equatable, Hashable, Sendable {
        case boundedSwift
        case genericCompilerArtifact
    }

    struct TextureBinding: Codable, Equatable, Hashable, Sendable {
        enum ChannelUse: String, Codable, Equatable, Hashable, Sendable {
            /// Every active sample result observes only red (`.r` / `.x`).
            case redOnly
            /// Every active sample result observes only green (`.g` / `.y`).
            case greenOnly
            /// Active sample results observe a nonempty subset of red/green,
            /// with the aggregate use requiring both stored components.
            case redGreenOnly
            /// At least one active sample observes the complete sampled vector.
            /// Typed R/RG graph resources may separately prove the format's
            /// deterministic Metal expansion for unstored components.
            case wholeVector
            /// The bounded frontend cannot prove a direct sampled-vector use.
            case unproven
        }

        let name: String
        let slot: Int
        let channelUse: ChannelUse
    }

    enum FragmentOutputChannelUse: String, Codable, Equatable, Hashable, Sendable {
        /// Every reachable fragment exit defines the attachment channels through
        /// one root-level, unconditional whole-output write. The historical case
        /// name is retained because it participates in stable shader identities.
        case redDefined
        case unproven
    }

    let metalSource: String
    let vertexFunctionName: String
    let fragmentFunctionName: String
    let uniformBufferIndex: Int
    let uniformLayout: SceneAuthoredShaderUniformLayout
    let textureBindings: [TextureBinding]
    let staticLoopWork: Int
    let colorTransfer: SceneShaderColorTransfer
    let fragmentOutputChannelUse: FragmentOutputChannelUse
    let backend: Backend

    func channelUse(forTextureSlot slot: Int) -> TextureBinding.ChannelUse? {
        textureBindings.first(where: { $0.slot == slot })?.channelUse
    }

    init(
        metalSource: String,
        vertexFunctionName: String,
        fragmentFunctionName: String,
        uniformBufferIndex: Int = 0,
        uniformLayout: SceneAuthoredShaderUniformLayout,
        textureBindings: [TextureBinding],
        staticLoopWork: Int,
        colorTransfer: SceneShaderColorTransfer,
        fragmentOutputChannelUse: FragmentOutputChannelUse = .unproven,
        backend: Backend = .boundedSwift
    ) {
        self.metalSource = metalSource
        self.vertexFunctionName = vertexFunctionName
        self.fragmentFunctionName = fragmentFunctionName
        self.uniformBufferIndex = uniformBufferIndex
        self.uniformLayout = uniformLayout
        self.textureBindings = textureBindings
        self.staticLoopWork = staticLoopWork
        self.colorTransfer = colorTransfer
        self.fragmentOutputChannelUse = fragmentOutputChannelUse
        self.backend = backend
    }

    func offscreenSize(viewportSize: CGSize) -> CGSize? {
        guard viewportSize.width.isFinite,
              viewportSize.height.isFinite,
              viewportSize.width > 0,
              viewportSize.height > 0 else {
            return nil
        }
        return CGSize(
            width: max(1, viewportSize.width.rounded(.up)),
            height: max(1, viewportSize.height.rounded(.up))
        )
    }
}

nonisolated struct SceneAuthoredShaderFrontendOutput {
    let program: SceneAuthoredShaderProgram?
    let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
}

nonisolated struct SceneAuthoredShaderToken: Hashable {
    enum Kind: Hashable {
        case identifier
        case number
        case symbol
    }

    let kind: Kind
    let text: String
    let line: Int
    let column: Int
}

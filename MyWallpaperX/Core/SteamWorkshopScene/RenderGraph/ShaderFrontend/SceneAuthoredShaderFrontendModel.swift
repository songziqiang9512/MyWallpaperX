import Foundation

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

/// Upper bounds proven from the resolved runtime producer domain. These facts
/// admit bounded control flow only; the Metal emitter never rewrites or clamps
/// the authored uniform from this projection.
nonisolated struct SceneAuthoredShaderRuntimeLoopBounds: Sendable {
    let vertex: [String: Int]
    let fragment: [String: Int]

    static let none = Self(vertex: [:], fragment: [:])

    func values(for stage: SceneShaderContract.StageKind) -> [String: Int] {
        switch stage {
        case .vertex: vertex
        case .fragment: fragment
        }
    }
}

nonisolated enum SceneAuthoredShaderValueType: String, CaseIterable, Hashable, Sendable {
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

nonisolated struct SceneAuthoredShaderUniformLayout: Equatable, Hashable, Sendable {
    struct Field: Equatable, Hashable, Sendable {
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

nonisolated enum SceneShaderColorTransfer: Equatable, Hashable, Sendable {
    case passthrough(textureSlot: Int)
    /// Scalar interpolation of two or more sampled colors. Finalization proves
    /// that every listed slot carries one common resolved representation.
    case interpolatedColor(textureSlots: [Int])
    case straightAlphaPreserving(textureSlot: Int)
    case straightAlpha(textureSlot: Int)
    /// A single straight-RGBA source is filtered with bounded whole-vector
    /// affine math, clamped to the UNorm attachment domain, then premultiplied.
    case straightAlphaUNorm(textureSlot: Int)
    case independentAlphaSignal(textureSlot: Int)
    case independentAlphaSignalPreserving(textureSlot: Int)
    case independentAlphaSignalCompositing(signalSlot: Int, colorSlot: Int)
    case premultipliedAlpha
    case opaque
    case unresolved
}

nonisolated struct SceneAuthoredShaderProgram {
    enum Backend: String, Equatable, Hashable, Sendable {
        case boundedSwift
        case genericCompilerArtifact
    }

    struct TextureBinding: Equatable, Hashable, Sendable {
        enum ChannelUse: String, Equatable, Hashable, Sendable {
            /// Every active sample result is immediately projected to `.r`.
            case redOnly
            /// The bounded frontend cannot prove a single stored component.
            case unproven
        }

        let name: String
        let slot: Int
        let channelUse: ChannelUse
    }

    enum FragmentOutputChannelUse: String, Equatable, Hashable, Sendable {
        /// Every reachable fragment exit defines red through one root-level,
        /// unconditional whole-output write.
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

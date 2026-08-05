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
        let name: String
        let type: SceneAuthoredShaderValueType
        let offset: Int
    }

    let fields: [Field]
    let byteSize: Int
}

nonisolated enum SceneShaderColorTransfer: Equatable, Hashable, Sendable {
    case passthrough(textureSlot: Int)
    case straightAlpha(textureSlot: Int)
    case opaque
    case unresolved
}

nonisolated struct SceneAuthoredShaderProgram {
    struct TextureBinding: Equatable, Hashable, Sendable {
        let name: String
        let slot: Int
    }

    let metalSource: String
    let vertexFunctionName: String
    let fragmentFunctionName: String
    let uniformLayout: SceneAuthoredShaderUniformLayout
    let textureBindings: [TextureBinding]
    let staticLoopWork: Int
    let colorTransfer: SceneShaderColorTransfer

    init(
        metalSource: String,
        vertexFunctionName: String,
        fragmentFunctionName: String,
        uniformLayout: SceneAuthoredShaderUniformLayout,
        textureBindings: [TextureBinding],
        staticLoopWork: Int,
        colorTransfer: SceneShaderColorTransfer
    ) {
        self.metalSource = metalSource
        self.vertexFunctionName = vertexFunctionName
        self.fragmentFunctionName = fragmentFunctionName
        self.uniformLayout = uniformLayout
        self.textureBindings = textureBindings
        self.staticLoopWork = staticLoopWork
        self.colorTransfer = colorTransfer
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

nonisolated struct SceneAuthoredShaderToken: Equatable {
    enum Kind: Equatable {
        case identifier
        case number
        case symbol
    }

    let kind: Kind
    let text: String
    let line: Int
    let column: Int
}

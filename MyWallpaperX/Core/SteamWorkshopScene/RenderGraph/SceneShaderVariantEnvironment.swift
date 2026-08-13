import CryptoKit
import Foundation

nonisolated struct SceneShaderSourceDependency: Codable, Equatable, Sendable {
    let relativePath: String
    let rawSHA256: String
}

nonisolated struct SceneShaderSourceMapEntry: Codable, Equatable, Sendable {
    let outputLine: Int
    let sourcePath: String
    let sourceLine: Int
}

nonisolated struct SceneShaderActiveAnnotation: Codable, Equatable, Sendable {
    let sourcePath: String
    let annotation: SceneShaderContract.Annotation
}

nonisolated struct SceneShaderActiveDeclaration: Codable, Equatable, Sendable {
    let sourcePath: String
    let declaration: SceneShaderContract.Declaration
}

nonisolated struct SceneShaderPreparedSource: Codable, Equatable, Sendable {
    let frontendSchemaVersion: Int
    let sourceDialect: SceneShaderSourceDialect
    let backend: SceneShaderBackendIdentity
    let stage: SceneShaderContract.StageKind
    let rootRelativePath: String
    let source: String
    let sourceMap: [SceneShaderSourceMapEntry]
    let activeAnnotations: [SceneShaderActiveAnnotation]
    let activeDeclarations: [SceneShaderActiveDeclaration]
    let dependencies: [SceneShaderSourceDependency]
    let dependencySHA256: String
    let variantSHA256: String
    let preparedSHA256: String
}

nonisolated struct SceneShaderColorContract: Codable, Equatable, Hashable, Sendable {
    let framebufferInput: SceneShaderColorRepresentationResolution
    let fragmentOutput: SceneShaderColorRepresentationResolution

    static let unresolvedAuthoredPass = SceneShaderColorContract(
        framebufferInput: .unresolved,
        fragmentOutput: .unresolved
    )

    var isResolved: Bool {
        guard case .resolved = framebufferInput,
              case .resolved = fragmentOutput else { return false }
        return true
    }
}

nonisolated struct SceneShaderPreparedProgram: Codable, Equatable, Sendable {
    let vertex: SceneShaderPreparedSource
    let fragment: SceneShaderPreparedSource
    let colorContract: SceneShaderColorContract
    let cacheKey: String

    var all: [SceneShaderPreparedSource] { [vertex, fragment] }
}

nonisolated enum SceneShaderStableDigest {
    static func hash<T: Encodable>(_ payload: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else {
            preconditionFailure("Scene shader digest payload must be encodable.")
        }
        return hash(data)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum SceneShaderBackendIdentity: String, Codable, Equatable, Sendable {
    case mwxMetal = "mwx-metal"
}

/// Describes the authored input grammar without claiming that it is GLSL,
/// HLSL, or Metal source. Backend translation is a separate identity.
nonisolated enum SceneShaderSourceDialect: String, Codable, Equatable, Sendable {
    case wallpaperEngineGLSLLike = "wallpaper-engine-glsl-like"
}

nonisolated enum SceneShaderMacroValue: Codable, Equatable, Sendable {
    case bare
    case integer(Int64)
    case floatingLiteral(String)
    case tokenSequence(String)

    var expressionValue: Int64? {
        switch self {
        case .bare: 1
        case let .integer(value): value
        case .floatingLiteral, .tokenSequence: nil
        }
    }

    var replacement: String {
        switch self {
        case .bare: "1"
        case let .integer(value): String(value)
        case let .floatingLiteral(value): value
        case let .tokenSequence(value): value
        }
    }

    static func isFloatingLiteral(_ value: String) -> Bool {
        (value.contains(".") || value.contains("e") || value.contains("E"))
            && Double(value)?.isFinite == true
    }
}

nonisolated enum SceneShaderMacroDefinition: Codable, Equatable, Sendable {
    case undefined
    case defined(SceneShaderMacroValue)
}

nonisolated struct SceneShaderMacroBinding: Codable, Equatable, Sendable {
    let name: String
    let definition: SceneShaderMacroDefinition
}

nonisolated enum SceneShaderComboProvenance: String, Codable, Equatable, Sendable {
    /// Material/instance resolution already selected this authored value.
    case explicitResolvedMaterial = "explicit-resolved-material"
    case annotationDefault = "annotation-default"
    case textureReadiness = "texture-readiness"
    case textureFormat = "texture-format"
    case requirementInactive = "requirement-inactive"
    case annotationUndefined = "annotation-undefined"
}

nonisolated struct SceneShaderComboResolution: Codable, Equatable, Sendable {
    let binding: SceneShaderMacroBinding
    let provenance: SceneShaderComboProvenance
    /// True only when the active contract declared this exact authored combo.
    let schemaDeclared: Bool
    /// Slots whose ready/unready fact was checked before accepting this value.
    let validatedTextureSlots: [Int]
}

nonisolated enum SceneShaderEnvironmentRequirement: String, Codable, Equatable, Sendable {
    case backendLanguage = "backend-language"
    case clientVersion = "client-version"
    case platform = "platform"
    case textureFormat = "texture-format"
}

nonisolated enum SceneShaderVariantErrorCode: String, Codable, Equatable, Sendable {
    case invalidIdentifier = "invalid-identifier"
    case invalidValue = "invalid-value"
    case conflictingDefinition = "conflicting-definition"
    case unsupportedEnvironmentDefine = "unsupported-environment-define"
}

nonisolated struct SceneShaderVariantFailure: Error, Codable, Equatable, Sendable {
    let code: SceneShaderVariantErrorCode
    let identifier: String
    let message: String
}

nonisolated struct SceneShaderVariantEnvironment: Codable, Equatable, Sendable {
    static let frontendSchemaVersion = 17

    let sourceDialect: SceneShaderSourceDialect
    let backend: SceneShaderBackendIdentity
    let stage: SceneShaderContract.StageKind
    let environmentDefines: [SceneShaderMacroBinding]
    let comboResolutions: [SceneShaderComboResolution]
    let variantSHA256: String

    var combos: [SceneShaderMacroBinding] {
        comboResolutions.map(\.binding)
    }

    /// The Metal path currently has no evidence-backed authored environment
    /// macro. Non-empty input therefore fails closed instead of pretending that
    /// Metal is HLSL/GLSL or inventing version/platform/format values.
    init(
        stage: SceneShaderContract.StageKind,
        environmentDefines: [SceneShaderMacroBinding] = [],
        combos: [SceneShaderMacroBinding] = []
    ) throws {
        let normalizedEnvironment = try Self.normalized(environmentDefines)
        if let unsupported = normalizedEnvironment.first {
            throw SceneShaderVariantFailure(
                code: .unsupportedEnvironmentDefine,
                identifier: unsupported.name,
                message: "The Metal shader backend has no verified authored environment defines."
            )
        }
        let normalizedCombos = try Self.normalized(combos)
        if let unsupported = normalizedCombos.first(where: { Self.isHostOwned($0.name) }) {
            throw SceneShaderVariantFailure(
                code: .unsupportedEnvironmentDefine,
                identifier: unsupported.name,
                message: "Backend-language and platform macros are host-owned and cannot come from material combos."
            )
        }
        try self.init(
            stage: stage,
            comboResolutions: normalizedCombos.map {
                SceneShaderComboResolution(
                    binding: $0,
                    provenance: .explicitResolvedMaterial,
                    schemaDeclared: false,
                    validatedTextureSlots: []
                )
            }
        )
    }

    init(
        stage: SceneShaderContract.StageKind,
        comboResolutions: [SceneShaderComboResolution]
    ) throws {
        let normalizedResolutions = try Self.normalized(comboResolutions)
        let bindings = normalizedResolutions.map(\.binding)
        if let unsupported = normalizedResolutions.first(where: {
            !Self.hasVerifiedHostResolution($0)
                && Self.unresolvedRequirement(for: $0.binding.name) != nil
        }) {
            throw SceneShaderVariantFailure(
                code: .unsupportedEnvironmentDefine,
                identifier: unsupported.binding.name,
                message: "Version, format, backend and platform macros require a verified host provider."
            )
        }
        sourceDialect = .wallpaperEngineGLSLLike
        backend = .mwxMetal
        self.stage = stage
        environmentDefines = []
        self.comboResolutions = normalizedResolutions
        variantSHA256 = SceneShaderStableDigest.hash(VariantDigestPayload(
            frontendSchemaVersion: Self.frontendSchemaVersion,
            sourceDialect: .wallpaperEngineGLSLLike,
            backend: .mwxMetal,
            stage: stage,
            environmentDefines: [],
            combos: bindings
        ))
    }

    func initialMacroTable() -> [String: SceneShaderMacroValue] {
        var result: [String: SceneShaderMacroValue] = [:]
        for (name, definition) in selectedMacroDefinitions() {
            guard case let .defined(value) = definition else { continue }
            result[name] = value
        }
        return result
    }

    func selectedMacroDefinitions() -> [String: SceneShaderMacroDefinition] {
        var result = Dictionary(uniqueKeysWithValues: (environmentDefines + combos).map {
            ($0.name, $0.definition)
        })
        for name in ["HLSL", "HLSL_SM30", "HLSL_SM40", "HLSL_GS40"] {
            result[name] = .undefined
        }
        return result
    }

    private static func normalized(
        _ bindings: [SceneShaderMacroBinding]
    ) throws -> [SceneShaderMacroBinding] {
        var definitions: [String: SceneShaderMacroDefinition] = [:]
        for binding in bindings {
            try validate(binding)
            if let existing = definitions[binding.name], existing != binding.definition {
                throw conflict(binding.name)
            }
            definitions[binding.name] = binding.definition
        }
        return definitions.keys.sorted().map {
            SceneShaderMacroBinding(name: $0, definition: definitions[$0]!)
        }
    }

    private static func normalized(
        _ resolutions: [SceneShaderComboResolution]
    ) throws -> [SceneShaderComboResolution] {
        var byName: [String: SceneShaderComboResolution] = [:]
        for resolution in resolutions {
            try validate(resolution.binding)
            let slots = Array(Set(resolution.validatedTextureSlots)).sorted()
            guard slots.allSatisfy({ (0 ... 7).contains($0) }) else {
                throw SceneShaderVariantFailure(
                    code: .invalidValue,
                    identifier: resolution.binding.name,
                    message: "Shader texture readiness provenance contains an invalid slot."
                )
            }
            let normalized = SceneShaderComboResolution(
                binding: resolution.binding,
                provenance: resolution.provenance,
                schemaDeclared: resolution.schemaDeclared,
                validatedTextureSlots: slots
            )
            if let existing = byName[resolution.binding.name], existing != normalized {
                throw conflict(resolution.binding.name)
            }
            byName[resolution.binding.name] = normalized
        }
        return byName.keys.sorted().map { byName[$0]! }
    }

    private static func validate(_ binding: SceneShaderMacroBinding) throws {
        guard binding.name.range(
            of: #"^[A-Za-z_][A-Za-z0-9_]*$"#,
            options: .regularExpression
        ) != nil else {
            throw SceneShaderVariantFailure(
                code: .invalidIdentifier,
                identifier: binding.name,
                message: "Shader macro names must preserve a valid, unpadded identifier."
            )
        }
        if case let .defined(.floatingLiteral(value)) = binding.definition,
           !SceneShaderMacroValue.isFloatingLiteral(value) {
            throw SceneShaderVariantFailure(
                code: .invalidValue,
                identifier: binding.name,
                message: "Shader macro floating literal is invalid."
            )
        }
        if case .defined(.tokenSequence) = binding.definition {
            throw SceneShaderVariantFailure(
                code: .invalidValue,
                identifier: binding.name,
                message: "Shader combo values cannot inject source macro token sequences."
            )
        }
    }

    private static func conflict(_ identifier: String) -> SceneShaderVariantFailure {
        SceneShaderVariantFailure(
            code: .conflictingDefinition,
            identifier: identifier,
            message: "Shader macro '\(identifier)' has conflicting definitions or provenance."
        )
    }

    private struct VariantDigestPayload: Encodable {
        let frontendSchemaVersion: Int
        let sourceDialect: SceneShaderSourceDialect
        let backend: SceneShaderBackendIdentity
        let stage: SceneShaderContract.StageKind
        let environmentDefines: [SceneShaderMacroBinding]
        let combos: [SceneShaderMacroBinding]
    }
}

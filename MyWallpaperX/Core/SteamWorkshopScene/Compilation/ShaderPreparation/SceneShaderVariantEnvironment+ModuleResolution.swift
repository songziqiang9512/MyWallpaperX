import Foundation

/// Typed identity for a preparation-time authored shader module. This is not
/// a source or ABI claim: the current bounded outcome contributes no source.
nonisolated enum SceneShaderModuleIdentity: String, Codable, Equatable, Hashable, Sendable {
    case lightingV1 = "LightingV1"
}

nonisolated enum SceneShaderModuleResolutionOutcome: String, Codable, Equatable, Hashable, Sendable {
    case zeroSourceContribution = "zero-source-contribution"
}

/// A module dependency is separate from file dependencies because it records
/// a preparation decision rather than bytes loaded from the authored VFS.
nonisolated struct SceneShaderModuleDependency: Codable, Equatable, Hashable, Sendable {
    let module: SceneShaderModuleIdentity
    let stage: SceneShaderContract.StageKind
    let sourcePath: String
    let sourceLine: Int
    let directiveOrdinal: Int
    let macroEnvironmentSHA256: String
    let outcome: SceneShaderModuleResolutionOutcome
}

nonisolated struct SceneShaderModuleFunctionMacroState: Codable, Equatable, Sendable {
    let name: String
    let parameters: [String]
    let replacement: String
}

/// Canonical identity of the macro table visible at one directive position.
/// Traversal stacks, budgets, paths, ordinals and other runtime state are
/// intentionally excluded because they do not change macro lookup semantics.
nonisolated enum SceneShaderModuleMacroEnvironment {
    private struct ObjectMacro: Encodable {
        let name: String
        let value: SceneShaderMacroValue
    }

    private struct DigestPayload: Encodable {
        let schemaVersion: Int
        let objectMacros: [ObjectMacro]
        let functionMacros: [SceneShaderModuleFunctionMacroState]
    }

    static func digest(
        objectMacros: [String: SceneShaderMacroValue],
        functionMacros: [SceneShaderModuleFunctionMacroState]
    ) -> String {
        let objects = objectMacros.keys.sorted().map {
            ObjectMacro(name: $0, value: objectMacros[$0]!)
        }
        let functions = functionMacros.sorted { $0.name < $1.name }
        return SceneShaderStableDigest.hash(DigestPayload(
            schemaVersion: 1,
            objectMacros: objects,
            functionMacros: functions
        ))
    }
}

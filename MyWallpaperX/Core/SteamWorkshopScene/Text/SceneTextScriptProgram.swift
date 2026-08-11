import Foundation

nonisolated struct SceneTextScriptProgram: Equatable, Sendable {
    nonisolated enum Profile: String, Codable, Equatable, Sendable {
        case ecmaTextUpdateSubset
    }

    nonisolated enum Configuration: Equatable, Sendable {
        case scriptSubset(
            program: SceneTextScriptSubsetProgram,
            properties: [String: SceneJSONValue]
        )
    }

    nonisolated struct Binding: Equatable, Sendable {
        let layerID: Int
        let profile: Profile
        let configuration: Configuration
        let definition: SceneDynamicTargetDefinition

        nonisolated var target: SceneDynamicTarget { definition.target }
    }

    nonisolated struct Diagnostic: Equatable, Sendable {
        enum Code: String {
            case unknownProfile
        }

        let layerID: Int
        let code: Code
        let sourceSHA256: String
    }

    let bindings: [Binding]
    let diagnostics: [Diagnostic]

    nonisolated static let empty = SceneTextScriptProgram(bindings: [], diagnostics: [])
}

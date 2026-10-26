import Foundation

nonisolated struct SceneTextScriptProgram: Equatable, Sendable {
    nonisolated enum Profile: String, Codable, Equatable, Sendable {
        case ecmaTextUpdateSubset
        case ecmaMediaPropertiesChangedSubset
    }

    nonisolated enum MediaProperty: Equatable, Sendable {
        case title
        case artist
    }

    nonisolated enum Configuration: Equatable, Sendable {
        case scriptSubset(
            program: SceneTextScriptSubsetProgram,
            properties: [String: SceneJSONValue]
        )
        case mediaProperties(field: MediaProperty)
    }

    nonisolated struct Binding: Equatable, Sendable {
        let layerID: Int
        let profile: Profile
        let configuration: Configuration
        let definition: SceneDynamicTargetDefinition

        nonisolated var target: SceneDynamicTarget { definition.target }
    }

#if DEBUG
    nonisolated struct Diagnostic: Equatable, Sendable {
        enum Code: String {
            case unknownProfile
        }

        let layerID: Int
        let code: Code
        let sourceSHA256: String
    }
#endif

    let bindings: [Binding]
#if DEBUG
    let diagnostics: [Diagnostic]

    nonisolated static let empty = SceneTextScriptProgram(bindings: [], diagnostics: [])
#else
    nonisolated static let empty = SceneTextScriptProgram(bindings: [])
#endif
}

/// Typed media metadata observed by text scripts. Generation zero means that no
/// media-properties event has been delivered; later generations preserve empty
/// title and artist values as authored event payloads rather than missing input.
nonisolated struct SceneTextMediaPropertiesSnapshot: Equatable, Sendable {
    let title: String
    let artist: String
    let generation: UInt64

    nonisolated static let empty = SceneTextMediaPropertiesSnapshot(
        title: "",
        artist: "",
        generation: 0
    )
}

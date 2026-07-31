import CryptoKit
import Foundation

/// Compiles only the independently verified delayed-loop texture profile.
nonisolated enum SceneTextureAnimationScriptCompiler {
    private static let delayedLoopSourceSHA256 =
        "a21a7d4bf2fefdf0e8694f4c83dcf224ff6f8a95eec94136f399b6a679541a3b"

    nonisolated static func compile(
        layerID: Int,
        definitions: [SceneTextureAnimationScriptDefinition]
    ) -> SceneTextureAnimationPlaybackPlan? {
        guard definitions.count == 1, let definition = definitions.first else { return nil }
        let sourceSHA256 = SHA256.hash(data: Data(definition.source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return compileVerifiedProfile(
            layerID: layerID,
            definition: definition,
            sourceSHA256: sourceSHA256
        )
    }

    /// Hash injection keeps positive fixtures independent of third-party script source.
    nonisolated static func compileVerifiedProfile(
        layerID: Int,
        definition: SceneTextureAnimationScriptDefinition,
        sourceSHA256: String
    ) -> SceneTextureAnimationPlaybackPlan? {
        guard sourceSHA256 == delayedLoopSourceSHA256,
              definition.host == "visible",
              definition.wrapperKeys == ["script", "scriptproperties", "user", "value"],
              definition.user == .string("fireworks"),
              definition.authoredValue == .bool(true),
              Set(definition.properties.keys) == ["initialDelay", "maxDelay", "minDelay"],
              let initialDelay = boundedNumber(definition.properties["initialDelay"]),
              let authoredMaximum = boundedNumber(definition.properties["maxDelay"]),
              let authoredMinimum = boundedNumber(definition.properties["minDelay"]) else {
            return nil
        }
        return SceneTextureAnimationPlaybackPlan(
            layerID: layerID,
            sourceSHA256: sourceSHA256,
            initialDelay: initialDelay,
            minimumDelay: min(authoredMinimum, authoredMaximum),
            maximumDelay: max(authoredMinimum, authoredMaximum)
        )
    }

    nonisolated private static func boundedNumber(_ value: SceneJSONValue?) -> Float? {
        guard let number = value?.numberValue,
              number.isFinite,
              (0 ... 100).contains(number) else {
            return nil
        }
        return Float(number)
    }
}

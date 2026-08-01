import CryptoKit
import Foundation

/// Compiles only the independently verified delayed-loop texture profile.
nonisolated enum SceneTextureAnimationScriptCompiler {
    private static let delayedLoopSourceSHA256 =
        "a21a7d4bf2fefdf0e8694f4c83dcf224ff6f8a95eec94136f399b6a679541a3b"
    private static let timeOfDaySourceSHA256 =
        "152842f1740fe7672fc2275d2eda3b1039da0ab6ee3da02ffab53e4e5de17cbf"

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

    nonisolated static func timeOfDaySchedule(
        definitions: [SceneTextureAnimationScriptDefinition]
    ) -> SceneTimeOfDaySchedule? {
        guard definitions.count == 1, let definition = definitions.first else { return nil }
        let sourceSHA256 = SHA256.hash(data: Data(definition.source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard sourceSHA256 == timeOfDaySourceSHA256 else { return nil }
        return compileTimeOfDaySchedule(definition: definition)
    }

    /// Hash injection keeps positive fixtures independent of third-party script source.
    nonisolated static func compileVerifiedProfile(
        layerID: Int,
        definition: SceneTextureAnimationScriptDefinition,
        sourceSHA256: String
    ) -> SceneTextureAnimationPlaybackPlan? {
        switch sourceSHA256 {
        case delayedLoopSourceSHA256:
            guard definition.host == "visible",
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
                mode: .delayedLoop(
                    initialDelay: initialDelay,
                    minimumDelay: min(authoredMinimum, authoredMaximum),
                    maximumDelay: max(authoredMinimum, authoredMaximum)
                )
            )
        case timeOfDaySourceSHA256:
            guard let schedule = compileTimeOfDaySchedule(definition: definition) else {
                return nil
            }
            return SceneTextureAnimationPlaybackPlan(
                layerID: layerID,
                sourceSHA256: sourceSHA256,
                mode: .timeOfDay(schedule)
            )
        default:
            return nil
        }
    }

    private nonisolated static func compileTimeOfDaySchedule(
        definition: SceneTextureAnimationScriptDefinition
    ) -> SceneTimeOfDaySchedule? {
        guard definition.host == "angles",
              definition.wrapperKeys == ["script", "scriptproperties", "value"],
              definition.user == nil,
              definition.authoredValue == .string("0.00000 -0.00000 0.00000"),
              Set(definition.properties.keys) == ["dayStart", "nightStart"],
              let dayStartHour = integerHour(definition.properties["dayStart"]),
              let nightStartHour = integerHour(definition.properties["nightStart"]),
              dayStartHour < nightStartHour else {
            return nil
        }
        return SceneTimeOfDaySchedule(
            dayStartHour: dayStartHour,
            nightStartHour: nightStartHour
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

    nonisolated private static func integerHour(_ value: SceneJSONValue?) -> Int? {
        guard let number = value?.numberValue,
              number.isFinite,
              number.rounded() == number,
              (0 ... 24).contains(number) else {
            return nil
        }
        return Int(number)
    }
}

import CryptoKit
import Foundation

/// Compiles only independently verified text-script profiles.
///
/// The raw source fingerprint and the complete property shape must both match.
/// Unknown or edited scripts keep their authored fallback text.
nonisolated enum SceneTextScriptCompiler {
    private static let clockSHA256 =
        "ebf5e5f476ec0a0e35c9dd5c77a9691e23468d24b58a465488157c9e026e4912"
    private static let spacedDaySHA256 =
        "dca4b368c3630dec922fd4015afec4962069827b2d45d18af83ff3ab80608f67"
    private static let dateSHA256 =
        "2bca0f3a950267440fe733611caee5481f7d60617b318a78ffd60235e29ce1bb"
    private static let compactDaySHA256 =
        "2fd0e22672675527167908de5535719726f8f07af5b24892ef31adfd412590a7"
    private static let longMonthDateSHA256 =
        "8420e0f255e350654503e24d87a8257dbec560a64ae09524966a5659f5b538cb"
    private static let clockWithPeriodSHA256 =
        "ef8b5597f44146180b337c0c0c732ea2e2d1238a7db561cdeab6ed9106599592"

    nonisolated static func compile(descriptor: SceneRenderDescriptor) -> SceneTextScriptProgram {
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(in: descriptor)
        var bindings: [SceneTextScriptProgram.Binding] = []
        var diagnostics: [SceneTextScriptProgram.Diagnostic] = []

        for layer in descriptor.layers where
            layer.contentKind == "text" && visibleLayerIDs.contains(layer.id) {
            guard let script = layer.textScript else { continue }
            let sourceSHA256 = sha256(script.source)
            guard let profile = profile(sourceSHA256: sourceSHA256) else {
                diagnostics.append(.init(
                    layerID: layer.id,
                    code: .unknownProfile,
                    sourceSHA256: sourceSHA256
                ))
                continue
            }
            guard let configuration = configuration(
                profile: profile,
                properties: script.properties
            ) else {
                diagnostics.append(.init(
                    layerID: layer.id,
                    code: .invalidProperties,
                    sourceSHA256: sourceSHA256
                ))
                continue
            }
            bindings.append(.init(
                layerID: layer.id,
                profile: profile,
                configuration: configuration,
                definition: .init(
                    target: .text(layerID: layer.id, field: .content),
                    valueType: .string,
                    authoredValue: .string(layer.text ?? "")
                )
            ))
        }
        return SceneTextScriptProgram(bindings: bindings, diagnostics: diagnostics)
    }

    /// Separate hash-to-profile entry point keeps the execution contract testable
    /// without copying third-party script source into repository fixtures.
    nonisolated static func compileVerifiedProfile(
        layerID: Int,
        authoredText: String,
        sourceSHA256: String,
        properties: [String: SceneJSONValue]
    ) -> SceneTextScriptProgram {
        guard let profile = profile(sourceSHA256: sourceSHA256) else {
            return .init(bindings: [], diagnostics: [.init(
                layerID: layerID,
                code: .unknownProfile,
                sourceSHA256: sourceSHA256
            )])
        }
        guard let configuration = configuration(profile: profile, properties: properties) else {
            return .init(bindings: [], diagnostics: [.init(
                layerID: layerID,
                code: .invalidProperties,
                sourceSHA256: sourceSHA256
            )])
        }
        return .init(bindings: [.init(
            layerID: layerID,
            profile: profile,
            configuration: configuration,
            definition: .init(
                target: .text(layerID: layerID, field: .content),
                valueType: .string,
                authoredValue: .string(authoredText)
            )
        )], diagnostics: [])
    }

    private nonisolated static func profile(
        sourceSHA256: String
    ) -> SceneTextScriptProgram.Profile? {
        switch sourceSHA256 {
        case clockSHA256: .workshop2981960200Clock
        case spacedDaySHA256: .workshop2981960200SpacedDay
        case dateSHA256: .workshop2981960200Date
        case compactDaySHA256: .workshop3732231168CompactDay
        case longMonthDateSHA256: .workshop3732231168LongMonthDate
        case clockWithPeriodSHA256: .workshop3732231168Clock
        default: nil
        }
    }

    private nonisolated static func configuration(
        profile: SceneTextScriptProgram.Profile,
        properties: [String: SceneJSONValue]
    ) -> SceneTextScriptProgram.Configuration? {
        switch profile {
        case .workshop2981960200Clock:
            guard Set(properties.keys) == ["use24hFormat", "showSeconds", "delimiter"],
                  let use24Hour = bool(properties["use24hFormat"]),
                  let showSeconds = bool(properties["showSeconds"]),
                  let delimiter = string(properties["delimiter"]) else {
                return nil
            }
            return .clock(
                use24Hour: use24Hour,
                showSeconds: showSeconds,
                delimiter: delimiter
            )
        case .workshop3732231168Clock:
            guard Set(properties.keys) == [
                "use24hFormat", "showSeconds", "displayDate", "delimiter",
            ],
                  let use24Hour = bool(properties["use24hFormat"]),
                  let showSeconds = bool(properties["showSeconds"]),
                  let displayDate = bool(properties["displayDate"]),
                  let delimiter = string(properties["delimiter"]) else {
                return nil
            }
            return .clockWithPeriod(
                use24Hour: use24Hour,
                showSeconds: showSeconds,
                displayDate: displayDate,
                delimiter: delimiter
            )
        case .workshop2981960200SpacedDay,
             .workshop2981960200Date,
             .workshop3732231168CompactDay,
             .workshop3732231168LongMonthDate:
            let keys = Set([
                "monthFormat", "dayFormat", "showDay",
                "alignVertical", "useDelimiter", "addDelimiter",
            ])
            guard Set(properties.keys) == keys,
                  let monthFormat = integerString(properties["monthFormat"]),
                  (1...3).contains(monthFormat),
                  let dayFormat = integerString(properties["dayFormat"]),
                  (1...2).contains(dayFormat),
                  let showDay = bool(properties["showDay"]),
                  let alignVertical = bool(properties["alignVertical"]),
                  let useDelimiter = bool(properties["useDelimiter"]),
                  let delimiter = string(properties["addDelimiter"]) else {
                return nil
            }
            return .date(
                monthFormat: monthFormat,
                dayFormat: dayFormat,
                showDay: showDay,
                alignVertical: alignVertical,
                useDelimiter: useDelimiter,
                delimiter: delimiter
            )
        }
    }

    private nonisolated static func unwrapped(_ value: SceneJSONValue?) -> SceneJSONValue? {
        guard case let .object(object)? = value, let nested = object["value"] else {
            return value
        }
        return unwrapped(nested)
    }

    private nonisolated static func bool(_ value: SceneJSONValue?) -> Bool? {
        unwrapped(value)?.boolValue
    }

    private nonisolated static func string(_ value: SceneJSONValue?) -> String? {
        unwrapped(value)?.stringValue
    }

    private nonisolated static func integerString(_ value: SceneJSONValue?) -> Int? {
        string(value).flatMap(Int.init)
    }

    private nonisolated static func sha256(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

/// Structural admission for the stock SceneScript audio-scaled scalar family.
/// Comments and local identifier spelling may vary, but the complete module,
/// 16-band registration, smoothing equation, clamp and scalar init must match.
nonisolated enum SceneAudioScaledValueSyntax {
    nonisolated struct Profile: Equatable, Sendable {
        let resolution: Int
        let propertyNames: [String]
    }

    nonisolated static func parse(_ source: String) -> Profile? {
        guard source.utf8.count <= 16_384,
              let tokens = SceneLaunchOriginTransitionLexer.lex(source),
              tokens.count <= 1_024 else { return nil }
        var parser = Parser(tokens: tokens)
        return parser.profile()
    }

    private struct Parser {
        private enum SliderField {
            case string(String)
            case number(Double)
            case bool(Bool)
        }

        let tokens: [SceneLaunchOriginTransitionToken]
        var index = 0

        mutating func profile() -> Profile? {
            guard string("use strict"), semi(), propertyBuilder(),
                  identifier("const"), let audio = bindingIdentifier(), symbol("="),
                  identifier("engine"), symbol("."),
                  identifier("registerAudioBuffers"), symbol("("),
                  identifier("engine"), symbol("."),
                  identifier("AUDIO_RESOLUTION_16"), symbol(")"), semi(),
                  identifier("let"), let smooth = bindingIdentifier(), symbol("="),
                  number(0), semi(),
                  identifier("let"), let initial = bindingIdentifier(), semi(),
                  Set([audio, smooth, initial]).count == 3,
                  update(audio: audio, smooth: smooth, initial: initial),
                  initialize(initial: initial),
                  index == tokens.count else { return nil }
            return Profile(
                resolution: 16,
                propertyNames: ["frequency", "maxvalue", "minvalue", "smoothing"]
            )
        }

        private mutating func propertyBuilder() -> Bool {
            guard identifier("export"), identifier("var"),
                  identifier("scriptProperties"), symbol("="),
                  identifier("createScriptProperties"), symbol("("), symbol(")") else {
                return false
            }
            var sliders: [String: [String: SliderField]] = [:]
            while symbol(".") {
                if identifier("finish") {
                    guard symbol("("), symbol(")"), semi(), sliders.count == 4 else {
                        return false
                    }
                    return slider(
                        sliders["frequency"],
                        name: "frequency", value: 0, minimum: 0, maximum: 15,
                        integer: true
                    ) && slider(
                        sliders["smoothing"],
                        name: "smoothing", value: 15, minimum: 0, maximum: 25,
                        integer: false
                    ) && slider(
                        sliders["minvalue"],
                        name: "minvalue", value: 0.8, minimum: 0, maximum: 3,
                        integer: false
                    ) && slider(
                        sliders["maxvalue"],
                        name: "maxvalue", value: 1.2, minimum: 0, maximum: 3,
                        integer: false
                    )
                }
                guard identifier("addSlider"), symbol("("), symbol("{"),
                      let fields = sliderObject(), symbol("}"), symbol(")"),
                      case let .string(name)? = fields["name"],
                      sliders[name] == nil else { return false }
                sliders[name] = fields
            }
            return false
        }

        private mutating func sliderObject() -> [String: SliderField]? {
            var fields: [String: SliderField] = [:]
            while true {
                guard let key = takeIdentifier(), fields[key] == nil,
                      symbol(":") else { return nil }
                let value: SliderField
                if let string = takeString() { value = .string(string) }
                else if let number = takeNumber() { value = .number(number) }
                else if identifier("true") { value = .bool(true) }
                else if identifier("false") { value = .bool(false) }
                else { return nil }
                fields[key] = value
                if symbol(",") { continue }
                return fields
            }
        }

        private func slider(
            _ fields: [String: SliderField]?,
            name: String,
            value: Double,
            minimum: Double,
            maximum: Double,
            integer: Bool
        ) -> Bool {
            guard let fields, fields.count == 6,
                  case let .string(actualName)? = fields["name"],
                  case .string? = fields["label"],
                  case let .number(actualValue)? = fields["value"],
                  case let .number(actualMinimum)? = fields["min"],
                  case let .number(actualMaximum)? = fields["max"],
                  case let .bool(actualInteger)? = fields["integer"] else { return false }
            return actualName == name
                && actualValue.bitPattern == value.bitPattern
                && actualMinimum.bitPattern == minimum.bitPattern
                && actualMaximum.bitPattern == maximum.bitPattern
                && actualInteger == integer
        }

        private mutating func update(
            audio: String,
            smooth: String,
            initial: String
        ) -> Bool {
            guard identifier("export"), identifier("function"),
                  identifier("update"), symbol("("), symbol(")"), symbol("{"),
                  identifier("const"), let delta = bindingIdentifier(), symbol("="),
                  property("maxvalue"), symbol("-"), property("minvalue"), semi(),
                  identifier("const"), let audioDelta = bindingIdentifier(), symbol("="),
                  identifier(audio), symbol("."), identifier("average"), symbol("["),
                  property("frequency"), symbol("]"), symbol("-"),
                  identifier(smooth), semi(),
                  Set([audio, smooth, initial, delta, audioDelta]).count == 5,
                  identifier(smooth), symbol("+="), identifier(audioDelta), symbol("*"),
                  identifier("Math"), symbol("."), identifier("min"), symbol("("),
                  number(1), symbol(","), identifier("engine"), symbol("."),
                  identifier("frametime"), symbol("*"), property("smoothing"),
                  symbol(")"), semi(),
                  identifier(smooth), symbol("="), identifier("Math"), symbol("."),
                  identifier("min"), symbol("("), number(1), symbol(","),
                  identifier(smooth), symbol(")"), semi(),
                  identifier("return"), identifier(initial), symbol("*"), symbol("("),
                  identifier(smooth), symbol("*"), identifier(delta), symbol("+"),
                  property("minvalue"), symbol(")"), semi(), symbol("}"),
                  optionalSemicolon() else { return false }
            return true
        }

        private mutating func initialize(initial: String) -> Bool {
            guard identifier("export"), identifier("function"),
                  identifier("init"), symbol("("), let value = bindingIdentifier(),
                  symbol(")"), symbol("{"), identifier(initial), symbol("="),
                  symbol("("), identifier("typeof"), identifier(value), symbol("==="),
                  string("number"), symbol(")"), symbol("?"), identifier(value),
                  symbol(":"), identifier(value), symbol("."), identifier("x"),
                  semi(), symbol("}"), optionalSemicolon() else { return false }
            return true
        }

        private mutating func property(_ name: String) -> Bool {
            identifier("scriptProperties") && symbol(".") && identifier(name)
        }

        private mutating func bindingIdentifier() -> String? {
            guard let value = takeIdentifier(), !Self.reserved.contains(value) else {
                return nil
            }
            return value
        }

        private static let reserved: Set<String> = [
            "arguments", "await", "break", "case", "catch", "class", "const",
            "continue", "debugger", "default", "delete", "do", "else", "enum",
            "eval", "export", "extends", "false", "finally", "for", "function",
            "if", "implements", "import", "in", "init", "instanceof", "interface",
            "let", "new", "null", "package", "private", "protected", "public",
            "return", "static", "super", "switch", "this", "throw", "true", "try",
            "typeof", "undefined", "update", "var", "void", "while", "with", "yield",
            "Math", "engine", "scriptProperties",
        ]

        private mutating func semi() -> Bool {
            if symbol(";") { return true }
            return index == tokens.count || tokens[index].lineBreakBefore
                || tokens[index] == .symbol("}")
        }

        private mutating func optionalSemicolon() -> Bool {
            _ = symbol(";")
            return true
        }

        private mutating func takeIdentifier() -> String? {
            guard index < tokens.count,
                  let value = tokens[index].identifierValue else { return nil }
            index += 1
            return value
        }

        private mutating func takeString() -> String? {
            guard index < tokens.count,
                  let value = tokens[index].stringValue else { return nil }
            index += 1
            return value
        }

        private mutating func takeNumber() -> Double? {
            guard index < tokens.count,
                  let value = tokens[index].numberValue else { return nil }
            index += 1
            return value
        }

        private mutating func identifier(_ value: String) -> Bool {
            consume(.identifier(value))
        }

        private mutating func number(_ value: Double) -> Bool {
            consume(.number(value))
        }

        private mutating func string(_ value: String) -> Bool {
            consume(.string(value))
        }

        private mutating func symbol(_ value: String) -> Bool {
            consume(.symbol(value))
        }

        private mutating func consume(
            _ token: SceneLaunchOriginTransitionToken
        ) -> Bool {
            guard index < tokens.count, tokens[index] == token else { return false }
            index += 1
            return true
        }
    }
}

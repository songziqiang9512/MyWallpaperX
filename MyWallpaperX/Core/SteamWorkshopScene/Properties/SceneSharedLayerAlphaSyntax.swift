import Foundation

/// Structural parser for the bounded `shared.flag` layer-alpha ramp family.
/// Comments, whitespace, identifiers and slider field order may vary, but the
/// complete module, branch polarity, operators and bounds must match.
nonisolated enum SceneSharedLayerAlphaSyntax {
    nonisolated enum Bound: Equatable {
        case number(Double)
        case property(String)
    }

    nonisolated struct Profile: Equatable {
        let sharedFlag: String
        let activeFlagValue: Bool
        let upperBound: Bound
        let lowerBound: Double
        let riseRate: Double
        let fallRate: Double
        let propertyNames: [String]
    }

    nonisolated static func parse(_ source: String) -> Profile? {
        guard source.utf8.count <= 16_384,
              let tokens = SceneLaunchOriginTransitionLexer.lex(source),
              tokens.count <= 1_024 else { return nil }
        var parser = Parser(tokens: tokens)
        return parser.profile()
    }

    nonisolated static func parseSharedInitializer(
        _ source: String
    ) -> [String: Bool]? {
        guard source.utf8.count <= 16_384,
              let tokens = SceneLaunchOriginTransitionLexer.lex(source),
              tokens.count <= 1_024 else { return nil }
        var parser = Parser(tokens: tokens)
        return parser.sharedInitializer()
    }

    private struct Parser {
        let tokens: [SceneLaunchOriginTransitionToken]
        var index = 0

        mutating func profile() -> Profile? {
            guard string("use strict"), endStatement() else { return nil }
            let propertyNames: [String]
            if peekIdentifier("export") && peekIdentifier("var", offset: 1) {
                guard let names = propertyBuilder() else { return nil }
                propertyNames = names
            } else {
                propertyNames = []
            }
            guard identifier("export"), identifier("function"), identifier("update"),
                  symbol("("), let value = takeIdentifier(), symbol(")"), symbol("{"),
                  identifier("if"), symbol("("),
                  let condition = sharedCondition(equal: true), symbol(")"), symbol("{"),
                  let riseRate = delta(value: value, adds: true),
                  identifier("if"), symbol("("), identifier(value), symbol(">"),
                  symbol("="), let upper = bound(), symbol(")"), symbol("{"),
                  assignment(value: value, bound: upper), symbol("}"), symbol("}"),
                  identifier("else"), identifier("if"), symbol("("),
                  let complement = sharedCondition(equal: false), symbol(")"),
                  symbol("{"), let fallRate = delta(value: value, adds: false),
                  identifier("if"), symbol("("), identifier(value), symbol("<"),
                  symbol("="), let lower = takeNumber(), symbol(")"), symbol("{"),
                  assignment(value: value, bound: .number(lower)), symbol("}"),
                  symbol("}"), identifier("return"), identifier(value),
                  endStatement(), symbol("}"), optionalSemicolon(),
                  index == tokens.count,
                  condition.flag == complement.flag,
                  condition.value == complement.value,
                  condition.flag != "__proto__",
                  riseRate.isFinite, riseRate > 0,
                  fallRate.isFinite, fallRate > 0,
                  lower.isFinite,
                  validate(upper: upper, lower: lower, propertyNames: propertyNames)
            else { return nil }
            return Profile(
                sharedFlag: condition.flag,
                activeFlagValue: condition.value,
                upperBound: upper,
                lowerBound: lower,
                riseRate: riseRate,
                fallRate: fallRate,
                propertyNames: propertyNames.sorted()
            )
        }

        mutating func sharedInitializer() -> [String: Bool]? {
            guard string("use strict"), endStatement(),
                  identifier("shared"), symbol("="), symbol("{") else {
                return nil
            }
            var result: [String: Bool] = [:]
            while !symbol("}") {
                guard let key = takeIdentifier(), key != "__proto__",
                      result[key] == nil, symbol(":"),
                      let value = takeBool() else { return nil }
                result[key] = value
                if symbol("}") { break }
                guard symbol(",") else { return nil }
            }
            guard endStatement(), !result.isEmpty,
                  index == tokens.count else { return nil }
            return result
        }

        /// Accepts one or more ordinary slider declarations. The runtime values
        /// come from the lossless wrapper IR; these declarations prove only the
        /// module's complete property schema and declared names.
        private mutating func propertyBuilder() -> [String]? {
            guard identifier("export"), identifier("var"),
                  identifier("scriptProperties"), symbol("="),
                  identifier("createScriptProperties"), symbol("("), symbol(")") else {
                return nil
            }
            var names: [String] = []
            while symbol(".") {
                if identifier("finish") {
                    guard symbol("("), symbol(")"), endStatement(),
                          !names.isEmpty, Set(names).count == names.count else { return nil }
                    return names
                }
                guard identifier("addSlider"), symbol("("), symbol("{"),
                      let name = sliderObject(), symbol("}"), symbol(")") else {
                    return nil
                }
                names.append(name)
            }
            return nil
        }

        private mutating func sliderObject() -> String? {
            enum FieldValue {
                case string(String)
                case number(Double)
                case bool(Bool)
            }
            var fields: [String: FieldValue] = [:]
            while true {
                guard let key = takeIdentifier(), fields[key] == nil, symbol(":") else {
                    return nil
                }
                let value: FieldValue
                if let string = takeString() { value = .string(string) }
                else if let number = takeNumber() { value = .number(number) }
                else if identifier("true") { value = .bool(true) }
                else if identifier("false") { value = .bool(false) }
                else { return nil }
                fields[key] = value
                if symbol(",") { continue }
                break
            }
            guard fields.count == 6,
                  case let .string(name)? = fields["name"], !name.isEmpty,
                  case .string? = fields["label"],
                  case let .number(value)? = fields["value"], value.isFinite,
                  case let .number(minimum)? = fields["min"], minimum.isFinite,
                  case let .number(maximum)? = fields["max"], maximum.isFinite,
                  case .bool? = fields["integer"], minimum <= maximum else { return nil }
            return name
        }

        private mutating func sharedCondition(
            equal: Bool
        ) -> (flag: String, value: Bool)? {
            guard identifier("shared"), symbol("."), let flag = takeIdentifier(),
                  symbol(equal ? "==" : "!=") else { return nil }
            if identifier("true") { return (flag, true) }
            if identifier("false") { return (flag, false) }
            return nil
        }

        private mutating func delta(value: String, adds: Bool) -> Double? {
            guard identifier(value), symbol(adds ? "+=" : "-="),
                  identifier("engine"), symbol("."), identifier("frametime") else {
                return nil
            }
            let rate: Double
            if symbol("*") {
                guard let value = takeNumber() else { return nil }
                rate = value
            } else {
                rate = 1
            }
            return endStatement() ? rate : nil
        }

        private mutating func bound() -> Bound? {
            if let number = takeNumber() { return .number(number) }
            guard identifier("scriptProperties"), symbol("."),
                  let name = takeIdentifier() else { return nil }
            return .property(name)
        }

        private mutating func assignment(value: String, bound: Bound) -> Bool {
            guard identifier(value), symbol("=") else { return false }
            switch bound {
            case let .number(number):
                guard consume(.number(number)) else { return false }
            case let .property(name):
                guard identifier("scriptProperties"), symbol("."),
                      identifier(name) else { return false }
            }
            return endStatement()
        }

        private func validate(
            upper: Bound, lower: Double, propertyNames: [String]
        ) -> Bool {
            switch upper {
            case let .number(value):
                return propertyNames.isEmpty && value.isFinite && value > lower
            case let .property(name):
                return propertyNames == [name]
            }
        }

        private mutating func endStatement() -> Bool {
            if symbol(";") { return true }
            guard index < tokens.count else { return true }
            return tokens[index].lineBreakBefore || tokens[index] == .symbol("}")
        }

        private mutating func optionalSemicolon() -> Bool {
            _ = symbol(";")
            return true
        }

        private func peekIdentifier(_ value: String, offset: Int = 0) -> Bool {
            index + offset < tokens.count
                && tokens[index + offset] == .identifier(value)
        }

        private mutating func takeIdentifier() -> String? {
            guard index < tokens.count,
                  let value = tokens[index].identifierValue else { return nil }
            index += 1
            return value
        }

        private mutating func takeNumber() -> Double? {
            guard index < tokens.count,
                  let value = tokens[index].numberValue else { return nil }
            index += 1
            return value
        }

        private mutating func takeString() -> String? {
            guard index < tokens.count,
                  let value = tokens[index].stringValue else { return nil }
            index += 1
            return value
        }

        private mutating func takeBool() -> Bool? {
            if identifier("true") { return true }
            if identifier("false") { return false }
            return nil
        }

        private mutating func identifier(_ value: String) -> Bool {
            consume(.identifier(value))
        }

        private mutating func string(_ value: String) -> Bool {
            consume(.string(value))
        }

        private mutating func symbol(_ value: String) -> Bool {
            consume(.symbol(value))
        }

        private mutating func consume(_ token: SceneLaunchOriginTransitionToken) -> Bool {
            guard index < tokens.count, tokens[index] == token else { return false }
            index += 1
            return true
        }
    }
}

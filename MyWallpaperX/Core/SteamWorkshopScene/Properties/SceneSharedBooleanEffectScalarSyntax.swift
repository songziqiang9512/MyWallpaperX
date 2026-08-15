import Foundation

/// Complete parser for a pass scalar selected by one shared boolean flag:
/// `if (shared.flag) value = A; else value = B; return value`.
/// It intentionally owns no arithmetic, nested branch or implicit mutation.
nonisolated enum SceneSharedBooleanEffectScalarSyntax {
    nonisolated struct Profile: Equatable {
        let sharedFlag: String
        let trueValue: Double
        let falseValue: Double
    }

    nonisolated static func parse(_ source: String) -> Profile? {
        guard source.utf8.count <= 16_384,
              let tokens = SceneLaunchOriginTransitionLexer.lex(source),
              tokens.count <= 256 else { return nil }
        var parser = Parser(tokens: tokens)
        return parser.profile()
    }

    private struct Parser {
        let tokens: [SceneLaunchOriginTransitionToken]
        var index = 0

        mutating func profile() -> Profile? {
            guard string("use strict"), endStatement(),
                  identifier("export"), identifier("function"),
                  identifier("update"), symbol("("),
                  let value = takeIdentifier(), symbol(")"), symbol("{"),
                  identifier("if"), symbol("("), identifier("shared"),
                  symbol("."), let flag = takeIdentifier(),
                  flag != "__proto__", symbol(")"), symbol("{"),
                  identifier(value), symbol("="),
                  let trueValue = signedNumber(), endStatement(), symbol("}"),
                  identifier("else"), symbol("{"), identifier(value),
                  symbol("="), let falseValue = signedNumber(),
                  endStatement(), symbol("}"), identifier("return"),
                  identifier(value), endStatement(), symbol("}"),
                  optionalSemicolon(), index == tokens.count,
                  trueValue.isFinite, falseValue.isFinite,
                  (0...1).contains(trueValue),
                  (0...1).contains(falseValue),
                  trueValue != falseValue,
                  validValueIdentifier(value) else { return nil }
            return .init(
                sharedFlag: flag,
                trueValue: trueValue,
                falseValue: falseValue
            )
        }

        private func validValueIdentifier(_ value: String) -> Bool {
            value != "shared" && value != "update" && value != "__proto__"
        }

        private mutating func signedNumber() -> Double? {
            let sign = symbol("-") ? -1.0 : 1.0
            guard index < tokens.count,
                  let number = tokens[index].numberValue else { return nil }
            index += 1
            return sign * number
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

        private mutating func takeIdentifier() -> String? {
            guard index < tokens.count,
                  let value = tokens[index].identifierValue else { return nil }
            index += 1
            return value
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

        private mutating func consume(
            _ token: SceneLaunchOriginTransitionToken
        ) -> Bool {
            guard index < tokens.count, tokens[index] == token else { return false }
            index += 1
            return true
        }
    }
}

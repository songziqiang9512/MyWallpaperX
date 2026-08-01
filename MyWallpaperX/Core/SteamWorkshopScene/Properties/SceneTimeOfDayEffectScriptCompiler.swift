import Foundation

/// Parses the documented `engine.timeOfDay` + `WEMath.smoothStep` Blend subset.
/// The complete wrapper and grammar must match; unsupported JavaScript fails closed.
nonisolated enum SceneTimeOfDayEffectScriptCompiler {
    private enum Token: Equatable {
        case identifier(String)
        case number(Double)
        case string(String)
        case symbol(String)
    }

    nonisolated static func compile(
        value: SceneDocument.ShaderValue,
        target: SceneDynamicTarget
    ) -> SceneTimeOfDayEffectScriptBinding? {
        guard value.valueKind.localizedLowercase == "binding",
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              value.bindingKeys == ["script", "user", "value"],
              let source = value.scriptSource,
              let components = value.components,
              components.count == 1,
              let authored = components.first,
              authored.isFinite,
              (0...2).contains(authored),
              let expression = compile(source: source) else {
            return nil
        }
        return SceneTimeOfDayEffectScriptBinding(
            definition: SceneDynamicTargetDefinition(
                target: target,
                valueType: .scalar,
                authoredValue: .scalar(authored)
            ),
            expression: expression
        )
    }

    nonisolated static func compile(
        source: String
    ) -> SceneTimeOfDayEffectScriptExpression? {
        guard let tokens = lex(source), tokens.count <= 1_024 else { return nil }
        var parser = Parser(tokens: tokens)
        return parser.parseProgram()
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var constants: [String: Double] = [:]
        var nodeCount = 0

        mutating func parseProgram() -> SceneTimeOfDayEffectScriptExpression? {
            guard consume(.string("use strict")), consume(.symbol(";")),
                  consume(.identifier("import")), consume(.symbol("*")),
                  consume(.identifier("as")), consume(.identifier("WEMath")),
                  consume(.identifier("from")), consume(.string("WEMath")),
                  consume(.symbol(";")) else {
                return nil
            }
            var declarationCount = 0
            while consume(.identifier("const")) {
                guard case let .identifier(name)? = consume(),
                      constants[name] == nil,
                      consume(.symbol("=")),
                      let expression = parseExpression(),
                      let value = constantValue(expression), value.isFinite,
                      consume(.symbol(";")) else {
                    return nil
                }
                constants[name] = value
                declarationCount += 1
            }
            guard declarationCount > 0,
                  consume(.identifier("export")), consume(.identifier("function")),
                  consume(.identifier("update")), consume(.symbol("(")),
                  case .identifier? = consume(), consume(.symbol(")")),
                  consume(.symbol("{")), consume(.identifier("return")),
                  let expression = parseExpression(), consume(.symbol(";")),
                  consume(.symbol("}")), index == tokens.count,
                  nodeCount <= 128 else {
                return nil
            }
            return expression
        }

        mutating func parseExpression() -> SceneTimeOfDayEffectScriptExpression? {
            parseAdditive()
        }

        mutating func parseAdditive() -> SceneTimeOfDayEffectScriptExpression? {
            guard var expression = parseMultiplicative() else { return nil }
            while true {
                if consume(.symbol("+")) {
                    guard let right = parseMultiplicative() else { return nil }
                    expression = node(.add(expression, right))
                } else if consume(.symbol("-")) {
                    guard let right = parseMultiplicative() else { return nil }
                    expression = node(.subtract(expression, right))
                } else {
                    return expression
                }
            }
        }

        mutating func parseMultiplicative() -> SceneTimeOfDayEffectScriptExpression? {
            guard var expression = parseUnary() else { return nil }
            while true {
                if consume(.symbol("*")) {
                    guard let right = parseUnary() else { return nil }
                    expression = node(.multiply(expression, right))
                } else if consume(.symbol("/")) {
                    guard let right = parseUnary() else { return nil }
                    expression = node(.divide(expression, right))
                } else {
                    return expression
                }
            }
        }

        mutating func parseUnary() -> SceneTimeOfDayEffectScriptExpression? {
            if consume(.symbol("-")) {
                return parseUnary().map { node(.negate($0)) }
            }
            return parsePrimary()
        }

        mutating func parsePrimary() -> SceneTimeOfDayEffectScriptExpression? {
            if consume(.symbol("(")) {
                guard let value = parseExpression(), consume(.symbol(")")) else { return nil }
                return value
            }
            guard let token = consume() else { return nil }
            switch token {
            case let .number(value):
                return value.isFinite ? node(.number(value)) : nil
            case let .identifier(name):
                if let value = constants[name] { return node(.number(value)) }
                return parseQualified(name)
            case .string, .symbol:
                return nil
            }
        }

        mutating func parseQualified(
            _ root: String
        ) -> SceneTimeOfDayEffectScriptExpression? {
            guard consume(.symbol(".")), case let .identifier(member)? = consume() else {
                return nil
            }
            if root == "engine", member == "timeOfDay" {
                return node(.timeOfDay)
            }
            guard consume(.symbol("(")) else { return nil }
            if root == "WEMath", member == "smoothStep" {
                guard let minimum = parseExpression(), consume(.symbol(",")),
                      let maximum = parseExpression(), consume(.symbol(",")),
                      let value = parseExpression(), consume(.symbol(")")) else {
                    return nil
                }
                return node(.smoothStep(minimum, maximum, value))
            }
            if root == "Math", member == "max" {
                guard let left = parseExpression(), consume(.symbol(",")),
                      let right = parseExpression(), consume(.symbol(")")) else {
                    return nil
                }
                return node(.maximum(left, right))
            }
            return nil
        }

        mutating func node(
            _ expression: SceneTimeOfDayEffectScriptExpression
        ) -> SceneTimeOfDayEffectScriptExpression {
            nodeCount += 1
            return expression
        }

        mutating func consume() -> Token? {
            guard index < tokens.count else { return nil }
            defer { index += 1 }
            return tokens[index]
        }

        mutating func consume(_ expected: Token) -> Bool {
            guard index < tokens.count, tokens[index] == expected else { return false }
            index += 1
            return true
        }
    }

    private static func constantValue(
        _ expression: SceneTimeOfDayEffectScriptExpression
    ) -> Double? {
        switch expression {
        case let .number(value): return value
        case let .add(left, right): return binary(left, right, +)
        case let .subtract(left, right): return binary(left, right, -)
        case let .multiply(left, right): return binary(left, right, *)
        case let .divide(left, right):
            guard let divisor = constantValue(right), divisor != 0,
                  let dividend = constantValue(left) else { return nil }
            return dividend / divisor
        case let .negate(value): return constantValue(value).map(-)
        case .timeOfDay, .smoothStep, .maximum: return nil
        }
    }

    private static func binary(
        _ left: SceneTimeOfDayEffectScriptExpression,
        _ right: SceneTimeOfDayEffectScriptExpression,
        _ operation: (Double, Double) -> Double
    ) -> Double? {
        guard let lhs = constantValue(left), let rhs = constantValue(right) else { return nil }
        return operation(lhs, rhs)
    }

    private static func lex(_ source: String) -> [Token]? {
        let characters = Array(source)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }
            if character == "/", index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    index += 2
                    while index < characters.count, characters[index] != "\n" { index += 1 }
                    continue
                }
                if characters[index + 1] == "*" {
                    index += 2
                    var closed = false
                    while index + 1 < characters.count {
                        if characters[index] == "*", characters[index + 1] == "/" {
                            index += 2; closed = true; break
                        }
                        index += 1
                    }
                    guard closed else { return nil }
                    continue
                }
            }
            if character.isLetter || character == "_" || character == "$" {
                let start = index
                index += 1
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber
                        || characters[index] == "_" || characters[index] == "$" {
                    index += 1
                }
                tokens.append(.identifier(String(characters[start..<index])))
                continue
            }
            if character.isNumber || (character == "." && index + 1 < characters.count
                && characters[index + 1].isNumber) {
                let start = index
                index += 1
                while index < characters.count,
                      characters[index].isNumber || characters[index] == "." {
                    index += 1
                }
                guard let value = Double(String(characters[start..<index])) else { return nil }
                tokens.append(.number(value))
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                index += 1
                let start = index
                while index < characters.count, characters[index] != quote {
                    guard characters[index] != "\\" else { return nil }
                    index += 1
                }
                guard index < characters.count else { return nil }
                tokens.append(.string(String(characters[start..<index])))
                index += 1
                continue
            }
            guard "(){};,*./+-=".contains(character) else { return nil }
            tokens.append(.symbol(String(character)))
            index += 1
        }
        return tokens
    }
}

import Foundation

/// Parses a deliberately small ECMAScript statement/expression subset used by
/// property-bound text updates. Unsupported syntax fails closed before playback.
nonisolated enum SceneTextScriptSubsetCompiler {
    private enum Token: Equatable {
        case identifier(String)
        case number(Double)
        case string(String)
        case symbol(String)
    }

    nonisolated static func compile(_ source: String) -> SceneTextScriptSubsetProgram? {
        guard let tokens = lex(source), tokens.count <= 2_048 else { return nil }
        let starts = tokens.indices.filter { index in
            index + 3 < tokens.count
                && tokens[index] == .identifier("export")
                && tokens[index + 1] == .identifier("function")
                && tokens[index + 2] == .identifier("update")
                && tokens[index + 3] == .symbol("(")
        }
        guard starts.count == 1 else { return nil }
        var parser = Parser(tokens: tokens, index: starts[0] + 4)
        guard case let .identifier(parameter)? = parser.consume(),
              parser.consume(.symbol(")")),
              parser.consume(.symbol("{")),
              let statements = parser.parseStatements(until: "}"),
              parser.consume(.symbol("}")),
              parser.statementCount <= 128 else {
            return nil
        }
        return SceneTextScriptSubsetProgram(
            parameterName: parameter,
            statements: statements
        )
    }

    private struct Parser {
        let tokens: [Token]
        var index: Int
        var statementCount = 0

        mutating func consume() -> Token? {
            guard index < tokens.count else { return nil }
            defer { index += 1 }
            return tokens[index]
        }

        mutating func consume(_ expected: Token) -> Bool {
            guard peek() == expected else { return false }
            index += 1
            return true
        }

        func peek(_ offset: Int = 0) -> Token? {
            let target = index + offset
            return target < tokens.count ? tokens[target] : nil
        }

        mutating func parseStatements(until terminator: String) -> [SceneTextScriptSubsetProgram.Statement]? {
            var statements: [SceneTextScriptSubsetProgram.Statement] = []
            while peek() != .symbol(terminator) {
                guard peek() != nil, let statement = parseStatement() else { return nil }
                statementCount += 1
                guard statementCount <= 128 else { return nil }
                statements.append(statement)
            }
            return statements
        }

        mutating func parseStatement() -> SceneTextScriptSubsetProgram.Statement? {
            if peek() == .identifier("let")
                || peek() == .identifier("var")
                || peek() == .identifier("const") {
                _ = consume()
                guard case let .identifier(name)? = consume() else { return nil }
                let value = consume(.symbol("=")) ? parseExpression() : nil
                guard consume(.symbol(";")) else { return nil }
                return .declare(name, value)
            }
            if consume(.identifier("if")) {
                guard consume(.symbol("(")),
                      let condition = parseExpression(),
                      consume(.symbol(")")),
                      consume(.symbol("{")),
                      let thenStatements = parseStatements(until: "}"),
                      consume(.symbol("}")) else {
                    return nil
                }
                var elseStatements: [SceneTextScriptSubsetProgram.Statement] = []
                if consume(.identifier("else")) {
                    guard consume(.symbol("{")),
                          let parsed = parseStatements(until: "}"),
                          consume(.symbol("}")) else {
                        return nil
                    }
                    elseStatements = parsed
                }
                return .conditional(condition, thenStatements, elseStatements)
            }
            if consume(.identifier("return")) {
                guard let value = parseExpression(), consume(.symbol(";")) else { return nil }
                return .returnValue(value)
            }
            guard case let .identifier(name)? = consume() else { return nil }
            let operation: SceneTextScriptSubsetProgram.AssignmentOperator
            if consume(.symbol("=")) {
                operation = .assign
            } else if consume(.symbol("+=")) {
                operation = .add
            } else if consume(.symbol("%=")) {
                operation = .remainder
            } else {
                return nil
            }
            guard let value = parseExpression(), consume(.symbol(";")) else { return nil }
            return .assign(name, operation, value)
        }

        mutating func parseExpression() -> SceneTextScriptSubsetProgram.Expression? {
            parseEquality()
        }

        mutating func parseEquality() -> SceneTextScriptSubsetProgram.Expression? {
            guard var expression = parseAdditive() else { return nil }
            while true {
                if consume(.symbol("==")) || consume(.symbol("===")) {
                    guard let right = parseAdditive() else { return nil }
                    expression = .equal(expression, right, negated: false)
                } else if consume(.symbol("!=")) || consume(.symbol("!==")) {
                    guard let right = parseAdditive() else { return nil }
                    expression = .equal(expression, right, negated: true)
                } else {
                    return expression
                }
            }
        }

        mutating func parseAdditive() -> SceneTextScriptSubsetProgram.Expression? {
            guard var expression = parseRemainder() else { return nil }
            while consume(.symbol("+")) {
                guard let right = parseRemainder() else { return nil }
                expression = .add(expression, right)
            }
            return expression
        }

        mutating func parseRemainder() -> SceneTextScriptSubsetProgram.Expression? {
            guard var expression = parseUnary() else { return nil }
            while consume(.symbol("%")) {
                guard let right = parseUnary() else { return nil }
                expression = .remainder(expression, right)
            }
            return expression
        }

        mutating func parseUnary() -> SceneTextScriptSubsetProgram.Expression? {
            if consume(.symbol("!")) {
                return parseUnary().map(SceneTextScriptSubsetProgram.Expression.unaryNot)
            }
            if consume(.symbol("-")) {
                return parseUnary().map(SceneTextScriptSubsetProgram.Expression.unaryMinus)
            }
            return parsePostfix()
        }

        mutating func parsePostfix() -> SceneTextScriptSubsetProgram.Expression? {
            guard var expression = parsePrimary() else { return nil }
            while true {
                if consume(.symbol(".")) {
                    guard case let .identifier(name)? = consume() else { return nil }
                    expression = .member(expression, name)
                } else if consume(.symbol("(")) {
                    var arguments: [SceneTextScriptSubsetProgram.Expression] = []
                    if !consume(.symbol(")")) {
                        while true {
                            guard let argument = parseExpression() else { return nil }
                            arguments.append(argument)
                            if consume(.symbol(")")) { break }
                            guard consume(.symbol(",")) else { return nil }
                        }
                    }
                    expression = .call(expression, arguments)
                } else {
                    return expression
                }
            }
        }

        mutating func parsePrimary() -> SceneTextScriptSubsetProgram.Expression? {
            if consume(.identifier("new")) {
                guard consume(.identifier("Date")),
                      consume(.symbol("(")),
                      consume(.symbol(")")) else {
                    return nil
                }
                return .newDate
            }
            guard let token = consume() else { return nil }
            switch token {
            case let .number(value): return .number(value)
            case let .string(value): return .string(value)
            case .identifier("true"): return .bool(true)
            case .identifier("false"): return .bool(false)
            case let .identifier(name): return .identifier(name)
            case .symbol("("):
                guard let value = parseExpression(), consume(.symbol(")")) else { return nil }
                return value
            case .symbol: return nil
            }
        }
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
                            index += 2
                            closed = true
                            break
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
            if character.isNumber {
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
                var value = ""
                var closed = false
                while index < characters.count {
                    let next = characters[index]
                    index += 1
                    if next == quote { closed = true; break }
                    if next == "\\" {
                        guard index < characters.count else { return nil }
                        let escaped = characters[index]
                        index += 1
                        switch escaped {
                        case "n": value.append("\n")
                        case "r": value.append("\r")
                        case "t": value.append("\t")
                        case "\\", "\"", "'": value.append(escaped)
                        default: return nil
                        }
                    } else {
                        value.append(next)
                    }
                }
                guard closed else { return nil }
                tokens.append(.string(value))
                continue
            }
            let candidates = ["===", "!==", "+=", "%=", "==", "!="]
            if let matched = candidates.first(where: {
                index + $0.count <= characters.count
                    && String(characters[index..<(index + $0.count)]) == $0
            }) {
                tokens.append(.symbol(matched))
                index += matched.count
                continue
            }
            if "(){}[];,:.!=+%-".contains(character) {
                tokens.append(.symbol(String(character)))
                index += 1
                continue
            }
            return nil
        }
        return tokens
    }
}

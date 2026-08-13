import Foundation

/// Recognizes one bounded, statement-for-statement stock placeholder fade.
/// Identifier spelling, comments, and valid semicolon insertion are irrelevant;
/// every operator, hook, state mapping, branch, and bound remains structural.
nonisolated enum SceneMediaPlaybackPlaceholderFadeCompiler {
    nonisolated static func compile(
        value: SceneDocument.ShaderValue,
        target: SceneDynamicTarget
    ) -> SceneMediaPlaybackPlaceholderFadeBinding? {
        guard value.valueKind.localizedLowercase == "binding",
              value.userBinding == nil,
              value.timeline == nil,
              value.timelineDiagnostics.isEmpty,
              value.bindingKeys.sorted() == ["script", "value"],
              let source = value.scriptSource,
              let components = value.components,
              components.count == 1,
              let authored = components.first,
              authored.isFinite,
              (0...1).contains(authored),
              case .effectConstant = target,
              source.utf8.count <= 16_384,
              let tokens = Lexer.lex(source),
              tokens.count <= 1_024 else {
            return nil
        }
        var parser = Parser(tokens: tokens)
        guard let plan = parser.parseProgram() else { return nil }
        return SceneMediaPlaybackPlaceholderFadeBinding(
            definition: SceneDynamicTargetDefinition(
                target: target,
                valueType: .scalar,
                authoredValue: .scalar(authored)
            ),
            plan: plan
        )
    }

    private struct Token: Equatable {
        enum Kind: Equatable {
            case identifier(String)
            case number(Double)
            case string(String)
            case symbol(String)
        }

        let kind: Kind
        let lineBreakBefore: Bool
    }

    private enum Lexer {
        static func lex(_ source: String) -> [Token]? {
            let characters = Array(source)
            var tokens: [Token] = []
            var index = 0
            var lineBreak = false
            while index < characters.count {
                let character = characters[index]
                if character.isWhitespace {
                    lineBreak = lineBreak || character == "\n" || character == "\r"
                    index += 1
                    continue
                }
                if character == "/", index + 1 < characters.count {
                    if characters[index + 1] == "/" {
                        index += 2
                        while index < characters.count,
                              characters[index] != "\n", characters[index] != "\r" {
                            index += 1
                        }
                        continue
                    }
                    if characters[index + 1] == "*" {
                        index += 2
                        var closed = false
                        while index + 1 < characters.count {
                            lineBreak = lineBreak || characters[index] == "\n"
                                || characters[index] == "\r"
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
                let kind: Token.Kind
                if character.isLetter || character == "_" || character == "$" {
                    let start = index
                    index += 1
                    while index < characters.count,
                          characters[index].isLetter || characters[index].isNumber
                            || characters[index] == "_" || characters[index] == "$" {
                        index += 1
                    }
                    kind = .identifier(String(characters[start..<index]))
                } else if character.isNumber || character == "."
                    && index + 1 < characters.count && characters[index + 1].isNumber {
                    let start = index
                    var dotCount = 0
                    repeat {
                        if characters[index] == "." { dotCount += 1 }
                        index += 1
                    } while index < characters.count
                        && (characters[index].isNumber || characters[index] == ".")
                    let spelling = String(characters[start..<index])
                    guard dotCount <= 1, let value = Double(spelling), value.isFinite else {
                        return nil
                    }
                    kind = .number(value)
                } else if character == "\"" || character == "'" {
                    let quote = character
                    index += 1
                    let start = index
                    while index < characters.count, characters[index] != quote {
                        guard characters[index] != "\\",
                              characters[index] != "\n", characters[index] != "\r" else {
                            return nil
                        }
                        index += 1
                    }
                    guard index < characters.count else { return nil }
                    kind = .string(String(characters[start..<index]))
                    index += 1
                } else if character == "=", index + 1 < characters.count,
                          characters[index + 1] == "=" {
                    kind = .symbol("==")
                    index += 2
                } else {
                    guard "(){};.*+-/=<>".contains(character) else { return nil }
                    kind = .symbol(String(character))
                    index += 1
                }
                tokens.append(Token(kind: kind, lineBreakBefore: lineBreak))
                guard tokens.count <= 1_024 else { return nil }
                lineBreak = false
            }
            return tokens
        }
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0

        mutating func parseProgram() -> SceneMediaPlaybackPlaceholderFadePlan? {
            guard string("use strict"), endStatement(),
                  let fade = declaration(number: 1),
                  let volume = declaration(number: 1),
                  let unusedState = declaration(number: 0),
                  let counter = declaration(number: 0),
                  identifier(fade), symbol("="), number(1), symbol("/"),
                  identifier(fade), endStatement(),
                  let mode = declaration(number: 0),
                  Set([fade, volume, unusedState, counter, mode]).count == 5,
                  mediaHook(mode: mode, globals: [fade, volume, unusedState, counter, mode]),
                  let stoppedAdds = updateHook(
                      fade: fade, volume: volume, counter: counter, mode: mode,
                      globals: [fade, volume, unusedState, counter, mode]
                  ),
                  index == tokens.count else {
                return nil
            }
            return stoppedAdds ? .stoppedRise : .activeRise
        }

        mutating func declaration(number expected: Double) -> String? {
            guard identifier("var"), let name = takeIdentifier(), symbol("="),
                  number(expected), endStatement() else { return nil }
            return name
        }

        mutating func mediaHook(mode: String, globals: [String]) -> Bool {
            guard identifier("export"), identifier("function"),
                  identifier("mediaPlaybackChanged"), symbol("("),
                  let event = takeIdentifier(), !globals.contains(event),
                  symbol(")"), symbol("{") else { return false }
            for state in 0...2 {
                if state == 0 {
                    guard identifier("if") else { return false }
                } else {
                    guard identifier("else"), identifier("if") else { return false }
                }
                guard symbol("("), identifier(event), symbol("."), identifier("state"),
                      symbol("=="), number(Double(state)), symbol(")"), symbol("{"),
                      assignment(mode, value: Double(state)), symbol("}") else {
                    return false
                }
            }
            return identifier("else") && symbol("{")
                && assignment(mode, value: 3) && symbol("}") && symbol("}")
        }

        mutating func updateHook(
            fade: String, volume: String, counter: String, mode: String,
            globals: [String]
        ) -> Bool? {
            guard identifier("export"), identifier("function"), identifier("update"),
                  symbol("("), let value = takeIdentifier(), !globals.contains(value),
                  symbol(")"), symbol("{") else { return nil }
            var operators: [Bool] = []
            for state in 0...2 {
                if state == 0 {
                    guard identifier("if") else { return nil }
                } else {
                    guard identifier("else"), identifier("if") else { return nil }
                }
                guard symbol("("), identifier(mode), symbol("=="),
                      number(Double(state)), symbol(")"), symbol("{"),
                      let adds = delta(counter: counter, fade: fade),
                      bound(counter: counter, lower: state == 0),
                      symbol("}") else { return nil }
                operators.append(adds)
            }
            guard operators.count == 3,
                  operators[1] == operators[2],
                  operators[0] != operators[1],
                  identifier("return"), identifier(counter), symbol("*"),
                  identifier(volume), endStatement(), symbol("}") else { return nil }
            return operators[0]
        }

        mutating func delta(counter: String, fade: String) -> Bool? {
            guard identifier(counter), symbol("="), identifier(counter) else { return nil }
            let adds: Bool
            if symbol("+") {
                adds = true
            } else if symbol("-") {
                adds = false
            } else {
                return nil
            }
            guard symbol("("), identifier(fade), symbol("*"), identifier("engine"),
                  symbol("."), identifier("frametime"), symbol("*"), number(2),
                  symbol(")"), endStatement() else { return nil }
            return adds
        }

        mutating func bound(counter: String, lower: Bool) -> Bool {
            identifier("if") && symbol("(") && identifier(counter)
                && symbol(lower ? "<" : ">") && number(lower ? 0 : 1)
                && symbol(")") && symbol("{")
                && assignment(counter, value: lower ? 0 : 1) && symbol("}")
        }

        mutating func assignment(_ name: String, value: Double) -> Bool {
            identifier(name) && symbol("=") && number(value) && endStatement()
        }

        mutating func endStatement() -> Bool {
            if symbol(";") { return true }
            guard index < tokens.count else { return true }
            return tokens[index].lineBreakBefore || tokens[index].kind == .symbol("}")
        }

        mutating func takeIdentifier() -> String? {
            guard index < tokens.count,
                  case let .identifier(value) = tokens[index].kind else { return nil }
            index += 1
            return value
        }

        mutating func identifier(_ expected: String) -> Bool {
            consume(.identifier(expected))
        }

        mutating func number(_ expected: Double) -> Bool {
            consume(.number(expected))
        }

        mutating func string(_ expected: String) -> Bool {
            consume(.string(expected))
        }

        mutating func symbol(_ expected: String) -> Bool {
            consume(.symbol(expected))
        }

        mutating func consume(_ expected: Token.Kind) -> Bool {
            guard index < tokens.count, tokens[index].kind == expected else { return false }
            index += 1
            return true
        }
    }
}

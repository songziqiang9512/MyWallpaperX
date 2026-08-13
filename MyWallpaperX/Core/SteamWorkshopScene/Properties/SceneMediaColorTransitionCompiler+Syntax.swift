import Foundation

nonisolated enum SceneMediaColorTransitionSyntax {
    nonisolated struct Result: Equatable, Sendable {
        let defaultTopColor: SIMD3<Double>
        let duration: TimeInterval
    }

    nonisolated static func parse(_ source: String) -> Result? {
        guard let tokens = Lexer.lex(source), tokens.count <= 2_048 else { return nil }
        var parser = Parser(tokens: tokens)
        return parser.parseProgram()
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
                    guard let number = number(characters, index: &index) else { return nil }
                    kind = .number(number)
                } else if character == "\"" || character == "'" {
                    guard let value = string(characters, index: &index) else { return nil }
                    kind = .string(value)
                } else {
                    let pair = index + 1 < characters.count
                        ? String(characters[index...index + 1]) : ""
                    if ["==", "+=", "||"].contains(pair) {
                        kind = .symbol(pair)
                        index += 2
                    } else {
                        guard "(){};.,:+-*/=<>".contains(character) else { return nil }
                        kind = .symbol(String(character))
                        index += 1
                    }
                }
                tokens.append(Token(kind: kind, lineBreakBefore: lineBreak))
                guard tokens.count <= 2_048 else { return nil }
                lineBreak = false
            }
            return tokens
        }

        private static func number(
            _ characters: [Character],
            index: inout Int
        ) -> Double? {
            let start = index
            while index < characters.count, characters[index].isNumber { index += 1 }
            if index < characters.count, characters[index] == "." {
                index += 1
                while index < characters.count, characters[index].isNumber { index += 1 }
            }
            if index < characters.count,
               ["e", "E"].contains(characters[index]) {
                index += 1
                if index < characters.count,
                   ["+", "-"].contains(characters[index]) { index += 1 }
                let exponentStart = index
                while index < characters.count, characters[index].isNumber { index += 1 }
                guard index > exponentStart else { return nil }
            }
            let spelling = String(characters[start..<index])
            guard let value = Double(spelling), value.isFinite else { return nil }
            return value
        }

        private static func string(
            _ characters: [Character],
            index: inout Int
        ) -> String? {
            let quote = characters[index]
            index += 1
            var value = ""
            while index < characters.count, characters[index] != quote {
                let character = characters[index]
                guard character != "\n", character != "\r" else { return nil }
                // This bounded profile does not need escaped literals. Treating
                // an escape as its following character would prove a different
                // ECMAScript string (for example, `\0`) as the authored text.
                guard character != "\\" else { return nil }
                value.append(characters[index])
                index += 1
            }
            guard index < characters.count else { return nil }
            index += 1
            return value
        }
    }

    private struct Parser {
        private static let prohibitedBindingNames: Set<String> = [
            "arguments", "await", "break", "case", "catch", "class", "const",
            "continue", "createScriptProperties", "debugger", "default", "delete",
            "do", "else", "engine", "enum", "eval", "export", "extends", "false",
            "finally", "for", "function", "if", "implements", "import", "in",
            "Infinity", "instanceof", "interface", "let", "mediaPlaybackChanged",
            "mediaThumbnailChanged", "NaN", "new", "null", "package", "private",
            "protected", "public", "return", "static", "super", "switch", "this",
            "throw", "true", "try", "typeof", "undefined", "update", "var", "Vec3",
            "void", "while", "with", "yield",
        ]

        let tokens: [Token]
        var index = 0

        mutating func parseProgram() -> Result? {
            guard string("use strict"), endStatement(),
                  let property = propertyDeclaration(),
                  let duration = declaration("const", number: 1),
                  let state = declaration("var", number: 0),
                  let newColor = propertyReferenceDeclaration("let", property.name),
                  let oldColor = propertyReferenceDeclaration("let", property.name),
                  let timer = referenceDeclaration("let", duration),
                  Set([property.name, duration, state, newColor, oldColor, timer]).count == 6,
                  thumbnailHook(
                      timer: timer, oldColor: oldColor, newColor: newColor,
                      globals: [property.name, duration, state, newColor, oldColor, timer]
                  ),
                  playbackHook(
                      state: state,
                      globals: [property.name, duration, state, newColor, oldColor, timer]
                  ),
                  updateHook(
                      property: property.name, duration: duration, state: state,
                      newColor: newColor, oldColor: oldColor, timer: timer,
                      globals: [property.name, duration, state, newColor, oldColor, timer]
                  ),
                  index == tokens.count else { return nil }
            return Result(defaultTopColor: property.defaultColor, duration: 1)
        }

        mutating func propertyDeclaration() -> (name: String, defaultColor: SIMD3<Double>)? {
            guard identifier("export"), identifier("var"), let name = takeBindingIdentifier(),
                  symbol("="), identifier("createScriptProperties"), symbol("("), symbol(")"),
                  symbol("."), identifier("addColor"), symbol("("), symbol("{") else {
                return nil
            }
            var propertyName: String?
            var label: String?
            var color: SIMD3<Double>?
            while !symbol("}") {
                guard let key = takeIdentifier(), symbol(":") else { return nil }
                switch key {
                case "name":
                    guard propertyName == nil, let value = takeString() else { return nil }
                    propertyName = value
                case "label":
                    guard label == nil, let value = takeString() else { return nil }
                    label = value
                case "value":
                    guard color == nil, identifier("new"), identifier("Vec3"), symbol("("),
                          let x = signedNumber(), symbol(","), let y = signedNumber(),
                          symbol(","), let z = signedNumber(), symbol(")") else { return nil }
                    color = SIMD3(x, y, z)
                default:
                    return nil
                }
                if symbol("}") { break }
                guard symbol(",") else { return nil }
            }
            guard propertyName == "topColor", let color,
                  symbol(")"), symbol("."), identifier("finish"), symbol("("), symbol(")"),
                  endStatement() else { return nil }
            _ = label
            return (name, color)
        }

        mutating func declaration(_ keyword: String, number expected: Double) -> String? {
            guard identifier(keyword), let name = takeBindingIdentifier(), symbol("="),
                  number(expected), endStatement() else { return nil }
            return name
        }

        mutating func propertyReferenceDeclaration(
            _ keyword: String,
            _ property: String
        ) -> String? {
            guard identifier(keyword), let name = takeBindingIdentifier(), symbol("="),
                  identifier(property), symbol("."), identifier("topColor"),
                  endStatement() else { return nil }
            return name
        }

        mutating func referenceDeclaration(_ keyword: String, _ source: String) -> String? {
            guard identifier(keyword), let name = takeBindingIdentifier(), symbol("="),
                  identifier(source), endStatement() else { return nil }
            return name
        }

        mutating func thumbnailHook(
            timer: String, oldColor: String, newColor: String, globals: [String]
        ) -> Bool {
            guard function("mediaThumbnailChanged"), let event = takeBindingIdentifier(),
                  !globals.contains(event), symbol(")"), symbol("{"),
                  assignment(timer, number: 0),
                  assignment(oldColor, identifier: newColor),
                  identifier(newColor), symbol("="), identifier(event), symbol("."),
                  identifier("secondaryColor"), endStatement(), symbol("}") else { return false }
            return true
        }

        mutating func playbackHook(state: String, globals: [String]) -> Bool {
            guard function("mediaPlaybackChanged"), let event = takeBindingIdentifier(),
                  !globals.contains(event), symbol(")"), symbol("{"),
                  identifier(state), symbol("="), identifier(event), symbol("."),
                  identifier("state"), endStatement(), symbol("}") else { return false }
            return true
        }

        mutating func updateHook(
            property: String, duration: String, state: String,
            newColor: String, oldColor: String, timer: String, globals: [String]
        ) -> Bool {
            guard identifier("export"), identifier("function"), identifier("update"),
                  symbol("("), symbol(")"), symbol("{"), identifier("var"),
                  let color = takeBindingIdentifier(), !globals.contains(color), symbol("="),
                  identifier(newColor), endStatement(),
                  identifier("if"), symbol("("), identifier(timer), symbol("<"),
                  identifier(duration), symbol(")"), symbol("{"),
                  identifier(color), symbol("="), identifier(newColor), symbol("."),
                  identifier("subtract"), symbol("("), identifier(oldColor), symbol(")"),
                  symbol("."), identifier("multiply"), symbol("("), identifier(timer),
                  symbol("/"), identifier(duration), symbol(")"), symbol("."),
                  identifier("add"), symbol("("), identifier(oldColor), symbol(")"),
                  endStatement(), identifier(timer), symbol("+="), identifier("engine"),
                  symbol("."), identifier("frametime"), endStatement(), symbol("}"),
                  identifier("if"), symbol("("), identifier(newColor), symbol("=="),
                  string("0 0 0"), symbol("||"), identifier(state), symbol("=="), number(0),
                  symbol(")"), symbol("{"), identifier(color), symbol("="),
                  identifier(property), symbol("."), identifier("topColor"),
                  endStatement(), symbol("}"), identifier("return"),
                  sameLineIdentifier(color),
                  endStatement(), symbol("}") else { return false }
            return true
        }

        mutating func function(_ name: String) -> Bool {
            identifier("export") && identifier("function") && identifier(name) && symbol("(")
        }

        mutating func assignment(_ target: String, number value: Double) -> Bool {
            identifier(target) && symbol("=") && number(value) && endStatement()
        }

        mutating func assignment(_ target: String, identifier value: String) -> Bool {
            identifier(target) && symbol("=") && identifier(value) && endStatement()
        }

        mutating func signedNumber() -> Double? {
            let sign = symbol("-") ? -1.0 : 1.0
            guard let value = takeNumber(), (sign * value).isFinite else { return nil }
            return sign * value
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

        mutating func takeBindingIdentifier() -> String? {
            guard let value = takeIdentifier(),
                  !Self.prohibitedBindingNames.contains(value) else { return nil }
            return value
        }

        mutating func sameLineIdentifier(_ value: String) -> Bool {
            guard index < tokens.count, !tokens[index].lineBreakBefore else { return false }
            return identifier(value)
        }

        mutating func takeString() -> String? {
            guard index < tokens.count,
                  case let .string(value) = tokens[index].kind else { return nil }
            index += 1
            return value
        }

        mutating func takeNumber() -> Double? {
            guard index < tokens.count,
                  case let .number(value) = tokens[index].kind else { return nil }
            index += 1
            return value
        }

        mutating func identifier(_ value: String) -> Bool { consume(.identifier(value)) }
        mutating func number(_ value: Double) -> Bool { consume(.number(value)) }
        mutating func string(_ value: String) -> Bool { consume(.string(value)) }
        mutating func symbol(_ value: String) -> Bool { consume(.symbol(value)) }

        mutating func consume(_ expected: Token.Kind) -> Bool {
            guard index < tokens.count, tokens[index].kind == expected else { return false }
            index += 1
            return true
        }
    }
}

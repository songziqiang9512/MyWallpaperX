import Foundation

/// Recognizes the data-only media metadata hook emitted by Workshop text assets.
/// The complete token stream must match one media hook plus optional inert
/// declarations; no JavaScript is evaluated by the product runtime.
nonisolated enum SceneTextMediaPropertiesCompiler {
    nonisolated struct Result: Equatable, Sendable {
        let field: SceneTextScriptProgram.MediaProperty
        let hasEmptyInitializer: Bool
    }

    private enum Token: Equatable {
        case identifier(String)
        case string(String)
        case symbol(Character)
    }

    nonisolated static func compile(
        _ source: String
    ) -> Result? {
        guard source.utf8.count <= 65_536,
              let tokens = lex(source),
              tokens.count <= 512 else {
            return nil
        }
        var parser = Parser(tokens: tokens)
        return parser.parse()
    }

    private struct Parser {
        let tokens: [Token]
        var index = 0
        var sawStrictDirective = false
        var sawWorkshopExport = false
        var sawInit = false
        var field: SceneTextScriptProgram.MediaProperty?

        mutating func parse() -> Result? {
            while peek() != nil {
                if case .string("use strict")? = peek() {
                    guard index == 0, !sawStrictDirective else { return nil }
                    _ = consume()
                    guard consume(.symbol(";")) else { return nil }
                    sawStrictDirective = true
                    continue
                }
                guard consume(.identifier("export")) else { return nil }
                if consume(.identifier("let")) {
                    guard parseWorkshopExport() else { return nil }
                } else if consume(.identifier("function")) {
                    guard parseFunction() else { return nil }
                } else {
                    return nil
                }
            }
            guard let field else { return nil }
            return .init(field: field, hasEmptyInitializer: sawInit)
        }

        mutating func parseWorkshopExport() -> Bool {
            guard !sawWorkshopExport,
                  consume(.identifier("__workshopId")),
                  consume(.symbol("=")),
                  case let .string(value)? = consume(),
                  !value.isEmpty,
                  value.count <= 32,
                  value.allSatisfy({ $0.isASCII && $0.isNumber }),
                  consume(.symbol(";")) else {
                return false
            }
            sawWorkshopExport = true
            return true
        }

        mutating func parseFunction() -> Bool {
            if consume(.identifier("mediaPropertiesChanged")) {
                return parseMediaPropertiesHook()
            }
            if consume(.identifier("init")) {
                return parseInitHook()
            }
            return false
        }

        mutating func parseMediaPropertiesHook() -> Bool {
            guard field == nil,
                  consume(.symbol("(")),
                  consume(.identifier("event")),
                  consume(.symbol(")")),
                  consume(.symbol("{")),
                  consume(.identifier("thisLayer")),
                  consume(.symbol(".")),
                  consume(.identifier("text")),
                  consume(.symbol("=")),
                  consume(.identifier("event")),
                  consume(.symbol(".")) else {
                return false
            }
            let parsedField: SceneTextScriptProgram.MediaProperty
            if consume(.identifier("title")) {
                parsedField = .title
            } else if consume(.identifier("artist")) {
                parsedField = .artist
            } else {
                return false
            }
            guard consume(.symbol(";")), consume(.symbol("}")) else {
                return false
            }
            field = parsedField
            return true
        }

        mutating func parseInitHook() -> Bool {
            guard !sawInit,
                  consume(.symbol("(")),
                  consume(.identifier("value")),
                  consume(.symbol(")")),
                  consume(.symbol("{")),
                  consume(.identifier("return")),
                  consume(.string("")),
                  consume(.symbol(";")),
                  consume(.symbol("}")) else {
                return false
            }
            sawInit = true
            return true
        }

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

        func peek() -> Token? {
            index < tokens.count ? tokens[index] : nil
        }
    }

    private static func lex(_ source: String) -> [Token]? {
        let characters = Array(source)
        var tokens: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character == "/", index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    index += 2
                    while index < characters.count, characters[index] != "\n" {
                        index += 1
                    }
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
            if isIdentifierStart(character) {
                let start = index
                index += 1
                while index < characters.count, isIdentifierContinuation(characters[index]) {
                    index += 1
                }
                tokens.append(.identifier(String(characters[start..<index])))
                continue
            }
            if character == "\"" || character == "'" {
                let quote = character
                index += 1
                let start = index
                while index < characters.count,
                      characters[index] != quote,
                      characters[index] != "\n",
                      characters[index] != "\r",
                      characters[index] != "\\" {
                    index += 1
                }
                guard index < characters.count, characters[index] == quote else {
                    return nil
                }
                tokens.append(.string(String(characters[start..<index])))
                index += 1
                continue
            }
            guard "{}().=;".contains(character) else { return nil }
            tokens.append(.symbol(character))
            index += 1
        }
        return tokens
    }

    private static func isIdentifierStart(_ value: Character) -> Bool {
        value.isASCII && (value.isLetter || value == "_" || value == "$")
    }

    private static func isIdentifierContinuation(_ value: Character) -> Bool {
        isIdentifierStart(value) || (value.isASCII && value.isNumber)
    }
}

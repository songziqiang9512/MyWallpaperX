import Foundation

/// Complete parser for the bounded `cursorEnter => true`,
/// `cursorLeave => false` shared-flag module.
nonisolated enum SceneHoverOriginTransitionSyntax {
    nonisolated struct Profile: Equatable {
        let sharedFlag: String
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
            guard string("use strict"), endStatement() else { return nil }
            var events: [String: (flag: String, value: Bool)] = [:]
            while index < tokens.count {
                guard identifier("export"), identifier("function"),
                      let name = takeIdentifier(), events[name] == nil,
                      name == "cursorEnter" || name == "cursorLeave",
                      symbol("("), let argument = takeIdentifier(),
                      validArgument(argument), symbol(")"), symbol("{") else {
                    return nil
                }
                let expected = name == "cursorEnter"
                guard identifier("shared"), symbol("."),
                      let flag = takeIdentifier(), flag != "__proto__",
                      symbol("="), bool(expected), endStatement(), symbol("}"),
                      optionalSemicolon() else { return nil }
                events[name] = (flag, expected)
            }
            guard events.count == 2,
                  let enter = events["cursorEnter"],
                  let leave = events["cursorLeave"],
                  enter.flag == leave.flag,
                  enter.value, !leave.value else { return nil }
            return Profile(sharedFlag: enter.flag)
        }

        private func validArgument(_ value: String) -> Bool {
            !reserved.contains(value) && value != "shared"
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

        private mutating func bool(_ value: Bool) -> Bool {
            identifier(value ? "true" : "false")
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

        private mutating func consume(_ token: SceneLaunchOriginTransitionToken) -> Bool {
            guard index < tokens.count, tokens[index] == token else { return false }
            index += 1
            return true
        }

        private let reserved: Set<String> = [
            "await", "break", "case", "catch", "class", "const", "continue",
            "debugger", "default", "delete", "do", "else", "enum", "export",
            "extends", "false", "finally", "for", "function", "if", "import",
            "in", "instanceof", "let", "new", "null", "return", "static",
            "super", "switch", "this", "throw", "true", "try", "typeof",
            "var", "void", "while", "with", "yield",
        ]
    }
}

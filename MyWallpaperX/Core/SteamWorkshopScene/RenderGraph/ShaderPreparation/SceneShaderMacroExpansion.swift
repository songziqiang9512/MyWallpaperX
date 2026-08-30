import Foundation

nonisolated enum SceneShaderMacroReplacement {
    static func isSupported(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.contains("#"),
              !value.contains("\\"),
              !value.contains("\""),
              !value.contains("'"),
              !value.contains("...") else { return false }
        var parentheses = 0
        var brackets = 0
        var braces = 0
        for character in value {
            switch character {
            case "(": parentheses += 1
            case ")": parentheses -= 1
            case "[": brackets += 1
            case "]": brackets -= 1
            case "{": braces += 1
            case "}": braces -= 1
            default:
                guard !character.isNewline else { return false }
            }
            guard parentheses >= 0, brackets >= 0, braces >= 0 else { return false }
        }
        return parentheses == 0 && brackets == 0 && braces == 0
    }
}

nonisolated struct SceneShaderFunctionMacro: Equatable, Sendable {
    struct ParseFailure: Error { let message: String }

    let name: String
    let parameters: [String]
    let replacement: String

    static func parse(
        name: String,
        suffix: Substring
    ) -> Result<SceneShaderFunctionMacro, ParseFailure> {
        guard suffix.first == "(" else {
            return .failure(.init(message: "Function-like shader macro has no parameter list."))
        }
        guard let closing = suffix.firstIndex(of: ")") else {
            return .failure(.init(message: "Function-like shader macro parameter list is unterminated."))
        }
        let parameterText = suffix[suffix.index(after: suffix.startIndex) ..< closing]
        guard !parameterText.contains("(") else {
            return .failure(.init(message: "Nested function-like macro parameter syntax is unsupported."))
        }
        let parameters: [String]
        if parameterText.trimmingCharacters(in: .whitespaces).isEmpty {
            parameters = []
        } else {
            parameters = parameterText.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
        guard parameters.allSatisfy(isIdentifier) else {
            return .failure(.init(message: "Function-like shader macro parameters must be identifiers."))
        }
        guard Set(parameters).count == parameters.count else {
            return .failure(.init(message: "Function-like shader macro parameters must be unique."))
        }
        let replacement = suffix[suffix.index(after: closing)...]
            .trimmingCharacters(in: .whitespaces)
        guard replacement.isEmpty || SceneShaderMacroReplacement.isSupported(replacement) else {
            return .failure(.init(
                message: "Function-like shader macro stringize, paste, quoted and multiline forms are unsupported."
            ))
        }
        return .success(.init(
            name: name,
            parameters: parameters,
            replacement: replacement
        ))
    }

    private static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.first, first == "_" || first.isLetter else { return false }
        return text.dropFirst().allSatisfy {
            $0 == "_" || $0.isLetter || $0.isNumber
        }
    }
}

nonisolated struct SceneShaderMacroExpansionError: Error {
    enum Kind { case unsupported, budgetExceeded }
    let kind: Kind
    let message: String
}

nonisolated enum SceneShaderLexicalExpander {
    static func expand(
        _ line: SceneShaderLexicalLine,
        objectMacros: [String: SceneShaderMacroValue],
        functionMacros: [String: SceneShaderFunctionMacro],
        limits: SceneShaderPreprocessor.Limits,
        resolved: @escaping (String) -> Void,
        unresolved: @escaping (String) throws -> Void
    ) throws -> String {
        var state = State(
            objectMacros: objectMacros,
            functionMacros: functionMacros,
            limits: limits,
            resolved: resolved,
            unresolved: unresolved
        )
        var result = ""
        for segment in line.segments {
            if segment.kind == .code {
                result += try state.expandCode(segment.text, active: [], depth: 0)
            } else {
                result += segment.text
            }
        }
        return result
    }
}

private extension SceneShaderLexicalExpander {
    nonisolated struct State {
        let objectMacros: [String: SceneShaderMacroValue]
        let functionMacros: [String: SceneShaderFunctionMacro]
        let limits: SceneShaderPreprocessor.Limits
        let resolved: (String) -> Void
        let unresolved: (String) throws -> Void
        var consumedTokens = 0
        var consumedBytes = 0

        mutating func expandCode(
            _ code: String,
            active: Set<String>,
            depth: Int
        ) throws -> String {
            guard depth <= limits.maximumMacroExpansionDepth else {
                throw expansionFailure(.budgetExceeded, "Shader macro expansion exceeds its depth budget.")
            }
            try consumeBudget(code)
            var result = ""
            var index = code.startIndex
            var changed = false
            while index < code.endIndex {
                guard isIdentifierStart(code[index]) else {
                    result.append(code[index])
                    index = code.index(after: index)
                    continue
                }
                let start = index
                index = code.index(after: index)
                while index < code.endIndex, isIdentifierBody(code[index]) {
                    index = code.index(after: index)
                }
                let name = String(code[start ..< index])
                if let macro = objectMacros[name] {
                    resolved(name)
                    try rejectRecursion(name, active: active)
                    result += try expandCode(
                        macro.replacement,
                        active: active.union([name]),
                        depth: depth + 1
                    )
                    changed = true
                    continue
                }
                if let macro = functionMacros[name] {
                    guard let invocation = try invocation(after: index, in: code) else {
                        result += name
                        continue
                    }
                    try rejectRecursion(name, active: active)
                    guard invocation.arguments.count == macro.parameters.count else {
                        throw expansionFailure(
                            .unsupported,
                            "Function-like shader macro '\(name)' received an invalid argument count."
                        )
                    }
                    guard invocation.arguments.allSatisfy({
                        !$0.trimmingCharacters(in: .whitespaces).isEmpty
                    }) || macro.parameters.isEmpty else {
                        throw expansionFailure(
                            .unsupported,
                            "Function-like shader macro '\(name)' received an empty argument."
                        )
                    }
                    let nestedActive = active.union([name])
                    var arguments: [String: String] = [:]
                    for (parameter, rawArgument) in zip(macro.parameters, invocation.arguments) {
                        let argument = rawArgument.trimmingCharacters(in: .whitespaces)
                        arguments[parameter] = try expandCode(
                            argument,
                            active: nestedActive,
                            depth: depth + 1
                        )
                    }
                    let substituted = substitute(macro.replacement, arguments: arguments)
                    result += try expandCode(
                        substituted,
                        active: nestedActive,
                        depth: depth + 1
                    )
                    index = invocation.end
                    changed = true
                    continue
                }
                try unresolved(name)
                result += name
            }
            return changed
                ? try expandCode(result, active: active, depth: depth + 1)
                : result
        }

        mutating func invocation(
            after nameEnd: String.Index,
            in code: String
        ) throws -> (arguments: [String], end: String.Index)? {
            var cursor = nameEnd
            while cursor < code.endIndex, code[cursor].isWhitespace {
                cursor = code.index(after: cursor)
            }
            guard cursor < code.endIndex, code[cursor] == "(" else { return nil }
            let contentStart = code.index(after: cursor)
            var argumentStart = contentStart
            cursor = contentStart
            var parenDepth = 1
            var bracketDepth = 0
            var braceDepth = 0
            var arguments: [String] = []
            while cursor < code.endIndex {
                switch code[cursor] {
                case "(": parenDepth += 1
                case ")":
                    parenDepth -= 1
                    if parenDepth == 0 {
                        let tail = String(code[argumentStart ..< cursor])
                        if !tail.trimmingCharacters(in: .whitespaces).isEmpty || !arguments.isEmpty {
                            arguments.append(tail)
                        }
                        guard bracketDepth == 0, braceDepth == 0 else {
                            throw expansionFailure(.unsupported, "Shader macro arguments are unbalanced.")
                        }
                        return (arguments, code.index(after: cursor))
                    }
                case "[": bracketDepth += 1
                case "]": bracketDepth -= 1
                case "{": braceDepth += 1
                case "}": braceDepth -= 1
                case "," where parenDepth == 1 && bracketDepth == 0 && braceDepth == 0:
                    arguments.append(String(code[argumentStart ..< cursor]))
                    argumentStart = code.index(after: cursor)
                default: break
                }
                guard parenDepth >= 1, bracketDepth >= 0, braceDepth >= 0 else {
                    throw expansionFailure(.unsupported, "Shader macro arguments are unbalanced.")
                }
                cursor = code.index(after: cursor)
            }
            throw expansionFailure(.unsupported, "Function-like shader macro invocation is unterminated.")
        }

        func substitute(_ replacement: String, arguments: [String: String]) -> String {
            var result = ""
            var index = replacement.startIndex
            while index < replacement.endIndex {
                guard isIdentifierStart(replacement[index]) else {
                    result.append(replacement[index])
                    index = replacement.index(after: index)
                    continue
                }
                let start = index
                index = replacement.index(after: index)
                while index < replacement.endIndex, isIdentifierBody(replacement[index]) {
                    index = replacement.index(after: index)
                }
                let name = String(replacement[start ..< index])
                result += arguments[name] ?? name
            }
            return result
        }

        mutating func consumeBudget(_ text: String) throws {
            consumedBytes += text.utf8.count
            consumedTokens += tokenCount(text)
            guard consumedBytes <= limits.maximumMacroExpansionBytes,
                  consumedTokens <= limits.maximumMacroExpansionTokens else {
                throw expansionFailure(.budgetExceeded, "Shader macro expansion exceeds its token or byte budget.")
            }
        }

        func tokenCount(_ text: String) -> Int {
            var count = 0
            var index = text.startIndex
            while index < text.endIndex {
                if text[index].isWhitespace {
                    index = text.index(after: index)
                } else if isIdentifierStart(text[index]) || text[index].isNumber {
                    count += 1
                    index = text.index(after: index)
                    while index < text.endIndex,
                          isIdentifierBody(text[index]) || text[index] == "." {
                        index = text.index(after: index)
                    }
                } else {
                    count += 1
                    index = text.index(after: index)
                }
            }
            return count
        }

        func rejectRecursion(_ name: String, active: Set<String>) throws {
            guard !active.contains(name) else {
                throw expansionFailure(.unsupported, "Recursive shader macro '\(name)' is unsupported.")
            }
        }

        func expansionFailure(
            _ kind: SceneShaderMacroExpansionError.Kind,
            _ message: String
        ) -> SceneShaderMacroExpansionError {
            .init(kind: kind, message: message)
        }

        func isIdentifierStart(_ character: Character) -> Bool {
            character == "_" || character.isLetter
        }

        func isIdentifierBody(_ character: Character) -> Bool {
            isIdentifierStart(character) || character.isNumber
        }
    }
}

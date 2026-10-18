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
    struct OutputLine { let sourceLine: Int; let text: String }
    enum Progress {
        case complete([OutputLine])
        case pending([OutputLine])

        var lines: [OutputLine] {
            switch self { case let .complete(lines), let .pending(lines): lines }
        }
    }

    /// One ordinary logical line, extended only while a known macro needs input.
    /// Its environment and expansion budget are fixed until completion.
    struct Stream {
        private var state: State
        private var run = Run()
        private var lines: [Int: String] = [:]
        private var lastTokens: [Int: Token] = [:]
        private var replacementGaps: Set<Int> = []
        private var firstLine: Int?
        private var lastLine: Int?

        init(
            objectMacros: [String: SceneShaderMacroValue],
            functionMacros: [String: SceneShaderFunctionMacro],
            limits: SceneShaderPreprocessor.Limits,
            unresolved: @escaping (String, Int) throws -> Void
        ) {
            state = State(objectMacros: objectMacros, functionMacros: functionMacros,
                          limits: limits, unresolved: unresolved)
        }

        var pendingLine: Int? { run.pending?.name.line }
        var resolvedMacros: Set<String> { state.resolvedMacros }

        mutating func feed(_ line: SceneShaderLexicalLine, sourceLine: Int) throws -> Progress {
            var tokens: [Token] = []
            if lastLine != nil {
                tokens.append(.init(kind: .lineBreak, text: "", line: sourceLine))
            }
            if firstLine == nil { firstLine = sourceLine }
            lastLine = sourceLine
            lines[sourceLine] = ""
            var needsTokens = run.pending != nil
            for segment in line.segments {
                if segment.kind == .code {
                    try state.consumeBudget(segment.text)
                    if needsTokens {
                        tokens += State.codeTokens(segment.text, line: sourceLine)
                    } else {
                        let ordinary = try state.ordinaryPrefix(segment.text, line: sourceLine)
                        tokens += ordinary.tokens
                        needsTokens = ordinary.needsExpansion
                    }
                } else {
                    let kind: Token.Kind = segment.kind == .quoted ? .quoted : .comment
                    tokens.append(.init(kind: kind, text: segment.text, line: sourceLine))
                }
            }
            run.push(tokens)
            try state.advance(&run, final: false)
            return collect()
        }

        mutating func finish() throws -> [OutputLine] {
            try state.advance(&run, final: true)
            return collect().lines
        }

        private mutating func collect() -> Progress {
            for token in run.output where token.kind != .lineBreak {
                if token.kind == .boundary {
                    replacementGaps.insert(token.line)
                    continue
                }
                if let previous = lastTokens[token.line],
                   (previous.generated || token.generated || replacementGaps.contains(token.line)),
                   !previous.isTrivia, !token.isTrivia,
                   let left = previous.text.last, let right = token.text.first,
                   State.requiresTokenBoundary(left, right) {
                    lines[token.line, default: ""] += " "
                }
                lines[token.line, default: ""] += token.text
                lastTokens[token.line] = token
                replacementGaps.remove(token.line)
            }
            run.output.removeAll(keepingCapacity: true)
            let end = run.pending?.name.line ?? ((lastLine ?? 0) + 1)
            var completed: [OutputLine] = []
            if let firstLine, firstLine < end {
                for line in firstLine ..< end {
                    completed.append(.init(sourceLine: line, text: lines.removeValue(forKey: line) ?? ""))
                    lastTokens.removeValue(forKey: line)
                    replacementGaps.remove(line)
                }
                self.firstLine = end
            }
            return run.pending == nil ? .complete(completed) : .pending(completed)
        }
    }
}

private nonisolated extension SceneShaderLexicalExpander {
    struct Token {
        enum Kind { case code, identifier, whitespace, quoted, comment, lineBreak, boundary }
        let kind: Kind
        let text: String
        let line: Int
        var active: Set<String> = []
        var depth = 0
        var generated = false

        var isTrivia: Bool {
            kind == .whitespace || kind == .comment || kind == .lineBreak || kind == .boundary
        }
        var argumentText: String { isTrivia ? " " : text }
    }

    struct Invocation {
        let name: Token
        let macro: SceneShaderFunctionMacro
        var opened = false
        var parentheses = 1
        var brackets = 0
        var braces = 0
        var trivia: [Token] = []
        var arguments: [[Token]] = []
        var current: [Token] = []
    }

    struct Run {
        struct Frame { let tokens: [Token]; var cursor = 0 }
        var frames: [Frame] = []
        var pending: Invocation?
        var output: [Token] = []

        mutating func push(_ tokens: [Token]) {
            if !tokens.isEmpty { frames.append(.init(tokens: tokens)) }
        }
        mutating func next() -> Token? {
            while let last = frames.last {
                if last.cursor == last.tokens.count {
                    frames.removeLast()
                } else {
                    frames[frames.count - 1].cursor += 1
                    return last.tokens[last.cursor]
                }
            }
            return nil
        }
    }

    struct State {
        let objectMacros: [String: SceneShaderMacroValue]
        let functionMacros: [String: SceneShaderFunctionMacro]
        let limits: SceneShaderPreprocessor.Limits
        var resolvedMacros: Set<String> = []
        let unresolved: (String, Int) throws -> Void
        var consumedTokens = 0
        var consumedBytes = 0

        /// The ordinary completed-line path keeps the existing identifier scan.
        /// Only the suffix beginning at a real macro needs structured tokens.
        mutating func ordinaryPrefix(_ code: String, line: Int) throws -> (tokens: [Token], needsExpansion: Bool) {
            var index = code.startIndex
            while index < code.endIndex {
                guard Self.isIdentifierStart(code[index]) else {
                    index = code.index(after: index)
                    continue
                }
                let start = index
                index = code.index(after: index)
                while index < code.endIndex, Self.isIdentifierBody(code[index]) {
                    index = code.index(after: index)
                }
                let name = String(code[start ..< index])
                if objectMacros[name] != nil || functionMacros[name] != nil {
                    var tokens: [Token] = []
                    if start != code.startIndex {
                        tokens.append(.init(kind: .code, text: String(code[..<start]), line: line))
                    }
                    tokens += Self.codeTokens(String(code[start...]), line: line)
                    return (tokens, true)
                }
                try unresolved(name, line)
            }
            return ([.init(kind: .code, text: code, line: line)], false)
        }

        mutating func advance(_ run: inout Run, final: Bool) throws {
            while let token = run.next() {
                if var call = run.pending {
                    // Remove the stored copy before appending: a long pending call
                    // retains its cursor/arguments rather than copying its prefix.
                    run.pending = nil
                    if !call.opened {
                        if token.isTrivia {
                            call.trivia.append(token)
                            run.pending = call
                            continue
                        }
                        if token.kind == .code, token.text == "(" {
                            try checkExpansion(call.name)
                            call.opened = true
                            run.pending = call
                            continue
                        }
                        run.output.append(call.name)
                        run.output += call.trivia
                        // The significant token still belongs to the ordinary stream.
                    } else {
                        if token.kind == .comment { call.trivia.append(token) }
                        if token.kind == .code {
                            switch token.text {
                            case "(": call.parentheses += 1
                            case ")": call.parentheses -= 1
                            case "[": call.brackets += 1
                            case "]": call.brackets -= 1
                            case "{": call.braces += 1
                            case "}": call.braces -= 1
                            default: break
                            }
                            guard call.brackets >= 0, call.braces >= 0 else {
                                throw failure(.unsupported, "Shader macro arguments are unbalanced.")
                            }
                            if call.parentheses == 0 {
                                guard call.brackets == 0, call.braces == 0 else {
                                    throw failure(.unsupported, "Shader macro arguments are unbalanced.")
                                }
                                if call.current.contains(where: { !$0.isTrivia }) || !call.arguments.isEmpty {
                                    call.arguments.append(call.current)
                                }
                                let replacement = try replacement(for: call)
                                run.push(call.trivia.filter { $0.kind == .comment })
                                run.push(replacement.isEmpty
                                    ? [.init(kind: .boundary, text: "", line: call.name.line)] : replacement)
                                continue
                            }
                            if token.text == ",", call.parentheses == 1,
                               call.brackets == 0, call.braces == 0 {
                                call.arguments.append(call.current)
                                call.current = []
                                run.pending = call
                                continue
                            }
                        }
                        call.current.append(token)
                        run.pending = call
                        continue
                    }
                }
                guard token.kind == .identifier else {
                    run.output.append(token)
                    continue
                }
                if let macro = objectMacros[token.text] {
                    try checkExpansion(token)
                    resolvedMacros.insert(token.text)
                    try consumeBudget(macro.replacement)
                    let replacement = Self.codeTokens(macro.replacement, replacing: token)
                    run.push(replacement.isEmpty
                        ? [.init(kind: .boundary, text: "", line: token.line)] : replacement)
                } else if let macro = functionMacros[token.text] {
                    run.pending = .init(name: token, macro: macro)
                } else {
                    try unresolved(token.text, token.line)
                    run.output.append(token)
                }
            }
            if final, let pending = run.pending {
                guard !pending.opened else {
                    throw failure(.unsupported, "Function-like shader macro invocation is unterminated.")
                }
                run.pending = nil
                run.output.append(pending.name)
                run.output += pending.trivia
            }
        }

        mutating func replacement(for call: Invocation) throws -> [Token] {
            guard call.arguments.count == call.macro.parameters.count else {
                throw failure(.unsupported, "Function-like shader macro '\(call.name.text)' received an invalid argument count.")
            }
            resolvedMacros.insert(call.name.text)
            var arguments: [String: [Token]] = [:]
            for (parameter, raw) in zip(call.macro.parameters, call.arguments) {
                guard raw.contains(where: { !$0.isTrivia }) else {
                    throw failure(.unsupported, "Function-like shader macro '\(call.name.text)' received an empty argument.")
                }
                // Comments/newlines are argument whitespace. Their original text
                // is retained once at the physical call site, never substituted.
                let first = raw.firstIndex { !$0.isTrivia }!
                let last = raw.lastIndex { !$0.isTrivia }!
                let normalized = raw[first ... last].map { token -> Token in
                    var value = Token(kind: token.isTrivia ? .whitespace : token.kind,
                                      text: token.argumentText, line: call.name.line)
                    value.active = call.name.active.union([call.name.text])
                    value.depth = call.name.depth + 1
                    value.generated = true
                    return value
                }
                try consumeBudget(normalized.map(\.text).joined())
                var nested = Run()
                nested.push(normalized)
                try advance(&nested, final: true)
                arguments[parameter] = nested.output
            }
            let template = Self.codeTokens(call.macro.replacement, replacing: call.name)
            var substituted: [Token] = []
            for token in template {
                if token.kind == .identifier, let argument = arguments[token.text] {
                    substituted += argument
                } else { substituted.append(token) }
            }
            try consumeBudget(substituted.map(\.text).joined())
            return substituted
        }

        func checkExpansion(_ token: Token) throws {
            guard token.depth < limits.maximumMacroExpansionDepth else {
                throw failure(.budgetExceeded, "Shader macro expansion exceeds its depth budget.")
            }
            guard !token.active.contains(token.text) else {
                throw failure(.unsupported, "Recursive shader macro '\(token.text)' is unsupported.")
            }
        }

        mutating func consumeBudget(_ text: String) throws {
            consumedBytes += text.utf8.count
            consumedTokens += Self.tokenCount(text)
            guard consumedBytes <= limits.maximumMacroExpansionBytes,
                  consumedTokens <= limits.maximumMacroExpansionTokens else {
                throw failure(.budgetExceeded, "Shader macro expansion exceeds its token or byte budget.")
            }
        }

        static func codeTokens(_ text: String, replacing token: Token) -> [Token] {
            codeTokens(text, line: token.line).map {
                var result = $0
                result.active = token.active.union([token.text])
                result.depth = token.depth + 1
                result.generated = true
                return result
            }
        }

        static func codeTokens(_ text: String, line: Int) -> [Token] {
            var tokens: [Token] = []
            var index = text.startIndex
            while index < text.endIndex {
                let start = index
                let first = text[index]
                index = text.index(after: index)
                let kind: Token.Kind
                if first.isWhitespace {
                    kind = .whitespace
                    while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
                } else if isIdentifierStart(first) {
                    kind = .identifier
                    while index < text.endIndex, isIdentifierBody(text[index]) { index = text.index(after: index) }
                } else if first.isNumber || (first == "." && index < text.endIndex && text[index].isNumber) {
                    kind = .code
                    var previous = first
                    while index < text.endIndex {
                        let value = text[index]
                        guard isIdentifierBody(value) || value == "."
                            || ((value == "+" || value == "-") && "eEpP".contains(previous)) else { break }
                        previous = value
                        index = text.index(after: index)
                    }
                } else {
                    kind = .code
                    if index < text.endIndex, compoundOperators.contains(String([first, text[index]])) {
                        index = text.index(after: index)
                        if index < text.endIndex, text[index] == "=",
                           ["<<", ">>"].contains(String(text[start ..< index])) {
                            index = text.index(after: index)
                        }
                    }
                }
                tokens.append(.init(kind: kind, text: String(text[start ..< index]), line: line))
            }
            return tokens
        }

        static func tokenCount(_ text: String) -> Int {
            var count = 0
            var index = text.startIndex
            while index < text.endIndex {
                if text[index].isWhitespace {
                    index = text.index(after: index)
                } else if isIdentifierStart(text[index]) || text[index].isNumber {
                    count += 1
                    index = text.index(after: index)
                    while index < text.endIndex, isIdentifierBody(text[index]) || text[index] == "." {
                        index = text.index(after: index)
                    }
                } else {
                    count += 1
                    index = text.index(after: index)
                }
            }
            return count
        }

        static let compoundOperators: Set<String> = [
            "++", "--", "+=", "-=", "*=", "/=", "%=", "==", "!=", "<=", ">=",
            "&&", "||", "<<", ">>", "&=", "|=", "^=", "//", "/*", "*/", "##",
        ]
        static func requiresTokenBoundary(_ left: Character, _ right: Character) -> Bool {
            guard !left.isWhitespace, !right.isWhitespace else { return false }
            return (isIdentifierBody(left) && isIdentifierBody(right))
                || (left == "." && (right.isNumber || right == "."))
                || (left.isNumber && right == ".")
                || compoundOperators.contains(String([left, right]))
        }
        static func isIdentifierStart(_ character: Character) -> Bool { character == "_" || character.isLetter }
        static func isIdentifierBody(_ character: Character) -> Bool { isIdentifierStart(character) || character.isNumber }
        func failure(_ kind: SceneShaderMacroExpansionError.Kind, _ message: String) -> SceneShaderMacroExpansionError {
            .init(kind: kind, message: message)
        }
    }
}

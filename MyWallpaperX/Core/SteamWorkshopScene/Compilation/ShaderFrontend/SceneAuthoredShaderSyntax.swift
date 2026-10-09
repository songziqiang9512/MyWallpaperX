import Foundation

nonisolated struct SceneAuthoredShaderSyntaxUnit {
    enum Storage: String {
        case uniform
        case attribute
        case varying
    }

    struct Declaration: Equatable {
        let storage: Storage
        let typeName: String
        let name: String
        let arraySize: Int?
        let range: Range<Int>
        let line: Int
    }

    struct Function: Equatable {
        let name: String
        let returnType: String
        let headerRange: Range<Int>
        let parameterRange: Range<Int>
        let bodyRange: Range<Int>
        let line: Int
    }

    let stage: SceneShaderContract.StageKind
    let tokens: [SceneAuthoredShaderToken]
    let defines: [String: String]
    let declarations: [Declaration]
    let functions: [Function]
    let staticLoopWork: Int
    let boundedLoopUniformReferences: [SceneAuthoredShaderToken: Int]
    let constantParameterArraysByFunctionIndex: [Int: Set<String>]
    let exactRuntimeLoopUniformArrays: Set<String>
}

nonisolated enum SceneAuthoredShaderSyntaxAnalyzer {
    struct Output {
        let unit: SceneAuthoredShaderSyntaxUnit?
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    /// The same unique-declarator proof also serves vector return conversion.
    /// Arrays, functions and repeated names never provide a value type.
    static func uniqueValueDeclarations(
        in tokens: [SceneAuthoredShaderToken], excluding ranges: [Range<Int>] = []
    ) -> [String: (type: String, index: Int)] {
        valueDeclarationFacts(in: tokens, excluding: ranges).compactMapValues { facts in
            guard facts.count == 1, facts[0].value else { return nil }
            return (facts[0].type, facts[0].index)
        }
    }

    /// Includes arrays and repeated declarations: either shadows an outer
    /// binding even when it cannot supply a unique scalar/vector value type.
    static func valueDeclarationNames(in tokens: [SceneAuthoredShaderToken]) -> Set<String> {
        Set(valueDeclarationFacts(in: tokens, excluding: []).keys)
    }

    private static func valueDeclarationFacts(
        in tokens: [SceneAuthoredShaderToken], excluding ranges: [Range<Int>]
    ) -> [String: [(type: String, index: Int, value: Bool)]] {
        var declarations: [String: [(type: String, index: Int, value: Bool)]] = [:]
        func record(_ index: Int, type: String) {
            guard !ranges.contains(where: { $0.contains(index) }) else { return }
            let next = index + 1 < tokens.count ? tokens[index + 1].text : ""
            declarations[tokens[index].text, default: []].append((
                type, index,
                next != "[" && next != "("
            ))
        }
        for index in tokens.indices.dropLast() {
            guard let valueType = SceneAuthoredShaderValueType(
                authoredName: tokens[index].text
            ), tokens[index + 1].kind == .identifier else { continue }
            record(index + 1, type: valueType.rawValue)
            guard index + 2 < tokens.count,
                  tokens[index + 2].text != "(" else { continue }
            var depth = 0
            var cursor = index + 2
            while cursor < tokens.count {
                let text = tokens[cursor].text
                if depth == 0, [";", ")", "{", "}"].contains(text) { break }
                if ["(", "["].contains(text) { depth += 1 }
                if [")", "]"].contains(text) { depth -= 1 }
                if text == ",", depth == 0, cursor + 2 < tokens.count,
                   tokens[cursor + 1].kind == .identifier,
                   ["=", ";", ",", "["].contains(tokens[cursor + 2].text) {
                    record(cursor + 1, type: valueType.rawValue)
                }
                cursor += 1
            }
        }
        return declarations
    }

    private static let forbiddenControlFlow: Set<String> = [
        "while", "do", "switch", "goto", "discard",
    ]

    static func analyze(
        lexerOutput: SceneAuthoredShaderLexer.Output,
        stage: SceneShaderContract.StageKind,
        provenRuntimeLoopBounds: [String: SceneAuthoredShaderExactScalarFact] = [:]
    ) -> Output {
        analyze(
            lexerOutput: lexerOutput, stage: stage,
            provenRuntimeLoopBounds: provenRuntimeLoopBounds,
            requiresBoundedLoops: true
        )
    }

    /// Reuses the syntax facts for explicit value conversions in a generic
    /// compiler input. This is not execution admission: the bounded frontend
    /// still calls `analyze` and proves every loop before it emits Metal.
    static func analyzeForTypeConversions(
        lexerOutput: SceneAuthoredShaderLexer.Output,
        stage: SceneShaderContract.StageKind
    ) -> Output {
        analyze(
            lexerOutput: lexerOutput, stage: stage,
            provenRuntimeLoopBounds: [:], requiresBoundedLoops: false
        )
    }

    private static func analyze(
        lexerOutput: SceneAuthoredShaderLexer.Output,
        stage: SceneShaderContract.StageKind,
        provenRuntimeLoopBounds: [String: SceneAuthoredShaderExactScalarFact],
        requiresBoundedLoops: Bool
    ) -> Output {
        guard lexerOutput.diagnostics.isEmpty else {
            return Output(unit: nil, diagnostics: lexerOutput.diagnostics)
        }
        let tokens = lexerOutput.tokens
        if let diagnostic = delimiterDiagnostic(tokens: tokens, stage: stage) {
            return Output(unit: nil, diagnostics: [diagnostic])
        }
        if let token = tokens.first(where: {
            $0.kind == .identifier && forbiddenControlFlow.contains($0.text)
        }) {
            return failure(
                .unsupportedControlFlow,
                "Control flow '\(token.text)' is not supported by the bounded frontend.",
                token: token,
                stage: stage
            )
        }

        var declarations: [SceneAuthoredShaderSyntaxUnit.Declaration] = []
        var functions: [SceneAuthoredShaderSyntaxUnit.Function] = []
        var index = 0
        var braceDepth = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.text == "{" {
                braceDepth += 1
                index += 1
                continue
            }
            if token.text == "}" {
                braceDepth -= 1
                index += 1
                continue
            }
            guard braceDepth == 0 else {
                index += 1
                continue
            }
            if let storage = SceneAuthoredShaderSyntaxUnit.Storage(rawValue: token.text) {
                guard let declaration = declaration(
                    at: index,
                    storage: storage,
                    tokens: tokens,
                    stage: stage
                ) else {
                    return failure(
                        .unsupportedDeclaration,
                        "Malformed top-level \(storage.rawValue) declaration.",
                        token: token,
                        stage: stage
                    )
                }
                declarations.append(declaration)
                index = declaration.range.upperBound
                continue
            }
            if let function = function(at: index, tokens: tokens) {
                functions.append(function)
                index = function.bodyRange.upperBound
                continue
            }
            index += 1
        }

        if let duplicate = duplicateDeclaration(declarations) {
            return failure(
                .duplicateDeclaration,
                "Shader declaration '\(duplicate.name)' is duplicated.",
                token: tokens[duplicate.range.lowerBound],
                stage: stage
            )
        }
        let mainFunctions = functions.filter { $0.name == "main" }
        guard mainFunctions.count == 1 else {
            return Output(unit: nil, diagnostics: [.init(
                code: mainFunctions.isEmpty ? .missingMain : .duplicateMain,
                message: mainFunctions.isEmpty
                    ? "Shader stage has no main function."
                    : "Shader stage defines main more than once.",
                stage: stage,
                line: mainFunctions.first?.line,
                column: nil
            )])
        }
        if let diagnostic = recursiveFunctionDiagnostic(
            functions: functions,
            tokens: tokens,
            stage: stage
        ) {
            return Output(unit: nil, diagnostics: [diagnostic])
        }
        let loopResult = requiresBoundedLoops ? SceneAuthoredShaderLoopAnalyzer.analyze(
            functions: functions,
            tokens: tokens,
            defines: lexerOutput.defines,
            declarations: declarations,
            provenRuntimeLoopBounds: provenRuntimeLoopBounds,
            stage: stage
        ) : nil
        if let loopResult, !loopResult.diagnostics.isEmpty {
            return Output(unit: nil, diagnostics: loopResult.diagnostics)
        }
        return Output(
            unit: .init(
                stage: stage,
                tokens: tokens,
                defines: lexerOutput.defines,
                declarations: declarations,
                functions: functions,
                staticLoopWork: max(1, loopResult?.work ?? 1),
                boundedLoopUniformReferences: loopResult?.boundedUniformReferences ?? [:],
                constantParameterArraysByFunctionIndex:
                    loopResult?.constantParameterArraysByFunctionIndex ?? [:],
                exactRuntimeLoopUniformArrays:
                    loopResult?.exactRuntimeLoopUniformArrays ?? []
            ),
            diagnostics: []
        )
    }

    static func declaration(
        at index: Int,
        storage: SceneAuthoredShaderSyntaxUnit.Storage,
        tokens: [SceneAuthoredShaderToken],
        stage: SceneShaderContract.StageKind
    ) -> SceneAuthoredShaderSyntaxUnit.Declaration? {
        guard index + 3 < tokens.count,
              tokens[index + 1].kind == .identifier,
              tokens[index + 2].kind == .identifier else {
            return nil
        }
        let typeName = tokens[index + 1].text
        let name = tokens[index + 2].text
        var cursor = index + 3
        if tokens[cursor].text == "." {
            // The authored fragment dialect admits this name suffix while
            // retaining the complete vec4 interface, including z/w reads.
            // It is not a projection or a general member declaration rule.
            guard stage == .fragment, storage == .varying, typeName == "vec4",
                  cursor + 2 < tokens.count,
                  tokens[cursor + 1].text == "xy",
                  tokens[cursor + 2].text == ";" else { return nil }
            cursor += 2
        }
        var arraySize: Int?
        if tokens[cursor].text == "[" {
            guard cursor + 2 < tokens.count,
                  let size = Int(tokens[cursor + 1].text),
                  size > 0,
                  tokens[cursor + 2].text == "]" else {
                return nil
            }
            arraySize = size
            cursor += 3
        }
        guard cursor < tokens.count, tokens[cursor].text == ";" else { return nil }
        return .init(
            storage: storage,
            typeName: typeName,
            name: name,
            arraySize: arraySize,
            range: index..<(cursor + 1),
            line: tokens[index].line
        )
    }

    private static func function(
        at index: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> SceneAuthoredShaderSyntaxUnit.Function? {
        guard index + 3 < tokens.count,
              tokens[index].kind == .identifier,
              tokens[index + 1].kind == .identifier,
              tokens[index + 2].text == "(",
              let close = matchingDelimiter(at: index + 2, tokens: tokens),
              close + 1 < tokens.count,
              tokens[close + 1].text == "{",
              let bodyClose = matchingDelimiter(at: close + 1, tokens: tokens) else {
            return nil
        }
        return .init(
            name: tokens[index + 1].text,
            returnType: tokens[index].text,
            headerRange: index..<(close + 1),
            parameterRange: (index + 3)..<close,
            bodyRange: (close + 1)..<(bodyClose + 1),
            line: tokens[index].line
        )
    }

    private static func duplicateDeclaration(
        _ declarations: [SceneAuthoredShaderSyntaxUnit.Declaration]
    ) -> SceneAuthoredShaderSyntaxUnit.Declaration? {
        var names: Set<String> = []
        return declarations.first { !names.insert($0.name).inserted }
    }

    private static func delimiterDiagnostic(
        tokens: [SceneAuthoredShaderToken],
        stage: SceneShaderContract.StageKind
    ) -> SceneAuthoredShaderFrontendDiagnostic? {
        let pairs: [String: String] = [")": "(", "]": "[", "}": "{"]
        var stack: [SceneAuthoredShaderToken] = []
        for token in tokens {
            if ["(", "[", "{"].contains(token.text) {
                stack.append(token)
            } else if let opening = pairs[token.text] {
                guard stack.last?.text == opening else {
                    return diagnostic(
                        .unbalancedDelimiter,
                        "Shader delimiter '\(token.text)' is unbalanced.",
                        token: token,
                        stage: stage
                    )
                }
                stack.removeLast()
            }
        }
        guard let token = stack.last else { return nil }
        return diagnostic(
            .unbalancedDelimiter,
            "Shader delimiter '\(token.text)' is not closed.",
            token: token,
            stage: stage
        )
    }

    static func matchingDelimiter(
        at index: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]
        guard tokens.indices.contains(index),
              let closing = pairs[tokens[index].text] else {
            return nil
        }
        var depth = 0
        for cursor in index..<tokens.count {
            if tokens[cursor].text == tokens[index].text { depth += 1 }
            if tokens[cursor].text == closing {
                depth -= 1
                if depth == 0 { return cursor }
            }
        }
        return nil
    }

    private static func recursiveFunctionDiagnostic(
        functions: [SceneAuthoredShaderSyntaxUnit.Function],
        tokens: [SceneAuthoredShaderToken],
        stage: SceneShaderContract.StageKind
    ) -> SceneAuthoredShaderFrontendDiagnostic? {
        let indicesByName = Dictionary(grouping: functions.indices) {
            functions[$0].name
        }
        let graph = Dictionary(uniqueKeysWithValues: functions.indices.map { functionIndex in
            let function = functions[functionIndex]
            let calls = function.bodyRange.flatMap { index -> [Int] in
                guard index + 1 < tokens.count,
                      tokens[index + 1].text == "(" else { return [] }
                return indicesByName[tokens[index].text] ?? []
            }
            return (functionIndex, Set(calls))
        })
        func visits(_ index: Int, path: Set<Int>) -> Bool {
            guard !path.contains(index) else { return true }
            return graph[index, default: []].contains {
                visits($0, path: path.union([index]))
            }
        }
        guard let functionIndex = functions.indices.first(where: { visits($0, path: []) }) else {
            return nil
        }
        let function = functions[functionIndex]
        return .init(
            code: .recursiveFunction,
            message: "Shader function '\(function.name)' is recursive.",
            stage: stage,
            line: function.line,
            column: nil
        )
    }

    private static func failure(
        _ code: SceneAuthoredShaderFrontendDiagnostic.Code,
        _ message: String,
        token: SceneAuthoredShaderToken,
        stage: SceneShaderContract.StageKind
    ) -> Output {
        Output(unit: nil, diagnostics: [diagnostic(code, message, token: token, stage: stage)])
    }

    private static func diagnostic(
        _ code: SceneAuthoredShaderFrontendDiagnostic.Code,
        _ message: String,
        token: SceneAuthoredShaderToken,
        stage: SceneShaderContract.StageKind
    ) -> SceneAuthoredShaderFrontendDiagnostic {
        .init(
            code: code,
            message: message,
            stage: stage,
            line: token.line,
            column: token.column
        )
    }
}

/// Source-text facts shared by the authored shader frontend and the generic
/// shader preparation. This file is compiled by every harness source subset that
/// contains a caller, which is what lets the helpers live in exactly one place.
nonisolated enum SceneShaderSourceTextFacts {
    static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }

    static func countWord(_ word: String, in source: String) -> Int {
        // `\b` around an escaped word is always a valid pattern, so compilation
        // cannot fail; fixed patterns follow the reviewed try! policy instead of
        // silently counting zero.
        try! NSRegularExpression(pattern: #"\b"# + escaped(word) + #"\b"#).matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).count
    }
}

extension SceneShaderSourceTextFacts {
    static func containsWord(_ word: String, in source: String) -> Bool {
        countWord(word, in: source) > 0
    }

    static func substring(_ range: NSRange, in source: String) -> String? {
        Range(range, in: source).map { String(source[$0]) }
    }

    /// Slot of a `g_TextureN` name; only `g_Texture0` … `g_Texture7` are slots.
    static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }
}

extension SceneShaderSourceTextFacts {
    /// Family regex entry point. Every pattern reaching it was audited
    /// (2026-09-29) to be a literal or a concatenation of escaped/digit text, so
    /// compilation cannot fail; a silent empty result would hide a broken pattern
    /// behind "no matches", which the reviewed policy forbids for fixed patterns.
    static func matches(
        _ pattern: String,
        in source: String,
        range: NSRange? = nil
    ) -> [NSTextCheckingResult] {
        try! NSRegularExpression(pattern: pattern).matches(
            in: source,
            range: range ?? NSRange(source.startIndex..., in: source)
        )
    }

    static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else { return nil }
        return String(source[range])
    }
}

/// Token-level scanners shared by the authored-shader analyzers. They read
/// `SceneAuthoredShaderToken` runs only; nothing here touches source text.
nonisolated enum SceneAuthoredShaderTokenScanner {}

extension SceneAuthoredShaderTokenScanner {
    /// Parentheses preserve an lvalue; a constructor/call creates a value.
    /// Peel only grouping around this exact reference before checking writes
    /// and indexing, so `(value.xy) += ...` cannot masquerade as a pure read.
    static func isReadOnlyValueUse(
        start: Int,
        end: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>,
        permitsReturn: Bool = false
    ) -> Bool {
        var lower = start
        var upper = end
        while lower > body.lowerBound, upper < body.upperBound,
              tokens[lower - 1].text == "(", tokens[upper].text == ")" {
            if lower >= body.lowerBound + 2,
               tokens[lower - 2].kind == .identifier,
               tokens[lower - 2].text != "return" { break }
            lower -= 1
            upper += 1
        }
        let forbiddenPrefix = permitsReturn ? ["++", "--"] : ["return", "++", "--"]
        return (lower == body.lowerBound
            || !forbiddenPrefix.contains(tokens[lower - 1].text))
            && (upper == body.upperBound
            || !["=", "+=", "-=", "*=", "/=", "%=", "++", "--", ".", "[", "]"]
                .contains(tokens[upper].text))
    }

    /// A one-token identifier; the ternary form of the same predicate that the
    /// analyzers used locally.
    static func identifier(_ tokens: ArraySlice<SceneAuthoredShaderToken>) -> String? {
        guard tokens.count == 1, tokens.first?.kind == .identifier else { return nil }
        return tokens.first?.text
    }

    static func argumentRanges(
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            switch tokens[index].text {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth < 0 { return nil }
            case "," where depth == 0:
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            default: break
            }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    static func commaRanges(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        guard !range.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" { depth -= 1 }
            if tokens[index].text == ",", depth == 0 {
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    static func matchingClose(_ open: Int, tokens: [SceneAuthoredShaderToken]) -> Int? {
        guard tokens.indices.contains(open), tokens[open].text == "(" else {
            return nil
        }
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    static func matchingParenthesis(
        tokens: [SceneAuthoredShaderToken],
        opening: Int
    ) -> Int? {
        var depth = 0
        for index in opening..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    static func split(
        _ range: Range<Int>,
        separator: String,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            let text = tokens[index].text
            if ["(", "["].contains(text) { depth += 1 }
            if [")", "]"].contains(text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if text == separator, depth == 0 {
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    static func split(
        _ tokens: ArraySlice<SceneAuthoredShaderToken>
    ) -> [ArraySlice<SceneAuthoredShaderToken>] {
        guard !tokens.isEmpty else { return [] }
        var result: [ArraySlice<SceneAuthoredShaderToken>] = []
        var depth = 0
        var start = tokens.startIndex
        for index in tokens.indices {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return [] }
                result.append(tokens[start..<index])
                start = index + 1
            default: break
            }
            guard depth >= 0 else { return [] }
        }
        guard depth == 0, start < tokens.endIndex else { return [] }
        result.append(tokens[start..<tokens.endIndex])
        return result
    }

    static func split(
        range: Range<Int>,
        separator: String,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            if depth == 0, tokens[index].text == separator {
                result.append(start..<index)
                start = index + 1
            }
        }
        result.append(start..<range.upperBound)
        return result
    }

}

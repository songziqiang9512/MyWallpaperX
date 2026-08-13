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
}

nonisolated enum SceneAuthoredShaderSyntaxAnalyzer {
    struct Output {
        let unit: SceneAuthoredShaderSyntaxUnit?
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private static let forbiddenControlFlow: Set<String> = [
        "while", "do", "switch", "goto", "discard",
    ]

    static func analyze(
        lexerOutput: SceneAuthoredShaderLexer.Output,
        stage: SceneShaderContract.StageKind,
        provenRuntimeLoopBounds: [String: Int] = [:]
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
                    tokens: tokens
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
        let loopResult = SceneAuthoredShaderLoopAnalyzer.analyze(
            functions: functions,
            tokens: tokens,
            defines: lexerOutput.defines,
            declarations: declarations,
            provenRuntimeLoopBounds: provenRuntimeLoopBounds,
            stage: stage
        )
        guard loopResult.diagnostics.isEmpty else {
            return Output(unit: nil, diagnostics: loopResult.diagnostics)
        }
        return Output(
            unit: .init(
                stage: stage,
                tokens: tokens,
                defines: lexerOutput.defines,
                declarations: declarations,
                functions: functions,
                staticLoopWork: max(1, loopResult.work),
                boundedLoopUniformReferences: loopResult.boundedUniformReferences,
                constantParameterArraysByFunctionIndex:
                    loopResult.constantParameterArraysByFunctionIndex
            ),
            diagnostics: []
        )
    }

    private static func declaration(
        at index: Int,
        storage: SceneAuthoredShaderSyntaxUnit.Storage,
        tokens: [SceneAuthoredShaderToken]
    ) -> SceneAuthoredShaderSyntaxUnit.Declaration? {
        guard index + 3 < tokens.count,
              tokens[index + 1].kind == .identifier,
              tokens[index + 2].kind == .identifier else {
            return nil
        }
        let typeName = tokens[index + 1].text
        let name = tokens[index + 2].text
        var cursor = index + 3
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

    private static func matchingDelimiter(
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

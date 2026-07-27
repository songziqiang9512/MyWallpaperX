import Foundation

nonisolated enum SceneAuthoredShaderLoopAnalyzer {
    struct Output {
        let work: Int
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private struct FunctionWork {
        var loopWork = 0
        var calls: [Int: Int] = [:]
    }

    private static let maximumLoopIterations = 256
    private static let maximumStaticLoopWork = 4_096

    static func analyze(
        functions: [SceneAuthoredShaderSyntaxUnit.Function],
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String],
        stage: SceneShaderContract.StageKind
    ) -> Output {
        let indicesByName = Dictionary(grouping: functions.indices) {
            functions[$0].name
        }
        var directWork: [Int: FunctionWork] = [:]
        for index in functions.indices {
            let result = functionWork(
                in: functions[index].bodyRange,
                tokens: tokens,
                defines: defines,
                functionIndicesByName: indicesByName,
                multiplier: 1,
                stage: stage
            )
            if !result.diagnostics.isEmpty {
                return Output(work: 0, diagnostics: result.diagnostics)
            }
            directWork[index] = result.work
        }
        guard let mainIndex = functions.indices.first(where: {
            functions[$0].name == "main"
        }) else {
            return Output(work: 0, diagnostics: [])
        }
        let total = expandedWork(
            for: mainIndex,
            directWork: directWork,
            path: []
        )
        guard total <= maximumStaticLoopWork else {
            return Output(work: total, diagnostics: [.init(
                code: .loopBudgetExceeded,
                message: "Shader expanded static work \(total) exceeds \(maximumStaticLoopWork).",
                stage: stage,
                line: nil,
                column: nil
            )])
        }
        return Output(work: total, diagnostics: [])
    }

    private struct FunctionWorkOutput {
        let work: FunctionWork
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private static func functionWork(
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String],
        functionIndicesByName: [String: [Int]],
        multiplier: Int,
        stage: SceneShaderContract.StageKind
    ) -> FunctionWorkOutput {
        var cursor = range.lowerBound
        var result = FunctionWork()
        while cursor < range.upperBound {
            guard tokens[cursor].text == "for" else {
                if cursor + 1 < tokens.count,
                   tokens[cursor + 1].text == "(",
                   let functionIndices = functionIndicesByName[tokens[cursor].text] {
                    for functionIndex in functionIndices {
                        guard add(multiplier, to: &result.calls[functionIndex, default: 0]) else {
                            return budgetFailure(token: tokens[cursor], stage: stage)
                        }
                    }
                }
                cursor += 1
                continue
            }
            guard cursor + 1 < tokens.count,
                  tokens[cursor + 1].text == "(",
                  let close = matchingDelimiter(at: cursor + 1, tokens: tokens),
                  let iterations = loopIterations(
                      header: (cursor + 2)..<close,
                      tokens: tokens,
                      defines: defines
                  ),
                  iterations <= maximumLoopIterations,
                  let body = statementRange(after: close, tokens: tokens) else {
                return FunctionWorkOutput(work: .init(), diagnostics: [diagnostic(
                    "Shader for-loop must have a static bound of at most \(maximumLoopIterations).",
                    token: tokens[cursor],
                    stage: stage
                )])
            }
            let (weightedIterations, overflow) = multiplier.multipliedReportingOverflow(
                by: iterations
            )
            guard !overflow,
                  add(weightedIterations, to: &result.loopWork) else {
                return budgetFailure(token: tokens[cursor], stage: stage)
            }
            let nested = functionWork(
                in: body,
                tokens: tokens,
                defines: defines,
                functionIndicesByName: functionIndicesByName,
                multiplier: weightedIterations,
                stage: stage
            )
            if !nested.diagnostics.isEmpty { return nested }
            guard merge(nested.work, into: &result) else {
                return budgetFailure(token: tokens[cursor], stage: stage)
            }
            cursor = body.upperBound
        }
        return FunctionWorkOutput(work: result, diagnostics: [])
    }

    private static func expandedWork(
        for index: Int,
        directWork: [Int: FunctionWork],
        path: Set<Int>
    ) -> Int {
        guard !path.contains(index), let direct = directWork[index] else {
            return maximumStaticLoopWork + 1
        }
        var total = max(1, direct.loopWork)
        let nextPath = path.union([index])
        for (callee, count) in direct.calls {
            let expanded = expandedWork(
                for: callee,
                directWork: directWork,
                path: nextPath
            )
            let (weighted, productOverflow) = count.multipliedReportingOverflow(by: expanded)
            let (next, sumOverflow) = total.addingReportingOverflow(weighted)
            if productOverflow || sumOverflow || next > maximumStaticLoopWork {
                return maximumStaticLoopWork + 1
            }
            total = next
        }
        return total
    }

    private static func add(_ value: Int, to target: inout Int) -> Bool {
        let (next, overflow) = target.addingReportingOverflow(value)
        guard !overflow, next <= maximumStaticLoopWork else { return false }
        target = next
        return true
    }

    private static func merge(_ source: FunctionWork, into target: inout FunctionWork) -> Bool {
        guard add(source.loopWork, to: &target.loopWork) else { return false }
        for (index, count) in source.calls {
            guard add(count, to: &target.calls[index, default: 0]) else { return false }
        }
        return true
    }

    private static func budgetFailure(
        token: SceneAuthoredShaderToken,
        stage: SceneShaderContract.StageKind
    ) -> FunctionWorkOutput {
        .init(work: .init(), diagnostics: [.init(
            code: .loopBudgetExceeded,
            message: "Shader expanded static work exceeds \(maximumStaticLoopWork).",
            stage: stage,
            line: token.line,
            column: token.column
        )])
    }

    private static func loopIterations(
        header: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String]
    ) -> Int? {
        let parts = split(range: header, separator: ";", tokens: tokens)
        guard parts.count == 3 else { return nil }
        var initialization = Array(tokens[parts[0]].map(\.text))
        if initialization.first == "int" { initialization.removeFirst() }
        guard initialization.count == 3,
              initialization[1] == "=",
              let start = integer(initialization[2], defines: defines) else {
            return nil
        }
        let variable = initialization[0]
        let condition = Array(tokens[parts[1]].map(\.text))
        guard condition.count == 3,
              condition[0] == variable,
              ["<", "<="].contains(condition[1]),
              let end = integer(condition[2], defines: defines) else {
            return nil
        }
        let increment = Array(tokens[parts[2]].map(\.text))
        let step: Int
        if increment == [variable, "++"] || increment == ["++", variable] {
            step = 1
        } else if increment.count == 3,
                  increment[0] == variable,
                  increment[1] == "+=",
                  let value = integer(increment[2], defines: defines), value > 0 {
            step = value
        } else {
            return nil
        }
        let distance = end - start + (condition[1] == "<=" ? 1 : 0)
        return distance <= 0 ? 0 : (distance + step - 1) / step
    }

    private static func integer(_ token: String, defines: [String: String]) -> Int? {
        Int(defines[token] ?? token)
    }

    private static func split(
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

    private static func statementRange(
        after index: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Range<Int>? {
        let start = index + 1
        guard start < tokens.count else { return nil }
        if tokens[start].text == "{", let close = matchingDelimiter(at: start, tokens: tokens) {
            return (start + 1)..<close
        }
        if tokens[start].text == "for",
           start + 1 < tokens.count,
           tokens[start + 1].text == "(",
           let close = matchingDelimiter(at: start + 1, tokens: tokens),
           let nested = statementRange(after: close, tokens: tokens) {
            return start..<nested.upperBound
        }
        guard let end = tokens[start...].firstIndex(where: { $0.text == ";" }) else { return nil }
        return start..<(end + 1)
    }

    private static func matchingDelimiter(
        at index: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]
        guard let closing = pairs[tokens[index].text] else { return nil }
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

    private static func diagnostic(
        _ message: String,
        token: SceneAuthoredShaderToken,
        stage: SceneShaderContract.StageKind
    ) -> SceneAuthoredShaderFrontendDiagnostic {
        .init(
            code: .dynamicLoop,
            message: message,
            stage: stage,
            line: token.line,
            column: token.column
        )
    }
}

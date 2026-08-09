import Foundation

nonisolated enum SceneAuthoredShaderLoopAnalyzer {
    struct Output {
        let work: Int
        let boundedUniformReferences: [SceneAuthoredShaderToken: Int]
        let constantParameterArraysByFunctionIndex: [Int: Set<String>]
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private struct FunctionWork {
        var loopWork = 0
        var calls: [Int: Int] = [:]
        var boundedUniformReferences: [SceneAuthoredShaderToken: Int] = [:]
        var constantParameterArrays: Set<String> = []
    }

    private static let maximumLoopIterations = 256
    private static let maximumStaticLoopWork = 4_096

    static func analyze(
        functions: [SceneAuthoredShaderSyntaxUnit.Function],
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String],
        declarations: [SceneAuthoredShaderSyntaxUnit.Declaration],
        provenRuntimeLoopBounds: [String: Int],
        stage: SceneShaderContract.StageKind
    ) -> Output {
        let indicesByName = Dictionary(grouping: functions.indices) {
            functions[$0].name
        }
        var directWork: [Int: FunctionWork] = [:]
        for index in functions.indices {
            let result = functionWork(
                in: functions[index].bodyRange,
                functionBody: functions[index].bodyRange,
                tokens: tokens,
                defines: defines,
                declarations: declarations,
                parameterArrays: SceneAuthoredShaderBoundedLoopAdmission.parameterArrays(
                    in: functions[index].parameterRange,
                    tokens: tokens
                ),
                parameterRange: functions[index].parameterRange,
                provenRuntimeLoopBounds: provenRuntimeLoopBounds,
                functionIndicesByName: indicesByName,
                multiplier: 1,
                stage: stage
            )
            if !result.diagnostics.isEmpty {
                return Output(
                    work: 0,
                    boundedUniformReferences: [:],
                    constantParameterArraysByFunctionIndex: [:],
                    diagnostics: result.diagnostics
                )
            }
            directWork[index] = result.work
        }
        guard let mainIndex = functions.indices.first(where: {
            functions[$0].name == "main"
        }) else {
            return Output(
                work: 0,
                boundedUniformReferences: [:],
                constantParameterArraysByFunctionIndex: [:],
                diagnostics: []
            )
        }
        let total = expandedWork(
            for: mainIndex,
            directWork: directWork,
            path: []
        )
        guard total <= maximumStaticLoopWork else {
            return Output(
                work: total,
                boundedUniformReferences: [:],
                constantParameterArraysByFunctionIndex: [:],
                diagnostics: [.init(
                code: .loopBudgetExceeded,
                message: "Shader expanded static work \(total) exceeds \(maximumStaticLoopWork).",
                stage: stage,
                line: nil,
                column: nil
            )])
        }
        var bounds: [SceneAuthoredShaderToken: Int] = [:]
        for work in directWork.values {
            guard SceneAuthoredShaderBoundedLoopAdmission.mergeBounds(
                work.boundedUniformReferences,
                into: &bounds
            ) else {
                return Output(
                    work: total,
                    boundedUniformReferences: [:],
                    constantParameterArraysByFunctionIndex: [:],
                    diagnostics: [.init(
                    code: .dynamicLoop,
                    message: "One loop-bound uniform has conflicting array extents.",
                    stage: stage,
                    line: nil,
                    column: nil
                )])
            }
        }
        let constantArrays = directWork.compactMapValues { work in
            work.constantParameterArrays.isEmpty ? nil : work.constantParameterArrays
        }
        return Output(
            work: total,
            boundedUniformReferences: bounds,
            constantParameterArraysByFunctionIndex: constantArrays,
            diagnostics: []
        )
    }

    private struct FunctionWorkOutput {
        let work: FunctionWork
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private static func functionWork(
        in range: Range<Int>,
        functionBody: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String],
        declarations: [SceneAuthoredShaderSyntaxUnit.Declaration],
        parameterArrays: [String: Int],
        parameterRange: Range<Int>,
        provenRuntimeLoopBounds: [String: Int],
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
                  let body = statementRange(after: close, tokens: tokens),
                  let loop = loopAdmission(
                      header: (cursor + 2)..<close,
                      body: body,
                      functionBody: functionBody,
                      loopIndex: cursor,
                      tokens: tokens,
                      defines: defines,
                      declarations: declarations,
                      parameterArrays: parameterArrays,
                      parameterRange: parameterRange,
                      provenRuntimeLoopBounds: provenRuntimeLoopBounds
                  ),
                  loop.iterations <= maximumLoopIterations,
                  SceneAuthoredShaderBoundedLoopAdmission.mergeBounds(
                      loop.boundedUniformReferences,
                      into: &result.boundedUniformReferences
                  ) else {
                return FunctionWorkOutput(work: .init(), diagnostics: [diagnostic(
                    "Shader for-loop must have a static bound of at most \(maximumLoopIterations).",
                    token: tokens[cursor],
                    stage: stage
                )])
            }
            result.constantParameterArrays.formUnion(loop.constantParameterArrays)
            let iterations = loop.iterations
            let (weightedIterations, overflow) = multiplier.multipliedReportingOverflow(
                by: iterations
            )
            guard !overflow,
                  add(weightedIterations, to: &result.loopWork) else {
                return budgetFailure(token: tokens[cursor], stage: stage)
            }
            let nested = functionWork(
                in: body,
                functionBody: functionBody,
                tokens: tokens,
                defines: defines,
                declarations: declarations,
                parameterArrays: parameterArrays,
                parameterRange: parameterRange,
                provenRuntimeLoopBounds: provenRuntimeLoopBounds,
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
        guard add(source.loopWork, to: &target.loopWork),
              SceneAuthoredShaderBoundedLoopAdmission.mergeBounds(
                  source.boundedUniformReferences,
                  into: &target.boundedUniformReferences
              ) else { return false }
        target.constantParameterArrays.formUnion(source.constantParameterArrays)
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

    private static func loopAdmission(
        header: Range<Int>,
        body: Range<Int>,
        functionBody: Range<Int>,
        loopIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String],
        declarations: [SceneAuthoredShaderSyntaxUnit.Declaration],
        parameterArrays: [String: Int],
        parameterRange: Range<Int>,
        provenRuntimeLoopBounds: [String: Int]
    ) -> SceneAuthoredShaderBoundedLoopAdmission.Result? {
        if let iterations = SceneAuthoredShaderStaticLoopAdmission.iterations(
            header: header,
            functionBody: functionBody,
            loopIndex: loopIndex,
            tokens: tokens,
            defines: defines
        ) {
            return .init(
                iterations: iterations,
                boundedUniformReferences: [:],
                constantParameterArrays: []
            )
        }
        if let iterations = SceneAuthoredShaderStaticLoopAdmission.earlyExitIterations(
            header: header,
            functionBody: functionBody,
            loopIndex: loopIndex,
            tokens: tokens,
            defines: defines
        ) {
            return .init(
                iterations: iterations,
                boundedUniformReferences: [:],
                constantParameterArrays: []
            )
        }
        if let bounded = SceneAuthoredShaderBoundedLoopAdmission.compile(
            header: header,
            body: body,
            tokens: tokens,
            declarations: declarations,
            parameterArrays: parameterArrays
        ) { return bounded }
        guard let iterations = SceneAuthoredShaderRuntimeLoopAdmission.iterations(
            header: header,
            body: body,
            functionBody: functionBody,
            parameterRange: parameterRange,
            tokens: tokens,
            declarations: declarations,
            provenBounds: provenRuntimeLoopBounds
        ) else { return nil }
        return .init(
            iterations: iterations,
            boundedUniformReferences: [:],
            constantParameterArrays: []
        )
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

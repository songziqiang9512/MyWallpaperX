nonisolated enum SceneAuthoredShaderFunctionSemantics {
    static func diagnostics(
        for unit: SceneAuthoredShaderSyntaxUnit
    ) -> [SceneAuthoredShaderFrontendDiagnostic] {
        mutableParameterDiagnostics(for: unit) + inverseDiagnostics(for: unit)
    }

    static func mutableParameterNames(
        for function: SceneAuthoredShaderSyntaxUnit.Function,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Set<String> {
        Set(parameterRanges(function, unit: unit).compactMap { range in
            let tokens = unit.tokens[range]
            guard tokens.count == 3,
                  tokens[tokens.startIndex].text == "inout",
                  SceneAuthoredShaderValueType(
                      authoredName: tokens[tokens.startIndex + 1].text
                  ) != nil,
                  tokens[tokens.startIndex + 2].kind == .identifier else {
                return nil
            }
            return tokens[tokens.startIndex + 2].text
        })
    }

    static func usesFloat3x3Inverse(
        _ unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        guard !unit.functions.contains(where: { $0.name == "inverse" }) else {
            return false
        }
        return unit.tokens.indices.contains { index in
            unit.tokens[index].text == "inverse"
                && index + 1 < unit.tokens.count
                && unit.tokens[index + 1].text == "("
        }
    }

    private static func mutableParameterDiagnostics(
        for unit: SceneAuthoredShaderSyntaxUnit
    ) -> [SceneAuthoredShaderFrontendDiagnostic] {
        unit.tokens.indices.compactMap { index in
            let token = unit.tokens[index]
            guard token.text == "inout" else { return nil }
            guard let function = unit.functions.first(where: {
                $0.parameterRange.contains(index)
            }), let range = parameterRanges(function, unit: unit).first(where: {
                $0.contains(index)
            }) else {
                return diagnostic(
                    "The inout qualifier is only supported on function parameters.",
                    token: token,
                    unit: unit
                )
            }
            let parameter = unit.tokens[range]
            guard parameter.count == 3,
                  index == range.lowerBound,
                  SceneAuthoredShaderValueType(
                      authoredName: parameter[range.lowerBound + 1].text
                  ) != nil,
                  parameter[range.lowerBound + 2].kind == .identifier else {
                return diagnostic(
                    "Only bounded 'inout value-type name' parameters are supported.",
                    token: token,
                    unit: unit
                )
            }
            return nil
        }
    }

    private static func inverseDiagnostics(
        for unit: SceneAuthoredShaderSyntaxUnit
    ) -> [SceneAuthoredShaderFrontendDiagnostic] {
        guard !unit.functions.contains(where: { $0.name == "inverse" }) else {
            return []
        }
        return unit.tokens.indices.compactMap { index in
            let token = unit.tokens[index]
            guard token.text == "inverse" else { return nil }
            guard index + 1 < unit.tokens.count,
                  unit.tokens[index + 1].text == "(",
                  let closing = SceneAuthoredShaderVectorConversion.matchingParenthesis(
                      tokens: unit.tokens,
                      opening: index + 1
                  ),
                  expressionType(
                      in: (index + 2)..<closing,
                      before: index,
                      unit: unit
                  ) == .float3x3 else {
                return diagnostic(
                    "Only statically typed mat3 inverse calls are supported.",
                    token: token,
                    unit: unit
                )
            }
            return nil
        }
    }

    private static func expressionType(
        in rawRange: Range<Int>,
        before limit: Int,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        let range = strippingParentheses(rawRange, tokens: unit.tokens)
        guard !range.isEmpty else { return nil }
        if range.count == 1 {
            return declaredType(
                of: unit.tokens[range.lowerBound].text,
                before: limit,
                unit: unit
            )
        }
        guard range.count >= 3,
              unit.tokens[range.lowerBound].kind == .identifier,
              unit.tokens[range.lowerBound + 1].text == "(",
              SceneAuthoredShaderVectorConversion.matchingParenthesis(
                  tokens: unit.tokens,
                  opening: range.lowerBound + 1
              ) == range.upperBound - 1 else {
            return nil
        }
        let name = unit.tokens[range.lowerBound].text
        if let constructor = SceneAuthoredShaderValueType(authoredName: name) {
            return constructor
        }
        let returnTypes = Set(unit.functions.compactMap { function in
            function.name == name
                ? SceneAuthoredShaderValueType(authoredName: function.returnType)
                : nil
        })
        guard returnTypes.count == 1 else { return nil }
        return returnTypes.first
    }

    private static func declaredType(
        of name: String,
        before limit: Int,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        var types = Set(unit.declarations.compactMap { declaration in
            declaration.name == name
                ? SceneAuthoredShaderValueType(authoredName: declaration.typeName)
                : nil
        })
        if limit > 0 {
            for index in 0..<limit where index + 1 < unit.tokens.count {
                guard unit.tokens[index + 1].text == name,
                      let type = SceneAuthoredShaderValueType(
                          authoredName: unit.tokens[index].text
                      ) else { continue }
                types.insert(type)
            }
        }
        guard types.count == 1 else { return nil }
        return types.first
    }

    private static func strippingParentheses(
        _ initial: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Range<Int> {
        var range = initial
        while range.count >= 2,
              tokens[range.lowerBound].text == "(",
              SceneAuthoredShaderVectorConversion.matchingParenthesis(
                  tokens: tokens,
                  opening: range.lowerBound
              ) == range.upperBound - 1 {
            range = (range.lowerBound + 1)..<(range.upperBound - 1)
        }
        return range
    }

    private static func parameterRanges(
        _ function: SceneAuthoredShaderSyntaxUnit.Function,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> [Range<Int>] {
        guard !function.parameterRange.isEmpty else { return [] }
        var ranges: [Range<Int>] = []
        var start = function.parameterRange.lowerBound
        var depth = 0
        for index in function.parameterRange.lowerBound...function.parameterRange.upperBound {
            let isEnd = index == function.parameterRange.upperBound
            if !isEnd {
                if ["(", "["].contains(unit.tokens[index].text) { depth += 1 }
                if [")", "]"].contains(unit.tokens[index].text) { depth -= 1 }
            }
            guard isEnd || (depth == 0 && unit.tokens[index].text == ",") else {
                continue
            }
            ranges.append(start..<index)
            start = index + 1
        }
        return ranges
    }

    private static func diagnostic(
        _ message: String,
        token: SceneAuthoredShaderToken,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderFrontendDiagnostic {
        .init(
            code: .unsupportedDeclaration,
            message: message,
            stage: unit.stage,
            line: token.line,
            column: token.column
        )
    }
}

import Foundation

/// Admits the narrow Wallpaper Engine/HLSL runtime-loop shape whose bound is
/// proven by the resolved producer domain. The authored control flow and bound
/// expression remain unchanged in emitted Metal.
nonisolated enum SceneAuthoredShaderRuntimeLoopAdmission {
    static func iterations(
        header: Range<Int>,
        body: Range<Int>,
        functionBody: Range<Int>,
        parameterRange: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        declarations: [SceneAuthoredShaderSyntaxUnit.Declaration],
        provenBounds: [String: Int]
    ) -> Int? {
        let parts = split(range: header, separator: ";", tokens: tokens)
        guard parts.count == 3 else { return nil }
        let initialization = Array(parts[0])
        guard initialization.count == 4,
              tokens[initialization[0]].text == "int",
              tokens[initialization[1]].kind == .identifier,
              tokens[initialization[2]].text == "=",
              let start = SceneAuthoredShaderLoopIntegerLiteral.value(
                  [tokens[initialization[3]].text],
                  defines: [:]
              ) else { return nil }
        let variable = tokens[initialization[1]].text

        let condition = Array(parts[1])
        guard condition.count == 6,
              tokens[condition[0]].text == variable,
              ["<", "<="].contains(tokens[condition[1]].text),
              tokens[condition[2]].text == "int",
              tokens[condition[3]].text == "(",
              tokens[condition[4]].kind == .identifier,
              tokens[condition[5]].text == ")",
              validIncrement(parts[2], variable: variable, tokens: tokens) else {
            return nil
        }
        let boundName = tokens[condition[4]].text
        guard let maximum = provenBounds[boundName],
              isScalarFloatUniform(boundName, declarations: declarations),
              !parameterRange.contains(where: { tokens[$0].text == boundName }),
              !hasLocalDeclaration(boundName, in: functionBody, tokens: tokens),
              !isMutated(variable, in: body, tokens: tokens),
              !isMutated(boundName, in: functionBody, tokens: tokens),
              !isArrayIndex(variable, in: body, tokens: tokens) else { return nil }

        let inclusive = tokens[condition[1]].text == "<="
        return SceneAuthoredShaderLoopIterationCount.value(
            start: start, end: maximum, inclusive: inclusive, step: 1
        )
    }

    private static func isScalarFloatUniform(
        _ name: String,
        declarations: [SceneAuthoredShaderSyntaxUnit.Declaration]
    ) -> Bool {
        declarations.contains {
            $0.storage == .uniform && $0.name == name
                && $0.typeName == "float" && $0.arraySize == nil
        }
    }

    private static func hasLocalDeclaration(
        _ name: String,
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        range.contains { index in
            guard tokens[index].text == name, index > range.lowerBound else { return false }
            return SceneAuthoredShaderValueType(
                authoredName: tokens[index - 1].text
            ) != nil
        }
    }

    private static func isMutated(
        _ name: String,
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        let operators: Set<String> = [
            "=", "+=", "-=", "*=", "/=", "%=", "++", "--",
        ]
        return range.contains { index in
            guard tokens[index].text == name else { return false }
            let previous = index > range.lowerBound ? tokens[index - 1].text : ""
            let next = index + 1 < range.upperBound ? tokens[index + 1].text : ""
            return operators.contains(previous) || operators.contains(next)
        }
    }

    private static func isArrayIndex(
        _ name: String,
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        var depth = 0
        for index in range {
            if tokens[index].text == "[" { depth += 1 }
            if tokens[index].text == name, depth > 0 { return true }
            if tokens[index].text == "]" { depth -= 1 }
        }
        return false
    }

    private static func validIncrement(
        _ range: Range<Int>,
        variable: String,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        let increment = Array(tokens[range].map(\.text))
        return increment == [variable, "++"] || increment == ["++", variable]
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
}

nonisolated enum SceneAuthoredShaderLoopIterationCount {
    static func value(start: Int, end: Int, inclusive: Bool, step: Int) -> Int? {
        guard step > 0 else { return nil }
        let (distance, subtractionOverflow) = end.subtractingReportingOverflow(start)
        guard !subtractionOverflow else { return nil }
        let (candidate, additionOverflow) = distance.addingReportingOverflow(
            inclusive ? 1 : 0
        )
        guard !additionOverflow else { return nil }
        return candidate <= 0 ? 0 : 1 + (candidate - 1) / step
    }
}

/// Parses exactly one optionally signed HLSL `int` literal. Expressions and
/// values outside Metal's 32-bit `int` domain remain unproven.
nonisolated enum SceneAuthoredShaderLoopIntegerLiteral {
    static func value(_ expression: [String], defines: [String: String]) -> Int? {
        guard (1 ... 2).contains(expression.count) else { return nil }
        let literal = defines[expression.last!] ?? expression.last!
        let sign = expression.count == 2 ? expression[0] : ""
        guard expression.count == 1 || sign == "+" || sign == "-",
              let value = Int32(sign + literal) else { return nil }
        return Int(value)
    }
}

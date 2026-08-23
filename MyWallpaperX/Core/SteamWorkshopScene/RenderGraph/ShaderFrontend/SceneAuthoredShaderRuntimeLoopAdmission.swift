import Foundation

/// Admits the narrow Wallpaper Engine/HLSL runtime-loop shape whose bound is
/// proven by the resolved producer domain. The authored control flow and bound
/// expression remain unchanged in emitted Metal.
nonisolated enum SceneAuthoredShaderRuntimeLoopAdmission {
    struct Result {
        let iterations: Int
        let uniformArrays: Set<String>
    }

    static func compile(
        header: Range<Int>,
        body: Range<Int>,
        functionBody: Range<Int>,
        parameterRange: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        declarations: [SceneAuthoredShaderSyntaxUnit.Declaration],
        provenBounds: [String: SceneAuthoredShaderExactScalarFact]
    ) -> Result? {
        let parts = split(range: header, separator: ";", tokens: tokens)
        guard parts.count == 3 else { return nil }
        let initialization = Array(parts[0])
        guard initialization.count >= 4,
              tokens[initialization[0]].text == "int",
              tokens[initialization[1]].kind == .identifier,
              tokens[initialization[2]].text == "=" else { return nil }
        let lowerExpression = Array(initialization.dropFirst(3))
        let lowerName = exactScalarName(lowerExpression, tokens: tokens)
        let exactLower = lowerName.flatMap { provenBounds[$0]?.value }
        let literalLower = SceneAuthoredShaderLoopIntegerLiteral.value(
            lowerExpression.map { tokens[$0].text }, defines: [:]
        )
        guard let lower = exactLower ?? literalLower else { return nil }
        let variable = tokens[initialization[1]].text

        let condition = Array(parts[1])
        guard condition.count >= 3,
              tokens[condition[0]].text == variable,
              ["<", "<="].contains(tokens[condition[1]].text),
              let upperName = exactScalarName(
                  Array(condition.dropFirst(2)), tokens: tokens
              ), let upper = provenBounds[upperName]?.value,
              validIncrement(parts[2], variable: variable, tokens: tokens) else {
            return nil
        }
        let lowerIsNotShadowed = lowerName.map {
            !hasLocalDeclaration($0, in: functionBody, tokens: tokens)
        } ?? true
        let lowerIsImmutable = lowerName.map {
            !isMutated($0, in: functionBody, tokens: tokens)
        } ?? true
        guard (lowerName == nil || isScalarFloatUniform(
                  lowerName!, declarations: declarations
              )), isScalarFloatUniform(upperName, declarations: declarations),
              !parameterRange.contains(where: {
                  [lowerName, upperName].compactMap { $0 }.contains(tokens[$0].text)
              }),
              lowerIsNotShadowed,
              !hasLocalDeclaration(upperName, in: functionBody, tokens: tokens),
              !isMutated(variable, in: body, tokens: tokens),
              lowerIsImmutable,
              !isMutated(upperName, in: functionBody, tokens: tokens) else { return nil }
        let hasArrayIndex = containsArrayIndex(variable, in: body, tokens: tokens)
        let arrays: [(name: String, extent: Int)]
        if hasArrayIndex {
            guard let proven = exactUniformArrayIndices(
                variable: variable,
                body: body,
                tokens: tokens,
                declarations: declarations
            ) else { return nil }
            arrays = proven
        } else {
            arrays = []
        }

        let inclusive = tokens[condition[1]].text == "<="
        guard lower >= 0 else { return nil }
        if !arrays.isEmpty {
            guard lowerName != nil, let minimumExtent = arrays.map(\.extent).min(),
                  lower >= 0, lower <= upper,
                  (inclusive ? upper < minimumExtent : upper <= minimumExtent) else {
                return nil
            }
        } else {
            // Preserve the earlier immutable upper-bound cohort, which does not
            // index an authored array and therefore needs no extent conjunction.
            guard lowerName == nil else { return nil }
        }
        guard let iterations = SceneAuthoredShaderLoopIterationCount.value(
            start: lower, end: upper, inclusive: inclusive, step: 1
        ) else { return nil }
        return .init(iterations: iterations, uniformArrays: Set(arrays.map(\.name)))
    }

    private static func exactScalarName(
        _ indices: [Int],
        tokens: [SceneAuthoredShaderToken]
    ) -> String? {
        if indices.count == 1, tokens[indices[0]].kind == .identifier {
            return tokens[indices[0]].text
        }
        guard indices.count == 4,
              tokens[indices[0]].text == "int",
              tokens[indices[1]].text == "(",
              tokens[indices[2]].kind == .identifier,
              tokens[indices[3]].text == ")" else { return nil }
        return tokens[indices[2]].text
    }

    private static func exactUniformArrayIndices(
        variable: String,
        body: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        declarations: [SceneAuthoredShaderSyntaxUnit.Declaration]
    ) -> [(name: String, extent: Int)]? {
        let variableUses = body.filter { tokens[$0].text == variable }
        guard !variableUses.isEmpty else { return [] }
        var arrays: [(String, Int)] = []
        for index in variableUses {
            guard index >= body.lowerBound + 2,
                  index + 1 < body.upperBound,
                  tokens[index - 2].kind == .identifier,
                  tokens[index - 1].text == "[",
                  tokens[index + 1].text == "]",
                  index + 2 >= body.upperBound || tokens[index + 2].text != "[" else {
                return nil
            }
            let name = tokens[index - 2].text
            let matches = declarations.filter { $0.name == name }
            guard matches.count == 1, let declaration = matches.first,
                  declaration.storage == .uniform,
                  declaration.typeName == "float",
                  let extent = declaration.arraySize,
                  (1 ... 256).contains(extent) else { return nil }
            arrays.append((name, extent))
        }
        let names = Set(arrays.map(\.0))
        for index in body where names.contains(tokens[index].text) {
            guard index + 3 < body.upperBound,
                  tokens[index + 1].text == "[",
                  tokens[index + 2].text == variable,
                  tokens[index + 3].text == "]" else { return nil }
        }
        return arrays
    }

    private static func containsArrayIndex(
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
        let assignments: Set<String> = ["=", "+=", "-=", "*=", "/=", "%="]
        let increments: Set<String> = ["++", "--"]
        return range.contains { index in
            guard tokens[index].text == name else { return false }
            let previous = index > range.lowerBound ? tokens[index - 1].text : ""
            let next = index + 1 < range.upperBound ? tokens[index + 1].text : ""
            return assignments.contains(next)
                || increments.contains(previous) || increments.contains(next)
        }
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

import Foundation

/// Makes the authored integer mask boundary explicit when a built-in `max`
/// combines one integer with a product of scalar `step` results. Each `step`
/// result is exactly zero or one, so the conversion preserves the authored
/// value without admitting general float-to-int coercion.
nonisolated enum SceneAuthoredShaderDiscreteMaskConversion {
    static func rewrite(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> String {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("#version")
                ? "" : line
        }.joined(separator: "\n")
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: analysisSource,
                stage: stage
            ),
            stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit,
              !unit.functions.contains(where: { ["max", "step"].contains($0.name) })
        else { return normalized }

        var lineStarts = [0]
        var scalarOffset = 0
        for scalar in normalized.unicodeScalars {
            scalarOffset += 1
            if scalar == "\n" { lineStarts.append(scalarOffset) }
        }
        func offset(_ index: Int, after: Bool) -> Int? {
            guard unit.tokens.indices.contains(index) else { return nil }
            let token = unit.tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else { return nil }
            return lineStarts[token.line - 1] + token.column - 1
                + (after ? token.text.unicodeScalars.count : 0)
        }

        var insertions: [(offset: Int, text: String)] = []
        for index in unit.tokens.indices {
            guard unit.tokens[index].text == "max", index >= 2,
                  unit.tokens[index - 1].text == "=",
                  unit.tokens[index - 2].kind == .identifier,
                  declaredType(
                      unit.tokens[index - 2].text,
                      before: index,
                      unit: unit
                  ) == .int,
                  index + 1 < unit.tokens.count,
                  unit.tokens[index + 1].text == "(",
                  let closing = SceneAuthoredShaderVectorConversion
                    .matchingParenthesis(tokens: unit.tokens, opening: index + 1),
                  closing + 1 < unit.tokens.count,
                  unit.tokens[closing + 1].text == ";",
                  let arguments = argumentRanges(
                      opening: index + 1,
                      closing: closing,
                      tokens: unit.tokens
                  ), arguments.count == 2 else { continue }
            let discrete: Range<Int>
            if isStandaloneInt(arguments[0], before: index, unit: unit),
               isStepProduct(arguments[1], before: index, unit: unit) {
                discrete = arguments[1]
            } else if isStandaloneInt(arguments[1], before: index, unit: unit),
                      isStepProduct(arguments[0], before: index, unit: unit) {
                discrete = arguments[0]
            } else {
                continue
            }
            guard let start = offset(discrete.lowerBound, after: false),
                  let end = offset(discrete.upperBound - 1, after: true) else {
                continue
            }
            insertions.append((start, "int("))
            insertions.append((end, ")"))
        }
        guard !insertions.isEmpty else { return normalized }

        var result = normalized
        for insertion in insertions.sorted(by: { lhs, rhs in
            lhs.offset != rhs.offset ? lhs.offset > rhs.offset : lhs.text == ")"
        }) {
            guard insertion.offset <= result.unicodeScalars.count else {
                return normalized
            }
            let scalarIndex = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: insertion.offset
            )
            guard let index = String.Index(scalarIndex, within: result) else {
                return normalized
            }
            result.insert(contentsOf: insertion.text, at: index)
        }
        return result
    }

    private static func isStandaloneInt(
        _ range: Range<Int>,
        before limit: Int,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        guard range.count == 1 else { return false }
        let token = unit.tokens[range.lowerBound]
        if token.kind == .number { return Int(token.text) != nil }
        return token.kind == .identifier
            && declaredType(token.text, before: limit, unit: unit) == .int
    }

    private static func isStepProduct(
        _ range: Range<Int>,
        before limit: Int,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        guard let factors = splitProduct(range, tokens: unit.tokens),
              !factors.isEmpty else { return false }
        return factors.allSatisfy { factor in
            guard factor.count >= 4,
                  unit.tokens[factor.lowerBound].text == "step",
                  unit.tokens[factor.lowerBound + 1].text == "(",
                  SceneAuthoredShaderVectorConversion.matchingParenthesis(
                      tokens: unit.tokens,
                      opening: factor.lowerBound + 1
                  ) == factor.upperBound - 1,
                  let arguments = argumentRanges(
                      opening: factor.lowerBound + 1,
                      closing: factor.upperBound - 1,
                      tokens: unit.tokens
                  ), arguments.count == 2 else { return false }
            return arguments.allSatisfy {
                isScalarNumeric($0, before: limit, unit: unit)
            }
        }
    }

    private static func isScalarNumeric(
        _ sourceRange: Range<Int>,
        before limit: Int,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        var range = sourceRange
        while range.count > 1, ["+", "-"].contains(unit.tokens[range.lowerBound].text) {
            range = (range.lowerBound + 1)..<range.upperBound
        }
        if range.count == 1 {
            let token = unit.tokens[range.lowerBound]
            if token.kind == .number { return true }
            guard token.kind == .identifier,
                  let type = declaredType(token.text, before: limit, unit: unit)
            else { return false }
            return [.float, .int, .uint].contains(type)
        }
        guard range.count == 3,
              unit.tokens[range.lowerBound].kind == .identifier,
              unit.tokens[range.lowerBound + 1].text == ".",
              unit.tokens[range.lowerBound + 2].kind == .identifier,
              unit.tokens[range.lowerBound + 2].text.count == 1,
              unit.tokens[range.lowerBound + 2].text.allSatisfy({
                  "xyzwrgba".contains($0)
              }),
              let type = declaredType(
                  unit.tokens[range.lowerBound].text,
                  before: limit,
                  unit: unit
              ) else { return false }
        return [.float2, .float3, .float4, .int2, .int3, .int4,
                .uint2, .uint3, .uint4].contains(type)
    }

    private static func declaredType(
        _ name: String,
        before limit: Int,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        var types = Set(unit.declarations.compactMap {
            $0.name == name
                ? SceneAuthoredShaderValueType(authoredName: $0.typeName) : nil
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
        return types.count == 1 ? types.first : nil
    }

    private static func splitProduct(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            guard depth == 0, tokens[index].text == "*" else { continue }
            guard start < index else { return nil }
            result.append(start..<index)
            start = index + 1
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    private static func argumentRanges(
        opening: Int,
        closing: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        var ranges: [Range<Int>] = []
        var start = opening + 1
        var depth = 0
        for index in (opening + 1)...closing {
            let isEnd = index == closing
            if !isEnd, ["(", "["].contains(tokens[index].text) { depth += 1 }
            if !isEnd, [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            guard isEnd || (depth == 0 && tokens[index].text == ",") else {
                continue
            }
            guard start < index else { return nil }
            ranges.append(start..<index)
            start = index + 1
        }
        return ranges
    }
}

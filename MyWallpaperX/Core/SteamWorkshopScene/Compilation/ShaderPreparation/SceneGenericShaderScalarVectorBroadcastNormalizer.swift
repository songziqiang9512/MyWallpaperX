import Foundation

/// Vulkan GLSL does not implicitly broadcast a scalar expression assigned to
/// a floating vector. Make only source-proven scalar arithmetic initializers
/// and assignments explicit; calls, unknown identifiers, and vector-valued
/// expressions remain under the compiler's fail-closed boundary.
nonisolated enum SceneGenericShaderScalarVectorBroadcastNormalizer {
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
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit else {
            return normalized
        }

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
            guard unit.tokens[index].text == "=", index > 0,
                  unit.tokens[index - 1].kind == .identifier,
                  let target = declaredType(
                      unit.tokens[index - 1].text,
                      before: index,
                      unit: unit
                  ), let constructor = vectorConstructor(target),
                  let end = statementEnd(after: index, tokens: unit.tokens),
                  index + 1 < end,
                  isScalarArithmetic(
                      (index + 1)..<end,
                      before: index,
                      unit: unit
                  ), let startOffset = offset(index + 1, after: false),
                  let endOffset = offset(end - 1, after: true) else { continue }
            insertions.append((startOffset, "\(constructor)("))
            insertions.append((endOffset, ")"))
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

    private static func isScalarArithmetic(
        _ range: Range<Int>,
        before limit: Int,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        var depth = 0
        var expectsOperand = true
        var sawOperand = false
        var index = range.lowerBound
        while index < range.upperBound {
            let token = unit.tokens[index]
            if token.text == "(" {
                guard expectsOperand else { return false }
                depth += 1
                index += 1
                continue
            }
            if token.text == ")" {
                guard !expectsOperand, depth > 0 else { return false }
                depth -= 1
                index += 1
                continue
            }
            if ["+", "-"].contains(token.text), expectsOperand {
                index += 1
                continue
            }
            if ["+", "-", "*", "/", "%"].contains(token.text) {
                guard !expectsOperand else { return false }
                expectsOperand = true
                index += 1
                continue
            }
            guard expectsOperand else { return false }
            if token.kind == .number {
                expectsOperand = false
                sawOperand = true
                index += 1
                continue
            }
            guard token.kind == .identifier,
                  index + 1 >= range.upperBound
                    || unit.tokens[index + 1].text != "(",
                  let type = declaredType(
                      token.text,
                      before: limit,
                      unit: unit
                  ) else { return false }
            if scalarType(type) {
                index += 1
            } else {
                guard index + 2 < range.upperBound,
                      unit.tokens[index + 1].text == ".",
                      unit.tokens[index + 2].kind == .identifier,
                      unit.tokens[index + 2].text.count == 1,
                      unit.tokens[index + 2].text.allSatisfy({
                          "xyzwrgba".contains($0)
                      }),
                      vectorType(type) else { return false }
                index += 3
            }
            expectsOperand = false
            sawOperand = true
        }
        return sawOperand && !expectsOperand && depth == 0
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

    private static func statementEnd(
        after assignment: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        var depth = 0
        for index in (assignment + 1)..<tokens.count {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if depth == 0, tokens[index].text == ";" { return index }
        }
        return nil
    }

    private static func vectorConstructor(
        _ type: SceneAuthoredShaderValueType
    ) -> String? {
        switch type {
        case .float2: "vec2"
        case .float3: "vec3"
        case .float4: "vec4"
        default: nil
        }
    }

    private static func scalarType(_ type: SceneAuthoredShaderValueType) -> Bool {
        [.float, .int, .uint].contains(type)
    }

    private static func vectorType(_ type: SceneAuthoredShaderValueType) -> Bool {
        [.float2, .float3, .float4, .int2, .int3, .int4,
         .uint2, .uint3, .uint4].contains(type)
    }
}

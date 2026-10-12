import Foundation

/// Makes proven scalar floating remainder explicit before either backend.
/// The existing expression proof owns types and purity; this pass only finds
/// operator spans and emits a helper whose arguments are each evaluated once.
nonisolated enum SceneGenericShaderFloatingModuloNormalizer {
    private struct Operation {
        let left: Range<Int>
        let right: Range<Int>
        var range: Range<Int> { left.lowerBound..<right.upperBound }
    }

    static func rewrite(
        _ source: String,
        stage: SceneShaderContract.StageKind = .fragment
    ) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#version") ? "" : $0
        }.joined(separator: "\n")
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: analysisSource, stage: stage),
            stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit,
              !unit.functions.contains(where: { $0.name == "fmod" }),
              !SceneAuthoredShaderSyntaxAnalyzer.valueDeclarationNames(in: unit.tokens).contains("fmod"),
              unit.defines["fmod"] == nil else { return normalized }
        let tokens = unit.tokens
        let sourceLines = normalized.components(separatedBy: "\n")
        func matchesSourceToken(_ index: Int) -> Bool {
            let token = tokens[index]
            return String(sourceLines[token.line - 1].unicodeScalars
                .dropFirst(token.column - 1).prefix(token.text.unicodeScalars.count)) == token.text
        }
        let scalarTypes: Set<SceneAuthoredShaderValueType> = [.float, .int, .uint]
        let operations = tokens.indices.compactMap { index -> Operation? in
            guard tokens[index].text == "%",
                  let caller = unit.functions.first(where: { $0.bodyRange.contains(index) }),
                  let operands = operands(at: index, tokens: tokens),
                  caller.bodyRange.contains(operands.left.lowerBound),
                  caller.bodyRange.contains(operands.right.upperBound - 1),
                  // Numeric defines can replace token text with a different
                  // source width. Never cut a source span using that width.
                  matchesSourceToken(operands.left.lowerBound),
                  matchesSourceToken(operands.right.upperBound - 1) else { return nil }
            let values = SceneAuthoredShaderFunctionSemantics
                .uniqueRootScopeValueDeclarations(for: caller, in: unit)
                .filter { $0.value.index < index }
                .compactMapValues { SceneAuthoredShaderValueType(authoredName: $0.type) }
            let expressions = [operands.left, operands.right].compactMap {
                SceneAuthoredShaderBuiltInVectorConversion.componentExpression(
                    $0, tokens: tokens, unit: unit, valueTypes: values
                )
            }
            guard expressions.count == 2,
                  expressions.allSatisfy({ scalarTypes.contains($0.type) && $0.conversions.isEmpty }),
                  expressions.contains(where: { $0.type == .float }) else { return nil }
            return operands
        }
        guard !operations.isEmpty else { return normalized }

        var names = Set(tokens.filter { $0.kind == .identifier }.map(\.text))
            .union(unit.defines.keys)
        func fresh(_ base: String) -> String {
            var name = base
            while names.contains(name) { name += "_" }
            names.insert(name)
            return name
        }
        let helper = fresh("mwxScalarRemainder")
        let dividend = fresh("mwxRemainderDividend")
        let divisor = fresh("mwxRemainderDivisor")
        var lineStarts = [0]
        var position = 0
        for scalar in normalized.unicodeScalars {
            position += 1
            if scalar == "\n" { lineStarts.append(position) }
        }
        func bounds(_ range: Range<Int>) -> Range<String.Index> {
            let first = tokens[range.lowerBound], last = tokens[range.upperBound - 1]
            let scalars = normalized.unicodeScalars
            let lower = scalars.index(scalars.startIndex,
                offsetBy: lineStarts[first.line - 1] + first.column - 1)
            let upper = scalars.index(scalars.startIndex,
                offsetBy: lineStarts[last.line - 1] + last.column - 1 + last.text.unicodeScalars.count)
            return String.Index(lower, within: normalized)!..<String.Index(upper, within: normalized)!
        }
        var replacements: [(range: Range<Int>, text: String)] = []
        func render(_ range: Range<Int>) -> String {
            let originalBounds = bounds(range)
            var text = String(normalized[originalBounds])
            let contained = replacements.filter { range.contains($0.range.lowerBound)
                && $0.range.upperBound <= range.upperBound }
            let roots = contained.filter { candidate in
                !contained.contains { other in other.range != candidate.range
                    && other.range.lowerBound <= candidate.range.lowerBound
                    && candidate.range.upperBound <= other.range.upperBound }
            }
            for replacement in roots.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
                let sourceBounds = bounds(replacement.range)
                let lower = normalized.distance(from: originalBounds.lowerBound, to: sourceBounds.lowerBound)
                let upper = normalized.distance(from: originalBounds.lowerBound, to: sourceBounds.upperBound)
                text.replaceSubrange(text.index(text.startIndex, offsetBy: lower)..<text.index(text.startIndex, offsetBy: upper),
                    with: replacement.text)
            }
            return text
        }
        for operation in operations.sorted(by: { $0.range.count < $1.range.count }) {
            replacements.append((operation.range,
                "\(helper)(float(\(render(operation.left))), float(\(render(operation.right))))"))
        }
        var result = render(0..<tokens.count)
        // Keep leading directives/comments and trailing whitespace outside the
        // token span. The helper precedes every authored function.
        let sourceBounds = bounds(0..<tokens.count)
        result = String(normalized[..<sourceBounds.lowerBound]) + result
            + String(normalized[sourceBounds.upperBound...])
        guard let firstFunction = unit.functions.first else { return normalized }
        let functionStart = bounds(firstFunction.headerRange).lowerBound
        let offset = normalized.distance(from: normalized.startIndex, to: functionStart)
        // Delegate arithmetic to the existing backend builtin lowering rather
        // than duplicating its formula or precision policy. The wrapper keeps
        // authored operands single-evaluation even for a macro backend.
        result.insert(contentsOf:
            "float \(helper)(float \(dividend), float \(divisor)) { return fmod(\(dividend), \(divisor)); }\n",
            at: result.index(result.startIndex, offsetBy: offset))
        return result
    }

    /// `%` shares multiplication precedence and associates left to right.
    /// Stop the left span at lower-precedence operators; the right span is one
    /// primary (with unary signs), not the following multiplication chain.
    private static func operands(
        at operation: Int, tokens: [SceneAuthoredShaderToken]
    ) -> Operation? {
        guard operation > 0, operation + 1 < tokens.count else { return nil }
        let boundaries: Set<String> = [";", "{", "}", "=", "+=", "-=", "*=", "/=", "%=",
            ",", "?", ":", "&&", "||", "==", "!=", "<", ">", "<=", ">=", "&", "|", "^", "return"]
        var lower = operation, depth = 0
        while lower > 0 {
            let index = lower - 1, text = tokens[index].text
            if [")", "]"].contains(text) { depth += 1 }
            if ["(", "["].contains(text) {
                if depth == 0 { break }
                depth -= 1
            }
            if depth == 0 {
                if boundaries.contains(text) { break }
                if ["+", "-"].contains(text), index > 0,
                   !boundaries.union(["(", "*", "/", "%", "+", "-"]).contains(tokens[index - 1].text) { break }
            }
            lower = index
        }
        var start = operation + 1
        while start < tokens.count, ["+", "-"].contains(tokens[start].text) { start += 1 }
        guard start < tokens.count else { return nil }
        var upper = start + 1
        if tokens[start].text == "(" {
            guard let close = SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens, opening: start) else { return nil }
            upper = close + 1
        } else if tokens[start].kind == .identifier, upper < tokens.count, tokens[upper].text == "(" {
            guard let close = SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens, opening: upper) else { return nil }
            upper = close + 1
        }
        while upper + 1 < tokens.count, tokens[upper].text == ".", tokens[upper + 1].kind == .identifier { upper += 2 }
        guard lower < operation,
              upper == tokens.count || !["++", "--", "[", "("].contains(tokens[upper].text) else { return nil }
        return Operation(left: lower..<operation, right: (operation + 1)..<upper)
    }
}

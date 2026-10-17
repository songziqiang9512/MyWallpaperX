import Foundation

/// Proves only that the fragment stage definitely initializes the stored red
/// component through one dominating whole-output write. Bounded direct
/// component mutations and their read-only RG values may follow because they
/// cannot make the initialized channel undefined. Attachment storage decides whether this fact has scalar
/// meaning; it never grants a color contract.
nonisolated enum SceneAuthoredShaderFragmentOutputAnalyzer {
    static func analyze(
        source: String
    ) -> SceneAuthoredShaderProgram.FragmentOutputChannelUse {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard let unit = syntax.unit, syntax.diagnostics.isEmpty else {
            return .unproven
        }
        return analyze(unit)
    }

    static func analyze(
        _ fragment: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderProgram.FragmentOutputChannelUse {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }) else {
            return .unproven
        }
        let tokens = fragment.tokens
        guard !tokens.contains(where: { $0.text == "discard" }) else {
            return .unproven
        }
        let outputUses = tokens.indices.filter {
            tokens[$0].text == "gl_FragColor"
        }
        let wholeAssignments = outputUses.filter {
            $0 + 1 < tokens.count && tokens[$0 + 1].text == "="
        }
        guard wholeAssignments.count == 1,
              let assignment = wholeAssignments.first,
              main.bodyRange.contains(assignment),
              assignment + 1 < tokens.count,
              tokens[assignment + 1].text == "=",
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  assignment,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let initializer = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                  after: assignment,
                  in: tokens,
                  body: main.bodyRange
              ) else {
            return .unproven
        }
        let mutations = Dictionary(uniqueKeysWithValues: outputUses.compactMap { use in
            componentMutationExpression(
                at: use, after: initializer.endIndex,
                in: tokens, body: main.bodyRange
            ).map { (use, $0) }
        })
        var provenReadExpressions: Set<Range<Int>> = []
        for use in outputUses where use != assignment && mutations[use] == nil {
            guard use > initializer.endIndex, use + 2 < main.bodyRange.upperBound,
                  tokens[use + 1].text == ".",
                  isRedGreenSwizzle(tokens[use + 2].text, requiresUnique: false),
                  SceneAuthoredShaderTokenScanner.isReadOnlyValueUse(
                      start: use, end: use + 3, tokens: tokens, body: main.bodyRange
                  ) else { return .unproven }
            let containing = mutations.values.filter { $0.contains(use) }
            guard containing.count == 1, let expression = containing.first else {
                return .unproven
            }
            if provenReadExpressions.insert(expression).inserted {
                guard !tokens[expression].contains(where: {
                    ["=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
                     "<<=", ">>=", "++", "--"].contains($0.text)
                }), SceneAuthoredShaderColorTransferAnalyzer.helperCallsArePureAndUnsampled(
                    fragment: fragment, expressionRanges: [expression],
                    permitsUnexpandedBlendingHelper: false,
                    permitsAuthoredHelpers: false
                ) else { return .unproven }
            }
        }
        return .redDefined
    }

    private static func componentMutationExpression(
        at outputUse: Int,
        after initialization: Int,
        in tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Range<Int>? {
        guard outputUse > initialization,
              body.contains(outputUse),
              outputUse + 3 < body.upperBound,
              tokens[outputUse + 1].text == ".",
              isRedGreenSwizzle(tokens[outputUse + 2].text),
              ["=", "+=", "-=", "*=", "/="].contains(
                  tokens[outputUse + 3].text
              ), let expression = SceneAuthoredShaderColorTransferAnalyzer.memberAssignmentExpression(
                  after: outputUse + 3, tokens: tokens, body: body, boundary: body.upperBound
              ) else { return nil }
        return expression.startIndex..<expression.endIndex
    }

    private static func isRedGreenSwizzle(_ value: String, requiresUnique: Bool = true) -> Bool {
        guard (1 ... 2).contains(value.count) else { return false }
        let coordinate = Set("xy")
        let color = Set("rg")
        let characters = Set(value)
        return (!requiresUnique || characters.count == value.count)
            && (characters.isSubset(of: coordinate)
                || characters.isSubset(of: color))
    }
}

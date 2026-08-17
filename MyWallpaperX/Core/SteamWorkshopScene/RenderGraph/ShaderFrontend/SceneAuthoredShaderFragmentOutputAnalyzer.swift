import Foundation

/// Proves only that the fragment stage definitely defines the stored red
/// component through one whole-output write. Attachment storage decides
/// whether this fact has scalar meaning; it never grants a color contract.
nonisolated enum SceneAuthoredShaderFragmentOutputAnalyzer {
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
        guard outputUses.count == 1,
              let assignment = outputUses.first,
              main.bodyRange.contains(assignment),
              assignment + 1 < tokens.count,
              tokens[assignment + 1].text == "=",
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  assignment,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                  after: assignment,
                  in: tokens,
                  body: main.bodyRange
              ) != nil else {
            return .unproven
        }
        return .redDefined
    }
}

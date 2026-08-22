import Foundation

/// Proves only that the fragment stage definitely initializes the stored red
/// component through one dominating whole-output write. Bounded direct
/// component mutations may follow because they cannot make the initialized
/// channel undefined. Attachment storage decides whether this fact has scalar
/// meaning; it never grants a color contract.
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
              SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                  after: assignment,
                  in: tokens,
                  body: main.bodyRange
              ) != nil,
              outputUses.allSatisfy({ use in
                  use == assignment
                      || directComponentMutation(
                          at: use,
                          after: assignment,
                          in: tokens,
                          body: main.bodyRange
                      )
              }) else {
            return .unproven
        }
        return .redDefined
    }

    private static func directComponentMutation(
        at outputUse: Int,
        after initialization: Int,
        in tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        guard outputUse > initialization,
              body.contains(outputUse),
              outputUse + 3 < body.upperBound,
              tokens[outputUse + 1].text == ".",
              isRedGreenSwizzle(tokens[outputUse + 2].text),
              ["=", "+=", "-=", "*=", "/="].contains(
                  tokens[outputUse + 3].text
              ),
              hasBalancedExpression(
                  after: outputUse + 3,
                  in: tokens,
                  body: body
              ) else {
            return false
        }
        return true
    }

    private static func hasBalancedExpression(
        after operation: Int,
        in tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        let start = operation + 1
        guard body.contains(start) else { return false }
        var stack: [String] = []
        let closing: [String: String] = [")": "(", "]": "["]
        for index in start..<body.upperBound {
            let text = tokens[index].text
            if ["(", "["].contains(text) {
                stack.append(text)
            } else if let expected = closing[text] {
                guard stack.last == expected else { return false }
                stack.removeLast()
            } else if text == ";", stack.isEmpty {
                return index > start
            } else if ["{", "}"].contains(text), stack.isEmpty {
                return false
            }
        }
        return false
    }

    private static func isRedGreenSwizzle(_ value: String) -> Bool {
        guard (1 ... 2).contains(value.count) else { return false }
        let coordinate = Set("xy")
        let color = Set("rg")
        let characters = Set(value)
        return characters.count == value.count
            && (characters.isSubset(of: coordinate)
                || characters.isSubset(of: color))
    }
}

import Foundation

/// Proves root-level scalar interpolation whose two color operands retain one
/// texture representation. It does not inspect shader paths or identities.
nonisolated enum SceneAuthoredShaderSameSlotMixAnalyzer {
    /// Returns the sampled slot only when a prepared fragment contains one
    /// unconditional whole-color replacement between two root locals sampled
    /// from that same slot. The result is source-derived and independent of
    /// shader path, effect identity, or local spelling.
    static func aliasReplacementSourceSlot(
        fragmentSource source: String
    ) -> Int? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty,
              let fragment = syntax.unit,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let outputUses = fragment.tokens.indices.filter {
            fragment.tokens[$0].text == "gl_FragColor"
        }
        return analyzeAliasReplacement(
            outputUses: outputUses,
            fragment: fragment,
            main: main
        )
    }

    static func analyze(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        let assignments = outputUses.filter {
            $0 + 1 < tokens.count && tokens[$0 + 1].text == "="
        }
        guard assignments.count == 2,
              outputUses.count == 3,
              assignments.allSatisfy({
                  main.bodyRange.contains($0)
                      && SceneAuthoredShaderColorTransferAnalyzer
                          .isUnconditionalWrite(
                              $0,
                              tokens: tokens,
                              body: main.bodyRange
                          )
              }),
              let initial = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: assignments[0],
                      in: tokens,
                      body: main.bodyRange
                  ),
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                  .directTextureSampleSlot(initial),
              let update = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: assignments[1],
                      in: tokens,
                      body: main.bodyRange
                  ),
              let arguments = callArguments(named: "mix", expression: update),
              arguments.count == 3,
              isScalar(
                  arguments[2],
                  before: assignments[1],
                  fragment: fragment,
                  body: main.bodyRange
              ) else {
            return nil
        }

        let firstIsSample = SceneAuthoredShaderColorTransferAnalyzer
            .directTextureSampleSlot(arguments[0]) == slot
        let secondIsSample = SceneAuthoredShaderColorTransferAnalyzer
            .directTextureSampleSlot(arguments[1]) == slot
        let firstIsOutput = isFragmentOutput(arguments[0])
        let secondIsOutput = isFragmentOutput(arguments[1])
        guard (firstIsSample && secondIsOutput)
                || (firstIsOutput && secondIsSample),
              outputUses.last == (firstIsOutput
                  ? arguments[0].startIndex
                  : arguments[1].startIndex) else {
            return nil
        }
        return slot
    }

    /// Proves a root-local replacement whose original and replacement colors
    /// are both direct samples of the same texture slot. Auxiliary samples may
    /// drive coordinates or scalar masks, but neither color local may be
    /// conditionally assigned, member-written, or otherwise reused.
    static func analyzeAliasReplacement(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: output,
                      in: tokens,
                      body: main.bodyRange
                  ),
              outputExpression.count == 1,
              outputExpression.first?.kind == .identifier,
              let outputName = outputExpression.first?.text,
              let outputDefinition = uniqueVectorDefinition(
                  named: outputName,
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  outputDefinition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let outputInitializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: outputDefinition,
                      in: tokens,
                      body: main.bodyRange
                  ),
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                  .directTextureSampleSlot(outputInitializer) else {
            return nil
        }

        let replacements = main.bodyRange.filter { index in
            index > outputDefinition && index < output
                && tokens[index].text == outputName
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        guard replacements.count == 1,
              let replacement = replacements.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  replacement,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let replacementExpression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: replacement,
                      in: tokens,
                      body: main.bodyRange
                  ),
              replacementExpression.count == 1,
              replacementExpression.first?.kind == .identifier,
              let aliasName = replacementExpression.first?.text,
              aliasName != outputName,
              let aliasDefinition = uniqueVectorDefinition(
                  named: aliasName,
                  before: replacement,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              aliasDefinition > outputDefinition,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  aliasDefinition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let aliasInitializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: aliasDefinition,
                      in: tokens,
                      body: main.bodyRange
                  ),
              SceneAuthoredShaderColorTransferAnalyzer
                  .directTextureSampleSlot(aliasInitializer) == slot else {
            return nil
        }

        let outputNameUses = Set(main.bodyRange.filter {
            tokens[$0].text == outputName
        })
        let aliasNameUses = Set(main.bodyRange.filter {
            tokens[$0].text == aliasName
        })
        guard outputNameUses == Set([
            outputDefinition,
            replacement,
            outputExpression.startIndex,
        ]), aliasNameUses == Set([
            aliasDefinition,
            replacementExpression.startIndex,
        ]) else {
            return nil
        }
        return slot
    }

    private static func uniqueVectorDefinition(
        named name: String,
        before boundary: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Int? {
        let definitions = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        return definitions.count == 1 ? definitions[0] : nil
    }

    private static func callArguments(
        named name: String,
        expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> [ArraySlice<SceneAuthoredShaderToken>]? {
        let tokens = Array(expression)
        guard tokens.count >= 6,
              tokens[0].text == name,
              tokens[1].text == "(",
              tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens) else {
            return nil
        }
        var depth = 0
        var starts = [2]
        var ranges: [Range<Int>] = []
        for index in 2..<(tokens.count - 1) {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard let start = starts.last, start < index else { return nil }
                ranges.append(start..<index)
                starts.append(index + 1)
            default: break
            }
        }
        guard depth == 0,
              let start = starts.last,
              start < tokens.count - 1 else {
            return nil
        }
        ranges.append(start..<(tokens.count - 1))
        let base = expression.startIndex
        return ranges.map {
            expression[(base + $0.lowerBound)..<(base + $0.upperBound)]
        }
    }

    private static func isFragmentOutput(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        expression.count == 1 && expression.first?.text == "gl_FragColor"
    }

    private static func isScalar(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        before assignment: Int,
        fragment: SceneAuthoredShaderSyntaxUnit,
        body: Range<Int>
    ) -> Bool {
        guard expression.count == 1, let token = expression.first else { return false }
        if token.kind == .number { return true }
        guard token.kind == .identifier else { return false }
        if fragment.declarations.contains(where: {
            $0.name == token.text && $0.typeName == "float" && $0.arraySize == nil
        }) {
            return true
        }
        let tokens = fragment.tokens
        let definitions = body.filter { index in
            index > body.lowerBound && index < assignment
                && tokens[index].text == token.text
                && tokens[index - 1].text == "float"
                && index + 1 < tokens.count
                && ["=", ";"].contains(tokens[index + 1].text)
        }
        return definitions.count == 1
            && definitions.allSatisfy {
                SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                    $0,
                    tokens: tokens,
                    body: body
                )
            }
    }

    private static func outerCallClosesAtEnd(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        var depth = 0
        for index in 1..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index == tokens.count - 1 }
                if depth < 0 { return false }
            }
        }
        return false
    }
}

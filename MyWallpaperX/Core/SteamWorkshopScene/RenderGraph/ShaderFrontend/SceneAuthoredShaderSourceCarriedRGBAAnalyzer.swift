import Foundation

/// Proves the remaining source-backed straight RGBA shapes after the exact
/// analyzers decline them. The proof separates one color source from auxiliary
/// scalar/data samplers and never selects by effect or shader identity.
nonisolated extension SceneAuthoredShaderGeneratedStraightRGBAAnalyzer {
    enum SourceCarriedTransfer: Equatable {
        case preserving
        case straight
    }

    struct SourceCarriedFact: Equatable {
        let sourceSlot: Int
        let transfer: SourceCarriedTransfer

        var colorTransfer: SceneShaderColorTransfer {
            switch transfer {
            case .preserving:
                .straightAlphaPreserving(textureSlot: sourceSlot)
            case .straight:
                .straightAlpha(textureSlot: sourceSlot)
            }
        }
    }

    static func analyzeSourceCarried(
        fragmentSource source: String
    ) -> SourceCarriedFact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source, stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyzeSourceCarried(fragment)
    }

    static func analyzeSourceCarried(_ fragment: Unit) -> SourceCarriedFact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let tokens = fragment.tokens
        let outputs = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard outputs.count == 1, let output = outputs.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                output, tokens: tokens, body: main.bodyRange
              ), let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: output, in: tokens, body: main.bodyRange),
              let sampled = sampledColorLocals(
                before: output, tokens: tokens, body: main.bodyRange
              ) else { return nil }

        if let carrier = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .identifier(expression), let slot = sampled[carrier],
           carrierPreservesAlpha(
            carrier, before: output, tokens: tokens, body: main.bodyRange
           ), auxiliaryColorsRemainScalarData(
            excluding: slot, sampled: sampled,
            before: output, tokens: tokens, body: main.bodyRange
           ) {
            return .init(sourceSlot: slot, transfer: .preserving)
        }

        guard let outputCall = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .call(expression),
              ["CAST4", "vec4", "float4"].contains(outputCall.name),
              outputCall.arguments.count == 2 else { return nil }
        return conditionalGeneratedRGBA(
            outputCall.arguments, sampled: sampled, output: output,
            fragment: fragment, main: main
        ) ?? uniformSeededBlendRGBA(
            outputCall.arguments, sampled: sampled, output: output,
            fragment: fragment, main: main
        )
    }

    private static func sampledColorLocals(
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> [String: Int]? {
        var resolved: [String: Int] = [:]
        for index in body where index > body.lowerBound && index < boundary {
            guard index + 1 < boundary,
                  ["vec4", "float4"].contains(tokens[index - 1].text),
                  tokens[index].kind == .identifier,
                  tokens[index + 1].text == "=",
                  let initializer = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(after: index, in: tokens, body: body)
            else { continue }
            if let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(initializer) {
                resolved[tokens[index].text] = slot
            } else if let alias = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(initializer), let slot = resolved[alias] {
                resolved[tokens[index].text] = slot
            }
        }
        return resolved.isEmpty ? nil : resolved
    }

    private static func carrierPreservesAlpha(
        _ carrier: String,
        before output: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let definitions = body.filter { index in
            index > body.lowerBound && index + 1 < output
                && tokens[index].text == carrier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1, let definition = definitions.first else {
            return false
        }
        for index in (definition + 1)..<output where tokens[index].text == carrier {
            if index + 1 < output,
               ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 1].text) {
                return false
            }
            if index + 3 < output, tokens[index + 1].text == ".",
               ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 3].text),
               !["rgb", "xyz"].contains(tokens[index + 2].text) {
                return false
            }
        }
        return true
    }

    private static func auxiliaryColorsRemainScalarData(
        excluding sourceSlot: Int,
        sampled: [String: Int],
        before output: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        for (name, slot) in sampled where slot != sourceSlot {
            let uses = body.filter { $0 < output && tokens[$0].text == name }
            guard uses.dropFirst().allSatisfy({ index in
                index + 2 < output && tokens[index + 1].text == "."
                    && ["r", "g", "b", "a", "x", "y", "z", "w"]
                        .contains(tokens[index + 2].text)
            }) else { return false }
        }
        return true
    }

}

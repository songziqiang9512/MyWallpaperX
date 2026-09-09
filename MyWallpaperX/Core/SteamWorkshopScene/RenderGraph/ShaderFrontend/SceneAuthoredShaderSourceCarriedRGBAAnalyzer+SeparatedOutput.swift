import Foundation

nonisolated extension SceneAuthoredShaderGeneratedStraightRGBAAnalyzer {
    /// Proves the progress-bar style source-carried RGBA form.  A sampled
    /// framebuffer color is kept as the only color source while a separate
    /// vec4 carrier is seeded from uniforms, optionally updated by one
    /// constant-true bounded branch, and then receives the canonical RGB and
    /// alpha helper calls.  The proof is deliberately structural: aliases,
    /// extra samples, escaping alpha, dynamic control flow, and helper bodies
    /// whose data flow is not exact all remain unresolved.
    static func generatedSourceCarried(
        sampled: [String: Int],
        output: Int,
        expression: ArraySlice<Token>,
        fragment: Unit,
        main: Unit.Function
    ) -> SourceCarriedFact? {
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let tokens = fragment.tokens
        guard sampled.count == 1,
              let sourceEntry = sampled.first,
              let carrier = Calls.identifier(expression),
              carrier != sourceEntry.key,
              totalTextureSampleCount(in: fragment) == 1,
              let sourceDefinition = uniqueRGBADefinition(
                  sourceEntry.key,
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let carrierDefinition = uniqueRGBADefinition(
                  carrier,
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              sourceDefinition != carrierDefinition,
              rootLevel(sourceDefinition, tokens: tokens, body: main.bodyRange),
              rootLevel(carrierDefinition, tokens: tokens, body: main.bodyRange),
              let seed = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: carrierDefinition,
                      in: tokens,
                      body: main.bodyRange
                  ),
              generatedRGBASeed(
                  seed,
                  fragment: fragment,
                  source: sourceEntry.key,
                  carrier: carrier
              ),
              let rgb = uniqueMemberAssignment(
                  carrier,
                  component: "rgb",
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let alpha = uniqueMemberAssignment(
                  carrier,
                  component: "a",
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              carrierDefinition < rgb.index,
              rgb.index < alpha.index,
              alpha.index < output,
              let rgbCall = Calls.call(rgb.rhs),
              rgbCall.name == "ApplyBlending",
              rgbCall.arguments.count == 4,
              Calls.number(rgbCall.arguments[0]) == 0,
              Calls.member(
                  rgbCall.arguments[1],
                  name: sourceEntry.key,
                  component: "rgb"
              ),
              Calls.member(
                  rgbCall.arguments[2],
                  name: carrier,
                  component: "rgb"
              ),
              let weight = carrierWeightedScalar(
                  rgbCall.arguments[3],
                  carrier: carrier,
                  fragment: fragment,
                  source: sourceEntry.key,
                  main: main
              ),
              validatedRGBBlendHelper(fragment, mode: 0),
              let alphaCall = Calls.call(alpha.rhs),
              alphaCall.name == "BlendTransparency",
              alphaCall.arguments.count == 3,
              Calls.member(
                  alphaCall.arguments[0],
                  name: sourceEntry.key,
                  component: "a"
              ),
              Calls.member(
                  alphaCall.arguments[1],
                  name: carrier,
                  component: "a"
              ),
              let alphaWeight = scalarValue(
                  alphaCall.arguments[2],
                  fragment: fragment,
                  source: sourceEntry.key,
                  carrier: carrier,
                  main: main
              ),
              alphaWeight == weight,
              let transfer = validatedTransparencyHelper(fragment),
              let controlUses = generatedCarrierControlFlowUses(
                  carrier: carrier,
                  source: sourceEntry.key,
                  carrierDefinition: carrierDefinition,
                  rgbIndex: rgb.index,
                  alphaIndex: alpha.index,
                  output: output,
                  fragment: fragment,
                  main: main
              ),
              exactGeneratedCarrierUses(
                  carrier: carrier,
                  source: sourceEntry.key,
                  sourceDefinition: sourceDefinition,
                  carrierDefinition: carrierDefinition,
                  rgb: rgb,
                  alpha: alpha,
                  output: output,
                  fragment: fragment,
                  main: main,
                  controlUses: controlUses
              ) else {
            return nil
        }
        return .init(
            sourceSlot: sourceEntry.value,
            transfer: transfer,
            shape: .generatedCarrier
        )
    }

    /// Generated text-like color with a source-alpha seed and conditional,
    /// source-independent alpha replacements.
    static func conditionalGeneratedRGBA(
        _ arguments: [ArraySlice<Token>],
        sampled: [String: Int],
        output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> SourceCarriedFact? {
        guard sampled.count == 1, let source = sampled.first,
              let rgb = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(arguments[0]),
              let alpha = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(arguments[1]),
              generatedRGB(
                rgb, before: output, fragment: fragment, main: main
              ), alphaSeedAndReplacements(
                alpha, source: source.key,
                before: output, fragment: fragment, main: main
              ), noWholeSampleFlowsIntoRGB(
                sourceDeclaration: source.key,
                before: output, tokens: fragment.tokens, body: main.bodyRange
              ) else { return nil }
        return .init(sourceSlot: source.value, transfer: .straight)
    }

    /// Audio-bar-like generated RGB: one uniform seed is blended with one
    /// sampled scene color and terminal alpha follows a bounded whitelist.
    static func uniformSeededBlendRGBA(
        _ arguments: [ArraySlice<Token>],
        sampled: [String: Int],
        output: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> SourceCarriedFact? {
        guard sampled.count == 1, let source = sampled.first,
              let rgb = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(arguments[0]),
              let alpha = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(arguments[1]),
              uniformSeededRGBBlend(
                rgb, source: source.key,
                before: output, fragment: fragment, main: main
              ), boundedTerminalAlpha(
                alpha, source: source.key, rgb: rgb,
                before: output, fragment: fragment, main: main
              ), noWholeSampleFlowsIntoRGB(
                sourceDeclaration: source.key,
                before: output, tokens: fragment.tokens, body: main.bodyRange
              ) else { return nil }
        return .init(sourceSlot: source.value, transfer: .straight)
    }
}

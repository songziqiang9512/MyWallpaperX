import Foundation

/// Proves one bounded associated-over of a graph-input color sample with a
/// distinct overlay color sample. The overlay contributes its own RGB and
/// alpha; a scalar weight and the unique helper body write both the composite
/// RGB and the Porter-Duff associated-over alpha. The existing `.straightAlpha`
/// boundary can therefore unpremultiply only the graph-input sample.
///
/// The fact is derived only from active source structure. It never inspects
/// effect, path, sample, layer, or hash identity, and it does not own the
/// ApplyBlending overlay-alpha form.
nonisolated enum SceneAuthoredShaderAssociatedOverBlendAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
        let overlaySlot: Int
        let blendFunction: String
        let blendWeight: String
        let blendWeightUniform: String
    }

    struct Call {
        let name: String
        let arguments: [ArraySlice<Token>]
    }

    static let colorVectorTypes: Set<String> = ["vec4", "float4"]
    static let rgbComponents: Set<String> = ["rgb", "xyz"]
    static let alphaComponents: Set<String> = ["a", "w"]
    static let mixNames: Set<String> = ["mix", "lerp"]
    static let sampleFunctions: Set<String> = [
        "texSample2D", "texture2D", "texSample2DLod", "texture2DLod",
    ]

    static func analyze(fragmentSource source: String) -> Fact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyze(fragment)
    }

    static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              fragment.functions.filter({ $0.name == "main" }).count == 1,
              let helper = uniqueAssociatedOverHelper(fragment)
        else { return nil }
        let allowedFunctions = Set(
            ["main", helper.name]
                + [uniqueConstantOneUVHelper(fragment)].compactMap { $0 }
        )
        guard fragment.functions.allSatisfy({
            allowedFunctions.contains($0.name)
        }), Set(fragment.functions.map(\.name)).count == fragment.functions.count
        else { return nil }
        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard outputUses.count == 1,
              let output = outputUses.first,
              rootAssignment(output, tokens: tokens, body: main.bodyRange),
              noControlFlow(main.bodyRange, tokens: tokens, allowReturn: false),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
              .assignmentExpression(
                  after: output, in: tokens, body: main.bodyRange
              ),
              let carrier = identifier(outputExpression),
              let carrierDefinition = uniqueDefinition(
                  carrier,
                  types: colorVectorTypes,
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let carrierInitializer = SceneAuthoredShaderColorTransferAnalyzer
              .assignmentExpression(
                  after: carrierDefinition, in: tokens, body: main.bodyRange
              ),
              let sourceSlot = SceneAuthoredShaderColorTransferAnalyzer
              .directTextureSampleSlot(carrierInitializer),
              let helperWrite = uniqueUntypedAssignment(
                  carrier,
                  after: carrierDefinition,
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let helperExpression = SceneAuthoredShaderColorTransferAnalyzer
              .assignmentExpression(
                  after: helperWrite, in: tokens, body: main.bodyRange
              ),
              let helperCall = call(helperExpression),
              helperCall.name == helper.name,
              helperCall.arguments.count == 3,
              identifier(helperCall.arguments[0]) == carrier,
              let overlay = identifier(helperCall.arguments[1]),
              overlay != carrier,
              let weight = identifier(helperCall.arguments[2]),
              weight != carrier,
              weight != overlay,
              let overlayDefinition = uniqueDefinition(
                  overlay,
                  types: colorVectorTypes,
                  before: helperWrite,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              overlayDefinition != carrierDefinition,
              let overlayInitializer = SceneAuthoredShaderColorTransferAnalyzer
              .assignmentExpression(
                  after: overlayDefinition, in: tokens, body: main.bodyRange
              ),
              let overlaySlot = SceneAuthoredShaderColorTransferAnalyzer
              .directTextureSampleSlot(overlayInitializer),
              overlaySlot != sourceSlot,
              (0 ... 7).contains(sourceSlot),
              (0 ... 7).contains(overlaySlot),
              sampleCallCount(in: fragment) == 2,
              helpersDoNotSample(fragment, excluding: main),
              let weightDefinition = uniqueDefinition(
                  weight,
                  types: ["float"],
                  before: helperWrite,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let blendWeightUniform = provenWeight(
                  weight,
                  overlayInitializer: overlayInitializer,
                  before: helperWrite,
                  fragment: fragment,
                  main: main
              ),
              exactUses(
                  carrier,
                  expected: [
                      helperWrite,
                      helperCall.arguments[0].startIndex,
                      outputExpression.startIndex,
                  ],
                  after: carrierDefinition,
                  before: outputExpression.endIndex,
                  tokens: tokens
              ),
              exactUses(
                  overlay,
                  expected: [helperCall.arguments[1].startIndex],
                  after: overlayDefinition,
                  before: helperExpression.endIndex,
                  tokens: tokens
              ),
              exactUses(
                  weight,
                  expected: [helperCall.arguments[2].startIndex],
                  after: weightDefinition,
                  before: helperExpression.endIndex,
                  tokens: tokens
              )
        else { return nil }
        return Fact(
            sourceSlot: sourceSlot,
            overlaySlot: overlaySlot,
            blendFunction: helper.name,
            blendWeight: weight,
            blendWeightUniform: blendWeightUniform
        )
    }

    private struct Helper {
        let name: String
    }

    private static func uniqueAssociatedOverHelper(_ fragment: Unit) -> Helper? {
        let matches = fragment.functions.compactMap { function -> Helper? in
            associatedOverHelper(function, fragment: fragment)
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func associatedOverHelper(
        _ function: Unit.Function,
        fragment: Unit
    ) -> Helper? {
        let tokens = fragment.tokens
        guard ["vec4", "float4"].contains(function.returnType),
              function.name != "main",
              noControlFlow(function.bodyRange, tokens: tokens, allowReturn: true),
              !function.bodyRange.contains(where: {
                  sampleFunctions.contains(tokens[$0].text)
              }),
              let parameters = splitTopLevel(
                  tokens[function.parameterRange], separator: ","
              ),
              parameters.count == 3,
              let source = colorParameter(parameters[0]),
              let overlay = colorParameter(parameters[1]),
              let weight = scalarParameter(parameters[2]),
              source != overlay,
              source != weight,
              overlay != weight,
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
              .topLevelStatements(in: function.bodyRange, tokens: tokens),
              statements.count == 8
        else { return nil }

        let alpha = tokens[statements[0]]
        let saved = tokens[statements[1]]
        let rgb = tokens[statements[2]]
        let src = tokens[statements[3]]
        let dst = tokens[statements[4]]
        let compensate = tokens[statements[5]]
        let alphaWrite = tokens[statements[6]]
        let returned = tokens[statements[7]]
        guard let alphaName = floatDeclaration(alpha),
              let savedName = colorDeclaration(saved, value: source),
              savedName != source,
              savedName != overlay,
              savedName != weight,
              savedName != alphaName,
              memberAssignment(
                  rgb,
                  name: source,
                  components: rgbComponents,
                  operation: "="
              ),
              associatedOverRGB(
                  assignmentExpression(rgb),
                  source: source,
                  overlay: overlay,
                  weight: weight
              ),
              let srcName = vectorDeclaration(src),
              srcName != source,
              srcName != overlay,
              srcName != savedName,
              srcName != alphaName,
              srcRGB(
                  assignmentExpression(src),
                  overlay: overlay,
                  saved: savedName,
                  weight: weight
              ),
              let dstName = vectorDeclaration(dst),
              dstName != source,
              dstName != overlay,
              dstName != savedName,
              dstName != srcName,
              dstName != alphaName,
              dstRGB(
                  assignmentExpression(dst),
                  overlay: overlay,
                  saved: savedName,
                  weight: weight
              ),
              memberAssignment(
                  compensate,
                  name: source,
                  components: rgbComponents,
                  operation: "+="
              ),
              rgbCompensation(
                  assignmentExpression(compensate),
                  sourceRGB: srcName,
                  destinationRGB: dstName,
                  weight: weight,
                  newAlpha: alphaName
              ),
              memberAssignment(
                  alphaWrite,
                  name: source,
                  components: alphaComponents,
                  operation: "="
              ),
              identifier(assignmentExpression(alphaWrite)) == alphaName,
              associatedOverAlpha(
                  assignmentExpression(alpha),
                  source: source,
                  overlay: overlay,
                  weight: weight
              ),
              returnIdentifier(returned) == source
        else { return nil }
        return Helper(name: function.name)
    }

    private static func provenWeight(
        _ name: String,
        overlayInitializer: ArraySlice<Token>,
        before boundary: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> String? {
        guard uniqueDefinition(
            name,
            types: ["float"],
            before: boundary,
            tokens: fragment.tokens,
            body: main.bodyRange
        ) != nil,
            let uv = overlaySampleCoordinate(overlayInitializer),
            let factors = scalarFactors(
                name,
                before: boundary,
                visiting: [],
                uvCoordinate: uv,
                fragment: fragment,
                main: main
            )
        else { return nil }
        let uniforms = factors.compactMap { factor -> String? in
            if case let .uniform(uniform) = factor { return uniform }
            return nil
        }
        let uvHelpers = factors.filter { $0 == .uvHelper }.count
        let ones = factors.filter { $0 == .one }.count
        guard uniforms.count == 1,
              Set(uniforms).count == 1,
              uvHelpers <= 1,
              ones + uvHelpers + 1 == factors.count,
              floatUniform(uniforms[0], fragment: fragment)
        else { return nil }
        guard uvHelpers == 0 || uniqueConstantOneUVHelper(fragment) != nil else {
            return nil
        }
        return uniforms[0]
    }

    private enum ScalarFactor: Equatable {
        case uniform(String)
        case one
        case uvHelper
    }

    private static func scalarFactors(
        _ name: String,
        before boundary: Int,
        visiting: Set<String>,
        uvCoordinate: String,
        fragment: Unit,
        main: Unit.Function
    ) -> [ScalarFactor]? {
        guard !visiting.contains(name) else { return nil }
        let tokens = fragment.tokens
        guard let definition = uniqueDefinition(
            name,
            types: ["float"],
            before: boundary,
            tokens: tokens,
            body: main.bodyRange
        ),
            let initializer = SceneAuthoredShaderColorTransferAnalyzer
            .assignmentExpression(
                after: definition, in: tokens, body: main.bodyRange
            )
        else { return nil }
        let next = visiting.union([name])
        guard var factors = expandProduct(
            initializer,
            selfName: name,
            selfFactors: nil,
            before: boundary,
            visiting: next,
            uvCoordinate: uvCoordinate,
            fragment: fragment,
            main: main
        ) else { return nil }
        if let assignment = uniqueUntypedAssignment(
            name,
            after: definition,
            before: boundary,
            tokens: tokens,
            body: main.bodyRange
        ),
            let expression = SceneAuthoredShaderColorTransferAnalyzer
            .assignmentExpression(
                after: assignment, in: tokens, body: main.bodyRange
            )
        {
            guard let replaced = expandProduct(
                expression,
                selfName: name,
                selfFactors: factors,
                before: boundary,
                visiting: next,
                uvCoordinate: uvCoordinate,
                fragment: fragment,
                main: main
            ) else { return nil }
            factors = replaced
        }
        return factors
    }

    private static func expandProduct(
        _ expression: ArraySlice<Token>,
        selfName: String,
        selfFactors: [ScalarFactor]?,
        before boundary: Int,
        visiting: Set<String>,
        uvCoordinate: String,
        fragment: Unit,
        main: Unit.Function
    ) -> [ScalarFactor]? {
        let factors = productFactors(stripOuterParens(expression))
        guard !factors.isEmpty else { return nil }
        var result: [ScalarFactor] = []
        for factor in factors {
            let value = stripOuterParens(factor)
            if isOne(value) {
                result.append(.one)
                continue
            }
            if let name = identifier(value) {
                if name == selfName {
                    guard let selfFactors else { return nil }
                    result.append(contentsOf: selfFactors)
                    continue
                }
                if floatUniform(name, fragment: fragment) {
                    result.append(.uniform(name))
                    continue
                }
                guard let nested = scalarFactors(
                    name,
                    before: boundary,
                    visiting: visiting,
                    uvCoordinate: uvCoordinate,
                    fragment: fragment,
                    main: main
                ) else { return nil }
                result.append(contentsOf: nested)
                continue
            }
            if let call = call(value),
               uniqueConstantOneUVHelper(fragment) == call.name,
               call.arguments.count == 1,
               identifier(call.arguments[0]) == uvCoordinate
            {
                result.append(.uvHelper)
                continue
            }
            return nil
        }
        return result
    }

    private static func uniqueConstantOneUVHelper(_ fragment: Unit) -> String? {
        let matches = fragment.functions.filter { function in
            constantOneUVHelper(function, fragment: fragment)
        }
        guard matches.count == 1 else { return nil }
        return matches[0].name
    }

    private static func constantOneUVHelper(
        _ function: Unit.Function,
        fragment: Unit
    ) -> Bool {
        let tokens = fragment.tokens
        guard function.returnType == "float",
              function.name != "main",
              let parameters = splitTopLevel(
                  tokens[function.parameterRange], separator: ","
              ),
              parameters.count == 1,
              vectorParameter(parameters[0], types: ["vec2", "float2"]),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
              .topLevelStatements(in: function.bodyRange, tokens: tokens),
              statements.count == 1,
              returnLiteralOne(tokens[statements[0]])
        else { return false }
        return true
    }

    private static func associatedOverAlpha(
        _ expression: ArraySlice<Token>,
        source: String,
        overlay: String,
        weight: String
    ) -> Bool {
        let summands = topLevelSummands(stripOuterParens(expression))
        guard summands.count == 2 else { return false }
        let sourceTerm = productFactors(summands[0])
        let overlayTerm = productFactors(summands[1])
        return sourceTerm.count == 2
            && member(sourceTerm[0], name: source, components: alphaComponents)
            && oneMinus(sourceTerm[1], name: weight)
            && overlayTerm.count == 2
            && member(overlayTerm[0], name: overlay, components: alphaComponents)
            && identifier(overlayTerm[1]) == weight
    }

    private static func associatedOverRGB(
        _ expression: ArraySlice<Token>,
        source: String,
        overlay: String,
        weight: String
    ) -> Bool {
        let summands = topLevelSummands(stripOuterParens(expression))
        guard summands.count == 2 else { return false }
        let sourceTerm = productFactors(summands[0])
        let overlayTerm = productFactors(summands[1])
        return sourceTerm.count == 3
            && member(sourceTerm[0], name: source, components: rgbComponents)
            && member(sourceTerm[1], name: source, components: alphaComponents)
            && oneMinus(sourceTerm[2], name: weight)
            && overlayTerm.count == 3
            && member(overlayTerm[0], name: overlay, components: rgbComponents)
            && member(overlayTerm[1], name: overlay, components: alphaComponents)
            && identifier(overlayTerm[2]) == weight
    }

    private static func srcRGB(
        _ expression: ArraySlice<Token>,
        overlay: String,
        saved: String,
        weight: String
    ) -> Bool {
        guard let mix = call(stripOuterParens(expression)),
              mixNames.contains(mix.name),
              mix.arguments.count == 3,
              member(mix.arguments[0], name: overlay, components: rgbComponents),
              member(mix.arguments[1], name: saved, components: rgbComponents)
        else { return false }
        let factors = productFactors(stripOuterParens(mix.arguments[2]))
        guard factors.count == 2,
              stepAlpha(factors[0], name: saved),
              oneMinusAlphaProduct(factors[1], color: overlay, weight: weight)
        else { return false }
        return true
    }

    private static func dstRGB(
        _ expression: ArraySlice<Token>,
        overlay: String,
        saved: String,
        weight: String
    ) -> Bool {
        guard let mix = call(stripOuterParens(expression)),
              mixNames.contains(mix.name),
              mix.arguments.count == 3,
              member(mix.arguments[0], name: saved, components: rgbComponents),
              member(mix.arguments[1], name: overlay, components: rgbComponents),
              let step = call(stripOuterParens(mix.arguments[2])),
              step.name == "step",
              step.arguments.count == 2,
              isThreshold(step.arguments[0])
        else { return false }
        let coverage = productFactors(stripOuterParens(step.arguments[1]))
        guard coverage.count == 2,
              member(coverage[0], name: overlay, components: alphaComponents),
              oneMinusAlphaProduct(coverage[1], color: saved, minusWeight: weight)
        else { return false }
        return true
    }

    private static func rgbCompensation(
        _ expression: ArraySlice<Token>,
        sourceRGB: String,
        destinationRGB: String,
        weight: String,
        newAlpha: String
    ) -> Bool {
        let factors = productFactors(stripOuterParens(expression))
        guard factors.count == 2,
              let mix = call(stripOuterParens(factors[0])),
              mixNames.contains(mix.name),
              mix.arguments.count == 3,
              identifier(mix.arguments[0]) == sourceRGB,
              identifier(mix.arguments[1]) == destinationRGB,
              identifier(mix.arguments[2]) == weight,
              oneMinus(factors[1], name: newAlpha)
        else { return false }
        return true
    }

    private static func stepAlpha(
        _ expression: ArraySlice<Token>,
        name: String
    ) -> Bool {
        guard let step = call(stripOuterParens(expression)),
              step.name == "step",
              step.arguments.count == 2,
              isThreshold(step.arguments[0]),
              member(step.arguments[1], name: name, components: alphaComponents)
        else { return false }
        return true
    }

    /// `1.0 - color.a * weight`, including an optional outer pair of parens.
    private static func oneMinusAlphaProduct(
        _ expression: ArraySlice<Token>,
        color: String,
        weight: String
    ) -> Bool {
        let value = stripOuterParens(expression)
        guard let minus = topLevelOperator(value, op: "-"),
              isOne(value[..<minus]) else { return false }
        let factors = productFactors(
            value[value.index(after: minus)...]
        )
        guard factors.count == 2 else { return false }
        return member(factors[0], name: color, components: alphaComponents)
            && identifier(factors[1]) == weight
            || identifier(factors[0]) == weight
            && member(factors[1], name: color, components: alphaComponents)
    }

    /// `1.0 - color.a * (1.0 - weight)`, including optional parens.
    private static func oneMinusAlphaProduct(
        _ expression: ArraySlice<Token>,
        color: String,
        minusWeight: String
    ) -> Bool {
        let value = stripOuterParens(expression)
        guard let minus = topLevelOperator(value, op: "-"),
              isOne(value[..<minus]) else { return false }
        let factors = productFactors(
            value[value.index(after: minus)...]
        )
        guard factors.count == 2,
              member(factors[0], name: color, components: alphaComponents),
              oneMinus(factors[1], name: minusWeight)
        else { return false }
        return true
    }

    private static func helpersDoNotSample(
        _ fragment: Unit,
        excluding main: Unit.Function
    ) -> Bool {
        fragment.functions.allSatisfy { function in
            function.name == main.name
                || !function.bodyRange.contains(where: {
                    sampleFunctions.contains(fragment.tokens[$0].text)
                })
        }
    }

    private static func sampleCallCount(in fragment: Unit) -> Int {
        fragment.tokens.indices.filter {
            sampleFunctions.contains(fragment.tokens[$0].text)
        }.count
    }
}

import Foundation

/// Proves a generated RGB replacement that reads one straight-color carrier,
/// interpolates RGB-only auxiliary data, and copies the carrier alpha to the
/// sole output. Resource purpose and readiness remain MaterialProgram facts;
/// this source proof never selects by effect, path, sample, or variable name.
nonisolated enum SceneAuthoredShaderGeneratedAuxiliaryRGBPreservedAlphaAnalyzer {
    private typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private enum Projection {
        case fullVector
        case rgb
    }

    private struct SampleCall {
        let index: Int
        let close: Int
        let slot: Int
        let projection: Projection
    }

    static func analyze(_ fragment: Unit) -> SceneAuthoredShaderTypedDataRGBFilterFact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let tokens = fragment.tokens
        let outputs = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard outputs.count == 1,
              let output = outputs.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output,
                    in: tokens,
                    body: main.bodyRange
                ),
              expression.endIndex + 1 == main.bodyRange.upperBound - 1,
              let construction = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(expression),
              ["vec4", "float4"].contains(construction.name),
              construction.arguments.count == 2,
              let blend = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(construction.arguments[0]),
              blend.name == "ApplyBlending",
              blend.arguments.count == 4,
              let rawMode = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .number(blend.arguments[0]),
              rawMode.rounded() == rawMode,
              let mode = Int(exactly: rawMode),
              (0 ... 32).contains(mode),
              let carrier = projectedIdentifier(
                  blend.arguments[1], projections: ["rgb", "xyz"]
              ),
              projectedIdentifier(
                  construction.arguments[1], projections: ["a", "w"]
              ) == carrier,
              let generated = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(blend.arguments[2]),
              ["mix", "lerp"].contains(generated.name),
              generated.arguments.count == 3,
              let firstAuxiliary = rgbSampleSlot(generated.arguments[0]),
              let secondAuxiliary = rgbSampleSlot(generated.arguments[1]),
              firstAuxiliary == secondAuxiliary,
              sampleFunctionCount(generated.arguments[2]) == 0,
              sampleFunctionCount(blend.arguments[3]) == 0,
              validRGBHelperBoundary(fragment),
              !main.bodyRange.contains(where: {
                  ["if", "for", "while", "do", "switch", "discard",
                   "gl_FragDepth"].contains(tokens[$0].text)
              })
        else { return nil }

        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound && index < output
                && tokens[index].text == carrier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  definition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: definition,
                    in: tokens,
                    body: main.bodyRange
                ),
              let sourceSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(initializer),
              sourceSlot != firstAuxiliary,
              samplerType(slot: sourceSlot, fragment: fragment) == "sampler2D",
              samplerType(slot: firstAuxiliary, fragment: fragment) == "sampler2D",
              let calls = sampleCalls(tokens: tokens),
              calls.count == 3,
              let sourceCall = calls.first(where: {
                  initializer.indices.contains($0.index)
              }),
              sourceCall.slot == sourceSlot,
              sourceCall.projection == .fullVector,
              calls.filter({ $0.slot == sourceSlot }).count == 1,
              calls.filter({ $0.slot == firstAuxiliary }).count == 2,
              calls.filter({ $0.slot == firstAuxiliary }).allSatisfy({
                  $0.projection == .rgb && expression.indices.contains($0.index)
              }),
              calls.allSatisfy({
                  main.bodyRange.contains($0.index)
              }),
              carrierUsesAreReadOnly(
                  carrier,
                  definition: definition,
                  output: output,
                  main: main,
                  tokens: tokens
              )
        else { return nil }

        return .init(
            sourceSlot: sourceSlot,
            terminalTransform: .identity,
            fullVectorDataSampleCallCounts: [:],
            rgbDataSampleCallCounts: [firstAuxiliary: 2],
            redDataSampleCallCounts: [:],
            redGreenDataSampleCallCounts: [:]
        )
    }

    /// RGB helper internals remain authored program semantics and are preserved
    /// by the compiler. The color boundary only needs to prove a value-only
    /// RGB result with no texture or final-output side effects.
    private static func validRGBHelperBoundary(_ fragment: Unit) -> Bool {
        let helpers = fragment.functions.filter { $0.name == "ApplyBlending" }
        guard helpers.count == 1,
              let helper = helpers.first,
              ["vec3", "float3"].contains(helper.returnType),
              SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .blendParameterNames(helper, fragment: fragment) != nil,
              !fragment.tokens[helper.parameterRange].contains(where: {
                  ["out", "inout"].contains($0.text)
              }),
              !fragment.tokens[helper.bodyRange].contains(where: {
                  ["texSample2D", "texture2D", "texSample2DLod", "textureLod",
                   "gl_FragColor"].contains($0.text)
              }) else { return false }
        return true
    }

    private static func carrierUsesAreReadOnly(
        _ carrier: String,
        definition: Int,
        output: Int,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let wholeAssignments = main.bodyRange.filter { index in
            index > definition && index < output
                && tokens[index].text == carrier
                && index + 1 < output
                && tokens[index + 1].text == "="
        }
        guard wholeAssignments.count <= 1 else { return false }
        var permittedWholeUseIndices: Set<Int> = []
        if let assignment = wholeAssignments.first {
            guard SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                assignment,
                tokens: tokens,
                body: main.bodyRange
            ),
            let value = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: assignment,
                    in: tokens,
                    body: main.bodyRange
                ),
            let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer.call(value),
            call.name == "saturate",
            call.arguments.count == 1,
            SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(call.arguments[0]) == carrier else { return false }
            permittedWholeUseIndices.insert(assignment)
            permittedWholeUseIndices.formUnion(value.indices.filter {
                tokens[$0].text == carrier
            })
        }

        let assignmentOperators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for index in (definition + 1) ..< output where tokens[index].text == carrier {
            if permittedWholeUseIndices.contains(index) { continue }
            guard index + 2 < output,
                  tokens[index + 1].text == ".",
                  ["r", "g", "b", "a", "x", "y", "z", "w", "rgb", "xyz"]
                    .contains(tokens[index + 2].text),
                  index + 3 >= output
                    || !assignmentOperators.contains(tokens[index + 3].text)
            else { return false }
        }
        return true
    }

    private static func rgbSampleSlot(_ expression: ArraySlice<Token>) -> Int? {
        let value = Array(
            SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .strippingParentheses(expression)
        )
        guard value.count >= 8,
              value[value.count - 2].text == ".",
              ["rgb", "xyz"].contains(value.last!.text),
              let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(value.dropLast(2)[...]),
              ["texSample2DLod", "textureLod"].contains(call.name),
              call.arguments.count == 3,
              let sampler = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(call.arguments[0])
        else { return nil }
        return textureSlot(sampler)
    }

    private static func sampleFunctionCount(
        _ expression: ArraySlice<Token>
    ) -> Int {
        expression.filter {
            ["texSample2D", "texture2D", "texSample2DLod", "textureLod"]
                .contains($0.text)
        }.count
    }

    private static func projectedIdentifier(
        _ expression: ArraySlice<Token>,
        projections: Set<String>
    ) -> String? {
        let value = Array(
            SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .strippingParentheses(expression)
        )
        guard value.count == 3,
              value[0].kind == .identifier,
              value[1].text == ".",
              projections.contains(value[2].text) else { return nil }
        return value[0].text
    }

    private static func sampleCalls(tokens: [Token]) -> [SampleCall]? {
        let names: Set<String> = [
            "texSample2D", "texture2D", "texSample2DLod", "textureLod",
        ]
        var result: [SampleCall] = []
        for index in tokens.indices where names.contains(tokens[index].text) {
            guard index + 3 < tokens.count,
                  tokens[index + 1].text == "(",
                  let slot = textureSlot(tokens[index + 2].text),
                  tokens[index + 3].text == ",",
                  let close = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                    .matching(index + 1, tokens: tokens)
            else { return nil }
            let projection: Projection
            if close + 2 < tokens.count,
               tokens[close + 1].text == ".",
               ["rgb", "xyz"].contains(tokens[close + 2].text) {
                projection = .rgb
            } else if close + 1 < tokens.count,
                      tokens[close + 1].text != "." {
                projection = .fullVector
            } else {
                return nil
            }
            result.append(.init(
                index: index,
                close: close,
                slot: slot,
                projection: projection
            ))
        }
        return result
    }

    private static func samplerType(slot: Int, fragment: Unit) -> String? {
        let name = "g_Texture\(slot)"
        let types = fragment.declarations.compactMap { declaration -> String? in
            guard declaration.name == name else { return nil }
            return declaration.typeName
        }
        return types.count == 1 ? types[0] : nil
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }
}

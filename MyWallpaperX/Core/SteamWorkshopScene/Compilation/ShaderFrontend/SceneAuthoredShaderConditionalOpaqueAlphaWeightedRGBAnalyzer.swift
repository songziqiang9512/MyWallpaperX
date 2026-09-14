import Foundation

/// Proves the canonicalized no-mask form of a bounded opaque post-process
/// that averages straight RGB with each sample's own alpha, applies one pure
/// RGB transform, and publishes opaque output. The proof is structural: slot,
/// varying, local, helper, and uniform names remain authored data.
nonisolated enum SceneAuthoredShaderConditionalOpaqueAlphaWeightedRGBAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
        let sampleCount: Int
    }

    private struct Locals {
        let weight: String
        let accumulator: String
        let sample: String
        let unusedVector: String?
    }

    private struct Block {
        let body: Range<Int>
        let closing: Int
    }

    private struct OutputFact {
        let radius: String
    }

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
        let tokens = fragment.tokens
        let mains = fragment.functions.filter { $0.name == "main" }
        guard fragment.stage == .fragment,
              fragment.functions.count == 2,
              mains.count == 1,
              let main = mains.first,
              main.parameterRange.isEmpty,
              let helper = fragment.functions.first(where: { $0.name != "main" }),
              identityHelper(helper, fragment: fragment),
              !main.bodyRange.contains(where: {
                  ["out", "inout", "else", "for", "while", "do", "switch",
                   "discard", "break", "continue", "return", "?"]
                    .contains(tokens[$0].text)
              }) else { return nil }

        let conditions = main.bodyRange.filter { tokens[$0].text == "if" }
        let outputs = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard conditions.count == 1,
              outputs.count == 1,
              let condition = conditions.first,
              let output = outputs.first,
              main.bodyRange.contains(output),
              condition + 1 < output,
              tokens[condition + 1].text == "(",
              let conditionClose = matchingDelimiter(
                  at: condition + 1,
                  tokens: tokens
              ),
              conditionClose + 1 < output,
              tokens[conditionClose + 1].text == "{",
              let bodyClose = matchingDelimiter(
                  at: conditionClose + 1,
                  tokens: tokens
              ),
              bodyClose + 1 == output,
              let declarations = statementRanges(
                  in: (main.bodyRange.lowerBound + 1)..<condition,
                  tokens: tokens
              ),
              declarations.count == 3,
              let locals = localDeclarations(declarations, tokens: tokens),
              let gate = gateUniforms(
                  (condition + 2)..<conditionClose,
                  tokens: tokens
              ),
              let outputEnd = firstSemicolon(
                  from: output,
                  before: main.bodyRange.upperBound - 1,
                  tokens: tokens
              ),
              outputEnd + 1 == main.bodyRange.upperBound - 1,
              let outputFact = opaqueOutput(
                  output..<outputEnd,
                  accumulator: locals.accumulator,
                  strength: gate.strength,
                  tokens: tokens
              ),
              let body = bodyElements(
                  in: (conditionClose + 2)..<bodyClose,
                  tokens: tokens
              ),
              (1 ... 16).contains(body.blocks.count),
              transform(
                  body.transform,
                  accumulator: locals.accumulator,
                  weight: locals.weight,
                  helper: helper.name,
                  tokens: tokens
              ) != nil else { return nil }

        let transformFact = transform(
            body.transform,
            accumulator: locals.accumulator,
            weight: locals.weight,
            helper: helper.name,
            tokens: tokens
        )!
        let uniformNames = [
            gate.strength, gate.activation, outputFact.radius,
            transformFact.threshold, transformFact.exponent,
        ]
        guard Set(uniformNames).count == uniformNames.count,
              uniformNames.allSatisfy({ name in
                  fragment.declarations.filter {
                      $0.name == name && $0.storage == .uniform
                        && $0.typeName == "float" && $0.arraySize == nil
                  }.count == 1
              }) else { return nil }

        var sourceSlot: Int?
        var coordinate: String?
        for (ordinal, block) in body.blocks.enumerated() {
            guard ordinal == 0 || body.blocks[ordinal - 1].closing + 1
                    == block.body.lowerBound - 1,
                  let statements = statementRanges(
                      in: block.body,
                      tokens: tokens
                  ),
                  statements.count == 3,
                  let sampleFact = sampleAssignment(
                      statements[0],
                      sample: locals.sample,
                      expectedIndex: ordinal,
                      expectedCount: body.blocks.count,
                      fragment: fragment,
                      tokens: tokens
                  ),
                  sourceSlot.map({ $0 == sampleFact.slot }) ?? true,
                  coordinate.map({ $0 == sampleFact.coordinate }) ?? true,
                  weightedAccumulation(
                      statements[1],
                      accumulator: locals.accumulator,
                      sample: locals.sample,
                      tokens: tokens
                  ),
                  weightAccumulation(
                      statements[2],
                      weight: locals.weight,
                      sample: locals.sample,
                      tokens: tokens
                  ) else { return nil }
            sourceSlot = sampleFact.slot
            coordinate = sampleFact.coordinate
        }

        let count = body.blocks.count
        guard let sourceSlot, let coordinate,
              wordCount(locals.weight, in: main.bodyRange, tokens: tokens)
                == count + 2,
              wordCount(locals.accumulator, in: main.bodyRange, tokens: tokens)
                == count + 4,
              wordCount(locals.sample, in: main.bodyRange, tokens: tokens)
                == count * 4 + 1,
              wordCount(coordinate, in: main.bodyRange, tokens: tokens) == count,
              wordCount(helper.name, in: tokens.indices, tokens: tokens) == 2,
              wordCount(gate.strength, in: main.bodyRange, tokens: tokens) == 2,
              wordCount(gate.activation, in: main.bodyRange, tokens: tokens) == 1,
              wordCount(outputFact.radius, in: main.bodyRange, tokens: tokens) == 1,
              wordCount(transformFact.threshold, in: main.bodyRange, tokens: tokens)
                == 1,
              wordCount(transformFact.exponent, in: main.bodyRange, tokens: tokens)
                == 1,
              locals.unusedVector.map({
                  wordCount($0, in: main.bodyRange, tokens: tokens) == 1
              }) ?? true,
              main.bodyRange.filter({ isTextureCall(tokens[$0].text) }).count
                == count,
              tokens.indices.filter({ isTextureCall(tokens[$0].text) }).count
                == count,
              mainCallsAreBounded(main, helper: helper.name, tokens: tokens)
        else { return nil }
        return .init(sourceSlot: sourceSlot, sampleCount: count)
    }

    private static func identityHelper(
        _ function: Unit.Function,
        fragment: Unit
    ) -> Bool {
        let tokens = fragment.tokens
        let parameters = Array(tokens[function.parameterRange])
        let body = Array(tokens[function.bodyRange]).map(\.text)
        guard ["vec3", "float3"].contains(function.returnType),
              parameters.count == 2,
              parameters[0].text == function.returnType,
              parameters[1].kind == .identifier else { return false }
        return body == ["{", "return", parameters[1].text, ";", "}"]
    }

    private static func localDeclarations(
        _ ranges: [Range<Int>],
        tokens: [Token]
    ) -> Locals? {
        let weight = Array(tokens[ranges[0]])
        let color = Array(tokens[ranges[1]])
        let sample = Array(tokens[ranges[2]])
        guard weight.count == 4,
              weight[0].text == "float",
              weight[1].kind == .identifier,
              weight[2].text == "=",
              number(weight[3]) == 0,
              [7, 9].contains(color.count),
              ["vec3", "float3"].contains(color[0].text),
              color[1].kind == .identifier,
              color[2].text == "=",
              ["CAST3", "vec3", "float3"].contains(color[3].text),
              color[4].text == "(",
              number(color[5]) == 0,
              color[6].text == ")",
              sample.count == 2,
              ["vec4", "float4"].contains(sample[0].text),
              sample[1].kind == .identifier else { return nil }
        let unused: String?
        if color.count == 9 {
            guard color[7].text == ",", color[8].kind == .identifier else {
                return nil
            }
            unused = color[8].text
        } else {
            unused = nil
        }
        let names = [weight[1].text, color[1].text, sample[1].text]
            + (unused.map { [$0] } ?? [])
        guard Set(names).count == names.count else { return nil }
        return .init(
            weight: weight[1].text,
            accumulator: color[1].text,
            sample: sample[1].text,
            unusedVector: unused
        )
    }

    private static func gateUniforms(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> (strength: String, activation: String)? {
        let values = Array(tokens[range])
        guard values.count == 7,
              values[0].kind == .identifier,
              values[1].text == ">",
              number(values[2]).map({ $0 > 0 }) == true,
              values[3].text == "&&",
              values[4].kind == .identifier,
              values[5].text == ">",
              number(values[6]).map({ $0 > 0 }) == true,
              values[0].text != values[4].text else { return nil }
        return (values[0].text, values[4].text)
    }

    private static func bodyElements(
        in range: Range<Int>,
        tokens: [Token]
    ) -> (blocks: [Block], transform: Range<Int>)? {
        var blocks: [Block] = []
        var cursor = range.lowerBound
        while cursor < range.upperBound, tokens[cursor].text == "{" {
            guard let closing = matchingDelimiter(at: cursor, tokens: tokens),
                  closing < range.upperBound else { return nil }
            blocks.append(.init(body: (cursor + 1)..<closing, closing: closing))
            cursor = closing + 1
        }
        guard !blocks.isEmpty,
              let statements = statementRanges(
                  in: cursor..<range.upperBound,
                  tokens: tokens
              ),
              statements.count == 1,
              let transform = statements.first else { return nil }
        return (blocks, transform)
    }

    private static func sampleAssignment(
        _ range: Range<Int>,
        sample: String,
        expectedIndex: Int,
        expectedCount: Int,
        fragment: Unit,
        tokens: [Token]
    ) -> (slot: Int, coordinate: String)? {
        let values = Array(tokens[range])
        guard values.count >= 10,
              values[0].text == sample,
              values[1].text == "=",
              let call = functionCall(Array(values.dropFirst(2))),
              isTextureCall(call.name),
              call.arguments.count == 2,
              call.arguments[0].count == 1,
              let sampler = call.arguments[0].first,
              let slot = textureSlot(sampler.text),
              call.arguments[1].count == 4,
              call.arguments[1][0].kind == .identifier,
              call.arguments[1][1].text == "[",
              integer(call.arguments[1][2]) == expectedIndex,
              call.arguments[1][3].text == "]" else { return nil }
        let coordinate = call.arguments[1][0].text
        guard fragment.declarations.filter({
                  $0.name == sampler.text && $0.storage == .uniform
                    && $0.typeName == "sampler2D" && $0.arraySize == nil
              }).count == 1,
              fragment.declarations.filter({
                  $0.name == coordinate && $0.storage == .varying
                    && ["vec2", "float2"].contains($0.typeName)
                    && $0.arraySize == expectedCount
              }).count == 1 else { return nil }
        return (slot, coordinate)
    }

    private static func weightedAccumulation(
        _ range: Range<Int>,
        accumulator: String,
        sample: String,
        tokens: [Token]
    ) -> Bool {
        let values = Array(tokens[range]).map(\.text)
        return values.count == 9
            && values[0] == accumulator && values[1] == "+="
            && values[2] == sample && values[3] == "."
            && ["rgb", "xyz"].contains(values[4]) && values[5] == "*"
            && values[6] == sample && values[7] == "."
            && ["a", "w"].contains(values[8])
    }

    private static func weightAccumulation(
        _ range: Range<Int>,
        weight: String,
        sample: String,
        tokens: [Token]
    ) -> Bool {
        let values = Array(tokens[range]).map(\.text)
        return values.count == 5
            && values[0] == weight && values[1] == "+="
            && values[2] == sample && values[3] == "."
            && ["a", "w"].contains(values[4])
    }

    private static func transform(
        _ range: Range<Int>,
        accumulator: String,
        weight: String,
        helper: String,
        tokens: [Token]
    ) -> (threshold: String, exponent: String)? {
        let values = Array(tokens[range])
        guard values.count > 4,
              values[0].text == accumulator,
              values[1].text == "=",
              let power = functionCall(Array(values.dropFirst(2))),
              power.name == "pow", power.arguments.count == 2 else { return nil }

        var colorExpression = power.arguments[0]
        if let multiply = topLevelIndices("*", in: colorExpression).first {
            guard topLevelIndices("*", in: colorExpression).count == 1,
                  multiply + 1 < colorExpression.count,
                  number(colorExpression[multiply + 1]).map({ $0 == 1 }) == true,
                  multiply + 2 == colorExpression.count else { return nil }
            colorExpression = Array(colorExpression[..<multiply])
        }
        guard let helperCall = functionCall(colorExpression),
              helperCall.name == helper,
              helperCall.arguments.count == 1,
              let saturate = functionCall(helperCall.arguments[0]),
              saturate.name == "saturate",
              saturate.arguments.count == 1 else { return nil }
        let normalized = saturate.arguments[0]
        guard normalized.count == 5,
              normalized[0].text == accumulator,
              normalized[1].text == "/",
              normalized[2].text == weight,
              normalized[3].text == "-",
              normalized[4].kind == .identifier,
              let exponent = functionCall(power.arguments[1]),
              ["CAST3", "vec3", "float3"].contains(exponent.name),
              exponent.arguments.count == 1,
              exponent.arguments[0].count == 1,
              exponent.arguments[0][0].kind == .identifier else { return nil }
        return (normalized[4].text, exponent.arguments[0][0].text)
    }

    private static func opaqueOutput(
        _ range: Range<Int>,
        accumulator: String,
        strength: String,
        tokens: [Token]
    ) -> OutputFact? {
        let values = Array(tokens[range])
        guard values.count > 4,
              values[0].text == "gl_FragColor",
              values[1].text == "=",
              let output = functionCall(Array(values.dropFirst(2))),
              ["vec4", "float4"].contains(output.name),
              output.arguments.count == 2,
              output.arguments[0].count == 7,
              output.arguments[0][0].text == accumulator,
              output.arguments[0][1].text == "*",
              output.arguments[0][2].text == strength,
              output.arguments[0][3].text == "*",
              output.arguments[0][4].kind == .identifier,
              output.arguments[0][5].text == "*",
              number(output.arguments[0][6]).map({ $0.isFinite && $0 > 0 })
                == true,
              output.arguments[1].count == 1,
              number(output.arguments[1][0]) == 1 else { return nil }
        return .init(radius: output.arguments[0][4].text)
    }

    private struct Call {
        let name: String
        let arguments: [[Token]]
    }

    private static func functionCall(_ values: [Token]) -> Call? {
        guard values.count >= 3,
              values[0].kind == .identifier,
              values[1].text == "(",
              values.last?.text == ")",
              matchingDelimiter(at: 1, tokens: values) == values.count - 1,
              let arguments = split(
                  2..<(values.count - 1),
                  separator: ",",
                  tokens: values
              ) else { return nil }
        return .init(
            name: values[0].text,
            arguments: arguments.map { Array(values[$0]) }
        )
    }

    private static func mainCallsAreBounded(
        _ main: Unit.Function,
        helper: String,
        tokens: [Token]
    ) -> Bool {
        let allowed: Set<String> = [
            "if", "texSample2D", "texture2D", "pow", "saturate",
            "CAST3", "vec3", "float3", "vec4", "float4", helper,
        ]
        return main.bodyRange.allSatisfy { index in
            guard index + 1 < main.bodyRange.upperBound,
                  tokens[index].kind == .identifier,
                  tokens[index + 1].text == "(" else { return true }
            return allowed.contains(tokens[index].text)
        }
    }

    private static func statementRanges(
        in range: Range<Int>,
        tokens: [Token]
    ) -> [Range<Int>]? {
        guard !range.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            let text = tokens[index].text
            if ["(", "["].contains(text) { depth += 1 }
            if [")", "]"].contains(text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if text == ";", depth == 0 {
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            }
        }
        guard depth == 0, start == range.upperBound else { return nil }
        return result
    }

    private static func split(
        _ range: Range<Int>,
        separator: String,
        tokens: [Token]
    ) -> [Range<Int>]? {
        guard !range.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            let text = tokens[index].text
            if ["(", "["].contains(text) { depth += 1 }
            if [")", "]"].contains(text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if text == separator, depth == 0 {
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    private static func topLevelIndices(
        _ value: String,
        in tokens: [Token]
    ) -> [Int] {
        var result: [Int] = []
        var depth = 0
        for index in tokens.indices {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == value, depth == 0 { result.append(index) }
        }
        return result
    }

    private static func matchingDelimiter(
        at opening: Int,
        tokens: [Token]
    ) -> Int? {
        guard tokens.indices.contains(opening),
              let closing = ["(": ")", "[": "]", "{": "}"][tokens[opening].text]
        else { return nil }
        var depth = 0
        for index in opening..<tokens.count {
            if tokens[index].text == tokens[opening].text { depth += 1 }
            if tokens[index].text == closing { depth -= 1 }
            if depth == 0 { return index }
        }
        return nil
    }

    private static func firstSemicolon(
        from start: Int,
        before end: Int,
        tokens: [Token]
    ) -> Int? {
        guard start < end else { return nil }
        return (start..<end).first { tokens[$0].text == ";" }
    }

    private static func wordCount(
        _ name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int {
        range.filter { tokens[$0].text == name }.count
    }

    private static func isTextureCall(_ name: String) -> Bool {
        ["texSample2D", "texture2D"].contains(name)
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }

    private static func integer(_ token: Token) -> Int? {
        guard let value = number(token),
              value.rounded(.towardZero) == value else { return nil }
        return Int(exactly: value)
    }

    private static func number(_ token: Token) -> Double? {
        var text = token.text
        if text.last.map({ "fF".contains($0) }) == true { text.removeLast() }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
}

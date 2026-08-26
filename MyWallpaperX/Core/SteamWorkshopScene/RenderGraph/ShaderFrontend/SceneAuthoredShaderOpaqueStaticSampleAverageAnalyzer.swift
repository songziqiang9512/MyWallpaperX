import Foundation

/// Proves one opaque RGB average assembled from a statically expanded list of
/// same-slot samples. Coordinate expressions remain authored data; the fact
/// owns only sample provenance, exact work, normalization, and opaque alpha.
nonisolated enum SceneAuthoredShaderOpaqueStaticSampleAverageAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
        let sampleCount: Int
    }

    private struct Sample {
        let slot: Int
        let sampler: String
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
              fragment.functions.count == 1,
              mains.count == 1,
              let main = mains.first,
              main.parameterRange.isEmpty,
              !tokens.contains(where: {
                  ["out", "inout", "if", "else", "for", "while", "do",
                   "switch", "discard", "break", "continue", "return", "?"]
                    .contains($0.text)
              }),
              let statements = statements(in: main.bodyRange, tokens: tokens),
              (3 ... 17).contains(statements.count),
              let first = initialSample(statements[0], tokens: tokens)
        else { return nil }

        let additions = statements.dropFirst().dropLast().compactMap {
            addedSample(
                $0,
                accumulator: first.accumulator,
                tokens: tokens
            )
        }
        let sampleCount = additions.count + 1
        guard additions.count == statements.count - 2,
              (2 ... 16).contains(sampleCount),
              additions.allSatisfy({ $0.slot == first.sample.slot }),
              additions.allSatisfy({ $0.sampler == first.sample.sampler }),
              opaqueNormalizedOutput(
                  statements[statements.count - 1],
                  accumulator: first.accumulator,
                  sampleCount: sampleCount,
                  tokens: tokens
              ),
              fragment.declarations.filter({
                  $0.name == first.sample.sampler
                    && $0.storage == .uniform
                    && $0.typeName == "sampler2D"
                    && $0.arraySize == nil
              }).count == 1,
              wordCount(
                  first.accumulator,
                  in: main.bodyRange,
                  tokens: tokens
              ) == sampleCount + 1,
              tokens.indices.filter({
                  ["texSample2D", "texture2D"]
                    .contains(tokens[$0].text)
              }).count == sampleCount,
              tokens.indices.filter({
                  tokens[$0].text == "gl_FragColor"
              }).count == 1 else { return nil }

        return .init(
            sourceSlot: first.sample.slot,
            sampleCount: sampleCount
        )
    }

    private static func initialSample(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> (accumulator: String, sample: Sample)? {
        let values = Array(tokens[range])
        guard values.count >= 10,
              ["vec3", "float3"].contains(values[0].text),
              values[1].kind == .identifier,
              values[2].text == "=",
              let sample = sampleExpression(
                  values[3..<values.count]
              ) else { return nil }
        return (values[1].text, sample)
    }

    private static func addedSample(
        _ range: Range<Int>,
        accumulator: String,
        tokens: [Token]
    ) -> Sample? {
        let values = Array(tokens[range])
        guard values.count >= 9,
              values[0].text == accumulator,
              values[1].text == "+=",
              let sample = sampleExpression(
                  values[2..<values.count]
              ) else { return nil }
        return sample
    }

    private static func sampleExpression(
        _ slice: ArraySlice<Token>
    ) -> Sample? {
        let values = Array(slice)
        guard values.count >= 7,
              ["texSample2D", "texture2D"]
                .contains(values[0].text),
              values[1].text == "(",
              let callClose = matchingDelimiter(at: 1, tokens: values),
              callClose == values.count - 3,
              values[callClose + 1].text == ".",
              ["rgb", "xyz"].contains(values[callClose + 2].text),
              let arguments = split(
                  2..<callClose,
                  separator: ",",
                  tokens: values
              ), arguments.count == 2 else { return nil }
        let sampler = Array(values[arguments[0]])
        let coordinate = Array(values[arguments[1]])
        guard sampler.count == 1,
              sampler[0].kind == .identifier,
              let slot = textureSlot(sampler[0].text),
              safeCoordinateExpression(coordinate) else { return nil }
        return .init(slot: slot, sampler: sampler[0].text)
    }

    private static func safeCoordinateExpression(_ tokens: [Token]) -> Bool {
        guard !tokens.isEmpty else { return false }
        let rejected = Set([
            "=", "+=", "-=", "*=", "/=", "++", "--", ";", "{", "}",
            "discard", "return", "texSample2D", "texture2D", "texture",
        ])
        var stack: [String] = []
        for (index, token) in tokens.enumerated() {
            if rejected.contains(token.text) { return false }
            if token.kind == .identifier,
               tokens.indices.contains(index + 1),
               tokens[index + 1].text == "(" {
                return false
            }
            if ["(", "["].contains(token.text) {
                stack.append(token.text)
            } else if [")", "]"].contains(token.text) {
                guard let opening = stack.popLast(),
                      (opening == "(" && token.text == ")")
                        || (opening == "[" && token.text == "]")
                else { return false }
            }
        }
        return stack.isEmpty
    }

    private static func opaqueNormalizedOutput(
        _ range: Range<Int>,
        accumulator: String,
        sampleCount: Int,
        tokens: [Token]
    ) -> Bool {
        let values = Array(tokens[range])
        guard values.count == 10,
              values[0].text == "gl_FragColor",
              values[1].text == "=",
              ["vec4", "float4"].contains(values[2].text),
              values[3].text == "(",
              values[5].text == "*",
              values[7].text == ",",
              number(values[8]) == 1,
              values[9].text == ")" else { return false }

        let weightToken: Token
        if values[4].text == accumulator {
            weightToken = values[6]
        } else if values[6].text == accumulator {
            weightToken = values[4]
        } else {
            return false
        }
        guard let weight = positiveLiteral(weightToken) else { return false }
        return abs(weight.value * Double(sampleCount) - 1)
            <= weight.roundingBound * Double(sampleCount) + 1e-12
    }

    private static func statements(
        in body: Range<Int>,
        tokens: [Token]
    ) -> [Range<Int>]? {
        let start = body.lowerBound + 1
        let end = body.upperBound - 1
        guard start < end else { return nil }
        var result: [Range<Int>] = []
        var statementStart = start
        var depth = 0
        for index in start..<end {
            let text = tokens[index].text
            if ["(", "["].contains(text) { depth += 1 }
            if [")", "]"].contains(text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if text == ";", depth == 0 {
                guard statementStart < index else { return nil }
                result.append(statementStart..<index)
                statementStart = index + 1
            }
        }
        guard depth == 0, statementStart == end else { return nil }
        return result
    }

    private static func split(
        _ range: Range<Int>,
        separator: String,
        tokens: [Token]
    ) -> [Range<Int>]? {
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

    private static func matchingDelimiter(
        at opening: Int,
        tokens: [Token]
    ) -> Int? {
        guard tokens.indices.contains(opening),
              let closing = ["(": ")", "[": "]"][tokens[opening].text]
        else { return nil }
        var depth = 0
        for index in opening..<tokens.count {
            if tokens[index].text == tokens[opening].text { depth += 1 }
            if tokens[index].text == closing { depth -= 1 }
            if depth == 0 { return index }
        }
        return nil
    }

    private static func wordCount(
        _ name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int {
        range.filter { tokens[$0].text == name }.count
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }

    private static func positiveLiteral(
        _ token: Token
    ) -> (value: Double, roundingBound: Double)? {
        var text = token.text
        if text.last.map({ "fF".contains($0) }) == true { text.removeLast() }
        guard !text.lowercased().contains("e"),
              let value = Double(text), value.isFinite, value > 0
        else { return nil }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let digits = parts.count == 2 ? parts[1].count : 0
        let bound = digits >= 5 ? 0.5 * pow(10, -Double(digits)) : 0
        return (value, bound)
    }

    private static func number(_ token: Token) -> Double? {
        var text = token.text
        if text.last.map({ "fF".contains($0) }) == true { text.removeLast() }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
}

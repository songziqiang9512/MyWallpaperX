import Foundation

/// Proves a bounded straight-color filter that repeatedly samples one texture,
/// weights RGB by sampled alpha, normalizes RGB by the accumulated alpha, and
/// derives output alpha from the same weighted accumulator. The proof depends
/// only on active source dataflow; effect names, paths, identities, and kernel
/// coordinates are deliberately outside this contract.
nonisolated enum SceneAuthoredShaderAlphaWeightedSampleAverageAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let textureSlot: Int
        let sampleCount: Int
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
        guard fragment.stage == .fragment,
              fragment.functions.count == 1,
              let main = fragment.functions.first,
              main.name == "main" else { return nil }
        let tokens = fragment.tokens
        let body = main.bodyRange
        let rejectedControl = Set([
            "if", "else", "for", "while", "do", "switch", "discard",
            "break", "continue", "return",
        ])
        guard !body.contains(where: { rejectedControl.contains(tokens[$0].text) })
        else { return nil }

        let outputUses = body.filter { tokens[$0].text == "gl_FragColor" }
        guard outputUses.count == 1,
              let output = outputUses.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output,
                  tokens: tokens,
                  body: body
              ),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(after: output, in: tokens, body: body),
              let outputFact = outputFact(Array(outputExpression)) else {
            return nil
        }

        let accumulator = outputFact.accumulator
        guard let normalization = normalizationFact(
            accumulator: accumulator,
            tokens: tokens,
            body: body,
            before: output
        ) else { return nil }
        let weight = normalization.weight

        let accumulatorWrites = body.filter {
            $0 + 1 < tokens.count
                && tokens[$0].text == accumulator
                && tokens[$0 + 1].text == "+="
        }
        guard (1 ... 16).contains(accumulatorWrites.count),
              accumulatorWrites.count == outputFact.sampleCount,
              let sample = commonWeightedSample(
                  accumulatorWrites,
                  accumulator: accumulator,
                  tokens: tokens,
                  body: body
              ),
              zeroVectorDeclaration(
                  accumulator,
                  sample: sample,
                  tokens: tokens,
                  body: body
              ),
              zeroScalarDeclaration(weight, tokens: tokens, body: body)
        else { return nil }

        let sampleAssignments = body.filter {
            $0 + 1 < tokens.count
                && tokens[$0].text == sample
                && tokens[$0 + 1].text == "="
        }
        let weightWrites = body.filter {
            $0 + 1 < tokens.count
                && tokens[$0].text == weight
                && tokens[$0 + 1].text == "+="
        }
        guard sampleAssignments.count == outputFact.sampleCount,
              weightWrites.count == outputFact.sampleCount,
              weightWrites.last.map({ $0 < normalization.statementIndex }) == true
        else { return nil }

        var slot: Int?
        for ordinal in 0..<outputFact.sampleCount {
            let assignment = sampleAssignments[ordinal]
            guard let expression = SceneAuthoredShaderColorTransferAnalyzer
                    .assignmentExpression(after: assignment, in: tokens, body: body),
                  let currentSlot = SceneAuthoredShaderColorTransferAnalyzer
                    .directTextureSampleSlot(expression),
                  slot.map({ $0 == currentSlot }) ?? true,
                  assignment < accumulatorWrites[ordinal],
                  accumulatorWrites[ordinal] < weightWrites[ordinal],
                  ordinal + 1 == outputFact.sampleCount
                    || weightWrites[ordinal] < sampleAssignments[ordinal + 1],
                  matchesWeightWrite(
                      at: weightWrites[ordinal],
                      weight: weight,
                      sample: sample,
                      tokens: tokens
                  ) else { return nil }
            slot = currentSlot
        }
        guard let slot else { return nil }

        let sampleCalls = fragment.tokens.indices.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }
        guard sampleCalls.count == outputFact.sampleCount,
              wordCount(accumulator, tokens: tokens, in: body)
                == outputFact.sampleCount + 4,
              wordCount(sample, tokens: tokens, in: body)
                == 1 + outputFact.sampleCount * 4,
              wordCount(weight, tokens: tokens, in: body)
                == outputFact.sampleCount + 2 else { return nil }
        return .init(textureSlot: slot, sampleCount: outputFact.sampleCount)
    }

    private struct OutputFact {
        let accumulator: String
        let sampleCount: Int
    }

    private static func outputFact(_ values: [Token]) -> OutputFact? {
        guard values.count == 12,
              ["vec4", "float4"].contains(values[0].text),
              values[1].text == "(", values[3].text == ".",
              ["rgb", "xyz"].contains(values[4].text),
              values[5].text == ",", values[7].text == ".",
              ["a", "w"].contains(values[8].text),
              values[9].text == "/", values[10].kind == .number,
              values[11].text == ")",
              values[2].kind == .identifier,
              values[6].text == values[2].text,
              let count = exactInteger(values[10].text),
              (1 ... 16).contains(count) else { return nil }
        return .init(accumulator: values[2].text, sampleCount: count)
    }

    private struct NormalizationFact {
        let weight: String
        let statementIndex: Int
    }

    private static func normalizationFact(
        accumulator: String,
        tokens: [Token],
        body: Range<Int>,
        before output: Int
    ) -> NormalizationFact? {
        let matches = body.filter { index in
            index + 10 < output
                && tokens[index].text == accumulator
                && tokens[index + 1].text == "."
                && ["rgb", "xyz"].contains(tokens[index + 2].text)
                && tokens[index + 3].text == "/="
                && tokens[index + 4].text == "max"
                && tokens[index + 5].text == "("
                && tokens[index + 6].kind == .number
                && (Double(tokens[index + 6].text).map { $0.isFinite && $0 > 0 } ?? false)
                && tokens[index + 7].text == ","
                && tokens[index + 8].kind == .identifier
                && tokens[index + 9].text == ")"
                && tokens[index + 10].text == ";"
        }
        guard matches.count == 1, let match = matches.first else { return nil }
        return .init(
            weight: tokens[match + 8].text,
            statementIndex: match
        )
    }

    private static func commonWeightedSample(
        _ writes: [Int],
        accumulator: String,
        tokens: [Token],
        body: Range<Int>
    ) -> String? {
        var sample: String?
        for write in writes {
            guard write + 7 < body.upperBound,
                  tokens[write].text == accumulator,
                  tokens[write + 1].text == "+=",
                  tokens[write + 2].kind == .identifier,
                  tokens[write + 3].text == "*",
                  tokens[write + 4].text == tokens[write + 2].text,
                  tokens[write + 5].text == ".",
                  ["a", "w"].contains(tokens[write + 6].text),
                  tokens[write + 7].text == ";",
                  sample.map({ $0 == tokens[write + 2].text }) ?? true else {
                return nil
            }
            sample = tokens[write + 2].text
        }
        return sample
    }

    private static func matchesWeightWrite(
        at write: Int,
        weight: String,
        sample: String,
        tokens: [Token]
    ) -> Bool {
        write + 5 < tokens.count
            && tokens[write].text == weight
            && tokens[write + 1].text == "+="
            && tokens[write + 2].text == sample
            && tokens[write + 3].text == "."
            && ["a", "w"].contains(tokens[write + 4].text)
            && tokens[write + 5].text == ";"
    }

    private static func zeroVectorDeclaration(
        _ accumulator: String,
        sample: String,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let matches = body.filter { index in
            guard index > body.lowerBound, index + 6 < body.upperBound,
                  tokens[index].text == accumulator,
                  ["vec4", "float4"].contains(tokens[index - 1].text),
                  tokens[index + 1].text == "=",
                  ["CAST4", "vec4", "float4"].contains(tokens[index + 2].text),
                  tokens[index + 3].text == "(",
                  tokens[index + 4].kind == .number,
                  Double(tokens[index + 4].text) == 0,
                  tokens[index + 5].text == ")" else { return false }
            if tokens[index + 6].text == ";" {
                return hasStandaloneVectorDeclaration(
                    sample, tokens: tokens, body: body
                )
            }
            return index + 8 < body.upperBound
                && tokens[index + 6].text == ","
                && tokens[index + 7].text == sample
                && tokens[index + 8].text == ";"
        }
        return matches.count == 1
    }

    private static func hasStandaloneVectorDeclaration(
        _ name: String,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        body.contains { index in
            index > body.lowerBound && index + 1 < body.upperBound
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == ";"
        }
    }

    private static func zeroScalarDeclaration(
        _ name: String,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        body.filter { index in
            index > body.lowerBound && index + 3 < body.upperBound
                && tokens[index].text == name
                && tokens[index - 1].text == "float"
                && tokens[index + 1].text == "="
                && tokens[index + 2].kind == .number
                && Double(tokens[index + 2].text) == 0
                && tokens[index + 3].text == ";"
        }.count == 1
    }

    private static func wordCount(
        _ name: String,
        tokens: [Token],
        in range: Range<Int>
    ) -> Int {
        range.filter { tokens[$0].text == name }.count
    }

    private static func exactInteger(_ raw: String) -> Int? {
        guard let value = Double(raw), value.isFinite,
              value.rounded(.towardZero) == value else { return nil }
        return Int(exactly: value)
    }
}

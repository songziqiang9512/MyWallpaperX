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
        guard let outputFact = outputFact(
            outputUses: outputUses,
            tokens: tokens,
            body: body
        ) else {
            return nil
        }
        let output = outputFact.firstOutput

        let accumulator = outputFact.accumulator
        let normalization: NormalizationFact
        if let outputNormalization = outputFact.outputNormalization {
            normalization = outputNormalization
        } else {
            guard let prior = normalizationFact(
                accumulator: accumulator,
                tokens: tokens,
                body: body,
                before: output
            ) else { return nil }
            normalization = prior
        }
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
              sampleAssignments.allSatisfy({
                  isSampleAssignment(
                      at: $0, sample: sample, tokens: tokens, body: body
                  )
              }),
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
        guard let slot,
              sampleStorageIsLexicallyBound(
                  sample,
                  assignments: sampleAssignments,
                  accumulatorWrites: accumulatorWrites,
                  weightWrites: weightWrites,
                  tokens: tokens,
                  body: body
              ) else { return nil }

        let sampleCalls = fragment.tokens.indices.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }
        guard sampleCalls.count == outputFact.sampleCount,
              wordCount(accumulator, tokens: tokens, in: body)
                == outputFact.sampleCount + outputFact.accumulatorUseOverhead,
              wordCount(weight, tokens: tokens, in: body)
                == outputFact.sampleCount + 2 else { return nil }
        return .init(textureSlot: slot, sampleCount: outputFact.sampleCount)
    }

    private struct OutputFact {
        let accumulator: String
        let sampleCount: Int
        let firstOutput: Int
        let accumulatorUseOverhead: Int
        let outputNormalization: NormalizationFact?
    }

    private static func outputFact(
        outputUses: [Int],
        tokens: [Token],
        body: Range<Int>
    ) -> OutputFact? {
        if outputUses.count == 1,
           let output = outputUses.first,
           SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
               output,
               tokens: tokens,
               body: body
           ), let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: output, in: tokens, body: body),
           let whole = wholeOutputFact(Array(expression)) {
            return .init(
                accumulator: whole.accumulator,
                sampleCount: whole.sampleCount,
                firstOutput: output,
                accumulatorUseOverhead: 4,
                outputNormalization: nil
            )
        }
        guard outputUses.count == 2,
              let rgb = memberOutput(
                  outputUses[0],
                  expectedMembers: ["rgb", "xyz"],
                  tokens: tokens,
                  body: body
              ),
              let alpha = memberOutput(
                  outputUses[1],
                  expectedMembers: ["a", "w"],
                  tokens: tokens,
                  body: body
              ),
              let rgbFact = rgbNormalizationFact(rgb.expression),
              let alphaFact = alphaOutputFact(alpha.expression),
              rgbFact.accumulator == alphaFact.accumulator,
              rgb.statementEnd == outputUses[1],
              alpha.statementEnd == body.upperBound - 1,
              (1 ... 16).contains(alphaFact.sampleCount) else {
            return nil
        }
        return .init(
            accumulator: alphaFact.accumulator,
            sampleCount: alphaFact.sampleCount,
            firstOutput: outputUses[0],
            accumulatorUseOverhead: 3,
            outputNormalization: .init(
                weight: rgbFact.weight,
                statementIndex: outputUses[0]
            )
        )
    }

    private struct MemberOutput {
        let expression: [Token]
        let statementEnd: Int
    }

    private static func memberOutput(
        _ output: Int,
        expectedMembers: Set<String>,
        tokens: [Token],
        body: Range<Int>
    ) -> MemberOutput? {
        guard output + 3 < body.upperBound,
              tokens[output + 1].text == ".",
              expectedMembers.contains(tokens[output + 2].text),
              tokens[output + 3].text == "=",
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output,
                  tokens: tokens,
                  body: body
              ), let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: output + 2, in: tokens, body: body)
        else { return nil }
        return .init(
            expression: Array(expression),
            statementEnd: expression.endIndex + 1
        )
    }

    private struct RGBNormalizationFact {
        let accumulator: String
        let weight: String
    }

    private static func rgbNormalizationFact(
        _ values: [Token]
    ) -> RGBNormalizationFact? {
        guard values.count == 10,
              values[0].kind == .identifier,
              values[1].text == ".",
              ["rgb", "xyz"].contains(values[2].text),
              values[3].text == "/",
              values[4].text == "max",
              values[5].text == "(",
              values[6].kind == .number,
              (Double(values[6].text).map { $0.isFinite && $0 > 0 } ?? false),
              values[7].text == ",",
              values[8].kind == .identifier,
              values[9].text == ")" else { return nil }
        return .init(accumulator: values[0].text, weight: values[8].text)
    }

    private struct AlphaOutputFact {
        let accumulator: String
        let sampleCount: Int
    }

    private static func alphaOutputFact(_ values: [Token]) -> AlphaOutputFact? {
        guard values.count == 5,
              values[0].kind == .identifier,
              values[1].text == ".",
              ["a", "w"].contains(values[2].text),
              values[3].text == "/",
              values[4].kind == .number,
              let count = exactInteger(values[4].text) else { return nil }
        return .init(accumulator: values[0].text, sampleCount: count)
    }

    private struct WholeOutputFact {
        let accumulator: String
        let sampleCount: Int
    }

    private static func wholeOutputFact(_ values: [Token]) -> WholeOutputFact? {
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
                return true
            }
            return index + 8 < body.upperBound
                && tokens[index + 6].text == ","
                && tokens[index + 7].text == sample
                && tokens[index + 8].text == ";"
        }
        return matches.count == 1
    }

    private static func isSampleAssignment(
        at index: Int, sample: String, tokens: [Token], body: Range<Int>
    ) -> Bool {
        guard tokens[index].text == sample, tokens[index + 1].text == "=" else {
            return false
        }
        if index > body.lowerBound,
           ["vec4", "float4"].contains(tokens[index - 1].text) {
            return true
        }
        return hasStandaloneVectorDeclaration(sample, tokens: tokens, body: body)
    }

    private static func sampleStorageIsLexicallyBound(
        _ sample: String,
        assignments: [Int],
        accumulatorWrites: [Int],
        weightWrites: [Int],
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let localDeclarations = assignments.filter {
            $0 > body.lowerBound
                && ["vec4", "float4"].contains(tokens[$0 - 1].text)
        }
        if localDeclarations.isEmpty {
            return hasStandaloneVectorDeclaration(
                sample, tokens: tokens, body: body
            ) && wordCount(sample, tokens: tokens, in: body)
                == 1 + assignments.count * 4
        }
        guard localDeclarations == assignments,
              !hasStandaloneVectorDeclaration(sample, tokens: tokens, body: body)
        else { return false }

        var priorBlocks: [Range<Int>] = []
        for ordinal in assignments.indices {
            guard let block = innermostLexicalBlock(
                containing: assignments[ordinal], tokens: tokens, body: body
            ), block != body,
               block.contains(accumulatorWrites[ordinal]),
               block.contains(weightWrites[ordinal]),
               wordCount(sample, tokens: tokens, in: block) == 4,
               !priorBlocks.contains(block) else { return false }
            priorBlocks.append(block)
        }
        let boundUses = priorBlocks.reduce(0) {
            $0 + wordCount(sample, tokens: tokens, in: $1)
        }
        return boundUses == wordCount(sample, tokens: tokens, in: body)
    }

    private static func innermostLexicalBlock(
        containing index: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Range<Int>? {
        var openings: [Int] = []
        for cursor in body.lowerBound...index {
            if tokens[cursor].text == "{" {
                openings.append(cursor)
            } else if tokens[cursor].text == "}", !openings.isEmpty {
                openings.removeLast()
            }
        }
        guard let opening = openings.last else { return body }
        var depth = 1
        var cursor = opening + 1
        while cursor < body.upperBound {
            if tokens[cursor].text == "{" {
                depth += 1
            } else if tokens[cursor].text == "}" {
                depth -= 1
                if depth == 0 {
                    return (opening + 1)..<cursor
                }
            }
            cursor += 1
        }
        return nil
    }

    private static func hasStandaloneVectorDeclaration(
        _ name: String,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        body.contains { index in
            guard index > body.lowerBound, index + 1 < body.upperBound,
                  tokens[index].text == name,
                  tokens[index + 1].text == ";" else { return false }
            if ["vec4", "float4"].contains(tokens[index - 1].text) {
                return true
            }
            guard tokens[index - 1].text == "," else { return false }
            var cursor = index - 2
            while cursor >= body.lowerBound, tokens[cursor].text != ";" {
                if ["vec4", "float4"].contains(tokens[cursor].text) {
                    return true
                }
                cursor -= 1
            }
            return false
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

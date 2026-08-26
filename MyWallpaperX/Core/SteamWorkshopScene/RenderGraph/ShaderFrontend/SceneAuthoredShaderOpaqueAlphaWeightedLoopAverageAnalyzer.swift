import Foundation

/// Proves an opaque RGB average formed by a statically bounded loop over one
/// texture. RGB is weighted by sampled alpha and normalized by the matching
/// accumulated weight. Names, coordinates, slots, and loop counts remain
/// authored data; the proof only owns dataflow, exact work, and opaque alpha.
nonisolated enum SceneAuthoredShaderOpaqueAlphaWeightedLoopAverageAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
        let sampleCount: Int
    }

    private struct LoopFact {
        let index: String
        let count: Int
        let body: Range<Int>
        let closingBrace: Int
    }

    private struct Locals {
        let weight: String
        let accumulator: String
        let sample: String
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
        analyzeLoop(fragment) ?? analyzeExpanded(fragment)
    }

    private static func analyzeLoop(_ fragment: Unit) -> Fact? {
        let tokens = fragment.tokens
        let mains = fragment.functions.filter { $0.name == "main" }
        guard fragment.stage == .fragment,
              fragment.functions.count == 1,
              mains.count == 1,
              let main = mains.first,
              main.parameterRange.isEmpty,
              !tokens.contains(where: {
                  ["out", "inout", "if", "else", "while", "do", "switch",
                   "discard", "break", "continue", "return", "?"]
                    .contains($0.text)
              }) else { return nil }

        let loopMarkers = main.bodyRange.filter { tokens[$0].text == "for" }
        let outputs = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard loopMarkers.count == 1,
              outputs.count == 1,
              let loopMarker = loopMarkers.first,
              let output = outputs.first,
              main.bodyRange.contains(output),
              let loop = loopFact(
                  at: loopMarker,
                  within: main.bodyRange,
                  tokens: tokens
              ) else { return nil }

        let bodyStart = main.bodyRange.lowerBound + 1
        let bodyEnd = main.bodyRange.upperBound - 1
        guard let declarations = statementRanges(
                  in: bodyStart..<loopMarker,
                  tokens: tokens
              ),
              declarations.count == 3,
              let locals = localDeclarations(
                  declarations,
                  tokens: tokens
              ),
              loop.closingBrace + 1 == output,
              let outputEnd = firstSemicolon(
                  from: output,
                  before: bodyEnd,
                  tokens: tokens
              ),
              outputEnd + 1 == bodyEnd,
              opaqueOutput(
                  output..<outputEnd,
                  accumulator: locals.accumulator,
                  weight: locals.weight,
                  tokens: tokens
              ) else { return nil }

        guard let loopStatements = statementRanges(
                  in: loop.body,
                  tokens: tokens
              ),
              loopStatements.count == 3,
              let sample = sampleAssignment(
                  loopStatements[0],
                  sample: locals.sample,
                  loop: loop,
                  fragment: fragment,
                  tokens: tokens
              ),
              weightedAccumulation(
                  loopStatements[1],
                  accumulator: locals.accumulator,
                  sample: locals.sample,
                  tokens: tokens
              ),
              weightAccumulation(
                  loopStatements[2],
                  weight: locals.weight,
                  sample: locals.sample,
                  tokens: tokens
              ),
              wordCount(locals.weight, in: main.bodyRange, tokens: tokens) == 3,
              wordCount(locals.accumulator, in: main.bodyRange, tokens: tokens) == 3,
              wordCount(locals.sample, in: main.bodyRange, tokens: tokens) == 5,
              wordCount(loop.index, in: main.bodyRange, tokens: tokens) == 4,
              wordCount(sample.coordinate, in: main.bodyRange, tokens: tokens) == 1,
              main.bodyRange.filter({ isTextureCall(tokens[$0].text) }).count == 1,
              tokens.indices.filter({ isTextureCall(tokens[$0].text) }).count == 1
        else { return nil }

        return .init(sourceSlot: sample.slot, sampleCount: loop.count)
    }

    /// The shared backend canonicalizer expands linked varying-array loops
    /// before route selection. Re-prove the exact expanded sequence so the
    /// source fact survives that semantics-preserving lowering without using
    /// a path or prepared hash as authority.
    private static func analyzeExpanded(_ fragment: Unit) -> Fact? {
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
              }) else { return nil }

        let outputs = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard outputs.count == 1,
              let output = outputs.first,
              main.bodyRange.contains(output),
              let blocks = topLevelBlocks(
                  in: main.bodyRange,
                  before: output,
                  tokens: tokens
              ),
              (1 ... 16).contains(blocks.count),
              let firstBlock = blocks.first,
              let declarations = statementRanges(
                  in: (main.bodyRange.lowerBound + 1)..<firstBlock.opening,
                  tokens: tokens
              ),
              declarations.count == 3,
              let locals = localDeclarations(declarations, tokens: tokens),
              let lastBlock = blocks.last,
              lastBlock.closing + 1 == output,
              let outputEnd = firstSemicolon(
                  from: output,
                  before: main.bodyRange.upperBound - 1,
                  tokens: tokens
              ),
              outputEnd + 1 == main.bodyRange.upperBound - 1,
              opaqueOutput(
                  output..<outputEnd,
                  accumulator: locals.accumulator,
                  weight: locals.weight,
                  tokens: tokens
              ) else { return nil }

        var sourceSlot: Int?
        var coordinate: String?
        for (ordinal, block) in blocks.enumerated() {
            guard ordinal == 0 || blocks[ordinal - 1].closing + 1 == block.opening,
                  let statements = statementRanges(
                      in: block.body,
                      tokens: tokens
                  ),
                  statements.count == 3,
                  let sample = expandedSampleAssignment(
                      statements[0],
                      sample: locals.sample,
                      expectedIndex: ordinal,
                      expectedCount: blocks.count,
                      fragment: fragment,
                      tokens: tokens
                  ),
                  sourceSlot.map({ $0 == sample.slot }) ?? true,
                  coordinate.map({ $0 == sample.coordinate }) ?? true,
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
            sourceSlot = sample.slot
            coordinate = sample.coordinate
        }
        guard let sourceSlot, let coordinate,
              wordCount(locals.weight, in: main.bodyRange, tokens: tokens)
                == blocks.count + 2,
              wordCount(locals.accumulator, in: main.bodyRange, tokens: tokens)
                == blocks.count + 2,
              wordCount(locals.sample, in: main.bodyRange, tokens: tokens)
                == blocks.count * 4 + 1,
              wordCount(coordinate, in: main.bodyRange, tokens: tokens)
                == blocks.count,
              main.bodyRange.filter({ isTextureCall(tokens[$0].text) }).count
                == blocks.count,
              tokens.indices.filter({ isTextureCall(tokens[$0].text) }).count
                == blocks.count else { return nil }
        return .init(sourceSlot: sourceSlot, sampleCount: blocks.count)
    }

    private struct TopLevelBlock {
        let opening: Int
        let body: Range<Int>
        let closing: Int
    }

    private static func topLevelBlocks(
        in mainBody: Range<Int>,
        before output: Int,
        tokens: [Token]
    ) -> [TopLevelBlock]? {
        var result: [TopLevelBlock] = []
        var cursor = mainBody.lowerBound + 1
        while cursor < output {
            if tokens[cursor].text == "{" {
                guard let closing = matchingDelimiter(
                    at: cursor,
                    tokens: tokens
                ), closing < output else { return nil }
                result.append(.init(
                    opening: cursor,
                    body: (cursor + 1)..<closing,
                    closing: closing
                ))
                cursor = closing + 1
            } else {
                cursor += 1
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func expandedSampleAssignment(
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
              isTextureCall(values[2].text),
              values[3].text == "(",
              let callClose = matchingDelimiter(at: 3, tokens: values),
              callClose == values.count - 1,
              let arguments = split(
                  4..<callClose,
                  separator: ",",
                  tokens: values
              ),
              arguments.count == 2 else { return nil }
        let sampler = Array(values[arguments[0]])
        let coordinate = Array(values[arguments[1]])
        guard sampler.count == 1,
              let slot = textureSlot(sampler[0].text),
              coordinate.count == 4,
              coordinate[0].kind == .identifier,
              coordinate[1].text == "[",
              integer(coordinate[2]) == expectedIndex,
              coordinate[3].text == "]",
              fragment.declarations.filter({
                  $0.name == sampler[0].text
                    && $0.storage == .uniform
                    && $0.typeName == "sampler2D"
                    && $0.arraySize == nil
              }).count == 1,
              fragment.declarations.filter({
                  $0.name == coordinate[0].text
                    && $0.storage == .varying
                    && ["vec2", "float2"].contains($0.typeName)
                    && $0.arraySize == expectedCount
              }).count == 1 else { return nil }
        return (slot, coordinate[0].text)
    }

    private static func localDeclarations(
        _ ranges: [Range<Int>],
        tokens: [Token]
    ) -> Locals? {
        var weight: String?
        var accumulator: String?
        var sample: String?
        for range in ranges {
            let values = Array(tokens[range])
            if values.count == 4,
               values[0].text == "float",
               values[1].kind == .identifier,
               values[2].text == "=",
               number(values[3]) == 0 {
                guard weight == nil else { return nil }
                weight = values[1].text
            } else if values.count == 7,
                      ["vec3", "float3"].contains(values[0].text),
                      values[1].kind == .identifier,
                      values[2].text == "=",
                      ["CAST3", "vec3", "float3"].contains(values[3].text),
                      values[4].text == "(",
                      number(values[5]) == 0,
                      values[6].text == ")" {
                guard accumulator == nil else { return nil }
                accumulator = values[1].text
            } else if values.count == 2,
                      ["vec4", "float4"].contains(values[0].text),
                      values[1].kind == .identifier {
                guard sample == nil else { return nil }
                sample = values[1].text
            } else {
                return nil
            }
        }
        guard let weight, let accumulator, let sample,
              Set([weight, accumulator, sample]).count == 3 else { return nil }
        return .init(
            weight: weight,
            accumulator: accumulator,
            sample: sample
        )
    }

    private static func loopFact(
        at marker: Int,
        within container: Range<Int>,
        tokens: [Token]
    ) -> LoopFact? {
        guard marker + 1 < tokens.count,
              tokens[marker + 1].text == "(",
              let headerClose = matchingDelimiter(at: marker + 1, tokens: tokens),
              let parts = split(
                  (marker + 2)..<headerClose,
                  separator: ";",
                  tokens: tokens
              ),
              parts.count == 3 else { return nil }
        let initial = Array(tokens[parts[0]])
        guard initial.count == 4,
              initial[0].text == "int",
              initial[1].kind == .identifier,
              initial[2].text == "=",
              number(initial[3]) == 0 else { return nil }
        let index = initial[1].text
        let condition = Array(tokens[parts[1]])
        guard condition.count == 3,
              condition[0].text == index,
              condition[1].text == "<",
              let count = integer(condition[2]),
              (1 ... 16).contains(count) else { return nil }
        let increment = Array(tokens[parts[2]]).map(\.text)
        guard increment == [index, "++"] || increment == ["++", index],
              headerClose + 1 < tokens.count,
              tokens[headerClose + 1].text == "{",
              let bodyClose = matchingDelimiter(
                  at: headerClose + 1,
                  tokens: tokens
              ),
              container.contains(bodyClose) else { return nil }
        return .init(
            index: index,
            count: count,
            body: (headerClose + 2)..<bodyClose,
            closingBrace: bodyClose
        )
    }

    private static func sampleAssignment(
        _ range: Range<Int>,
        sample: String,
        loop: LoopFact,
        fragment: Unit,
        tokens: [Token]
    ) -> (slot: Int, coordinate: String)? {
        let values = Array(tokens[range])
        guard values.count >= 10,
              values[0].text == sample,
              values[1].text == "=",
              isTextureCall(values[2].text),
              values[3].text == "(",
              let callClose = matchingDelimiter(at: 3, tokens: values),
              callClose == values.count - 1,
              let arguments = split(
                  4..<callClose,
                  separator: ",",
                  tokens: values
              ),
              arguments.count == 2 else { return nil }
        let sampler = Array(values[arguments[0]])
        let coordinate = Array(values[arguments[1]])
        guard sampler.count == 1,
              let slot = textureSlot(sampler[0].text),
              coordinate.count == 4,
              coordinate[0].kind == .identifier,
              coordinate[1].text == "[",
              coordinate[2].text == loop.index,
              coordinate[3].text == "]",
              fragment.declarations.filter({
                  $0.name == sampler[0].text
                    && $0.storage == .uniform
                    && $0.typeName == "sampler2D"
                    && $0.arraySize == nil
              }).count == 1,
              fragment.declarations.filter({
                  $0.name == coordinate[0].text
                    && $0.storage == .varying
                    && ["vec2", "float2"].contains($0.typeName)
                    && $0.arraySize == loop.count
              }).count == 1 else { return nil }
        return (slot, coordinate[0].text)
    }

    private static func weightedAccumulation(
        _ range: Range<Int>,
        accumulator: String,
        sample: String,
        tokens: [Token]
    ) -> Bool {
        let values = Array(tokens[range]).map(\.text)
        return values.count == 9
            && values[0] == accumulator
            && values[1] == "+="
            && values[2] == sample
            && values[3] == "."
            && ["rgb", "xyz"].contains(values[4])
            && values[5] == "*"
            && values[6] == sample
            && values[7] == "."
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
            && values[0] == weight
            && values[1] == "+="
            && values[2] == sample
            && values[3] == "."
            && ["a", "w"].contains(values[4])
    }

    private static func opaqueOutput(
        _ range: Range<Int>,
        accumulator: String,
        weight: String,
        tokens: [Token]
    ) -> Bool {
        let values = Array(tokens[range])
        guard values.count == 17,
              values[0].text == "gl_FragColor",
              values[1].text == "=",
              ["vec4", "float4"].contains(values[2].text),
              values[3].text == "(",
              values[4].text == accumulator,
              values[5].text == ".",
              ["rgb", "xyz"].contains(values[6].text),
              values[7].text == "/",
              values[8].text == "max",
              values[9].text == "(",
              let epsilon = number(values[10]),
              epsilon > 0,
              values[11].text == ",",
              values[12].text == weight,
              values[13].text == ")",
              values[14].text == ",",
              number(values[15]) == 1,
              values[16].text == ")" else { return false }
        return true
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
              let closing = ["(": ")", "[": "]", "{": "}"][
                  tokens[opening].text
              ] else { return nil }
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

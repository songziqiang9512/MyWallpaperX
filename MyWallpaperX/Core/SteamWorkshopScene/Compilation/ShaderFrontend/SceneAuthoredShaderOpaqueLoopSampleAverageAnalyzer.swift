import Foundation

/// Proves one opaque RGB average produced by a symmetric, statically bounded
/// same-slot sample loop. Coordinates and uniform values remain authored data;
/// this fact only owns source provenance, exact work, normalization, and alpha.
nonisolated enum SceneAuthoredShaderOpaqueLoopSampleAverageAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
        let sampleCount: Int
    }

    private struct LoopFact {
        let index: String
        let radius: Int
        let body: Range<Int>
        let closingBrace: Int
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
                  ["out", "inout", "else", "while", "do", "switch",
                   "discard", "break", "continue", "return", "?"]
                    .contains($0.text)
              }) else { return nil }

        let ifMarkers = main.bodyRange.filter { tokens[$0].text == "if" }
        let loopMarkers = main.bodyRange.filter { tokens[$0].text == "for" }
        let outputs = tokens.indices.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard ifMarkers.count == 1,
              loopMarkers.count == 1,
              outputs.count == 1,
              let ifMarker = ifMarkers.first,
              let loopMarker = loopMarkers.first,
              let output = outputs.first,
              main.bodyRange.contains(output),
              let conditional = conditionalBody(
                  at: ifMarker,
                  fragment: fragment,
                  main: main
              ),
              conditional.body.contains(loopMarker),
              let loop = loopFact(
                  at: loopMarker,
                  within: conditional.body,
                  tokens: tokens
              ) else { return nil }

        let bodyStart = main.bodyRange.lowerBound + 1
        let bodyEnd = main.bodyRange.upperBound - 1
        guard let accumulatorEnd = firstSemicolon(
                  from: bodyStart,
                  before: ifMarker,
                  tokens: tokens
              ),
              accumulatorEnd + 1 == ifMarker,
              let accumulator = zeroVectorDeclaration(
                  bodyStart..<accumulatorEnd,
                  widths: ["vec3", "float3"],
                  constructors: ["CAST3", "vec3", "float3"],
                  tokens: tokens
              ),
              conditional.closingBrace + 1 == output,
              let outputEnd = firstSemicolon(
                  from: output,
                  before: bodyEnd,
                  tokens: tokens
              ),
              outputEnd + 1 == bodyEnd,
              opaqueOutput(
                  output..<outputEnd,
                  accumulator: accumulator,
                  tokens: tokens
              ) else { return nil }

        let conditionalStart = conditional.body.lowerBound
        guard let offsetEnd = firstSemicolon(
                  from: conditionalStart,
                  before: loopMarker,
                  tokens: tokens
              ),
              offsetEnd + 1 == loopMarker,
              let offset = zeroVectorDeclaration(
                  conditionalStart..<offsetEnd,
                  widths: ["vec2", "float2"],
                  constructors: ["CAST2", "vec2", "float2"],
                  tokens: tokens
              ),
              loop.closingBrace + 1 < conditional.body.upperBound,
              let normalizationEnd = firstSemicolon(
                  from: loop.closingBrace + 1,
                  before: conditional.body.upperBound,
                  tokens: tokens
              ),
              normalizationEnd + 1 == conditional.body.upperBound,
              normalization(
                  (loop.closingBrace + 1)..<normalizationEnd,
                  accumulator: accumulator,
                  radius: loop.radius,
                  tokens: tokens
              ) else { return nil }

        guard let offsetWriteEnd = firstSemicolon(
                  from: loop.body.lowerBound,
                  before: loop.body.upperBound,
                  tokens: tokens
              ),
              let axisAndScale = offsetAssignment(
                  loop.body.lowerBound..<offsetWriteEnd,
                  offset: offset,
                  loopIndex: loop.index,
                  fragment: fragment,
                  tokens: tokens
              ),
              let sampleEnd = firstSemicolon(
                  from: offsetWriteEnd + 1,
                  before: loop.body.upperBound,
                  tokens: tokens
              ),
              sampleEnd + 1 == loop.body.upperBound,
              let sample = sampleAccumulation(
                  (offsetWriteEnd + 1)..<sampleEnd,
                  accumulator: accumulator,
                  offset: offset,
                  fragment: fragment,
                  tokens: tokens
              ),
              wordCount(accumulator, in: main.bodyRange, tokens: tokens) == 4,
              wordCount(offset, in: main.bodyRange, tokens: tokens) == 3,
              wordCount(loop.index, in: main.bodyRange, tokens: tokens) == 4,
              wordCount(axisAndScale.scale, in: main.bodyRange, tokens: tokens) == 1,
              wordCount(sample.coordinate, in: main.bodyRange, tokens: tokens) == 1,
              main.bodyRange.filter({
                  ["texSample2D", "texture2D"].contains(tokens[$0].text)
              }).count == 1,
              tokens.indices.filter({
                  ["texSample2D", "texture2D"].contains(tokens[$0].text)
              }).count == 1 else { return nil }
        return .init(
            sourceSlot: sample.slot,
            sampleCount: loop.radius * 2 + 1
        )
    }

    private static func conditionalBody(
        at marker: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> (body: Range<Int>, closingBrace: Int)? {
        let tokens = fragment.tokens
        guard marker + 1 < tokens.count,
              tokens[marker + 1].text == "(",
              let conditionClose = matchingDelimiter(
                  at: marker + 1,
                  tokens: tokens
              ),
              conditionClose + 1 < tokens.count,
              tokens[conditionClose + 1].text == "{",
              let bodyClose = matchingDelimiter(
                  at: conditionClose + 1,
                  tokens: tokens
              ),
              bodyClose < main.bodyRange.upperBound,
              scalarGate(
                  (marker + 2)..<conditionClose,
                  fragment: fragment,
                  main: main
              ) else { return nil }
        return ((conditionClose + 2)..<bodyClose, bodyClose)
    }

    private static func scalarGate(
        _ range: Range<Int>,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        guard let clauses = split(range, separator: "&&", tokens: tokens),
              clauses.count == 2 else { return false }
        let names = clauses.compactMap { clause -> String? in
            let values = Array(tokens[clause])
            guard values.count == 3,
                  values[0].kind == .identifier,
                  values[1].text == ">",
                  let threshold = number(values[2]),
                  threshold > 0,
                  fragment.declarations.filter({
                      $0.name == values[0].text
                        && $0.storage == .uniform
                        && $0.typeName == "float"
                        && $0.arraySize == nil
                  }).count == 1,
                  wordCount(
                      values[0].text,
                      in: main.bodyRange,
                      tokens: tokens
                  ) == 1 else { return nil }
            return values[0].text
        }
        return names.count == 2 && Set(names).count == 2
    }

    private static func loopFact(
        at marker: Int,
        within container: Range<Int>,
        tokens: [Token]
    ) -> LoopFact? {
        guard marker + 1 < tokens.count,
              tokens[marker + 1].text == "(",
              let headerClose = matchingDelimiter(
                  at: marker + 1,
                  tokens: tokens
              ),
              let parts = split(
                  (marker + 2)..<headerClose,
                  separator: ";",
                  tokens: tokens
              ), parts.count == 3 else { return nil }
        let initial = Array(tokens[parts[0]])
        guard initial.count == 5,
              initial[0].text == "int",
              initial[1].kind == .identifier,
              initial[2].text == "=",
              initial[3].text == "-",
              let radius = integer(initial[4]),
              (1 ... 16).contains(radius) else { return nil }
        let index = initial[1].text
        let condition = Array(tokens[parts[1]]).map(\.text)
        let increment = Array(tokens[parts[2]]).map(\.text)
        guard condition == [index, "<=", String(radius)],
              increment == [index, "++"] || increment == ["++", index],
              headerClose + 1 < tokens.count,
              tokens[headerClose + 1].text == "{",
              let bodyClose = matchingDelimiter(
                  at: headerClose + 1,
                  tokens: tokens
              ),
              container.contains(bodyClose) else { return nil }
        return .init(
            index: index,
            radius: radius,
            body: (headerClose + 2)..<bodyClose,
            closingBrace: bodyClose
        )
    }

    private static func offsetAssignment(
        _ range: Range<Int>,
        offset: String,
        loopIndex: String,
        fragment: Unit,
        tokens: [Token]
    ) -> (axis: String, scale: String)? {
        let values = Array(tokens[range])
        guard values.count == 12,
              values[0].text == offset,
              values[1].text == ".",
              ["x", "y"].contains(values[2].text),
              values[3].text == "=",
              values[4].text == "float",
              values[5].text == "(",
              values[6].text == loopIndex,
              values[7].text == ")",
              values[8].text == "*",
              values[9].kind == .identifier,
              values[10].text == ".",
              values[11].text == values[2].text,
              fragment.declarations.filter({
                  $0.name == values[9].text
                    && $0.storage == .varying
                    && ["vec2", "float2"].contains($0.typeName)
                    && $0.arraySize == nil
              }).count == 1 else { return nil }
        return (values[2].text, values[9].text)
    }

    private static func sampleAccumulation(
        _ range: Range<Int>,
        accumulator: String,
        offset: String,
        fragment: Unit,
        tokens: [Token]
    ) -> (slot: Int, coordinate: String)? {
        let values = Array(tokens[range])
        guard values.count >= 12,
              values[0].text == accumulator,
              values[1].text == "+=",
              ["texSample2D", "texture2D"].contains(values[2].text),
              values[3].text == "(",
              let callClose = matchingDelimiter(at: 3, tokens: values),
              callClose == values.count - 3,
              values[callClose + 1].text == ".",
              ["rgb", "xyz"].contains(values[callClose + 2].text),
              let arguments = split(
                  4..<callClose,
                  separator: ",",
                  tokens: values
              ), arguments.count == 2 else { return nil }
        let sampler = Array(values[arguments[0]])
        let coordinate = Array(values[arguments[1]])
        guard sampler.count == 1,
              let slot = textureSlot(sampler[0].text),
              coordinate.count == 3,
              coordinate[0].kind == .identifier,
              coordinate[1].text == "+",
              coordinate[2].text == offset,
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
                    && $0.arraySize == nil
              }).count == 1 else { return nil }
        return (slot, coordinate[0].text)
    }

    private static func normalization(
        _ range: Range<Int>,
        accumulator: String,
        radius: Int,
        tokens: [Token]
    ) -> Bool {
        let values = Array(tokens[range])
        guard values.count == 10,
              values[0].text == accumulator,
              values[1].text == "/=",
              values[2].text == "float",
              values[3].text == "(",
              integer(values[4]) == radius,
              values[5].text == "+",
              integer(values[6]) == radius,
              values[7].text == ")",
              values[8].text == "+",
              number(values[9]) == 1 else { return false }
        return true
    }

    private static func opaqueOutput(
        _ range: Range<Int>,
        accumulator: String,
        tokens: [Token]
    ) -> Bool {
        let values = Array(tokens[range])
        guard values.count == 8,
              values[0].text == "gl_FragColor",
              values[1].text == "=",
              ["vec4", "float4"].contains(values[2].text),
              values[3].text == "(",
              values[4].text == accumulator,
              values[5].text == ",",
              number(values[6]) == 1,
              values[7].text == ")" else { return false }
        return true
    }

    private static func zeroVectorDeclaration(
        _ range: Range<Int>,
        widths: Set<String>,
        constructors: Set<String>,
        tokens: [Token]
    ) -> String? {
        let values = Array(tokens[range])
        guard values.count == 7,
              widths.contains(values[0].text),
              values[1].kind == .identifier,
              values[2].text == "=",
              constructors.contains(values[3].text),
              values[4].text == "(",
              number(values[5]) == 0,
              values[6].text == ")" else { return nil }
        return values[1].text
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

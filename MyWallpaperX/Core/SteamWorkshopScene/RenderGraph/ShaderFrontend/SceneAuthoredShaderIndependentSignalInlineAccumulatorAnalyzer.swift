import Foundation

/// Proves an independent RGBA signal accumulated by one statically bounded
/// loop directly inside `main`. The proof owns only color provenance and loop
/// work; the authored compiler still owns coordinates, uniforms, and math.
/// Effect, material, path, sample, and shader identities never participate.
nonisolated enum SceneAuthoredShaderIndependentSignalInlineAccumulatorAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private struct LoopFact {
        let index: String
        let denominator: String
        let iterations: Int
        let marker: Int
        let body: Range<Int>
    }

    private struct Fact {
        let slot: Int
        let work: Int
    }

    private enum OutputConstraint {
        case explicitAlphaClamp
        case rgba8UnormAttachment
    }

    static func analyze(fragmentSource source: String) -> SceneShaderColorTransfer? {
        sourceSlot(fragmentSource: source).map {
            .independentAlphaSignalPreserving(textureSlot: $0)
        }
    }

    static func sourceSlot(fragmentSource source: String) -> Int? {
        parsed(source)?.slot
    }

    static func staticLoopWork(fragmentSource source: String) -> Int? {
        parsed(source)?.work
    }

    static func rgba8UnormAttachmentSourceSlot(
        fragmentSource source: String
    ) -> Int? {
        parsed(source, outputConstraint: .rgba8UnormAttachment)?.slot
    }

    static func rgba8UnormAttachmentLoopWork(
        fragmentSource source: String
    ) -> Int? {
        parsed(source, outputConstraint: .rgba8UnormAttachment)?.work
    }

    static func analyze(_ fragment: Unit) -> Int? {
        analysis(fragment)?.slot
    }

    private static func parsed(
        _ source: String,
        outputConstraint: OutputConstraint = .explicitAlphaClamp
    ) -> Fact? {
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
        return analysis(fragment, outputConstraint: outputConstraint)
    }

    private static func analysis(
        _ fragment: Unit,
        outputConstraint: OutputConstraint = .explicitAlphaClamp
    ) -> Fact? {
        let tokens = fragment.tokens
        let mains = fragment.functions.filter { $0.name == "main" }
        guard fragment.stage == .fragment,
              mains.count == 1,
              let main = mains.first,
              main.parameterRange.isEmpty,
              !tokens.contains(where: { ["out", "inout"].contains($0.text) })
        else { return nil }

        let forbidden: Set<String> = [
            "if", "else", "switch", "case", "while", "do", "discard",
            "break", "continue", "return",
        ]
        guard !main.bodyRange.contains(where: { forbidden.contains(tokens[$0].text) }),
              !main.bodyRange.contains(where: { tokens[$0].text == "?" })
        else { return nil }

        let loopMarkers = main.bodyRange.filter { tokens[$0].text == "for" }
        guard loopMarkers.count == 1,
              tokens.indices.filter({ tokens[$0].text == "for" }) == loopMarkers,
              !tokens.contains(where: { ["while", "do"].contains($0.text) }),
              let loop = loopFact(
                  at: loopMarkers[0],
                  function: main,
                  tokens: tokens
              ) else { return nil }

        let vectorDefinitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound
                && index + 1 < tokens.count
                && tokens[index].kind == .identifier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard vectorDefinitions.count == 2,
              let accumulator = vectorDefinitions.first(where: {
                  guard let value = SceneAuthoredShaderColorTransferAnalyzer
                      .assignmentExpression(
                          after: $0,
                          in: tokens,
                          body: main.bodyRange
                      ) else { return false }
                  return zeroVector(Array(value))
              }),
              let sample = vectorDefinitions.first(where: {
                  guard let value = SceneAuthoredShaderColorTransferAnalyzer
                      .assignmentExpression(
                          after: $0,
                          in: tokens,
                          body: main.bodyRange
                      ) else { return false }
                  return SceneAuthoredShaderColorTransferAnalyzer
                      .directTextureSampleSlot(value) != nil
              }),
              accumulator != sample,
              accumulator < loop.marker,
              loop.body.contains(sample),
              let sampleValue = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: sample,
                      in: tokens,
                      body: main.bodyRange
                  ),
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                  .directTextureSampleSlot(sampleValue),
              fragment.declarations.filter({
                  $0.storage == .uniform
                    && $0.name == "g_Texture\(slot)"
                    && $0.typeName == "sampler2D"
                    && $0.arraySize == nil
              }).count == 1 else { return nil }

        let sampleCalls = main.bodyRange.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }
        guard sampleCalls.count == 1,
              wordCount(tokens[sample].text, in: main.bodyRange, tokens: tokens) == 2,
              let accumulation = uniqueRootWrite(
                  named: tokens[accumulator].text,
                  operation: "+=",
                  in: loop.body,
                  tokens: tokens
              ),
              let update = expression(
                  after: accumulation,
                  operation: "+=",
                  body: loop.body,
                  tokens: tokens
              ),
              nonnegativeWeightedSample(
                  Array(update),
                  sample: tokens[sample].text,
                  index: loop.index,
                  denominator: loop.denominator
              ) else { return nil }

        guard let rgbWrite = uniqueMemberWrite(
            named: tokens[accumulator].text,
            member: ["rgb", "xyz"],
            operation: "*=",
            in: main.bodyRange,
            tokens: tokens
        ), rgbWrite > loop.body.upperBound,
           let rgbTint = expression(
               after: rgbWrite + 2,
               operation: "*=",
               body: main.bodyRange,
               tokens: tokens
           ), rgbTint.count == 1,
           let tintName = rgbTint.first?.text,
           fragment.declarations.filter({
               $0.storage == .uniform
                 && $0.name == tintName
                 && ["vec3", "float3"].contains($0.typeName)
                 && $0.arraySize == nil
           }).count == 1 else { return nil }

        let outputs = main.bodyRange.filter { tokens[$0].text == "gl_FragColor" }
        guard outputs.count == 1,
              let output = outputs.first,
              output > rgbWrite,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: output,
                      in: tokens,
                      body: main.bodyRange
                  ),
              writeSignatures(
                  named: tokens[accumulator].text,
                  in: main.bodyRange,
                  tokens: tokens
              ) == ["root:=", "root:+=", "rgb:*="] else { return nil }
        let outputIsProven: Bool = switch outputConstraint {
        case .explicitAlphaClamp:
            outputFact(
                Array(outputExpression),
                accumulator: tokens[accumulator].text,
                before: output,
                fragment: fragment,
                main: main
            )
        case .rgba8UnormAttachment:
            rgba8UnormOutputFact(
                Array(outputExpression),
                accumulator: tokens[accumulator].text,
                before: output,
                fragment: fragment,
                main: main
            )
        }
        let expectedAccumulatorUses = switch outputConstraint {
        case .explicitAlphaClamp: 5
        case .rgba8UnormAttachment: 4
        }
        guard outputIsProven,
              wordCount(
                  tokens[accumulator].text,
                  in: main.bodyRange,
                  tokens: tokens
              ) == expectedAccumulatorUses else { return nil }
        return .init(slot: slot, work: loop.iterations)
    }

    private static func loopFact(
        at marker: Int,
        function: Unit.Function,
        tokens: [Token]
    ) -> LoopFact? {
        guard marker + 1 < tokens.count,
              tokens[marker + 1].text == "(",
              let close = matchingDelimiter(at: marker + 1, tokens: tokens),
              let parts = split(
                  (marker + 2)..<close,
                  separator: ";",
                  tokens: tokens
              ), parts.count == 3 else { return nil }
        let initial = texts(parts[0], tokens: tokens)
        guard initial.count == 4,
              initial[0] == "int",
              tokens[parts[0].lowerBound + 1].kind == .identifier,
              initial[2] == "=",
              numeric(tokens[parts[0].lowerBound + 3]) == 0 else { return nil }
        let index = initial[1]
        let condition = texts(parts[1], tokens: tokens)
        let increment = texts(parts[2], tokens: tokens)
        guard condition.count == 3,
              condition[0] == index,
              condition[1] == "<",
              increment == ["++", index] || increment == [index, "++"],
              close + 1 < tokens.count,
              tokens[close + 1].text == "{",
              let bodyClose = matchingDelimiter(at: close + 1, tokens: tokens),
              bodyClose < function.bodyRange.upperBound,
              !isWritten(
                  index,
                  in: (close + 2)..<bodyClose,
                  tokens: tokens
              ),
              let iterations = constantInt(
                  condition[2],
                  before: marker,
                  function: function,
                  tokens: tokens
              ), (2 ... 64).contains(iterations),
              wordCount(
                  index,
                  in: function.bodyRange,
                  tokens: tokens
              ) == 4,
              tokens[parts[1].lowerBound + 2].kind != .identifier
                || wordCount(
                    condition[2],
                    in: function.bodyRange,
                    tokens: tokens
                ) == 3,
              let denominator = denominator(
                  for: condition[2],
                  before: marker,
                  function: function,
                  tokens: tokens
              ) else { return nil }
        return .init(
            index: index,
            denominator: denominator,
            iterations: iterations,
            marker: marker,
            body: (close + 2)..<bodyClose
        )
    }

    private static func isWritten(
        _ name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        let assignments: Set<String> = [
            "=", "+=", "-=", "*=", "/=", "%=", "++", "--",
        ]
        for index in range where tokens[index].text == name {
            if index + 1 < range.upperBound,
               assignments.contains(tokens[index + 1].text) {
                return true
            }
            if index > range.lowerBound,
               ["++", "--"].contains(tokens[index - 1].text) {
                return true
            }
        }
        return false
    }

    private static func constantInt(
        _ value: String,
        before boundary: Int,
        function: Unit.Function,
        tokens: [Token]
    ) -> Int? {
        if let literal = Int(value) { return literal }
        let matches = function.bodyRange.filter { index in
            index + 5 < boundary
                && texts(index..<(index + 6), tokens: tokens)
                    == ["const", "int", value, "=", tokens[index + 4].text, ";"]
                && tokens[index + 4].kind == .number
        }
        guard matches.count == 1,
              let marker = matches.first,
              let number = numeric(tokens[marker + 4]),
              number.rounded(.towardZero) == number else { return nil }
        return Int(exactly: number)
    }

    private static func denominator(
        for bound: String,
        before boundary: Int,
        function: Unit.Function,
        tokens: [Token]
    ) -> String? {
        let matches = function.bodyRange.compactMap { index -> String? in
            guard index + 7 < boundary,
                  texts(index..<(index + 8), tokens: tokens)
                    == [
                        "const", "float", tokens[index + 2].text, "=",
                        bound, "-", "1", ";",
                    ], tokens[index + 2].kind == .identifier else { return nil }
            return tokens[index + 2].text
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func outputFact(
        _ expression: [Token],
        accumulator: String,
        before boundary: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        guard let arguments = constructorArguments(expression),
              arguments.count == 2,
              let rgbFactors = carrierFactors(
                  arguments[0],
                  carrier: accumulator,
                  members: ["rgb", "xyz"]
              ),
              let alphaValue = clampedAlpha(arguments[1]),
              let alphaFactors = carrierFactors(
                  alphaValue,
                  carrier: accumulator,
                  members: ["a", "w"]
              ), rgbFactors.map(texts) == alphaFactors.map(texts),
              !rgbFactors.isEmpty else { return false }
        return rgbFactors.allSatisfy {
            safeScalarFactor(
                $0,
                before: boundary,
                fragment: fragment,
                main: main
            )
        }
    }

    /// The authored RGBA8 target supplies the terminal [0, 1] clamp. Before
    /// that typed storage boundary, every output channel must still be the
    /// same accumulated signal multiplied only by bounded scalar facts.
    private static func rgba8UnormOutputFact(
        _ expression: [Token],
        accumulator: String,
        before boundary: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let factors = productFactors(unwrapped(expression))
        let carrier = factors.filter { texts(unwrapped($0)) == [accumulator] }
        guard carrier.count == 1 else { return false }
        return factors.filter { texts(unwrapped($0)) != [accumulator] }
            .allSatisfy {
                safeScalarFactor(
                    unwrapped($0),
                    before: boundary,
                    fragment: fragment,
                    main: main
                )
            }
    }

    private static func safeScalarFactor(
        _ value: [Token],
        before boundary: Int,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let factor = unwrapped(value)
        guard factor.count == 1, let token = factor.first else { return false }
        if let number = numeric(token) { return number >= 0 }
        guard token.kind == .identifier else { return false }
        if fragment.declarations.contains(where: {
            $0.storage == .uniform
                && $0.name == token.text
                && $0.typeName == "float"
                && $0.arraySize == nil
        }) { return true }
        let tokens = fragment.tokens
        let definitions = main.bodyRange.filter { index in
            index + 3 < boundary
                && texts(index..<(index + 3), tokens: tokens)
                    == ["const", "float", token.text]
                && tokens[index + 3].text == "="
        }
        guard definitions.count == 1, let definition = definitions.first,
              let initializer = expression(
                  after: definition + 2,
                  operation: "=",
                  body: main.bodyRange,
                  tokens: tokens
              ) else { return false }
        return positiveNumericExpression(Array(initializer))
    }

    private static func positiveNumericExpression(_ value: [Token]) -> Bool {
        let allowed: Set<String> = ["(", ")", "+", "*", "/"]
        var sawNumber = false
        for token in value {
            if let number = numeric(token) {
                guard number > 0 else { return false }
                sawNumber = true
            } else if !allowed.contains(token.text) {
                return false
            }
        }
        return sawNumber
    }

    private static func constructorArguments(_ value: [Token]) -> [[Token]]? {
        let expression = unwrapped(value)
        guard expression.count >= 5,
              ["vec4", "float4"].contains(expression[0].text),
              expression[1].text == "(",
              matchingDelimiter(at: 1, tokens: expression) == expression.count - 1,
              let parts = split(2..<(expression.count - 1), separator: ",", tokens: expression),
              parts.count == 2 else { return nil }
        return parts.map { Array(expression[$0]) }
    }

    private static func clampedAlpha(_ value: [Token]) -> [Token]? {
        let expression = unwrapped(value)
        if expression.count >= 4,
           expression[0].text == "saturate",
           expression[1].text == "(",
           matchingDelimiter(at: 1, tokens: expression) == expression.count - 1 {
            return Array(expression[2..<(expression.count - 1)])
        }
        guard expression.count >= 8,
              expression[0].text == "clamp",
              expression[1].text == "(",
              matchingDelimiter(at: 1, tokens: expression) == expression.count - 1,
              let parts = split(2..<(expression.count - 1), separator: ",", tokens: expression),
              parts.count == 3,
              numericTokens(Array(expression[parts[1]])) == 0,
              numericTokens(Array(expression[parts[2]])) == 1 else { return nil }
        return Array(expression[parts[0]])
    }

    private static func carrierFactors(
        _ value: [Token],
        carrier: String,
        members: Set<String>
    ) -> [[Token]]? {
        let factors = productFactors(unwrapped(value))
        let carrierFactors = factors.filter {
            let fact = unwrapped($0)
            return fact.count == 3
                && fact[0].text == carrier
                && fact[1].text == "."
                && members.contains(fact[2].text)
        }
        guard carrierFactors.count == 1 else { return nil }
        return factors.filter {
            let fact = unwrapped($0)
            return !(fact.count == 3
                && fact[0].text == carrier
                && fact[1].text == "."
                && members.contains(fact[2].text))
        }.map(unwrapped)
    }

    private static func nonnegativeWeightedSample(
        _ value: [Token],
        sample: String,
        index: String,
        denominator: String
    ) -> Bool {
        let factors = productFactors(unwrapped(value))
        guard factors.count == 2 else { return false }
        let sampleFactors = factors.filter { texts(unwrapped($0)) == [sample] }
        let weights = factors.filter { texts(unwrapped($0)) != [sample] }
        return sampleFactors.count == 1
            && weights.count == 1
            && texts(unwrapped(weights[0])) == [index, "/", denominator]
    }

    private static func productFactors(_ value: [Token]) -> [[Token]] {
        guard let ranges = split(0..<value.count, separator: "*", tokens: value) else {
            return [value]
        }
        return ranges.map { Array(value[$0]) }
    }

    private static func zeroVector(_ value: [Token]) -> Bool {
        let expression = unwrapped(value)
        guard expression.count == 4,
              ["CAST4", "vec4", "float4"].contains(expression[0].text),
              expression[1].text == "(", expression[3].text == ")" else {
            return false
        }
        return numeric(expression[2]) == 0
    }

    private static func uniqueRootWrite(
        named name: String,
        operation: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int? {
        let matches = range.filter { index in
            index + 1 < tokens.count
                && tokens[index].text == name
                && tokens[index + 1].text == operation
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func uniqueMemberWrite(
        named name: String,
        member: Set<String>,
        operation: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int? {
        let matches = range.filter { index in
            index + 3 < tokens.count
                && tokens[index].text == name
                && tokens[index + 1].text == "."
                && member.contains(tokens[index + 2].text)
                && tokens[index + 3].text == operation
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func expression(
        after assignment: Int,
        operation: String,
        body: Range<Int>,
        tokens: [Token]
    ) -> ArraySlice<Token>? {
        let start = assignment + 2
        guard assignment + 1 < tokens.count,
              tokens[assignment + 1].text == operation,
              body.contains(start) else { return nil }
        var stack: [String] = []
        let closing = [")": "(", "]": "[", "}": "{"]
        for index in start..<body.upperBound {
            let text = tokens[index].text
            if ["(", "[", "{"].contains(text) {
                stack.append(text)
            } else if let expected = closing[text] {
                guard stack.last == expected else { return nil }
                stack.removeLast()
            } else if text == ";", stack.isEmpty {
                return start < index ? tokens[start..<index] : nil
            }
        }
        return nil
    }

    private static func writeSignatures(
        named name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> [String] {
        range.compactMap { index in
            guard tokens[index].text == name, index + 1 < tokens.count else {
                return nil
            }
            if ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 1].text) {
                return "root:\(tokens[index + 1].text)"
            }
            guard index + 3 < tokens.count,
                  tokens[index + 1].text == ".",
                  ["=", "+=", "-=", "*=", "/="].contains(tokens[index + 3].text)
            else { return nil }
            return "\(tokens[index + 2].text):\(tokens[index + 3].text)"
        }
    }

    private static func split(
        _ range: Range<Int>,
        separator: String,
        tokens: [Token]
    ) -> [Range<Int>]? {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var stack: [String] = []
        let closing = [")": "(", "]": "[", "}": "{"]
        for index in range {
            let text = tokens[index].text
            if ["(", "[", "{"].contains(text) {
                stack.append(text)
            } else if let expected = closing[text] {
                guard stack.last == expected else { return nil }
                stack.removeLast()
            } else if text == separator, stack.isEmpty {
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            }
        }
        guard stack.isEmpty, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
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
            if tokens[index].text == closing {
                depth -= 1
                if depth == 0 { return index }
                if depth < 0 { return nil }
            }
        }
        return nil
    }

    private static func unwrapped(_ value: [Token]) -> [Token] {
        var result = value
        while result.count >= 2,
              result.first?.text == "(",
              matchingDelimiter(at: 0, tokens: result) == result.count - 1 {
            result = Array(result.dropFirst().dropLast())
        }
        return result
    }

    private static func wordCount(
        _ name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int {
        range.filter { tokens[$0].text == name }.count
    }

    private static func texts(_ value: [Token]) -> [String] { value.map(\.text) }

    private static func texts(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> [String] {
        tokens[range].map(\.text)
    }

    private static func numeric(_ token: Token) -> Double? {
        guard token.kind == .number else { return nil }
        let normalized = token.text.last.map { "fF".contains($0) } == true
            ? String(token.text.dropLast()) : token.text
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private static func numericTokens(_ value: [Token]) -> Double? {
        let expression = unwrapped(value)
        return expression.count == 1 ? numeric(expression[0]) : nil
    }
}

import Foundation

/// Proves one source-derived independent-signal graph whose only whole-vector
/// texture sample is accumulated with a statically bounded, nonnegative affine
/// weight. The root combines only results from that helper, applies one RGB
/// tint, then uses the same scalar scale for RGB and alpha while clamping alpha.
/// No effect, material, path, shader hash, or authored identifier participates
/// in the decision.
nonisolated enum SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private struct SampleCall {
        let index: Int
        let slot: Int
        let closing: Int
    }

    private struct LoopFact {
        let indexName: String
        let boundName: String
        let iterations: Int
        let body: Range<Int>
    }

    private struct HelperFact {
        let name: String
        let textureSlot: Int
        let loopIterations: Int
    }

    /// Returns the compositor-facing transfer so the existing independent-alpha
    /// owner can consume this proof without inventing another color taxonomy.
    static func analyze(
        fragmentSource source: String
    ) -> SceneShaderColorTransfer? {
        sourceSlot(fragmentSource: source).map {
            .independentAlphaSignalPreserving(textureSlot: $0)
        }
    }

    static func sourceSlot(fragmentSource source: String) -> Int? {
        analysis(fragmentSource: source)?.slot
    }

    static func staticLoopWork(fragmentSource source: String) -> Int? {
        analysis(fragmentSource: source)?.work
    }

    private static func analysis(
        fragmentSource source: String
    ) -> (slot: Int, work: Int)? {
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
        return analysis(fragment)
    }

    /// Internal slot proof intended for direct use by
    /// `SceneAuthoredShaderIndependentAlphaAnalyzer` during integration.
    static func analyze(_ fragment: Unit) -> Int? {
        analysis(fragment)?.slot
    }

    private static func analysis(_ fragment: Unit) -> (slot: Int, work: Int)? {
        let tokens = fragment.tokens
        guard fragment.stage == .fragment,
              !tokens.contains(where: { ["out", "inout"].contains($0.text) }),
              Set(fragment.functions.map(\.name)).count == fragment.functions.count,
              fragment.functions.count == 2,
              let main = uniqueFunction(named: "main", fragment: fragment),
              main.parameterRange.isEmpty,
              let helper = fragment.functions.first(where: { $0.name != "main" }),
              let samples = sampleCalls(tokens: tokens),
              samples.count == 1,
              let sample = samples.first,
              sample.closing + 1 >= tokens.count
                || tokens[sample.closing + 1].text != ".",
              helper.bodyRange.contains(sample.index),
              let helperFact = helperFact(
                  helper,
                  sample: sample,
                  fragment: fragment
              ),
              let helperCallCount = mainFact(
                  main,
                  helper: helperFact,
                  fragment: fragment
              ), helperFact.loopIterations * helperCallCount <= 256 else {
            return nil
        }
        return (
            helperFact.textureSlot,
            helperFact.loopIterations * helperCallCount
        )
    }

    private static func helperFact(
        _ function: Unit.Function,
        sample: SampleCall,
        fragment: Unit
    ) -> HelperFact? {
        let tokens = fragment.tokens
        let definitions = vectorDefinitions(in: function.bodyRange, tokens: tokens)
        guard ["vec4", "float4"].contains(function.returnType),
              let parameters = parameterNames(function, tokens: tokens),
              parameters.count == 2,
              let sampler = fragment.declarations.first(where: {
                  $0.storage == .uniform
                    && $0.name == "g_Texture\(sample.slot)"
                    && $0.typeName == "sampler2D"
                    && $0.arraySize == nil
              }), sampler.name == "g_Texture\(sample.slot)",
              let loops = loopIndices(in: function.bodyRange, tokens: tokens),
              loops.count == 1,
              let loop = loopFact(
                  at: loops[0],
                  function: function,
                  tokens: tokens
              ),
              loop.body.contains(sample.index),
              let denominator = denominatorFact(
                  bound: loop.boundName,
                  before: loops[0],
                  function: function,
                  tokens: tokens
              ),
              definitions.count == 2,
              let accumulator = definitions.first(where: {
                  zeroVector(expression(after: $0, tokens: tokens, body: function.bodyRange))
              }),
              let sampled = definitions.first(where: {
                  directSampleSlot(
                      expression(after: $0, tokens: tokens, body: function.bodyRange)
                  ) == sample.slot
              }), accumulator != sampled,
              loop.body.contains(sampled), sampled < sample.index,
              let accumulation = uniqueAccumulatorWrite(
                  named: tokens[accumulator].text,
                  in: loop.body,
                  tokens: tokens
              ),
              accumulation > sampled,
              let weighted = expression(
                  after: accumulation,
                  operators: ["+="],
                  tokens: tokens,
                  body: loop.body
              ),
              nonnegativeWeightedSample(
                  Array(weighted),
                  sample: tokens[sampled].text,
                  index: loop.indexName,
                  denominator: denominator
              ),
              exactReturn(
                  tokens[accumulator].text,
                  function: function,
                  tokens: tokens
              ),
              wordCount(
                  tokens[accumulator].text,
                  in: function.bodyRange,
                  tokens: tokens
              ) == 3,
              wordCount(
                  tokens[sampled].text,
                  in: function.bodyRange,
                  tokens: tokens
              ) == 2,
              wordCount(
                  loop.indexName,
                  in: function.bodyRange,
                  tokens: tokens
              ) == 4,
              wordCount(
                  loop.boundName,
                  in: function.bodyRange,
                  tokens: tokens
              ) == 3,
              safeDenominatorUses(
                  denominator,
                  in: function.bodyRange,
                  tokens: tokens
              ) else { return nil }
        return .init(
            name: function.name,
            textureSlot: sample.slot,
            loopIterations: loop.iterations
        )
    }

    private static func mainFact(
        _ main: Unit.Function,
        helper: HelperFact,
        fragment: Unit
    ) -> Int? {
        let tokens = fragment.tokens
        let definitions = vectorDefinitions(in: main.bodyRange, tokens: tokens)
        let outputs = main.bodyRange.filter {
            tokens[$0].text == "gl_FragColor"
        }
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "break", "continue", "return",
        ]
        guard !main.bodyRange.contains(where: { forbidden.contains(tokens[$0].text) }),
              definitions.count == 1,
              let accumulator = definitions.first,
              zeroVector(expression(after: accumulator, tokens: tokens, body: main.bodyRange)),
              let helperWrites = helperAccumulations(
                  accumulator: tokens[accumulator].text,
                  helper: helper.name,
                  body: main.bodyRange,
                  tokens: tokens
              ), (1 ... 8).contains(helperWrites.count),
              helperWrites.allSatisfy({ $0 > accumulator }),
              wordCount(helper.name, in: main.bodyRange, tokens: tokens)
                == helperWrites.count,
              let rgbWrite = uniqueMemberWrite(
                  tokens[accumulator].text,
                  members: ["rgb", "xyz"],
                  operation: "*=",
                  in: main.bodyRange,
                  tokens: tokens
              ), helperWrites.allSatisfy({ $0 < rgbWrite }),
              let tintExpression = expression(
                  after: rgbWrite + 2,
                  operators: ["*="],
                  tokens: tokens,
                  body: main.bodyRange
              ), safeRGBTint(
                  Array(tintExpression),
                  fragment: fragment
              ),
              outputs.count == 1,
              let output = outputs.first, rgbWrite < output,
              output + 1 < tokens.count, tokens[output + 1].text == "=",
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output,
                  tokens: tokens,
                  body: main.bodyRange
              ), let outputExpression = expression(
                  after: output,
                  tokens: tokens,
                  body: main.bodyRange
              ), outputExpression.endIndex == main.bodyRange.upperBound - 2,
              terminalOutput(
                  Array(outputExpression),
                  accumulator: tokens[accumulator].text,
                  before: output,
                  main: main,
                  fragment: fragment
              ),
              wordCount(
                  tokens[accumulator].text,
                  in: main.bodyRange,
                  tokens: tokens
              ) == helperWrites.count + 4 else { return nil }
        return helperWrites.count
    }

    private static func loopFact(
        at marker: Int,
        function: Unit.Function,
        tokens: [Token]
    ) -> LoopFact? {
        guard marker + 1 < tokens.count, tokens[marker + 1].text == "(",
              let close = matchingDelimiter(at: marker + 1, tokens: tokens),
              let parts = split(
                  (marker + 2)..<close,
                  separator: ";",
                  tokens: tokens
              ), parts.count == 3,
              texts(parts[0], tokens: tokens).count == 4,
              tokens[parts[0].lowerBound].text == "int",
              tokens[parts[0].lowerBound + 1].kind == .identifier,
              tokens[parts[0].lowerBound + 2].text == "=",
              numeric(tokens[parts[0].lowerBound + 3]) == 0 else { return nil }
        let index = tokens[parts[0].lowerBound + 1].text
        let condition = texts(parts[1], tokens: tokens)
        let increment = texts(parts[2], tokens: tokens)
        guard condition.count == 3, condition[0] == index,
              condition[1] == "<", isIdentifier(condition[2]),
              increment == ["++", index] || increment == [index, "++"],
              close + 1 < tokens.count, tokens[close + 1].text == "{",
              let bodyClose = matchingDelimiter(at: close + 1, tokens: tokens),
              bodyClose < function.bodyRange.upperBound,
              let iterations = rootConstantInt(
                  named: condition[2],
                  before: marker,
                  function: function,
                  tokens: tokens
              ), (2 ... 64).contains(iterations) else { return nil }
        return .init(
            indexName: index,
            boundName: condition[2],
            iterations: iterations,
            body: (close + 2)..<bodyClose
        )
    }

    private static func rootConstantInt(
        named name: String,
        before boundary: Int,
        function: Unit.Function,
        tokens: [Token]
    ) -> Int? {
        let matches = function.bodyRange.filter { index in
            index + 5 < boundary
                && texts(index..<(index + 6), tokens: tokens)
                    == ["const", "int", name, "=", tokens[index + 4].text, ";"]
                && tokens[index + 4].kind == .number
        }
        guard matches.count == 1, let index = matches.first,
              let value = numeric(tokens[index + 4]), value.rounded(.towardZero) == value
        else { return nil }
        return Int(exactly: value)
    }

    private static func denominatorFact(
        bound: String,
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

    private static func nonnegativeWeightedSample(
        _ expression: [Token],
        sample: String,
        index: String,
        denominator: String
    ) -> Bool {
        let factors = flattenedProduct(expression)
        guard factors.count == 2 else { return false }
        let sampleFactors = factors.filter { texts($0) == [sample] }
        let weights = factors.filter { texts($0) != [sample] }
        guard sampleFactors.count == 1, weights.count == 1 else { return false }
        return texts(unwrapped(weights[0])) == [index, "/", denominator]
    }

    private static func terminalOutput(
        _ expression: [Token],
        accumulator: String,
        before boundary: Int,
        main: Unit.Function,
        fragment: Unit
    ) -> Bool {
        guard let constructor = call(unwrapped(expression)),
              ["vec4", "float4"].contains(constructor.name),
              constructor.arguments.count == 2,
              let rgbScale = scaledMember(
                  constructor.arguments[0],
                  base: accumulator,
                  members: ["rgb", "xyz"],
                  before: boundary,
                  main: main,
                  fragment: fragment
              ), let alphaExpression = clampedAlpha(constructor.arguments[1]),
              let alphaScale = scaledMember(
                  alphaExpression,
                  base: accumulator,
                  members: ["a", "w"],
                  before: boundary,
                  main: main,
                  fragment: fragment
              ) else { return false }
        return rgbScale == alphaScale && !rgbScale.isEmpty
    }

    private static func clampedAlpha(_ expression: [Token]) -> [Token]? {
        guard let value = call(unwrapped(expression)) else { return nil }
        if value.name == "saturate", value.arguments.count == 1 {
            return value.arguments[0]
        }
        guard value.name == "clamp", value.arguments.count == 3,
              value.arguments[1].count == 1,
              value.arguments[2].count == 1,
              value.arguments[1].first.flatMap(numeric) == 0,
              value.arguments[2].first.flatMap(numeric) == 1 else { return nil }
        return value.arguments[0]
    }

    private static func scaledMember(
        _ expression: [Token],
        base: String,
        members: Set<String>,
        before boundary: Int,
        main: Unit.Function,
        fragment: Unit
    ) -> [String]? {
        let factors = flattenedProduct(expression)
        let memberFactors = factors.filter {
            let value = texts(unwrapped($0))
            return value.count == 3 && value[0] == base && value[1] == "."
                && members.contains(value[2])
        }
        guard memberFactors.count == 1 else { return nil }
        let scalarFactors = factors.filter { candidate in
            !memberFactors.contains(where: { texts($0) == texts(candidate) })
        }
        guard !scalarFactors.isEmpty,
              scalarFactors.allSatisfy({
                  safeScalarFactor(
                      unwrapped($0),
                      before: boundary,
                      main: main,
                      fragment: fragment
                  )
              }) else { return nil }
        return scalarFactors.map { texts(unwrapped($0)).joined(separator: " ") }.sorted()
    }

    private static func safeScalarFactor(
        _ value: [Token],
        before boundary: Int,
        main: Unit.Function,
        fragment: Unit
    ) -> Bool {
        guard value.count == 1, let token = value.first else { return false }
        if let number = numeric(token) { return number.isFinite && number >= 0 }
        guard token.kind == .identifier else { return false }
        if fragment.declarations.contains(where: {
            $0.storage == .uniform && $0.name == token.text
                && $0.typeName == "float" && $0.arraySize == nil
        }) { return true }
        let tokens = fragment.tokens
        let definitions = main.bodyRange.filter { index in
            index + 3 < boundary
                && texts(index..<(index + 3), tokens: tokens)
                    == ["const", "float", token.text]
                && tokens[index + 3].text == "="
        }
        guard definitions.count == 1, let definition = definitions.first,
              let expression = expression(
                  after: definition + 2,
                  tokens: tokens,
                  body: main.bodyRange
              ) else { return false }
        return positiveNumericExpression(Array(expression))
    }

    private static func positiveNumericExpression(_ expression: [Token]) -> Bool {
        let allowed: Set<String> = ["(", ")", "+", "*", "/"]
        var sawNumber = false
        for token in expression {
            if let number = numeric(token) {
                guard number.isFinite && number > 0 else { return false }
                sawNumber = true
            } else if !allowed.contains(token.text) {
                return false
            }
        }
        return sawNumber
    }

    private static func safeRGBTint(
        _ expression: [Token],
        fragment: Unit
    ) -> Bool {
        let value = unwrapped(expression)
        guard value.count == 1, let name = value.first?.text else { return false }
        return fragment.declarations.contains {
            $0.storage == .uniform && $0.name == name
                && ["vec3", "float3"].contains($0.typeName)
                && $0.arraySize == nil
        }
    }

    private static func helperAccumulations(
        accumulator: String,
        helper: String,
        body: Range<Int>,
        tokens: [Token]
    ) -> [Int]? {
        let writes = body.filter { index in
            index + 1 < body.upperBound && tokens[index].text == accumulator
                && tokens[index + 1].text == "+="
        }
        guard !writes.isEmpty else { return nil }
        for write in writes {
            guard let value = expression(
                after: write,
                operators: ["+="],
                tokens: tokens,
                body: body
            ), let invocation = call(unwrapped(Array(value))),
                  invocation.name == helper, !invocation.arguments.isEmpty,
                  invocation.arguments.allSatisfy({ argument in
                      !argument.isEmpty && !argument.contains(where: {
                          $0.text == accumulator || $0.text == "gl_FragColor"
                            || ["texSample2D", "texture2D"].contains($0.text)
                      })
                  }) else { return nil }
        }
        return writes
    }

    private static func uniqueAccumulatorWrite(
        named name: String,
        in body: Range<Int>,
        tokens: [Token]
    ) -> Int? {
        let writes = body.filter { index in
            index + 1 < body.upperBound && tokens[index].text == name
                && tokens[index + 1].text == "+="
        }
        return writes.count == 1 ? writes[0] : nil
    }

    private static func uniqueMemberWrite(
        _ name: String,
        members: Set<String>,
        operation: String,
        in body: Range<Int>,
        tokens: [Token]
    ) -> Int? {
        let writes = body.filter { index in
            index + 3 < body.upperBound && tokens[index].text == name
                && tokens[index + 1].text == "."
                && members.contains(tokens[index + 2].text)
                && tokens[index + 3].text == operation
        }
        return writes.count == 1 ? writes[0] : nil
    }

    private static func exactReturn(
        _ name: String,
        function: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let returns = function.bodyRange.filter { tokens[$0].text == "return" }
        guard returns.count == 1, let marker = returns.first,
              marker + 2 < function.bodyRange.upperBound,
              tokens[marker + 1].text == name,
              tokens[marker + 2].text == ";" else { return false }
        return marker + 3 == function.bodyRange.upperBound - 1
    }

    private static func safeDenominatorUses(
        _ name: String,
        in body: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        let uses = body.filter { tokens[$0].text == name }
        guard uses.count == 3 else { return false }
        let declaration = uses.filter { index in
            index > body.lowerBound && tokens[index - 1].text == "float"
        }
        guard declaration.count == 1, let declared = declaration.first else { return false }
        return uses.filter({ $0 != declared }).allSatisfy {
            $0 > body.lowerBound && tokens[$0 - 1].text == "/"
        }
    }

    private static func parameterNames(
        _ function: Unit.Function,
        tokens: [Token]
    ) -> [String]? {
        guard let ranges = split(
            function.parameterRange,
            separator: ",",
            tokens: tokens
        ) else { return nil }
        var names: [String] = []
        for range in ranges {
            let values = Array(tokens[range]).filter { !["const", "in"].contains($0.text) }
            guard values.count == 2,
                  ["vec2", "float2"].contains(values[0].text),
                  values[1].kind == .identifier else { return nil }
            names.append(values[1].text)
        }
        return Set(names).count == names.count ? names : nil
    }

    private static func vectorDefinitions(
        in body: Range<Int>,
        tokens: [Token]
    ) -> [Int] {
        body.filter { index in
            index > body.lowerBound && index + 1 < body.upperBound
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index].kind == .identifier
                && tokens[index + 1].text == "="
        }
    }

    private static func zeroVector(_ expression: ArraySlice<Token>?) -> Bool {
        guard let expression, let value = call(unwrapped(Array(expression))),
              ["CAST4", "vec4", "float4"].contains(value.name),
              value.arguments.count == 1, value.arguments[0].count == 1,
              value.arguments[0].first.flatMap(numeric) == 0 else { return false }
        return true
    }

    private static func directSampleSlot(
        _ expression: ArraySlice<Token>?
    ) -> Int? {
        guard let expression else { return nil }
        return SceneAuthoredShaderColorTransferAnalyzer.directTextureSampleSlot(expression)
    }

    private static func expression(
        after assignment: Int,
        operators: Set<String> = ["="],
        tokens: [Token],
        body: Range<Int>
    ) -> ArraySlice<Token>? {
        let start = assignment + 2
        guard assignment + 1 < body.upperBound,
              operators.contains(tokens[assignment + 1].text),
              start < body.upperBound else { return nil }
        var depth = 0
        for index in start..<body.upperBound {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == ";", depth == 0 {
                return start < index ? tokens[start..<index] : nil
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    private struct Call {
        let name: String
        let arguments: [[Token]]
    }

    private static func call(_ expression: [Token]) -> Call? {
        guard expression.count >= 3, expression[0].kind == .identifier,
              expression[1].text == "(",
              matchingDelimiter(at: 1, tokens: expression) == expression.count - 1,
              let ranges = split(
                  2..<(expression.count - 1),
                  separator: ",",
                  tokens: expression
              ) else { return nil }
        return .init(
            name: expression[0].text,
            arguments: ranges.map { Array(expression[$0]) }
        )
    }

    private static func flattenedProduct(_ expression: [Token]) -> [[Token]] {
        let value = unwrapped(expression)
        guard let ranges = split(
            0..<value.count,
            separator: "*",
            tokens: value
        ), ranges.count > 1 else { return [value] }
        return ranges.flatMap { flattenedProduct(Array(value[$0])) }
    }

    private static func unwrapped(_ expression: [Token]) -> [Token] {
        var value = expression
        while value.count >= 2, value.first?.text == "(", value.last?.text == ")",
              matchingDelimiter(at: 0, tokens: value) == value.count - 1 {
            value.removeFirst()
            value.removeLast()
        }
        return value
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
            if ["(", "[", "{"].contains(tokens[index].text) { depth += 1 }
            if [")", "]", "}"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == separator, depth == 0 {
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            }
            guard depth >= 0 else { return nil }
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
              let closing = ["(": ")", "[": "]", "{": "}"][tokens[opening].text]
        else { return nil }
        var depth = 0
        for index in opening..<tokens.count {
            if tokens[index].text == tokens[opening].text { depth += 1 }
            if tokens[index].text == closing {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func loopIndices(
        in range: Range<Int>,
        tokens: [Token]
    ) -> [Int]? {
        guard !range.contains(where: {
            ["while", "do"].contains(tokens[$0].text)
        }) else { return nil }
        return range.filter { tokens[$0].text == "for" }
    }

    private static func sampleCalls(tokens: [Token]) -> [SampleCall]? {
        var result: [SampleCall] = []
        for index in tokens.indices where ["texSample2D", "texture2D"].contains(
            tokens[index].text
        ) {
            guard index + 3 < tokens.count, tokens[index + 1].text == "(",
                  tokens[index + 2].text.hasPrefix("g_Texture"),
                  let slot = Int(tokens[index + 2].text.dropFirst("g_Texture".count)),
                  (0 ... 7).contains(slot), tokens[index + 3].text == ",",
                  let closing = matchingDelimiter(at: index + 1, tokens: tokens)
            else { return nil }
            result.append(.init(index: index, slot: slot, closing: closing))
        }
        return result
    }

    private static func uniqueFunction(
        named name: String,
        fragment: Unit
    ) -> Unit.Function? {
        let values = fragment.functions.filter { $0.name == name }
        return values.count == 1 ? values[0] : nil
    }

    private static func wordCount(
        _ name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int {
        range.filter { tokens[$0].text == name }.count
    }

    private static func texts(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> [String] {
        range.map { tokens[$0].text }
    }

    private static func texts(_ tokens: [Token]) -> [String] {
        tokens.map(\.text)
    }

    private static func numeric(_ token: Token) -> Double? {
        guard token.kind == .number else { return nil }
        return Double(token.text)
    }

    private static func isIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z_]\w*$"#, options: .regularExpression) != nil
    }
}

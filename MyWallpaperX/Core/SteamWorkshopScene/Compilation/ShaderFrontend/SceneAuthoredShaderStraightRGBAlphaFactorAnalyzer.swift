import Foundation

/// Proves the bounded authored form `vec4(sample.rgb, sample.a * factors)`.
/// The proof is local to `main`: one color sample, no control flow, no color
/// mutation, and a multiplication-only alpha expression.
nonisolated enum SceneAuthoredShaderStraightRGBAlphaFactorAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output, tokens: tokens, body: main.bodyRange
              ), !containsControlFlow(tokens: tokens, body: main.bodyRange),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: output, in: tokens, body: main.bodyRange
                  ), let construction = outputConstruction(expression),
              let colorDefinition = uniqueDefinition(
                  construction.color,
                  types: ["vec4", "float4"],
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ), let colorInitializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: colorDefinition, in: tokens, body: main.bodyRange
                  ), let slot = SceneAuthoredShaderColorTransferAnalyzer
                  .directTextureSampleSlot(colorInitializer),
              let alphaDefinition = uniqueDefinition(
                  construction.alpha,
                  types: ["float"],
                  before: output,
                  tokens: tokens,
                  body: main.bodyRange
              ), let alphaInitializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: alphaDefinition, in: tokens, body: main.bodyRange
                  ), alphaProduct(alphaInitializer, color: construction.color),
              let closure = safeFunctionClosure(fragment: fragment, main: main),
              closure.reduce(0, {
                  $0 + sampleCallCount(tokens: tokens, body: $1.bodyRange)
              }) == 1,
              exactUses(
                  color: construction.color,
                  colorDefinition: colorDefinition,
                  alpha: construction.alpha,
                  alphaDefinition: alphaDefinition,
                  tokens: tokens,
                  body: main.bodyRange
              ) else { return nil }
        return slot
    }

    /// Restricts user helpers reachable from `main` to scalar-safe, local
    /// computation. Unused helpers do not affect the proof, while a reachable
    /// helper cannot hide another texture read, control flow, or an external
    /// write behind an otherwise scalar-looking factor.
    private static func safeFunctionClosure(
        fragment: Unit,
        main: Unit.Function
    ) -> [Unit.Function]? {
        let functions = fragment.functions
        let indicesByName = Dictionary(grouping: functions.indices) {
            functions[$0].name
        }
        guard let mainIndex = functions.firstIndex(of: main) else { return nil }
        var pending = [mainIndex]
        var visited: Set<Int> = []
        while let index = pending.popLast() {
            guard visited.insert(index).inserted else { continue }
            let function = functions[index]
            for call in functionCalls(
                tokens: fragment.tokens,
                body: function.bodyRange
            ) {
                guard let matches = indicesByName[call] else { continue }
                guard matches.count == 1, let callee = matches.first else {
                    return nil
                }
                pending.append(callee)
            }
        }
        let closure = visited.sorted().map { functions[$0] }
        guard closure.allSatisfy({ function in
            function.name == "main" || safeHelper(function, fragment: fragment)
        }), !containsControlFlow(tokens: fragment.tokens, body: main.bodyRange) else {
            return nil
        }
        return closure
    }

    private static func safeHelper(
        _ function: Unit.Function,
        fragment: Unit
    ) -> Bool {
        let tokens = fragment.tokens
        guard hasOneTerminalRootReturn(tokens: tokens, body: function.bodyRange),
              sampleCallCount(tokens: tokens, body: function.bodyRange) == 0,
              !tokens[function.parameterRange].contains(where: {
                  ["out", "inout"].contains($0.text)
              }) else { return false }

        let parameters = parameterNames(
            tokens: tokens, range: function.parameterRange
        )
        let locals = localNames(tokens: tokens, body: function.bodyRange)
        let writable = parameters.union(locals)
        return function.bodyRange.allSatisfy { index in
            guard tokens[index].kind == .identifier else { return true }
            let directWrite = index + 1 < function.bodyRange.upperBound
                && assignmentOperators.contains(tokens[index + 1].text)
            let memberWrite = index + 3 < function.bodyRange.upperBound
                && tokens[index + 1].text == "."
                && assignmentOperators.contains(tokens[index + 3].text)
            return !(directWrite || memberWrite) || writable.contains(tokens[index].text)
        }
    }

    private static func hasOneTerminalRootReturn(
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case", "discard",
        ]
        guard !body.contains(where: { forbidden.contains(tokens[$0].text) }) else {
            return false
        }
        let returns = body.filter { tokens[$0].text == "return" }
        guard returns.count == 1, let result = returns.first else { return false }
        var depth = 0
        for index in body.lowerBound..<result {
            if tokens[index].text == "{" { depth += 1 }
            if tokens[index].text == "}" { depth -= 1 }
        }
        guard depth == 1,
              let semicolon = (result..<body.upperBound).first(where: {
                  tokens[$0].text == ";"
              }) else { return false }
        return semicolon == body.upperBound - 2
    }

    private static let assignmentOperators: Set<String> = [
        "=", "+=", "-=", "*=", "/=",
    ]

    private static let localTypes: Set<String> = [
        "bool", "int", "uint", "float", "vec2", "vec3", "vec4",
        "float2", "float3", "float4", "mat2", "mat3", "mat4",
        "float2x2", "float3x3", "float4x4",
    ]

    private static func parameterNames(
        tokens: [Token],
        range: Range<Int>
    ) -> Set<String> {
        var result: Set<String> = []
        var start = range.lowerBound
        for index in range.lowerBound...range.upperBound {
            if index == range.upperBound || tokens[index].text == "," {
                if let name = tokens[start..<index].last(where: {
                    $0.kind == .identifier && !localTypes.contains($0.text)
                        && !["const", "in"].contains($0.text)
                })?.text {
                    result.insert(name)
                }
                start = index + 1
            }
        }
        return result
    }

    private static func localNames(
        tokens: [Token],
        body: Range<Int>
    ) -> Set<String> {
        Set(body.compactMap { index in
            guard index > body.lowerBound, index + 1 < body.upperBound,
                  tokens[index].kind == .identifier,
                  localTypes.contains(tokens[index - 1].text),
                  ["=", ";", ","].contains(tokens[index + 1].text) else {
                return nil
            }
            return tokens[index].text
        })
    }

    private static func functionCalls(
        tokens: [Token],
        body: Range<Int>
    ) -> Set<String> {
        Set(body.compactMap { index in
            guard index + 1 < body.upperBound,
                  tokens[index].kind == .identifier,
                  tokens[index + 1].text == "(" else { return nil }
            return tokens[index].text
        })
    }

    private static func outputConstruction(
        _ expression: ArraySlice<Token>
    ) -> (color: String, alpha: String)? {
        let value = Array(expression)
        guard value.count == 8,
              ["vec4", "float4"].contains(value[0].text),
              value[1].text == "(", value[2].kind == .identifier,
              value[3].text == ".", value[4].text == "rgb",
              value[5].text == ",", value[6].kind == .identifier,
              value[7].text == ")" else { return nil }
        return (value[2].text, value[6].text)
    }

    private static func uniqueDefinition(
        _ name: String,
        types: Set<String>,
        before boundary: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Int? {
        let matches = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && types.contains(tokens[index - 1].text)
                && index + 1 < tokens.count && tokens[index + 1].text == "="
        }
        guard matches.count == 1, let definition = matches.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  definition, tokens: tokens, body: body
              ) else { return nil }
        return definition
    }

    private static func alphaProduct(
        _ expression: ArraySlice<Token>,
        color: String
    ) -> Bool {
        let value = Array(expression)
        var cursor = 0
        var colorAlphaCount = 0
        var operandCount = 0
        while cursor < value.count {
            if cursor + 2 < value.count,
               value[cursor].text == color,
               value[cursor + 1].text == ".",
               value[cursor + 2].text == "a" {
                colorAlphaCount += 1
                cursor += 3
            } else if [.identifier, .number].contains(value[cursor].kind) {
                cursor += 1
            } else {
                return false
            }
            operandCount += 1
            if cursor == value.count { break }
            guard value[cursor].text == "*" else { return false }
            cursor += 1
        }
        return colorAlphaCount == 1 && operandCount >= 2
    }

    private static func exactUses(
        color: String,
        colorDefinition: Int,
        alpha: String,
        alphaDefinition: Int,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let colorUses = body.filter { tokens[$0].text == color }
        let alphaUses = body.filter { tokens[$0].text == alpha }
        guard colorUses.count == 3, colorUses.contains(colorDefinition),
              alphaUses.count == 2, alphaUses.contains(alphaDefinition) else {
            return false
        }
        let members = colorUses.filter { $0 != colorDefinition }.compactMap { index in
            index + 2 < body.upperBound && tokens[index + 1].text == "."
                ? tokens[index + 2].text : nil
        }
        return members.sorted() == ["a", "rgb"]
    }

    private static func sampleCallCount(
        tokens: [Token],
        body: Range<Int>
    ) -> Int {
        body.filter { ["texSample2D", "texture2D"].contains(tokens[$0].text) }.count
    }

    private static func containsControlFlow(
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let controls: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case", "return", "discard",
        ]
        return body.contains { controls.contains(tokens[$0].text) }
    }
}

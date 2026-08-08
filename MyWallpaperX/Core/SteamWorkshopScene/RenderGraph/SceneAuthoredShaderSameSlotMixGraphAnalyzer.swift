import Foundation

/// Proves a bounded root-local color graph whose leaves all sample one texture
/// slot and whose only color operation is scalar `mix`. Coordinate and scalar
/// expressions may consume auxiliary samplers without changing color ownership.
nonisolated enum SceneAuthoredShaderSameSlotMixGraphAnalyzer {
    private struct State {
        let fragment: SceneAuthoredShaderSyntaxUnit
        let main: SceneAuthoredShaderSyntaxUnit.Function
        var remainingNodes = 64
        var activeAssignments: Set<Int> = []
    }

    static func analyze(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
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
                  ) else {
            return nil
        }
        var state = State(fragment: fragment, main: main)
        guard let slots = colorSlots(
            expression,
            before: output,
            state: &state
        ), slots.count == 1 else {
            return nil
        }
        return slots.first
    }

    private static func colorSlots(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        before boundary: Int,
        state: inout State
    ) -> Set<Int>? {
        guard state.remainingNodes > 0 else { return nil }
        state.remainingNodes -= 1
        let expression = unwrapped(expression)
        if let slot = SceneAuthoredShaderColorTransferAnalyzer
            .directTextureSampleSlot(expression) {
            return [slot]
        }
        if let arguments = callArguments(named: "mix", expression: expression),
           arguments.count == 3,
           isScalar(arguments[2], before: boundary, state: state),
           let first = colorSlots(arguments[0], before: boundary, state: &state),
           let second = colorSlots(arguments[1], before: boundary, state: &state) {
            let slots = first.union(second)
            return slots.count == 1 ? slots : nil
        }
        guard expression.count == 1,
              let token = expression.first,
              token.kind == .identifier,
              let assignment = reachingVectorAssignment(
                  named: token.text,
                  before: boundary,
                  state: state
              ),
              state.activeAssignments.insert(assignment).inserted,
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: assignment,
                      in: state.fragment.tokens,
                      body: state.main.bodyRange
                  ),
              isDeclaration(assignment, state: state)
                  || isSelfMix(
                      initializer,
                      name: token.text
                  ) else {
            return nil
        }
        defer { state.activeAssignments.remove(assignment) }
        return colorSlots(initializer, before: assignment, state: &state)
    }

    private static func isDeclaration(
        _ assignment: Int,
        state: State
    ) -> Bool {
        assignment > state.main.bodyRange.lowerBound
            && ["vec4", "float4"].contains(
                state.fragment.tokens[assignment - 1].text
            )
    }

    private static func isSelfMix(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        name: String
    ) -> Bool {
        guard let arguments = callArguments(
            named: "mix",
            expression: unwrapped(expression)
        ), arguments.count == 3 else { return false }
        return arguments.prefix(2).contains {
            $0.count == 1 && $0.first?.text == name
        }
    }

    private static func reachingVectorAssignment(
        named name: String,
        before boundary: Int,
        state: State
    ) -> Int? {
        let tokens = state.fragment.tokens
        let body = state.main.bodyRange
        let declarations = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        guard declarations.count == 1 else { return nil }
        let assignments = body.filter { index in
            index >= declarations[0] && index < boundary
                && tokens[index].text == name
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
                && (index == body.lowerBound || tokens[index - 1].text != ".")
        }
        guard let assignment = assignments.last,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  assignment,
                  tokens: tokens,
                  body: body
              ),
              !hasMutation(
                  named: name,
                  after: assignment,
                  before: boundary,
                  tokens: tokens
              ) else {
            return nil
        }
        return assignment
    }

    private static func hasMutation(
        named name: String,
        after assignment: Int,
        before boundary: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        let operators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        return tokens.indices.contains { index in
            guard index > assignment, index < boundary,
                  tokens[index].text == name else { return false }
            if index + 1 < boundary, operators.contains(tokens[index + 1].text) {
                return true
            }
            return index + 3 < boundary
                && tokens[index + 1].text == "."
                && operators.contains(tokens[index + 3].text)
        }
    }

    private static func isScalar(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        before boundary: Int,
        state: State
    ) -> Bool {
        let expression = unwrapped(expression)
        guard let first = expression.first else { return false }
        if expression.count == 1 {
            if first.kind == .number { return true }
            guard first.kind == .identifier else { return false }
            return state.fragment.declarations.contains {
                $0.name == first.text && $0.typeName == "float" && $0.arraySize == nil
            } || localType(
                named: first.text,
                before: boundary,
                state: state
            ) == "float"
        }
        if expression.count == 3,
           expression[expression.startIndex + 1].text == ".",
           expression.last?.text.count == 1,
           let type = expressionType(
               named: first.text,
               before: boundary,
               state: state
           ), ["vec2", "vec3", "vec4", "float2", "float3", "float4"]
               .contains(type) {
            return true
        }
        let componentwise: Set<String> = [
            "abs", "acos", "asin", "atan", "ceil", "cos", "exp", "floor",
            "fract", "frac", "log", "round", "saturate", "sign", "sin", "sqrt",
        ]
        if componentwise.contains(first.text),
           let arguments = callArguments(named: first.text, expression: expression),
           arguments.count == 1 {
            return isScalar(arguments[0], before: boundary, state: state)
        }
        let scalarResults: Set<String> = ["distance", "dot", "length"]
        if scalarResults.contains(first.text),
           callArguments(named: first.text, expression: expression) != nil {
            return true
        }
        let scalarArguments: Set<String> = ["clamp", "max", "min", "mix", "pow", "smoothstep", "step"]
        guard scalarArguments.contains(first.text),
              let arguments = callArguments(named: first.text, expression: expression),
              !arguments.isEmpty else { return false }
        return arguments.allSatisfy {
            isScalar($0, before: boundary, state: state)
        }
    }

    private static func expressionType(
        named name: String,
        before boundary: Int,
        state: State
    ) -> String? {
        state.fragment.declarations.first { $0.name == name }?.typeName
            ?? localType(named: name, before: boundary, state: state)
    }

    private static func localType(
        named name: String,
        before boundary: Int,
        state: State
    ) -> String? {
        let tokens = state.fragment.tokens
        let types = state.main.bodyRange.compactMap { index -> String? in
            guard index > state.main.bodyRange.lowerBound, index < boundary,
                  tokens[index].text == name,
                  tokens[index - 1].kind == .identifier,
                  SceneAuthoredShaderValueType(
                      authoredName: tokens[index - 1].text
                  ) != nil else { return nil }
            return tokens[index - 1].text
        }
        return Set(types).count == 1 ? types.first : nil
    }

    private static func unwrapped(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> ArraySlice<SceneAuthoredShaderToken> {
        guard expression.count >= 2,
              expression.first?.text == "(", expression.last?.text == ")",
              outerCallClosesAtEnd(Array(expression)) else { return expression }
        return expression.dropFirst().dropLast()
    }

    private static func callArguments(
        named name: String,
        expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> [ArraySlice<SceneAuthoredShaderToken>]? {
        let tokens = Array(expression)
        guard tokens.count >= 4, tokens[0].text == name,
              tokens[1].text == "(", tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens) else { return nil }
        var depth = 0
        var start = 2
        var ranges: [Range<Int>] = []
        for index in 2..<(tokens.count - 1) {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return nil }
                ranges.append(start..<index)
                start = index + 1
            default: break
            }
        }
        guard depth == 0, start < tokens.count - 1 else { return nil }
        ranges.append(start..<(tokens.count - 1))
        let base = expression.startIndex
        return ranges.map {
            expression[(base + $0.lowerBound)..<(base + $0.upperBound)]
        }
    }

    private static func outerCallClosesAtEnd(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        var depth = 0
        for index in 1..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index == tokens.count - 1 }
                if depth < 0 { return false }
            }
        }
        return false
    }
}

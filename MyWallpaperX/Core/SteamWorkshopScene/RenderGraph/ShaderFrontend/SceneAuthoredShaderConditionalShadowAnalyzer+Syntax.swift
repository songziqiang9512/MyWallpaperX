import Foundation

nonisolated extension SceneAuthoredShaderConditionalShadowAnalyzer {
    static func terminalBranches(
        main: Unit.Function,
        tokens: [Token]
    ) -> Branches? {
        let body = main.bodyRange
        var depth = 0
        var rootIfs: [Int] = []
        for index in body {
            if tokens[index].text == "if",
               depth == 1,
               index == body.lowerBound || tokens[index - 1].text != "else" {
                rootIfs.append(index)
            }
            if tokens[index].text == "{" { depth += 1 }
            if tokens[index].text == "}" { depth -= 1 }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0,
              rootIfs.count == 1,
              let firstIf = rootIfs.first,
              tokens[firstIf + 1].text == "(",
              let firstClose = matching(firstIf + 1, tokens: tokens),
              tokens[firstClose + 1].text == "{",
              let firstEnd = matching(firstClose + 1, tokens: tokens),
              tokens[firstEnd + 1].text == "else",
              tokens[firstEnd + 2].text == "if",
              tokens[firstEnd + 3].text == "(",
              let secondClose = matching(firstEnd + 3, tokens: tokens),
              tokens[secondClose + 1].text == "{",
              let secondEnd = matching(secondClose + 1, tokens: tokens),
              tokens[secondEnd + 1].text == "else",
              tokens[secondEnd + 2].text == "{",
              let fallbackEnd = matching(secondEnd + 2, tokens: tokens),
              fallbackEnd == body.upperBound - 2 else { return nil }
        return .init(
            prelude: (body.lowerBound + 1)..<firstIf,
            firstCondition: tokens[(firstIf + 2)..<firstClose],
            firstBody: (firstClose + 2)..<firstEnd,
            secondCondition: tokens[(firstEnd + 4)..<secondClose],
            secondBody: (secondClose + 2)..<secondEnd,
            fallbackBody: (secondEnd + 3)..<fallbackEnd
        )
    }

    static func exactStatements(
        _ range: Range<Int>,
        starts: [Int],
        tokens: [Token]
    ) -> Bool {
        var result: [Int] = []
        var depth = 0
        var start = range.lowerBound
        for index in range {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == ";", depth == 0 {
                result.append(start)
                start = index + 1
            }
            guard depth >= 0 else { return false }
        }
        return depth == 0 && start == range.upperBound && result == starts
    }

    static func sampleCalls(in range: Range<Int>, tokens: [Token]) -> [Int] {
        range.filter { ["texSample2D", "texture2D"].contains(tokens[$0].text) }
    }

    static func mainCallsAreBounded(_ main: Unit.Function, fragment: Unit) -> Bool {
        let allowed: Set<String> = [
            "ApplyBlending", "float2", "if", "min", "texSample2D",
            "texture2D", "vec2",
        ]
        let tokens = fragment.tokens
        return main.bodyRange.allSatisfy { index in
            guard tokens[index].kind == .identifier,
                  index + 1 < main.bodyRange.upperBound,
                  tokens[index + 1].text == "(" else { return true }
            return allowed.contains(tokens[index].text)
        }
    }

    static func member(
        _ expression: ArraySlice<Token>,
        name: String,
        component: String
    ) -> Bool {
        texts(strippingParentheses(expression)) == [name, ".", component]
    }

    static func call(
        _ expression: ArraySlice<Token>
    ) -> (name: String, arguments: [ArraySlice<Token>])? {
        let value = Array(strippingParentheses(expression))
        guard value.count >= 3,
              value[0].kind == .identifier,
              value[1].text == "(",
              value.last?.text == ")",
              matching(1, tokens: value) == value.count - 1 else { return nil }
        let content = value[2..<(value.count - 1)]
        guard let arguments = commaSeparated(content) else { return nil }
        return (value[0].text, arguments)
    }

    static func commaSeparated(
        _ tokens: ArraySlice<Token>
    ) -> [ArraySlice<Token>]? {
        guard !tokens.isEmpty else { return [] }
        var result: [ArraySlice<Token>] = []
        var start = tokens.startIndex
        var depth = 0
        for index in tokens.indices {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == ",", depth == 0 {
                guard start < index else { return nil }
                result.append(tokens[start..<index])
                start = index + 1
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < tokens.endIndex else { return nil }
        result.append(tokens[start..<tokens.endIndex])
        return result
    }

    static func rootReturnExpressions(
        _ function: Unit.Function,
        fragment: Unit
    ) -> [ArraySlice<Token>]? {
        let tokens = fragment.tokens
        var result: [ArraySlice<Token>] = []
        var cursor = function.bodyRange.lowerBound + 1
        let end = function.bodyRange.upperBound - 1
        while cursor < end {
            guard tokens[cursor].text == "return" else { return nil }
            var depth = 0
            var semicolon: Int?
            for index in (cursor + 1)..<end {
                if ["(", "["].contains(tokens[index].text) { depth += 1 }
                if [")", "]"].contains(tokens[index].text) { depth -= 1 }
                if tokens[index].text == ";", depth == 0 {
                    semicolon = index
                    break
                }
                guard depth >= 0 else { return nil }
            }
            guard let semicolon, cursor + 1 < semicolon else { return nil }
            result.append(tokens[(cursor + 1)..<semicolon])
            cursor = semicolon + 1
        }
        return cursor == end ? result : nil
    }

    static func blendParameterNames(
        _ function: Unit.Function,
        fragment: Unit
    ) -> [String]? {
        guard ["vec3", "float3"].contains(function.returnType),
              let parameters = commaSeparated(
                  fragment.tokens[function.parameterRange]
              ),
              parameters.count == 4 else { return nil }
        let normalized = parameters.map { parameter in
            parameter.filter { !["const", "in"].contains($0.text) }
        }
        let expectedTypes: [Set<String>] = [
            ["int"], ["vec3", "float3"], ["vec3", "float3"], ["float"],
        ]
        var names: [String] = []
        for (parameter, types) in zip(normalized, expectedTypes) {
            guard parameter.count == 2,
                  types.contains(parameter[0].text),
                  parameter[1].kind == .identifier else { return nil }
            names.append(parameter[1].text)
        }
        return Set(names).count == 4 ? names : nil
    }

    static func strippingParentheses(
        _ raw: ArraySlice<Token>
    ) -> ArraySlice<Token> {
        var value = raw
        while value.count >= 2,
              value.first?.text == "(",
              value.last?.text == ")" {
            let array = Array(value)
            guard matching(0, tokens: array) == array.count - 1 else { break }
            value = value.dropFirst().dropLast()
        }
        return value
    }

    static func matching(_ open: Int, tokens: [Token]) -> Int? {
        guard tokens.indices.contains(open) else { return nil }
        let opening = tokens[open].text
        let closing = opening == "(" ? ")" : opening == "{" ? "}" : "]"
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index].text == opening { depth += 1 }
            if tokens[index].text == closing {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    static func number(_ expression: ArraySlice<Token>) -> Double? {
        let value = strippingParentheses(expression)
        guard value.count == 1 else { return nil }
        return Double(value.first!.text)
    }

    static func identifier(_ expression: ArraySlice<Token>) -> String? {
        let value = strippingParentheses(expression)
        return value.count == 1 && value.first?.kind == .identifier
            ? value.first?.text : nil
    }

    static func texts<S: Sequence>(_ tokens: S) -> [String]
    where S.Element == Token {
        tokens.map(\.text)
    }
}

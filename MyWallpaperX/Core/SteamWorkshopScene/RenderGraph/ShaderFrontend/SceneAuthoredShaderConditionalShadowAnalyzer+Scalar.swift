import Foundation

nonisolated extension SceneAuthoredShaderConditionalShadowAnalyzer {
    struct ScalarOneDefinition {
        let name: String
        let nameIndex: Int
    }

    static func scalarOneDefinitions(
        in range: Range<Int>,
        main: Unit.Function,
        tokens: [Token]
    ) -> [ScalarOneDefinition]? {
        var definitions: [ScalarOneDefinition] = []
        for index in range where index > range.lowerBound
            && index + 2 < range.upperBound
            && tokens[index - 1].text == "float"
            && tokens[index].kind == .identifier
            && tokens[index + 1].text == "=" {
            guard SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                index, tokens: tokens, body: main.bodyRange
            ), let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(after: index, in: tokens, body: main.bodyRange),
                  number(expression) == 1 else {
                return nil
            }
            definitions.append(.init(
                name: tokens[index].text,
                nameIndex: index
            ))
        }
        guard definitions.count <= 1 else { return nil }
        return definitions
    }

    static func scalarExpression(
        _ expression: ArraySlice<Token>,
        scalarOne: String?,
        fragment: Unit
    ) -> Bool {
        guard let factors = multiplicationFactors(expression),
              (1...8).contains(factors.count) else { return false }
        return factors.allSatisfy { factor in
            let value = strippingParentheses(factor)
            if let literal = number(value) { return literal.isFinite }
            guard value.count == 1,
                  let name = value.first?.text else { return false }
            return name == scalarOne
                || readOnlyScalarUniform(name, fragment: fragment)
        }
    }

    private static func readOnlyScalarUniform(
        _ name: String,
        fragment: Unit
    ) -> Bool {
        let declarations = fragment.declarations.filter {
            $0.name == name
                && ["float", "int", "uint", "bool"].contains($0.typeName)
                && $0.arraySize == nil
        }
        guard declarations.count == 1,
              declarations[0].storage == .uniform else { return false }
        return !fragment.tokens.indices.contains { index in
            guard fragment.tokens[index].text == name else { return false }
            let previous = index > 0 ? fragment.tokens[index - 1].text : ""
            let next = index + 1 < fragment.tokens.count
                ? fragment.tokens[index + 1].text : ""
            return ["=", "+=", "-=", "*=", "/=", "++", "--"].contains(next)
                || ["++", "--"].contains(previous)
        }
    }

    private static func multiplicationFactors(
        _ expression: ArraySlice<Token>
    ) -> [ArraySlice<Token>]? {
        let value = strippingParentheses(expression)
        guard !value.isEmpty else { return nil }
        var result: [ArraySlice<Token>] = []
        var start = value.startIndex
        var depth = 0
        for index in value.indices {
            if ["(", "["].contains(value[index].text) { depth += 1 }
            if [")", "]"].contains(value[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if value[index].text == "*", depth == 0 {
                guard start < index else { return nil }
                result.append(value[start..<index])
                start = index + 1
            }
        }
        guard depth == 0, start < value.endIndex else { return nil }
        result.append(value[start..<value.endIndex])
        return result
    }

    static func scalarOneIsExact(
        _ definition: ScalarOneDefinition?,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        guard let definition else { return true }
        return main.bodyRange.filter { tokens[$0].text == definition.name }.count
            == 3
    }
}

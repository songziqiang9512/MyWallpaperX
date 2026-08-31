import Foundation

/// Shared token mechanics for the bounded helper-accumulator proof. Keeping
/// them separate leaves the primary analyzer focused on provenance, loop work,
/// and output-storage constraints.
extension SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer {
    static func flattenedProduct(_ expression: [Token]) -> [[Token]] {
        let value = unwrapped(expression)
        guard let ranges = split(
            0..<value.count,
            separator: "*",
            tokens: value
        ), ranges.count > 1 else { return [value] }
        return ranges.flatMap { flattenedProduct(Array(value[$0])) }
    }

    static func unwrapped(_ expression: [Token]) -> [Token] {
        var value = expression
        while value.count >= 2, value.first?.text == "(", value.last?.text == ")",
              matchingDelimiter(at: 0, tokens: value) == value.count - 1 {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }

    static func split(
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

    static func matchingDelimiter(
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

    static func loopIndices(
        in range: Range<Int>,
        tokens: [Token]
    ) -> [Int]? {
        guard !range.contains(where: {
            ["while", "do"].contains(tokens[$0].text)
        }) else { return nil }
        return range.filter { tokens[$0].text == "for" }
    }

    static func uniqueFunction(
        named name: String,
        fragment: Unit
    ) -> Unit.Function? {
        let values = fragment.functions.filter { $0.name == name }
        return values.count == 1 ? values[0] : nil
    }

    static func wordCount(
        _ name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int {
        range.filter { tokens[$0].text == name }.count
    }

    static func texts(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> [String] {
        range.map { tokens[$0].text }
    }

    static func texts(_ tokens: [Token]) -> [String] {
        tokens.map(\.text)
    }

    static func numeric(_ token: Token) -> Double? {
        guard token.kind == .number else { return nil }
        return Double(token.text)
    }

    static func isIdentifier(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z_]\w*$"#, options: .regularExpression) != nil
    }
}

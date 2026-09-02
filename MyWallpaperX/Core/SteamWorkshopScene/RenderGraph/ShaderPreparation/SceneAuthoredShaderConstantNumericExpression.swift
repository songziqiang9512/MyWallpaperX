import Foundation

/// Evaluates the small constant-number grammar used by source-driven shader
/// canonicalizers. Unknown identifiers remain caller-owned and fail closed.
nonisolated struct SceneAuthoredShaderConstantNumericExpression {
    private let source: String
    private let resolve: (String) -> Double?
    private var index: String.Index

    init(_ source: String, resolve: @escaping (String) -> Double?) {
        self.source = source
        self.resolve = resolve
        self.index = source.startIndex
    }

    mutating func parse() -> Double? {
        guard let value = sum() else { return nil }
        skipSpaces()
        return index == source.endIndex ? value : nil
    }

    private mutating func sum() -> Double? {
        guard var value = product() else { return nil }
        while let operation = take(oneOf: "+-") {
            guard let right = product() else { return nil }
            value = operation == "+" ? value + right : value - right
        }
        return value
    }

    private mutating func product() -> Double? {
        guard var value = atom() else { return nil }
        while let operation = take(oneOf: "*/%") {
            guard let right = atom(), right != 0 else { return nil }
            if operation == "*" { value *= right }
            if operation == "/" { value /= right }
            if operation == "%" { value.formTruncatingRemainder(dividingBy: right) }
        }
        return value
    }

    private mutating func atom() -> Double? {
        skipSpaces()
        if take("(") {
            guard let value = sum(), take(")") else { return nil }
            return value
        }
        if take("-") { return atom().map(-) }
        if let value = number() { return value }
        guard let name = identifier() else { return nil }
        if ["int", "uint", "float"].contains(name), take("(") {
            guard let value = sum(), take(")") else { return nil }
            if name == "float" { return value }
            if name == "uint", value < 0 { return nil }
            return value.rounded(.towardZero)
        }
        return resolve(name)
    }

    private mutating func number() -> Double? {
        skipSpaces()
        let start = index
        while index < source.endIndex,
              source[index].isNumber || source[index] == "." {
            index = source.index(after: index)
        }
        guard start != index else { return nil }
        return Double(source[start..<index])
    }

    private mutating func identifier() -> String? {
        skipSpaces()
        let start = index
        guard index < source.endIndex,
              source[index].isLetter || source[index] == "_" else { return nil }
        while index < source.endIndex,
              source[index].isLetter || source[index].isNumber || source[index] == "_" {
            index = source.index(after: index)
        }
        return String(source[start..<index])
    }

    private mutating func take(_ token: Character) -> Bool {
        skipSpaces()
        guard index < source.endIndex, source[index] == token else { return false }
        index = source.index(after: index)
        return true
    }

    private mutating func take(oneOf tokens: String) -> Character? {
        skipSpaces()
        guard index < source.endIndex, tokens.contains(source[index]) else { return nil }
        let token = source[index]
        index = source.index(after: index)
        return token
    }

    private mutating func skipSpaces() {
        while index < source.endIndex, source[index].isWhitespace {
            index = source.index(after: index)
        }
    }
}

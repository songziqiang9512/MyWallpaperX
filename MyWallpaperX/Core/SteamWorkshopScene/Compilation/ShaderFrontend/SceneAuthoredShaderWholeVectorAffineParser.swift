import Foundation

/// Parses the deliberately small expression algebra used by the whole-RGBA
/// filter proof. Color values may only be added/subtracted or scaled by a
/// scalar; color-by-color and scalar-divided-by-color operations are rejected.
nonisolated enum SceneAuthoredShaderWholeVectorAffineParser {
    enum ValueKind {
        case scalar
        case color
    }

    static func parse(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        scalarNames: Set<String>,
        colorNames: Set<String>
    ) -> ValueKind? {
        var parser = Parser(
            tokens: Array(expression),
            scalarNames: scalarNames,
            colorNames: colorNames
        )
        return parser.parse()
    }

    private struct Parser {
        let tokens: [SceneAuthoredShaderToken]
        let scalarNames: Set<String>
        let colorNames: Set<String>
        var index = 0

        mutating func parse() -> ValueKind? {
            guard let value = addition(), index == tokens.count else { return nil }
            return value
        }

        private mutating func addition() -> ValueKind? {
            guard var value = multiplication() else { return nil }
            while index < tokens.count, ["+", "-"].contains(tokens[index].text) {
                index += 1
                guard let right = multiplication(), right == value else { return nil }
                value = right
            }
            return value
        }

        private mutating func multiplication() -> ValueKind? {
            guard var value = unary() else { return nil }
            while index < tokens.count, ["*", "/"].contains(tokens[index].text) {
                let operation = tokens[index].text
                index += 1
                let denominatorIsFiniteLiteral = operation != "/"
                    || (index < tokens.count
                        && tokens[index].kind == .number
                        && Double(tokens[index].text).map({
                            $0.isFinite && $0 > 0
                        }) == true)
                guard let right = unary() else { return nil }
                guard denominatorIsFiniteLiteral else { return nil }
                switch (value, right, operation) {
                case (.scalar, .scalar, _): value = .scalar
                case (.color, .scalar, _): value = .color
                case (.scalar, .color, "*"): value = .color
                default: return nil
                }
            }
            return value
        }

        private mutating func unary() -> ValueKind? {
            if index < tokens.count, ["+", "-"].contains(tokens[index].text) {
                index += 1
                return unary()
            }
            return primary()
        }

        private mutating func primary() -> ValueKind? {
            guard index < tokens.count else { return nil }
            let token = tokens[index]
            if token.text == "(" {
                index += 1
                guard let value = addition(), index < tokens.count,
                      tokens[index].text == ")" else { return nil }
                index += 1
                return value
            }
            index += 1
            if token.kind == .number { return .scalar }
            guard token.kind == .identifier else { return nil }
            if scalarNames.contains(token.text) { return .scalar }
            if colorNames.contains(token.text) { return .color }
            return nil
        }
    }
}

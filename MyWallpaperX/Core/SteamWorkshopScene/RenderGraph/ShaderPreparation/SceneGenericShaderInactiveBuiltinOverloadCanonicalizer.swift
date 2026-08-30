import Foundation

/// Namespaces an inactive authored overload that collides with an external
/// GLSL built-in. The function body remains intact for compiler validation.
nonisolated enum SceneGenericShaderInactiveBuiltinOverloadCanonicalizer {
    private static let authoredName = "inverse"
    private static let canonicalName = "mwxInactiveInverse"

    private struct Token {
        enum Kind {
            case identifier
            case symbol
        }

        let kind: Kind
        let text: String
        let scalarRange: Range<Int>
    }

    private struct FunctionDefinition {
        let startTokenIndex: Int
        let nameTokenIndex: Int
        let openParenthesisIndex: Int
        let closeParenthesisIndex: Int
    }

    static func rewrite(_ source: String) -> String {
        guard let tokens = tokens(in: source),
              !tokens.contains(where: {
                  $0.kind == .identifier && $0.text == canonicalName
              }),
              let functions = functionDefinitions(in: tokens) else {
            return source
        }
        let candidates = functions.filter { isExactCollision($0, tokens: tokens) }
        guard !candidates.isEmpty else { return source }

        let definitionNames = Set(candidates.map(\.nameTokenIndex))
        for index in tokens.indices where tokens[index].text == authoredName {
            guard index + 1 < tokens.count, tokens[index + 1].text == "(" else {
                continue
            }
            if !definitionNames.contains(index) {
                return source
            }
        }

        var result = source
        for candidate in candidates.sorted(by: {
            tokens[$0.nameTokenIndex].scalarRange.lowerBound
                > tokens[$1.nameTokenIndex].scalarRange.lowerBound
        }) {
            let scalarRange = tokens[candidate.nameTokenIndex].scalarRange
            let lower = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: scalarRange.lowerBound
            )
            let upper = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: scalarRange.upperBound
            )
            result.unicodeScalars.replaceSubrange(
                lower..<upper,
                with: canonicalName.unicodeScalars
            )
        }
        return result
    }

    private static func isExactCollision(
        _ function: FunctionDefinition,
        tokens: [Token]
    ) -> Bool {
        guard tokens[function.startTokenIndex].text == "mat3",
              function.nameTokenIndex == function.startTokenIndex + 1,
              tokens[function.nameTokenIndex].text == authoredName,
              function.closeParenthesisIndex == function.openParenthesisIndex + 3
        else { return false }
        let parameterType = tokens[function.openParenthesisIndex + 1]
        let parameterName = tokens[function.openParenthesisIndex + 2]
        return parameterType.kind == .identifier
            && parameterType.text == "mat3"
            && parameterName.kind == .identifier
    }

    private static func tokens(in source: String) -> [Token]? {
        let scalars = Array(source.unicodeScalars)
        var result: [Token] = []
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                index += 1
                continue
            }
            if scalar == "/", index + 1 < scalars.count {
                if scalars[index + 1] == "/" {
                    index += 2
                    while index < scalars.count, scalars[index] != "\n" {
                        index += 1
                    }
                    continue
                }
                if scalars[index + 1] == "*" {
                    index += 2
                    var terminated = false
                    while index + 1 < scalars.count {
                        if scalars[index] == "*", scalars[index + 1] == "/" {
                            index += 2
                            terminated = true
                            break
                        }
                        index += 1
                    }
                    guard terminated else { return nil }
                    continue
                }
            }
            guard scalar != "#", scalar != "\"", scalar != "'" else {
                return nil
            }
            if isIdentifierStart(scalar) {
                let start = index
                index += 1
                while index < scalars.count, isIdentifierContinue(scalars[index]) {
                    index += 1
                }
                result.append(Token(
                    kind: .identifier,
                    text: String(String.UnicodeScalarView(scalars[start..<index])),
                    scalarRange: start..<index
                ))
                continue
            }
            result.append(Token(
                kind: .symbol,
                text: String(scalar),
                scalarRange: index..<(index + 1)
            ))
            index += 1
        }
        return result
    }

    private static func functionDefinitions(
        in tokens: [Token]
    ) -> [FunctionDefinition]? {
        var result: [FunctionDefinition] = []
        var braceDepth = 0
        var previousTopLevelBoundary = -1
        var index = 0
        while index < tokens.count {
            switch tokens[index].text {
            case "{" where braceDepth == 0:
                guard index > 0 else { return nil }
                if tokens[index - 1].text == ")" {
                    guard let open = matchingOpenParenthesis(
                        before: index,
                        tokens: tokens
                    ), open > 0,
                          tokens[open - 1].kind == .identifier,
                          let close = matchingCloseBrace(at: index, tokens: tokens)
                    else { return nil }
                    result.append(FunctionDefinition(
                        startTokenIndex: previousTopLevelBoundary + 1,
                        nameTokenIndex: open - 1,
                        openParenthesisIndex: open,
                        closeParenthesisIndex: index - 1
                    ))
                    previousTopLevelBoundary = close
                    index = close + 1
                    continue
                }
                braceDepth += 1
            case "}":
                guard braceDepth > 0 else { return nil }
                braceDepth -= 1
                if braceDepth == 0 { previousTopLevelBoundary = index }
            case ";" where braceDepth == 0:
                previousTopLevelBoundary = index
            default:
                break
            }
            index += 1
        }
        guard braceDepth == 0 else { return nil }
        return result
    }

    private static func matchingOpenParenthesis(
        before end: Int,
        tokens: [Token]
    ) -> Int? {
        var depth = 0
        for index in stride(from: end - 1, through: 0, by: -1) {
            if tokens[index].text == ")" { depth += 1 }
            if tokens[index].text == "(" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func matchingCloseBrace(
        at start: Int,
        tokens: [Token]
    ) -> Int? {
        var depth = 0
        for index in start..<tokens.count {
            if tokens[index].text == "{" { depth += 1 }
            if tokens[index].text == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func isIdentifierStart(_ scalar: UnicodeScalar) -> Bool {
        scalar == "_" || CharacterSet.letters.contains(scalar)
    }

    private static func isIdentifierContinue(_ scalar: UnicodeScalar) -> Bool {
        isIdentifierStart(scalar) || CharacterSet.decimalDigits.contains(scalar)
    }
}

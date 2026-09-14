import Foundation

/// Namespaces an exact authored overload that collides with an external GLSL
/// built-in. Inactive definitions and statically mat3-typed active calls are
/// rewritten atomically; function bodies remain intact for compiler validation.
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

        guard candidates.count == 1 else { return source }
        let definitionNames = Set(candidates.map(\.nameTokenIndex))
        let activeCalls = tokens.indices.filter { index in
            tokens[index].text == authoredName
                && index + 1 < tokens.count
                && tokens[index + 1].text == "("
                && !definitionNames.contains(index)
        }
        guard activeCalls.allSatisfy({
            isStaticallyMat3Call($0, tokens: tokens, functions: functions)
        }) else { return source }

        var result = source
        let rewrittenNames = definitionNames.union(activeCalls)
        for nameIndex in rewrittenNames.sorted(by: {
            tokens[$0].scalarRange.lowerBound > tokens[$1].scalarRange.lowerBound
        }) {
            let scalarRange = tokens[nameIndex].scalarRange
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

    private static func isStaticallyMat3Call(
        _ nameIndex: Int,
        tokens: [Token],
        functions: [FunctionDefinition]
    ) -> Bool {
        guard nameIndex + 1 < tokens.count,
              let close = matchingCloseParenthesis(
                  at: nameIndex + 1,
                  tokens: tokens
              ),
              let argument = singleArgumentRange(
                  (nameIndex + 2)..<close,
                  tokens: tokens
              ) else { return false }
        return isStaticallyMat3Expression(
            argument,
            before: nameIndex,
            tokens: tokens,
            functions: functions
        )
    }

    private static func isStaticallyMat3Expression(
        _ rawRange: Range<Int>,
        before limit: Int,
        tokens: [Token],
        functions: [FunctionDefinition]
    ) -> Bool {
        let range = strippingParentheses(rawRange, tokens: tokens)
        guard !range.isEmpty else { return false }
        if range.count == 1, tokens[range.lowerBound].kind == .identifier {
            return lastDeclaredType(
                of: tokens[range.lowerBound].text,
                before: limit,
                tokens: tokens
            ) == "mat3"
        }
        guard range.count >= 3,
              tokens[range.lowerBound].kind == .identifier,
              tokens[range.lowerBound + 1].text == "(",
              matchingCloseParenthesis(
                  at: range.lowerBound + 1,
                  tokens: tokens
              ) == range.upperBound - 1 else { return false }
        let callee = tokens[range.lowerBound].text
        if callee == "mat3" { return true }
        let matchingFunctions = functions.filter {
            tokens[$0.nameTokenIndex].text == callee
        }
        return matchingFunctions.count == 1
            && tokens[matchingFunctions[0].startTokenIndex].text == "mat3"
    }

    private static func strippingParentheses(
        _ rawRange: Range<Int>,
        tokens: [Token]
    ) -> Range<Int> {
        var range = rawRange
        while range.count >= 2,
              tokens[range.lowerBound].text == "(",
              matchingCloseParenthesis(
                  at: range.lowerBound,
                  tokens: tokens
              ) == range.upperBound - 1 {
            range = (range.lowerBound + 1)..<(range.upperBound - 1)
        }
        return range
    }

    private static func lastDeclaredType(
        of name: String,
        before limit: Int,
        tokens: [Token]
    ) -> String? {
        let valueTypes: Set<String> = [
            "bool", "int", "uint", "float", "vec2", "vec3", "vec4",
            "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4",
            "bvec2", "bvec3", "bvec4", "mat2", "mat3", "mat4",
        ]
        var result: String?
        guard limit >= 2 else { return nil }
        for index in 0..<(limit - 1) where
            valueTypes.contains(tokens[index].text)
                && tokens[index + 1].kind == .identifier
                && tokens[index + 1].text == name
                && (index + 2 >= tokens.count || tokens[index + 2].text != "(") {
            result = tokens[index].text
        }
        return result
    }

    private static func singleArgumentRange(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> Range<Int>? {
        guard !range.isEmpty else { return nil }
        var parenthesisDepth = 0
        var bracketDepth = 0
        for index in range {
            switch tokens[index].text {
            case "(": parenthesisDepth += 1
            case ")": parenthesisDepth -= 1
            case "[": bracketDepth += 1
            case "]": bracketDepth -= 1
            case "," where parenthesisDepth == 0 && bracketDepth == 0:
                return nil
            default: break
            }
            guard parenthesisDepth >= 0, bracketDepth >= 0 else { return nil }
        }
        return parenthesisDepth == 0 && bracketDepth == 0 ? range : nil
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

    private static func matchingCloseParenthesis(
        at start: Int,
        tokens: [Token]
    ) -> Int? {
        guard tokens.indices.contains(start), tokens[start].text == "(" else {
            return nil
        }
        var depth = 0
        for index in start..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            guard depth >= 0 else { return nil }
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

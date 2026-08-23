import Foundation

/// One source-proven stage-link relaxation: a wider floating-point vertex
/// varying may satisfy a narrower fragment declaration only when the fragment
/// consumes the leading components and the vertex initializes that prefix on
/// every reachable path. No value conversion or suffix synthesis occurs.
nonisolated enum SceneAuthoredShaderVaryingPrefixLink {
    struct Fact {
        let name: String
        let vertexWidth: Int
        let fragmentWidth: Int
        let requiredComponents: String
        let wholeFragmentReferences: Set<SceneAuthoredShaderToken>
    }

    static func prove(
        name: String,
        vertexWidth: Int,
        fragmentWidth: Int,
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Fact? {
        prove(
            name: name,
            vertexWidth: vertexWidth,
            fragmentWidth: fragmentWidth,
            vertexTokens: vertex.tokens,
            vertexMain: vertex.functions.first { $0.name == "main" }?.bodyRange,
            vertexFunctionBodies: vertex.functions.map(\.bodyRange),
            fragmentTokens: fragment.tokens,
            fragmentFunctionBodies: fragment.functions.map(\.bodyRange)
        )
    }

    static func prove(
        name: String,
        vertexWidth: Int,
        fragmentWidth: Int,
        vertexSource: String,
        fragmentSource: String
    ) -> Fact? {
        let vertex = SceneAuthoredShaderLexer.lex(source: vertexSource, stage: .vertex)
        let fragment = SceneAuthoredShaderLexer.lex(source: fragmentSource, stage: .fragment)
        guard vertex.diagnostics.isEmpty, fragment.diagnostics.isEmpty,
              let vertexMain = mainBody(in: vertex.tokens),
              mainBody(in: fragment.tokens) != nil else { return nil }
        return prove(
            name: name,
            vertexWidth: vertexWidth,
            fragmentWidth: fragmentWidth,
            vertexTokens: vertex.tokens,
            vertexMain: vertexMain,
            vertexFunctionBodies: functionBodies(in: vertex.tokens),
            fragmentTokens: fragment.tokens,
            fragmentFunctionBodies: functionBodies(in: fragment.tokens)
        )
    }

    static func rewriteWholeFragmentReferences(
        _ source: String,
        facts: [String: Fact]
    ) -> String {
        var result = source
        for fact in facts.values.sorted(by: { $0.name > $1.name }) {
            let escaped = NSRegularExpression.escapedPattern(for: fact.name)
            let regex = try! NSRegularExpression(
                pattern: #"\b"# + escaped + #"\b(?!\s*\.)"#
            )
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: fact.name + "." + fact.requiredComponents
            )
        }
        return result
    }

    private static func prove(
        name: String,
        vertexWidth: Int,
        fragmentWidth: Int,
        vertexTokens: [SceneAuthoredShaderToken],
        vertexMain: Range<Int>?,
        vertexFunctionBodies: [Range<Int>],
        fragmentTokens: [SceneAuthoredShaderToken],
        fragmentFunctionBodies: [Range<Int>]
    ) -> Fact? {
        guard let vertexMain, (2 ... 4).contains(fragmentWidth),
              fragmentWidth < vertexWidth, vertexWidth <= 4 else { return nil }
        guard !vertexMain.contains(where: { vertexTokens[$0].text == "return" }),
              !vertexFunctionBodies.contains(where: { body in
                  body != vertexMain && body.contains {
                      vertexTokens[$0].text == name
                  }
              }) else { return nil }
        let required = String("xyzw".prefix(fragmentWidth))
        var depth = 0
        var assignments = 0
        for index in vertexMain {
            let text = vertexTokens[index].text
            if text == "{" { depth += 1 }
            defer { if text == "}" { depth -= 1 } }
            guard text == name else { continue }
            guard !isLocalDeclaration(index, tokens: vertexTokens) else { return nil }
            let assignment: Bool
            if index + 1 < vertexMain.upperBound,
               vertexTokens[index + 1].text == "=" {
                assignment = true
            } else if index + 3 < vertexMain.upperBound,
                      vertexTokens[index + 1].text == ".",
                      vertexTokens[index + 2].text == required,
                      vertexTokens[index + 3].text == "=" {
                assignment = true
            } else {
                return nil
            }
            guard assignment, depth == 1 else { return nil }
            assignments += 1
        }
        guard assignments == 1 else { return nil }

        var whole: Set<SceneAuthoredShaderToken> = []
        for body in fragmentFunctionBodies {
            for index in body where fragmentTokens[index].text == name {
                guard !isLocalDeclaration(index, tokens: fragmentTokens) else { return nil }
                let previous = index > body.lowerBound
                    ? fragmentTokens[index - 1].text : ""
                let next = index + 1 < body.upperBound
                    ? fragmentTokens[index + 1].text : ""
                guard !["=", "+=", "-=", "*=", "/=", "++", "--", "["].contains(next),
                      !["++", "--"].contains(previous) else { return nil }
                if next == "." {
                    guard index + 2 < body.upperBound,
                          fragmentTokens[index + 2].text == required,
                          index + 3 >= body.upperBound || ![
                              "=", "+=", "-=", "*=", "/=", "++", "--",
                          ].contains(fragmentTokens[index + 3].text),
                          safeCallContext(
                              index, tokens: fragmentTokens, body: body
                          ) else { return nil }
                } else {
                    // GLSL vector initialization is a value copy, not an alias.
                    // Accept only the exact declared prefix shape; assignments
                    // to an existing value and return/parameter escape remain
                    // outside this proof.
                    if previous == "=" {
                        guard isExactLocalPrefixValueCopy(
                            index,
                            width: fragmentWidth,
                            tokens: fragmentTokens,
                            body: body
                        ) else { return nil }
                    } else if previous == "return" {
                        return nil
                    }
                    guard safeCallContext(
                        index, tokens: fragmentTokens, body: body
                    ) else { return nil }
                    whole.insert(fragmentTokens[index])
                }
            }
        }
        guard !whole.isEmpty || fragmentFunctionBodies.contains(where: { body in
            body.indices.contains { index in
                fragmentTokens[index].text == name
                    && index + 2 < body.upperBound
                    && fragmentTokens[index + 1].text == "."
                    && fragmentTokens[index + 2].text == required
            }
        }) else { return nil }
        return .init(
            name: name,
            vertexWidth: vertexWidth,
            fragmentWidth: fragmentWidth,
            requiredComponents: required,
            wholeFragmentReferences: whole
        )
    }

    private static func isLocalDeclaration(
        _ index: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        guard index > 0 else { return false }
        return SceneAuthoredShaderValueType(authoredName: tokens[index - 1].text) != nil
    }

    private static func isExactLocalPrefixValueCopy(
        _ index: Int,
        width: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        guard index >= body.lowerBound + 3,
              index + 1 < body.upperBound,
              tokens[index - 3].text == "vec\(width)",
              tokens[index - 2].kind == .identifier,
              tokens[index - 1].text == "=",
              tokens[index + 1].text == ";" else { return false }
        let preceding = index >= body.lowerBound + 4
            ? tokens[index - 4].text : "{"
        return preceding == "{" || preceding == ";"
    }

    /// Passing the stage input to an unknown call could bind it to `out` or
    /// `inout`. Constructors create a value, so they are the only admitted
    /// enclosing calls for this first bounded profile.
    private static func safeCallContext(
        _ index: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        let constructors: Set<String> = [
            "float", "vec2", "vec3", "vec4",
            "int", "ivec2", "ivec3", "ivec4",
            "uint", "uvec2", "uvec3", "uvec4",
            "bool", "bvec2", "bvec3", "bvec4",
            "mat2", "mat3", "mat4",
        ]
        var closedParentheses = 0
        guard index > body.lowerBound else { return true }
        for cursor in stride(from: index - 1, through: body.lowerBound, by: -1) {
            let text = tokens[cursor].text
            if text == ")" {
                closedParentheses += 1
                continue
            }
            if text == "(" {
                if closedParentheses > 0 {
                    closedParentheses -= 1
                    continue
                }
                guard cursor > body.lowerBound,
                      tokens[cursor - 1].kind == .identifier else { continue }
                return constructors.contains(tokens[cursor - 1].text)
            }
            if closedParentheses == 0, [";", "{", "}"].contains(text) {
                return true
            }
        }
        return true
    }

    private static func mainBody(
        in tokens: [SceneAuthoredShaderToken]
    ) -> Range<Int>? {
        let candidates = tokens.indices.filter { index in
            index + 4 < tokens.count
                && tokens[index].text == "void"
                && tokens[index + 1].text == "main"
                && tokens[index + 2].text == "("
                && tokens[index + 3].text == ")"
                && tokens[index + 4].text == "{"
        }
        guard candidates.count == 1, let start = candidates.first else { return nil }
        var depth = 0
        for index in (start + 4)..<tokens.count {
            if tokens[index].text == "{" { depth += 1 }
            if tokens[index].text == "}" {
                depth -= 1
                if depth == 0 { return (start + 4)..<(index + 1) }
            }
        }
        return nil
    }

    private static func functionBodies(
        in tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var index = 0
        while index + 4 < tokens.count {
            guard tokens[index].kind == .identifier,
                  tokens[index + 1].kind == .identifier,
                  tokens[index + 2].text == "(" else {
                index += 1
                continue
            }
            var parenthesisDepth = 0
            var close: Int?
            for cursor in (index + 2)..<tokens.count {
                if tokens[cursor].text == "(" { parenthesisDepth += 1 }
                if tokens[cursor].text == ")" {
                    parenthesisDepth -= 1
                    if parenthesisDepth == 0 { close = cursor; break }
                }
            }
            guard let close, close + 1 < tokens.count,
                  tokens[close + 1].text == "{" else {
                index += 1
                continue
            }
            var braceDepth = 0
            var end: Int?
            for cursor in (close + 1)..<tokens.count {
                if tokens[cursor].text == "{" { braceDepth += 1 }
                if tokens[cursor].text == "}" {
                    braceDepth -= 1
                    if braceDepth == 0 { end = cursor; break }
                }
            }
            guard let end else { return [] }
            result.append((close + 1)..<(end + 1))
            index = end + 1
        }
        return result
    }
}

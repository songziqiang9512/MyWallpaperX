import Foundation

/// Source-proven stage linking for mismatched floating-vector declarations.
/// Both directions require a fully initialized vertex prefix and fragment
/// reads confined to it. A wider fragment declaration permits only explicit
/// component reads; no value conversion or suffix synthesis occurs.
nonisolated enum SceneAuthoredShaderVaryingPrefixLink {
    enum Direction: Equatable {
        /// The vertex stage publishes a wider value and the fragment stage
        /// consumes its leading prefix.  Bare fragment references are lowered
        /// to the proven prefix by the emitter.
        case vertexWider
        /// The vertex stage publishes the complete value while the authored
        /// fragment declaration is wider.  Only component reads that fit the
        /// vertex value are admitted; no suffix is synthesized.
        case fragmentDeclarationWider
    }

    struct Fact {
        let name: String
        let vertexWidth: Int
        let fragmentWidth: Int
        let requiredComponents: String
        let wholeFragmentReferences: Set<SceneAuthoredShaderToken>
        let direction: Direction
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
            fragmentFunctionBodies: fragment.functions.map(\.bodyRange),
            fragmentFunctionNames: Set(fragment.functions.map(\.name))
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
        let fragmentFunctions = functionDefinitions(in: fragment.tokens)
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
            fragmentFunctionBodies: fragmentFunctions.map(\.body),
            fragmentFunctionNames: Set(fragmentFunctions.map(\.name))
        )
    }

    static func rewriteWholeFragmentReferences(
        _ source: String,
        facts: [String: Fact]
    ) -> String {
        var result = source
        for fact in facts.values.sorted(by: { $0.name > $1.name }) {
            guard fact.direction == .vertexWider,
                  !fact.wholeFragmentReferences.isEmpty else { continue }
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
        fragmentFunctionBodies: [Range<Int>],
        fragmentFunctionNames: Set<String>
    ) -> Fact? {
        guard let vertexMain, (2 ... 4).contains(vertexWidth),
              (2 ... 4).contains(fragmentWidth), vertexWidth <= 4 else {
            return nil
        }
        if fragmentWidth > vertexWidth {
            return proveFragmentDeclarationWider(
                name: name,
                vertexWidth: vertexWidth,
                fragmentWidth: fragmentWidth,
                vertexTokens: vertexTokens,
                vertexMain: vertexMain,
                vertexFunctionBodies: vertexFunctionBodies,
                fragmentTokens: fragmentTokens,
                fragmentFunctionBodies: fragmentFunctionBodies,
                fragmentFunctionNames: fragmentFunctionNames
            )
        }
        guard fragmentWidth < vertexWidth else { return nil }
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
                          previous != "return",
                          index + 3 >= body.upperBound || ![
                              "=", "+=", "-=", "*=", "/=", "++", "--", "[",
                          ].contains(fragmentTokens[index + 3].text),
                          safeCallContext(
                              index,
                              tokens: fragmentTokens,
                              body: body,
                              functionNames: fragmentFunctionNames
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
                        index,
                        tokens: fragmentTokens,
                        body: body,
                        functionNames: fragmentFunctionNames
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
            wholeFragmentReferences: whole,
            direction: .vertexWider
        )
    }

    /// Proves the reverse shape seen in a small set of authored shaders: the
    /// fragment declaration is wider than the vertex output, but every live
    /// fragment use is a read-only component swizzle within the vertex width.
    /// This is deliberately stricter than a language-level implicit conversion:
    /// whole-value reads, suffix/index/assignment uses, local shadowing and
    /// unknown or mutable calls are rejected.  The proof is source-only and
    /// does not inspect effect, layer, sample, path, or identity names.
    private static func proveFragmentDeclarationWider(
        name: String,
        vertexWidth: Int,
        fragmentWidth: Int,
        vertexTokens: [SceneAuthoredShaderToken],
        vertexMain: Range<Int>,
        vertexFunctionBodies: [Range<Int>],
        fragmentTokens: [SceneAuthoredShaderToken],
        fragmentFunctionBodies: [Range<Int>],
        fragmentFunctionNames: Set<String>
    ) -> Fact? {
        guard vertexWidth < fragmentWidth,
              vertexWidth >= 2,
              fragmentWidth <= 4,
              !vertexMain.contains(where: { vertexTokens[$0].text == "return" }),
              !vertexFunctionBodies.contains(where: { body in
                  body != vertexMain && body.contains {
                      vertexTokens[$0].text == name
                  }
              }),
              !hasFunctionParameter(named: name, in: fragmentTokens) else {
            return nil
        }

        // The vertex value is the complete source of the linked prefix.  Reuse
        // the same all-path, single-writer check as the forward proof, with the
        // published width (rather than the fragment declaration width).
        let required = String("xyzw".prefix(vertexWidth))
        let requiredSet = Set(required)
        var depth = 0
        var assignments = 0
        var initializedComponents: Set<Character> = []
        for index in vertexMain {
            let text = vertexTokens[index].text
            if text == "{" { depth += 1 }
            defer { if text == "}" { depth -= 1 } }
            guard text == name else { continue }
            guard !isLocalDeclaration(index, tokens: vertexTokens) else {
                return nil
            }
            let assigned: Set<Character>
            if index + 1 < vertexMain.upperBound,
               vertexTokens[index + 1].text == "=" {
                assigned = requiredSet
            } else if index + 3 < vertexMain.upperBound,
                      vertexTokens[index + 1].text == ".",
                      vertexTokens[index + 2].kind == .identifier,
                      vertexTokens[index + 3].text == "=" {
                let swizzle = vertexTokens[index + 2].text
                guard !swizzle.isEmpty, swizzle.count <= 4 else { return nil }
                let components = Set(swizzle.map(canonicalComponent))
                guard components.count == swizzle.count,
                      components.isSubset(of: requiredSet) else { return nil }
                assigned = components
            } else {
                return nil
            }
            guard depth == 1,
                  isUnconditionalVertexAssignment(
                      index,
                      tokens: vertexTokens,
                      body: vertexMain
                  ),
                  initializedComponents.isDisjoint(with: assigned) else {
                return nil
            }
            initializedComponents.formUnion(assigned)
            assignments += 1
        }
        guard assignments > 0, initializedComponents == requiredSet else {
            return nil
        }

        var componentUses = 0
        let componentLimit = Set("xyzw".prefix(vertexWidth))
        for body in fragmentFunctionBodies {
            // A same-named local in any body makes lexical ownership
            // ambiguous.  Reject the whole proof instead of guessing scope.
            guard !hasLocalDeclaration(named: name, in: body, tokens: fragmentTokens)
            else { return nil }
            for index in body where fragmentTokens[index].text == name {
                guard !isLocalDeclaration(index, tokens: fragmentTokens),
                      index + 2 < body.upperBound,
                      fragmentTokens[index + 1].text == ".",
                      fragmentTokens[index + 2].kind == .identifier,
                      index == body.lowerBound
                          || fragmentTokens[index - 1].text != "." else {
                    return nil
                }
                let swizzle = fragmentTokens[index + 2].text
                guard !swizzle.isEmpty,
                      swizzle.count <= 4,
                      swizzle.allSatisfy({ component in
                          componentLimit.contains(canonicalComponent(component))
                      }) else { return nil }
                let after = index + 3
                guard after >= body.upperBound || ![
                    ".", "[", "=", "+=", "-=", "*=", "/=", "%=", "++", "--",
                ].contains(fragmentTokens[after].text),
                index == body.lowerBound || ![
                    "return", "++", "--",
                ].contains(fragmentTokens[index - 1].text),
                isReverseComponentReadOnlyUse(
                    swizzleEnd: after,
                    tokens: fragmentTokens,
                    body: body
                ),
                safeReverseComponentCallContext(
                    index,
                    tokens: fragmentTokens,
                    body: body,
                    functionNames: fragmentFunctionNames
                ) else { return nil }
                componentUses += 1
            }
        }
        guard componentUses > 0 else { return nil }
        return .init(
            name: name,
            vertexWidth: vertexWidth,
            fragmentWidth: fragmentWidth,
            requiredComponents: required,
            wholeFragmentReferences: [],
            direction: .fragmentDeclarationWider
        )
    }

    private static func isUnconditionalVertexAssignment(
        _ index: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        let controlWords: Set<String> = [
            "if", "else", "for", "while", "switch", "case", "default", "do",
        ]
        var cursor = index
        while cursor > body.lowerBound {
            cursor -= 1
            let text = tokens[cursor].text
            if [";", "{", "}"].contains(text) { return true }
            if controlWords.contains(text) { return false }
        }
        return true
    }

    private static func isReverseComponentReadOnlyUse(
        swizzleEnd: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        var cursor = swizzleEnd
        var nestedClosures = 0
        while cursor < body.upperBound {
            let text = tokens[cursor].text
            if text == ")" {
                nestedClosures += 1
                cursor += 1
                continue
            }
            if nestedClosures > 0 {
                if ["=", "+=", "-=", "*=", "/=", "%=", "++", "--", ".", "[", "]"].contains(text) {
                    return false
                }
                return true
            }
            return !["=", "+=", "-=", "*=", "/=", "%=", "++", "--", ".", "[", "]"].contains(text)
        }
        return true
    }

    private static func canonicalComponent(_ value: Character) -> Character {
        switch value {
        case "r": return "x"
        case "g": return "y"
        case "b": return "z"
        case "a": return "w"
        default: return value
        }
    }

    private static func hasLocalDeclaration(
        named name: String,
        in body: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        body.contains { index in
            var typeIndex = index
            if tokens[typeIndex].text == "const" { typeIndex += 1 }
            return typeIndex + 1 < body.upperBound
                && SceneAuthoredShaderValueType(
                    authoredName: tokens[typeIndex].text
                ) != nil
                && tokens[typeIndex + 1].text == name
        }
    }

    private static func hasFunctionParameter(
        named name: String,
        in tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        var index = 0
        while index + 3 < tokens.count {
            guard tokens[index].kind == .identifier,
                  tokens[index + 1].kind == .identifier,
                  tokens[index + 2].text == "(" else {
                index += 1
                continue
            }
            guard let close = SceneAuthoredShaderVectorConversion
                .matchingParenthesis(tokens: tokens, opening: index + 2) else {
                return true
            }
            if (index + 3..<close).contains(where: { cursor in
                guard tokens[cursor].text == name else { return false }
                let previous = cursor > index + 3
                    ? tokens[cursor - 1].text : ""
                if SceneAuthoredShaderValueType(authoredName: previous) != nil {
                    return true
                }
                return cursor > index + 4
                    && ["const", "in", "out", "inout"].contains(previous)
                    && SceneAuthoredShaderValueType(
                        authoredName: tokens[cursor - 2].text
                    ) != nil
            }) {
                return true
            }
            index = close + 1
        }
        return false
    }

    /// Reverse-prefix reads may occur in pure arithmetic built-ins (the B5
    /// shader uses `step`, `min`, `max`, and `mix`).  User-defined calls remain
    /// closed unless they are texture samples already proven value-only by the
    /// shared emitter contract.
    private static func safeReverseComponentCallContext(
        _ index: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>,
        functionNames: Set<String>
    ) -> Bool {
        let constructors: Set<String> = [
            "float", "vec2", "vec3", "vec4",
            "int", "ivec2", "ivec3", "ivec4",
            "uint", "uvec2", "uvec3", "uvec4",
            "bool", "bvec2", "bvec3", "bvec4",
            "mat2", "mat3", "mat4",
        ]
        let pureBuiltins: Set<String> = [
            "abs", "acos", "asin", "atan", "ceil", "clamp", "cos", "cross",
            "degrees", "distance", "dot", "exp", "exp2", "floor", "fract",
            "inversesqrt", "length", "log", "log2", "max", "min", "mix",
            "mod", "normalize", "pow", "radians", "reflect", "round", "sign",
            "sin", "smoothstep", "sqrt", "step", "tan", "trunc",
        ]
        guard index > body.lowerBound else { return true }

        // Walk from the beginning of the function body so nested calls cannot
        // hide an unsafe outer call (for example `unknown(vec2(feedback.x))`).
        // Parentheses that are ordinary grouping expressions have no callable
        // identifier immediately before them and therefore impose no extra
        // contract.
        var openParentheses: [Int] = []
        for cursor in body.lowerBound..<index {
            switch tokens[cursor].text {
            case "(": openParentheses.append(cursor)
            case ")":
                guard !openParentheses.isEmpty else { return false }
                openParentheses.removeLast()
            default: break
            }
        }
        for opening in openParentheses {
            guard opening > body.lowerBound,
                  tokens[opening - 1].kind == .identifier else {
                continue
            }
            let function = tokens[opening - 1].text
            if !functionNames.contains(function),
               constructors.contains(function) || pureBuiltins.contains(function) {
                continue
            }
            guard let expectedArgumentCount = SceneAuthoredShaderMetalEmitter
                      .textureSampleArgumentCount(
                          function,
                          functionNames: functionNames
                      ),
                  let closing = SceneAuthoredShaderVectorConversion
                      .matchingParenthesis(tokens: tokens, opening: opening),
                  closing < body.upperBound,
                  let arguments = SceneAuthoredShaderMetalEmitter
                      .textureSampleArguments(
                          tokens: tokens,
                          opening: opening,
                          closing: closing
                      ),
                  arguments.count == expectedArgumentCount,
                  arguments[1].contains(index) else { return false }
        }
        return true
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
    /// `inout`. Constructors create a value. The shared frontend's exact
    /// texture-sampling built-ins also consume their coordinate argument as a
    /// value; no other argument or call context is admitted here.
    private static func safeCallContext(
        _ index: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>,
        functionNames: Set<String>
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
                let function = tokens[cursor - 1].text
                if constructors.contains(function) { return true }
                guard let expectedArgumentCount = SceneAuthoredShaderMetalEmitter
                          .textureSampleArgumentCount(
                              function,
                              functionNames: functionNames
                          ),
                      let closing = SceneAuthoredShaderVectorConversion
                          .matchingParenthesis(tokens: tokens, opening: cursor),
                      closing < body.upperBound,
                      let arguments = SceneAuthoredShaderMetalEmitter
                          .textureSampleArguments(
                              tokens: tokens,
                              opening: cursor,
                              closing: closing
                          ),
                      arguments.count == expectedArgumentCount,
                      arguments[1].contains(index) else { return false }
                return true
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
        functionDefinitions(in: tokens).map(\.body)
    }

    private static func functionDefinitions(
        in tokens: [SceneAuthoredShaderToken]
    ) -> [(name: String, body: Range<Int>)] {
        var result: [(name: String, body: Range<Int>)] = []
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
            result.append((tokens[index + 1].text, (close + 1)..<(end + 1)))
            index = end + 1
        }
        return result
    }
}

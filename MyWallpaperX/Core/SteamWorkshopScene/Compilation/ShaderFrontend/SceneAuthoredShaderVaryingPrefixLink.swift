import Foundation

/// Source-proven stage linking for mismatched floating-vector declarations.
/// Both directions require a fully initialized vertex prefix and fragment
/// reads confined to it. A wider fragment declaration permits only explicit
/// component reads; no value conversion or suffix synthesis occurs.
/// A vertex-wider link additionally admits member mutations inside main:
/// the authored dialect treats the stage input as a mutable working
/// register there, and both consuming backends hand main a mutable local
/// copy of the linked value, so the mutation never rewrites the link.
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
        /// Components the fragment reads but the active variant's vertex never
        /// writes. The proof is only valid when the emitting backend actually
        /// zero-fills exactly these components; a consumer that cannot apply
        /// the fill must reject the shader instead of emitting it.
        let zeroInitializedComponents: Set<Character>
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
            fragmentMain: fragment.functions.first { $0.name == "main" }?
                .bodyRange,
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
            fragmentMain: fragmentFunctions.first { $0.name == "main" }?
                .body,
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

    /// Applies the zero-fill promise carried by the facts: appends one
    /// unconditional top-level assignment per promised component at the end
    /// of the vertex main body. Returns nil when main cannot be located
    /// uniquely — the caller must reject the shader in that case, the same
    /// fail-closed contract as the proof itself.
    static func appendVertexZeroFill(
        _ source: String,
        facts: [String: Fact]
    ) -> String? {
        let promised = facts.values.filter { !$0.zeroInitializedComponents.isEmpty }
        guard !promised.isEmpty else { return source }
        let regex = try! NSRegularExpression(pattern: #"\bvoid\s+main\s*\(\s*\)\s*\{"#)
        let range = NSRange(source.startIndex..., in: source)
        guard regex.numberOfMatches(in: source, range: range) == 1,
              let match = regex.firstMatch(in: source, range: range),
              let openRange = Range(match.range, in: source) else {
            return nil
        }
        var depth = 0
        var bodyEnd: String.Index?
        var cursor = openRange.upperBound
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                if depth == 0 {
                    bodyEnd = cursor
                    break
                }
                depth -= 1
            }
            cursor = source.index(after: cursor)
        }
        guard let bodyEnd else { return nil }
        let componentOrder = Array("xyzw")
        let statements = promised.sorted(by: { $0.name < $1.name }).map { fact -> String in
            let components = componentOrder
                .filter { fact.zeroInitializedComponents.contains($0) }
                .map(String.init)
                .joined()
            let value: String
            switch fact.zeroInitializedComponents.count {
            case 1: value = "0.0"
            case let width: value = "vec\(width)(\(Array(repeating: "0.0", count: width).joined(separator: ", ")))"
            }
            return "// MWX zero-fill: the active variant never writes these components.\n"
                + "\(fact.name).\(components) = \(value);"
        }
        return source[..<bodyEnd]
            + statements.joined(separator: "\n") + "\n"
            + source[bodyEnd...]
    }

    private static func prove(
        name: String,
        vertexWidth: Int,
        fragmentWidth: Int,
        vertexTokens: [SceneAuthoredShaderToken],
        vertexMain: Range<Int>?,
        vertexFunctionBodies: [Range<Int>],
        fragmentTokens: [SceneAuthoredShaderToken],
        fragmentMain: Range<Int>?,
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
              }),
              !hasFunctionParameter(named: name, in: fragmentTokens)
        else { return nil }
        let required = String("xyzw".prefix(fragmentWidth))
        let publishedComponents = Set("xyzw".prefix(vertexWidth))

        var whole: Set<SceneAuthoredShaderToken> = []
        var readComponents: Set<Character> = []
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
                    // Any component read inside the published value is backed
                    // by an initialized component; the declared prefix only
                    // decides what a bare reference means.
                    guard index + 2 < body.upperBound,
                          fragmentTokens[index + 2].kind == .identifier,
                          fragmentTokens[index + 2].text.allSatisfy({
                              publishedComponents.contains(canonicalComponent($0))
                          }),
                          previous != "return",
                          safeReadOnlyCallContext(
                              index,
                              tokens: fragmentTokens,
                              body: body,
                              functionNames: fragmentFunctionNames
                          ) else { return nil }
                    let swizzle = fragmentTokens[index + 2]
                        .text.map(canonicalComponent)
                    let following = index + 3 < body.upperBound
                        ? fragmentTokens[index + 3].text : nil
                    if let following, isMemberMutationOperator(following) {
                        // The authored dialect lets main treat the linked
                        // value as a mutable working register (the real
                        // sine_wave shape writes `v_TexCoord.x += ...`).
                        // Both consumers hand main a mutable local copy of
                        // the stage input — the bounded emitter passes its
                        // context struct by value and the generic normalizer
                        // localizes main-body mutations before emission — so
                        // a member mutation inside main only ever reads and
                        // rewrites that copy. Mutations outside main have no
                        // localizing consumer (a helper would mutate its own
                        // by-value argument), and mutations of components
                        // beyond the declared fragment prefix stay rejected.
                        guard body == fragmentMain,
                              swizzle.allSatisfy({ required.contains($0) })
                        else { return nil }
                    } else {
                        guard isComponentReadOnlyUse(
                            start: index, end: index + 3,
                            tokens: fragmentTokens, body: body
                        ) else { return nil }
                    }
                    readComponents.formUnion(swizzle)
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
                    guard isComponentReadOnlyUse(
                        start: index, end: index + 1,
                        tokens: fragmentTokens, body: body
                    ), safeReadOnlyCallContext(
                        index,
                        tokens: fragmentTokens,
                        body: body,
                        functionNames: fragmentFunctionNames
                    ) else { return nil }
                    whole.insert(fragmentTokens[index])
                    readComponents.formUnion(required)
                }
            }
        }

        // Vertex side: every component the fragment reads must be written
        // exactly once, unconditionally, at main's top level.  A whole-value
        // assignment covers the published width; authored shaders may instead
        // partition it across component assignments (`v_TexCoord.xy = ...`
        // then `v_TexCoord.zw = ...`), the same shape the fragment-wider proof
        // accepts.  A declaration wider than the initialized set stays legal as
        // long as no live fragment read reaches the uninitialized part.
        var depth = 0
        var assignments = 0
        var initializedComponents: Set<Character> = []
        for index in vertexMain {
            let text = vertexTokens[index].text
            if text == "{" { depth += 1 }
            defer { if text == "}" { depth -= 1 } }
            guard text == name else { continue }
            guard !isLocalDeclaration(index, tokens: vertexTokens) else { return nil }
            let assigned: Set<Character>
            if index + 1 < vertexMain.upperBound,
               vertexTokens[index + 1].text == "=" {
                assigned = publishedComponents
            } else if index + 3 < vertexMain.upperBound,
                      vertexTokens[index + 1].text == ".",
                      vertexTokens[index + 2].kind == .identifier,
                      vertexTokens[index + 3].text == "=" {
                let swizzle = vertexTokens[index + 2].text
                guard !swizzle.isEmpty, swizzle.count <= 4 else { return nil }
                let components = Set(swizzle.map(canonicalComponent))
                guard components.count == swizzle.count,
                      components.isSubset(of: publishedComponents) else { return nil }
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
        // Reads beyond the initialized set are admitted under a zero-fill
        // promise: the Fact names exactly the unwritten components and the
        // consuming backend must append their zero assignments (see
        // appendVertexZeroFill). A vertex that never writes the varying at
        // all is still rejected — at least one authored assignment is
        // required. The presence check below keeps shapes that only read
        // beyond-prefix components without a whole or literal-prefix use
        // rejected.
        guard assignments > 0 else {
            return nil
        }
        let zeroInitializedComponents = readComponents.subtracting(initializedComponents)
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
            zeroInitializedComponents: zeroInitializedComponents,
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
                isComponentReadOnlyUse(
                    start: index, end: after,
                    tokens: fragmentTokens,
                    body: body
                ),
                safeReadOnlyCallContext(
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
            zeroInitializedComponents: [],
            direction: .fragmentDeclarationWider
        )
    }

    /// Compound and plain member-assignment operators that make the linked
    /// value a mutable working register inside main. Increment, decrement,
    /// and subscript targets are deliberately absent: no admitted corpus
    /// shape needs them and each would widen this proof's semantics.
    private static func isMemberMutationOperator(_ text: String) -> Bool {
        ["=", "+=", "-=", "*=", "/=", "%="].contains(text)
    }

    private static func isUnconditionalVertexAssignment(
        _ index: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        let controlWords: Set<String> = [
            "if", "else", "for", "while", "switch", "case", "default", "do",
        ]
        // Conditional-expression and short-circuit operators keep the write
        // conditional, so they revoke the proof exactly like a control word:
        // `(a) ? (v = b) : c` and `(a) && (v = b)` do not always execute.
        let conditionalOperators: Set<String> = ["?", ":", "&&", "||"]
        var cursor = index
        while cursor > body.lowerBound {
            cursor -= 1
            let text = tokens[cursor].text
            if [";", "{", "}"].contains(text) { return true }
            if controlWords.contains(text) || conditionalOperators.contains(text) {
                return false
            }
        }
        return true
    }

    /// Parentheses preserve an lvalue; a constructor/call creates a value.
    /// Peel only grouping around this exact reference before checking writes
    /// and indexing, so `(value.xy) += ...` cannot masquerade as a pure read.
    private static func isComponentReadOnlyUse(
        start: Int,
        end: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        var lower = start
        var upper = end
        while lower > body.lowerBound, upper < body.upperBound,
              tokens[lower - 1].text == "(", tokens[upper].text == ")" {
            if lower >= body.lowerBound + 2,
               tokens[lower - 2].kind == .identifier,
               tokens[lower - 2].text != "return" { break }
            lower -= 1
            upper += 1
        }
        return (lower == body.lowerBound
            || !["return", "++", "--"].contains(tokens[lower - 1].text))
            && (upper == body.upperBound
            || !["=", "+=", "-=", "*=", "/=", "%=", "++", "--", ".", "[", "]"]
                .contains(tokens[upper].text))
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
            guard let close = SceneAuthoredShaderTokenScanner
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

    /// Prefix reads in either direction may occur in unshadowed constructors,
    /// pure arithmetic built-ins, or the exact coordinate argument of texture
    /// samples already proven value-only by the shared emitter contract. Every
    /// enclosing call must satisfy that contract, including outer calls around
    /// a constructor or texture sample.
    private static func safeReadOnlyCallContext(
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
            "mod", "normalize", "pow", "radians", "reflect", "round", "saturate", "sign",
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
            // Control-statement parentheses group a condition, not a call.
            if ["if", "for", "while", "switch"].contains(function) { continue }
            if !functionNames.contains(function),
               constructors.contains(function) || pureBuiltins.contains(function) {
                continue
            }
            guard let expectedArgumentCount = SceneAuthoredShaderMetalEmitter
                      .textureSampleArgumentCount(
                          function,
                          functionNames: functionNames
                      ),
                  let closing = SceneAuthoredShaderTokenScanner
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

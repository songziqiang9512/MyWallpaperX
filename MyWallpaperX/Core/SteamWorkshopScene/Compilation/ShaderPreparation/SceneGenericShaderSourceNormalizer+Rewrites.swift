import Foundation

extension SceneGenericShaderSourceNormalizer {
    static func rewriteAssignmentVectorConversions(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> String {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("#version")
                ? "" : line
        }.joined(separator: "\n")
        let lexer = SceneAuthoredShaderLexer.lex(source: analysisSource, stage: stage)
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: lexer,
            stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit else {
            return normalized
        }
        let boundaries = SceneAuthoredShaderVectorConversion.assignmentBoundaries(
            in: unit.tokens,
            unit: unit
        )
        guard !boundaries.starts.isEmpty || !boundaries.ends.isEmpty else {
            return normalized
        }

        var lineStarts = [0]
        var scalarOffset = 0
        for scalar in normalized.unicodeScalars {
            scalarOffset += 1
            if scalar == "\n" { lineStarts.append(scalarOffset) }
        }
        func offset(for tokenIndex: Int) -> Int? {
            guard unit.tokens.indices.contains(tokenIndex) else { return nil }
            let token = unit.tokens[tokenIndex]
            guard token.line > 0, token.line <= lineStarts.count else { return nil }
            return lineStarts[token.line - 1] + token.column - 1
        }
        var insertions: [(offset: Int, text: String)] = []
        for (tokenIndex, count) in boundaries.starts {
            guard count > 0, let value = offset(for: tokenIndex) else { continue }
            insertions.append((value, String(repeating: "(", count: count)))
        }
        for (tokenIndex, suffixes) in boundaries.ends {
            guard !suffixes.isEmpty, let value = offset(for: tokenIndex) else { continue }
            insertions.append((value, suffixes.map { ").\($0)" }.joined()))
        }
        guard !insertions.isEmpty else { return normalized }
        var result = normalized
        for insertion in insertions.sorted(by: { $0.offset > $1.offset }) {
            guard insertion.offset <= result.unicodeScalars.count else { return normalized }
            let scalarIndex = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: insertion.offset
            )
            guard let index = String.Index(scalarIndex, within: result) else {
                return normalized
            }
            result.insert(contentsOf: insertion.text, at: index)
        }
        return result
    }

    /// Vulkan GLSL requires an integer array subscript, while the authored
    /// shader dialect accepts a float scalar used as an index (the common
    /// audio-bar shape computes a bin with `floor`). Preserve the authored
    /// value and add only the target-language conversion when both sides are
    /// structurally proven: a fixed-size float array and an unambiguous float
    /// scalar identifier. Unknown expressions, dynamic arrays, and ambiguous
    /// shadowed names remain untouched and therefore fail closed in glslang.
    static func rewriteFloatArrayIndices(_ source: String) -> String {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let masked = lexicalMask(normalized)
        let arrayMatcher = try! NSRegularExpression(pattern:
            #"\b(?:uniform\s+|const\s+)?float\s+([A-Za-z_][A-Za-z0-9_]*)\s*\[\s*[0-9]+\s*\]"#
        )
        let nameMatcher = try! NSRegularExpression(pattern:
            #"\b(?:const\s+)?float\s+([A-Za-z_][A-Za-z0-9_]*)\b"#
        )
        let integerMatcher = try! NSRegularExpression(pattern:
            #"\b(?:const\s+)?(?:int|uint)\s+([A-Za-z_][A-Za-z0-9_]*)\b"#
        )
        let functionMatcher = try! NSRegularExpression(pattern:
            #"\b(?:bool|int|uint|float|vec[2-4]|ivec[2-4]|uvec[2-4])\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#
        )
        let declarationRange = NSRange(masked.startIndex..., in: masked)
        let arrayNames = Set(arrayMatcher.matches(in: masked, range: declarationRange)
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: masked) else {
                    return nil
                }
                return String(masked[range])
            })
        guard !arrayNames.isEmpty else { return normalized }
        let floatNames = Set(nameMatcher.matches(in: masked, range: declarationRange)
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: masked) else {
                    return nil
                }
                return String(masked[range])
            })
        let integerNames = Set(integerMatcher.matches(in: masked, range: declarationRange)
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: masked) else {
                    return nil
                }
                return String(masked[range])
            })
        let functionNames = Set(functionMatcher.matches(in: masked, range: declarationRange)
            .compactMap { match -> String? in
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: masked) else {
                    return nil
                }
                return String(masked[range])
            })
        let eligibleNames = floatNames
            .subtracting(integerNames)
            .subtracting(functionNames)
        guard !eligibleNames.isEmpty else { return normalized }

        let accessMatcher = try! NSRegularExpression(pattern:
            #"\b([A-Za-z_][A-Za-z0-9_]*)\s*\[\s*([A-Za-z_][A-Za-z0-9_]*)\s*\]"#
        )
        var result = normalized
        for match in accessMatcher.matches(in: masked, range: declarationRange).reversed() {
            guard match.numberOfRanges > 2,
                  let arrayRange = Range(match.range(at: 1), in: masked),
                  let indexRange = Range(match.range(at: 2), in: masked) else {
                continue
            }
            let arrayName = String(masked[arrayRange])
            let indexName = String(masked[indexRange])
            guard arrayNames.contains(arrayName), eligibleNames.contains(indexName),
                  !hasMemberPrefix(before: arrayRange.lowerBound, in: masked),
                  let replacementRange = Range(match.range(at: 2), in: result) else {
                continue
            }
            result.replaceSubrange(
                replacementRange,
                with: "int(\(indexName))"
            )
        }
        return result
    }

    static func hasMemberPrefix(
        before location: String.Index,
        in source: String
    ) -> Bool {
        source[..<location].last(where: { !$0.isWhitespace }) == "."
    }

    /// Comment- and label-insensitive word presence. The stage-shape admission
    /// below deliberately lets a comment-only declaration pass, so this check
    /// must run on the masked view while the rest of the family matches the
    /// raw source.
    static func maskedContainsWord(_ word: String, in source: String) -> Bool {
        SceneShaderSourceTextFacts.containsWord(word, in: lexicalMask(source))
    }

    /// Return a same-length view containing only executable source. Keeping
    /// offsets stable lets regex rewrites apply to the original source while
    /// ignoring comments and quoted labels.
    static func lexicalMask(_ source: String) -> String {
        var inBlockComment = false
        return source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let lexical = SceneShaderLexicalScanner.scan(
                    String(line),
                    inBlockComment: &inBlockComment
                )
                return lexical.segments.map { segment -> String in
                    switch segment.kind {
                    case .code:
                        return segment.text
                    case .quoted, .blockComment, .lineComment:
                        return String(repeating: " ", count: segment.text.utf16.count)
                    }
                }.joined()
            }
            .joined(separator: "\n")
    }

    /// The authored sampler accepts a float2 coordinate, while the common
    /// shader ABI exposes several texture-coordinate varyings as vec4. Apply
    /// the existing narrowing rule only when the coordinate is a declared
    /// vector identifier; complex expressions remain untouched and fail closed
    /// in the helper compiler.
    static func rewriteTextureCoordinates(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\btexSample2D\(\s*(g_Texture[0-7])\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#
        )
        var result = source
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let textureRange = Range(match.range(at: 1), in: source),
                  let coordinateRange = Range(match.range(at: 2), in: source),
                  let coordinateShape = shapes[String(source[coordinateRange])],
                  ["vec3", "vec4"].contains(coordinateShape.type),
                  let fullRange = Range(match.range, in: result) else {
                continue
            }
            let texture = String(source[textureRange])
            let coordinate = String(source[coordinateRange])
            result.replaceSubrange(
                fullRange,
                with: "texSample2D(\(texture), \(coordinate).xy)"
            )
        }
        return result
    }

    /// Authored effects sometimes carry a vec3/vec4 coordinate varying but use
    /// it as a vec2 in arithmetic. GLSL does not permit implicit truncation;
    /// preserve the authored coordinate contract by narrowing only the vector
    /// operand of an explicitly vec2 expression.
    static func rewriteVector2ArithmeticOperands(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let names = shapes.compactMap { name, shape in
            ["vec3", "vec4"].contains(shape.type) ? name : nil
        }
        guard !names.isEmpty else { return source }
        let escaped = names.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let pattern = #"\b("# + escaped + #")\s*([+-])\s*(?:CAST2\([^;\n]*\)|vec2\([^;\n]*\))"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var result = source
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            guard let name = Range(match.range(at: 1), in: source),
                  let full = Range(match.range, in: result) else { continue }
            let op = String(source[Range(match.range(at: 2), in: source)!])
            let rhs = String(source[full]).drop(while: { $0 != op.first! }).dropFirst()
            result.replaceSubrange(full, with: "\(source[name]).xy \(op)\(rhs)")
        }
        return result
    }

    static func rewriteScalarVectorAssignments(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\bfloat\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*([^;]+);"#
        )
        let vectorNames = shapes.compactMap { name, shape in
            ["vec2", "vec3", "vec4"].contains(shape.type) ? name : nil
        }
        guard !vectorNames.isEmpty else { return source }
        let vectorRegex = try! NSRegularExpression(pattern:
            #"\b(?:"# + vectorNames.map(NSRegularExpression.escapedPattern).joined(separator: "|")
                + #")\b(?!\s*(?:\[[^\]]*\]|\.\s*[xyzwrgba]\b))"#
        )
        let functionCallRegex = try! NSRegularExpression(pattern:
            #"\b[A-Za-z_][A-Za-z0-9_]*\s*\("#
        )
        let scalarResultRegex = try! NSRegularExpression(pattern:
            #"(?:\.\s*[xyzwrgba]|\[[^\]]*\])\s*$"#
        )
        var result = source
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let expressionRange = Range(match.range(at: 1), in: result) else { continue }
            let expression = String(result[expressionRange])
            guard !expression.contains(","),
                  scalarResultRegex.firstMatch(
                    in: expression,
                    range: NSRange(expression.startIndex..., in: expression)
                  ) == nil,
                  functionCallRegex.firstMatch(
                    in: expression,
                    range: NSRange(expression.startIndex..., in: expression)
                  ) == nil,
                  vectorRegex.firstMatch(
                in: expression,
                range: NSRange(expression.startIndex..., in: expression)
            ) != nil,
            !expression.trimmingCharacters(in: .whitespaces).hasPrefix("vec") else { continue }
            result.replaceSubrange(expressionRange, with: "(\(expression)).x")
        }
        return result
    }

    static func rewriteVectorConstructorAssignments(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\b(vec[2-4])\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(vec[2-4])\s*\(([^;]*)\);"#
        )
        var result = source
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let targetRange = Range(match.range(at: 1), in: source),
                  let nameRange = Range(match.range(at: 2), in: source),
                  let sourceRange = Range(match.range(at: 3), in: source),
                  let targetWidth = Int(source[targetRange].dropFirst(3)),
                  let sourceWidth = Int(source[sourceRange].dropFirst(3)),
                  sourceWidth > targetWidth,
                  let argumentsRange = Range(match.range(at: 4), in: source),
                  let range = Range(match.range, in: result) else { continue }
            let target = String(source[targetRange])
            let name = String(source[nameRange])
            let constructor = String(source[sourceRange])
            let arguments = String(source[argumentsRange])
            let suffix = targetWidth == 2 ? ".xy" : ".xyz"
            result.replaceSubrange(
                range,
                with: "\(target) \(name) = \(constructor)(\(arguments))\(suffix);"
            )
        }
        return result
    }

    /// HLSL attribute annotations (`[loop]`, `[unroll]`, `[branch]`, …) are
    /// meaningful to the lenient compilers but are not Vulkan GLSL: glslang
    /// rejects a bare `[identifier]` line with "expecting LEFT_BRACKET".
    /// The annotations carry loop-execution hints only, so dropping them
    /// preserves semantics.
    static func stripHLSLAttributeAnnotations(_ source: String) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\[\s*(?:loop|unroll|branch|flatten|fastopt)\s*\]"#
        )
        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: ""
        )
    }

    /// GLSL ES accepts implicit scalar conversions in some authors' compilers,
    /// while glslang's Vulkan frontend requires an explicit conversion. An
    /// integer target assigned a float-bearing expression (declaration,
    /// plain assignment, or a comparison operand) truncates through
    /// `int(...)` - the same rounding the lenient compilers performed.
    /// Compound assignments keep their ambiguous promotion semantics and
    /// stay fail-closed; the type facts come from the shared declared-type
    /// table so local declarations and shapes are treated alike.
    static func rewriteFloatToIntAssignments(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let (types, conflicted) = declaredScalarVectorTypes(source, shapes: shapes)
        let intNames = types.compactMap { name, type in
            ["int", "uint"].contains(type) && !conflicted.contains(name)
                ? name : nil
        }
        let floatNames = types.compactMap { name, type in
            type == "float" && !conflicted.contains(name) ? name : nil
        }
        let lexical = SceneAuthoredShaderLexer.lex(source: source, stage: .fragment)
        guard lexical.diagnostics.isEmpty, !intNames.isEmpty else { return source }
        let tokens = lexical.tokens

        // A right-hand-side atom carries a float value when it is a float
        // literal, a declared float scalar, or a swizzle member of a declared
        // floating vector.
        func isFloatAtom(_ tokenIndex: Int) -> Bool {
            let token = tokens[tokenIndex]
            if token.kind == .number {
                return token.text.contains(".") || token.text.lowercased().contains("e")
            }
            guard token.kind == .identifier,
                  let type = types[token.text],
                  !conflicted.contains(token.text) else { return false }
            if type == "float" { return true }
            if ["float2", "float3", "float4"].contains(type),
               tokenIndex + 2 < tokens.count,
               tokens[tokenIndex + 1].text == ".",
               tokens[tokenIndex + 2].kind == .identifier,
               ["x", "y", "z", "w", "r", "g", "b", "a"]
                   .contains(tokens[tokenIndex + 2].text) {
                return true
            }
            return false
        }

        var edits: [(offset: Int, length: Int, text: String)] = []
        var lineStarts = [0]
        var running = 0
        for scalar in source.unicodeScalars {
            running += 1
            if scalar == "\n" { lineStarts.append(running) }
        }
        func sourceOffset(_ token: SceneAuthoredShaderToken, after: Bool) -> Int? {
            guard token.line > 0, token.line <= lineStarts.count else { return nil }
            return lineStarts[token.line - 1] + token.column - 1
                + (after ? token.text.unicodeScalars.count : 0)
        }

        for index in tokens.indices where index > 1 && index + 1 < tokens.count {
            guard tokens[index].text == "=",
                  tokens[index - 1].kind == .identifier,
                  let lhsType = types[tokens[index - 1].text],
                  !conflicted.contains(tokens[index - 1].text),
                  ["int", "uint"].contains(lhsType) else { continue }
            var end = index + 1
            var depth = 0
            while end < tokens.count {
                if tokens[end].text == "(" { depth += 1 }
                if tokens[end].text == ")" && depth > 0 { depth -= 1 }
                if tokens[end].text == ";" && depth == 0 { break }
                end += 1
            }
            guard end < tokens.count, index + 1 < end,
                  let startOffset = sourceOffset(tokens[index + 1], after: false),
                  let endOffset = sourceOffset(tokens[end - 1], after: true) else { continue }
            let rhs = (index + 1)..<end
            let rhsHasFloatAtom = rhs.contains { isFloatAtom($0) }
            let single = rhs.lowerBound
            let provablyInteger = rhs.count == 1
                && (tokens[single].kind == .number && !isFloatAtom(single)
                    || tokens[single].kind == .identifier
                        && (types[tokens[single].text] ?? "float") == "int"
                        && !conflicted.contains(tokens[single].text))
            // An explicit int/uint conversion call is the truncation the
            // dedicated discrete-mask and step owners already emit; wrapping
            // it again would double the conversion.
            let explicitConversion = rhs.count >= 3
                && ["int", "uint"].contains(tokens[single].text)
                && tokens[single + 1].text == "("
                && {
                    var depth = 0
                    for position in rhs.dropFirst() {
                        if tokens[position].text == "(" { depth += 1 }
                        if tokens[position].text == ")" {
                            depth -= 1
                            if depth == 0 {
                                return position == rhs.upperBound - 1
                            }
                        }
                    }
                    return false
                }()
            // A top-level comma (multi-declarator) or a nested assignment
            // would corrupt the span rewrite; both stay fail-closed.
            let rhsTopLevelCorrupts = {
                var depth = 0
                for position in rhs {
                    if tokens[position].text == "(" { depth += 1 }
                    if tokens[position].text == ")" { depth -= 1 }
                    if depth == 0, [",", "="].contains(tokens[position].text) {
                        return true
                    }
                }
                return false
            }()
            guard rhsHasFloatAtom, !provablyInteger, !explicitConversion,
                  !rhsTopLevelCorrupts else { continue }
            let lowerIndex = source.unicodeScalars.index(
                source.unicodeScalars.startIndex, offsetBy: startOffset
            )
            let upperIndex = source.unicodeScalars.index(
                source.unicodeScalars.startIndex, offsetBy: endOffset
            )
            edits.append((
                offset: startOffset,
                length: endOffset - startOffset,
                text: "int(\(source[lowerIndex..<upperIndex]))"
            ))
        }
        var result = source
        for edit in edits.sorted(by: { $0.offset > $1.offset }) {
            guard edit.offset + edit.length <= result.unicodeScalars.count else {
                continue
            }
            let lower = result.unicodeScalars.index(
                result.unicodeScalars.startIndex, offsetBy: edit.offset
            )
            let upper = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: edit.offset + edit.length
            )
            result.replaceSubrange(lower..<upper, with: edit.text)
        }

        guard !floatNames.isEmpty else { return result }
        let floatIdentPattern = floatNames.map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        let comparisonRegex = try! NSRegularExpression(pattern:
            #"\b([A-Za-z_][A-Za-z0-9_]*)\s*(<=|>=|<|>)\s*("#
                + floatIdentPattern
                + #")\b"#
        )
        for match in comparisonRegex.matches(
            in: result,
            range: NSRange(result.startIndex..., in: result)
        ).reversed() {
            guard let valueRange = Range(match.range(at: 3), in: result),
                  let fullRange = Range(match.range, in: result) else { continue }
            let value = String(result[valueRange])
            let expression = String(result[fullRange])
            result.replaceSubrange(fullRange, with: expression.replacingOccurrences(of: value, with: "int(\(value))"))
        }
        return result
    }

    /// The unified declared-type table for the source-stage scalar-broadcast
    /// rules: varying/uniform shapes plus lexed local declarations, unified
    /// through the value-type model with conflicting names filtered out.
    static func declaredScalarVectorTypes(
        _ source: String,
        shapes: [String: Shape]
    ) -> (types: [String: String], conflicted: Set<String>) {
        var types: [String: String] = shapes.compactMapValues {
            SceneAuthoredShaderValueType(authoredName: $0.type)?.rawValue
        }
        var conflicted: Set<String> = []
        let lexical = SceneAuthoredShaderLexer.lex(source: source, stage: .fragment)
        guard lexical.diagnostics.isEmpty else { return (types, conflicted) }
        let tokens = lexical.tokens
        for index in tokens.indices.dropLast() {
            guard let valueType = SceneAuthoredShaderValueType(
                authoredName: tokens[index].text
            ), tokens[index + 1].kind == .identifier else { continue }
            let name = tokens[index + 1].text
            if let existing = types[name], existing != valueType.rawValue {
                conflicted.insert(name)
            } else {
                types[name] = valueType.rawValue
            }
        }
        return (types, conflicted)
    }

    /// A declared integer scalar in the first argument of max/min against a
    /// declared vector has no Vulkan GLSL overload (the vector-to-scalar
    /// direction converts implicitly, this one does not). The authored
    /// language broadcasts the scalar, so the scalar is promoted to the
    /// sibling's vector type. Identifier atoms only; the literal form is
    /// owned by `rewriteVectorClampLiteralArguments`. Names whose declared
    /// type is ambiguous (shadowing or conflicting declarations) are skipped.
    /// Owner: this is the source-stage matcher for the scalar-broadcast
    /// shape; the backend canonicalizer owns the typed broadcast family
    /// (`rewriteLiteralBoundBroadcasts`). Retire this rule together with
    /// that family when the backend model covers declared-identifier
    /// operands.
    static func rewriteVectorBuiltInIntFirstOperands(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let (types, conflicted) = declaredScalarVectorTypes(source, shapes: shapes)
        let vectorNames = types.compactMap { name, type in
            ["float2", "float3", "float4", "int2", "int3", "int4",
             "uint2", "uint3", "uint4"].contains(type)
                && !conflicted.contains(name) ? name : nil
        }
        let scalarNames = types.compactMap { name, type in
            ["float", "int", "uint"].contains(type) && !conflicted.contains(name)
                ? name : nil
        }
        guard !vectorNames.isEmpty, !scalarNames.isEmpty else { return source }
        // An authored overload sharing the built-in name owns its call sites.
        let definitions = try! NSRegularExpression(pattern:
            #"\b(?:bool|int|uint|float|[biu]?vec[2-4])\s+(max|min)\s*\("#
        )
        let authoredNames = Set(definitions.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        })
        let regex = try! NSRegularExpression(pattern:
            #"\b(max|min)\(\s*("#
                + scalarNames.map(NSRegularExpression.escapedPattern).joined(separator: "|")
                + #")\s*,\s*("#
                + vectorNames.map(NSRegularExpression.escapedPattern).joined(separator: "|")
                + #")\s*\)"#
        )
        let glslSpelling = [
            "float2": "vec2", "float3": "vec3", "float4": "vec4",
            "int2": "ivec2", "int3": "ivec3", "int4": "ivec4",
            "uint2": "uvec2", "uint3": "uvec3", "uint4": "uvec4",
        ]
        var result = source
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let intRange = Range(match.range(at: 2), in: source),
                  let vectorRange = Range(match.range(at: 3), in: source),
                  let fullRange = Range(match.range, in: result),
                  let vectorType = types[String(source[vectorRange])],
                  let constructor = glslSpelling[vectorType],
                  let scalarType = types[String(source[intRange])]
            else { continue }  // name lists only admit known scalar/vector types
            // A float scalar entering an integer vector would narrow; the
            // authored language is ambiguous there, so it stays fail-closed.
            if scalarType == "float",
               ["int2", "int3", "int4", "uint2", "uint3", "uint4"]
                   .contains(vectorType) {
                continue
            }
            guard !authoredNames.contains(String(source[nameRange])) else { continue }
            result.replaceSubrange(
                fullRange,
                with: "\(source[nameRange])(\(constructor)(\(source[intRange])),"
                    + " \(source[vectorRange]))"
            )
        }
        return result
    }

    /// An integer literal as the first max/min argument has no overload
    /// against a vector sibling and needs an explicit broadcast; against a
    /// float scalar the implicit int-to-float conversion suffices once the
    /// literal is spelled as a float. The broadcast follows the sibling's
    /// declared vector type instead of a hardcoded width; integer-scalar and
    /// unknown siblings are left untouched, and authored overloads owning
    /// the built-in name keep their call sites.
    static func rewriteVectorClampLiteralArguments(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let (types, conflicted) = declaredScalarVectorTypes(source, shapes: shapes)
        let definitions = try! NSRegularExpression(pattern:
            #"\b(?:bool|int|uint|float|[biu]?vec[2-4])\s+(max|min)\s*\("#
        )
        let authoredNames = Set(definitions.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        })
        let glslSpelling = [
            "float2": "vec2", "float3": "vec3", "float4": "vec4",
            "int2": "ivec2", "int3": "ivec3", "int4": "ivec4",
            "uint2": "uvec2", "uint3": "uvec3", "uint4": "uvec4",
        ]
        let regex = try! NSRegularExpression(pattern:
            #"\b(max|min)\(\s*(-?[0-9]+)\s*,\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[xyzwrgba]+)?)\s*\)"#
        )
        var result = source
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let literal = Range(match.range(at: 2), in: source),
                  let siblingRange = Range(match.range(at: 3), in: source),
                  let full = Range(match.range, in: result) else { continue }
            guard !authoredNames.contains(String(source[nameRange])) else { continue }
            let siblingName = String(source[siblingRange])
            let value = String(source[literal])
            let expression = String(source[full])
            if let vectorType = types[siblingName],
               !conflicted.contains(siblingName),
               let spelling = glslSpelling[vectorType] {
                let component = ["float2", "float3", "float4"].contains(vectorType)
                    ? value + ".0" : value
                result.replaceSubrange(
                    full,
                    with: expression.replacingOccurrences(
                        of: value,
                        with: "\(spelling)(\(component))",
                        options: [],
                        range: nil
                    )
                )
            } else if types[siblingName] == "float" || siblingName.contains(".") {
                // A float scalar (declared or swizzled) converts from the
                // integer literal implicitly once it is spelled as a float.
                result.replaceSubrange(
                    full,
                    with: expression.replacingOccurrences(
                        of: value,
                        with: value + ".0",
                        options: [],
                        range: nil
                    )
                )
            }
        }
        return result
    }

    static func replaceWord(_ word: String, with replacement: String, in source: String) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#
        )
        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: replacement
        )
    }

}

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

    /// GLSL ES accepts implicit scalar conversions in some authors' compilers,
    /// while glslang's Vulkan frontend requires an explicit conversion.
    /// Restrict the rewrite to authored float symbols so local type semantics
    /// remain untouched and the rule stays generic across scenes.
    static func rewriteFloatToIntAssignments(
        _ source: String,
        shapes: [String: Shape]
    ) -> String {
        let floatNames = shapes.compactMap { name, shape in
            shape.type == "float" ? name : nil
        }
        guard !floatNames.isEmpty else { return source }
        let regex = try! NSRegularExpression(pattern:
            #"\bint\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*("#
                + floatNames.map(NSRegularExpression.escapedPattern).joined(separator: "|")
                + #")\s*;"#
        )
        let comparisonRegex = try! NSRegularExpression(pattern:
            #"\b([A-Za-z_][A-Za-z0-9_]*)\s*(<=|>=|<|>)\s*("#
                + floatNames.map(NSRegularExpression.escapedPattern).joined(separator: "|")
                + #")\b"#
        )
        var result = source
        for match in regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let variableRange = Range(match.range(at: 1), in: source),
                  let valueRange = Range(match.range(at: 2), in: source),
                  let fullRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(
                fullRange,
                with: "int \(source[variableRange]) = int(\(source[valueRange]));"
            )
        }
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

    static func rewriteVectorClampLiteralArguments(_ source: String) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"\b(max|min)\(\s*(-?[0-9]+)\s*,\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[xyzwrgba]+)?)\s*\)"#
        )
        var result = source
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).reversed() {
            guard let literal = Range(match.range(at: 2), in: source),
                  let full = Range(match.range, in: result) else { continue }
            let expression = String(source[full])
            let scalar = String(source[literal]) + ".0"
            result.replaceSubrange(full, with: expression.replacingOccurrences(of: String(source[literal]), with: "vec3(\(scalar))", options: [], range: nil))
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

    static func containsWord(_ word: String, in source: String) -> Bool {
        let regex = try! NSRegularExpression(pattern:
            #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#
        )
        let code = lexicalMask(source)
        return regex.firstMatch(
            in: code,
            range: NSRange(code.startIndex..., in: code)
        ) != nil
    }

}

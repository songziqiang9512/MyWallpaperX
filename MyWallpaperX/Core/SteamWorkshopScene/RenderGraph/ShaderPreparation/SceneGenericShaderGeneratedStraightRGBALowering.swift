import Foundation

/// Conserves a source-proven generated straight-RGBA terminal through the
/// fixed SPIRV-Cross output shape. No texture boundary is introduced because
/// every surviving sample must be a source-correlated dead local whose value
/// cannot reach the generated color or coverage carriers.
nonisolated enum SceneGenericShaderGeneratedStraightRGBALowering {
    /// Confirms that a compiler artifact still has the sample-free terminal
    /// shape required by the authored generated-RGBA proof. This is used before
    /// the generic straight-color fallback so an injected texture read cannot
    /// be hidden behind that broader boundary.
    static func compilerContractMatches(_ source: String) -> Bool {
        lower(source) != nil
    }

    static func prepare(
        _ source: String,
        authoredSource: String
    ) -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    )? {
        guard SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.analyze(
            fragmentSource: authoredSource
        ) != nil, let lowered = lower(
            source,
            authoredSource: authoredSource
        ) else { return nil }
        return (
            lowered,
            .init(kind: "generated-straight-alpha", slot: nil, slots: nil)
        )
    }

    static func lower(_ source: String) -> String? {
        lower(source, expectedDeadSampleSlots: [])
    }

    private static func lower(
        _ source: String,
        authoredSource: String
    ) -> String? {
        guard let expectedDeadSampleSlots = authoredDeadSampleSlots(
            in: authoredSource
        ) else { return nil }
        return lower(
            source,
            expectedDeadSampleSlots: expectedDeadSampleSlots
        )
    }

    private static func lower(
        _ source: String,
        expectedDeadSampleSlots: [Int]
    ) -> String? {
        guard !containsWord("mwxGenericUnpremultiply", in: source),
              !containsWord("mwxGenericPremultiply", in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              compilerDeadSamplesMatch(
                  source,
                  expectedSlots: expectedDeadSampleSlots
              ),
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1
        else { return nil }
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\([^;]+\))\s*;[ \t]*$"#,
            in: source
        )
        let returns = matches(#"(?m)^[ \t]*return\s+out\s*;[ \t]*$"#, in: source)
        guard outputs.count == 1, returns.count == 1,
              let output = outputs.first,
              output.range.location < returns[0].range.location,
              let range = Range(output.range, in: source),
              let indent = capture(output, 1, in: source),
              let value = capture(output, 2, in: source) else { return nil }
        var transformed = source
        transformed.replaceSubrange(
            range,
            with: "\(indent)out.mwxFragColor = mwxGenericPremultiply(\(value));"
        )
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    /// Projects only the authored shape admitted by the generated-RGBA proof:
    /// zero or more direct full-vector samples assigned to otherwise unused
    /// locals from a simple coordinate read. The compiler may remove any of
    /// these declarations, so its surviving slot multiset is checked as a
    /// subset rather than requiring all source-dead work to remain.
    private static func authoredDeadSampleSlots(in source: String) -> [Int]? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty,
              let fragment = syntax.unit,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let tokens = fragment.tokens
        let sampleNames = Set([
            "texSample2D", "texture2D", "texture",
            "texSample2DLod", "texture2DLod", "textureLod",
        ])
        let samples = main.bodyRange.filter { sampleNames.contains(tokens[$0].text) }
        guard samples.count <= 8 else { return nil }

        var slots: [Int] = []
        for sample in samples {
            var statementStart = sample
            while statementStart > main.bodyRange.lowerBound,
                  ![";", "{", "}"].contains(tokens[statementStart - 1].text) {
                statementStart -= 1
            }
            guard ["texSample2D", "texture2D", "texture"].contains(
                      tokens[sample].text
                  ),
                  sample == statementStart + 3,
                  ["vec4", "float4"].contains(tokens[statementStart].text),
                  tokens[statementStart + 1].kind == .identifier,
                  tokens[statementStart + 2].text == "=",
                  sample + 4 < main.bodyRange.upperBound,
                  tokens[sample + 1].text == "(",
                  tokens[sample + 2].kind == .identifier,
                  tokens[sample + 3].text == ",",
                  let close = matchingClose(
                      opening: sample + 1,
                      tokens: tokens,
                      limit: main.bodyRange.upperBound
                  ), close + 1 < main.bodyRange.upperBound,
                  tokens[close + 1].text == ";",
                  simpleCoordinateRead(tokens[(sample + 4)..<close]),
                  let slot = textureSlot(tokens[sample + 2].text),
                  fragment.declarations.contains(where: {
                      $0.storage == .uniform
                          && $0.typeName == "sampler2D"
                          && $0.name == "g_Texture\(slot)"
                  }) else { return nil }
            let local = tokens[statementStart + 1].text
            guard main.bodyRange.filter({ tokens[$0].text == local }).count == 1
            else { return nil }
            slots.append(slot)
        }
        return slots
    }

    /// Accepts only the fixed compiler representation observed for a direct
    /// authored sample: a full `float4` local, the matching texture/sampler/
    /// coordinate helper, and a single-use coordinate temporary. Texture
    /// sampling itself has no side effects; constraining both arguments to
    /// compiler-owned reads keeps arbitrary calls and mutations out.
    private static func compilerDeadSamplesMatch(
        _ source: String,
        expectedSlots: [Int]
    ) -> Bool {
        let memberSamples = matches(
            #"\b[A-Za-z_]\w*\.sample\s*\("#,
            in: source
        )
        guard !memberSamples.isEmpty else { return true }
        guard let body = fragmentBodyRange(in: source),
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source),
              calls.count == memberSamples.count,
              calls.count <= expectedSlots.count else { return false }

        let declarationPattern =
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)"#
            + #"(g_Texture([0-7])\.sample\([^;\r\n]+\))(\s*;[ \t]*)$"#
        let declarations = matches(declarationPattern, in: source)
        guard declarations.count == calls.count,
              declarations.allSatisfy({ range(body, contains: $0.range) })
        else { return false }

        var observedSlots: [Int] = []
        for declaration in declarations {
            guard let local = capture(declaration, 2, in: source),
                  let call = capture(declaration, 3, in: source),
                  let slotText = capture(declaration, 4, in: source),
                  let slot = Int(slotText),
                  countWord(local, in: source) == 1,
                  let arguments = matches(
                      #"^g_Texture"# + String(slot)
                        + #"\.sample\(\s*g_Texture"# + String(slot)
                        + #"Smplr\s*,\s*mwxTexture"# + String(slot)
                        + #"Coordinate\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*\)\s*\)$"#,
                      in: call
                  ).first,
                  let coordinate = capture(arguments, 1, in: call),
                  let uniforms = capture(arguments, 2, in: call),
                  compilerDeadSampleBindingsMatch(
                      slot: slot,
                      uniforms: uniforms,
                      in: source
                  ),
                  countWord(coordinate, in: source) == 2 else { return false }
            let coordinateDeclarations = matches(
                #"(?m)^[ \t]*(?:const\s+)?float2\s+"#
                    + NSRegularExpression.escapedPattern(for: coordinate)
                    + #"\s*=\s*[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?\s*;[ \t]*$"#,
                in: source
            )
            guard coordinateDeclarations.count == 1,
                  let coordinateDeclaration = coordinateDeclarations.first,
                  range(body, contains: coordinateDeclaration.range),
                  coordinateDeclaration.range.location < declaration.range.location
            else { return false }
            observedSlots.append(slot)
        }

        var available = expectedSlots.reduce(into: [Int: Int]()) {
            $0[$1, default: 0] += 1
        }
        for slot in observedSlots {
            guard let count = available[slot], count > 0 else { return false }
            available[slot] = count - 1
        }
        return true
    }

    private static func compilerDeadSampleBindingsMatch(
        slot: Int,
        uniforms: String,
        in source: String
    ) -> Bool {
        let slotText = String(slot)
        let escapedUniforms = NSRegularExpression.escapedPattern(for: uniforms)
        let texture = #"\btexture2d\s*<\s*float\s*>\s+g_Texture"#
            + slotText + #"\s*\[\[\s*texture\s*\(\s*"#
            + slotText + #"\s*\)\s*\]\]"#
        let sampler = #"\bsampler\s+g_Texture"# + slotText
            + #"Smplr\s*\[\[\s*sampler\s*\(\s*"#
            + slotText + #"\s*\)\s*\]\]"#
        let uniform = #"\bconstant\s+[A-Za-z_]\w*\s*&\s*"#
            + escapedUniforms + #"\s*\[\[\s*buffer\s*\(\s*8\s*\)\s*\]\]"#
        let helper = #"\bfloat2\s+mwxTexture"# + slotText
            + #"Coordinate\s*\(\s*thread\s+const\s+float2\s*&\s*[A-Za-z_]\w*\s*,"#
            + #"\s*constant\s+[A-Za-z_]\w*\s*&\s*"#
            + escapedUniforms + #"\s*\)"#
        return matches(texture, in: source).count == 1
            && matches(sampler, in: source).count == 1
            && matches(uniform, in: source).count == 1
            && matches(helper, in: source).count == 1
    }

    private static func simpleCoordinateRead(
        _ tokens: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        let values = Array(tokens)
        return (values.count == 1 && values[0].kind == .identifier)
            || (values.count == 3
                && values[0].kind == .identifier
                && values[1].text == "."
                && values[2].kind == .identifier)
    }

    private static func matchingClose(
        opening: Int,
        tokens: [SceneAuthoredShaderToken],
        limit: Int
    ) -> Int? {
        var depth = 0
        for index in opening..<limit {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
                if depth < 0 { return nil }
            }
        }
        return nil
    }

    private static func textureSlot(_ name: String) -> Int? {
        let prefix = "g_Texture"
        guard name.hasPrefix(prefix),
              let slot = Int(name.dropFirst(prefix.count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }

    private static func fragmentBodyRange(in source: String) -> NSRange? {
        let signatures = matches(#"\bfragment\b[^\{]*\{"#, in: source)
        guard signatures.count == 1,
              let signature = signatures.first,
              let signatureRange = Range(signature.range, in: source),
              let open = source[..<signatureRange.upperBound].lastIndex(of: "{")
        else { return nil }
        var depth = 0
        var cursor = open
        while cursor < source.endIndex {
            if source[cursor] == "{" { depth += 1 }
            if source[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    return NSRange(source.index(after: open)..<cursor, in: source)
                }
                if depth < 0 { return nil }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func range(_ outer: NSRange, contains inner: NSRange) -> Bool {
        outer.location <= inner.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(
            #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#,
            in: source
        ).isEmpty
    }

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(
            #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#,
            in: source
        ).count
    }

    private static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern).matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )) ?? []
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else {
            return nil
        }
        return String(source[range])
    }
}

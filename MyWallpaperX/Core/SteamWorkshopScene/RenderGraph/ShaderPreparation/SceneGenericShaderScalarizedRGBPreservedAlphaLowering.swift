import Foundation

/// Conserves the compiler form of a source-proven RGB-only carrier mutation.
/// SPIRV-Cross may scalarize one authored `carrier.rgb = value` assignment
/// into three component writes. The graph-input carrier crosses the straight
/// color boundary; auxiliary scalar textures remain data, and the unchanged
/// carrier alpha returns through the sole compositor boundary.
nonisolated enum SceneGenericShaderScalarizedRGBPreservedAlphaLowering {
    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    static func lower(_ source: String, expectedSlot: Int) -> String? {
        guard (0 ..< 8).contains(expectedSlot),
              !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let body = fragmentBodyRange(in: source),
              bodyIsLinear(body, source: source),
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source),
              (2 ... 16).contains(calls.count),
              calls.allSatisfy({ contains(body, $0.range) })
        else { return nil }

        let carrierDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard carrierDeclarations.count == 1,
              let declaration = carrierDeclarations.first,
              contains(body, declaration.range),
              let carrier = capture(declaration, 2, in: source),
              calls.filter({ $0.slot == expectedSlot }).count == 1,
              auxiliaryCallsAreScalar(
                  calls,
                  expectedSlot: expectedSlot,
                  source: source
              ),
              bodyTextureReferences(in: body, source: source) == calls.count
        else { return nil }

        let carrierPattern = escaped(carrier)
        let outputs = outputPatterns(carrierPattern).flatMap {
            matches($0, in: source)
        }
        guard outputs.count == 1,
              let output = outputs.first,
              contains(body, output.range),
              let outputRange = Range(output.range, in: source),
              let outputIndent = capture(output, 1, in: source),
              let outputValue = capture(output, 2, in: source),
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              calls.allSatisfy({ $0.range.location < output.range.location }),
              terminalTail(after: output.range, within: body, source: source)
        else { return nil }

        let componentWrites = matches(
            #"(?m)^[ \t]*"# + carrierPattern
                + #"\.([xyz])\s*=\s*([A-Za-z_]\w*)\.([xyz])\s*;[ \t]*$"#,
            in: source
        )
        let writtenComponents = componentWrites.compactMap {
            capture($0, 1, in: source)
        }
        let valueNames = componentWrites.compactMap {
            capture($0, 2, in: source)
        }
        let valueComponents = componentWrites.compactMap {
            capture($0, 3, in: source)
        }
        guard componentWrites.count == 3,
              Set(writtenComponents) == Set(["x", "y", "z"]),
              writtenComponents == valueComponents,
              Set(valueNames).count == 1,
              let value = valueNames.first,
              value != carrier,
              componentWrites.allSatisfy({
                  declaration.range.location < $0.range.location
                      && $0.range.location < output.range.location
              }),
              componentWritesAreTheOnlyCarrierWrites(
                  componentWrites,
                  carrier: carrier,
                  source: source
              ),
              hasSingleImmutableRGBValue(
                  value,
                  before: componentWrites.map(\.range.location).min() ?? 0,
                  writes: componentWrites,
                  source: source
              ),
              carrierUsesAreRGBOnly(
                  carrier,
                  declaration: declaration.range,
                  writes: componentWrites.map(\.range),
                  output: output.range,
                  source: source
              ),
              hasRGBRead(
                  carrier,
                  after: declaration.range,
                  before: componentWrites.map(\.range.location).min() ?? 0,
                  source: source
              )
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(outputIndent)out.mwxFragColor = \(premultiply)(\(outputValue));"
        )
        guard let prefix = capture(declaration, 1, in: source),
              let arguments = capture(declaration, 3, in: source),
              let suffix = capture(declaration, 4, in: source),
              let declarationRange = Range(declaration.range, in: transformed)
        else { return nil }
        transformed.replaceSubrange(
            declarationRange,
            with: "\(prefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(arguments)))\(suffix)"
        )
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private static func outputPatterns(_ carrier: String) -> [String] {
        [
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\(\s*fast::max\(\s*float3\(\s*0(?:\.0+)?\s*\)\s*,\s*"#
                + carrier
                + #"\.(?:xyz|rgb)\s*\)\s*,\s*"#
                + carrier + #"\.(?:w|a)\s*\))\s*;[ \t]*$"#,
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\(\s*fast::max\(\s*"#
                + carrier
                + #"\.(?:xyz|rgb)\s*,\s*float3\(\s*0(?:\.0+)?\s*\)\s*\)\s*,\s*"#
                + carrier + #"\.(?:w|a)\s*\))\s*;[ \t]*$"#,
        ]
    }

    private static func auxiliaryCallsAreScalar(
        _ calls: [SceneGenericShaderStraightAlphaPreservingLowering.CompilerTextureSampleCall],
        expectedSlot: Int,
        source: String
    ) -> Bool {
        var sourceCalls = 0
        for call in calls {
            guard let range = Range(call.range, in: source) else { return false }
            let suffix = source[range.upperBound...]
            if call.slot == expectedSlot {
                guard suffix.range(
                    of: #"^\s*;"#,
                    options: .regularExpression
                ) != nil else { return false }
                sourceCalls += 1
            } else if suffix.range(
                of: #"^\s*\.\s*[xyzwrgba]\b"#,
                options: .regularExpression
            ) == nil {
                return false
            }
        }
        return sourceCalls == 1
    }

    private static func bodyTextureReferences(
        in body: NSRange,
        source: String
    ) -> Int {
        guard let range = Range(body, in: source) else { return -1 }
        return matches(#"\bg_Texture[0-7]\b"#, in: String(source[range])).count
    }

    private static func componentWritesAreTheOnlyCarrierWrites(
        _ writes: [NSTextCheckingResult],
        carrier: String,
        source: String
    ) -> Bool {
        let allWrites = matches(
            #"(?m)^[ \t]*"# + escaped(carrier)
                + #"(?:\.[xyzwrgba]{1,4})?\s*(?:[+\-*/]=|=(?!=)|\+\+|--)"#,
            in: source
        )
        let prefixMutations = matches(
            #"(?:\+\+|--)\s*\b"# + escaped(carrier) + #"\b"#,
            in: source
        )
        return prefixMutations.isEmpty
            && allWrites.count == writes.count
            && allWrites.allSatisfy { candidate in
                writes.contains(where: { contains($0.range, candidate.range) })
            }
    }

    private static func hasSingleImmutableRGBValue(
        _ value: String,
        before firstWrite: Int,
        writes: [NSTextCheckingResult],
        source: String
    ) -> Bool {
        let declarations = matches(
            #"(?m)^[ \t]*float3\s+"# + escaped(value)
                + #"\s*=\s*[^;]+;[ \t]*$"#,
            in: source
        )
        guard declarations.count == 1,
              let declaration = declarations.first,
              declaration.range.location < firstWrite else { return false }
        let mutations = matches(
            #"(?m)^[ \t]*"# + escaped(value)
                + #"(?:\.[xyzwrgba]{1,4})?\s*(?:[+\-*/]=|=(?!=)|\+\+|--)"#,
            in: source
        )
        return mutations.isEmpty
            && countWord(value, in: source) == writes.count + 1
    }

    private static func carrierUsesAreRGBOnly(
        _ carrier: String,
        declaration: NSRange,
        writes: [NSRange],
        output: NSRange,
        source: String
    ) -> Bool {
        let words = matches(#"\b"# + escaped(carrier) + #"\b"#, in: source)
        let rgbUses = matches(
            #"\b"# + escaped(carrier) + #"\s*\.\s*(?:rgb|xyz|[xyz])\b"#,
            in: source
        )
        return words.allSatisfy { word in
            contains(declaration, word.range)
                || writes.contains(where: { contains($0, word.range) })
                || contains(output, word.range)
                || rgbUses.contains(where: { contains($0.range, word.range) })
        }
    }

    private static func hasRGBRead(
        _ carrier: String,
        after declaration: NSRange,
        before firstWrite: Int,
        source: String
    ) -> Bool {
        matches(
            #"\b"# + escaped(carrier) + #"\s*\.\s*(?:rgb|xyz|[xyz])\b"#,
            in: source
        ).contains {
            NSMaxRange(declaration) <= $0.range.location
                && NSMaxRange($0.range) <= firstWrite
        }
    }

    private static func fragmentBodyRange(in source: String) -> NSRange? {
        let text = source as NSString
        let signatures = matches(#"\bfragment\b[^\{]*\{"#, in: source)
        guard signatures.count == 1, let signature = signatures.first else {
            return nil
        }
        let open = NSMaxRange(signature.range) - 1
        var depth = 0
        for cursor in open..<text.length {
            switch text.character(at: cursor) {
            case 123: depth += 1
            case 125:
                depth -= 1
                if depth == 0 {
                    return NSRange(
                        location: open + 1,
                        length: cursor - open - 1
                    )
                }
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    private static func bodyIsLinear(_ body: NSRange, source: String) -> Bool {
        guard let range = Range(body, in: source) else { return false }
        let text = String(source[range])
        return matches(#"\b(?:if|for|while|switch|do|goto|discard)\b"#, in: text)
            .isEmpty
            && matches(#"\breturn\b"#, in: text).count == 1
    }

    private static func terminalTail(
        after output: NSRange,
        within body: NSRange,
        source: String
    ) -> Bool {
        let end = NSMaxRange(body)
        guard NSMaxRange(output) <= end,
              let range = Range(
                  NSRange(
                      location: NSMaxRange(output),
                      length: end - NSMaxRange(output)
                  ),
                  in: source
              ) else { return false }
        return String(source[range]).range(
            of: #"^\s*return\s+out\s*;\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer.location <= inner.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    private static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        return expression.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }

    private static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
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

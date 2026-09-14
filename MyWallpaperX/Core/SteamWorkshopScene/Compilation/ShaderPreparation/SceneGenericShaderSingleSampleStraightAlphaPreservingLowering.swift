import Foundation

/// Conserves the general compiler shape for one source-proven color sample
/// whose authored program changes RGB but preserves that sample's alpha. The
/// authored analyzer owns the semantic proof; this only verifies the compiled
/// data flow before inserting the shared compositor color boundary.
nonisolated enum SceneGenericShaderSingleSampleStraightAlphaPreservingLowering {
    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    static func lower(_ source: String, expectedSlot: Int) -> String? {
        guard (0 ..< 8).contains(expectedSlot),
              !hasWord(unpremultiply, in: source),
              !hasWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source),
              calls.count == 1,
              calls[0].slot == expectedSlot
        else { return nil }

        let functionHeaders = matches(
            #"\bfragment\s+([A-Za-z_]\w*)\s+mwxGenericFragment\s*\("#,
            in: source
        )
        guard functionHeaders.count == 1,
              let function = functionHeaders.first,
              let returnType = capture(function, 1, in: source),
              let functionRange = Range(function.range, in: source),
              let body = bracedBody(after: functionRange.upperBound, in: source)
        else { return nil }

        let bodySource = String(source[body])
        let sampleDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;\n]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard sampleDeclarations.count == 1,
              let sampleDeclaration = sampleDeclarations.first,
              let sample = capture(sampleDeclaration, 2, in: source),
              contains(body, sampleDeclaration.range, in: source),
              contains(sampleDeclaration.range, calls[0].range),
              matches(#"\bg_Texture[0-7]\b"#, in: bodySource).count == 1,
              matches(
                  #"\.\s*(?:sample|read|gather)(?:_compare)?\s*\("#,
                  in: bodySource
              ).count == 1
        else { return nil }

        let carrierDeclarations = matches(
            #"(?m)^[ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*"#
                + escaped(sample) + #"\s*;[ \t]*$"#,
            in: source
        )
        guard carrierDeclarations.count == 1,
              let carrierDeclaration = carrierDeclarations.first,
              let carrier = capture(carrierDeclaration, 1, in: source),
              carrier != sample,
              contains(body, carrierDeclaration.range, in: source),
              wordUsesAreConfined(
                  sample,
                  to: [sampleDeclaration.range, carrierDeclaration.range],
                  source: source
              )
        else { return nil }

        let carrierPattern = escaped(carrier)
        guard let rgbMutation = rgbMutation(
            carrier: carrier,
            body: body,
            source: source
        ) else { return nil }

        let outputWrites = matches(
            outputPattern(carrier: carrierPattern), in: source
        )
        let returns = matches(
            #"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#,
            in: source
        )
        guard outputWrites.count == 1,
              returns.count == 1,
              let output = outputWrites.first,
              let outputIndent = capture(output, 1, in: source),
              let outputValue = capture(output, 2, in: source),
              let terminalReturn = returns.first,
              contains(body, output.range, in: source),
              contains(body, terminalReturn.range, in: source),
              contains(body, calls[0].range, in: source),
              sampleDeclaration.range.location
                < carrierDeclaration.range.location,
              carrierDeclaration.range.location < rgbMutation.firstLocation,
              rgbMutation.lastLocation < output.range.location,
              output.range.location < terminalReturn.range.location,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              matches(#"\breturn\b"#, in: bodySource).count == 1,
              bodyIsLinear(bodySource),
              matches(
                  #"(?m)^[ \t]*"# + escaped(returnType)
                    + #"\s+out(?:\s*=\s*\{\s*\})?\s*;[ \t]*$"#,
                  in: bodySource
              ).count == 1,
              matches(#"\bout\b"#, in: bodySource).count == 3,
              wordUsesAreConfined(
                  carrier,
                  to: [carrierDeclaration.range]
                    + rgbMutation.statementRanges
                    + [output.range],
                  source: source
              ),
              let returnRange = Range(terminalReturn.range, in: source),
              String(source[returnRange.upperBound..<body.upperBound])
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let callRange = Range(calls[0].range, in: source),
              let outputRange = Range(output.range, in: source)
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(outputIndent)out.mwxFragColor = \(premultiply)(\(outputValue));"
        )
        guard let adjustedCallRange = Range(calls[0].range, in: transformed)
        else { return nil }
        transformed.replaceSubrange(
            adjustedCallRange,
            with: "\(unpremultiply)(\(source[callRange]))"
        )
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private static func outputPattern(carrier: String) -> String {
        #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*(float4\(\s*fast::max\(\s*float3\(\s*0(?:\.0+)?\s*\)\s*,\s*"#
            + carrier
            + #"\s*\.\s*(?:xyz|rgb)\s*\)\s*,\s*"#
            + carrier
            + #"\s*\.\s*(?:w|a)\s*\))\s*;[ \t]*$"#
    }

    private struct RGBMutation {
        let statementRanges: [NSRange]
        let firstLocation: Int
        let lastLocation: Int
    }

    private static func rgbMutation(
        carrier: String,
        body: Range<String.Index>,
        source: String
    ) -> RGBMutation? {
        let carrierPattern = escaped(carrier)
        let wholeWrites = matches(
            #"(?m)^[ \t]*"# + carrierPattern
                + #"\s*\.\s*(?:xyz|rgb)\s*=\s*([^;\n]+);[ \t]*$"#,
            in: source
        )
        if wholeWrites.count == 1,
           let write = wholeWrites.first,
           let expression = capture(write, 1, in: source),
           contains(body, write.range, in: source),
           !matches(
               #"\b"# + carrierPattern + #"\s*\.\s*(?:xyz|rgb)\b"#,
               in: expression
           ).isEmpty,
           carrierMutationsAreLimitedTo(
               [write.range], carrier: carrier, source: source
           ) {
            return .init(
                statementRanges: [write.range],
                firstLocation: write.range.location,
                lastLocation: NSMaxRange(write.range)
            )
        }

        let componentWrites = matches(
            #"(?m)^[ \t]*"# + carrierPattern
                + #"\s*\.\s*([xyz])\s*=\s*([A-Za-z_]\w*)\s*\.\s*([xyz])\s*;[ \t]*$"#,
            in: source
        )
        let writtenComponents = componentWrites.compactMap {
            capture($0, 1, in: source)
        }
        let values = componentWrites.compactMap {
            capture($0, 2, in: source)
        }
        let valueComponents = componentWrites.compactMap {
            capture($0, 3, in: source)
        }
        guard componentWrites.count == 3,
              Set(writtenComponents) == Set(["x", "y", "z"]),
              writtenComponents == valueComponents,
              Set(values).count == 1,
              let value = values.first,
              value != carrier,
              let firstWrite = componentWrites.map(\.range.location).min(),
              let lastWrite = componentWrites.map({ NSMaxRange($0.range) }).max(),
              componentWrites.allSatisfy({ contains(body, $0.range, in: source) }),
              carrierMutationsAreLimitedTo(
                  componentWrites.map(\.range), carrier: carrier, source: source
              )
        else { return nil }

        let valueDeclarations = matches(
            #"(?m)^[ \t]*float3\s+"# + escaped(value)
                + #"\s*=\s*([^;\n]+);[ \t]*$"#,
            in: source
        )
        guard valueDeclarations.count == 1,
              let declaration = valueDeclarations.first,
              let expression = capture(declaration, 1, in: source),
              contains(body, declaration.range, in: source),
              declaration.range.location < firstWrite,
              wordUsesAreConfined(
                  value,
                  to: [declaration.range] + componentWrites.map(\.range),
                  source: source
              )
        else { return nil }
        let dependencyDeclarations: [NSTextCheckingResult]
        if matches(
            #"\b"# + carrierPattern + #"\s*\.\s*(?:xyz|rgb)\b"#,
            in: expression
        ).isEmpty {
            let candidates = matches(
                #"(?m)^[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*([^;\n]+);[ \t]*$"#,
                in: source
            )
            dependencyDeclarations = candidates.filter { candidate in
                guard candidate.range.location < declaration.range.location,
                      let candidateExpression = capture(candidate, 2, in: source)
                else { return false }
                return !matches(
                    #"\b"# + carrierPattern
                        + #"\s*\.\s*(?:xyz|rgb)\b"#,
                    in: candidateExpression
                ).isEmpty
            }
            guard (1 ... 8).contains(dependencyDeclarations.count),
                  dependencyDeclarations.allSatisfy({ dependency in
                      guard contains(body, dependency.range, in: source),
                            let name = capture(dependency, 1, in: source)
                      else { return false }
                      return hasWord(name, in: expression)
                          && wordUsesAreConfined(
                              name,
                              to: [dependency.range, declaration.range],
                              source: source
                          )
                  })
            else { return nil }
        } else {
            dependencyDeclarations = []
        }
        let scalarizedStatements = dependencyDeclarations.map(\.range)
            + [declaration.range]
            + componentWrites.map(\.range)
        return .init(
            statementRanges: scalarizedStatements,
            firstLocation: scalarizedStatements.map(\.location).min()
                ?? declaration.range.location,
            lastLocation: lastWrite
        )
    }

    private static func carrierMutationsAreLimitedTo(
        _ accepted: [NSRange],
        carrier: String,
        source: String
    ) -> Bool {
        let escapedCarrier = escaped(carrier)
        let mutations = matches(
            #"(?m)^[ \t]*"# + escapedCarrier
                + #"(?:\s*\.\s*[xyzwrgba]{1,4})?\s*(?:[+\-*/]=|=(?!=)|\+\+|--)"#,
            in: source
        )
        let prefixMutations = matches(
            #"(?:\+\+|--)\s*\b"# + escapedCarrier + #"\b"#,
            in: source
        )
        return prefixMutations.isEmpty
            && mutations.count == accepted.count
            && mutations.allSatisfy { mutation in
                accepted.contains(where: { contains($0, mutation.range) })
            }
    }

    private static func wordUsesAreConfined(
        _ word: String,
        to statements: [NSRange],
        source: String
    ) -> Bool {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).allSatisfy {
            use in statements.contains(where: { contains($0, use.range) })
        }
    }

    private static func bodyIsLinear(_ source: String) -> Bool {
        matches(
            #"\b(?:if|for|while|switch|do|goto|discard)\b"#,
            in: source
        ).isEmpty
    }

    private static func bracedBody(
        after start: String.Index,
        in source: String
    ) -> Range<String.Index>? {
        guard let opening = source[start...].firstIndex(of: "{") else {
            return nil
        }
        if let prototype = source[start...].firstIndex(of: ";"),
           prototype < opening {
            return nil
        }
        var depth = 0
        var cursor = opening
        while cursor < source.endIndex {
            switch source[cursor] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return source.index(after: opening)..<cursor
                }
                if depth < 0 { return nil }
            default: break
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func contains(
        _ outer: Range<String.Index>,
        _ inner: NSRange,
        in source: String
    ) -> Bool {
        guard let range = Range(inner, in: source) else { return false }
        return outer.lowerBound <= range.lowerBound
            && range.upperBound <= outer.upperBound
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        outer.location <= inner.location
            && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private static func hasWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    private static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) ?? []
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
              let range = Range(match.range(at: index), in: source)
        else { return nil }
        return String(source[range])
    }
}

extension SceneGenericShaderStraightAlphaPreservingLowering {
    nonisolated static func lowerSingleSample(
        _ source: String,
        expectedSlot: Int
    ) -> String? {
        SceneGenericShaderSingleSampleStraightAlphaPreservingLowering.lower(
            source,
            expectedSlot: expectedSlot
        )
    }
}

import Foundation

/// Conserves a source-proven associated-over through SPIRV-Cross. Only the
/// graph-input color sample crosses the straight-color boundary; the overlay
/// remains authored data, and the unique terminal result returns to the
/// compositor's premultiplied storage. The source analyzer owns the semantic
/// proof; this pass rejects hidden samples, extra outputs, and helper drift.
nonisolated enum SceneGenericShaderAssociatedOverBlendLowering {
    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    static func lower(
        _ source: String,
        fact: SceneAuthoredShaderAssociatedOverBlendAnalyzer.Fact
    ) -> String? {
        lower(
            source,
            sourceSlot: fact.sourceSlot,
            overlaySlot: fact.overlaySlot,
            blendFunctions: [fact.blendFunction],
            blendWeight: fact.blendWeight,
            blendWeightUniform: fact.blendWeightUniform,
            requiresOverlayAlphaWrite: false
        )
    }

    /// Shared conservation for associated-over and overlay-alpha WRITEALPHA:
    /// unpremultiply only the graph-input sample, leave the overlay as data,
    /// and premultiply the unique terminal assignment.
    static func lower(
        _ source: String,
        sourceSlot: Int,
        overlaySlot: Int
    ) -> String? {
        lower(
            source,
            sourceSlot: sourceSlot,
            overlaySlot: overlaySlot,
            blendFunctions: ["ApplyBlending", "mix", "lerp"],
            blendWeight: nil,
            blendWeightUniform: nil,
            requiresOverlayAlphaWrite: true
        )
    }

    private static func lower(
        _ source: String,
        sourceSlot: Int,
        overlaySlot: Int,
        blendFunctions: Set<String>,
        blendWeight: String?,
        blendWeightUniform: String?,
        requiresOverlayAlphaWrite: Bool
    ) -> String? {
        guard (0 ..< 8).contains(sourceSlot),
              (0 ..< 8).contains(overlaySlot),
              sourceSlot != overlaySlot,
              !blendFunctions.isEmpty,
              !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let sampleCalls = SceneGenericShaderStraightAlphaPreservingLowering
              .compilerTextureSampleCalls(in: source),
              sampleCalls.count == 2,
              Set(sampleCalls.map(\.slot)) == Set([sourceSlot, overlaySlot]),
              sampleCalls.filter({ $0.slot == sourceSlot }).count == 1,
              sampleCalls.filter({ $0.slot == overlaySlot }).count == 1
        else { return nil }

        let sourceDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(sourceSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        let overlayDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(overlaySlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*$"#,
            in: source
        )
        guard sourceDeclarations.count == 1,
              overlayDeclarations.count == 1,
              outputs.count == 1,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              let sourceDeclaration = sourceDeclarations.first,
              let overlayDeclaration = overlayDeclarations.first,
              let output = outputs.first,
              sourceDeclaration.range.location < output.range.location,
              overlayDeclaration.range.location < output.range.location,
              let prefix = capture(sourceDeclaration, 1, in: source),
              let sourceCarrier = capture(sourceDeclaration, 2, in: source),
              let arguments = capture(sourceDeclaration, 3, in: source),
              let suffix = capture(sourceDeclaration, 4, in: source),
              let overlayCarrier = capture(overlayDeclaration, 2, in: source),
              let indent = capture(output, 1, in: source),
              let carrier = capture(output, 2, in: source),
              carrier == sourceCarrier,
              let sourceRange = Range(sourceDeclaration.range, in: source),
              let overlayRange = Range(overlayDeclaration.range, in: source),
              let outputRange = Range(output.range, in: source),
              max(sourceRange.upperBound, overlayRange.upperBound)
                < outputRange.lowerBound
        else { return nil }
        let operationBody = String(source[
            max(sourceRange.upperBound, overlayRange.upperBound)
                ..< outputRange.lowerBound
        ])
        guard (hasBlendUpdate(
                  sourceCarrier: sourceCarrier,
                  overlayCarrier: overlayCarrier,
                  blendFunctions: blendFunctions,
                  blendWeight: blendWeight,
                  blendWeightUniform: blendWeightUniform,
                  requiresOverlayAlphaWrite: requiresOverlayAlphaWrite,
                  in: operationBody
              ) || (requiresOverlayAlphaWrite && hasCompilerSpilledBlendUpdate(
                  sourceCarrier: sourceCarrier,
                  overlayCarrier: overlayCarrier,
                  blendFunctions: blendFunctions,
                  in: operationBody
              ))),
              matches(#"\b(?:discard|discard_fragment)\b"#, in: source).isEmpty
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(\(carrier));"
        )
        guard let adjustedSourceRange = Range(
            sourceDeclaration.range,
            in: transformed
        ) else { return nil }
        transformed.replaceSubrange(
            adjustedSourceRange,
            with: "\(prefix)\(unpremultiply)(g_Texture\(sourceSlot).sample(\(arguments)))\(suffix)"
        )
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    /// SPIRV-Cross preserves some authored float3 helper calls by spilling the
    /// two RGB inputs and scalar weight, then writing the returned vector back
    /// one component at a time. Accept only that exact, straight-line shape.
    private static func hasCompilerSpilledBlendUpdate(
        sourceCarrier: String,
        overlayCarrier: String,
        blendFunctions: Set<String>,
        in source: String
    ) -> Bool {
        let sourceName = escaped(sourceCarrier)
        let overlayName = escaped(overlayCarrier)
        let functions = blendFunctions.sorted().map(escaped).joined(separator: "|")
        let pattern = #"(?m)^[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*"#
            + sourceName + #"\.(?:rgb|xyz)\s*;[ \t]*\n"#
            + #"[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*"#
            + overlayName + #"\.(?:rgb|xyz)\s*;[ \t]*\n"#
            + #"[ \t]*float\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*\n"#
            + #"[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*("#
            + functions + #")\s*\(\s*0\s*,\s*\1\s*,\s*\2\s*,\s*\3\s*\)\s*;[ \t]*\n"#
            + #"[ \t]*"# + sourceName + #"\.x\s*=\s*\5\.x\s*;[ \t]*\n"#
            + #"[ \t]*"# + sourceName + #"\.y\s*=\s*\5\.y\s*;[ \t]*\n"#
            + #"[ \t]*"# + sourceName + #"\.z\s*=\s*\5\.z\s*;[ \t]*$"#
        let updates = matches(pattern, in: source)
        guard updates.count == 1, let update = updates.first,
              let sourceAlias = capture(update, 1, in: source),
              let overlayAlias = capture(update, 2, in: source),
              let weightAlias = capture(update, 3, in: source),
              let weight = capture(update, 4, in: source),
              let result = capture(update, 5, in: source),
              Set([sourceAlias, overlayAlias, weightAlias, weight, result]).count == 5,
              wordUseCount(sourceAlias, in: source) == 2,
              wordUseCount(overlayAlias, in: source) == 2,
              wordUseCount(weightAlias, in: source) == 2,
              wordUseCount(result, in: source) == 4,
              assignmentCount(to: weight, in: source) == 1,
              weightInitializerIsSafe(
                  initializerForScalar(weight, in: source) ?? "",
                  expectedUniform: nil
              ),
              componentAssignmentCount(to: sourceCarrier, in: source) == 4
        else { return false }
        return true
    }

    private static func wordUseCount(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    private static func initializerForScalar(
        _ name: String,
        in source: String
    ) -> String? {
        let definitions = matches(
            #"(?m)^[ \t]*(?:const[ \t]+)?(?:float|half)[ \t]+"#
                + escaped(name) + #"\s*=\s*([^;\n]+);[ \t]*$"#,
            in: source
        )
        guard definitions.count == 1 else { return nil }
        return capture(definitions[0], 1, in: source)
    }

    private static func componentAssignmentCount(
        to name: String,
        in source: String
    ) -> Int {
        matches(
            #"(?m)^[ \t]*"# + escaped(name)
                + #"\.(?:x|y|z|w|r|g|b|a)\s*=\s*[^;\n]+;[ \t]*$"#,
            in: source
        ).count
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    private static func hasBlendUpdate(
        sourceCarrier: String,
        overlayCarrier: String,
        blendFunctions: Set<String>,
        blendWeight: String?,
        blendWeightUniform: String?,
        requiresOverlayAlphaWrite: Bool,
        in source: String
    ) -> Bool {
        let sourceName = escaped(sourceCarrier)
        let overlayName = escaped(overlayCarrier)
        let functions = blendFunctions
            .sorted()
            .map(escaped)
            .joined(separator: "|")
        let weight = blendWeight.map(escaped) ?? #"[A-Za-z_]\w*"#
        let colorMember = requiresOverlayAlphaWrite
            ? #"\.(?:rgb|xyz)"#
            : ""
        let pattern = #"(?m)^[ \t]*"#
            + sourceName + colorMember
            + #"\s*=\s*(?:"# + functions + #")\s*\(\s*"#
            + sourceName + colorMember
            + #"\s*,\s*"# + overlayName + colorMember
            + #"\s*,\s*("# + weight + #")\s*\)\s*;[ \t]*$"#
        let updates = matches(pattern, in: source)
        guard updates.count == 1,
              let update = updates.first,
              let actualWeight = capture(update, 1, in: source),
              blendWeight == nil || blendWeight == actualWeight,
              assignmentCount(to: sourceCarrier, in: source)
                == (requiresOverlayAlphaWrite ? 2 : 1),
              assignmentCount(to: overlayCarrier, in: source) == 0,
              assignmentCount(to: actualWeight, in: source) == 1
        else { return false }
        let definitions = matches(
            #"(?m)^[ \t]*(?:const[ \t]+)?(?:float|half)[ \t]+"#
                + escaped(actualWeight) + #"\s*=\s*([^;\n]+);[ \t]*$"#,
            in: source
        )
        guard definitions.count == 1,
              definitions[0].range.location < update.range.location,
              let initializer = capture(definitions[0], 1, in: source),
              weightInitializerIsSafe(
                  initializer,
                  expectedUniform: blendWeightUniform
              )
        else { return false }
        if requiresOverlayAlphaWrite {
            let alphaWrites = matches(
                #"(?m)^[ \t]*"# + sourceName
                    + #"\.(?:a|w)\s*=\s*([^;\n]+);[ \t]*$"#,
                in: source
            )
            guard alphaWrites.count == 1,
                  alphaWrites[0].range.location > update.range.location,
                  let alphaExpression = capture(alphaWrites[0], 1, in: source)
            else { return false }
            return overlayAlphaWriteIsSafe(
                alphaExpression,
                overlayCarrier: overlayCarrier
            )
        }
        return true
    }

    private static func overlayAlphaWriteIsSafe(
        _ expression: String,
        overlayCarrier: String
    ) -> Bool {
        guard !containsZeroNumber(in: expression) else { return false }
        let factors = expression.split(
            separator: "*",
            omittingEmptySubsequences: false
        )
        guard !factors.isEmpty else { return false }
        var overlayUses = 0
        for factor in factors {
            let value = factor.trimmingCharacters(in: CharacterSet(
                charactersIn: " \t\r\n()"
            ))
            if matches(
                #"^"# + escaped(overlayCarrier) + #"\.(?:a|w)$"#,
                in: value
            ).count == 1 {
                overlayUses += 1
                continue
            }
            if matches(
                #"^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*$"#,
                in: value
            ).count == 1 {
                continue
            }
            let number = value.trimmingCharacters(in: CharacterSet(
                charactersIn: "fFhH"
            ))
            guard Double(number) == 1 else { return false }
        }
        return overlayUses == 1
    }

    private static func weightInitializerIsSafe(
        _ initializer: String,
        expectedUniform: String?
    ) -> Bool {
        guard !containsZeroNumber(in: initializer) else { return false }
        guard let expectedUniform else {
            return !initializer.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
        let expression = initializer
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        let factors = expression.split(
            separator: "*",
            omittingEmptySubsequences: false
        )
        guard !factors.isEmpty else { return false }
        var uniformUses = 0
        for factor in factors {
            let value = factor.trimmingCharacters(in: .whitespacesAndNewlines)
            if value == expectedUniform || value.hasSuffix(".\(expectedUniform)") {
                uniformUses += 1
                continue
            }
            let number = value.trimmingCharacters(in: CharacterSet(
                charactersIn: "fFhH"
            ))
            guard Double(number) == 1 else { return false }
        }
        return uniformUses == 1
    }

    private static func containsZeroNumber(in source: String) -> Bool {
        matches(
            #"(?<![A-Za-z0-9_.])(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?[fFhH]?(?![A-Za-z0-9_.])"#,
            in: source
        ).contains { match in
            guard let value = capture(match, 0, in: source) else { return false }
            let number = value.trimmingCharacters(in: CharacterSet(
                charactersIn: "fFhH"
            ))
            return Double(number) == 0
        }
    }

    private static func assignmentCount(
        to name: String,
        in source: String
    ) -> Int {
        let assigned = matches(
            #"(?m)^[ \t]*(?:(?:const[ \t]+)?[A-Za-z_]\w*[ \t]+)?"#
                + escaped(name)
                + #"(?:\.(?:rgb|xyz|a|w))?\s*(?:=|\+=|-=|\*=|/=)"#,
            in: source
        ).count
        let incremented = matches(
            #"(?m)^[ \t]*(?:(?:\+\+|--)\s*"# + escaped(name)
                + #"(?:\.(?:rgb|xyz|a|w))?|"# + escaped(name)
                + #"(?:\.(?:rgb|xyz|a|w))?\s*(?:\+\+|--))[ \t]*;[ \t]*$"#,
            in: source
        ).count
        return assigned + incremented
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

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source)
        else {
            return nil
        }
        return String(source[range])
    }

    private static func escaped(_ value: String) -> String {
        NSRegularExpression.escapedPattern(for: value)
    }
}

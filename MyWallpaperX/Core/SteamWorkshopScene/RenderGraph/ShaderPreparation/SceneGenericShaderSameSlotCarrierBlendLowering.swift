import Foundation

/// Independently verifies the compiler form of a source-proven same-slot
/// carrier blend before moving every color sample into straight space and the
/// one terminal output back to the premultiplied compositor boundary.
nonisolated enum SceneGenericShaderSameSlotCarrierBlendLowering {
    private struct SampleCall {
        let range: Range<String.Index>
        let slot: Int
    }

    static func lower(_ source: String, expectedSlot: Int) -> String? {
        guard matches(#"\bmwxGeneric(?:Unpremultiply|Premultiply)\b"#, in: source)
                .isEmpty,
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1
        else { return nil }

        let slot = String(expectedSlot)
        let declarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + slot + #"\.sample\(([^;\n]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*$"#,
            in: source
        )
        guard declarations.count == 1,
              outputs.count == 1,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              let declaration = declarations.first,
              let carrier = capture(declaration, 2, in: source),
              let output = outputs.first,
              capture(output, 2, in: source) == carrier,
              let outputRange = Range(output.range, in: source),
              let indent = capture(output, 1, in: source)
        else { return nil }

        let carrierPattern = escaped(carrier)
        let projected = matches(
            #"(?m)^[ \t]*"# + carrierPattern
                + #"\.([xyz])\s*=\s*g_Texture"# + slot
                + #"\.sample\(([^;\n]+)\)\.([xyz])\s*;[ \t]*$"#,
            in: source
        )
        let projectedTargets = projected.compactMap {
            capture($0, 1, in: source)
        }
        let projectedSources = projected.compactMap {
            capture($0, 3, in: source)
        }
        guard (1 ... 3).contains(projected.count),
              projectedTargets.count == projected.count,
              projectedTargets == projectedSources,
              Set(projectedTargets).count == projected.count
        else { return nil }

        let blendSources = matches(
            #"(?m)^[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*g_Texture"#
                + slot + #"\.sample\(([^;\n]+)\)\.xyz\s*;[ \t]*$"#,
            in: source
        )
        let carrierAliases = matches(
            #"(?m)^[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*"#
                + carrierPattern + #"\.xyz\s*;[ \t]*$"#,
            in: source
        )
        guard blendSources.count == 1,
              carrierAliases.count == 1,
              let blendSource = capture(blendSources[0], 1, in: source),
              let carrierAlias = capture(carrierAliases[0], 1, in: source)
        else { return nil }

        let blendResults = matches(
            #"(?m)^[ \t]*float3\s+([A-Za-z_]\w*)\s*=\s*ApplyBlending\(\s*[^,;\n]+\s*,\s*"#
                + escaped(blendSource) + #"\s*,\s*"#
                + escaped(carrierAlias) + #"\s*,\s*[^;\n]+\)\s*;[ \t]*$"#,
            in: source
        )
        guard blendResults.count == 1,
              let blendResult = capture(blendResults[0], 1, in: source)
        else { return nil }

        let resultWrites = matches(
            #"(?m)^[ \t]*"# + carrierPattern
                + #"\.([xyz])\s*=\s*"# + escaped(blendResult)
                + #"\.([xyz])\s*;[ \t]*$"#,
            in: source
        )
        let resultTargets = resultWrites.compactMap {
            capture($0, 1, in: source)
        }
        let resultSources = resultWrites.compactMap {
            capture($0, 2, in: source)
        }
        guard resultWrites.count == 3,
              resultTargets == resultSources,
              Set(resultTargets) == Set(["x", "y", "z"]),
              declaration.range.location < projected.map(\.range.location).min()!,
              projected.map(\.range.location).max()! < blendSources[0].range.location,
              blendSources[0].range.location < carrierAliases[0].range.location,
              carrierAliases[0].range.location < blendResults[0].range.location,
              blendResults[0].range.location
                < resultWrites.map(\.range.location).min()!,
              resultWrites.map(\.range.location).max()! < output.range.location,
              countWord(carrier, in: source) == projected.count + 6,
              countWord(blendSource, in: source) == 2,
              countWord(carrierAlias, in: source) == 2,
              countWord(blendResult, in: source) == 4
        else { return nil }

        let sampleCalls = sampleCalls(in: source)
        guard sampleCalls.count == projected.count + 2,
              sampleCalls.allSatisfy({ $0.slot == expectedSlot })
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = mwxGenericPremultiply(\(carrier));"
        )
        for call in sampleCalls.sorted(by: {
            $0.range.lowerBound > $1.range.lowerBound
        }) {
            let text = transformed[call.range]
            transformed.replaceSubrange(
                call.range,
                with: "mwxGenericUnpremultiply(\(text))"
            )
        }
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private static func sampleCalls(in source: String) -> [SampleCall] {
        let starts = matches(#"\bg_Texture([0-7])\.sample\s*\("#, in: source)
        return starts.compactMap { match in
            guard let slotText = capture(match, 1, in: source),
                  let slot = Int(slotText),
                  let start = Range(match.range, in: source)?.lowerBound,
                  let open = Range(match.range, in: source).map({
                    source.index(before: $0.upperBound)
                  }) else { return nil }
            var depth = 0
            var cursor = open
            while cursor < source.endIndex {
                if source[cursor] == "(" { depth += 1 }
                if source[cursor] == ")" {
                    depth -= 1
                    if depth == 0 {
                        return .init(
                            range: start..<source.index(after: cursor),
                            slot: slot
                        )
                    }
                    if depth < 0 { return nil }
                }
                cursor = source.index(after: cursor)
            }
            return nil
        }
    }

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
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
              let range = Range(match.range(at: index), in: source) else {
            return nil
        }
        return String(source[range])
    }
}

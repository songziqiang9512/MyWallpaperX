import Foundation

nonisolated extension SceneGenericShaderStraightAlphaPreservingLowering {
    struct CompilerTextureSampleCall {
        let range: NSRange
        let slot: Int
    }

    /// Validates the compiler's sample topology and projection contract for a
    /// source-proven preserved-alpha RGB filter. The exact lowering may reject
    /// a different output shape, but the boundary fallback must never accept a
    /// hidden sample or a changed data/color projection under the same source
    /// fact. Returning the parsed calls lets the exact lowering reuse this
    /// proof without a second text scan.
    static func preservedAlphaRGBFilterCompilerSamplesMatch(
        in source: String,
        sourceSlot: Int,
        fullColorSampleCallCounts: [Int: Int],
        rgbColorSampleCallCounts: [Int: Int],
        dataSampleCallCounts: [Int: Int]
    ) -> Bool {
        validatedPreservedAlphaRGBFilterSampleCalls(
            in: source,
            sourceSlot: sourceSlot,
            fullColorSampleCallCounts: fullColorSampleCallCounts,
            rgbColorSampleCallCounts: rgbColorSampleCallCounts,
            dataSampleCallCounts: dataSampleCallCounts
        ) != nil
    }

    static func validatedPreservedAlphaRGBFilterSampleCalls(
        in source: String,
        sourceSlot: Int,
        fullColorSampleCallCounts: [Int: Int],
        rgbColorSampleCallCounts: [Int: Int],
        dataSampleCallCounts: [Int: Int]
    ) -> [CompilerTextureSampleCall]? {
        let colorSampleCallCounts = fullColorSampleCallCounts.merging(
            rgbColorSampleCallCounts,
            uniquingKeysWith: +
        )
        let sampleCounts = Array(colorSampleCallCounts.values)
            + Array(dataSampleCallCounts.values)
        guard !colorSampleCallCounts.isEmpty,
              fullColorSampleCallCounts[sourceSlot] != nil,
              sampleCounts.allSatisfy({ (1 ... 16).contains($0) }),
              sampleCounts.reduce(0, +) <= 32,
              !dataSampleCallCounts.isEmpty
                || colorSampleCallCounts.keys.count >= 2,
              Set(colorSampleCallCounts.keys).isDisjoint(
                  with: dataSampleCallCounts.keys
              ),
              !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let calls = compilerTextureSampleCalls(in: source) else {
            return nil
        }
        let expectedTotal = colorSampleCallCounts.values.reduce(0, +)
            + dataSampleCallCounts.values.reduce(0, +)
        guard calls.count == expectedTotal else { return nil }
        var observedFullColorCounts: [Int: Int] = [:]
        var observedRGBColorCounts: [Int: Int] = [:]
        var observedDataCounts: [Int: Int] = [:]
        for call in calls {
            guard let range = Range(call.range, in: source) else { return nil }
            let suffix = source[range.upperBound...]
            if dataSampleCallCounts[call.slot] != nil {
                guard suffix.range(
                    of: #"^\.(?:xy|rg)\b"#,
                    options: .regularExpression
                ) != nil else { return nil }
                observedDataCounts[call.slot, default: 0] += 1
            } else if rgbColorSampleCallCounts[call.slot] != nil,
                      suffix.range(
                          of: #"^\.(?:xyz|rgb)\b"#,
                          options: .regularExpression
                      ) != nil {
                observedRGBColorCounts[call.slot, default: 0] += 1
            } else if fullColorSampleCallCounts[call.slot] != nil,
                      suffix.range(
                          of: #"^\s*;"#,
                          options: .regularExpression
                      ) != nil {
                observedFullColorCounts[call.slot, default: 0] += 1
            } else {
                return nil
            }
        }
        guard observedFullColorCounts == fullColorSampleCallCounts,
              observedRGBColorCounts == rgbColorSampleCallCounts,
              observedDataCounts == dataSampleCallCounts else { return nil }
        return calls
    }

    static func compilerTextureSampleCalls(
        in source: String
    ) -> [CompilerTextureSampleCall]? {
        let starts = matches(#"\bg_Texture([0-7])\.sample\("#, in: source)
        var result: [CompilerTextureSampleCall] = []
        for start in starts {
            guard let rawSlot = capture(start, 1, in: source),
                  let slot = Int(rawSlot),
                  let startRange = Range(start.range, in: source),
                  let open = source[..<startRange.upperBound].lastIndex(of: "(")
            else { return nil }
            var depth = 0
            var close: String.Index?
            var cursor = open
            while cursor < source.endIndex {
                let character = source[cursor]
                if character == "(" { depth += 1 }
                if character == ")" {
                    depth -= 1
                    if depth == 0 {
                        close = cursor
                        break
                    }
                    if depth < 0 { return nil }
                }
                cursor = source.index(after: cursor)
            }
            guard let close else { return nil }
            let range = startRange.lowerBound..<source.index(after: close)
            result.append(.init(range: NSRange(range, in: source), slot: slot))
        }
        return result
    }

    static func insertingBoundaryHelpers(into source: String) -> String? {
        let helpers = """

inline float4 \(unpremultiply)(float4 color) {
    const float alpha = clamp(color.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0
        ? clamp(color.xyz / alpha, float3(0.0), float3(1.0))
        : float3(0.0);
    return float4(rgb, alpha);
}

inline float4 \(premultiply)(float4 color) {
    const float alpha = clamp(color.w, 0.0, 1.0);
    return float4(color.xyz * alpha, alpha);
}
"""
        guard let namespace = source.range(
            of: #"\busing\s+namespace\s+metal\s*;"#,
            options: .regularExpression
        ) else { return nil }
        var transformed = source
        transformed.insert(contentsOf: helpers, at: namespace.upperBound)
        return transformed
    }

    /// Conserves the strict source-carried generated RGBA proof through the
    /// SPIRV-Cross MSL shape.  The compiler commonly expands the RGB helper
    /// call into three temporary values and component writes; this verifier
    /// accepts that exact lowering (and the direct equivalent), while keeping
    /// the one sampled source and one terminal carrier boundaries explicit.
    static func lowerGeneratedSourceCarried(
        _ source: String,
        expectedSlot: Int,
        expectedTransfer: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer
            .SourceCarriedTransfer
    ) -> String? {
        guard (0 ..< 8).contains(expectedSlot),
              !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let samples = compilerTextureSampleCalls(in: source),
              samples.count == 1,
              samples[0].slot == expectedSlot else { return nil }

        let sampleDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard sampleDeclarations.count == 1,
              let sampleDeclaration = sampleDeclarations.first,
              let sampleLocal = capture(sampleDeclaration, 2, in: source),
              let sampleArguments = capture(sampleDeclaration, 3, in: source),
              let samplePrefix = capture(sampleDeclaration, 1, in: source),
              let sampleSuffix = capture(sampleDeclaration, 4, in: source) else {
            return nil
        }

        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*$"#,
            in: source
        )
        guard outputs.count == 1,
              let output = outputs.first,
              let carrier = capture(output, 2, in: source),
              carrier != sampleLocal,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              matches(#"(?m)^[ \t]*return\s+out\s*;[ \t]*$"#, in: source).count == 1,
              sampleDeclaration.range.location < output.range.location else {
            return nil
        }

        let carrierDefinitions = matches(
            #"(?m)^[ \t]*float4\s+"# + escaped(carrier)
                + #"\s*=\s*float4\([^;]+\)\s*;[ \t]*$"#,
            in: source
        )
        guard carrierDefinitions.count == 1,
              carrierDefinitions[0].range.location < output.range.location else {
            return nil
        }

        guard compilerGeneratedCarrierBranch(
            source,
            carrier: carrier,
            sampleLocal: sampleLocal,
            before: output.range.location
        ) else { return nil }

        guard compilerNormalApplyBlending(source),
              let rgbFlow = compilerGeneratedRGBFlow(
                  source,
                  carrier: carrier,
                  sampleLocal: sampleLocal,
                  before: output.range.location
              ),
              let alphaFlow = compilerGeneratedAlphaFlow(
                  source,
                  carrier: carrier,
                  sampleLocal: sampleLocal,
                  before: output.range.location
              ),
              rgbFlow.weight == alphaFlow,
              compilerTransparencyHelper(
                  source,
                  transfer: expectedTransfer
              ),
              compilerCarrierUseCounts(
                  source,
                  carrier: carrier,
                  sampleLocal: sampleLocal,
                  branchPresent: compilerHasTrueBranch(
                      source,
                      before: output.range.location
                  )
              ) else { return nil }

        var transformed = source
        guard let outputRange = Range(output.range, in: transformed),
              let outputIndent = capture(output, 1, in: source),
              let declarationRange = Range(sampleDeclaration.range, in: transformed) else {
            return nil
        }
        transformed.replaceSubrange(
            outputRange,
            with: "\(outputIndent)out.mwxFragColor = \(premultiply)(\(carrier));"
        )
        transformed.replaceSubrange(
            declarationRange,
            with: "\(samplePrefix)\(unpremultiply)(g_Texture\(expectedSlot).sample(\(sampleArguments)))\(sampleSuffix)"
        )
        return insertingBoundaryHelpers(into: transformed)
    }

    private static func compilerGeneratedCarrierBranch(
        _ source: String,
        carrier: String,
        sampleLocal: String,
        before boundary: Int
    ) -> Bool {
        let branches = matches(
            #"(?s)\bif\s*\(\s*true\s*\)\s*\{([^{}]*)\}"#,
            in: source
        )
        let allIfs = matches(#"\bif\s*\("#, in: source)
        guard allIfs.count == branches.count, branches.count <= 1 else {
            return false
        }
        guard let branch = branches.first else { return true }
        guard branch.range.location < boundary,
              let body = capture(branch, 1, in: source),
              !body.contains(sampleLocal),
              !body.contains("g_Texture"),
              !body.contains("mwxFragColor"),
              countWord(carrier, in: body) == 2 else { return false }
        let assignment = matches(
            #"(?m)^\s*"# + escaped(carrier)
                + #"\s*=\s*(?:mix|lerp)\s*\(\s*"# + escaped(carrier)
                + #"\s*,\s*float4\([^;]+\)\s*,\s*float4\([^;]+\)\s*\)\s*;\s*$"#,
            in: body
        )
        return assignment.count == 1
    }

    private static func compilerHasTrueBranch(
        _ source: String,
        before boundary: Int
    ) -> Bool {
        matches(
            #"(?s)\bif\s*\(\s*true\s*\)\s*\{[^{}]*\}"#,
            in: source
        ).contains { $0.range.location < boundary }
    }

    private static func compilerNormalApplyBlending(_ source: String) -> Bool {
        let functions = matches(
            #"(?s)\bfloat3\s+ApplyBlending\s*\(([^)]*)\)\s*\{([^{}]*)\}"#,
            in: source
        )
        guard functions.count == 1,
              let parameters = capture(functions[0], 1, in: source),
              let body = capture(functions[0], 2, in: source) else {
            return false
        }
        let parameterMatch = matches(
            #"^\s*int\s+([A-Za-z_]\w*)\s*,\s*thread\s+const\s+float3\s*&\s*([A-Za-z_]\w*)\s*,\s*thread\s+const\s+float3\s*&\s*([A-Za-z_]\w*)\s*,\s*thread\s+const\s+float\s*&\s*([A-Za-z_]\w*)\s*$"#,
            in: parameters
        )
        guard parameterMatch.count == 1,
              let mode = capture(parameterMatch[0], 1, in: parameters),
              let base = capture(parameterMatch[0], 2, in: parameters),
              let blend = capture(parameterMatch[0], 3, in: parameters),
              let opacity = capture(parameterMatch[0], 4, in: parameters) else {
            return false
        }
        let compactBody = body.replacingOccurrences(
            of: #"\s+"#, with: "", options: .regularExpression
        )
        let expected = "returnmix(\(base),\(blend),float3(\(opacity)));"
        let alternate = "returnmix(\(base),\(blend),\(opacity));"
        return mode != base && mode != blend && mode != opacity
            && (compactBody == expected || compactBody == alternate)
    }

    private static func compilerTransparencyHelper(
        _ source: String,
        transfer: SceneAuthoredShaderGeneratedStraightRGBAAnalyzer.SourceCarriedTransfer
    ) -> Bool {
        let functions = matches(
            #"(?s)\bfloat\s+BlendTransparency\s*\(([^)]*)\)\s*\{([^{}]*)\}"#,
            in: source
        )
        guard functions.count == 1,
              let parameters = capture(functions[0], 1, in: source),
              let body = capture(functions[0], 2, in: source) else {
            return false
        }
        let parameterMatch = matches(
            #"^\s*float\s+([A-Za-z_]\w*)\s*,\s*float\s+([A-Za-z_]\w*)\s*,\s*float\s+([A-Za-z_]\w*)\s*$"#,
            in: parameters
        )
        guard parameterMatch.count == 1,
              let base = capture(parameterMatch[0], 1, in: parameters),
              let blend = capture(parameterMatch[0], 2, in: parameters),
              let opacity = capture(parameterMatch[0], 3, in: parameters) else {
            return false
        }
        let compact = body.replacingOccurrences(
            of: #"\s+"#, with: "", options: .regularExpression
        )
        let direct = "returnmix(\(base),\(blend),\(opacity));"
        if case .straight = transfer { return compact == direct }
        let localMatch = matches(
            #"^float([A-Za-z_]\w*)=([A-Za-z_]\w*);returnmix\("#,
            in: compact
        )
        guard localMatch.count == 1,
              let local = capture(localMatch[0], 1, in: compact),
              let seed = capture(localMatch[0], 2, in: compact) else {
            return false
        }
        let expected = "float\(local)=\(base);returnmix(\(base),\(local),\(opacity));"
        return seed == base && compact == expected
    }

    private static func compilerGeneratedRGBFlow(
        _ source: String,
        carrier: String,
        sampleLocal: String,
        before boundary: Int
    ) -> (weight: String, result: String)? {
        let calls = matches(
            #"(?m)^\s*float3\s+([A-Za-z_]\w*)\s*=\s*ApplyBlending\(\s*0\s*,\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*\)\s*;\s*$"#,
            in: source
        ).filter { $0.range.location < boundary }
        guard calls.count == 1,
              let call = calls.first,
              let result = capture(call, 1, in: source),
              let sourceAlias = capture(call, 2, in: source),
              let carrierAlias = capture(call, 3, in: source),
              let weightAlias = capture(call, 4, in: source) else { return nil }
        guard matches(
            #"(?m)^\s*float3\s+"# + escaped(sourceAlias)
                + #"\s*=\s*"# + escaped(sampleLocal) + #"\.(?:xyz|rgb)\s*;\s*$"#,
            in: source
        ).count == 1,
        matches(
            #"(?m)^\s*float3\s+"# + escaped(carrierAlias)
                + #"\s*=\s*"# + escaped(carrier) + #"\.(?:xyz|rgb)\s*;\s*$"#,
            in: source
        ).count == 1,
        let weightMatch = matches(
            #"(?m)^\s*float\s+"# + escaped(weightAlias)
                + #"\s*=\s*"# + escaped(carrier) + #"\.(?:w|a)\s*\*\s*([^;]+)\s*;\s*$"#,
            in: source
        ).first,
        let weight = capture(weightMatch, 1, in: source),
        compilerScalar(weight, in: source),
        (0..<3).allSatisfy({ component in
            let names = ["x", "y", "z"]
            return matches(
                #"(?m)^\s*"# + escaped(carrier) + #"\."# + names[component]
                    + #"\s*=\s*"# + escaped(result) + #"\."# + names[component]
                    + #"\s*;\s*$"#,
                in: source
            ).count == 1
        }) else { return nil }
        return (weight.trimmingCharacters(in: .whitespacesAndNewlines), result)
    }

    private static func compilerGeneratedAlphaFlow(
        _ source: String,
        carrier: String,
        sampleLocal: String,
        before boundary: Int
    ) -> String? {
        let pattern = #"(?m)^\s*"# + escaped(carrier)
            + #"\.(?:w|a)\s*=\s*BlendTransparency\(\s*"#
            + escaped(sampleLocal) + #"\.(?:w|a)\s*,\s*"#
            + escaped(carrier) + #"\.(?:w|a)\s*,\s*([^,)]+)\s*\)\s*;\s*$"#
        let matches = matches(pattern, in: source).filter {
            $0.range.location < boundary
        }
        guard matches.count == 1, let weight = capture(matches[0], 1, in: source),
              compilerScalar(weight, in: source) else { return nil }
        return weight.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compilerScalar(_ raw: String, in source: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let numeric = try! NSRegularExpression(
            pattern: #"^[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?[fF]?$"#
        )
        if numeric.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil {
            return Double(value.trimmingCharacters(in: CharacterSet(charactersIn: "fF")))?.isFinite == true
        }
        let field = try! NSRegularExpression(
            pattern: #"^([A-Za-z_]\w*)\.([A-Za-z_]\w*)$"#
        )
        guard let match = field.firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ), let object = capture(match, 1, in: value),
        let member = capture(match, 2, in: value) else { return false }
        return matches(
            #"(?m)^\s*float\s+"# + escaped(member) + #"\s*;"#,
            in: source
        ).count == 1 && !object.isEmpty
    }

    private static func compilerCarrierUseCounts(
        _ source: String,
        carrier: String,
        sampleLocal: String,
        branchPresent: Bool
    ) -> Bool {
        let expected = branchPresent ? 11 : 9
        return countWord(carrier, in: source) == expected
            && countWord(sampleLocal, in: source) == 3
    }

    static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        try! NSRegularExpression(pattern: pattern).matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }

    static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }

    static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else { return nil }
        return String(source[range])
    }

}

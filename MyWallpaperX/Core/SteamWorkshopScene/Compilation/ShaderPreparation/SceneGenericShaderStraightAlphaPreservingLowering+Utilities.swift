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
        dataSampleCallCounts: [Int: Int],
        scalarDataSampleCallCounts: [Int: Int] = [:]
    ) -> Bool {
        validatedPreservedAlphaRGBFilterSampleCalls(
            in: source,
            sourceSlot: sourceSlot,
            fullColorSampleCallCounts: fullColorSampleCallCounts,
            rgbColorSampleCallCounts: rgbColorSampleCallCounts,
            dataSampleCallCounts: dataSampleCallCounts,
            scalarDataSampleCallCounts: scalarDataSampleCallCounts
        ) != nil
    }

    static func validatedPreservedAlphaRGBFilterSampleCalls(
        in source: String,
        sourceSlot: Int,
        fullColorSampleCallCounts: [Int: Int],
        rgbColorSampleCallCounts: [Int: Int],
        dataSampleCallCounts: [Int: Int],
        scalarDataSampleCallCounts: [Int: Int] = [:]
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
              scalarDataSampleCallCounts.allSatisfy({ slot, count in
                  count > 0 && count <= dataSampleCallCounts[slot, default: 0]
              }),
              !SceneShaderSourceTextFacts.containsWord(unpremultiply, in: source),
              !SceneShaderSourceTextFacts.containsWord(premultiply, in: source),
              SceneShaderSourceTextFacts.matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let calls = compilerTextureSampleCalls(in: source) else {
            return nil
        }
        let expectedTotal = colorSampleCallCounts.values.reduce(0, +)
            + dataSampleCallCounts.values.reduce(0, +)
        guard calls.count == expectedTotal else { return nil }
        var observedFullColorCounts: [Int: Int] = [:]
        var observedRGBColorCounts: [Int: Int] = [:]
        var observedDataCounts: [Int: Int] = [:]
        var observedScalarDataCounts: [Int: Int] = [:]
        for call in calls {
            guard let range = Range(call.range, in: source) else { return nil }
            let suffix = source[range.upperBound...]
            if dataSampleCallCounts[call.slot] != nil {
                if suffix.range(
                    of: #"^\.(?:x|r)\b"#,
                    options: .regularExpression
                ) != nil {
                    observedScalarDataCounts[call.slot, default: 0] += 1
                } else {
                    guard suffix.range(
                        of: #"^\.(?:xy|rg)\b"#,
                        options: .regularExpression
                    ) != nil else { return nil }
                }
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
              observedDataCounts == dataSampleCallCounts,
              observedScalarDataCounts == scalarDataSampleCallCounts else {
            return nil
        }
        return calls
    }

    static func compilerTextureSampleCalls(
        in source: String
    ) -> [CompilerTextureSampleCall]? {
        let starts = SceneShaderSourceTextFacts.matches(#"\bg_Texture([0-7])\.sample\("#, in: source)
        var result: [CompilerTextureSampleCall] = []
        for start in starts {
            guard let rawSlot = SceneShaderSourceTextFacts.capture(start, 1, in: source),
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
              !SceneShaderSourceTextFacts.containsWord(unpremultiply, in: source),
              !SceneShaderSourceTextFacts.containsWord(premultiply, in: source),
              SceneShaderSourceTextFacts.matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let samples = compilerTextureSampleCalls(in: source),
              samples.count == 1,
              samples[0].slot == expectedSlot else { return nil }

        let sampleDeclarations = SceneShaderSourceTextFacts.matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(expectedSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard sampleDeclarations.count == 1,
              let sampleDeclaration = sampleDeclarations.first,
              let sampleLocal = SceneShaderSourceTextFacts.capture(sampleDeclaration, 2, in: source),
              let sampleArguments = SceneShaderSourceTextFacts.capture(sampleDeclaration, 3, in: source),
              let samplePrefix = SceneShaderSourceTextFacts.capture(sampleDeclaration, 1, in: source),
              let sampleSuffix = SceneShaderSourceTextFacts.capture(sampleDeclaration, 4, in: source) else {
            return nil
        }

        let outputs = SceneShaderSourceTextFacts.matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*$"#,
            in: source
        )
        guard outputs.count == 1,
              let output = outputs.first,
              let carrier = SceneShaderSourceTextFacts.capture(output, 2, in: source),
              carrier != sampleLocal,
              SceneShaderSourceTextFacts.matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              SceneShaderSourceTextFacts.matches(#"(?m)^[ \t]*return\s+out\s*;[ \t]*$"#, in: source).count == 1,
              sampleDeclaration.range.location < output.range.location else {
            return nil
        }

        let carrierDefinitions = SceneShaderSourceTextFacts.matches(
            #"(?m)^[ \t]*float4\s+"# + SceneShaderSourceTextFacts.escaped(carrier)
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
              let outputIndent = SceneShaderSourceTextFacts.capture(output, 1, in: source),
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
        let branches = SceneShaderSourceTextFacts.matches(
            #"(?s)\bif\s*\(\s*true\s*\)\s*\{([^{}]*)\}"#,
            in: source
        )
        let allIfs = SceneShaderSourceTextFacts.matches(#"\bif\s*\("#, in: source)
        guard allIfs.count == branches.count, branches.count <= 1 else {
            return false
        }
        guard let branch = branches.first else { return true }
        guard branch.range.location < boundary,
              let body = SceneShaderSourceTextFacts.capture(branch, 1, in: source),
              !body.contains(sampleLocal),
              !body.contains("g_Texture"),
              !body.contains("mwxFragColor"),
              SceneShaderSourceTextFacts.countWord(carrier, in: body) == 2 else { return false }
        let assignment = SceneShaderSourceTextFacts.matches(
            #"(?m)^\s*"# + SceneShaderSourceTextFacts.escaped(carrier)
                + #"\s*=\s*(?:mix|lerp)\s*\(\s*"# + SceneShaderSourceTextFacts.escaped(carrier)
                + #"\s*,\s*float4\([^;]+\)\s*,\s*float4\([^;]+\)\s*\)\s*;\s*$"#,
            in: body
        )
        return assignment.count == 1
    }

    private static func compilerHasTrueBranch(
        _ source: String,
        before boundary: Int
    ) -> Bool {
        SceneShaderSourceTextFacts.matches(
            #"(?s)\bif\s*\(\s*true\s*\)\s*\{[^{}]*\}"#,
            in: source
        ).contains { $0.range.location < boundary }
    }

    private static func compilerNormalApplyBlending(_ source: String) -> Bool {
        let functions = SceneShaderSourceTextFacts.matches(
            #"(?s)\bfloat3\s+ApplyBlending\s*\(([^)]*)\)\s*\{([^{}]*)\}"#,
            in: source
        )
        guard functions.count == 1,
              let parameters = SceneShaderSourceTextFacts.capture(functions[0], 1, in: source),
              let body = SceneShaderSourceTextFacts.capture(functions[0], 2, in: source) else {
            return false
        }
        let parameterMatch = SceneShaderSourceTextFacts.matches(
            #"^\s*int\s+([A-Za-z_]\w*)\s*,\s*thread\s+const\s+float3\s*&\s*([A-Za-z_]\w*)\s*,\s*thread\s+const\s+float3\s*&\s*([A-Za-z_]\w*)\s*,\s*thread\s+const\s+float\s*&\s*([A-Za-z_]\w*)\s*$"#,
            in: parameters
        )
        guard parameterMatch.count == 1,
              let mode = SceneShaderSourceTextFacts.capture(parameterMatch[0], 1, in: parameters),
              let base = SceneShaderSourceTextFacts.capture(parameterMatch[0], 2, in: parameters),
              let blend = SceneShaderSourceTextFacts.capture(parameterMatch[0], 3, in: parameters),
              let opacity = SceneShaderSourceTextFacts.capture(parameterMatch[0], 4, in: parameters) else {
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
        let functions = SceneShaderSourceTextFacts.matches(
            #"(?s)\bfloat\s+BlendTransparency\s*\(([^)]*)\)\s*\{([^{}]*)\}"#,
            in: source
        )
        guard functions.count == 1,
              let parameters = SceneShaderSourceTextFacts.capture(functions[0], 1, in: source),
              let body = SceneShaderSourceTextFacts.capture(functions[0], 2, in: source) else {
            return false
        }
        let parameterMatch = SceneShaderSourceTextFacts.matches(
            #"^\s*float\s+([A-Za-z_]\w*)\s*,\s*float\s+([A-Za-z_]\w*)\s*,\s*float\s+([A-Za-z_]\w*)\s*$"#,
            in: parameters
        )
        guard parameterMatch.count == 1,
              let base = SceneShaderSourceTextFacts.capture(parameterMatch[0], 1, in: parameters),
              let blend = SceneShaderSourceTextFacts.capture(parameterMatch[0], 2, in: parameters),
              let opacity = SceneShaderSourceTextFacts.capture(parameterMatch[0], 3, in: parameters) else {
            return false
        }
        let compact = body.replacingOccurrences(
            of: #"\s+"#, with: "", options: .regularExpression
        )
        let direct = "returnmix(\(base),\(blend),\(opacity));"
        if case .straight = transfer { return compact == direct }
        let localMatch = SceneShaderSourceTextFacts.matches(
            #"^float([A-Za-z_]\w*)=([A-Za-z_]\w*);returnmix\("#,
            in: compact
        )
        guard localMatch.count == 1,
              let local = SceneShaderSourceTextFacts.capture(localMatch[0], 1, in: compact),
              let seed = SceneShaderSourceTextFacts.capture(localMatch[0], 2, in: compact) else {
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
        let calls = SceneShaderSourceTextFacts.matches(
            #"(?m)^\s*float3\s+([A-Za-z_]\w*)\s*=\s*ApplyBlending\(\s*0\s*,\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*\)\s*;\s*$"#,
            in: source
        ).filter { $0.range.location < boundary }
        guard calls.count == 1,
              let call = calls.first,
              let result = SceneShaderSourceTextFacts.capture(call, 1, in: source),
              let sourceAlias = SceneShaderSourceTextFacts.capture(call, 2, in: source),
              let carrierAlias = SceneShaderSourceTextFacts.capture(call, 3, in: source),
              let weightAlias = SceneShaderSourceTextFacts.capture(call, 4, in: source) else { return nil }
        guard SceneShaderSourceTextFacts.matches(
            #"(?m)^\s*float3\s+"# + SceneShaderSourceTextFacts.escaped(sourceAlias)
                + #"\s*=\s*"# + SceneShaderSourceTextFacts.escaped(sampleLocal) + #"\.(?:xyz|rgb)\s*;\s*$"#,
            in: source
        ).count == 1,
        SceneShaderSourceTextFacts.matches(
            #"(?m)^\s*float3\s+"# + SceneShaderSourceTextFacts.escaped(carrierAlias)
                + #"\s*=\s*"# + SceneShaderSourceTextFacts.escaped(carrier) + #"\.(?:xyz|rgb)\s*;\s*$"#,
            in: source
        ).count == 1,
        let weightMatch = SceneShaderSourceTextFacts.matches(
            #"(?m)^\s*float\s+"# + SceneShaderSourceTextFacts.escaped(weightAlias)
                + #"\s*=\s*"# + SceneShaderSourceTextFacts.escaped(carrier) + #"\.(?:w|a)\s*\*\s*([^;]+)\s*;\s*$"#,
            in: source
        ).first,
        let weight = SceneShaderSourceTextFacts.capture(weightMatch, 1, in: source),
        compilerScalar(weight, in: source),
        (0..<3).allSatisfy({ component in
            let names = ["x", "y", "z"]
            return SceneShaderSourceTextFacts.matches(
                #"(?m)^\s*"# + SceneShaderSourceTextFacts.escaped(carrier) + #"\."# + names[component]
                    + #"\s*=\s*"# + SceneShaderSourceTextFacts.escaped(result) + #"\."# + names[component]
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
        let pattern = #"(?m)^\s*"# + SceneShaderSourceTextFacts.escaped(carrier)
            + #"\.(?:w|a)\s*=\s*BlendTransparency\(\s*"#
            + SceneShaderSourceTextFacts.escaped(sampleLocal) + #"\.(?:w|a)\s*,\s*"#
            + SceneShaderSourceTextFacts.escaped(carrier) + #"\.(?:w|a)\s*,\s*([^,)]+)\s*\)\s*;\s*$"#
        let matches = SceneShaderSourceTextFacts.matches(pattern, in: source).filter {
            $0.range.location < boundary
        }
        guard matches.count == 1, let weight = SceneShaderSourceTextFacts.capture(matches[0], 1, in: source),
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
        ), let object = SceneShaderSourceTextFacts.capture(match, 1, in: value),
        let member = SceneShaderSourceTextFacts.capture(match, 2, in: value) else { return false }
        return SceneShaderSourceTextFacts.matches(
            #"(?m)^\s*float\s+"# + SceneShaderSourceTextFacts.escaped(member) + #"\s*;"#,
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
        return SceneShaderSourceTextFacts.countWord(carrier, in: source) == expected
            && SceneShaderSourceTextFacts.countWord(sampleLocal, in: source) == 3
    }

}

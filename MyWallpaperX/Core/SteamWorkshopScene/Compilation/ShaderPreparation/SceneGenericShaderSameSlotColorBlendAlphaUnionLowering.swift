import Foundation

nonisolated extension SceneGenericShaderArtifactBuilder {
    static func prepareSameSlotColorBlendAlphaUnion(
        msl source: String,
        authoredSource: String,
        expectedSlot: Int
    ) throws -> (
        msl: String,
        transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
    )? {
        guard let fact = SceneAuthoredShaderSameSlotColorBlendAlphaUnionAnalyzer
            .analyze(fragmentSource: authoredSource),
              fact.sourceSlot == expectedSlot else { return nil }
        guard let lowered =
                SceneGenericShaderSameSlotColorBlendAlphaUnionLowering
                    .lower(source, fact: fact) else {
            throw Failure.colorTransfer
        }
        return (
            lowered,
            artifactTransfer(kind: "straight-alpha", slot: expectedSlot)
        )
    }
}

/// Revalidates the compiler form of a source-proven two-read color blend and
/// moves only its same-slot RGBA reads across the straight-color boundary.
/// Optional opacity-mask samples remain scalar data. The sole terminal output
/// returns to premultiplied compositor storage once.
nonisolated enum SceneGenericShaderSameSlotColorBlendAlphaUnionLowering {
    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    static func lower(
        _ source: String,
        fact: SceneAuthoredShaderSameSlotColorBlendAlphaUnionAnalyzer.Fact
    ) -> String? {
        guard (0 ..< 8).contains(fact.sourceSlot),
              fact.maskSlot.map({ (0 ..< 8).contains($0) }) ?? true,
              fact.maskSlot != fact.sourceSlot,
              matches(#"\bmwxGeneric(?:Unpremultiply|Premultiply)\b"#, in: source)
                .isEmpty,
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let body = fragmentBodyRange(in: source),
              compilerBodyIsLinear(body, source: source),
              let calls = SceneGenericShaderStraightAlphaPreservingLowering
                .compilerTextureSampleCalls(in: source),
              calls.allSatisfy({ contains(body, $0.range) }) else { return nil }

        let expectedSlots = [fact.sourceSlot, fact.sourceSlot]
            + (fact.maskSlot.map { [$0] } ?? [])
        guard calls.map(\.slot).sorted() == expectedSlots.sorted() else {
            return nil
        }

        let colorDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(fact.sourceSlot)
                + #"\.sample\(([^;\n]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard colorDeclarations.count == 2,
              colorDeclarations.allSatisfy({ contains(body, $0.range) }),
              let base = capture(colorDeclarations[0], 2, in: source),
              let reflected = capture(colorDeclarations[1], 2, in: source),
              base != reflected else { return nil }

        if let maskSlot = fact.maskSlot {
            let masks = matches(
                #"(?m)^[ \t]*float\s+[A-Za-z_]\w*\s*=\s*g_Texture"#
                    + String(maskSlot)
                    + #"\.sample\([^;\n]+\)\.(?:x|r)\s*;[ \t]*$"#,
                in: source
            )
            guard masks.count == 1, contains(body, masks[0].range) else {
                return nil
            }
        }

        guard let rgb = compilerRGBBlend(
            in: source,
            body: body,
            base: base,
            reflected: reflected,
            mode: fact.blendMode
        ) else { return nil }

        let alphaWrites = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\.(?:w|a)\s*=\s*(?:fast::)?min\s*\(\s*1(?:\.0+)?f?\s*,\s*"#
                + #"(.+?)\s*\)\s*;[ \t]*$"#,
            in: source
        )
        guard alphaWrites.count == 1,
              let alpha = alphaWrites.first,
              contains(body, alpha.range),
              let alphaUnion = capture(alpha, 2, in: source),
              alphaUnionUsesSameFactor(
                alphaUnion,
                base: base,
                reflected: reflected,
                rgbFactor: rgb.factor
              ),
              matches(#"\bout\.mwxFragColor\b"#, in: source).count
                == rgb.outputWriteCount + 1,
              countWord(base, in: source) == 3,
              countWord(reflected, in: source) == 3,
              colorDeclarations[0].range.location
                < colorDeclarations[1].range.location,
              colorDeclarations[1].range.location < rgb.firstRange.location,
              NSMaxRange(rgb.lastRange) < alpha.range.location,
              terminalTail(after: alpha.range, within: body, source: source),
              matches(
                #"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#,
                in: source
              ).count == 1,
              let returnStatement = matches(
                #"(?m)^([ \t]*)return\s+out\s*;[ \t]*$"#,
                in: source
              ).first,
              contains(body, returnStatement.range),
              let returnRange = Range(returnStatement.range, in: source),
              let indent = capture(returnStatement, 1, in: source) else {
            return nil
        }

        var transformed = source
        transformed.replaceSubrange(
            returnRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(out.mwxFragColor);\n"
                + "\(indent)return out;"
        )
        let colorCalls = calls.filter { $0.slot == fact.sourceSlot }
        for call in colorCalls.sorted(by: {
            $0.range.location > $1.range.location
        }) {
            guard let originalRange = Range(call.range, in: source),
                  let adjustedRange = Range(call.range, in: transformed) else {
                return nil
            }
            transformed.replaceSubrange(
                adjustedRange,
                with: "\(unpremultiply)(\(source[originalRange]))"
            )
        }
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private struct CompilerRGBBlend {
        let factor: String
        let firstRange: NSRange
        let lastRange: NSRange
        let outputWriteCount: Int
    }

    private static func compilerRGBBlend(
        in source: String,
        body: NSRange,
        base: String,
        reflected: String,
        mode: Int
    ) -> CompilerRGBBlend? {
        let direct = matches(
            #"(?ms)^([ \t]*)out\.mwxFragColor\.(?:xyz|rgb)\s*=\s*ApplyBlending\s*\(\s*"#
                + String(mode) + #"\s*,\s*"#
                + escaped(base) + #"\.(?:xyz|rgb)\s*,\s*"#
                + escaped(reflected) + #"\.(?:xyz|rgb)\s*,\s*(.*?)\)\s*;[ \t]*$"#,
            in: source
        )
        if direct.count == 1, let match = direct.first,
           contains(body, match.range),
           let factor = capture(match, 2, in: source),
           !normalizedExpression(factor).isEmpty {
            return .init(
                factor: factor,
                firstRange: match.range,
                lastRange: match.range,
                outputWriteCount: 1
            )
        }

        let constantTemporary = matches(
            #"(?ms)^([ \t]*)float3\s+([A-Za-z_]\w*)\s*=\s*"#
                + escaped(base) + #"\.(?:xyz|rgb)\s*;\s*^\1float3\s+([A-Za-z_]\w*)\s*=\s*"#
                + escaped(reflected) + #"\.(?:xyz|rgb)\s*;\s*^\1float\s+([A-Za-z_]\w*)\s*=\s*(.*?)\s*;\s*^\1float3\s+([A-Za-z_]\w*)\s*=\s*ApplyBlending\s*\(\s*"#
                + String(mode) + #"\s*,\s*\2\s*,\s*\3\s*,\s*\4\s*\)\s*;\s*^\1out\.mwxFragColor\.x\s*=\s*\6\.x\s*;\s*^\1out\.mwxFragColor\.y\s*=\s*\6\.y\s*;\s*^\1out\.mwxFragColor\.z\s*=\s*\6\.z\s*;[ \t]*$"#,
            in: source
        )
        if constantTemporary.count == 1,
           let match = constantTemporary.first,
           contains(body, match.range),
           let factor = capture(match, 5, in: source),
           !normalizedExpression(factor).isEmpty {
            return .init(
                factor: factor,
                firstRange: match.range,
                lastRange: match.range,
                outputWriteCount: 3
            )
        }

        let temporary = matches(
            #"(?ms)^([ \t]*)int\s+([A-Za-z_]\w*)\s*=\s*"#
                + String(mode) + #"\s*;\s*^\1float3\s+([A-Za-z_]\w*)\s*=\s*"#
                + escaped(base) + #"\.(?:xyz|rgb)\s*;\s*^\1float3\s+([A-Za-z_]\w*)\s*=\s*"#
                + escaped(reflected) + #"\.(?:xyz|rgb)\s*;\s*^\1float\s+([A-Za-z_]\w*)\s*=\s*(.*?)\s*;\s*^\1float3\s+([A-Za-z_]\w*)\s*=\s*ApplyBlending\s*\(\s*\2\s*,\s*\3\s*,\s*\4\s*,\s*\5\s*\)\s*;\s*^\1out\.mwxFragColor\.x\s*=\s*\7\.x\s*;\s*^\1out\.mwxFragColor\.y\s*=\s*\7\.y\s*;\s*^\1out\.mwxFragColor\.z\s*=\s*\7\.z\s*;[ \t]*$"#,
            in: source
        )
        guard temporary.count == 1, let match = temporary.first,
              contains(body, match.range),
              let factor = capture(match, 6, in: source),
              !normalizedExpression(factor).isEmpty else { return nil }
        return .init(
            factor: factor,
            firstRange: match.range,
            lastRange: match.range,
            outputWriteCount: 3
        )
    }

    private static func alphaUnionUsesSameFactor(
        _ source: String,
        base: String,
        reflected: String,
        rgbFactor: String
    ) -> Bool {
        guard let sum = splitTopLevel(source, at: "+"), sum.count == 2,
              normalizedExpression(sum[0])
                == normalizedExpression("\(base).w"),
              let product = flattenedProductTerms(sum[1]),
              let rgbTerms = flattenedProductTerms(rgbFactor) else {
            return false
        }
        var alphaTerms = product.map(normalizedExpression)
        let reflectedTerms = ["\(reflected).w", "\(reflected).a"]
        guard let reflectedIndex = alphaTerms.firstIndex(where: {
            reflectedTerms.contains($0)
        }), alphaTerms.filter({ reflectedTerms.contains($0) }).count == 1 else {
            return false
        }
        alphaTerms.remove(at: reflectedIndex)
        return alphaTerms.sorted() == rgbTerms.map(normalizedExpression).sorted()
    }

    private static func flattenedProductTerms(_ source: String) -> [String]? {
        let stripped = normalizedExpression(source)
        guard !stripped.isEmpty else { return nil }
        guard let parts = splitTopLevel(stripped, at: "*") else {
            return [stripped]
        }
        var result: [String] = []
        for part in parts {
            guard let nested = flattenedProductTerms(part) else { return nil }
            result.append(contentsOf: nested)
        }
        return result
    }

    private static func splitTopLevel(
        _ source: String, at operation: Character
    ) -> [String]? {
        let value = normalizedExpression(source)
        var depth = 0
        var start = value.startIndex
        var result: [String] = []
        for index in value.indices {
            let character = value[index]
            if character == "(" || character == "[" { depth += 1 }
            if character == ")" || character == "]" { depth -= 1 }
            guard depth >= 0 else { return nil }
            if depth == 0, character == operation {
                guard start < index else { return nil }
                result.append(String(value[start..<index]))
                start = value.index(after: index)
            }
        }
        guard depth == 0 else { return nil }
        if result.isEmpty { return nil }
        guard start < value.endIndex else { return nil }
        result.append(String(value[start...]))
        return result
    }

    private static func normalizedExpression(_ source: String) -> String {
        var value = source.replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
        while value.first == "(", value.last == ")",
              balancedOuterParentheses(value) {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }

    private static func balancedOuterParentheses(_ source: String) -> Bool {
        var depth = 0
        for (offset, character) in source.enumerated() {
            if character == "(" { depth += 1 }
            if character == ")" { depth -= 1 }
            guard depth >= 0 else { return false }
            if depth == 0, offset != source.count - 1 { return false }
        }
        return depth == 0
    }

    private static func fragmentBodyRange(in source: String) -> NSRange? {
        let signatures = matches(#"\bfragment\b[^\{]*\{"#, in: source)
        guard signatures.count == 1,
              let range = Range(signatures[0].range, in: source),
              let opening = source[..<range.upperBound].lastIndex(of: "{") else {
            return nil
        }
        var depth = 0
        var cursor = opening
        while cursor < source.endIndex {
            if source[cursor] == "{" { depth += 1 }
            if source[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    return NSRange(
                        source.index(after: opening)..<cursor,
                        in: source
                    )
                }
                if depth < 0 { return nil }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func compilerBodyIsLinear(
        _ body: NSRange, source: String
    ) -> Bool {
        let text = (source as NSString).substring(with: body)
        return matches(#"\b(?:if|else|for|while|do|switch|discard)\b"#, in: text)
            .isEmpty
            && matches(#"\breturn\b"#, in: text).count == 1
    }

    private static func terminalTail(
        after output: NSRange,
        within body: NSRange,
        source: String
    ) -> Bool {
        guard NSMaxRange(output) <= NSMaxRange(body) else { return false }
        let tail = (source as NSString).substring(with: NSRange(
            location: NSMaxRange(output),
            length: NSMaxRange(body) - NSMaxRange(output)
        ))
        return matches(#"^\s*return\s+out\s*;\s*$"#, in: tail).count == 1
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    private static func matches(
        _ pattern: String, in source: String
    ) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) ?? []
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

    private static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }
}

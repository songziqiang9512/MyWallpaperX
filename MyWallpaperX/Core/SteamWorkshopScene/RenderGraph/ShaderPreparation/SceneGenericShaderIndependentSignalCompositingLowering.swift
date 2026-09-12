import Foundation

/// Conserves the color boundary for an exact source-proven composition with
/// ordered signal/color sampler roles. The color carrier is presented to the
/// authored program as straight RGBA and its sole output is repremultiplied;
/// the independent signal sample remains raw.
nonisolated enum SceneGenericShaderIndependentSignalCompositingLowering {
    private static let unpremultiply =
        "mwxGenericSignalCompositeUnpremultiply"
    private static let premultiply =
        "mwxGenericSignalCompositePremultiply"

    static func lower(
        _ source: String,
        expectedSignalSlot: Int,
        expectedColorSlot: Int,
        expectedUnderlaySlot: Int? = nil
    ) -> String? {
        let debug = ProcessInfo.processInfo.arguments.contains(
            "--mwx-debug-scene-evidence-dir"
        )
        guard (0 ..< 8).contains(expectedSignalSlot),
              (0 ..< 8).contains(expectedColorSlot),
              expectedSignalSlot != expectedColorSlot,
              expectedUnderlaySlot.map({
                  (0 ..< 8).contains($0)
                      && $0 != expectedSignalSlot
                      && $0 != expectedColorSlot
              }) ?? true,
              !containsWord(unpremultiply, in: source),
              !containsWord(premultiply, in: source),
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              let body = fragmentBody(in: source) else { return nil }

        let sampleCalls = matches(
            #"\bg_Texture([0-7])\.sample\s*\("#,
            in: source,
            range: body
        )
        let expectedSlots = Set(
            [expectedSignalSlot, expectedColorSlot]
                + (expectedUnderlaySlot.map { [$0] } ?? [])
        )
        // The signal prefix may contain additional typed samples (for
        // example a gradient lookup that modifies the signal carrier). The
        // analyzer has already proven that only the expected signal/color
        // roles participate in the compositing tail; preserve those samples
        // and lower only the proven color boundary.
        guard sampleCalls.count >= expectedSlots.count else { return nil }

        let declarationPattern =
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture([0-7])\.sample\(([^;]+)\)(\s*;[ \t]*)$"#
        let declarations = matches(
            declarationPattern, in: source, range: body
        )
        if debug {
            NSLog(
                "MWX DEBUG SCENE: phase=signal-compositing-lowering-shape expectedSlots=%@ sampleCalls=%d declarations=%d",
                expectedSlots.sorted().map(String.init).joined(separator: ","),
                sampleCalls.count,
                declarations.count
            )
        }
        guard declarations.count >= expectedSlots.count else { return nil }

        var bySlot: [Int: (match: NSTextCheckingResult, name: String)] = [:]
        for declaration in declarations {
            guard let slotText = capture(declaration, 3, in: source),
                  let slot = Int(slotText),
                  let name = capture(declaration, 2, in: source),
                  bySlot[slot] == nil else { return nil }
            bySlot[slot] = (declaration, name)
        }
        guard expectedSlots.isSubset(of: Set(bySlot.keys)),
              let signal = bySlot[expectedSignalSlot],
              let color = bySlot[expectedColorSlot],
              signal.name != color.name,
              countWord(signal.name, in: substring(body, source: source)) >= 2
        else { return nil }
        if debug {
            NSLog(
                "MWX DEBUG SCENE: phase=signal-compositing-lowering-bindings signal=%@ color=%@ slots=%@",
                signal.name,
                color.name,
                bySlot.keys.sorted().map(String.init).joined(separator: ",")
            )
        }

        let control = matches(
            #"\b(?:if|else|for|while|do|switch|case|discard|break|continue)\b|\?"#,
            in: source,
            range: body
        )
        let outputWrites = matches(
            #"(?m)^[ \t]*out\.mwxFragColor(?:\.([xyzwrgba]{1,4}))?\s*(?:[+\-*/]?=).*;[ \t]*$"#,
            in: source,
            range: body
        )
        let outputAssignments = matches(
            #"(?m)^[ \t]*out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*$"#,
            in: source,
            range: body
        )
        if debug {
            NSLog(
                "MWX DEBUG SCENE: phase=signal-compositing-lowering-tail control=%d outputWrites=%d outputAssignments=%d returns=%d outputName=%@ colorName=%@ colorBefore=%@ signalBefore=%@",
                control.count,
                outputWrites.count,
                outputAssignments.count,
                matches(#"\breturn\s+out\s*;"#, in: source, range: body).count,
                outputAssignments.first.map { capture($0, 1, in: source) ?? "-" } ?? "-",
                color.name,
                outputAssignments.first.map { color.match.range.location < $0.range.location ? "yes" : "no" } ?? "-",
                outputAssignments.first.map { signal.match.range.location < $0.range.location ? "yes" : "no" } ?? "-"
            )
        }
        let outputName = capture(outputAssignments[0], 1, in: source)
        // Orientation A keeps the color carrier as the output variable. The
        // signal-carrier orientation (proven by the analyzer at the authored
        // level) terminates with the signal variable after its rgb composites
        // the color carrier through the authored blending and its alpha
        // combines both carriers; mirror that proof on the compiled MSL
        // before accepting the terminal.
        let signalCarrierTail: Bool
        if outputName == signal.name {
            let colorRange = NSRange(
                location: color.match.range.location,
                length: outputAssignments[0].range.location
                    - color.match.range.location
            )
            let colorTemp = matches(
                #"(?m)^[ \t]*float3\s+\w+\s*=\s*"# + color.name + #"\.xyz\s*;[ \t]*$"#,
                in: source,
                range: colorRange
            )
            let signalTemp = matches(
                #"(?m)^[ \t]*float3\s+\w+\s*=\s*"# + signal.name + #"\.xyz\s*;[ \t]*$"#,
                in: source,
                range: colorRange
            )
            let blendedComponents = matches(
                #"(?m)^[ \t]*"# + signal.name
                    + #"\.([xyz])\s*=\s*\w+\.\1\s*;[ \t]*$"#,
                in: source,
                range: colorRange
            )
            let combinedAlpha = matches(
                #"(?m)^[ \t]*"# + signal.name
                    + #"\.w\s*=\s*(?:fast::)?(?:clamp|saturate)\(\s*"#
                    + color.name + #"\.w\s*\+\s*"# + signal.name + #"\.w\b[^;]*;"#,
                in: source,
                range: colorRange
            )
            signalCarrierTail = colorTemp.count == 1
                && signalTemp.count == 1
                && blendedComponents.count == 3
                && combinedAlpha.count == 1
        } else {
            signalCarrierTail = false
        }
        guard control.isEmpty,
              outputWrites.count == 1,
              outputAssignments.count == 1,
              outputName == color.name || signalCarrierTail,
              color.match.range.location < outputAssignments[0].range.location,
              signal.match.range.location < outputAssignments[0].range.location,
              matches(
                  #"\breturn\s+out\s*;"#, in: source, range: body
              ).count == 1 else { return nil }
        if debug { NSLog("MWX DEBUG SCENE: phase=signal-compositing-lowering-tail-accepted") }

        guard let outputRange = Range(outputAssignments[0].range, in: source),
              let outputName
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "out.mwxFragColor = \(premultiply)(\(outputName));"
        )
        let straightColorSlots = Set(
            [expectedColorSlot] + (expectedUnderlaySlot.map { [$0] } ?? [])
        )
        let straightDeclarations = straightColorSlots.compactMap { slot in
            bySlot[slot].map { (slot, $0) }
        }.sorted { $0.1.match.range.location > $1.1.match.range.location }
        guard straightDeclarations.count == straightColorSlots.count else {
            return nil
        }
        if debug {
            NSLog(
                "MWX DEBUG SCENE: phase=signal-compositing-lowering-declarations accepted=%d",
                straightDeclarations.count
            )
        }
        for (slot, declaration) in straightDeclarations {
            guard let adjustedRange = Range(declaration.match.range, in: transformed),
                  let prefix = capture(declaration.match, 1, in: source),
                  let arguments = capture(declaration.match, 4, in: source),
                  let suffix = capture(declaration.match, 5, in: source) else {
                return nil
            }
            transformed.replaceSubrange(
                adjustedRange,
                with: "\(prefix)\(unpremultiply)(g_Texture\(slot).sample(\(arguments)))\(suffix)"
            )
        }

        let helpers = """

inline float4 \(unpremultiply)(float4 value) {
    const float alpha = clamp(value.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0
        ? clamp(value.xyz / alpha, float3(0.0), float3(1.0))
        : float3(0.0);
    return float4(rgb, alpha);
}

inline float4 \(premultiply)(float4 value) {
    const float alpha = clamp(value.w, 0.0, 1.0);
    return float4(clamp(value.xyz, float3(0.0), float3(1.0)) * alpha, alpha);
}
"""
        guard let namespace = transformed.range(
            of: #"\busing\s+namespace\s+metal\s*;"#,
            options: .regularExpression
        ) else { return nil }
        if debug { NSLog("MWX DEBUG SCENE: phase=signal-compositing-lowering-complete") }
        transformed.insert(contentsOf: helpers, at: namespace.upperBound)
        return transformed
    }

    private static func fragmentBody(in source: String) -> NSRange? {
        let masked = maskComments(source)
        let signatures = matches(
            #"\bfragment\b[^\{;]*\bmwxGenericFragment\s*\([^\{;]*\)\s*\{"#,
            in: masked
        )
        guard signatures.count == 1,
              let signature = signatures.first,
              let signatureRange = Range(signature.range, in: masked) else {
            return nil
        }
        let opening = masked.index(before: signatureRange.upperBound)
        var cursor = opening
        var depth = 0
        while cursor < masked.endIndex {
            if masked[cursor] == "{" { depth += 1 }
            if masked[cursor] == "}" {
                depth -= 1
                if depth == 0 {
                    let start = masked.index(after: opening)
                    return NSRange(start..<cursor, in: masked)
                }
                if depth < 0 { return nil }
            }
            cursor = masked.index(after: cursor)
        }
        return nil
    }

    private static func maskComments(_ source: String) -> String {
        let pattern = #"/\*.*?\*/|//[^\n]*"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern, options: .dotMatchesLineSeparators
        ) else { return source }
        var masked = source
        for match in expression.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).reversed() {
            guard let range = Range(match.range, in: source) else { continue }
            masked.replaceSubrange(range, with: source[range].map {
                $0 == "\n" ? "\n" : " "
            })
        }
        return masked
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        !matches(#"\b"# + escaped(word) + #"\b"#, in: source).isEmpty
    }

    private static func countWord(_ word: String, in source: String) -> Int {
        matches(#"\b"# + escaped(word) + #"\b"#, in: source).count
    }

    private static func matches(
        _ pattern: String,
        in source: String,
        range: NSRange? = nil
    ) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(
            in: source,
            range: range ?? NSRange(source.startIndex..., in: source)
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

    private static func substring(_ range: NSRange, source: String) -> String {
        Range(range, in: source).map { String(source[$0]) } ?? ""
    }
}

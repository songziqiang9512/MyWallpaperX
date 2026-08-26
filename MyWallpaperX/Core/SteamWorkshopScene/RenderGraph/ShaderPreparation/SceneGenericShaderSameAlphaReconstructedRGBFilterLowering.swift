import Foundation

/// Revalidates the external compiler shape for a source-proven same-alpha RGB
/// reconstruction. Every color-slot sample crosses one straight-color
/// boundary, typed-data samples remain untouched, and the terminal mix is
/// premultiplied exactly once for compositor storage.
nonisolated enum SceneGenericShaderSameAlphaReconstructedRGBFilterLowering {
    typealias Fact =
        SceneAuthoredShaderSameAlphaReconstructedRGBFilterFact
    private typealias Projection =
        SceneAuthoredShaderSameAlphaReconstructedRGBSampleProjection

    private struct SampleCall {
        let range: NSRange
        let slot: Int
        let projection: Projection
    }

    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    static func lower(_ source: String, fact: Fact) -> String? {
        guard (0 ..< 8).contains(fact.sourceSlot),
              !fact.auxiliarySlots.isEmpty,
              fact.auxiliarySlots.allSatisfy({ (0 ..< 8).contains($0) }),
              !fact.auxiliarySlots.contains(fact.sourceSlot),
              fact.totalSampleCallCount <= 32,
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              matches(#"\b"# + unpremultiply + #"\b"#, in: source).isEmpty,
              matches(#"\b"# + premultiply + #"\b"#, in: source).isEmpty,
              matches(
                  #"(?s)\b(?:mix|lerp)\s*\([^;{}]*\)\s*\{"#,
                  in: source
              ).isEmpty,
              let calls = sampleCalls(in: source),
              matches(#"\.\s*sample\s*\("#, in: source).count == calls.count,
              calls.count == fact.totalSampleCallCount,
              observedCounts(calls, sourceSlot: fact.sourceSlot)
                == (fact.sourceSampleCallCounts, fact.dataSampleCallCounts)
        else { return nil }

        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*((?:mix|lerp)\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*,\s*(?:float4\([^;]+\)|[^;]+)\))\s*;[ \t]*$"#,
            in: source
        )
        guard outputs.count == 1,
              let output = outputs.first,
              let indent = capture(output, 1, in: source),
              let expression = capture(output, 2, in: source),
              let snapshot = capture(output, 3, in: source),
              let carrier = capture(output, 4, in: source),
              snapshot != carrier,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              let body = fragmentBodyRange(
                  containing: output.range.location,
                  in: source
              ),
              contains(body, output.range),
              calls.allSatisfy({
                  contains(body, $0.range)
                      && $0.range.location < output.range.location
              }),
              terminalOutputIsProven(output: output.range, body: body, source: source),
              bodyHasNoExtraAuthority(body, output: output.range, source: source),
              snapshotAndCarrierFlowIsProven(
                  snapshot: snapshot,
                  carrier: carrier,
                  sourceSlot: fact.sourceSlot,
                  sourceCalls: calls.filter({ $0.slot == fact.sourceSlot }),
                  output: output.range,
                  body: body,
                  source: source
              ),
              let outputRange = Range(output.range, in: source)
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(\(expression));"
        )
        for call in calls.filter({ $0.slot == fact.sourceSlot }).sorted(by: {
            $0.range.location > $1.range.location
        }) {
            guard let originalRange = Range(call.range, in: source),
                  let transformedRange = Range(call.range, in: transformed) else {
                return nil
            }
            transformed.replaceSubrange(
                transformedRange,
                with: "\(unpremultiply)(\(source[originalRange]))"
            )
        }
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private static func observedCounts(
        _ calls: [SampleCall],
        sourceSlot: Int
    ) -> (
        [Projection: Int],
        [Int: [Projection: Int]]
    ) {
        var sourceCounts: [Projection: Int] = [:]
        var dataCounts: [Int: [Projection: Int]] = [:]
        for call in calls {
            if call.slot == sourceSlot {
                sourceCounts[call.projection, default: 0] += 1
            } else {
                dataCounts[call.slot, default: [:]][call.projection, default: 0]
                    += 1
            }
        }
        return (sourceCounts, dataCounts)
    }

    private static func snapshotAndCarrierFlowIsProven(
        snapshot: String,
        carrier: String,
        sourceSlot: Int,
        sourceCalls: [SampleCall],
        output: NSRange,
        body: NSRange,
        source: String
    ) -> Bool {
        let escapedSnapshot = escaped(snapshot)
        let escapedCarrier = escaped(carrier)
        let snapshotDefinitions = matches(
            #"(?m)^[ \t]*(?:const[ \t]+)?float4[ \t]+"#
                + escapedSnapshot + #"\s*=\s*g_Texture"#
                + String(sourceSlot) + #"\.sample\([^;]+\)\s*;[ \t]*$"#,
            in: source
        )
        let carrierDeclarations = matches(
            #"(?m)^[ \t]*float4[ \t]+"# + escapedCarrier
                + #"\s*;[ \t]*$"#,
            in: source
        )
        guard snapshotDefinitions.count == 1,
              carrierDeclarations.count == 1,
              let snapshotDefinition = snapshotDefinitions.first,
              let carrierDeclaration = carrierDeclarations.first,
              contains(body, snapshotDefinition.range),
              contains(body, carrierDeclaration.range),
              snapshotDefinition.range.location < carrierDeclaration.range.location,
              carrierDeclaration.range.location < output.location else { return false }

        let fullSourceCalls = sourceCalls.filter({ $0.projection == .fullVector })
        guard fullSourceCalls.count == 1,
              contains(snapshotDefinition.range, fullSourceCalls[0].range)
        else { return false }

        let snapshotWrites = matches(
            #"\b"# + escapedSnapshot
                + #"\b(?:\s*\.\s*[A-Za-z_]\w*)?\s*(?:\+=|-=|\*=|/=|=(?!=)|\+\+|--)"#,
            in: source
        )
        let snapshotPrefixWrites = matches(
            #"(?:\+\+|--)\s*\b"# + escapedSnapshot + #"\b"#,
            in: source
        )
        guard snapshotWrites.count == 1,
              contains(snapshotDefinition.range, snapshotWrites[0].range),
              snapshotPrefixWrites.isEmpty else { return false }

        let wholeCarrierWrites = matches(
            #"(?m)^[ \t]*"# + escapedCarrier + #"\s*="#,
            in: source
        )
        let carrierPrefixWrites = matches(
            #"(?:\+\+|--)\s*\b"# + escapedCarrier
                + #"\b(?:\s*\.\s*[A-Za-z_]\w*)?"#,
            in: source
        )
        guard wholeCarrierWrites.isEmpty, carrierPrefixWrites.isEmpty else {
            return false
        }

        let alphaWrites = matches(
            #"(?m)^[ \t]*"# + escapedCarrier
                + #"\s*\.\s*(?:w|a)\s*=\s*([^;]+)\s*;[ \t]*$"#,
            in: source
        )
        guard alphaWrites.count == 1,
              let alphaExpression = capture(alphaWrites[0], 1, in: source),
              selectedLane(alphaExpression, from: snapshot) == "w",
              carrierDeclaration.range.location < alphaWrites[0].range.location,
              alphaWrites[0].range.location < output.location else { return false }

        var initializedColorLanes = Set<String>()
        for call in sourceCalls where call.projection != .fullVector {
            guard let callRange = Range(call.range, in: source) else { return false }
            let text = escaped(String(source[callRange]))
            let lane = compilerLane(call.projection)
            guard let lane else { return false }
            let assignments = matches(
                #"(?m)^[ \t]*"# + escapedCarrier + #"\s*\.\s*"#
                    + lane + #"\s*=\s*"# + text + #"\s*\.\s*"#
                    + lane + #"\s*;[ \t]*$"#,
                in: source
            )
            guard assignments.count == 1,
                  assignments[0].range.location < output.location else {
                return false
            }
            initializedColorLanes.insert(lane)
        }

        let snapshotColorWrites = matches(
            #"(?m)^[ \t]*"# + escapedCarrier
                + #"\s*\.\s*([xyzrgb])\s*=\s*"# + escapedSnapshot
                + #"\s*\.\s*([xyzwrgba]{1,4})(?:\s*\.\s*([xyzwrgba]))?\s*;[ \t]*$"#,
            in: source
        )
        for write in snapshotColorWrites {
            guard let target = capture(write, 1, in: source),
                  let base = capture(write, 2, in: source),
                  let nested = capture(write, 3, in: source),
                  selectedLane(base, nested: nested) == normalizedLane(target)
            else { return false }
            initializedColorLanes.insert(normalizedLane(target))
        }
        guard initializedColorLanes == Set(["x", "y", "z"]) else {
            return false
        }

        let alphaCompoundWrites = matches(
            #"\b"# + escapedCarrier
                + #"\b\s*\.\s*(?:w|a)\s*(?:\+=|-=|\*=|/=|\+\+|--)"#,
            in: source
        )
        let alphaPrefixWrites = matches(
            #"(?:\+\+|--)\s*\b"# + escapedCarrier
                + #"\b\s*\.\s*(?:w|a)"#,
            in: source
        )
        return alphaCompoundWrites.isEmpty && alphaPrefixWrites.isEmpty
    }

    private static func selectedLane(_ expression: String, from name: String) -> String? {
        let pattern = #"^\s*"# + escaped(name)
            + #"\s*\.\s*([xyzwrgba]{1,4})(?:\s*\.\s*([xyzwrgba]))?\s*$"#
        guard let match = matches(pattern, in: expression).first,
              let base = capture(match, 1, in: expression) else { return nil }
        return selectedLane(base, nested: capture(match, 2, in: expression))
    }

    private static func selectedLane(_ base: String, nested: String?) -> String? {
        let normalized = base.map(normalizedLane)
        if let nested {
            let lane = normalizedLane(nested)
            guard let index = ["x", "y", "z", "w"].firstIndex(of: lane),
                  normalized.indices.contains(index) else { return nil }
            return normalized[index]
        }
        return normalized.count == 1 ? normalized[0] : nil
    }

    private static func normalizedLane(_ raw: Character) -> String {
        normalizedLane(String(raw))
    }

    private static func normalizedLane(_ raw: String) -> String {
        switch raw {
        case "r": "x"
        case "g": "y"
        case "b": "z"
        case "a": "w"
        default: raw
        }
    }

    private static func compilerLane(_ projection: Projection) -> String? {
        switch projection {
        case .red: "x"
        case .green: "y"
        case .blue: "z"
        default: nil
        }
    }

    private static func terminalOutputIsProven(
        output: NSRange,
        body: NSRange,
        source: String
    ) -> Bool {
        let text = source as NSString
        let tail = text.substring(with: NSRange(
            location: NSMaxRange(output),
            length: NSMaxRange(body) - NSMaxRange(output)
        ))
        let clean = tail
            .replacingOccurrences(
                of: #"(?s)/\*.*?\*/"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?m)//.*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return matches(#"^return\s+out\s*;$"#, in: clean).count == 1
    }

    private static func bodyHasNoExtraAuthority(
        _ body: NSRange,
        output: NSRange,
        source: String
    ) -> Bool {
        let text = (source as NSString).substring(with: body)
        guard matches(
            #"\b(?:discard_fragment|threadgroup_barrier|simdgroup_barrier|atomic_[A-Za-z_]\w*)\b"#,
            in: text
        ).isEmpty,
        matches(#"\.\s*(?:read|write|gather)\s*\("#, in: text).isEmpty
        else { return false }

        let outputWrites = matches(
            #"\bout\s*\.\s*([A-Za-z_]\w*)\s*(?:\+=|-=|\*=|/=|=(?!=)|\+\+|--)"#,
            in: source
        )
        let prefixWrites = matches(
            #"(?:\+\+|--)\s*\bout\s*\.\s*([A-Za-z_]\w*)"#,
            in: source
        )
        return outputWrites.count == 1
            && prefixWrites.isEmpty
            && capture(outputWrites[0], 1, in: source) == "mwxFragColor"
            && contains(output, outputWrites[0].range)
    }

    private static func sampleCalls(in source: String) -> [SampleCall]? {
        let starts = matches(#"\bg_Texture([0-7])\s*\.\s*sample\s*\("#, in: source)
        var result: [SampleCall] = []
        for start in starts {
            guard let slotText = capture(start, 1, in: source),
                  let slot = Int(slotText),
                  let startRange = Range(start.range, in: source),
                  let open = source[..<startRange.upperBound].lastIndex(of: "(")
            else { return nil }
            var depth = 0
            var close: String.Index?
            var cursor = open
            while cursor < source.endIndex {
                switch source[cursor] {
                case "(": depth += 1
                case ")":
                    depth -= 1
                    if depth == 0 { close = cursor }
                default: break
                }
                guard depth >= 0 else { return nil }
                if close != nil { break }
                cursor = source.index(after: cursor)
            }
            guard let close else { return nil }
            let range = startRange.lowerBound..<source.index(after: close)
            let suffix = String(source[range.upperBound...])
            guard let projection = compilerProjection(suffix) else { return nil }
            result.append(.init(
                range: NSRange(range, in: source),
                slot: slot,
                projection: projection
            ))
        }
        return result
    }

    private static func compilerProjection(_ suffix: String) -> Projection? {
        guard let match = matches(
            #"^\s*\.\s*([xyzwrgba]{1,4})\b"#,
            in: suffix
        ).first else { return .fullVector }
        guard let raw = capture(match, 1, in: suffix) else { return nil }
        let normalized = raw.map(normalizedLane).joined()
        switch normalized {
        case "x": return .red
        case "y": return .green
        case "z": return .blue
        case "w": return .alpha
        case "xy": return .redGreen
        case let value where value.count == 3
            && Set(value).isSubset(of: Set("xyz")):
            return .rgbPermutation
        default: return nil
        }
    }

    private static func fragmentBodyRange(
        containing location: Int,
        in source: String
    ) -> NSRange? {
        let text = source as NSString
        let signatures = matches(#"\bfragment\b[^\{]*\{"#, in: source)
            .filter { $0.range.location < location }
            .reversed()
        for signature in signatures {
            let open = NSMaxRange(signature.range) - 1
            var depth = 0
            for cursor in open..<text.length {
                switch text.character(at: cursor) {
                case 123: depth += 1
                case 125:
                    depth -= 1
                    if depth == 0, open < location, location < cursor {
                        return NSRange(
                            location: open + 1,
                            length: cursor - open - 1
                        )
                    }
                default: break
                }
                if depth < 0 { break }
            }
        }
        return nil
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

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }
}

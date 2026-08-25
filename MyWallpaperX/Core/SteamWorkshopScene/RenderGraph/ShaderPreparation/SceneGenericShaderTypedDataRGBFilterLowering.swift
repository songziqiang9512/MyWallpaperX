import Foundation

/// Independently checks the external compiler's sampler projections before
/// applying the shared straight/premultiplied color boundary. Data samplers
/// stay byte-semantic and are never unpremultiplied.
nonisolated enum SceneGenericShaderTypedDataRGBFilterLowering {
    private enum Projection {
        case fullVector
        case red
        case redGreen
    }

    private struct SampleCall {
        let range: NSRange
        let slot: Int
        let projection: Projection
    }

    private struct TerminalOutput {
        let match: NSTextCheckingResult
        let indent: String
        let expression: String
        let carrier: String
    }

    static func lower(
        _ source: String,
        fact: SceneAuthoredShaderTypedDataRGBFilterFact
    ) -> String? {
        guard let calls = sampleCalls(in: source),
              calls.count == fact.totalSampleCallCount else { return nil }
        var sourceCount = 0
        var fullVector: [Int: Int] = [:]
        var red: [Int: Int] = [:]
        var redGreen: [Int: Int] = [:]
        for call in calls {
            if call.slot == fact.sourceSlot {
                guard call.projection == .fullVector else { return nil }
                sourceCount += 1
                continue
            }
            switch call.projection {
            case .fullVector: fullVector[call.slot, default: 0] += 1
            case .red: red[call.slot, default: 0] += 1
            case .redGreen: redGreen[call.slot, default: 0] += 1
            }
        }
        guard sourceCount == 1,
              fullVector == fact.fullVectorDataSampleCallCounts,
              red == fact.redDataSampleCallCounts,
              redGreen == fact.redGreenDataSampleCallCounts else { return nil }
        switch fact.terminalTransform {
        case .identity:
            return SceneGenericShaderStraightAlphaPreservingLowering
                .lowerPreserving(source, expectedSlot: fact.sourceSlot)
        case .saturateRGBA, .nonNegativeRGBPreservedAlpha:
            return lowerSnapshotCarrier(
                source,
                sourceSlot: fact.sourceSlot,
                calls: calls,
                terminalTransform: fact.terminalTransform
            )
        }
    }

    private static func lowerSnapshotCarrier(
        _ source: String,
        sourceSlot: Int,
        calls: [SampleCall],
        terminalTransform:
            SceneAuthoredShaderTypedDataRGBFilterTerminalTransform
    ) -> String? {
        guard matches(#"\bmwxGenericUnpremultiply\b"#, in: source).isEmpty,
              matches(#"\bmwxGenericPremultiply\b"#, in: source).isEmpty,
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1
        else { return nil }
        let sourceCalls = calls.filter { $0.slot == sourceSlot }
        guard sourceCalls.count == 1,
              sourceCalls[0].projection == .fullVector,
              let terminal = terminalOutput(
                  in: source,
                  transform: terminalTransform
              ),
              sourceCalls[0].range.location < terminal.match.range.location,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              matches(#"(?m)^[ \t]*return\s+out\s*;[ \t]*$"#, in: source).count == 1,
              let outputRange = Range(terminal.match.range, in: source),
              snapshotCarrierDataflowIsProven(
                  in: source,
                  sourceCall: sourceCalls[0],
                  carrier: terminal.carrier,
                  output: terminal.match
              ),
              let sourceRange = Range(sourceCalls[0].range, in: source)
        else { return nil }

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(terminal.indent)out.mwxFragColor = "
                + "mwxGenericPremultiply(\(terminal.expression));"
        )
        guard let adjustedSourceRange = Range(sourceCalls[0].range, in: transformed)
        else { return nil }
        transformed.replaceSubrange(
            adjustedSourceRange,
            with: "mwxGenericUnpremultiply(\(source[sourceRange]))"
        )
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private static func terminalOutput(
        in source: String,
        transform: SceneAuthoredShaderTypedDataRGBFilterTerminalTransform
    ) -> TerminalOutput? {
        let pattern: String
        switch transform {
        case .identity:
            return nil
        case .saturateRGBA:
            pattern = #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*((?:fast::)?clamp\(\s*([A-Za-z_]\w*)\s*,\s*float4\(\s*0(?:\.0+)?f?\s*\)\s*,\s*float4\(\s*1(?:\.0+)?f?\s*\)\s*\))\s*;[ \t]*$"#
        case .nonNegativeRGBPreservedAlpha:
            pattern = #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*((?:float4|half4)\(\s*(?:fast::)?max\(\s*(?:float3|half3)\(\s*0(?:\.0+)?f?\s*\)\s*,\s*([A-Za-z_]\w*)\s*\.\s*(?:xyz|rgb)\s*\)\s*,\s*([A-Za-z_]\w*)\s*\.\s*(?:w|a)\s*\))\s*;[ \t]*$"#
        }
        let outputs = matches(pattern, in: source)
        guard outputs.count == 1,
              let output = outputs.first,
              let indent = capture(output, 1, in: source),
              let expression = capture(output, 2, in: source),
              let carrier = capture(output, 3, in: source)
        else { return nil }
        if transform == .nonNegativeRGBPreservedAlpha {
            guard capture(output, 4, in: source) == carrier else { return nil }
        }
        return .init(
            match: output,
            indent: indent,
            expression: expression,
            carrier: carrier
        )
    }

    /// Re-proves the compiler artifact's snapshot -> carrier -> RGB write ->
    /// optional scalar mix -> exact terminal transform chain. Sampler census
    /// alone cannot establish that the output still owns the source alpha.
    private static func snapshotCarrierDataflowIsProven(
        in source: String,
        sourceCall: SampleCall,
        carrier: String,
        output: NSTextCheckingResult
    ) -> Bool {
        let escapedCarrier = NSRegularExpression.escapedPattern(for: carrier)
        guard let sourceRange = Range(sourceCall.range, in: source) else {
            return false
        }
        let sample = NSRegularExpression.escapedPattern(
            for: String(source[sourceRange])
        )
        let sourceDefinitions = matches(
            #"(?m)^[ \t]*(?:const[ \t]+)?float4[ \t]+([A-Za-z_]\w*)\s*=\s*"#
                + sample + #"\s*;[ \t]*$"#,
            in: source
        )
        guard sourceDefinitions.count == 1,
              let sourceDefinition = sourceDefinitions.first,
              let snapshot = capture(sourceDefinition, 1, in: source),
              snapshot != carrier
        else { return false }
        let escapedSnapshot = NSRegularExpression.escapedPattern(for: snapshot)
        let carrierDefinitions = matches(
            #"(?m)^[ \t]*(?:const[ \t]+)?float4[ \t]+"#
                + escapedCarrier + #"\s*=\s*"# + escapedSnapshot
                + #"\s*;[ \t]*$"#,
            in: source
        )
        let vectorRGBWrites = matches(
            #"(?m)^[ \t]*"# + escapedCarrier
                + #"\s*\.\s*(?:xyz|rgb)\s*="#,
            in: source
        )
        let componentRGBWrites = matches(
            #"(?m)^[ \t]*"# + escapedCarrier
                + #"\s*\.\s*([xyzrgb])\s*="#,
            in: source
        )
        let rgbWrites: [NSTextCheckingResult]
        if vectorRGBWrites.count == 1, componentRGBWrites.isEmpty {
            rgbWrites = vectorRGBWrites
        } else {
            let lanes = componentRGBWrites.compactMap {
                capture($0, 1, in: source)
            }.map { lane in
                switch lane {
                case "r": "x"
                case "g": "y"
                case "b": "z"
                default: lane
                }
            }
            guard vectorRGBWrites.isEmpty,
                  lanes.count == 3,
                  Set(lanes) == Set(["x", "y", "z"])
            else { return false }
            rgbWrites = componentRGBWrites
        }
        let rgbStatements = rgbWrites.compactMap {
            statementRange(startingAt: $0.range.location, in: source)
        }
        guard carrierDefinitions.count == 1,
              let carrierDefinition = carrierDefinitions.first,
              rgbStatements.count == rgbWrites.count,
              let body = fragmentBodyRange(
                  containing: output.range.location,
                  in: source
              ),
              contains(body, sourceDefinition.range),
              contains(body, carrierDefinition.range),
              rgbStatements.allSatisfy({ contains(body, $0) }),
              contains(body, output.range),
              sourceDefinition.range.location < carrierDefinition.range.location,
              rgbStatements.allSatisfy({
                  carrierDefinition.range.location < $0.location
                      && NSMaxRange($0) < output.range.location
              }),
              ([sourceDefinition.range, carrierDefinition.range, output.range]
               + rgbStatements).allSatisfy({
                  topLevel($0.location, in: body, source: source)
              })
        else { return false }

        let wholeAssignments = matches(
            #"(?m)^[ \t]*"# + escapedCarrier + #"\s*="#,
            in: source
        )
        guard wholeAssignments.count <= 1 else { return false }
        var mixRange: NSRange?
        if let assignment = wholeAssignments.first {
            guard let statement = statementRange(
                      startingAt: assignment.range.location,
                      in: source
                  ),
                  carrierDefinition.range.location < statement.location,
                  rgbStatements.allSatisfy({
                      NSMaxRange($0) <= statement.location
                  }),
                  NSMaxRange(statement) < output.range.location,
                  topLevel(statement.location, in: body, source: source)
            else { return false }
            let statementText = (source as NSString).substring(with: statement)
            let arguments = matches(
                #"^\s*"# + escapedCarrier
                    + #"\s*=\s*(?:fast::)?(?:mix|lerp)\(\s*([A-Za-z_]\w*)\s*,\s*([A-Za-z_]\w*)\s*,\s*(?:(?:float4|half4)\(\s*([A-Za-z_]\w*|[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?f?)\s*\)|([A-Za-z_]\w*|[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?f?))\s*\)\s*;$"#,
                in: statementText
            )
            guard arguments.count == 1,
                  let call = arguments.first,
                  let first = capture(call, 1, in: statementText),
                  let second = capture(call, 2, in: statementText),
                  Set([first, second]) == Set([snapshot, carrier]),
                  let weight = capture(call, 3, in: statementText)
                      ?? capture(call, 4, in: statementText),
                  scalarWeightIsProven(
                      weight,
                      before: statement.location,
                      body: body,
                      source: source
                  )
            else { return false }
            mixRange = statement
        }

        let allowedSnapshotRanges: [NSRange] = [
            sourceDefinition.range(at: 0), carrierDefinition.range(at: 0),
        ] + [mixRange].compactMap { $0 }
        guard wordMatches(snapshot, in: source).allSatisfy({ use in
            allowedSnapshotRanges.contains(where: { contains($0, use.range) })
        }) else { return false }
        let wholeCarrierRanges: [NSRange] = [
            carrierDefinition.range(at: 0), output.range(at: 0),
        ] + [mixRange].compactMap { $0 }
        guard wordMatches(carrier, in: source).allSatisfy({ use in
            if wholeCarrierRanges.contains(where: {
                contains($0, use.range)
            }) { return true }
            guard carrierDefinition.range.location < use.range.location,
                  use.range.location < output.range.location,
                  contains(body, use.range)
            else { return false }
            let suffix = (source as NSString).substring(
                from: NSMaxRange(use.range)
            )
            return matches(
                #"^\s*\.\s*(?:xyz|rgb|[xyzrgb])\b"#,
                in: suffix
            ).count == 1
        }) else { return false }

        let bodyText = (source as NSString).substring(with: body)
        return matches(#"\breturn\b"#, in: bodyText).count == 1
            && matches(#"(?m)^[ \t]*return\s+out\s*;[ \t]*$"#, in: bodyText).count == 1
            && matches(#"\b(?:discard|gl_FragDepth)\b"#, in: bodyText).isEmpty
    }

    private static func scalarWeightIsProven(
        _ value: String,
        before location: Int,
        body: NSRange,
        source: String
    ) -> Bool {
        if matches(
            #"^[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?f?$"#,
            in: value
        ).count == 1 { return true }
        let escaped = NSRegularExpression.escapedPattern(for: value)
        let declarations = matches(
            #"(?m)^[ \t]*(?:const[ \t]+)?(?:float|half)[ \t]+"#
                + escaped + #"\s*=.*;[ \t]*$"#,
            in: source
        )
        return declarations.count == 1
            && declarations[0].range.location < location
            && contains(body, declarations[0].range)
            && topLevel(declarations[0].range.location, in: body, source: source)
    }

    private static func wordMatches(
        _ value: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        matches(
            #"\b"# + NSRegularExpression.escapedPattern(for: value) + #"\b"#,
            in: source
        )
    }

    private static func statementRange(
        startingAt location: Int,
        in source: String
    ) -> NSRange? {
        let text = source as NSString
        guard location < text.length else { return nil }
        let tail = NSRange(location: location, length: text.length - location)
        let terminator = text.range(of: ";", range: tail)
        guard terminator.location != NSNotFound else { return nil }
        return NSRange(
            location: location,
            length: NSMaxRange(terminator) - location
        )
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
            for cursor in open ..< text.length {
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

    private static func topLevel(
        _ location: Int,
        in body: NSRange,
        source: String
    ) -> Bool {
        guard body.location <= location, location <= NSMaxRange(body) else {
            return false
        }
        let text = source as NSString
        var depth = 0
        for cursor in body.location ..< location {
            switch text.character(at: cursor) {
            case 123: depth += 1
            case 125: depth -= 1
            default: break
            }
            guard depth >= 0 else { return false }
        }
        return depth == 0
    }

    private static func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    private static func sampleCalls(in source: String) -> [SampleCall]? {
        let starts = matches(#"\bg_Texture([0-7])\.sample\("#, in: source)
        var result: [SampleCall] = []
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
            let projection: Projection
            if matches(#"^\s*\.(?:x|r)\b"#, in: suffix).count == 1 {
                projection = .red
            } else if matches(#"^\s*\.(?:xy|rg)\b"#, in: suffix).count == 1 {
                projection = .redGreen
            } else if matches(#"^\s*\."#, in: suffix).isEmpty {
                projection = .fullVector
            } else {
                return nil
            }
            result.append(.init(
                range: NSRange(range, in: source),
                slot: slot,
                projection: projection
            ))
        }
        return result
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
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else {
            return nil
        }
        return String(source[range])
    }
}

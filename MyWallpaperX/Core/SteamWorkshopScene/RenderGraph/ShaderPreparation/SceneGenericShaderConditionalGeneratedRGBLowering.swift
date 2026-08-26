import Foundation

/// Verifies the compiler shape corresponding to the source-proven
/// conditional generated-RGB flow, then inserts exactly one straight-color
/// boundary around its sampled alpha carrier.
nonisolated enum SceneGenericShaderConditionalGeneratedRGBLowering {
    private enum Projection: Equatable {
        case fullVector
        case rgb
        case red
        case green
        case blue
        case alpha
    }

    private struct SampleCall {
        let range: NSRange
        let slot: Int
        let projection: Projection
    }

    private static let unpremultiply = "mwxGenericUnpremultiply"
    private static let premultiply = "mwxGenericPremultiply"

    static func lower(
        _ source: String,
        fact: SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact
    ) -> String? {
        guard (0 ..< 8).contains(fact.alphaCarrierSlot),
              !fact.generatedOpaqueColorSlots.isEmpty,
              fact.generatedOpaqueColorSlots.allSatisfy({ (0 ..< 8).contains($0) }),
              fact.sampleCallCounts.values.allSatisfy({ (1 ... 16).contains($0) }),
              fact.sampleCallCounts.values.reduce(0, +) <= 32,
              matches(#"\busing\s+namespace\s+metal\s*;"#, in: source).count == 1,
              matches(#"\b"# + unpremultiply + #"\b"#, in: source).isEmpty,
              matches(#"\b"# + premultiply + #"\b"#, in: source).isEmpty,
              let calls = sampleCalls(in: source) else {
            return nil
        }

        let carrierDeclarations = matches(
            #"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)g_Texture"#
                + String(fact.alphaCarrierSlot)
                + #"\.sample\(([^;]+)\)(\s*;[ \t]*)$"#,
            in: source
        )
        guard carrierDeclarations.count == 1,
              let declaration = carrierDeclarations.first,
              let prefix = capture(declaration, 1, in: source),
              let carrier = capture(declaration, 2, in: source),
              let arguments = capture(declaration, 3, in: source),
              let suffix = capture(declaration, 4, in: source) else {
            return nil
        }
        let outputs = matches(
            #"(?m)^([ \t]*)out\.mwxFragColor\s*=\s*float4\(\s*([A-Za-z_]\w*)\s*,\s*"#
                + escaped(carrier)
                + #"\.w\s*\)\s*;[ \t]*$"#,
            in: source
        )
        guard outputs.count == 1,
              let output = outputs.first,
              let indent = capture(output, 1, in: source),
              let color = capture(output, 2, in: source),
              color != carrier,
              declaration.range.location < output.range.location,
              matches(#"\bout\.mwxFragColor\b"#, in: source).count == 1,
              let body = fragmentBodyRange(
                  containing: output.range.location,
                  in: source
              ),
              contains(body, declaration.range),
              calls.allSatisfy({ contains(body, $0.range) }),
              compilerRolesAreProven(
                  calls,
                  fact: fact,
                  declaration: declaration.range,
                  color: color,
                  carrier: carrier,
                  output: output.range,
                  source: source
              ),
              terminalOutputIsProven(
                  output: output.range,
                  body: body,
                  source: source
              ),
              compilerBodyHasNoExtraAuthority(
                  body,
                  output: output.range,
                  source: source
              ),
              let outputText = substring(output.range, in: source),
              let assignment = outputText.range(of: "out.mwxFragColor = "),
              let outputRange = Range(output.range, in: source) else {
            return nil
        }
        let valueStart = assignment.upperBound
        guard let valueEnd = outputText[valueStart...].lastIndex(of: ";") else {
            return nil
        }
        let value = outputText[valueStart..<valueEnd]

        var transformed = source
        transformed.replaceSubrange(
            outputRange,
            with: "\(indent)out.mwxFragColor = \(premultiply)(\(value));"
        )
        guard let declarationRange = Range(declaration.range, in: transformed) else {
            return nil
        }
        transformed.replaceSubrange(
            declarationRange,
            with: "\(prefix)\(unpremultiply)(g_Texture\(fact.alphaCarrierSlot).sample(\(arguments)))\(suffix)"
        )
        return SceneGenericShaderStraightAlphaPreservingLowering
            .insertingBoundaryHelpers(into: transformed)
    }

    private static func compilerRolesAreProven(
        _ calls: [SampleCall],
        fact: SceneAuthoredShaderConditionalGeneratedRGBAnalyzer.Fact,
        declaration: NSRange,
        color: String,
        carrier: String,
        output: NSRange,
        source: String
    ) -> Bool {
        var observedCounts: [Int: Int] = [:]
        var generated: [Int: Int] = [:]
        var red: [Int: Int] = [:]
        var green: [Int: Int] = [:]
        var blue: [Int: Int] = [:]
        var alpha: [Int: Int] = [:]
        var carrierCalls = 0
        for call in calls {
            observedCounts[call.slot, default: 0] += 1
            if contains(declaration, call.range) {
                guard call.slot == fact.alphaCarrierSlot,
                      call.projection == .fullVector else { return false }
                carrierCalls += 1
                continue
            }
            guard call.range.location < output.location,
                  compilerRolePlacementIsProven(
                      call,
                      color: color,
                      carrier: carrier,
                      source: source
                  ) else { return false }
            switch call.projection {
            case .rgb: generated[call.slot, default: 0] += 1
            case .red: red[call.slot, default: 0] += 1
            case .green: green[call.slot, default: 0] += 1
            case .blue: blue[call.slot, default: 0] += 1
            case .alpha: alpha[call.slot, default: 0] += 1
            case .fullVector: return false
            }
        }
        guard carrierCalls == 1,
              observedCounts == fact.sampleCallCounts,
              generated == fact.generatedSampleCallCounts,
              red == fact.scalarRedSampleCallCounts,
              green == fact.scalarGreenSampleCallCounts,
              blue == fact.scalarBlueSampleCallCounts,
              alpha == fact.scalarAlphaSampleCallCounts else { return false }

        let carrierWrites = matches(
            #"\b"# + escaped(carrier)
                + #"\b(?:\s*\.\s*[A-Za-z_]\w*)?\s*"#
                + assignmentOperatorPattern,
            in: source
        )
        let carrierPrefixWrites = matches(
            #"(?:\+\+|--)\s*\b"# + escaped(carrier)
                + #"\b(?:\s*\.\s*[A-Za-z_]\w*)?"#,
            in: source
        )
        return carrierWrites.count == 1
            && carrierWrites.allSatisfy({ contains(declaration, $0.range) })
            && carrierPrefixWrites.isEmpty
    }

    private static func compilerRolePlacementIsProven(
        _ call: SampleCall,
        color: String,
        carrier: String,
        source: String
    ) -> Bool {
        guard let line = sourceLine(containing: call.range, in: source),
              sampleCalls(in: line)?.count == 1 else { return false }
        switch call.projection {
        case .rgb:
            return matches(
                #"^\s*(?:(?:const\s+)?float3\s+)?"# + escaped(color)
                    + #"\s*(?:=|\+=)\s*.+\.(?:xyz|rgb)\s*;\s*$"#,
                in: line
            ).count == 1
        case .red, .green, .blue, .alpha:
            let lane: String
            switch call.projection {
            case .red: lane = "(?:x|r)"
            case .green: lane = "(?:y|g)"
            case .blue: lane = "(?:z|b)"
            case .alpha: lane = "(?:w|a)"
            default: return false
            }
            let assignments = matches(
                #"^\s*(?:(?:const\s+)?(?:float|half)\s+)?([A-Za-z_]\w*)"#
                    + #"\s*=\s*.+\."# + lane + #"\s*;\s*$"#,
                in: line
            )
            guard assignments.count == 1,
                  let assignment = assignments.first,
                  let target = capture(assignment, 1, in: line) else {
                return false
            }
            return target != color && target != carrier
        case .fullVector:
            return false
        }
    }

    private static func terminalOutputIsProven(
        output: NSRange,
        body: NSRange,
        source: String
    ) -> Bool {
        guard contains(body, output),
              topLevel(output.location, in: body, source: source),
              NSMaxRange(output) <= NSMaxRange(body) else { return false }
        let text = source as NSString
        let tail = text.substring(with: NSRange(
            location: NSMaxRange(output),
            length: NSMaxRange(body) - NSMaxRange(output)
        ))
        let withoutComments = tail
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
        return matches(#"^return\s+out\s*;$"#, in: withoutComments).count == 1
    }

    private static func compilerBodyHasNoExtraAuthority(
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

        let memberCalls = matches(
            #"\b([A-Za-z_]\w*)\s*\.\s*([A-Za-z_]\w*)\s*\("#,
            in: text
        )
        guard memberCalls.allSatisfy({ call in
            guard let root = capture(call, 1, in: text),
                  let method = capture(call, 2, in: text) else { return false }
            return root.range(
                of: #"^g_Texture[0-7]$"#,
                options: .regularExpression
            ) != nil && method == "sample"
        }) else { return false }

        let outputWrites = matches(
            #"\bout\s*\.\s*([A-Za-z_]\w*)\s*"#
                + assignmentOperatorPattern,
            in: source
        )
        let outputPrefixWrites = matches(
            #"(?:\+\+|--)\s*\bout\s*\.\s*([A-Za-z_]\w*)"#,
            in: source
        )
        guard outputWrites.count == 1,
              outputPrefixWrites.isEmpty,
              let onlyOutput = outputWrites.first,
              capture(onlyOutput, 1, in: source) == "mwxFragColor",
              contains(output, onlyOutput.range) else { return false }

        var locals: Set<String> = ["out"]
        for declaration in matches(
            #"\b(?:bool|int|uint|float|half|double)(?:[234](?:x[234])?)?\s+([A-Za-z_]\w*)\b"#,
            in: text
        ) {
            guard let name = capture(declaration, 1, in: text) else {
                return false
            }
            locals.insert(name)
        }
        let suffixWritesAreLocal = matches(
            #"\b([A-Za-z_]\w*)\b(?:\s*(?:\.\s*[A-Za-z_]\w*|\[[^\]]+\]))*\s*"#
                + assignmentOperatorPattern,
            in: text
        ).allSatisfy({ write in
            capture(write, 1, in: text).map(locals.contains) == true
        })
        let prefixWritesAreLocal = matches(
            #"(?:\+\+|--)\s*\b([A-Za-z_]\w*)\b"#
                + #"(?:\s*(?:\.\s*[A-Za-z_]\w*|\[[^\]]+\]))*"#,
            in: text
        ).allSatisfy({ write in
            capture(write, 1, in: text).map(locals.contains) == true
        })
        return suffixWritesAreLocal && prefixWritesAreLocal
    }

    private static let assignmentOperatorPattern =
        #"(?:<<=|>>=|\+=|-=|\*=|/=|%=|&=|\|=|\^=|=(?!=)|\+\+|--)"#

    private static func sampleCalls(in source: String) -> [SampleCall]? {
        let starts = matches(
            #"\bg_Texture([0-7])\s*\.\s*sample\s*\("#,
            in: source
        )
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
            if matches(#"^\s*\.(?:xyz|rgb)\b"#, in: suffix).count == 1 {
                projection = .rgb
            } else if matches(#"^\s*\.(?:x|r)\b"#, in: suffix).count == 1 {
                projection = .red
            } else if matches(#"^\s*\.(?:y|g)\b"#, in: suffix).count == 1 {
                projection = .green
            } else if matches(#"^\s*\.(?:z|b)\b"#, in: suffix).count == 1 {
                projection = .blue
            } else if matches(#"^\s*\.(?:w|a)\b"#, in: suffix).count == 1 {
                projection = .alpha
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

    private static func sourceLine(
        containing range: NSRange,
        in source: String
    ) -> String? {
        let text = source as NSString
        guard range.location != NSNotFound,
              NSMaxRange(range) <= text.length else { return nil }
        return text.substring(with: text.lineRange(for: range))
    }

    private static func fragmentBodyRange(
        containing location: Int,
        in source: String
    ) -> NSRange? {
        let text = source as NSString
        let signatures = matches(#"\bfragment\b[^\{]*\{"#, in: source)
            .filter { $0.range.location < location }
            .sorted(by: { $0.range.location > $1.range.location })
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

    private static func substring(
        _ range: NSRange,
        in source: String
    ) -> String? {
        Range(range, in: source).map { String(source[$0]) }
    }

    private static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }
}

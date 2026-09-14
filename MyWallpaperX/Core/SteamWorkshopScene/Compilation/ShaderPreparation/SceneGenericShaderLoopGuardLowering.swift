import Foundation

/// Product loop policy for authored loops that `SceneGenericShaderBoundedLoopWork`
/// cannot prove. The official runtime executes authored loops as written, so
/// the generic route runs them as written too and only guards one shader
/// invocation against a runaway iteration count: every supported `for` and
/// `while` condition passes through one shared guard, so nested and helper
/// loops share the same cap. `do ... while` remains unlowered until its
/// post-test condition can be delimited safely. Statically proven loops never take this
/// path and their artifacts stay byte-identical.
nonisolated enum SceneGenericShaderLoopGuardLowering {
    static let iterationCap = 4096
    static let guardFunctionName = "mwxGuardLoop"
    static let guardCounterName = "mwxLoopGuardCount"
    static let vertexGuardFunctionName = "mwxVertexGuardLoop"
    static let vertexGuardCounterName = "mwxVertexLoopGuardCount"
    static let fragmentGuardFunctionName = "mwxFragmentGuardLoop"
    static let fragmentGuardCounterName = "mwxFragmentLoopGuardCount"

    struct Lowered: Equatable {
        let source: String
        /// Loop conditions routed through the guard; zero when the stage has
        /// no loop and the source is returned unchanged.
        let guardedLoopCount: Int
    }

    struct LoweredPair: Equatable {
        let vertex: String
        let fragment: String
        let guardedLoopCount: Int
    }

    /// Guards both normalized glslang stage sources. Returns nil unless at
    /// least one loop was guarded and every loop header could be delimited.
    static func lowerPair(vertex: String, fragment: String) -> LoweredPair? {
        guard let loweredVertex = lower(
                  vertex,
                  functionName: vertexGuardFunctionName,
                  counterName: vertexGuardCounterName
              ), let loweredFragment = lower(
                  fragment,
                  functionName: fragmentGuardFunctionName,
                  counterName: fragmentGuardCounterName
              ),
              loweredVertex.guardedLoopCount + loweredFragment.guardedLoopCount > 0
        else { return nil }
        return LoweredPair(
            vertex: loweredVertex.source,
            fragment: loweredFragment.source,
            guardedLoopCount: loweredVertex.guardedLoopCount
                + loweredFragment.guardedLoopCount
        )
    }

    /// Rewrites every loop condition of one normalized stage source into
    /// `mwxGuardLoop(condition)` and declares the shared counter and guard
    /// right after the `#version` line. Comments never count as loops.
    static func lower(_ source: String) -> Lowered? {
        lower(
            source,
            functionName: guardFunctionName,
            counterName: guardCounterName
        )
    }

    static func containsGuardFunction(in source: String) -> Bool {
        [
            guardFunctionName,
            vertexGuardFunctionName,
            fragmentGuardFunctionName,
        ].contains(where: source.contains)
    }

    private static func lower(
        _ source: String,
        functionName: String,
        counterName: String
    ) -> Lowered? {
        guard !source.contains(functionName),
              !source.contains(counterName),
              matches(#"\bdo\b"#, in: commentMaskedString(source)).isEmpty
        else { return nil }
        let units = Array(source.utf16)
        let masked = commentMasked(units)
        let maskedString = String(utf16CodeUnits: masked, count: masked.count)
        let headers = matches(#"\b(for|while)\b\s*\("#, in: maskedString)
        guard !headers.isEmpty else {
            return Lowered(source: source, guardedLoopCount: 0)
        }
        guard let versionLineEnd = units.firstIndex(of: 10),
              String(utf16CodeUnits: Array(units[..<versionLineEnd]), count: versionLineEnd)
              .trimmingCharacters(in: .whitespaces).hasPrefix("#version ")
        else { return nil }

        var edits: [(range: NSRange, replacement: String)] = []
        for header in headers {
            let keyword = String(
                utf16CodeUnits: Array(units[header.range(at: 1).lowerBound
                        ..< header.range(at: 1).upperBound]),
                count: header.range(at: 1).length
            )
            let open = NSMaxRange(header.range) - 1
            guard let close = closingParenthesis(in: masked, after: open) else {
                return nil
            }
            let conditionRange: NSRange
            if keyword == "for" {
                var separators: [Int] = []
                var depth = 0
                for index in (open + 1) ..< close {
                    switch masked[index] {
                    case 40: depth += 1
                    case 41: depth -= 1
                    case 59 where depth == 0: separators.append(index)
                    default: break
                    }
                }
                guard separators.count == 2 else { return nil }
                conditionRange = NSRange(
                    location: separators[0] + 1,
                    length: separators[1] - separators[0] - 1
                )
            } else {
                conditionRange = NSRange(location: open + 1, length: close - open - 1)
            }
            let condition = String(
                utf16CodeUnits: Array(units[conditionRange.lowerBound ..< conditionRange.upperBound]),
                count: conditionRange.length
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard keyword == "for" || !condition.isEmpty else { return nil }
            let guarded = "\(functionName)(\(condition.isEmpty ? "true" : condition))"
            edits.append((conditionRange, keyword == "for" ? " \(guarded)" : guarded))
        }

        let result = NSMutableString(string: source)
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            result.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        result.insert(
            preamble(functionName: functionName, counterName: counterName),
            at: versionLineEnd + 1
        )
        return Lowered(source: result as String, guardedLoopCount: headers.count)
    }

    private static func commentMaskedString(_ source: String) -> String {
        let units = commentMasked(Array(source.utf16))
        return String(decoding: units, as: UTF16.self)
    }

    private static func preamble(
        functionName: String,
        counterName: String
    ) -> String {
        """
        int \(counterName) = 0;
        bool \(functionName)(bool keepGoing) {
            \(counterName) += 1;
            return keepGoing && \(counterName) <= \(iterationCap);
        }

        """
    }

    /// Replaces `//` and `/* */` comment characters with spaces so structural
    /// scans keep every offset of the original source.
    private static func commentMasked(_ units: [UInt16]) -> [UInt16] {
        var masked = units
        var index = 0
        while index + 1 < units.count {
            if units[index] == 47, units[index + 1] == 47 {
                while index < units.count, units[index] != 10 {
                    masked[index] = 32
                    index += 1
                }
            } else if units[index] == 47, units[index + 1] == 42 {
                masked[index] = 32
                masked[index + 1] = 32
                index += 2
                while index < units.count {
                    if units[index] == 42, index + 1 < units.count, units[index + 1] == 47 {
                        masked[index] = 32
                        masked[index + 1] = 32
                        index += 2
                        break
                    }
                    masked[index] = 32
                    index += 1
                }
            } else {
                index += 1
            }
        }
        return masked
    }

    private static func closingParenthesis(in units: [UInt16], after open: Int) -> Int? {
        var depth = 0
        var index = open
        while index < units.count {
            switch units[index] {
            case 40: depth += 1
            case 41:
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
            index += 1
        }
        return nil
    }

    private static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        try! NSRegularExpression(pattern: pattern).matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )
    }
}

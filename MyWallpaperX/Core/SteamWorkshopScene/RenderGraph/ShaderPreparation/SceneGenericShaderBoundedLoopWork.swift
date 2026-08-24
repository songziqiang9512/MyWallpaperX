import Foundation

nonisolated enum SceneGenericShaderBoundedLoopWork {
    enum Failure: Error {
        case unbounded
        case budget
    }

    struct Consumption {
        let found: Bool
        let work: Int?
    }

    private struct FunctionBody {
        let name: String
        let range: NSRange
    }

    static func evaluate(sources: [String]) -> Result<Int, Failure> {
        let floatLiteral = #"(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?[fF]?"#
        let zeroBasedPattern = #"\bfor\s*\(\s*int\s+([A-Za-z_]\w*)\s*=\s*0\s*;\s*([A-Za-z_]\w*)\s*<\s*(\d+)\s*;\s*(?:(?:\+\+\s*([A-Za-z_]\w*))|(?:([A-Za-z_]\w*)\s*\+\+))\s*\)"#
        let signedInclusivePattern = #"\bfor\s*\(\s*int\s+([A-Za-z_]\w*)\s*=\s*(-?(?:\d+|[A-Za-z_]\w*))\s*;\s*([A-Za-z_]\w*)\s*<=\s*(-?(?:\d+|[A-Za-z_]\w*))\s*;\s*(?:(?:\+\+\s*([A-Za-z_]\w*))|(?:([A-Za-z_]\w*)\s*\+\+))\s*\)"#
        var total = 0
        for source in sources {
            var body = source.replacingOccurrences(
                of: #"(?s)/\*.*?\*/|//[^\n]*"#,
                with: " ",
                options: .regularExpression
            )
            guard !containsNestedLoop(in: body) else {
                return .failure(.unbounded)
            }
            guard loopCallGraphIsSingleShot(in: body) else {
                return .failure(.unbounded)
            }
            guard let defines = numericDefines(in: body) else {
                return .failure(.unbounded)
            }
            let floatEarlyExitLoops = consumeStaticFloatEarlyExitLoops(
                in: &body,
                floatLiteral: floatLiteral
            )
            if floatEarlyExitLoops.found {
                guard let work = floatEarlyExitLoops.work else {
                    return .failure(.unbounded)
                }
                total += work
            }
            for match in matches(zeroBasedPattern, in: body).reversed() {
                guard let declared = capture(match, 1, in: body),
                      let compared = capture(match, 2, in: body),
                      let limitText = capture(match, 3, in: body),
                      let limit = Int(limitText), (1 ... 64).contains(limit),
                      [capture(match, 4, in: body), capture(match, 5, in: body)]
                        .compactMap({ $0 }).contains(declared),
                      declared == compared,
                      let range = Range(match.range, in: body) else {
                    return .failure(.unbounded)
                }
                total += limit
                body.removeSubrange(range)
            }
            for match in matches(signedInclusivePattern, in: body).reversed() {
                guard let declared = capture(match, 1, in: body),
                      let startText = capture(match, 2, in: body),
                      let compared = capture(match, 3, in: body),
                      let endText = capture(match, 4, in: body),
                      let start = signedBound(startText, defines: defines),
                      let end = signedBound(endText, defines: defines),
                      declared == compared,
                      [capture(match, 5, in: body), capture(match, 6, in: body)]
                        .compactMap({ $0 }).contains(declared),
                      (-64 ... 64).contains(start),
                      (-64 ... 64).contains(end),
                      (1 ... 64).contains(end - start + 1),
                      let range = Range(match.range, in: body) else {
                    return .failure(.unbounded)
                }
                total += end - start + 1
                body.removeSubrange(range)
            }
            let audioLoops = consumeAudioLoops(in: &body)
            if audioLoops.found {
                guard let work = audioLoops.work else {
                    return .failure(.unbounded)
                }
                total += work
            }
            if regexMatches(#"\b(for|while|do)\b"#, body) {
                return .failure(.unbounded)
            }
        }
        return total <= 256 ? .success(total) : .failure(.budget)
    }

    /// A dynamic conjunct may only shorten a loop whose float induction
    /// variable has an immutable, finite local upper bound.
    private static func consumeStaticFloatEarlyExitLoops(
        in source: inout String,
        floatLiteral: String
    ) -> Consumption {
        let pattern = #"\bfor\s*\(\s*float\s+([A-Za-z_]\w*)\s*=\s*("#
            + floatLiteral
            + #")\s*;\s*([^;]+)\s*;\s*(?:(?:\+\+\s*([A-Za-z_]\w*))|(?:([A-Za-z_]\w*)\s*\+\+))\s*\)"#
        let loops = matches(pattern, in: source)
        guard !loops.isEmpty else { return .init(found: false, work: 0) }
        var work = 0
        for loop in loops.reversed() {
            guard let index = capture(loop, 1, in: source),
                  let initial = capture(loop, 2, in: source),
                  finiteIntegral(initial) == 0,
                  let condition = capture(loop, 3, in: source),
                  [capture(loop, 4, in: source), capture(loop, 5, in: source)]
                    .compactMap({ $0 }).contains(index),
                  let limit = staticEarlyExitBound(
                      condition: condition,
                      index: index,
                      source: source,
                      before: loop.range.location,
                      floatLiteral: floatLiteral
                  ),
                  (1 ... 64).contains(limit),
                  let bodyRange = loopBodyRange(
                      in: source,
                      after: NSMaxRange(loop.range)
                  ),
                  !isWritten(index, in: bodyRange, source: source),
                  !isPassedToAuthoredFunction(
                      index,
                      in: bodyRange,
                      source: source
                  ),
                  let headerRange = Range(loop.range, in: source) else {
                return .init(found: true, work: nil)
            }
            work += limit
            source.removeSubrange(headerRange)
        }
        return .init(found: true, work: work)
    }

    private static func staticEarlyExitBound(
        condition: String,
        index: String,
        source: String,
        before loopLocation: Int,
        floatLiteral: String
    ) -> Int? {
        let conjuncts = condition.components(separatedBy: "&&")
        guard conjuncts.count >= 2 else { return nil }
        let escapedIndex = NSRegularExpression.escapedPattern(for: index)
        let boundPattern = #"^\s*"# + escapedIndex
            + #"\s*<\s*([A-Za-z_]\w*|"# + floatLiteral + #")\s*$"#
        var bound: Int?
        for conjunct in conjuncts {
            let found = matches(boundPattern, in: conjunct)
            if let match = found.first,
               let raw = capture(match, 1, in: conjunct) {
                guard found.count == 1, bound == nil,
                      let value = finiteIntegral(raw)
                        ?? rootInvariantFloat(
                            named: raw,
                            source: source,
                            before: loopLocation,
                            floatLiteral: floatLiteral
                        ) else { return nil }
                bound = value
            } else if regexMatches(#"\b"# + escapedIndex + #"\b"#, conjunct) {
                return nil
            }
        }
        return bound
    }

    private static func rootInvariantFloat(
        named name: String,
        source: String,
        before loopLocation: Int,
        floatLiteral: String
    ) -> Int? {
        guard let functionRange = enclosingFunctionBodyRange(
            in: source,
            containing: loopLocation
        ) else { return nil }
        let functionSource = (source as NSString).substring(with: functionRange)
        let localLoopLocation = loopLocation - functionRange.location
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let declarations = matches(
            #"\b(?:const\s+)?float\s+"# + escaped
                + #"\s*=\s*("# + floatLiteral + #")\s*;"#,
            in: functionSource
        )
        guard declarations.count == 1,
              let declaration = declarations.first,
              declaration.range.location < localLoopLocation,
              braceDepth(
                  in: functionSource,
                  before: declaration.range.location
              ) == 0,
              let raw = capture(declaration, 1, in: functionSource),
              let value = finiteIntegral(raw) else { return nil }
        let suffix = NSRange(
            location: functionRange.location + NSMaxRange(declaration.range),
            length: (functionSource as NSString).length - NSMaxRange(declaration.range)
        )
        return isWritten(name, in: suffix, source: source)
            || isPassedToAuthoredFunction(name, in: suffix, source: source)
            ? nil : value
    }

    private static func enclosingFunctionBodyRange(
        in source: String,
        containing location: Int
    ) -> NSRange? {
        let signature = #"\b(?:void|bool|int|uint|float|half|double|[biu]?vec[234]|mat[234](?:x[234])?)\s+[A-Za-z_]\w*\s*\([^;{}]*\)\s*\{"#
        let value = source as NSString
        return matches(signature, in: source).compactMap { match in
            let opening = NSMaxRange(match.range) - 1
            guard opening < location,
                  let closing = closingBrace(
                      in: value,
                      after: opening
                  ),
                  location < closing else { return nil }
            return NSRange(location: opening + 1, length: closing - opening - 1)
        }.min { lhs, rhs in lhs.length < rhs.length }
    }

    private static func closingBrace(
        in source: NSString,
        after opening: Int
    ) -> Int? {
        var depth = 1
        var cursor = opening + 1
        while cursor < source.length {
            switch source.character(at: cursor) {
            case 123: depth += 1
            case 125:
                depth -= 1
                if depth == 0 { return cursor }
            default: break
            }
            cursor += 1
        }
        return nil
    }

    private static func containsNestedLoop(in source: String) -> Bool {
        let value = source as NSString
        for marker in matches(#"\bfor\s*\("#, in: source) {
            let opening = NSMaxRange(marker.range) - 1
            guard let headerEnd = closingParenthesis(
                in: value,
                after: opening
            ),
            let bodyRange = loopBodyRange(
                in: source,
                after: headerEnd + 1
            ) else { continue }
            let body = value.substring(with: bodyRange)
            if regexMatches(#"\b(for|while|do)\b"#, body) {
                return true
            }
        }
        return false
    }

    /// Loop work is counted from definitions, so a loop-bearing helper is
    /// only safe when exactly one direct, non-loop-nested call from `main`
    /// can execute it. This deliberately rejects indirect and overloaded
    /// call graphs instead of trying to reconstruct compiler inlining.
    private static func loopCallGraphIsSingleShot(in source: String) -> Bool {
        let loopMarkers = matches(#"\bfor\s*\("#, in: source)
        guard !loopMarkers.isEmpty else { return true }
        guard let functions = functionBodies(in: source),
              functions.filter({ $0.name == "main" }).count == 1 else {
            return false
        }
        let value = source as NSString
        var loopBodies: [NSRange] = []
        var loopFunctionNames: Set<String> = []
        for marker in loopMarkers {
            let opening = NSMaxRange(marker.range) - 1
            guard let headerEnd = closingParenthesis(
                in: value,
                after: opening
            ), let body = loopBodyRange(
                in: source,
                after: headerEnd + 1
            ), let function = functions
                .filter({
                    $0.range.location <= marker.range.location
                        && marker.range.location < NSMaxRange($0.range)
                })
                .min(by: { $0.range.length < $1.range.length }) else {
                return false
            }
            loopBodies.append(body)
            loopFunctionNames.insert(function.name)
        }

        for name in loopFunctionNames where name != "main" {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            var calls: [(caller: String, location: Int)] = []
            for function in functions {
                let body = value.substring(with: function.range)
                calls.append(contentsOf: matches(
                    #"\b"# + escaped + #"\s*\("#,
                    in: body
                ).map {
                    (function.name, function.range.location + $0.range.location)
                })
            }
            guard calls.count == 1, calls[0].caller == "main",
                  !loopBodies.contains(where: {
                      $0.location <= calls[0].location
                          && calls[0].location < NSMaxRange($0)
                  }) else {
                return false
            }
        }
        return true
    }

    private static func functionBodies(in source: String) -> [FunctionBody]? {
        let signature = #"\b(?:void|bool|int|uint|float|half|double|[biu]?vec[234]|mat[234](?:x[234])?)\s+([A-Za-z_]\w*)\s*\([^;{}]*\)\s*\{"#
        let value = source as NSString
        var result: [FunctionBody] = []
        for match in matches(signature, in: source) {
            guard let name = capture(match, 1, in: source) else { return nil }
            let opening = NSMaxRange(match.range) - 1
            guard let closing = closingBrace(in: value, after: opening) else {
                return nil
            }
            result.append(.init(
                name: name,
                range: NSRange(
                    location: opening + 1,
                    length: closing - opening - 1
                )
            ))
        }
        guard Set(result.map(\.name)).count == result.count else { return nil }
        return result
    }

    /// Without interprocedural alias analysis, passing an induction variable
    /// or its local bound to an authored helper could mutate it through
    /// `inout`. Treat every such call as unproven; ordinary reads remain valid.
    private static func isPassedToAuthoredFunction(
        _ name: String,
        in range: NSRange,
        source: String
    ) -> Bool {
        guard let functions = functionBodies(in: source) else { return true }
        let value = source as NSString
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        for function in functions {
            let escapedFunction = NSRegularExpression.escapedPattern(
                for: function.name
            )
            let body = value.substring(with: range)
            for call in matches(
                #"\b"# + escapedFunction + #"\s*\("#,
                in: body
            ) {
                let opening = range.location + NSMaxRange(call.range) - 1
                guard let closing = closingParenthesis(
                    in: value,
                    after: opening
                ), closing < NSMaxRange(range) else { return true }
                let arguments = value.substring(with: NSRange(
                    location: opening + 1,
                    length: closing - opening - 1
                ))
                if regexMatches(#"\b"# + escapedName + #"\b"#, arguments) {
                    return true
                }
            }
        }
        return false
    }

    private static func closingParenthesis(
        in source: NSString,
        after opening: Int
    ) -> Int? {
        var depth = 1
        var cursor = opening + 1
        while cursor < source.length {
            switch source.character(at: cursor) {
            case 40: depth += 1
            case 41:
                depth -= 1
                if depth == 0 { return cursor }
            default: break
            }
            cursor += 1
        }
        return nil
    }

    private static func braceDepth(in source: String, before location: Int) -> Int {
        let value = source as NSString
        var depth = 0
        for cursor in 0 ..< min(location, value.length) {
            switch value.character(at: cursor) {
            case 123: depth += 1
            case 125: depth -= 1
            default: break
            }
        }
        return depth
    }

    private static func finiteIntegral(_ raw: String) -> Int? {
        let normalized = raw.last.map { $0 == "f" || $0 == "F" } == true
            ? String(raw.dropLast()) : raw
        guard let value = Double(normalized), value.isFinite,
              value.rounded(.towardZero) == value else { return nil }
        return Int(exactly: value)
    }

    private static func loopBodyRange(
        in source: String,
        after headerEnd: Int
    ) -> NSRange? {
        let value = source as NSString
        var cursor = headerEnd
        while cursor < value.length,
              let scalar = UnicodeScalar(value.character(at: cursor)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            cursor += 1
        }
        guard cursor < value.length else { return nil }
        if value.character(at: cursor) != 123 {
            let tail = NSRange(location: cursor, length: value.length - cursor)
            let semicolon = value.range(of: ";", range: tail)
            return semicolon.location == NSNotFound
                ? nil
                : NSRange(location: cursor, length: NSMaxRange(semicolon) - cursor)
        }
        let bodyStart = cursor + 1
        var depth = 1
        cursor = bodyStart
        while cursor < value.length {
            switch value.character(at: cursor) {
            case 123: depth += 1
            case 125:
                depth -= 1
                if depth == 0 {
                    return NSRange(location: bodyStart, length: cursor - bodyStart)
                }
            default: break
            }
            cursor += 1
        }
        return nil
    }

    private static func isWritten(
        _ name: String,
        in range: NSRange,
        source: String
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"(?:\b"# + escaped
            + #"\s*(?:\+=|-=|\*=|/=|%=|=(?!=)|\+\+|--)|(?:\+\+|--)\s*\b"#
            + escaped + #"\b)"#
        return !matches(pattern, in: (source as NSString).substring(with: range)).isEmpty
    }

    static func consumeAudioLoops(in source: inout String) -> Consumption {
        let pattern = #"\bfor\s*\(\s*int\s+([A-Za-z_]\w*)\s*=\s*int\(g_AudioFrequencyMin\)\s*;\s*\1\s*<=\s*int\(g_AudioFrequencyMax\)\s*;\s*\+\+\s*\1\s*\)"#
        let loops = matches(pattern, in: source)
        guard !loops.isEmpty else { return .init(found: false, work: 0) }
        guard let bound = audioSpectrumBound(in: source) else {
            return .init(found: true, work: nil)
        }
        for loop in loops.reversed() {
            guard let range = Range(loop.range, in: source) else {
                return .init(found: true, work: nil)
            }
            source.removeSubrange(range)
        }
        return .init(found: true, work: bound * loops.count)
    }

    private static func audioSpectrumBound(in source: String) -> Int? {
        let names = matches(
            #"\b(?:float|half)\s+g_AudioSpectrum(16|32|64)(?:Left|Right)\s*\[\s*\1\s*\]"#,
            in: source
        )
        guard names.count >= 2 else { return nil }
        let bounds = names.compactMap { capture($0, 1, in: source) }.compactMap(Int.init)
        guard !bounds.isEmpty, Set(bounds).count == 1 else { return nil }
        return bounds[0]
    }

    private static func numericDefines(in source: String) -> [String: Int]? {
        var result: [String: Int] = [:]
        for match in matches(
            #"(?m)^\s*#define\s+([A-Za-z_]\w*)\s+(-?\d+)\s*$"#,
            in: source
        ) {
            guard let name = capture(match, 1, in: source),
                  let raw = capture(match, 2, in: source),
                  let value = Int(raw),
                  result.updateValue(value, forKey: name) == nil else {
                return nil
            }
        }
        return result
    }

    private static func signedBound(
        _ raw: String,
        defines: [String: Int]
    ) -> Int? {
        if let literal = Int(raw) { return literal }
        let isNegative = raw.hasPrefix("-")
        let name = isNegative ? String(raw.dropFirst()) : raw
        guard let value = defines[name] else { return nil }
        return isNegative ? -value : value
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

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else { return nil }
        return String(source[range])
    }

    private static func regexMatches(_ pattern: String, _ source: String) -> Bool {
        source.range(of: pattern, options: .regularExpression) != nil
    }
}

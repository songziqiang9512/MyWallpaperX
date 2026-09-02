import Foundation

/// Shrinks oversized linked varying arrays when both stages expose a smaller,
/// statically proven live prefix through top-level `main` loops. This keeps the
/// authored source as truth while avoiding interface locations that no stage
/// can observe.
nonisolated enum SceneAuthoredShaderVaryingArrayLivePrefixCanonicalizer {
    struct Pair {
        let vertex: String
        let fragment: String
    }

    private struct Shape: Equatable {
        let type: String
        let count: Int
    }

    private struct LoopReplacement {
        let range: Range<String.Index>
        let source: String
        let bodyRange: Range<String.Index>
    }

    private static let maximumInterfaceElements = 16
    private static let maximumIterations = 64
    private static let maximumSourceBytes = 512 * 1_024

    static func rewrite(vertex: String, fragment: String) -> Pair {
        let original = Pair(vertex: vertex, fragment: fragment)
        let linked = varyingArrays(in: vertex).filter { name, shape in
            shape.count > maximumInterfaceElements
                && varyingArrays(in: fragment)[name] == shape
        }
        var result = original
        for (name, shape) in linked.sorted(by: { $0.key < $1.key }) {
            guard let rewrittenVertex = rewriteStage(
                result.vertex, array: name, shape: shape, requireTopLevelLoop: true
            ),
                  let rewrittenFragment = rewriteStage(
                    result.fragment, array: name, shape: shape, requireTopLevelLoop: false
                  ),
                  let vertexFacts = literalReferences(array: name, in: rewrittenVertex),
                  let fragmentFacts = literalReferences(array: name, in: rewrittenFragment),
                  !fragmentFacts.indices.isEmpty,
                  fragmentFacts.indices.isSubset(of: vertexFacts.writes),
                  vertexFacts.indices == vertexFacts.writes,
                  let maximumIndex = vertexFacts.indices.union(fragmentFacts.indices).max(),
                  maximumIndex < maximumInterfaceElements else { continue }
            let count = maximumIndex + 1
            result = .init(
                vertex: replaceCount(
                    array: name, from: shape.count, to: count, in: rewrittenVertex
                ),
                fragment: replaceCount(
                    array: name, from: shape.count, to: count, in: rewrittenFragment
                )
            )
        }
        guard result.vertex.utf8.count <= maximumSourceBytes,
              result.fragment.utf8.count <= maximumSourceBytes else { return original }
        return result
    }

    private static func rewriteStage(
        _ source: String,
        array: String,
        shape: Shape,
        requireTopLevelLoop: Bool
    ) -> String? {
        guard let main = mainBody(in: source) else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: array)
        let references = regex(#"\b"# + escaped + #"\b"#).matches(
            in: source,
            range: NSRange(main, in: source)
        )
        guard !references.isEmpty else { return nil }

        let pattern = #"\bfor\s*\(\s*(?:int\s+)?([A-Za-z_]\w*)\s*=\s*0\s*;\s*\1\s*<\s*([0-9]+)\s*;\s*(?:(?:\+\+\s*\1)|(?:\1\s*\+\+)|(?:\1\s*\+=\s*([0-9]+)))\s*\)"#
        let matches = regex(pattern).matches(
            in: source,
            range: NSRange(main, in: source)
        )
        var replacements: [LoopReplacement] = []
        for match in matches {
            guard let variable = capture(match, 1, in: source),
                  let boundText = capture(match, 2, in: source),
                  let bound = Int(boundText), bound > 0,
                  let strideText = capture(match, 3, in: source) else { continue }
                  let step = strideText.isEmpty ? 1 : (Int(strideText) ?? 0)
            guard step > 0,
                  let header = Range(match.range, in: source),
                  (!requireTopLevelLoop
                    || braceDepth(at: header.lowerBound, inside: main, in: source) == 0),
                  let body = loopBody(after: header.upperBound, in: source),
                  body.range.upperBound <= main.upperBound,
                  containsWord(array, in: body.content),
                  eligible(body.content, variable: variable) else { continue }
            let values = Array(Swift.stride(from: 0, to: bound, by: step))
            guard !values.isEmpty, values.count <= maximumIterations else { continue }
            var expanded: [String] = []
            var failed = false
            for value in values {
                let substituted = replaceWord(variable, with: String(value), in: body.content)
                guard let folded = foldArraySubscripts(
                    array: array,
                    count: shape.count,
                    in: substituted
                ) else {
                    failed = true
                    break
                }
                expanded.append("{\n\(folded)\n}")
            }
            if failed { continue }
            replacements.append(.init(
                range: header.lowerBound..<body.range.upperBound,
                source: expanded.joined(separator: "\n"),
                bodyRange: body.range
            ))
        }
        guard references.allSatisfy({ reference in
            guard let range = Range(reference.range, in: source) else { return false }
            return replacements.contains { $0.bodyRange.contains(range.lowerBound) }
        }) else { return nil }
        var result = source
        for replacement in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            result.replaceSubrange(replacement.range, with: replacement.source)
        }
        return result
    }

    private static func eligible(_ body: String, variable: String) -> Bool {
        let code = withoutComments(body)
        guard regex(#"\b(break|continue|return|discard|for|while|do|if|switch)\b"#)
            .firstMatch(in: code, range: fullRange(code)) == nil else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: variable)
        let mutation = #"\b"# + escaped
            + #"\s*(?:[+\-*/%]?=|\+\+|--)|(?:\+\+|--)\s*\b"#
            + escaped + #"\b"#
        return regex(mutation).firstMatch(in: code, range: fullRange(code)) == nil
    }

    private static func foldArraySubscripts(
        array: String,
        count: Int,
        in source: String
    ) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: array)
        let matches = regex(#"\b"# + escaped + #"\s*\["#).matches(
            in: source,
            range: fullRange(source)
        )
        guard !matches.isEmpty else { return nil }
        var result = source
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: source),
                  let opening = source[..<matchRange.upperBound].lastIndex(of: "["),
                  let closing = matchingBracket(at: opening, in: source) else { return nil }
            let expressionRange = source.index(after: opening)..<closing
            guard let value = evaluate(
                String(source[expressionRange]),
                before: opening,
                in: source,
                visited: []
            ), value.isFinite,
               value.rounded(.towardZero) == value,
               let index = Int(exactly: value), (0..<count).contains(index) else {
                return nil
            }
            let resultOpening = result.index(
                result.startIndex,
                offsetBy: source.distance(from: source.startIndex, to: opening)
            )
            let resultClosing = result.index(
                result.startIndex,
                offsetBy: source.distance(from: source.startIndex, to: closing)
            )
            result.replaceSubrange(result.index(after: resultOpening)..<resultClosing, with: String(index))
        }
        return result
    }

    private static func evaluate(
        _ expression: String,
        before offset: String.Index,
        in source: String,
        visited: Set<String>
    ) -> Double? {
        var parser = SceneAuthoredShaderConstantNumericExpression(expression) { name in
            guard !visited.contains(name),
                  let assignment = lastAssignment(of: name, before: offset, in: source),
                  braceDepth(at: assignment.range.lowerBound, inside: source.startIndex..<offset, in: source) == 0,
                  !hasMutation(
                    of: name,
                    in: assignment.range.upperBound..<offset,
                    source: source
                  ), !hasFunctionCall(
                    in: assignment.range.upperBound..<offset,
                    source: source
                  )
            else { return nil }
            return evaluate(
                assignment.expression,
                before: assignment.range.lowerBound,
                in: source,
                visited: visited.union([name])
            )
        }
        return parser.parse()
    }

    private static func lastAssignment(
        of name: String,
        before offset: String.Index,
        in source: String
    ) -> (expression: String, range: Range<String.Index>)? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let matches = regex(#"\b"# + escaped + #"\s*=\s*([^;]+);"#).matches(
            in: source,
            range: NSRange(source.startIndex..<offset, in: source)
        )
        guard let match = matches.last,
              let expression = capture(match, 1, in: source),
              let range = Range(match.range, in: source) else { return nil }
        return (expression, range)
    }

    private static func hasMutation(
        of name: String,
        in range: Range<String.Index>,
        source: String
    ) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"\b"# + escaped
            + #"\s*(?:(?:\+\+|--)|(?:<<|>>|[+\-*/%&|^])?=(?!=))"#
            + #"|(?:\+\+|--)\s*\b"# + escaped + #"\b"#
        return regex(pattern).firstMatch(
            in: source,
            range: NSRange(range, in: source)
        ) != nil
    }

    private static func hasFunctionCall(
        in range: Range<String.Index>,
        source: String
    ) -> Bool {
        regex(#"\b[A-Za-z_]\w*\s*\("#).firstMatch(
            in: source,
            range: NSRange(range, in: source)
        ) != nil
    }

    private static func literalReferences(
        array: String,
        in source: String
    ) -> (indices: Set<Int>, writes: Set<Int>)? {
        guard let main = mainBody(in: source) else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: array)
        let matches = regex(#"\b"# + escaped + #"\s*\[\s*([0-9]+)\s*\]"#).matches(
            in: source,
            range: NSRange(main, in: source)
        )
        let all = regex(#"\b"# + escaped + #"\b"#).matches(
            in: source,
            range: NSRange(main, in: source)
        )
        guard matches.count == all.count else { return nil }
        var indices = Set<Int>()
        var writes = Set<Int>()
        for match in matches {
            guard let text = capture(match, 1, in: source), let index = Int(text) else { return nil }
            indices.insert(index)
            let suffixOffset = match.range.location + match.range.length
            let suffix = (source as NSString).substring(from: suffixOffset)
            if regex(#"^\s*=(?!=)"#).firstMatch(in: suffix, range: fullRange(suffix)) != nil {
                writes.insert(index)
            }
        }
        return (indices, writes)
    }

    private static func varyingArrays(in source: String) -> [String: Shape] {
        let pattern = #"(?m)^\s*varying\s+([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*\[\s*([0-9]+)\s*\]\s*;(?:\s*//.*)?$"#
        var result: [String: Shape] = [:]
        for match in regex(pattern).matches(in: source, range: fullRange(source)) {
            guard let type = capture(match, 1, in: source),
                  let name = capture(match, 2, in: source),
                  let countText = capture(match, 3, in: source),
                  let count = Int(countText), (1...128).contains(count),
                  result[name] == nil else { continue }
            result[name] = .init(type: type, count: count)
        }
        return result
    }

    private static func replaceCount(
        array: String,
        from oldCount: Int,
        to newCount: Int,
        in source: String
    ) -> String {
        let pattern = #"(?m)^(\s*varying\s+[A-Za-z_]\w*\s+"#
            + NSRegularExpression.escapedPattern(for: array)
            + #"\s*\[\s*)"# + String(oldCount) + #"(\s*\]\s*;(?:\s*//.*)?)$"#
        return regex(pattern).stringByReplacingMatches(
            in: source,
            range: fullRange(source),
            withTemplate: "$1\(newCount)$2"
        )
    }

    private static func mainBody(in source: String) -> Range<String.Index>? {
        let matches = regex(#"\bvoid\s+main\s*\(\s*\)\s*\{"#).matches(
            in: source, range: fullRange(source)
        )
        guard matches.count == 1,
              let header = Range(matches[0].range, in: source),
              let opening = source[..<header.upperBound].lastIndex(of: "{"),
              let closing = matchingBrace(at: opening, in: source) else { return nil }
        return source.index(after: opening)..<closing
    }

    private static func loopBody(
        after header: String.Index,
        in source: String
    ) -> (content: String, range: Range<String.Index>)? {
        var cursor = header
        while cursor < source.endIndex, source[cursor].isWhitespace {
            cursor = source.index(after: cursor)
        }
        guard cursor < source.endIndex, source[cursor] == "{",
              let closing = matchingBrace(at: cursor, in: source) else { return nil }
        return (
            String(source[source.index(after: cursor)..<closing]),
            cursor..<source.index(after: closing)
        )
    }

    private static func matchingBrace(at opening: String.Index, in source: String) -> String.Index? {
        matchingDelimiter(at: opening, open: "{", close: "}", in: source)
    }

    private static func matchingBracket(at opening: String.Index, in source: String) -> String.Index? {
        matchingDelimiter(at: opening, open: "[", close: "]", in: source)
    }

    private static func matchingDelimiter(
        at opening: String.Index,
        open: Character,
        close: Character,
        in source: String
    ) -> String.Index? {
        var depth = 0
        var cursor = opening
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == open { depth += 1 }
            if character == close {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func braceDepth(
        at index: String.Index,
        inside range: Range<String.Index>,
        in source: String
    ) -> Int {
        guard range.lowerBound <= index else { return -1 }
        return source[range.lowerBound..<index].reduce(into: 0) { depth, character in
            if character == "{" { depth += 1 }
            if character == "}" { depth -= 1 }
        }
    }

    private static func withoutComments(_ source: String) -> String {
        source.replacingOccurrences(
            of: #"(?s)/\*.*?\*/|//[^\n]*"#,
            with: " ",
            options: .regularExpression
        )
    }

    private static func replaceWord(_ word: String, with value: String, in source: String) -> String {
        regex(#"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#)
            .stringByReplacingMatches(in: source, range: fullRange(source), withTemplate: value)
    }

    private static func containsWord(_ word: String, in source: String) -> Bool {
        regex(#"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#)
            .firstMatch(in: source, range: fullRange(source)) != nil
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    private static func fullRange(_ source: String) -> NSRange {
        NSRange(source.startIndex..., in: source)
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else { return "" }
        return String(source[range])
    }
}

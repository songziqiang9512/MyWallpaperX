import Foundation

/// Applies bounded, source-driven lowering shared by both authored shader
/// backends. The prepared authored source remains the loss-preserving truth;
/// this pass only canonicalizes compiler input when the observable result is
/// fully determined by static source facts.
nonisolated enum SceneAuthoredShaderBackendCanonicalizer {
    struct Pair: Equatable {
        let vertex: String
        let fragment: String
    }

    private struct VaryingArray: Equatable {
        let type: String
        let count: Int
    }

    private struct LoopBody {
        let content: String
        let replacementRange: Range<String.Index>
    }

    private static let maximumUnrolledIterations = 16
    private static let maximumSourceBytes = 512 * 1_024

    static func canonicalize(vertex: String, fragment: String) -> Pair {
        let original = Pair(vertex: vertex, fragment: fragment)
        var result = Pair(
            vertex: SceneAuthoredShaderBuiltInVectorConversion
                .rewriteScalarMixBroadcasts(vertex, stage: .vertex),
            fragment: SceneAuthoredShaderBuiltInVectorConversion
                .rewriteScalarMixBroadcasts(fragment, stage: .fragment)
        )
        let arrays = linkedVaryingArrays(
            vertex: result.vertex,
            fragment: result.fragment
        )
        if !arrays.isEmpty {
            result = Pair(
                vertex: unrollStaticVaryingLoops(
                    in: result.vertex,
                    arrays: arrays
                ),
                fragment: unrollStaticVaryingLoops(
                    in: result.fragment,
                    arrays: arrays
                )
            )
            result = compactVaryingArrays(
                result,
                arrays: arrays.filter {
                    $0.value.count > maximumUnrolledIterations
                }
            )
        }
        guard result.vertex.utf8.count <= maximumSourceBytes,
              result.fragment.utf8.count <= maximumSourceBytes else {
            return original
        }
        return result
    }

    private static func linkedVaryingArrays(
        vertex: String,
        fragment: String
    ) -> [String: VaryingArray] {
        let vertexArrays = varyingArrays(in: vertex)
        let fragmentArrays = varyingArrays(in: fragment)
        return vertexArrays.filter { name, value in
            fragmentArrays[name] == value
        }
    }

    private static func varyingArrays(in source: String) -> [String: VaryingArray] {
        let pattern = #"(?m)^\s*varying\s+([A-Za-z_]\w*)\s+([A-Za-z_]\w*)\s*\[\s*([0-9]+)\s*\]\s*;(?:\s*//.*)?$"#
        let matches = regex(pattern).matches(in: source, range: fullRange(source))
        var result: [String: VaryingArray] = [:]
        var duplicates = Set<String>()
        for match in matches {
            guard let type = capture(match, 1, in: source),
                  let name = capture(match, 2, in: source),
                  let countText = capture(match, 3, in: source),
                  let count = Int(countText), (1 ... 128).contains(count) else {
                continue
            }
            if result.updateValue(.init(type: type, count: count), forKey: name) != nil {
                duplicates.insert(name)
            }
        }
        for name in duplicates { result.removeValue(forKey: name) }
        return result
    }

    private static func unrollStaticVaryingLoops(
        in source: String,
        arrays: [String: VaryingArray]
    ) -> String {
        guard !arrays.isEmpty else { return source }
        let headerPattern = #"\bfor\s*\(\s*int\s+([A-Za-z_]\w*)\s*=\s*0\s*;\s*\1\s*<\s*([^;]+?)\s*;\s*(?:(?:\+\+\s*\1)|(?:\1\s*\+\+))\s*\)"#
        let header = regex(headerPattern)
        var result = source
        var replacementCount = 0
        while replacementCount < 32 {
            let matches = header.matches(in: result, range: fullRange(result))
            var replacement: (Range<String.Index>, String)?
            for match in matches {
                guard let variable = capture(match, 1, in: result),
                      let rawBound = capture(match, 2, in: result),
                      let iterations = staticBound(
                          rawBound,
                          before: match.range.location,
                          in: result
                      ), (1 ... maximumUnrolledIterations).contains(iterations),
                      let headerRange = Range(match.range, in: result),
                      let body = loopBody(after: headerRange.upperBound, in: result),
                      eligible(
                          body.content,
                          variable: variable,
                          iterations: iterations,
                          arrays: arrays
                      )
                else { continue }
                let variablePattern = #"\b"#
                    + NSRegularExpression.escapedPattern(for: variable) + #"\b"#
                let variableRegex = regex(variablePattern)
                let expanded = (0 ..< iterations).map { value in
                    let content = variableRegex.stringByReplacingMatches(
                        in: body.content,
                        range: fullRange(body.content),
                        withTemplate: String(value)
                    )
                    return "{\n\(content)\n}"
                }.joined(separator: "\n")
                replacement = (
                    headerRange.lowerBound..<body.replacementRange.upperBound,
                    expanded
                )
                break
            }
            guard let replacement else { break }
            result.replaceSubrange(replacement.0, with: replacement.1)
            replacementCount += 1
        }
        return result
    }

    private static func staticBound(
        _ raw: String,
        before offset: Int,
        in source: String
    ) -> Int? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let integer = Int(value) { return integer }
        if let product = literalFloatProduct(value) { return product }
        guard let match = firstMatch(
            #"^int\s*\(\s*([A-Za-z_]\w*)\s*\)$"#,
            in: value
        ), let name = capture(match, 1, in: value) else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let declarationPattern = #"\b(?:const\s+)?float\s+"# + escaped
            + #"\s*=\s*(float\s*\(\s*[0-9]+\s*\)\s*\*\s*[0-9]+(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)\s*;"#
        let declarations = regex(declarationPattern).matches(
            in: source,
            range: NSRange(location: 0, length: min(offset, source.utf16.count))
        )
        guard declarations.count == 1,
              let expression = capture(declarations[0], 1, in: source) else {
            return nil
        }
        let writePattern = #"\b"# + escaped + #"\s*(?:[+\-*/%]?=|\+\+|--)"#
        guard regex(writePattern).numberOfMatches(
            in: source,
            range: fullRange(source)
        ) == 1 else { return nil }
        return literalFloatProduct(expression) ?? exactInteger(expression)
    }

    private static func literalFloatProduct(_ raw: String) -> Int? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = firstMatch(
            #"^(?:int\s*\(\s*)?float\s*\(\s*([0-9]+)\s*\)\s*\*\s*([0-9]+(?:\.[0-9]+)?)(?:\s*\))?$"#,
            in: value
        ), let leftText = capture(match, 1, in: value),
           let rightText = capture(match, 2, in: value),
           let left = Double(leftText), let right = Double(rightText) else {
            return nil
        }
        return exactInteger(String(left * right))
    }

    private static func exactInteger(_ raw: String) -> Int? {
        guard let value = Double(raw), value.isFinite,
              value.rounded(.towardZero) == value else { return nil }
        return Int(exactly: value)
    }

    private static func eligible(
        _ body: String,
        variable: String,
        iterations: Int,
        arrays: [String: VaryingArray]
    ) -> Bool {
        let escapedVariable = NSRegularExpression.escapedPattern(for: variable)
        let code = withoutComments(body)
        guard regex(#"\b(break|continue|return|discard|for|while|do)\b"#)
            .firstMatch(in: code, range: fullRange(code)) == nil else { return false }
        guard regex(
            #"\b"# + escapedVariable
                + #"\s*(?:[+\-*/%]?=|\+\+|--)|(?:\+\+|--)\s*\b"#
                + escapedVariable + #"\b"#
        ).numberOfMatches(in: body, range: fullRange(body)) == 0 else { return false }
        let referencedArrays = arrays.compactMap { name, shape in
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name)
                + #"\s*\[\s*"# + escapedVariable + #"\s*\]"#
            return regex(pattern).firstMatch(in: body, range: fullRange(body)) == nil
                ? nil : shape
        }
        return !referencedArrays.isEmpty
            && referencedArrays.allSatisfy { iterations <= $0.count }
    }

    private static func loopBody(
        after header: String.Index,
        in source: String
    ) -> LoopBody? {
        var cursor = header
        while cursor < source.endIndex, source[cursor].isWhitespace {
            cursor = source.index(after: cursor)
        }
        guard cursor < source.endIndex else { return nil }
        if source[cursor] == "{" {
            guard let closing = matchingBrace(at: cursor, in: source) else { return nil }
            let contentStart = source.index(after: cursor)
            return .init(
                content: String(source[contentStart..<closing]),
                replacementRange: cursor..<source.index(after: closing)
            )
        }
        guard let semicolon = source[cursor...].firstIndex(of: ";") else { return nil }
        let end = source.index(after: semicolon)
        return .init(
            content: String(source[cursor..<end]),
            replacementRange: cursor..<end
        )
    }

    private static func matchingBrace(
        at opening: String.Index,
        in source: String
    ) -> String.Index? {
        enum LexicalState {
            case code
            case lineComment
            case blockComment
        }

        var depth = 0
        var cursor = opening
        var state = LexicalState.code
        while cursor < source.endIndex {
            let character = source[cursor]
            let next = source.index(after: cursor)
            let nextCharacter = next < source.endIndex ? source[next] : nil
            switch state {
            case .lineComment:
                if character == "\n" { state = .code }
                cursor = next
                continue
            case .blockComment:
                if character == "*", nextCharacter == "/" {
                    state = .code
                    cursor = source.index(after: next)
                } else {
                    cursor = next
                }
                continue
            case .code:
                if character == "/", nextCharacter == "/" {
                    state = .lineComment
                    cursor = source.index(after: next)
                    continue
                }
                if character == "/", nextCharacter == "*" {
                    state = .blockComment
                    cursor = source.index(after: next)
                    continue
                }
            }
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor = next
        }
        return nil
    }

    private static func compactVaryingArrays(
        _ pair: Pair,
        arrays: [String: VaryingArray]
    ) -> Pair {
        var vertex = pair.vertex
        var fragment = pair.fragment
        for (name, shape) in arrays.sorted(by: { $0.key < $1.key }) {
            guard let vertexCount = requiredElementCount(name, in: vertex),
                  let fragmentCount = requiredElementCount(name, in: fragment),
                  vertexCount == fragmentCount,
                  (1 ... maximumUnrolledIterations).contains(vertexCount),
                  vertexCount <= shape.count else { continue }
            vertex = replaceVaryingCount(
                name: name, from: shape.count, to: vertexCount, in: vertex
            )
            fragment = replaceVaryingCount(
                name: name, from: shape.count, to: vertexCount, in: fragment
            )
        }
        return .init(vertex: vertex, fragment: fragment)
    }

    private static func requiredElementCount(_ name: String, in source: String) -> Int? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let declarationPattern = #"(?m)^\s*varying\s+[A-Za-z_]\w*\s+"#
            + escaped + #"\s*\[\s*[0-9]+\s*\]\s*;(?:\s*//.*)?$"#
        let scrubbed = regex(declarationPattern).stringByReplacingMatches(
            in: withoutComments(source),
            range: fullRange(withoutComments(source)),
            withTemplate: ""
        )
        let occurrences = regex(#"\b"# + escaped + #"\b"#).matches(
            in: scrubbed,
            range: fullRange(scrubbed)
        )
        guard !occurrences.isEmpty else { return nil }
        var maximum = -1
        for occurrence in occurrences {
            let suffixStart = occurrence.range.location + occurrence.range.length
            let suffix = (scrubbed as NSString).substring(from: suffixStart)
            guard let subscriptMatch = regex(#"^\s*\[\s*([0-9]+)\s*\]"#)
                .firstMatch(in: suffix, range: fullRange(suffix)),
                  subscriptMatch.range.location == 0,
                  let indexText = capture(subscriptMatch, 1, in: suffix),
                  let index = Int(indexText) else { return nil }
            maximum = max(maximum, index)
        }
        return maximum + 1
    }

    private static func replaceVaryingCount(
        name: String,
        from oldCount: Int,
        to newCount: Int,
        in source: String
    ) -> String {
        let pattern = #"(?m)^(\s*varying\s+[A-Za-z_]\w*\s+"#
            + NSRegularExpression.escapedPattern(for: name)
            + #"\s*\[\s*)"# + String(oldCount) + #"(\s*\]\s*;(?:\s*//.*)?)$"#
        return regex(pattern).stringByReplacingMatches(
            in: source,
            range: fullRange(source),
            withTemplate: "$1\(newCount)$2"
        )
    }

    private static func withoutComments(_ source: String) -> String {
        source.replacingOccurrences(
            of: #"(?s)/\*.*?\*/|//[^\n]*"#,
            with: " ",
            options: .regularExpression
        )
    }

    private static func firstMatch(
        _ pattern: String,
        in source: String
    ) -> NSTextCheckingResult? {
        regex(pattern).firstMatch(in: source, range: fullRange(source))
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
              let range = Range(match.range(at: index), in: source) else { return nil }
        return String(source[range])
    }
}

import Foundation

/// Verifies the compiler-visible terminal shape for an independent RGBA
/// accumulator whose typed render attachment supplies the final UNorm clamp.
/// The authored-source analyzer owns the graph and loop proof; this owner only
/// accepts one whole float4 carrier scaled by explicit scalar facts.
nonisolated enum SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer {
    static func validates(_ source: String, expectedSlot: Int) -> Bool {
        guard (0 ..< 8).contains(expectedSlot),
              matches(
                #"\bg_Texture([0-7])\s*\.\s*sample\s*\("#,
                in: source
              ).compactMap({ capture($0, 1, in: source).flatMap(Int.init) })
                == [expectedSlot],
              let body = fragmentBody(in: source) else { return false }
        let assignments = matches(
            #"\bout\.mwxFragColor\s*=\s*([^;]+)\s*;"#,
            in: body
        )
        guard assignments.count == 1,
              matches(#"\bout\.mwxFragColor\b"#, in: body).count == 1,
              matches(#"\breturn\s+out\s*;"#, in: body).count == 1,
              let expression = capture(assignments[0], 1, in: body),
              let factors = flattenedProduct(expression) else { return false }
        let carriers = factors.filter { factor in
            guard regexMatches(#"^[A-Za-z_]\w*$"#, factor) else { return false }
            return matches(
                #"\bfloat4\s+"# + escaped(factor) + #"\b"#,
                in: body
            ).count == 1
        }
        guard carriers.count == 1 else { return false }
        var remaining = factors
        guard let carrierIndex = remaining.firstIndex(of: carriers[0]) else {
            return false
        }
        remaining.remove(at: carrierIndex)
        return !remaining.isEmpty && remaining.allSatisfy {
            scalarFact($0, in: source)
        }
    }

    private static func scalarFact(_ value: String, in source: String) -> Bool {
        if regexMatches(
            #"^[+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?[fF]?$"#,
            value
        ) { return true }
        guard let identity = captures(
            #"^(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)$"#,
            in: value
        ), identity.count == 2 else { return false }
        let name = identity[1]
        return matches(
            #"\bfloat\s+"# + escaped(name) + #"\s*(?:[;=])"#,
            in: source
        ).count == 1
    }

    private static func flattenedProduct(_ expression: String) -> [String]? {
        let value = strippingOuterParentheses(expression)
        guard let factors = splitTopLevel(value, separator: "*") else {
            return nil
        }
        if factors.count == 1 { return [value] }
        var result: [String] = []
        for factor in factors {
            guard let nested = flattenedProduct(factor) else { return nil }
            result.append(contentsOf: nested)
        }
        return result
    }

    private static func strippingOuterParentheses(_ source: String) -> String {
        var value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.first == "(", value.last == ")",
              matchingDelimiter(
                in: value, opening: value.startIndex
              ) == value.index(before: value.endIndex) {
            value = String(
                value[
                    value.index(after: value.startIndex)
                        ..< value.index(before: value.endIndex)
                ]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func splitTopLevel(
        _ source: String,
        separator: Character
    ) -> [String]? {
        var parts: [String] = []
        var start = source.startIndex
        var stack: [Character] = []
        let opening: Set<Character> = ["(", "[", "{"]
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        for index in source.indices {
            let character = source[index]
            if opening.contains(character) { stack.append(character) }
            else if let expected = pairs[character] {
                guard stack.popLast() == expected else { return nil }
            } else if character == separator, stack.isEmpty {
                let part = String(source[start..<index])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !part.isEmpty else { return nil }
                parts.append(part)
                start = source.index(after: index)
            }
        }
        let tail = String(source[start...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard stack.isEmpty, !tail.isEmpty else { return nil }
        parts.append(tail)
        return parts
    }

    private static func fragmentBody(in source: String) -> String? {
        let signatures = matches(
            #"\bfragment\b[^\{;]*\bmwxGenericFragment\s*\([^\{;]*\)\s*\{"#,
            in: source
        )
        guard signatures.count == 1,
              let range = Range(signatures[0].range, in: source) else { return nil }
        let opening = source.index(before: range.upperBound)
        guard let closing = matchingDelimiter(in: source, opening: opening) else {
            return nil
        }
        return String(source[source.index(after: opening)..<closing])
    }

    private static func matchingDelimiter(
        in source: String,
        opening: String.Index
    ) -> String.Index? {
        let left = source[opening]
        let right: Character = left == "(" ? ")" : "}"
        var depth = 0
        var index = opening
        while index < source.endIndex {
            if source[index] == left { depth += 1 }
            if source[index] == right {
                depth -= 1
                if depth == 0 { return index }
                if depth < 0 { return nil }
            }
            index = source.index(after: index)
        }
        return nil
    }

    private static func matches(
        _ pattern: String,
        in source: String
    ) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern))?.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) ?? []
    }

    private static func captures(_ pattern: String, in source: String) -> [String]? {
        guard let match = matches(pattern, in: source).first else { return nil }
        return (1 ..< match.numberOfRanges).map {
            capture(match, $0, in: source) ?? ""
        }
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in source: String
    ) -> String? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source) else { return nil }
        return String(source[range])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func regexMatches(_ pattern: String, _ source: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        return expression.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )?.range == NSRange(source.startIndex..., in: source)
    }

    private static func escaped(_ source: String) -> String {
        NSRegularExpression.escapedPattern(for: source)
    }
}

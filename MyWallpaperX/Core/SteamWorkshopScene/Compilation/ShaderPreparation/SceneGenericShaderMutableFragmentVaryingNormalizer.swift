import Foundation

/// Lowers the authored-dialect convention where a fragment varying doubles
/// as a mutable working coordinate. Vulkan GLSL stage inputs remain read-only;
/// only values whose complete use is local to `main` receive a local copy.
nonisolated enum SceneGenericShaderMutableFragmentVaryingNormalizer {
    struct Output {
        let source: String
        let localizedNames: Set<String>
    }

    struct Shape {
        let type: String
        let count: Int?
    }

    static func rewrite(
        _ source: String,
        varyings: [String: Shape]
    ) -> Output? {
        let main = regex(#"\bvoid\s+main\s*\(\s*\)\s*\{"#)
        let matches = main.matches(in: source, range: fullRange(source))
        guard matches.count == 1,
              let headerRange = Range(matches[0].range, in: source),
              let opening = source[..<headerRange.upperBound].lastIndex(of: "{"),
              let closing = matchingBrace(at: opening, in: source) else {
            return nil
        }

        let contentStart = source.index(after: opening)
        let prefix = withoutComments(String(source[..<opening]))
        let suffix = withoutComments(String(source[source.index(after: closing)...]))
        var content = String(source[contentStart..<closing])
        let code = withoutComments(content)
        var mutable: [(name: String, shape: Shape, local: String)] = []

        for (name, shape) in varyings.sorted(by: { $0.key < $1.key }) {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let member = #"(?:\s*(?:\.[A-Za-z_][A-Za-z0-9_]*|\[[^\]\n]+\]))*"#
            let mutation = regex(
                #"(?:\+\+|--)\s*\b"# + escaped + #"\b"# + member
                    + #"|\b"# + escaped + #"\b"# + member
                    + #"\s*(?:[+\-*/%]?=|\+\+|--)"#
            )
            guard mutation.firstMatch(in: code, range: fullRange(code)) != nil else {
                continue
            }
            guard shape.count == nil,
                  !containsWord(name, in: prefix),
                  !containsWord(name, in: suffix) else {
                return nil
            }
            let local = "mwxMutable_\(name)"
            guard !containsWord(local, in: source) else { return nil }
            mutable.append((name, shape, local))
        }
        guard !mutable.isEmpty else {
            return .init(source: source, localizedNames: [])
        }

        for item in mutable {
            content = replaceWord(item.name, with: item.local, in: content)
        }
        let initializers = mutable.map {
            "    \($0.shape.type) \($0.local) = \($0.name);"
        }.joined(separator: "\n")
        var result = source
        result.replaceSubrange(
            contentStart..<closing,
            with: "\n\(initializers)\n\(content)"
        )
        return .init(
            source: result,
            localizedNames: Set(mutable.map(\.name))
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

    private static func withoutComments(_ source: String) -> String {
        source.replacingOccurrences(
            of: #"(?s)/\*.*?\*/|//[^\n]*"#,
            with: " ",
            options: .regularExpression
        )
    }

    private static func replaceWord(
        _ word: String,
        with replacement: String,
        in source: String
    ) -> String {
        regex(#"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#)
            .stringByReplacingMatches(
                in: source,
                range: fullRange(source),
                withTemplate: replacement
            )
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
}

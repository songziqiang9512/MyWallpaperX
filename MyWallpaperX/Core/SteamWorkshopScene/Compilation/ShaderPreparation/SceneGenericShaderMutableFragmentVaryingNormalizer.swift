import Foundation

/// Lowers the authored-dialect convention where a fragment varying doubles
/// as a mutable working coordinate. Vulkan GLSL stage inputs remain read-only;
/// only proven global references confined to `main` receive a local copy.
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
        guard !varyings.isEmpty else { return .init(source: source, localizedNames: []) }
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let declarations = varyings.sorted(by: { $0.key < $1.key }).map { name, shape in
            "varying \(shape.type) \(name)" + (shape.count.map { "[\($0)]" } ?? "") + ";"
        }.joined(separator: "\n") + "\n"
        let analysisSource = declarations + normalized
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: analysisSource, stage: .fragment),
            stage: .fragment
        )
        // Unknown syntax remains the backend's input. It cannot authorize a
        // name-wide rewrite or a synthetic mutable copy.
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit,
              let main = unit.functions.first(where: { $0.name == "main" }) else {
            return .init(source: source, localizedNames: [])
        }
        let tokens = unit.tokens
        let body = (main.bodyRange.lowerBound + 1)..<(main.bodyRange.upperBound - 1)
        var mutable: [(name: String, type: String, local: String, references: [Int])] = []
        for (name, shape) in varyings.sorted(by: { $0.key < $1.key }) {
            // An incomplete proof leaves this name unchanged for the backend;
            // an actual write to a read-only stage input will still be rejected.
            guard let references = SceneAuthoredShaderGlobalReferenceAnalyzer.exactReferenceIndices(name, in: unit),
                  references.contains(where: { isMutation(at: $0, tokens: tokens) }) else { continue }
            guard shape.count == nil,
                  references.allSatisfy({ body.contains($0) }) else { return nil }
            let local = "mwxMutable_\(name)"
            guard !tokens.contains(where: { $0.text == local }) else { return nil }
            mutable.append((name, shape.type, local, references))
        }
        guard !mutable.isEmpty else { return .init(source: source, localizedNames: []) }

        // Lexer locations refer to Unicode scalars in this exact analysis
        // source. Remove only the synthetic declaration prefix from offsets.
        var lineStarts = [0]
        var offset = 0
        for scalar in analysisSource.unicodeScalars {
            offset += 1
            if scalar == "\n" { lineStarts.append(offset) }
        }
        let prefixCount = declarations.unicodeScalars.count
        func sourceOffset(_ index: Int) -> Int {
            let token = tokens[index]
            return lineStarts[token.line - 1] + token.column - 1 - prefixCount
        }
        var edits: [(range: Range<Int>, text: String)] = []
        for item in mutable {
            for reference in item.references {
                let start = sourceOffset(reference)
                edits.append((start..<(start + item.name.unicodeScalars.count), item.local))
            }
        }
        let initializers = mutable.map { "    \($0.type) \($0.local) = \($0.name);" }
            .joined(separator: "\n")
        let contentStart = sourceOffset(main.bodyRange.lowerBound) + 1
        edits.append((contentStart..<contentStart, "\n" + initializers + "\n"))
        var scalars = Array(normalized.unicodeScalars)
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            scalars.replaceSubrange(edit.range, with: edit.text.unicodeScalars)
        }
        return .init(source: String(String.UnicodeScalarView(scalars)),
            localizedNames: Set(mutable.map(\.name)))
    }

    private static func isMutation(at index: Int, tokens: [SceneAuthoredShaderToken]) -> Bool {
        if index > 0, ["++", "--"].contains(tokens[index - 1].text) { return true }
        var cursor = index + 1
        while cursor < tokens.count {
            if tokens[cursor].text == ".", cursor + 1 < tokens.count,
               tokens[cursor + 1].kind == .identifier {
                cursor += 2
            } else if tokens[cursor].text == "[",
                      let end = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(at: cursor, tokens: tokens) {
                cursor = end + 1
            } else {
                return ["=", "+=", "-=", "*=", "/=", "%=", "++", "--"].contains(tokens[cursor].text)
            }
        }
        return false
    }
}

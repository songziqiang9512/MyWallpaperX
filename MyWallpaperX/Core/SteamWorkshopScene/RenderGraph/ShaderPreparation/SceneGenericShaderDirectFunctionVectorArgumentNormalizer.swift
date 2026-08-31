import Foundation

/// Applies the one direct user-function vector conversion that can remain
/// valid when the broader bounded syntax analyzer rejects unrelated language.
nonisolated enum SceneGenericShaderDirectFunctionVectorArgumentNormalizer {
    typealias Shape = SceneGenericShaderSourceNormalizer.Shape

    /// Uses the complete bounded syntax graph whenever that graph accepts the
    /// authored stage. Unknown expressions and overloads remain fail-closed.
    static func rewriteUsingBoundedSyntax(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> String {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix("#version")
                ? "" : line
        }.joined(separator: "\n")
        let lexer = SceneAuthoredShaderLexer.lex(source: analysisSource, stage: stage)
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: lexer,
            stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit else {
            return normalized
        }

        var lineStarts = [0]
        var scalarOffset = 0
        for scalar in normalized.unicodeScalars {
            scalarOffset += 1
            if scalar == "\n" { lineStarts.append(scalarOffset) }
        }
        let insertions = unit.tokens.indices.compactMap { index -> (Int, String)? in
            let token = unit.tokens[index]
            guard token.kind == .identifier,
                  let suffix = SceneAuthoredShaderVectorConversion.suffix(
                      forIdentifierAt: index,
                      in: unit.tokens,
                      unit: unit
                  ), token.line > 0, token.line <= lineStarts.count else {
                return nil
            }
            let end = lineStarts[token.line - 1] + token.column - 1
                + token.text.unicodeScalars.count
            guard end <= normalized.unicodeScalars.count else { return nil }
            return (end, ".\(suffix)")
        }.sorted { $0.0 > $1.0 }
        guard !insertions.isEmpty else { return normalized }

        var result = normalized
        for (offset, suffix) in insertions {
            let scalarIndex = result.unicodeScalars.index(
                result.unicodeScalars.startIndex,
                offsetBy: offset
            )
            guard let index = String.Index(scalarIndex, within: result) else {
                return normalized
            }
            result.insert(contentsOf: suffix, at: index)
        }
        return result
    }

    /// An unambiguous user function can consume the leading components of a
    /// directly named wider authored vector. Complete local definitions are
    /// required; overloaded names, compound expressions and locally shadowed
    /// identifiers remain untouched for the helper compiler to reject.
    static func rewrite(_ source: String, shapes: [String: Shape]) -> String {
        let valueType = #"(?:bool|int|uint|float|[biu]?vec[2-4]|mat[2-4])"#
        let definition = try! NSRegularExpression(
            pattern: #"\b"# + valueType
                + #"\s+([A-Za-z_]\w*)\s*\(([^()]*)\)\s*\{"#
        )
        let parameter = try! NSRegularExpression(
            pattern: #"^(?:(?:const|in|out|inout|highp|mediump|lowp)\s+)*("#
                + valueType + #")\s+[A-Za-z_]\w*$"#
        )
        var signatures: [String: [[Int?]]] = [:]
        for match in definition.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) {
            guard let nameRange = Range(match.range(at: 1), in: source),
                  let parametersRange = Range(match.range(at: 2), in: source) else {
                continue
            }
            let rawParameters = source[parametersRange]
                .split(separator: ",", omittingEmptySubsequences: false)
            if rawParameters.count == 1,
               String(rawParameters[0]).trimmingCharacters(
                   in: .whitespacesAndNewlines
               ).isEmpty {
                signatures[String(source[nameRange]), default: []].append([])
                continue
            }
            var widths: [Int?] = []
            for raw in rawParameters {
                let value = String(raw).trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let range = NSRange(value.startIndex..., in: value)
                guard let parameterMatch = parameter.firstMatch(in: value, range: range),
                      parameterMatch.range == range,
                      let typeRange = Range(parameterMatch.range(at: 1), in: value) else {
                    widths.removeAll()
                    break
                }
                widths.append(floatVectorWidth(String(value[typeRange])))
            }
            guard widths.count == rawParameters.count else { continue }
            signatures[String(source[nameRange]), default: []].append(widths)
        }

        var replacements: [(range: NSRange, value: String)] = []
        for (name, candidates) in signatures where candidates.count == 1 {
            let widths = candidates[0]
            guard widths.contains(where: { $0 != nil }) else { continue }
            let call = try! NSRegularExpression(
                pattern: #"\b"# + NSRegularExpression.escapedPattern(for: name)
                    + #"\s*\(([^()]*)\)"#
            )
            for match in call.matches(
                in: source,
                range: NSRange(source.startIndex..., in: source)
            ).reversed() {
                guard let argumentsRange = Range(match.range(at: 1), in: source) else {
                    continue
                }
                let rawArguments = source[argumentsRange]
                    .split(separator: ",", omittingEmptySubsequences: false)
                guard rawArguments.count == widths.count else { continue }
                var arguments = rawArguments.map {
                    String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                var changed = false
                for index in arguments.indices {
                    guard let targetWidth = widths[index],
                          arguments[index].range(
                              of: #"^[A-Za-z_]\w*$"#,
                              options: .regularExpression
                          ) != nil,
                          let shape = shapes[arguments[index]],
                          shape.count == nil,
                          let sourceWidth = floatVectorWidth(shape.type),
                          sourceWidth > targetWidth,
                          !hasLocalDeclaration(arguments[index], in: source) else {
                        continue
                    }
                    arguments[index] += targetWidth == 2 ? ".xy" : ".xyz"
                    changed = true
                }
                guard changed else { continue }
                replacements.append(
                    (
                        range: match.range,
                        value: "\(name)(\(arguments.joined(separator: ", ")))"
                    )
                )
            }
        }
        var result = source
        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            guard let range = Range(replacement.range, in: result) else { return source }
            result.replaceSubrange(range, with: replacement.value)
        }
        return result
    }

    private static func floatVectorWidth(_ type: String) -> Int? {
        guard type.hasPrefix("vec"), let width = Int(type.dropFirst(3)),
              (2 ... 4).contains(width) else { return nil }
        return width
    }

    private static func hasLocalDeclaration(_ name: String, in source: String) -> Bool {
        let valueTypes = [
            "bool", "int", "uint", "float",
            "ivec2", "ivec3", "ivec4",
            "uvec2", "uvec3", "uvec4",
            "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
        ]
        let types = valueTypes.map(
            NSRegularExpression.escapedPattern
        ).joined(separator: "|")
        let regex = try! NSRegularExpression(
            pattern: #"\b(?:"# + types + #")\s+"#
                + NSRegularExpression.escapedPattern(for: name) + #"\b"#
        )
        return regex.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) != nil
    }
}

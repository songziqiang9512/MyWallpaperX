import Foundation

/// Preserves authored sampling coordinates while normalizing sampler aliases
/// and the supported scalar/vector result conversions.
nonisolated enum SceneGenericShaderTextureSamplingNormalizer {
    static func rewrite(_ source: String) -> String {
        let functions = ["texSample2D", "texture2D", "texSample2DLod", "texture2DLod"]
        let names = functions.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        let definition = try! NSRegularExpression(
            pattern: #"\b(?:bool|int|uint|float|[biu]?vec[2-4]|mat[2-4])\s+(?:"#
                + names + #")\s*\("#
        )
        guard definition.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ) == nil else { return source }
        let assignment = try! NSRegularExpression(
            pattern: #"\b(float|vec2|vec3)\s+[A-Za-z_]\w*\s*=\s*(?:"#
                + names + #")\s*\("#
        )
        let insertions = assignment.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        ).compactMap { match -> (String.Index, String)? in
            guard let typeRange = Range(match.range(at: 1), in: source),
                  let prefixRange = Range(match.range, in: source),
                  let open = source[..<prefixRange.upperBound].lastIndex(of: "("),
                  let close = matchingParenthesis(in: source, openingAt: open) else {
                return nil
            }
            let remainder = source[source.index(after: close)...]
            guard let semicolon = remainder.firstIndex(of: ";"),
                  remainder[..<semicolon].trimmingCharacters(
                      in: .whitespacesAndNewlines
                  ).isEmpty else { return nil }
            let suffix = switch String(source[typeRange]) {
            case "float": ".r"
            case "vec2": ".xy"
            default: ".xyz"
            }
            return (source.index(after: close), suffix)
        }.sorted { $0.0 > $1.0 }
        var result = source
        for (index, suffix) in insertions {
            result.insert(contentsOf: suffix, at: index)
        }
        return result
    }

    private static func matchingParenthesis(
        in source: String,
        openingAt opening: String.Index
    ) -> String.Index? {
        var depth = 0
        var index = opening
        while index < source.endIndex {
            switch source[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
            case "/":
                let next = source.index(after: index)
                if next < source.endIndex, source[next] == "/" {
                    index = source[next...].firstIndex(of: "\n") ?? source.endIndex
                    continue
                }
                if next < source.endIndex, source[next] == "*",
                   let end = source[next...].range(of: "*/")?.upperBound {
                    index = end
                    continue
                }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }

    static func supportLines() -> [String] {
        [
            "#define texSample2D(textureValue, value) texture(textureValue, value)",
            "#define texture2D(textureValue, value) texture(textureValue, value)",
            "#define texSample2DLod(textureValue, value, lodValue) textureLod(textureValue, value, lodValue)",
            "#define texture2DLod(textureValue, value, lodValue) textureLod(textureValue, value, lodValue)",
        ]
    }
}

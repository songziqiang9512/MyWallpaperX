import Foundation

/// Normalizes the generic compiler's texture-sampling surface while keeping
/// every active sampler on the shared host texture-transform ABI.
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

    static func uniformLines(activeSlots: [Int]) -> [String] {
        activeSlots.flatMap { slot in
            [
                SceneMaterialTextureTransformABI.Component.originAndXAxis,
                .yAxis,
            ].map { component in
                let name = SceneMaterialTextureTransformABI.fieldName(
                    slot: slot,
                    component: component
                )
                return "    vec4 \(name);"
            }
        }
    }

    static func supportLines(activeSlots: [Int]) -> [String] {
        let functions = activeSlots.map { slot in
            let first = SceneMaterialTextureTransformABI.fieldName(
                slot: slot,
                component: .originAndXAxis
            )
            let second = SceneMaterialTextureTransformABI.fieldName(
                slot: slot,
                component: .yAxis
            )
            return "vec2 mwxTexture\(slot)Coordinate(vec2 value) { return "
                + "\(first).xy + \(first).zw * value.x + \(second).xy * value.y; }"
        }
        let routes = activeSlots.map { slot in
            "#define MWX_TEXTURE_UV_g_Texture\(slot)(value) "
                + "mwxTexture\(slot)Coordinate(value)"
        }
        return functions + routes + [
            "#define MWX_TEXTURE_UV_INNER(textureName, value) MWX_TEXTURE_UV_##textureName(value)",
            "#define MWX_TEXTURE_UV(textureName, value) MWX_TEXTURE_UV_INNER(textureName, value)",
            "#define texSample2D(textureValue, value) texture(textureValue, MWX_TEXTURE_UV(textureValue, value))",
            "#define texture2D(textureValue, value) texture(textureValue, MWX_TEXTURE_UV(textureValue, value))",
            "#define texSample2DLod(textureValue, value, lodValue) textureLod(textureValue, MWX_TEXTURE_UV(textureValue, value), lodValue)",
            "#define texture2DLod(textureValue, value, lodValue) textureLod(textureValue, MWX_TEXTURE_UV(textureValue, value), lodValue)",
        ]
    }
}

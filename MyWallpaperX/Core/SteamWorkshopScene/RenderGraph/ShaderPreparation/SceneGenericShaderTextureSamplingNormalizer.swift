import Foundation

/// Normalizes the generic compiler's texture-sampling surface while keeping
/// every active sampler on the shared host texture-transform ABI.
nonisolated enum SceneGenericShaderTextureSamplingNormalizer {
    static func rewrite(_ source: String) -> String {
        let regex = try! NSRegularExpression(pattern:
            #"(\bfloat\s+[A-Za-z_]\w*\s*=\s*)(texSample2D\([^;]+\))(\s*;)"#
        )
        return regex.stringByReplacingMatches(
            in: source,
            range: NSRange(source.startIndex..., in: source),
            withTemplate: "$1$2.r$3"
        )
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

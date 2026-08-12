import Foundation

/// Proves the narrow sampled-component fact needed by single-channel graph
/// resources. It inspects the same active syntax units emitted to Metal and
/// never consults shader paths, effect identities, or source fingerprints.
nonisolated enum SceneAuthoredShaderTextureChannelAnalyzer {
    typealias ChannelUse = SceneAuthoredShaderProgram.TextureBinding.ChannelUse

    static func analyze(
        samplerName: String,
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> ChannelUse {
        let vertexUses = referenceIndices(samplerName, in: vertex)
        let fragmentUses = referenceIndices(samplerName, in: fragment)
        guard vertexUses.isEmpty,
              !fragmentUses.isEmpty,
              fragmentUses.allSatisfy({ isDirectRedSample($0, in: fragment) }) else {
            return .unproven
        }
        return .redOnly
    }

    private static func referenceIndices(
        _ name: String,
        in unit: SceneAuthoredShaderSyntaxUnit
    ) -> [Int] {
        let declarations = unit.declarations.filter { $0.name == name }.map(\.range)
        return unit.tokens.indices.filter { index in
            unit.tokens[index].text == name
                && !declarations.contains(where: { $0.contains(index) })
        }
    }

    /// Accepts only `texSample2D(g_TextureN, coordinates).r` and the equivalent
    /// `texture2D` spelling. Aliasing the vec4 result or observing any other
    /// swizzle remains deliberately unproven.
    private static func isDirectRedSample(
        _ samplerIndex: Int,
        in unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        let tokens = unit.tokens
        guard samplerIndex >= 2,
              tokens[samplerIndex - 1].text == "(",
              ["texSample2D", "texture2D"].contains(
                  tokens[samplerIndex - 2].text
              ),
              let close = matchingClose(
                  opening: samplerIndex - 1,
                  tokens: tokens
              ),
              close + 2 < tokens.count,
              tokens[close + 1].text == ".",
              tokens[close + 2].text == "r" else {
            return false
        }
        return true
    }

    private static func matchingClose(
        opening: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        guard tokens.indices.contains(opening), tokens[opening].text == "(" else {
            return nil
        }
        var depth = 0
        for index in opening..<tokens.count {
            switch tokens[index].text {
            case "(":
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
                if depth < 0 { return nil }
            default:
                break
            }
        }
        return nil
    }
}

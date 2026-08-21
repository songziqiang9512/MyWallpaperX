import Foundation

/// Proves the narrow sampled-component fact needed by preserved-channel graph
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
        guard vertexUses.isEmpty, !fragmentUses.isEmpty else {
            return .unproven
        }
        let uses = fragmentUses.compactMap { directSampleUse($0, in: fragment) }
        guard uses.count == fragmentUses.count,
              let first = uses.first,
              uses.allSatisfy({ $0 == first }) else { return .unproven }
        return first
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

    /// Accepts only an immediate `.r` or `.rg` projection of `texSample2D` and
    /// `texture2D`. Aliasing the vec4 result, mixing projections, or observing
    /// another swizzle remains deliberately unproven.
    private static func directSampleUse(
        _ samplerIndex: Int,
        in unit: SceneAuthoredShaderSyntaxUnit
    ) -> ChannelUse? {
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
              tokens[close + 1].text == "." else {
            return nil
        }
        switch tokens[close + 2].text {
        case "r": return .redOnly
        case "rg": return .redGreenOnly
        default: return nil
        }
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

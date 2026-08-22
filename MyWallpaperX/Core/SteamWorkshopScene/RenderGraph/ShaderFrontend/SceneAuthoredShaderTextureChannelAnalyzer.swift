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
        guard uses.count == fragmentUses.count else { return .unproven }
        if uses.contains(.wholeVector) { return .wholeVector }
        let mask = uses.reduce(0) { partial, use in
            partial | use.componentMask
        }
        switch mask {
        case 1: return .redOnly
        case 2: return .greenOnly
        case 3: return .redGreenOnly
        default: return .unproven
        }
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

    /// Accepts a direct complete-vector sample or an immediate `.r/.x`,
    /// `.g/.y`, or `.rg/.xy` projection of `texSample2D` and `texture2D`.
    /// The caller unions projected uses and preserves complete-vector use as a
    /// separate fact; target-format admission owns any unstored-component
    /// semantics. Permutations and other explicit swizzles remain unproven.
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
              ) else {
            return nil
        }
        guard close + 1 < tokens.count,
              tokens[close + 1].text == "." else {
            return .wholeVector
        }
        guard close + 2 < tokens.count else { return nil }
        switch tokens[close + 2].text {
        case "r", "x": return .redOnly
        case "g", "y": return .greenOnly
        case "rg", "xy": return .redGreenOnly
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

private extension SceneAuthoredShaderProgram.TextureBinding.ChannelUse {
    var componentMask: Int {
        switch self {
        case .redOnly: 1
        case .greenOnly: 2
        case .redGreenOnly: 3
        case .wholeVector, .unproven: 0
        }
    }
}

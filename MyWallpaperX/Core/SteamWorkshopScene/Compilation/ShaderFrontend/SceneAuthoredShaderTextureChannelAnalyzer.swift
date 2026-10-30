import Foundation

/// Proves the narrow sampled-component fact needed by preserved-channel graph
/// resources. It inspects the same active syntax units emitted to Metal and
/// never consults shader paths, effect identities, or source fingerprints.
nonisolated enum SceneAuthoredShaderTextureChannelAnalyzer {
    typealias ChannelUse = SceneAuthoredShaderProgram.TextureBinding.ChannelUse
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    /// Projects one active prepared variant without requiring the complete
    /// bounded frontend to emit Metal. Purpose admission may use this fact
    /// before a concrete texture is loaded, but an incomplete syntax parse
    /// remains unproven.
    static func analyze(
        samplerName: String,
        vertexSource: String,
        fragmentSource: String
    ) -> ChannelUse {
        let vertex = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: vertexSource,
                stage: .vertex
            ),
            stage: .vertex
        )
        let fragment = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: fragmentSource,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard vertex.diagnostics.isEmpty,
              fragment.diagnostics.isEmpty,
              let vertexUnit = vertex.unit,
              let fragmentUnit = fragment.unit else { return .unproven }
        return analyze(
            samplerName: samplerName,
            vertex: vertexUnit,
            fragment: fragmentUnit
        )
    }

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
        let functionNames = Set(fragment.functions.map(\.name))
        let uses = fragmentUses.compactMap {
            directSampleUse($0, in: fragment, functionNames: functionNames)
        }
        guard uses.count == fragmentUses.count else { return .unproven }
        if uses.contains(.wholeVector) { return .wholeVector }
        let mask = uses.reduce(0) { partial, use in
            partial | use.componentMask
        }
        switch mask {
        case 1: return .redOnly
        case 2: return .greenOnly
        case 3: return .redGreenOnly
        case 8: return .alphaOnly
        default: return .unproven
        }
    }

    /// Shared by the generic artifact builder; the bounded frontend already
    /// owns validated units and consumes the same `analyze` fact directly.
    static func provesAlphaOnlyInputs(
        _ slots: [Int], vertexSource: String, fragmentSource: String
    ) -> Bool {
        guard !slots.isEmpty else { return true }
        guard let syntax = SceneAuthoredShaderSyntaxAnalyzer.validatedStages(
            vertexSource: vertexSource, fragmentSource: fragmentSource
        ) else { return false }
        return slots.allSatisfy {
            analyze(samplerName: "g_Texture\($0)", vertex: syntax.vertex,
                    fragment: syntax.fragment) == .alphaOnly
        }
    }

    /// Proves that every active use of one sampler is a direct RGB lookup.
    ///
    /// This is deliberately narrower than `analyze`: a channel projection is
    /// useful for scalar/mask roles, while a straight-color source proof must
    /// reject every whole-vector, scalar, alpha, indirect, or helper-owned
    /// use.  The proof is tied to the active syntax units supplied by shader
    /// preparation and does not inspect paths, labels, or effect identities.
    static func provesStraightColorUse(
        samplerName: String,
        vertexSource: String,
        fragmentSource: String
    ) -> Bool {
        let vertex = syntax(vertexSource, stage: .vertex)
        let fragment = syntax(fragmentSource, stage: .fragment)
        guard let vertex, let fragment else { return false }
        return provesStraightColorUse(
            samplerName: samplerName,
            vertex: vertex,
            fragment: fragment
        )
    }

    /// Unit-level form used when preparation already owns parsed active
    /// syntax.  Every sampler token must be the sampler argument of a direct
    /// two-dimensional sample in `main`, immediately projected to `.rgb` or
    /// `.xyz`; any other token occurrence is an alias/escape and fails closed.
    static func provesStraightColorUse(
        samplerName: String,
        vertex: Unit,
        fragment: Unit
    ) -> Bool {
        guard fragment.declarations.contains(where: { declaration in
            declaration.storage == .uniform
                && declaration.name == samplerName
                && declaration.typeName == "sampler2D"
        }),
        let main = fragment.functions.first(where: { $0.name == "main" }) else {
            return false
        }

        let vertexUses = referenceIndices(samplerName, in: vertex)
        let fragmentUses = referenceIndices(samplerName, in: fragment)
        guard vertexUses.isEmpty, !fragmentUses.isEmpty else { return false }

        return fragmentUses.allSatisfy { index in
            main.bodyRange.contains(index)
                && directStraightColorSample(
                    samplerName: samplerName,
                    samplerIndex: index,
                    in: fragment
                )
        }
    }

    private static func syntax(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> Unit? {
        let result = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: stage),
            stage: stage
        )
        guard result.diagnostics.isEmpty else { return nil }
        return result.unit
    }

    static func referenceIndices(
        _ name: String,
        in unit: SceneAuthoredShaderSyntaxUnit
    ) -> [Int] {
        let declarations = unit.declarations.filter { $0.name == name }.map(\.range)
        return unit.tokens.indices.filter { index in
            unit.tokens[index].text == name
                && !declarations.contains(where: { $0.contains(index) })
        }
    }

    /// LOD changes the sampled level, not the component projection. Ordinary
    /// 2D red/green/vector uses keep their existing argument-range policy.
    private static func directSampleUse(
        _ samplerIndex: Int,
        in unit: SceneAuthoredShaderSyntaxUnit,
        functionNames: Set<String>
    ) -> ChannelUse? {
        let tokens = unit.tokens
        guard samplerIndex >= 2,
              tokens[samplerIndex - 1].text == "(",
              let expectedArgumentCount = SceneAuthoredShaderMetalEmitter
                  .textureSampleArgumentCount(
                      tokens[samplerIndex - 2].text,
                      functionNames: functionNames
                  ),
              let close = SceneAuthoredShaderTokenScanner.matchingParenthesis(
                  tokens: tokens,
                  opening: samplerIndex - 1
              ) else { return nil }
        let hasProjection = close + 1 < tokens.count
            && tokens[close + 1].text == "."
        guard !hasProjection || close + 2 < tokens.count else { return nil }
        let projection = hasProjection ? tokens[close + 2].text : nil
        let isAlpha = projection == "a" || projection == "w"
        if expectedArgumentCount == 3 || isAlpha {
            guard let arguments = SceneAuthoredShaderMetalEmitter
                      .textureSampleArguments(
                          tokens: tokens, opening: samplerIndex - 1, closing: close
                      ),
                  arguments.count == expectedArgumentCount,
                  arguments[0] == samplerIndex..<(samplerIndex + 1) else {
                return nil
            }
            if isAlpha, arguments.dropFirst().contains(where: { argument in
                argument.contains { tokens[$0].text == tokens[samplerIndex].text }
            }) { return nil }
        }
        switch projection {
        case nil: return .wholeVector
        case "r", "x": return .redOnly
        case "g", "y": return .greenOnly
        case "rg", "xy": return .redGreenOnly
        case "a", "w": return .alphaOnly
        default: return nil
        }
    }

    private static func directStraightColorSample(
        samplerName: String,
        samplerIndex: Int,
        in unit: Unit
    ) -> Bool {
        let tokens = unit.tokens
        guard samplerIndex >= 2,
              tokens[samplerIndex - 1].text == "(",
              ["texSample2D", "texture2D"].contains(
                  tokens[samplerIndex - 2].text
              ),
              let close = SceneAuthoredShaderTokenScanner.matchingParenthesis(
                  tokens: tokens,
                  opening: samplerIndex - 1
              ),
              let arguments = SceneAuthoredShaderMetalEmitter.textureSampleArguments(
                  tokens: tokens,
                  opening: samplerIndex - 1,
                  closing: close
              ),
              arguments.count == 2,
              arguments[0].count == 1,
              arguments[0].lowerBound == samplerIndex,
              tokens[samplerIndex].text == samplerName,
              !arguments[1].contains(where: {
                  tokens[$0].text == samplerName
              }),
              close + 2 < tokens.count,
              tokens[close + 1].text == ".",
              ["rgb", "xyz"].contains(tokens[close + 2].text) else {
            return false
        }

        // The projected value must be consumed as one vec3 lookup. A second
        // projection/index or immediate arithmetic (for example `.rgb.a`,
        // `.rgb[0]`, or `.rgb * 2`) would turn this into a component/data
        // transform and is therefore not a straight-color lookup proof.
        if close + 3 < tokens.count,
           ![";", ")", ","].contains(tokens[close + 3].text) {
            return false
        }
        return true
    }


}

private nonisolated extension SceneAuthoredShaderProgram.TextureBinding.ChannelUse {
    var componentMask: Int {
        switch self {
        case .redOnly: 1
        case .greenOnly: 2
        case .redGreenOnly: 3
        case .alphaOnly: 8
        case .wholeVector, .unproven: 0
        }
    }
}

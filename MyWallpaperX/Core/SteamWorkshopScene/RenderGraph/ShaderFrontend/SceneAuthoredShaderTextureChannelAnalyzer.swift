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
              let close = matchingClose(
                  opening: samplerIndex - 1,
                  tokens: tokens
              ),
              let arguments = argumentRanges(
                  in: (samplerIndex)..<close,
                  tokens: tokens
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

    private static func argumentRanges(
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        guard range.lowerBound <= range.upperBound,
              range.lowerBound >= 0,
              range.upperBound <= tokens.count else { return nil }
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            switch tokens[index].text {
            case "(", "[", "{":
                depth += 1
            case ")", "]", "}":
                depth -= 1
                if depth < 0 { return nil }
            case "," where depth == 0:
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            default:
                break
            }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
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

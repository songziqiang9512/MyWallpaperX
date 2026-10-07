import Foundation

/// Source-derived role for an otherwise untyped auxiliary texture. The fact
/// contains no effect, resource-path, or sample identity.
nonisolated struct SceneAuthoredShaderAuxiliaryTexturePurposeFact:
    Equatable, Sendable
{
    enum Role: Equatable, Sendable {
        case phase
        case normal
        case dataChannels
    }

    let slot: Int
    let role: Role
}

/// Proves two bounded channel-preserving auxiliary dataflows used by authored
/// shaders: a scalar phase selector and a decoded two-sample normal field.
nonisolated enum SceneAuthoredShaderAuxiliaryTexturePurposeAnalyzer {
    typealias Fact = SceneAuthoredShaderAuxiliaryTexturePurposeFact
    private typealias Token = SceneAuthoredShaderToken
    private typealias Unit = SceneAuthoredShaderSyntaxUnit

    static func analyze(
        vertexSource: String,
        fragmentSource: String
    ) -> [Fact] {
        let vertex = syntax(vertexSource, stage: .vertex)
        let fragment = syntax(fragmentSource, stage: .fragment)
        guard let vertex, let fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              let ranges = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens)
        else { return [] }

        let statements = ranges.map { Array(fragment.tokens[$0]) }
        let candidates = phaseFacts(
            statements: statements,
            main: main,
            vertex: vertex,
            fragment: fragment
        ) + normalFacts(
            statements: statements,
            main: main,
            vertex: vertex,
            fragment: fragment
        ) + dataChannelFacts(
            statements: statements,
            main: main,
            vertex: vertex,
            fragment: fragment
        )
        var roles: [Int: Fact.Role] = [:]
        for candidate in candidates {
            if let existing = roles[candidate.slot], existing != candidate.role {
                return []
            }
            roles[candidate.slot] = candidate.role
        }
        return roles.keys.sorted().compactMap { slot in
            roles[slot].map { Fact(slot: slot, role: $0) }
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

    private struct Sample {
        let slot: Int
        let sampler: String
        let projection: String
        let upperBound: Int
    }

    private struct PhaseDeclaration {
        let name: String
        let sample: Sample
    }

    private static func phaseFacts(
        statements: [[Token]],
        main: Unit.Function,
        vertex: Unit,
        fragment: Unit
    ) -> [Fact] {
        statements.compactMap { tokens -> Fact? in
            guard let declaration = phaseDeclaration(tokens),
                  referenceCount(declaration.sample.sampler, in: vertex) == 0,
                  referenceCount(declaration.sample.sampler, in: fragment) == 1,
                  identifierCount(
                    declaration.name,
                    in: main.bodyRange,
                    tokens: fragment.tokens
                  ) == 2,
                  smoothstepConsumesOnly(
                    declaration.name,
                    in: main.bodyRange,
                    tokens: fragment.tokens
                  ) else { return nil }
            return Fact(slot: declaration.sample.slot, role: .phase)
        }
    }

    private static func phaseDeclaration(
        _ tokens: [Token]
    ) -> PhaseDeclaration? {
        guard tokens.count >= 9,
              tokens[0].text == "float",
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let sample = sample(at: 3, tokens: tokens),
              sample.upperBound == tokens.count,
              ["r", "x"].contains(sample.projection) else { return nil }
        return .init(name: tokens[1].text, sample: sample)
    }

    private static func smoothstepConsumesOnly(
        _ name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        var matches = 0
        for index in range where tokens[index].text == "smoothstep" {
            guard index + 1 < range.upperBound,
                  tokens[index + 1].text == "(",
                  let close = matchingClose(index + 1, tokens: tokens),
                  close < range.upperBound,
                  let arguments = SceneAuthoredShaderTokenScanner.argumentRanges(
                    in: (index + 2)..<close,
                    tokens: tokens
                  ), arguments.count == 3,
                  numericScalar(Array(tokens[arguments[0]])),
                  numericScalar(Array(tokens[arguments[1]])),
                  Array(tokens[arguments[2]]).map(\.text) == [name]
            else { continue }
            matches += 1
        }
        return matches == 1
    }

    private struct NormalDeclaration {
        let name: String
        let sample: Sample
    }

    private static func normalFacts(
        statements: [[Token]],
        main: Unit.Function,
        vertex: Unit,
        fragment: Unit
    ) -> [Fact] {
        let declarations = statements.compactMap(normalDeclaration)
        let groups = Dictionary(grouping: declarations, by: { $0.sample.slot })
        return groups.compactMap { slot, group -> Fact? in
            guard group.count == 2,
                  group[0].name != group[1].name,
                  group.allSatisfy({ $0.sample.sampler == "g_Texture\(slot)" }),
                  referenceCount("g_Texture\(slot)", in: vertex) == 0,
                  referenceCount("g_Texture\(slot)", in: fragment) == 2,
                  let combine = normalCombine(
                    statements,
                    first: group[0].name,
                    second: group[1].name
                  ),
                  sampleVariableUseIsClosed(
                    group[0].name,
                    zOwner: combine.zOwner,
                    main: main,
                    tokens: fragment.tokens
                  ),
                  sampleVariableUseIsClosed(
                    group[1].name,
                    zOwner: combine.zOwner,
                    main: main,
                    tokens: fragment.tokens
                  ),
                  normalUseIsClosed(
                    combine.output,
                    main: main,
                    tokens: fragment.tokens
                  ) else { return nil }
            return Fact(slot: slot, role: .normal)
        }
    }

    private static func normalDeclaration(
        _ tokens: [Token]
    ) -> NormalDeclaration? {
        guard tokens.count >= 13,
              ["vec3", "float3"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let sampled = sample(at: 3, tokens: tokens),
              ["xyz", "rgb"].contains(sampled.projection),
              sampled.upperBound + 4 == tokens.count,
              tokens[sampled.upperBound].text == "*",
              number(tokens[sampled.upperBound + 1], equals: 2),
              tokens[sampled.upperBound + 2].text == "-",
              number(tokens[sampled.upperBound + 3], equals: 1) else {
            return nil
        }
        return .init(name: tokens[1].text, sample: sampled)
    }

    private static func normalCombine(
        _ statements: [[Token]],
        first: String,
        second: String
    ) -> (output: String, zOwner: String)? {
        let matches = statements.compactMap { tokens -> (String, String)? in
            guard tokens.count == 20,
                  ["vec3", "float3"].contains(tokens[0].text),
                  tokens[1].kind == .identifier,
                  Array(tokens[2...6]).map(\.text)
                    == ["=", "normalize", "(", tokens[0].text, "("],
                  tokens[7].text == first,
                  Array(tokens[8...10]).map(\.text) == [".", "xy", "+"],
                  tokens[11].text == second,
                  Array(tokens[12...14]).map(\.text) == [".", "xy", ","],
                  [first, second].contains(tokens[15].text),
                  Array(tokens[16...19]).map(\.text)
                    == [".", "z", ")", ")"] else { return nil }
            return (tokens[1].text, tokens[15].text)
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func sampleVariableUseIsClosed(
        _ name: String,
        zOwner: String,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        identifierCount(name, in: main.bodyRange, tokens: tokens)
            == (name == zOwner ? 3 : 2)
    }

    private static func normalUseIsClosed(
        _ name: String,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let uses = main.bodyRange.filter { tokens[$0].text == name }
        guard uses.count >= 2 else { return false }
        return uses.dropFirst().allSatisfy { index in
            index + 2 < main.bodyRange.upperBound
                && tokens[index + 1].text == "."
                && ["xy", "rg"].contains(tokens[index + 2].text)
        }
    }

    private static func sample(at start: Int, tokens: [Token]) -> Sample? {
        guard start + 5 < tokens.count,
              ["texSample2D", "texture2D"].contains(tokens[start].text),
              tokens[start + 1].text == "(",
              let close = matchingClose(start + 1, tokens: tokens),
              let arguments = SceneAuthoredShaderTokenScanner.argumentRanges(
                in: (start + 2)..<close,
                tokens: tokens
              ), arguments.count == 2,
              arguments[0].count == 1,
              let slot = SceneShaderSourceTextFacts.textureSlot(tokens[arguments[0].lowerBound].text),
              close + 2 < tokens.count,
              tokens[close + 1].text == "." else { return nil }
        return .init(
            slot: slot,
            sampler: tokens[arguments[0].lowerBound].text,
            projection: tokens[close + 2].text,
            upperBound: close + 3
        )
    }

    private static func referenceCount(_ name: String, in unit: Unit) -> Int {
        let declarations = unit.declarations.filter { $0.name == name }.map(\.range)
        return unit.tokens.indices.filter { index in
            unit.tokens[index].text == name
                && !declarations.contains(where: { $0.contains(index) })
        }.count
    }

    // MARK: Data-channel weight facts (`texSample2D(s, uv).ra` -> mix weight)

    /// Proves a channel-subset sample is data, not color: the sampled variable
    /// is only read per-component, feeds scalar arithmetic and the scalar
    /// call whitelist, and at least one chain terminates in a `mix`
    /// weight position (`mix(a, b, t)` with t derived from the sample).
    /// Producer: workshop 3718261802's juguangdeng samples the spotlight
    /// shape `.ra` and multiplies the channels into the blend factor.
    private static func dataChannelFacts(
        statements: [[Token]],
        main: Unit.Function,
        vertex: Unit,
        fragment: Unit
    ) -> [Fact] {
        let declaredTypes = Dictionary(fragment.declarations.map {
            ($0.name, $0.typeName)
        }, uniquingKeysWith: { first, _ in first })
        var claimedSlots = Set<Int>()
        var facts: [Fact] = []
        for tokens in statements {
            guard let declaration = dataChannelDeclaration(tokens)
            else { continue }
            let name = declaration.name
            guard referenceCount(declaration.sample.sampler, in: vertex) == 0,
                  referenceCount(declaration.sample.sampler, in: fragment) == 1,
                  usesAreClosedComponentReads(
                    name,
                    main: main,
                    fragment: fragment
                  ),
                  let _ = dataChannelWeightClosure(
                    name,
                    statements: statements,
                    declaredTypes: declaredTypes
                  ) else { continue }
            // Two independent channel-data samples of one slot would make the
            // proven purpose ambiguous; stay fail-closed.
            guard claimedSlots.insert(declaration.sample.slot).inserted
            else { return [] }
            facts.append(Fact(slot: declaration.sample.slot, role: .dataChannels))
        }
        return facts
    }

    private static func dataChannelDeclaration(
        _ tokens: [Token]
    ) -> (name: String, sample: Sample)? {
        guard tokens.count >= 9,
              let width = vectorWidth(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let sample = sample(at: 3, tokens: tokens),
              // The projection tail `.` + swizzle is already included in
              // the sample's exclusive upper bound.
              sample.upperBound == tokens.count,
              tokens[sample.upperBound - 2].text == ".",
              let _ = dataChannelProjection(
                tokens[sample.upperBound - 1].text,
                expectedWidth: width
              ) else { return nil }
        return (tokens[1].text, sample)
    }

    private static func vectorWidth(_ typeName: String) -> Int? {
        switch typeName {
        case "float": return 1
        case "vec2", "float2": return 2
        case "vec3", "float3": return 3
        case "vec4", "float4": return 4
        default: return nil
        }
    }

    /// Accepts homogeneous rgba/xyzw projections that select a strict subset
    /// of the sampled channels; a whole-vector projection carries color
    /// semantics and stays unproven.
    private static func dataChannelProjection(
        _ text: String,
        expectedWidth: Int
    ) -> String? {
        let rgba = "rgba", xyzw = "xyzw"
        guard !text.isEmpty, text.count < 4,
              text.allSatisfy({ rgba.contains($0) })
                  || text.allSatisfy({ xyzw.contains($0) }) else { return nil }
        return text.count == expectedWidth ? text : nil
    }

    /// Every use of the sampled variable outside its declaration must be a
    /// single-component read; a bare identifier use is a vector context.
    private static func usesAreClosedComponentReads(
        _ name: String,
        main: Unit.Function,
        fragment: Unit
    ) -> Bool {
        let uses = main.bodyRange.filter { index in
            fragment.tokens[index].text == name
        }
        guard !uses.isEmpty else { return false }
        return uses.allSatisfy { index in
            // The declaration is the one use followed by `=`; every other
            // use must read a single component.
            fragment.tokens[index + 1].text == "="
                || (index + 2 < main.bodyRange.upperBound
                    && fragment.tokens[index + 1].text == "."
                    && isComponentLetter(fragment.tokens[index + 2].text))
        }
    }

    private static func isComponentLetter(_ text: String) -> Bool {
        text.count == 1 && "xyzwrgba".contains(text)
    }

    /// Walks main's statements and returns the set of float locals transitively
    /// derived from the sampled variable when every use stays inside the
    /// scalar weight vocabulary; nil means any use escaped the shape.
    private static func dataChannelWeightClosure(
        _ name: String,
        statements: [[Token]],
        declaredTypes: [String: String]
    ) -> Set<String>? {
        var derived = Set<String>()
        func touches(_ tokens: [Token]) -> Bool {
            tokens.contains { $0.text == name || derived.contains($0.text) }
        }
        // Fixpoint: float locals whose initializer expression touches the
        // sample or an existing derived local join the weight closure.
        var changed = true
        while changed {
            changed = false
            for tokens in statements where !tokens.isEmpty {
                // Statement ranges exclude the trailing `;`, so the whole
                // suffix after `=` is the initializer expression.
                guard tokens[0].text == "float", tokens[1].kind == .identifier,
                      tokens[2].text == "=", tokens.count > 4 else { continue }
                let local = tokens[1].text
                guard !derived.contains(local),
                      touches(Array(tokens[3...])) else { continue }
                guard isScalarWeightExpression(
                    Array(tokens[3...]),
                    channelRoots: [name] + derived,
                    declaredTypes: declaredTypes
                ) else { return nil }
                derived.insert(local)
                changed = true
            }
        }
        var weightUseCount = 0
        for tokens in statements where !tokens.isEmpty {
            guard touches(tokens) else { continue }
            if tokens.count > 4, tokens[2].text == "=",
               tokens[1].kind == .identifier,
               // Scalar declarations joined the closure above; the channel
               // declaration itself carries the only vector occurrence.
               tokens[1].text == name || tokens[0].text == "float" {
                continue
            }
            var index = 0
            while index < tokens.count {
                let token = tokens[index]
                guard token.kind == .identifier, index + 1 < tokens.count,
                      tokens[index + 1].text == "(",
                      let close = matchingClose(index + 1, tokens: tokens) else {
                    if token.text == name || derived.contains(token.text) {
                        // Bare occurrence outside the whitelisted call shapes
                        // has no proven scalar position.
                        return nil
                    }
                    index += 1
                    continue
                }
                let arguments = SceneAuthoredShaderTokenScanner.argumentRanges(
                    in: (index + 2)..<close, tokens: tokens
                )
                guard let arguments else { return nil }
                if token.text == "mix" {
                    guard arguments.count == 3 else { return nil }
                    if touches(Array(tokens[arguments[0]]))
                        || touches(Array(tokens[arguments[1]])) {
                        // The sampled channels may only weight the blend, not
                        // feed either mixed color operand.
                        return nil
                    }
                    if touches(Array(tokens[arguments[2]])) {
                        weightUseCount += 1
                    }
                } else if weightCallAllowlist.contains(token.text) {
                    if arguments.contains(where: { touches(Array(tokens[$0])) }) {
                        weightUseCount += 1
                    }
                } else {
                    return nil
                }
                index = close + 1
            }
        }
        guard weightUseCount > 0 else { return nil }
        return derived
    }

    private static let weightCallAllowlist: Set<String> = [
        "saturate", "abs", "min", "max", "clamp", "smoothstep",
        "floor", "ceil", "fract", "mod",
    ]

    private static func isScalarWeightExpression(
        _ tokens: [Token],
        channelRoots: [String],
        declaredTypes: [String: String]
    ) -> Bool {
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .number
                || ["+", "-", "*", "/", "(", ")", ","].contains(token.text) {
                index += 1
                continue
            }
            guard token.kind == .identifier else { return false }
            if index + 2 < tokens.count,
               tokens[index + 1].text == ".",
               isComponentLetter(tokens[index + 2].text) {
                index += 3
                continue
            }
            if channelRoots.contains(token.text)
                || declaredTypes[token.text] == "float"
                || declaredTypes[token.text] == "int" {
                index += 1
                continue
            }
            if weightCallAllowlist.contains(token.text),
               index + 1 < tokens.count, tokens[index + 1].text == "(",
               let close = matchingClose(index + 1, tokens: tokens) {
                index = close + 1
                continue
            }
            return false
        }
        return true
    }

    private static func identifierCount(
        _ name: String,
        in range: Range<Int>,
        tokens: [Token]
    ) -> Int {
        range.filter { tokens[$0].text == name }.count
    }

    private static func numericScalar(_ tokens: [Token]) -> Bool {
        tokens.count == 1 && Double(tokens[0].text) != nil
    }

    private static func number(_ token: Token, equals expected: Double) -> Bool {
        Double(token.text) == expected
    }

    private static func matchingClose(
        _ opening: Int,
        tokens: [Token]
    ) -> Int? {
        guard tokens.indices.contains(opening), tokens[opening].text == "(" else {
            return nil
        }
        var depth = 0
        for index in opening..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
                if depth < 0 { return nil }
            }
        }
        return nil
    }

}

import Foundation

/// Source-derived role for an otherwise untyped auxiliary texture. The fact
/// contains no effect, resource-path, or sample identity.
nonisolated struct SceneAuthoredShaderAuxiliaryTexturePurposeFact:
    Equatable, Sendable
{
    enum Role: Equatable, Sendable {
        case phase
        case normal
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
                  let arguments = argumentRanges(
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
              let arguments = argumentRanges(
                in: (start + 2)..<close,
                tokens: tokens
              ), arguments.count == 2,
              arguments[0].count == 1,
              let slot = textureSlot(tokens[arguments[0].lowerBound].text),
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

    private static func argumentRanges(
        in range: Range<Int>,
        tokens: [Token]
    ) -> [Range<Int>]? {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            switch tokens[index].text {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth < 0 { return nil }
            case "," where depth == 0:
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            default: break
            }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
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

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0..<8).contains(slot) else { return nil }
        return slot
    }
}

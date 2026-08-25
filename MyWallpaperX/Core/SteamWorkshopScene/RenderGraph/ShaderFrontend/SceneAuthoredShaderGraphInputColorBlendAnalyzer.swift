import Foundation

/// Source-derived proof for one bounded full-frame color blend. The proof is
/// intentionally independent of effect, material, shader, path, and sample
/// identity: one sampled color is blended with one uniform RGB value, using a
/// finite scalar weight and at most one auxiliary red-channel sample. The
/// sampled color is then published unchanged apart from the proven RGB blend
/// and an optional opaque-alpha assignment for blend mode zero.
nonisolated struct SceneAuthoredShaderGraphInputColorBlendFact: Equatable, Sendable {
    enum AlphaOutput: Equatable, Sendable {
        case preserved
        case opaque
    }

    let sourceSlot: Int
    let auxiliaryRedSlots: Set<Int>
    let alphaOutput: AlphaOutput
}

nonisolated enum SceneAuthoredShaderGraphInputColorBlendAnalyzer {
    typealias Fact = SceneAuthoredShaderGraphInputColorBlendFact
    private typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    static func analyze(fragmentSource source: String) -> Fact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyze(fragment)
    }

    static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens),
              (4 ... 6).contains(statements.count),
              let source = sourceDeclaration(
                Array(fragment.tokens[statements[0]]),
                fragment: fragment
              ), let weight = weightDeclaration(
                Array(fragment.tokens[statements[1]]),
                fragment: fragment,
                sourceSlot: source.slot
              ) else {
            return nil
        }

        var position = 2
        var auxiliarySlots = weight.auxiliarySlots
        if position < statements.count,
           let mutation = weightMutation(
            Array(fragment.tokens[statements[position]]),
            name: weight.name,
            fragment: fragment,
            sourceSlot: source.slot
           ) {
            auxiliarySlots.formUnion(mutation.auxiliarySlots)
            position += 1
        }
        guard auxiliarySlots.count <= 1,
              position < statements.count,
              let blendMode = colorBlend(
                Array(fragment.tokens[statements[position]]),
                sourceName: source.name,
                weightName: weight.name,
                fragment: fragment
              ) else {
            return nil
        }
        position += 1

        let alphaOutput: Fact.AlphaOutput
        if position < statements.count,
           opaqueAlphaWrite(
            Array(fragment.tokens[statements[position]]),
            sourceName: source.name
           ) {
            guard blendMode == 0 else { return nil }
            alphaOutput = .opaque
            position += 1
        } else {
            guard blendMode != 0 else { return nil }
            alphaOutput = .preserved
        }
        guard position == statements.count - 1,
              output(
                Array(fragment.tokens[statements[position]]),
                sourceName: source.name
              ), sampleSlots(in: main.bodyRange, tokens: fragment.tokens)
                == [source.slot] + auxiliarySlots.sorted() else {
            return nil
        }
        return .init(
            sourceSlot: source.slot,
            auxiliaryRedSlots: auxiliarySlots,
            alphaOutput: alphaOutput
        )
    }

    private static func sourceDeclaration(
        _ tokens: [Token],
        fragment: Unit
    ) -> (name: String, slot: Int)? {
        guard tokens.count >= 6,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(tokens[3...]),
              samplerType(slot, fragment: fragment) == "sampler2D" else {
            return nil
        }
        return (tokens[1].text, slot)
    }

    private struct Weight {
        let name: String
        let auxiliarySlots: Set<Int>
    }

    private static func weightDeclaration(
        _ tokens: [Token],
        fragment: Unit,
        sourceSlot: Int
    ) -> Weight? {
        guard tokens.count >= 4,
              tokens[0].text == "float",
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let slots = scalarExpression(
                Array(tokens.dropFirst(3)),
                fragment: fragment,
                sourceSlot: sourceSlot
              ) else {
            return nil
        }
        return .init(name: tokens[1].text, auxiliarySlots: slots)
    }

    private static func weightMutation(
        _ tokens: [Token],
        name: String,
        fragment: Unit,
        sourceSlot: Int
    ) -> Weight? {
        guard tokens.count >= 3,
              tokens[0].text == name,
              ["=", "*="].contains(tokens[1].text),
              let slots = scalarExpression(
                Array(tokens.dropFirst(2)),
                fragment: fragment,
                sourceSlot: sourceSlot
              ) else {
            return nil
        }
        return .init(name: name, auxiliarySlots: slots)
    }

    private static func scalarExpression(
        _ tokens: [Token],
        fragment: Unit,
        sourceSlot: Int
    ) -> Set<Int>? {
        let expression = strippingParentheses(tokens)
        guard !expression.isEmpty else { return nil }
        if expression.count == 1 {
            let token = expression[0]
            if token.kind == .number {
                let raw = token.text.trimmingCharacters(
                    in: CharacterSet(charactersIn: "fFuU")
                )
                return Double(raw).map(\.isFinite) == true ? [] : nil
            }
            return uniformType(token.text, fragment: fragment) == "float" ? [] : nil
        }
        if let slot = redSampleSlot(expression),
           slot != sourceSlot,
           samplerType(slot, fragment: fragment) == "sampler2D" {
            return [slot]
        }
        guard let operatorIndex = soleTopLevelOperator("*", in: expression),
              let left = scalarExpression(
                Array(expression[..<operatorIndex]),
                fragment: fragment,
                sourceSlot: sourceSlot
              ), let right = scalarExpression(
                Array(expression[(operatorIndex + 1)...]),
                fragment: fragment,
                sourceSlot: sourceSlot
              ) else {
            return nil
        }
        return left.union(right)
    }

    private static func colorBlend(
        _ tokens: [Token],
        sourceName: String,
        weightName: String,
        fragment: Unit
    ) -> Int? {
        guard tokens.count >= 16,
              Array(tokens.prefix(4)).map(\.text)
                == [sourceName, ".", "rgb", "="],
              tokens[4].text == "ApplyBlending",
              tokens[5].text == "(",
              tokens.last?.text == ")",
              let arguments = arguments(
                in: 6..<(tokens.count - 1),
                tokens: tokens
              ), arguments.count == 4,
              arguments[0].count == 1,
              let rawMode = Int(tokens[arguments[0].lowerBound].text),
              (0 ... maximumBlendMode).contains(rawMode),
              Array(tokens[arguments[1]]).map(\.text)
                == [sourceName, ".", "rgb"],
              arguments[2].count == 1,
              uniformType(tokens[arguments[2].lowerBound].text, fragment: fragment)
                .map({ ["vec3", "float3"].contains($0) }) == true,
              arguments[3].count == 1,
              tokens[arguments[3].lowerBound].text == weightName else {
            return nil
        }
        return rawMode
    }

    private static func opaqueAlphaWrite(
        _ tokens: [Token],
        sourceName: String
    ) -> Bool {
        guard tokens.count == 5,
              Array(tokens.prefix(4)).map(\.text)
                == [sourceName, ".", "a", "="],
              let value = Double(tokens[4].text) else { return false }
        return value == 1
    }

    private static func output(_ tokens: [Token], sourceName: String) -> Bool {
        tokens.count == 3
            && tokens[0].text == "gl_FragColor"
            && tokens[1].text == "="
            && tokens[2].text == sourceName
    }

    private static func sampleSlots(in range: Range<Int>, tokens: [Token]) -> [Int]? {
        var result: [Int] = []
        for index in range where ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 2 < range.upperBound,
                  tokens[index + 1].text == "(",
                  let slot = textureSlot(tokens[index + 2].text) else {
                return nil
            }
            result.append(slot)
        }
        return result
    }

    private static func redSampleSlot(_ tokens: [Token]) -> Int? {
        guard tokens.count >= 8,
              ["texSample2D", "texture2D"].contains(tokens[0].text),
              tokens[1].text == "(",
              let close = matchingClose(1, tokens: tokens),
              close + 2 == tokens.count - 1,
              tokens[close + 1].text == ".",
              ["r", "x"].contains(tokens[close + 2].text),
              let ranges = arguments(in: 2..<close, tokens: tokens),
              ranges.count == 2,
              ranges[0].count == 1 else { return nil }
        return textureSlot(tokens[ranges[0].lowerBound].text)
    }

    private static func samplerType(_ slot: Int, fragment: Unit) -> String? {
        uniformType("g_Texture\(slot)", fragment: fragment)
    }

    private static func uniformType(_ name: String, fragment: Unit) -> String? {
        let matches = fragment.declarations.filter {
            $0.storage == .uniform && $0.arraySize == nil && $0.name == name
        }
        return matches.count == 1 ? matches[0].typeName : nil
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ... 7).contains(slot) else { return nil }
        return slot
    }

    private static func strippingParentheses(_ tokens: [Token]) -> [Token] {
        var result = tokens
        while result.count >= 2,
              result.first?.text == "(",
              matchingClose(0, tokens: result) == result.count - 1 {
            result.removeFirst()
            result.removeLast()
        }
        return result
    }

    private static func soleTopLevelOperator(
        _ value: String,
        in tokens: [Token]
    ) -> Int? {
        var matches: [Int] = []
        var depth = 0
        for index in tokens.indices {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            if depth == 0, tokens[index].text == value { matches.append(index) }
        }
        return depth == 0 && matches.count == 1 ? matches[0] : nil
    }

    private static func matchingClose(_ open: Int, tokens: [Token]) -> Int? {
        guard tokens.indices.contains(open), tokens[open].text == "(" else {
            return nil
        }
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    private static func arguments(
        in range: Range<Int>,
        tokens: [Token]
    ) -> [Range<Int>]? {
        guard !range.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == ",", depth == 0 {
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    /// Authored `imageblending` combo contract currently exposes modes 0...32.
    private static let maximumBlendMode = 32
}

/// Source-derived proof for a full-frame graph color whose RGB is blended
/// with one straight-color sample through a spatial scalar weight. A second
/// sampled texture may contribute preserved red/alpha weight data and one
/// optional scalar mask may further attenuate the weight. The proof is based
/// only on active shader dataflow; effect, path, asset, and sample identities
/// are deliberately absent.
nonisolated struct SceneAuthoredShaderSpatialWeightedColorBlendFact:
    Equatable, Sendable
{
    let sourceSlot: Int
    let straightColorSlot: Int
    let preservedRedAlphaSlot: Int
    let optionalMaskSlot: Int?

    var activeSlots: Set<Int> {
        Set([sourceSlot, straightColorSlot, preservedRedAlphaSlot])
            .union(optionalMaskSlot.map { [$0] } ?? [])
    }
}

/// Proves the bounded dataflow used by spatially weighted authored color
/// replacement. Variable and varying names are discovered from declarations;
/// the admission does not key on source identity or resource paths.
nonisolated enum SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer {
    typealias Fact = SceneAuthoredShaderSpatialWeightedColorBlendFact
    private typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    static func analyze(
        fragmentSource source: String,
        normalBlendModeIdentifiers: Set<String> = []
    ) -> Fact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyze(
            fragment,
            normalBlendModeIdentifiers: normalBlendModeIdentifiers
        )
    }

    static func analyze(
        _ fragment: Unit,
        normalBlendModeIdentifiers: Set<String> = []
    ) -> Fact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              let statementRanges = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens),
              (8 ... 24).contains(statementRanges.count) else {
            return nil
        }
        let statements = statementRanges.map { Array(fragment.tokens[$0]) }
        guard let source = completeSampleDeclaration(statements[0]),
              let color = completeSampleDeclaration(statements[1]),
              source.slot != color.slot,
              let weight = weightDeclaration(
                statements[2],
                colorName: color.name,
                fragment: fragment
              ) else {
            return nil
        }

        let outputStatements = statements.filter {
            wholeOutput($0, sourceName: source.name)
        }
        guard outputStatements.count == 1,
              wholeOutput(statements.last ?? [], sourceName: source.name),
              let preserved = preservedWeightDeclaration(in: statements),
              ![source.slot, color.slot].contains(preserved.slot),
              statements.contains(where: {
                  preservedWeightMutation(
                    $0,
                    weightName: weight,
                    preservedName: preserved.name
                  )
              }), statements.contains(where: {
                  blendWrite(
                    $0,
                    sourceName: source.name,
                    colorName: color.name,
                    weightName: weight,
                    normalBlendModeIdentifiers: normalBlendModeIdentifiers
                  )
              }), sourceWrites(in: statements, sourceName: source.name) == 2,
              sourceReferenceStatementCount(
                in: statements,
                sourceName: source.name
              ) == 3
        else { return nil }

        let masks = statements.compactMap {
            scalarMaskMutation($0, weightName: weight)
        }
        guard masks.count <= 1 else { return nil }
        let maskSlot = masks.first
        guard maskSlot.map({
            ![source.slot, color.slot, preserved.slot].contains($0)
        }) ?? true else { return nil }

        let expectedSamples: [SampleUse] = [
            .init(slot: source.slot, projection: nil),
            .init(slot: color.slot, projection: nil),
        ] + (maskSlot.map { [.init(slot: $0, projection: "r")] } ?? []) + [
            .init(slot: preserved.slot, projection: "ra"),
        ]
        guard sampleUses(in: main.bodyRange, tokens: fragment.tokens)
                == expectedSamples else { return nil }

        return .init(
            sourceSlot: source.slot,
            straightColorSlot: color.slot,
            preservedRedAlphaSlot: preserved.slot,
            optionalMaskSlot: maskSlot
        )
    }

    private struct SampleUse: Equatable {
        let slot: Int
        let projection: String?
    }

    private static func completeSampleDeclaration(
        _ tokens: [Token]
    ) -> (name: String, slot: Int)? {
        guard tokens.count >= 8,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let sample = sampleUse(Array(tokens.dropFirst(3))),
              sample.projection == nil else { return nil }
        return (tokens[1].text, sample.slot)
    }

    private static func weightDeclaration(
        _ tokens: [Token],
        colorName: String,
        fragment: Unit
    ) -> String? {
        guard tokens.count == 8,
              tokens[0].text == "float",
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              tokens[3].text == colorName,
              tokens[4].text == ".",
              ["a", "w"].contains(tokens[5].text),
              tokens[6].text == "*",
              fragment.declarations.contains(where: {
                  $0.storage == .uniform
                      && $0.name == tokens[7].text
                      && $0.typeName == "float"
              }) else { return nil }
        return tokens[1].text
    }

    private static func preservedWeightDeclaration(
        in statements: [[Token]]
    ) -> (name: String, slot: Int)? {
        let matches = statements.compactMap { tokens -> (String, Int)? in
            guard tokens.count >= 10,
                  ["vec2", "float2"].contains(tokens[0].text),
                  tokens[1].kind == .identifier,
                  tokens[2].text == "=",
                  let sample = sampleUse(Array(tokens.dropFirst(3))),
                  ["ra", "xw"].contains(sample.projection ?? "") else {
                return nil
            }
            return (tokens[1].text, sample.slot)
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func preservedWeightMutation(
        _ tokens: [Token],
        weightName: String,
        preservedName: String
    ) -> Bool {
        guard tokens.count == 9,
              tokens[0].text == weightName,
              tokens[1].text == "*=",
              tokens[2].text == preservedName,
              tokens[3].text == ".",
              ["x", "r"].contains(tokens[4].text),
              tokens[5].text == "*",
              tokens[6].text == preservedName,
              tokens[7].text == ".",
              ["y", "g"].contains(tokens[8].text) else { return false }
        return true
    }

    private static func scalarMaskMutation(
        _ tokens: [Token],
        weightName: String
    ) -> Int? {
        guard tokens.count >= 10,
              tokens[0].text == weightName,
              tokens[1].text == "*=",
              let sample = sampleUse(Array(tokens.dropFirst(2))),
              ["r", "x"].contains(sample.projection ?? "") else { return nil }
        return sample.slot
    }

    private static func blendWrite(
        _ tokens: [Token],
        sourceName: String,
        colorName: String,
        weightName: String,
        normalBlendModeIdentifiers: Set<String>
    ) -> Bool {
        guard tokens.count >= 18,
              Array(tokens.prefix(4)).map(\.text)
                == [sourceName, ".", "rgb", "="],
              tokens[4].text == "ApplyBlending",
              tokens[5].text == "(",
              let close = matchingClose(5, tokens: tokens),
              close == tokens.count - 1,
              let arguments = argumentRanges(in: 6..<close, tokens: tokens),
              arguments.count == 4 else { return false }
        let mode = Array(tokens[arguments[0]])
        guard mode.count == 1,
              mode[0].text == "0"
                || (mode[0].kind == .identifier
                    && normalBlendModeIdentifiers.contains(mode[0].text)) else {
            return false
        }
        return true
            && Array(tokens[arguments[1]]).map(\.text)
                == [sourceName, ".", "rgb"]
            && Array(tokens[arguments[2]]).map(\.text)
                == [colorName, ".", "rgb"]
            && Array(tokens[arguments[3]]).map(\.text) == [weightName]
    }

    private static func wholeOutput(
        _ tokens: [Token],
        sourceName: String
    ) -> Bool {
        tokens.map(\.text) == ["gl_FragColor", "=", sourceName]
    }

    private static func sourceWrites(
        in statements: [[Token]],
        sourceName: String
    ) -> Int {
        statements.filter { tokens in
            guard let first = tokens.first?.text else { return false }
            if first == sourceName {
                return tokens.dropFirst().contains(where: { $0.text == "=" })
            }
            return tokens.count > 2
                && ["vec4", "float4"].contains(first)
                && tokens[1].text == sourceName
                && tokens[2].text == "="
        }.count
    }

    private static func sourceReferenceStatementCount(
        in statements: [[Token]],
        sourceName: String
    ) -> Int {
        statements.filter { tokens in
            tokens.contains(where: {
                $0.kind == .identifier && $0.text == sourceName
            })
        }.count
    }

    private static func sampleUses(
        in range: Range<Int>,
        tokens: [Token]
    ) -> [SampleUse]? {
        var result: [SampleUse] = []
        var index = range.lowerBound
        while index < range.upperBound {
            guard ["texSample2D", "texture2D"].contains(tokens[index].text) else {
                index += 1
                continue
            }
            let suffix = Array(tokens[index..<range.upperBound])
            guard suffix.indices.contains(1), suffix[1].text == "(",
                  let close = matchingClose(1, tokens: suffix) else {
                return nil
            }
            let expressionEnd = close + 2 < suffix.count
                    && suffix[close + 1].text == "."
                ? close + 2 : close
            guard let sample = sampleUse(
                Array(suffix[0...expressionEnd])
            ) else { return nil }
            result.append(sample)
            index += close + 1
            if sample.projection != nil { index += 2 }
        }
        return result
    }

    private static func sampleUse(_ tokens: [Token]) -> SampleUse? {
        guard tokens.count >= 5,
              ["texSample2D", "texture2D"].contains(tokens[0].text),
              tokens[1].text == "(",
              let close = matchingClose(1, tokens: tokens),
              let ranges = argumentRanges(in: 2..<close, tokens: tokens),
              ranges.count == 2,
              ranges[0].count == 1,
              let slot = textureSlot(tokens[ranges[0].lowerBound].text) else {
            return nil
        }
        if close == tokens.count - 1 {
            return .init(slot: slot, projection: nil)
        }
        guard close + 2 == tokens.count - 1,
              tokens[close + 1].text == "." else { return nil }
        return .init(slot: slot, projection: tokens[close + 2].text)
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
            switch tokens[index].text {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return index }
                if depth < 0 { return nil }
            default: break
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

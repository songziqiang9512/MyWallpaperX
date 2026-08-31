import Foundation

/// Proves the small base-material shape that the shared image compositor can
/// execute without a second shader/output chain: one neutral authored quad
/// samples one texture, multiplies RGB by one color and two neutral scalars,
/// and preserves sampled alpha apart from one neutral scalar.
///
/// Uniform spelling is returned as authored data. Paths, shader identities and
/// sample identities never participate in this proof.
nonisolated enum SceneAuthoredShaderNeutralTextureTintAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let textureSlot: Int
        let tintUniformName: String
        let brightnessUniformName: String
        let alphaUniformName: String
        let powerUniformName: String
        let scrollUniformNames: [String]
    }

    static func analyze(
        vertexSource: String,
        fragmentSource: String
    ) -> Fact? {
        guard let vertex = unit(vertexSource, stage: .vertex),
              let fragment = unit(fragmentSource, stage: .fragment),
              let vertexFact = neutralVertex(vertex),
              let fragmentFact = neutralFragment(fragment) else { return nil }
        return .init(
            textureSlot: fragmentFact.textureSlot,
            tintUniformName: fragmentFact.tint,
            brightnessUniformName: fragmentFact.brightness,
            alphaUniformName: fragmentFact.alpha,
            powerUniformName: fragmentFact.power,
            scrollUniformNames: vertexFact
        )
    }

    private static func unit(
        _ source: String,
        stage: SceneShaderContract.StageKind
    ) -> Unit? {
        let output = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: stage
            ),
            stage: stage
        )
        guard output.diagnostics.isEmpty else { return nil }
        return output.unit
    }

    private static func neutralVertex(
        _ vertex: Unit
    ) -> [String]? {
        guard vertex.stage == .vertex,
              vertex.functions.filter({ $0.name == "main" }).count == 1,
              let main = vertex.functions.first(where: { $0.name == "main" }),
              let ranges = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: vertex.tokens),
              ranges.count == 4 else { return nil }
        let statements = ranges.map { Array(vertex.tokens[$0]) }

        guard let position = positionStatement(statements[0]),
              let scroll = scrollDeclaration(statements[1]),
              scrollNormalizationStatement(
                statements[2],
                scrollName: scroll.name,
                uniformNames: scroll.uniforms
              ),
              let uv = uvStatement(
                statements[3],
                scrollName: scroll.name
              ),
              declaration(
                position.attribute,
                storage: .attribute,
                type: "vec3",
                in: vertex
              ),
              declaration(
                position.matrix,
                storage: .uniform,
                type: "mat4",
                in: vertex
              ),
              declaration(
                uv.attribute,
                storage: .attribute,
                type: "vec2",
                in: vertex
              ),
              declaration(
                uv.varying,
                storage: .varying,
                type: "vec2",
                in: vertex
              ),
              declaration(
                uv.time,
                storage: .uniform,
                type: "float",
                in: vertex
              ),
              scroll.uniforms.allSatisfy({
                declaration(
                    $0,
                    storage: .uniform,
                    type: "float",
                    in: vertex
                )
              }),
              exactIdentifierUses(
                expected: [
                    position.attribute: 1,
                    position.matrix: 1,
                    uv.attribute: 1,
                    uv.varying: 1,
                    uv.time: 1,
                    scroll.name: 4,
                    scroll.uniforms[0]: 2,
                    scroll.uniforms[1]: 2,
                    "gl_Position": 1,
                ],
                body: main.bodyRange,
                tokens: vertex.tokens
              ) else { return nil }
        return scroll.uniforms
    }

    private static func neutralFragment(
        _ fragment: Unit
    ) -> (
        textureSlot: Int,
        tint: String,
        brightness: String,
        alpha: String,
        power: String
    )? {
        guard fragment.stage == .fragment,
              fragment.functions.filter({ $0.name == "main" }).count == 1,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              let ranges = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens),
              ranges.count == 5 else { return nil }
        let statements = ranges.map { Array(fragment.tokens[$0]) }
        guard let source = sampledColorDeclaration(statements[0]),
              let tint = rgbTintStatement(
                statements[1], sourceName: source.name
              ),
              let alpha = alphaStatement(
                statements[2], sourceName: source.name
              ),
              let power = powerStatement(
                statements[3], sourceName: source.name
              ),
              statements[4].map(\.text) == [
                "gl_FragColor", "=", source.name,
              ],
              declaration(
                "g_Texture\(source.slot)",
                storage: .uniform,
                type: "sampler2D",
                in: fragment
              ),
              declaration(
                tint.tint,
                storage: .uniform,
                type: "vec3",
                in: fragment
              ),
              [tint.brightness, alpha, power].allSatisfy({
                declaration(
                    $0,
                    storage: .uniform,
                    type: "float",
                    in: fragment
                )
              }),
              exactIdentifierUses(
                expected: [
                    source.name: 6,
                    "g_Texture\(source.slot)": 1,
                    tint.tint: 1,
                    tint.brightness: 1,
                    alpha: 1,
                    power: 1,
                    "gl_FragColor": 1,
                ],
                body: main.bodyRange,
                tokens: fragment.tokens
              ) else { return nil }
        return (
            source.slot, tint.tint, tint.brightness, alpha, power
        )
    }

    private static func positionStatement(
        _ tokens: [Token]
    ) -> (attribute: String, matrix: String)? {
        let texts = tokens.map(\.text)
        guard texts.count == 13,
              texts[0...4] == ["gl_Position", "=", "mul", "(", "vec4"],
              texts[5] == "(", texts[7] == ",", number(texts[8], equals: 1),
              texts[9] == ")", texts[10] == ",", texts[12] == ")" else {
            return nil
        }
        return (texts[6], texts[11])
    }

    private static func scrollDeclaration(
        _ tokens: [Token]
    ) -> (name: String, uniforms: [String])? {
        let texts = tokens.map(\.text)
        guard texts.count == 9,
              texts[0] == "vec2", tokens[1].kind == .identifier,
              texts[2...4] == ["=", "vec2", "("],
              texts[6] == ",", texts[8] == ")" else { return nil }
        return (texts[1], [texts[5], texts[7]])
    }

    private static func scrollNormalizationStatement(
        _ tokens: [Token],
        scrollName: String,
        uniformNames: [String]
    ) -> Bool {
        let texts = tokens.map(\.text)
        guard uniformNames.count == 2, texts.count == 21 else { return false }
        return texts[0...5] == [
            scrollName, "=", "sign", "(", scrollName, ")",
        ] && texts[6...8] == ["*", "pow", "("]
            && ["vec2", "float2"].contains(texts[9])
            && texts[10] == "(" && texts[11] == uniformNames[0]
            && texts[12] == "," && texts[13] == uniformNames[1]
            && texts[14...15] == [")", ","]
            && ["CAST2", "vec2", "float2"].contains(texts[16])
            && texts[17] == "(" && number(texts[18], equals: 2)
            && texts[19...20] == [")", ")"]
    }

    private static func uvStatement(
        _ tokens: [Token],
        scrollName: String
    ) -> (varying: String, attribute: String, time: String)? {
        let texts = tokens.map(\.text)
        guard texts.count == 7,
              texts[1] == "=", texts[3] == "+", texts[5] == "*",
              texts[6] == scrollName else { return nil }
        return (texts[0], texts[2], texts[4])
    }

    private static func sampledColorDeclaration(
        _ tokens: [Token]
    ) -> (name: String, slot: Int)? {
        guard tokens.count >= 6,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(tokens[3...]) else { return nil }
        return (tokens[1].text, slot)
    }

    private static func rgbTintStatement(
        _ tokens: [Token],
        sourceName: String
    ) -> (brightness: String, tint: String)? {
        let texts = tokens.map(\.text)
        guard texts.count == 7,
              texts[0...3] == [sourceName, ".", "rgb", "*="],
              texts[5] == "*" else { return nil }
        return (texts[4], texts[6])
    }

    private static func alphaStatement(
        _ tokens: [Token],
        sourceName: String
    ) -> String? {
        let texts = tokens.map(\.text)
        guard texts.count == 5,
              texts[0...3] == [sourceName, ".", "a", "*="] else {
            return nil
        }
        return texts[4]
    }

    private static func powerStatement(
        _ tokens: [Token],
        sourceName: String
    ) -> String? {
        let texts = tokens.map(\.text)
        guard texts.count == 15,
              texts[0...3] == [sourceName, ".", "rgb", "="],
              texts[4...8] == ["pow", "(", sourceName, ".", "rgb"],
              texts[9] == ",",
              ["CAST3", "vec3", "float3"].contains(texts[10]),
              texts[11] == "(",
              texts[13...14] == [")", ")"] else { return nil }
        return texts[12]
    }

    private static func declaration(
        _ name: String,
        storage: Unit.Storage,
        type: String,
        in unit: Unit
    ) -> Bool {
        unit.declarations.filter {
            $0.name == name && $0.storage == storage
                && $0.typeName == type && $0.arraySize == nil
        }.count == 1
    }

    private static func exactIdentifierUses(
        expected: [String: Int],
        body: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        expected.allSatisfy { name, count in
            body.filter { tokens[$0].text == name }.count == count
        }
    }

    private static func number(_ text: String, equals value: Double) -> Bool {
        Double(text) == value
    }
}

import Foundation

/// Proves one straight-color source mixed with an authored uniform RGB value
/// by a scalar that is explicitly clamped to 0...1. Sampled alpha must be
/// copied unchanged to the single fragment output.
nonisolated enum SceneAuthoredShaderUniformRGBMixAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    enum ScalarFact {
        case finite
        case positive
        case bounded01

        var isStrictlyPositive: Bool { self == .positive }
    }

    struct ScalarValue {
        let fact: ScalarFact
        let dependencies: Set<String>
    }

    struct ScalarContext {
        let fragment: Unit
        let variables: [String: ScalarValue]
        let globals: [String: String]
        let helperStack: Set<String>
    }

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              let statements = topLevelStatements(
                  in: main.bodyRange, tokens: tokens
              ), (4 ... 20).contains(statements.count),
              statements.last?.contains(output) == true,
              !containsControlFlow(main.bodyRange, tokens: tokens),
              fragment.functions.allSatisfy({
                  !shadowedBuiltins.contains($0.name)
              }),
              let source = sourceDeclaration(
                  Array(tokens[statements[0]]), fragment: fragment
              ) else { return nil }

        let globals = Dictionary(uniqueKeysWithValues:
            fragment.declarations.compactMap { declaration in
                declaration.arraySize == nil
                    ? (declaration.name, declaration.typeName) : nil
            }
        )
        var values: [String: ScalarValue] = [:]
        var definitions: [String: ScalarValue] = [:]
        var rgbName: String?
        var weightName: String?

        for range in statements.dropFirst().dropLast() {
            let statement = Array(tokens[range])
            if let scalar = scalarDeclaration(statement), rgbName == nil {
                guard values[scalar.name] == nil,
                      let value = scalarValue(
                          scalar.expression,
                          context: .init(
                              fragment: fragment,
                              variables: values,
                              globals: globals,
                              helperStack: []
                          )
                      ) else { return nil }
                values[scalar.name] = value
                definitions[scalar.name] = value
                continue
            }
            guard rgbName == nil,
                  let rgb = rgbDeclaration(statement),
                  let mix = call(rgb.expression), mix.name == "mix",
                  mix.arguments.count == 3,
                  texts(mix.arguments[0]) == [source.name, ".", "rgb"],
                  mix.arguments[1].count == 1,
                  let tint = mix.arguments[1].first?.text,
                  isUniformRGB(tint, fragment: fragment),
                  mix.arguments[2].count == 1,
                  let weight = mix.arguments[2].first?.text,
                  values[weight]?.fact == .bounded01 else { return nil }
            rgbName = rgb.name
            weightName = weight
        }

        guard let rgbName, let weightName,
              outputStatement(
                  Array(tokens[statements.last!]),
                  rgbName: rgbName,
                  sourceName: source.name
              ), allScalarDefinitionsFeed(
                  weightName, definitions: definitions
              ), exactUses(
                  source: source.name,
                  rgb: rgbName,
                  tokens: tokens,
                  body: main.bodyRange
              ) else { return nil }
        return source.slot
    }

    private static let shadowedBuiltins: Set<String> = [
        "clamp", "floor", "frac", "fract", "max", "min", "mix",
        "saturate", "smoothstep", "step", "vec4", "float4",
    ]

    private static func isUniformRGB(_ name: String, fragment: Unit) -> Bool {
        let matches = fragment.declarations.filter { $0.name == name }
        guard matches.count == 1, let declaration = matches.first else {
            return false
        }
        return declaration.storage == .uniform
            && declaration.arraySize == nil
            && ["vec3", "float3"].contains(declaration.typeName)
    }

    private static func sourceDeclaration(
        _ tokens: [Token],
        fragment: Unit
    ) -> (name: String, slot: Int)? {
        guard tokens.count >= 6,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=",
              let sample = call(Array(tokens.dropFirst(3))),
              ["texSample2D", "texture2D"].contains(sample.name),
              sample.arguments.count == 2,
              sample.arguments[0].count == 1,
              let sampler = sample.arguments[0].first?.text,
              let slot = textureSlot(sampler),
              fragment.declarations.contains(where: {
                  $0.storage == .uniform && $0.typeName == "sampler2D"
                      && $0.name == sampler && $0.arraySize == nil
              }),
              safeCoordinate(sample.arguments[1], fragment: fragment) else {
            return nil
        }
        return (tokens[1].text, slot)
    }

    static func scalarDeclaration(
        _ tokens: [Token]
    ) -> (name: String, expression: [Token])? {
        guard tokens.count >= 4, tokens[0].text == "float",
              tokens[1].kind == .identifier,
              tokens[2].text == "=" else { return nil }
        return (tokens[1].text, Array(tokens.dropFirst(3)))
    }

    private static func rgbDeclaration(
        _ tokens: [Token]
    ) -> (name: String, expression: [Token])? {
        guard tokens.count >= 4,
              ["vec3", "float3"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=" else { return nil }
        return (tokens[1].text, Array(tokens.dropFirst(3)))
    }

    private static func outputStatement(
        _ tokens: [Token],
        rgbName: String,
        sourceName: String
    ) -> Bool {
        guard tokens.count >= 5, tokens[0].text == "gl_FragColor",
              tokens[1].text == "=",
              let output = call(Array(tokens.dropFirst(2))),
              ["vec4", "float4"].contains(output.name),
              output.arguments.count == 2 else { return false }
        return texts(output.arguments[0]) == [rgbName]
            && texts(output.arguments[1]) == [sourceName, ".", "a"]
    }

    private static func allScalarDefinitionsFeed(
        _ root: String,
        definitions: [String: ScalarValue]
    ) -> Bool {
        var pending = [root]
        var reached: Set<String> = []
        while let name = pending.popLast() {
            guard reached.insert(name).inserted else { continue }
            guard let definition = definitions[name] else { return false }
            pending.append(contentsOf: definition.dependencies)
        }
        return reached == Set(definitions.keys)
    }

    private static func exactUses(
        source: String,
        rgb: String,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let sourceUses = body.filter { tokens[$0].text == source }
        let rgbUses = body.filter { tokens[$0].text == rgb }
        guard sourceUses.count == 3, rgbUses.count == 2 else { return false }
        let sourceMembers = sourceUses.compactMap { index -> String? in
            guard index + 2 < body.upperBound,
                  tokens[index + 1].text == "." else { return nil }
            return tokens[index + 2].text
        }
        return sourceMembers.sorted() == ["a", "rgb"]
    }

    private static func containsControlFlow(
        _ body: Range<Int>, tokens: [Token]
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "return",
        ]
        return body.contains { forbidden.contains(tokens[$0].text) }
    }

    static func topLevelStatements(
        in body: Range<Int>, tokens: [Token]
    ) -> [Range<Int>]? {
        guard body.count >= 2, tokens[body.lowerBound].text == "{",
              tokens[body.upperBound - 1].text == "}" else { return nil }
        var result: [Range<Int>] = []
        var start = body.lowerBound + 1
        var depth = 0
        for index in start..<(body.upperBound - 1) {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "{", "}": return nil
            case ";" where depth == 0:
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return depth == 0 && start == body.upperBound - 1 ? result : nil
    }

    static func texts(_ tokens: [Token]) -> [String] { tokens.map(\.text) }
}

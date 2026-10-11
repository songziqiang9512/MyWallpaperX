import Foundation

nonisolated enum SceneAuthoredShaderNeutralTextureResolutionAnalyzer {
    private typealias Unit = SceneAuthoredShaderSyntaxUnit
    private typealias Token = SceneAuthoredShaderToken

    static func analyze(
        vertexSource: String,
        fragmentSource: String,
        activeSamplerSlots: Set<Int>
    ) -> SceneAuthoredShaderNeutralTextureResolutionFact? {
        guard let vertex = unit(source: vertexSource, stage: .vertex),
              let fragment = unit(source: fragmentSource, stage: .fragment)
        else { return nil }
        return analyze(vertex: vertex, fragment: fragment,
                       activeSamplerSlots: activeSamplerSlots)
    }

    static func analyze(
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit,
        activeSamplerSlots: Set<Int>
    ) -> SceneAuthoredShaderNeutralTextureResolutionFact? {
        let facts = vertex.declarations.compactMap { resolution
            -> SceneAuthoredShaderNeutralTextureResolutionFact? in
            guard resolution.storage == .uniform, resolution.typeName == "vec4",
                  resolution.arraySize == nil,
                  let slot = textureResolutionSlot(resolution.name),
                  !activeSamplerSlots.contains(slot),
                  references(resolution.name, in: fragment).isEmpty,
                  let main = main(in: vertex) else { return nil }
            let uses = references(resolution.name, in: vertex)
            guard uses.count == 4,
                  let assignment = single(statements(in: main.bodyRange, tokens: vertex.tokens),
                    where: { range in uses.allSatisfy(range.contains) }),
                  let source = normalizationSource(assignment,
                    resolution: resolution.name, unit: vertex),
                  authoredUVSource(source, assignment: assignment, unit: vertex),
                  noSamplerDefault(slot: slot, units: [vertex, fragment]) else { return nil }
            return .init(resolutionSlot: slot)
        }
        return facts.count == 1 ? facts[0] : nil
    }

    /// Preserve the authored multiplication/division, including parentheses.
    /// The complete expressions contain only these three operands and two
    /// operators; dropping parentheses here compares their shape, not codegen.
    private static func normalizationSource(
        _ range: Range<Int>, resolution: String, unit: Unit
    ) -> String? {
        let expression = Array(unit.tokens[range].dropLast()).map(\.text)
        guard let equal = expression.firstIndex(of: "="),
              (equal == 1 || (equal == 3 && expression[1] == ".")),
              let target = single(unit.declarations, where: {
                  $0.name == expression[0] && $0.storage == .varying && $0.arraySize == nil
              }),
              (equal == 1 && target.typeName == "vec2")
                || (equal == 3 && target.typeName == "vec4" && expression[2] == "zw"),
              let constructor = call(Array(expression.dropFirst(equal + 1))),
              constructor.name == "vec2", constructor.arguments.count == 2 else { return nil }
        let x = compact(constructor.arguments[0]), y = compact(constructor.arguments[1])
        guard x.count == 11, y.count == 11, x[0] == y[0],
              Array(x.dropFirst()) == [".", "x", "*", resolution, ".", "z", "/", resolution, ".", "x"],
              Array(y.dropFirst()) == [".", "y", "*", resolution, ".", "w", "/", resolution, ".", "y"]
        else { return nil }
        return x[0]
    }

    private static func authoredUVSource(
        _ name: String, assignment: Range<Int>, unit: Unit
    ) -> Bool {
        // A local declaration/parameter with the same name is not the authored input.
        guard SceneAuthoredShaderSyntaxAnalyzer.uniqueValueDeclarations(in: unit.tokens)[name] != nil,
              let declaration = single(unit.declarations, where: { $0.name == name }),
              declaration.arraySize == nil else { return false }
        if declaration.storage == .attribute { return declaration.typeName == "vec2" }
        guard declaration.storage == .varying, declaration.typeName == "vec4",
              let main = main(in: unit),
              let producer = single(statements(in: main.bodyRange, tokens: unit.tokens),
                where: { exactAuthoredUVAssignment($0, varying: name, unit: unit) }) else { return false }
        return sourceXYHasOnlyProducerAndConsumer(name, producer: producer,
                                                  consumer: assignment, unit: unit)
    }

    /// Default metadata must survive before dead-binding projection. Reuse the
    /// contract parser, and conservatively keep the resource path for any
    /// default declaration (including malformed/ambiguous metadata).
    private static func noSamplerDefault(slot: Int, units: [Unit]) -> Bool {
        let name = "g_Texture\(slot)"
        for unit in units {
            guard let source = unit.source else { return false }
            let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: "")
            guard parsed.diagnostics.isEmpty else { return false }
            let declarations = parsed.declarations.filter { $0.name == name }
            let syntaxDeclarations = unit.declarations.filter { $0.name == name }
            guard declarations.count == syntaxDeclarations.count,
                  syntaxDeclarations.allSatisfy({ expected in
                      declarations.contains { $0.line == expected.line && $0.type == expected.typeName }
                  }) else { return false }
            let lines = Set(declarations.map(\.line))
            for annotation in parsed.annotations where lines.contains(annotation.line) {
                guard case let .object(values) = annotation.value,
                      values["default"] == nil else { return false }
            }
        }
        return true
    }

    private static func sourceXYHasOnlyProducerAndConsumer(
        _ varying: String,
        producer: Range<Int>,
        consumer: Range<Int>,
        unit: Unit
    ) -> Bool {
        let varyingReferences = references(varying, in: unit)
        guard varyingReferences.contains(where: producer.contains),
              varyingReferences.contains(where: consumer.contains),
              let body = main(in: unit)?.bodyRange
        else { return false }
        let bodyStatements = statements(in: body, tokens: unit.tokens)
        for index in varyingReferences where
            !producer.contains(index) && !consumer.contains(index) {
            guard let statement = single(bodyStatements, where: {
                      $0.contains(index)
                  }),
                  statement.count >= 5,
                  unit.tokens[statement.lowerBound].text == varying,
                  unit.tokens[statement.lowerBound + 1].text == ".",
                  unit.tokens[statement.lowerBound + 3].text == "="
            else { return false }
            let written = unit.tokens[statement.lowerBound + 2].text
            guard !written.contains("x"), !written.contains("y"),
                  !written.contains("r"), !written.contains("g"),
                  !written.contains("s"), !written.contains("t")
            else { return false }
        }
        return true
    }

    private static func exactAuthoredUVAssignment(
        _ range: Range<Int>,
        varying: String,
        unit: Unit
    ) -> Bool {
        let expression = Array(unit.tokens[range]).map(\.text)
        guard (expression.count == 6 || expression.count == 8),
              expression[0] == varying,
              expression[1] == ".",
              expression[2] == "xy",
              expression[3] == "=",
              expression.last == ";",
              expression.count == 6 || Array(expression[5...6]) == [".", "xy"]
        else { return false }
        return unit.declarations.contains {
            $0.storage == .attribute
                && $0.typeName == "vec2"
                && $0.name == expression[4]
                && $0.arraySize == nil
        }
    }

    private static func call(
        _ expression: [String]
    ) -> (name: String, arguments: [[String]])? {
        guard expression.count >= 3,
              expression[1] == "(",
              expression.last == ")" else { return nil }
        var depth = 0
        var start = 2
        var arguments: [[String]] = []
        for index in 2..<(expression.count - 1) {
            switch expression[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                guard depth >= 0 else { return nil }
            case "," where depth == 0:
                guard start < index else { return nil }
                arguments.append(Array(expression[start..<index]))
                start = index + 1
            default: break
            }
        }
        guard depth == 0, start < expression.count - 1 else { return nil }
        arguments.append(Array(expression[start..<(expression.count - 1)]))
        return (expression[0], arguments)
    }

    private static func compact(_ expression: [String]) -> [String] {
        expression.filter { $0 != "(" && $0 != ")" }
    }

    private static func statements(
        in body: Range<Int>,
        tokens: [Token]
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = body.lowerBound + 1
        var depth = 0
        for index in (body.lowerBound + 1)..<(body.upperBound - 1) {
            switch tokens[index].text {
            case "{": depth += 1
            case "}": depth -= 1
            case ";" where depth == 0:
                result.append(start..<(index + 1))
                start = index + 1
            default: break
            }
        }
        return result
    }

    private static func references(_ name: String, in unit: Unit) -> [Int] {
        let declarations = unit.declarations.filter { $0.name == name }.map(\.range)
        return unit.tokens.indices.filter { index in
            unit.tokens[index].text == name
                && !declarations.contains(where: { $0.contains(index) })
        }
    }

    private static func main(in unit: Unit) -> Unit.Function? {
        single(unit.functions, where: { $0.name == "main" })
    }

    private static func unit(source: String, stage: SceneShaderContract.StageKind) -> Unit? {
        // This is a structural uniform proof, not bounded execution admission.
        // The normal frontend still checks its own loop budget before emitting.
        let output = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: stage), stage: stage)
        return output.diagnostics.isEmpty ? output.unit : nil
    }

    private static func textureResolutionSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"), name.hasSuffix("Resolution"),
              let slot = Int(name.dropFirst(9).dropLast(10)), (0..<8).contains(slot),
              name == "g_Texture\(slot)Resolution" else { return nil }
        return slot
    }

    private static func single<Element>(_ values: [Element], where predicate: (Element) -> Bool) -> Element? {
        let matches = values.filter(predicate)
        return matches.count == 1 ? matches[0] : nil
    }
}

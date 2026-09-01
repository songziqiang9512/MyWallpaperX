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

        return analyze(
            vertex: vertex,
            fragment: fragment,
            activeSamplerSlots: activeSamplerSlots
        )
    }

    static func analyze(
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit,
        activeSamplerSlots: Set<Int>
    ) -> SceneAuthoredShaderNeutralTextureResolutionFact? {

        let facts = vertex.declarations.flatMap { declaration in
            [
                packedCoordinateFact(
                    resolution: declaration,
                    vertex: vertex,
                    fragment: fragment,
                    activeSamplerSlots: activeSamplerSlots
                ),
                separateCoordinateFact(
                    resolution: declaration,
                    vertex: vertex,
                    fragment: fragment,
                    activeSamplerSlots: activeSamplerSlots
                ),
            ].compactMap { $0 }
        }
        return facts.count == 1 ? facts[0] : nil
    }

    private static func packedCoordinateFact(
        resolution: Unit.Declaration,
        vertex: Unit,
        fragment: Unit,
        activeSamplerSlots: Set<Int>
    ) -> SceneAuthoredShaderNeutralTextureResolutionFact? {
        guard resolution.storage == .uniform,
              resolution.typeName == "vec4",
              resolution.arraySize == nil,
              let resolutionSlot = textureResolutionSlot(resolution.name),
              (0 ..< 8).contains(resolutionSlot),
              !activeSamplerSlots.contains(resolutionSlot),
              references(resolution.name, in: fragment).isEmpty,
              let vertexMain = main(in: vertex),
              let fragmentMain = main(in: fragment)
        else { return nil }

        let resolutionReferences = references(resolution.name, in: vertex)
        guard resolutionReferences.count == 4,
              let assignment = single(
                statements(in: vertexMain.bodyRange, tokens: vertex.tokens),
                where: { range in
                    resolutionReferences.allSatisfy(range.contains)
                }
              ),
              let varying = exactCoordinateAssignment(
                  assignment,
                  resolutionName: resolution.name,
                  tokens: vertex.tokens
              ),
              resolutionReferences.allSatisfy(assignment.contains),
              let vertexVarying = single(vertex.declarations, where: {
                  $0.storage == .varying
                      && $0.typeName == "vec4"
                      && $0.name == varying
                      && $0.arraySize == nil
              }),
              fragment.declarations.contains(where: {
                  $0.storage == .varying
                      && $0.typeName == vertexVarying.typeName
                      && $0.name == varying
                      && $0.arraySize == nil
              })
        else { return nil }

        let vertexVaryingReferences = references(varying, in: vertex)
        guard vertexVaryingReferences.count == 4,
              let sourceAssignment = single(
                statements(in: vertexMain.bodyRange, tokens: vertex.tokens),
                where: {
                    exactAuthoredUVAssignment(
                        $0,
                        varying: varying,
                        unit: vertex
                    )
                }
              ),
              vertexVaryingReferences.allSatisfy({
                  assignment.contains($0) || sourceAssignment.contains($0)
              }),
              let sample = exactCoordinateConsumer(
                  varying: varying,
                  main: fragmentMain,
                  unit: fragment
              ),
              targetComponentsHaveOnlyConsumer(
                  varying: varying,
                  consumerRange: sample.range,
                  unit: fragment
              ),
              let coordinateSlot = textureSamplerSlot(sample.samplerName),
              coordinateSlot != resolutionSlot,
              activeSamplerSlots.contains(coordinateSlot),
              !activeSamplerSlots.contains(resolutionSlot),
              fragment.declarations.contains(where: {
                  $0.storage == .uniform
                      && $0.typeName == "sampler2D"
                      && $0.name == sample.samplerName
                      && $0.arraySize == nil
              }),
              references(sample.samplerName, in: vertex).isEmpty,
              references(sample.samplerName, in: fragment).count == 1
        else { return nil }

        return .init(
            resolutionSlot: resolutionSlot,
            coordinateTextureSlot: coordinateSlot,
            varyingName: varying,
            sourceComponents: "xy",
            targetComponents: "zw"
        )
    }

    private static func separateCoordinateFact(
        resolution: Unit.Declaration,
        vertex: Unit,
        fragment: Unit,
        activeSamplerSlots: Set<Int>
    ) -> SceneAuthoredShaderNeutralTextureResolutionFact? {
        guard resolution.storage == .uniform,
              resolution.typeName == "vec4",
              resolution.arraySize == nil,
              let resolutionSlot = textureResolutionSlot(resolution.name),
              (0 ..< 8).contains(resolutionSlot),
              !activeSamplerSlots.contains(resolutionSlot),
              references(resolution.name, in: fragment).isEmpty,
              let vertexMain = main(in: vertex),
              let fragmentMain = main(in: fragment)
        else { return nil }

        let resolutionReferences = references(resolution.name, in: vertex)
        guard resolutionReferences.count == 4,
              let assignment = single(
                  statements(in: vertexMain.bodyRange, tokens: vertex.tokens),
                  where: { range in resolutionReferences.allSatisfy(range.contains) }
              ),
              let mapping = exactSeparateCoordinateAssignment(
                  assignment,
                  resolutionName: resolution.name,
                  tokens: vertex.tokens
              ),
              mapping.source != mapping.target,
              resolutionReferences.allSatisfy(assignment.contains),
              vertex.declarations.contains(where: {
                  $0.storage == .varying
                      && $0.typeName == "vec4"
                      && $0.name == mapping.source
                      && $0.arraySize == nil
              }),
              vertex.declarations.contains(where: {
                  $0.storage == .varying
                      && $0.typeName == "vec2"
                      && $0.name == mapping.target
                      && $0.arraySize == nil
              }),
              fragment.declarations.contains(where: {
                  $0.storage == .varying
                      && $0.typeName == "vec4"
                      && $0.name == mapping.source
                      && $0.arraySize == nil
              }),
              fragment.declarations.contains(where: {
                  $0.storage == .varying
                      && $0.typeName == "vec2"
                      && $0.name == mapping.target
                      && $0.arraySize == nil
              })
        else { return nil }

        let targetReferences = references(mapping.target, in: vertex)
        guard let sourceAssignment = single(
                  statements(in: vertexMain.bodyRange, tokens: vertex.tokens),
                  where: {
                      exactAuthoredUVAssignment(
                          $0,
                          varying: mapping.source,
                          unit: vertex
                      )
                  }
              ),
              sourceXYHasOnlyProducerAndConsumer(
                  mapping.source,
                  producer: sourceAssignment,
                  consumer: assignment,
                  unit: vertex
              ),
              targetReferences.count == 1,
              targetReferences.allSatisfy(assignment.contains),
              let sample = exactDirectCoordinateConsumer(
                  varying: mapping.target,
                  main: fragmentMain,
                  unit: fragment
              ),
              references(mapping.target, in: fragment).count == 1,
              references(mapping.target, in: fragment).allSatisfy(
                  sample.range.contains
              ),
              let coordinateSlot = textureSamplerSlot(sample.samplerName),
              coordinateSlot != resolutionSlot,
              activeSamplerSlots.contains(coordinateSlot),
              fragment.declarations.contains(where: {
                  $0.storage == .uniform
                      && $0.typeName == "sampler2D"
                      && $0.name == sample.samplerName
                      && $0.arraySize == nil
              }),
              references(sample.samplerName, in: vertex).isEmpty,
              references(sample.samplerName, in: fragment).count == 1
        else { return nil }

        return .init(
            resolutionSlot: resolutionSlot,
            coordinateTextureSlot: coordinateSlot,
            varyingName: mapping.target,
            sourceComponents: "\(mapping.source).xy",
            targetComponents: "xy"
        )
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
        guard expression.count == 6,
              expression[0] == varying,
              expression[1] == ".",
              expression[2] == "xy",
              expression[3] == "=",
              expression[5] == ";" else { return false }
        return unit.declarations.contains {
            $0.storage == .attribute
                && $0.typeName == "vec2"
                && $0.name == expression[4]
                && $0.arraySize == nil
        }
    }

    private static func targetComponentsHaveOnlyConsumer(
        varying: String,
        consumerRange: Range<Int>,
        unit: Unit
    ) -> Bool {
        for index in references(varying, in: unit) {
            guard index + 2 < unit.tokens.count,
                  unit.tokens[index + 1].text == "." else { return false }
            let swizzle = unit.tokens[index + 2].text
            if consumerRange.contains(index) {
                guard swizzle == "zw" else { return false }
            } else if swizzle.contains("z") || swizzle.contains("w")
                        || swizzle.contains("b") || swizzle.contains("a")
                        || swizzle.contains("p") || swizzle.contains("q") {
                return false
            }
        }
        return references(varying, in: unit).contains(where: consumerRange.contains)
    }

    private static func exactCoordinateAssignment(
        _ range: Range<Int>,
        resolutionName: String,
        tokens: [Token]
    ) -> String? {
        let expression = Array(tokens[range].dropLast()).map(\.text)
        guard expression.count >= 10,
              expression[1] == ".",
              expression[2] == "zw",
              expression[3] == "=",
              let call = call(Array(expression.dropFirst(4))),
              call.name == "vec2",
              call.arguments.count == 2
        else { return nil }
        let varying = expression[0]
        guard compact(call.arguments[0]) == [
            varying, ".", "x", "*", resolutionName, ".", "z", "/",
            resolutionName, ".", "x",
        ], compact(call.arguments[1]) == [
            varying, ".", "y", "*", resolutionName, ".", "w", "/",
            resolutionName, ".", "y",
        ] else { return nil }
        return varying
    }

    private static func exactSeparateCoordinateAssignment(
        _ range: Range<Int>,
        resolutionName: String,
        tokens: [Token]
    ) -> (source: String, target: String)? {
        let expression = Array(tokens[range].dropLast()).map(\.text)
        guard expression.count >= 8,
              expression[1] == "=",
              let call = call(Array(expression.dropFirst(2))),
              call.name == "vec2",
              call.arguments.count == 2
        else { return nil }
        let target = expression[0]
        let first = compact(call.arguments[0])
        let second = compact(call.arguments[1])
        guard first.count == 11, second.count == 11,
              first[1...] == [
                  ".", "x", "*", resolutionName, ".", "z", "/",
                  resolutionName, ".", "x",
              ],
              second[1...] == [
                  ".", "y", "*", resolutionName, ".", "w", "/",
                  resolutionName, ".", "y",
              ],
              first[0] == second[0]
        else { return nil }
        return (first[0], target)
    }

    private static func exactCoordinateConsumer(
        varying: String,
        main: Unit.Function,
        unit: Unit
    ) -> (samplerName: String, range: Range<Int>)? {
        var matches: [(String, Range<Int>)] = []
        var index = main.bodyRange.lowerBound
        while index + 1 < main.bodyRange.upperBound {
            let name = unit.tokens[index].text
            guard ["texSample2D", "texture2D"].contains(name),
                  unit.tokens[index + 1].text == "(",
                  let end = matchingDelimiter(
                      at: index + 1,
                      upperBound: main.bodyRange.upperBound,
                      tokens: unit.tokens
                  ),
                  let parsed = call(Array(unit.tokens[index...end]).map(\.text)),
                  parsed.arguments.count == 2,
                  parsed.arguments[0].count == 1,
                  compact(parsed.arguments[1]) == [varying, ".", "zw"]
            else {
                index += 1
                continue
            }
            matches.append((parsed.arguments[0][0], index..<(end + 1)))
            index = end + 1
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func exactDirectCoordinateConsumer(
        varying: String,
        main: Unit.Function,
        unit: Unit
    ) -> (samplerName: String, range: Range<Int>)? {
        var matches: [(String, Range<Int>)] = []
        var index = main.bodyRange.lowerBound
        while index + 1 < main.bodyRange.upperBound {
            let name = unit.tokens[index].text
            guard ["texSample2D", "texture2D"].contains(name),
                  unit.tokens[index + 1].text == "(",
                  let end = matchingDelimiter(
                      at: index + 1,
                      upperBound: main.bodyRange.upperBound,
                      tokens: unit.tokens
                  ),
                  let parsed = call(Array(unit.tokens[index...end]).map(\.text)),
                  parsed.arguments.count == 2,
                  parsed.arguments[0].count == 1,
                  compact(parsed.arguments[1]) == [varying]
            else {
                index += 1
                continue
            }
            matches.append((parsed.arguments[0][0], index..<(end + 1)))
            index = end + 1
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
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

    private static func unit(
        source: String,
        stage: SceneShaderContract.StageKind
    ) -> Unit? {
        let output = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: stage),
            stage: stage
        )
        guard output.diagnostics.isEmpty else { return nil }
        return output.unit
    }

    private static func textureResolutionSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"), name.hasSuffix("Resolution") else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: "g_Texture".count)
        let end = name.index(name.endIndex, offsetBy: -"Resolution".count)
        return Int(name[start..<end])
    }

    private static func textureSamplerSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture") else { return nil }
        return Int(name.dropFirst("g_Texture".count))
    }

    private static func matchingDelimiter(
        at open: Int,
        upperBound: Int,
        tokens: [Token]
    ) -> Int? {
        var depth = 0
        for index in open..<upperBound {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func single<Element>(
        _ values: [Element],
        where predicate: (Element) -> Bool
    ) -> Element? {
        let matches = values.filter(predicate)
        return matches.count == 1 ? matches[0] : nil
    }
}

import Foundation

/// A source-pair proof that one texture slot's authored coordinate is mapped
/// exactly once by that same slot's physical-to-content resolution ratio.
///
/// This fact is deliberately source-structural. It never consults an effect,
/// material, path, asset, or sample identity.
nonisolated struct SceneAuthoredShaderSameSlotMappedCoordinateFact:
    Hashable,
    Sendable
{
    let textureSlot: Int
    let sourceAttributeName: String
    let varyingName: String
    let sourceComponents: String
    let mappedComponents: String

    var resolutionUniformName: String {
        "g_Texture\(textureSlot)Resolution"
    }

    var samplerName: String {
        "g_Texture\(textureSlot)"
    }

    var diagnosticIdentity: String {
        [
            "slot\(textureSlot)",
            "\(sourceAttributeName).\(sourceComponents)",
            "\(varyingName).\(mappedComponents)",
        ].joined(separator: ":")
    }
}

/// Proves only narrow, straight-line authored UV mappings. Unproven or mixed
/// coordinate flows produce no fact so a caller can retain the existing host
/// transform without weakening texture identity or binding safety.
nonisolated enum SceneAuthoredShaderSameSlotMappedCoordinateAnalyzer {
    private typealias Unit = SceneAuthoredShaderSyntaxUnit
    private typealias Token = SceneAuthoredShaderToken

    private struct Mapping {
        let attributeName: String
        let varyingName: String
        let sourceComponents: String
        let mappedComponents: String
        let allowedVertexRanges: [Range<Int>]
    }

    private struct AuthoredCopy {
        let attributeName: String
        let copiedComponents: Set<String>
        let range: Range<Int>
    }

    static func analyze(
        vertexSource: String,
        fragmentSource: String,
        activeSamplerSlots: Set<Int>
    ) -> Set<SceneAuthoredShaderSameSlotMappedCoordinateFact> {
        guard let vertex = unit(source: vertexSource, stage: .vertex),
              let fragment = unit(source: fragmentSource, stage: .fragment),
              !hasAmbiguousControlFlow(vertex),
              !hasAmbiguousControlFlow(fragment)
        else { return [] }

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
    ) -> Set<SceneAuthoredShaderSameSlotMappedCoordinateFact> {
        guard !hasAmbiguousControlFlow(vertex),
              !hasAmbiguousControlFlow(fragment)
        else { return [] }

        return Set(activeSamplerSlots.compactMap { slot in
            fact(slot: slot, vertex: vertex, fragment: fragment)
        })
    }

    private static func fact(
        slot: Int,
        vertex: Unit,
        fragment: Unit
    ) -> SceneAuthoredShaderSameSlotMappedCoordinateFact? {
        guard (0 ..< 8).contains(slot),
              let vertexMain = single(vertex.functions, where: {
                  $0.name == "main"
              }),
              let fragmentMain = single(fragment.functions, where: {
                  $0.name == "main"
              }),
              !containsEarlyReturn(in: vertexMain, unit: vertex),
              !containsEarlyReturn(in: fragmentMain, unit: fragment)
        else { return nil }

        let resolutionName = "g_Texture\(slot)Resolution"
        let samplerName = "g_Texture\(slot)"
        guard single(vertex.declarations, where: {
            $0.storage == .uniform
                && $0.typeName == "vec4"
                && $0.name == resolutionName
                && $0.arraySize == nil
        }) != nil,
        single(fragment.declarations, where: {
            $0.storage == .uniform
                && $0.typeName == "sampler2D"
                && $0.name == samplerName
                && $0.arraySize == nil
        }) != nil,
        references(resolutionName, in: fragment).isEmpty,
        references(samplerName, in: vertex).isEmpty
        else { return nil }

        let vertexStatements = statements(
            in: vertexMain.bodyRange,
            tokens: vertex.tokens
        )
        let mappings = vertexStatements.compactMap { range in
            wholeVectorMapping(
                statement: range,
                slot: slot,
                statements: vertexStatements,
                unit: vertex
            )
        } + componentMappings(
            slot: slot,
            statements: vertexStatements,
            unit: vertex
        )
        guard mappings.count == 1, let mapping = mappings.first,
              exactVertexOwnership(mapping: mapping, slot: slot, unit: vertex),
              linkedVarying(mapping: mapping, vertex: vertex, fragment: fragment),
              let sampleRange = exactSingleSample(
                  samplerName: samplerName,
                  mapping: mapping,
                  main: fragmentMain,
                  unit: fragment
              ),
              mappedComponentsHaveOnlyConsumer(
                  mapping: mapping,
                  consumerRange: sampleRange,
                  unit: fragment
              )
        else { return nil }

        return .init(
            textureSlot: slot,
            sourceAttributeName: mapping.attributeName,
            varyingName: mapping.varyingName,
            sourceComponents: mapping.sourceComponents,
            mappedComponents: mapping.mappedComponents
        )
    }

    private static func wholeVectorMapping(
        statement: Range<Int>,
        slot: Int,
        statements: [Range<Int>],
        unit: Unit
    ) -> Mapping? {
        let expression = Array(unit.tokens[statement].dropLast()).map(\.text)
        guard let left = lvalue(expression),
              left.nextIndex < expression.count,
              expression[left.nextIndex] == "=",
              let call = call(Array(expression.dropFirst(left.nextIndex + 1))),
              call.name == "vec2",
              call.arguments.count == 2,
              let varying = varyingDeclaration(
                  name: left.name,
                  components: left.components,
                  in: unit
              )
        else { return nil }

        let mappedComponents = left.components
            ?? (varying.typeName == "vec2" ? "xy" : "")
        guard ["xy", "zw"].contains(mappedComponents),
              let source = ratioSource(
                  x: call.arguments[0],
                  y: call.arguments[1],
                  slot: slot
              )
        else { return nil }

        if attributeDeclaration(name: source.name, in: unit) != nil,
           source.components == "xy" {
            return Mapping(
                attributeName: source.name,
                varyingName: varying.name,
                sourceComponents: source.components,
                mappedComponents: mappedComponents,
                allowedVertexRanges: [statement]
            )
        }

        guard source.name == varying.name,
              let copy = single(statements, where: {
                  authoredCopy(
                      statement: $0,
                      varying: varying,
                      unit: unit
                  ).map {
                      $0.copiedComponents.contains(source.components)
                          && $0.range.upperBound <= statement.lowerBound
                  } == true
              }).flatMap({
                  authoredCopy(statement: $0, varying: varying, unit: unit)
              })
        else { return nil }

        return Mapping(
            attributeName: copy.attributeName,
            varyingName: varying.name,
            sourceComponents: source.components,
            mappedComponents: mappedComponents,
            allowedVertexRanges: [copy.range, statement]
        )
    }

    private static func componentMappings(
        slot: Int,
        statements: [Range<Int>],
        unit: Unit
    ) -> [Mapping] {
        let scales = statements.compactMap { range in
            componentScale(statement: range, slot: slot, unit: unit)
        }
        var results: [Mapping] = []
        for varying in unit.declarations where varying.storage == .varying {
            for components in ["xy", "zw"] {
                guard varyingSupports(
                    varying,
                    components: components
                ),
                let horizontal = single(scales, where: {
                    $0.varyingName == varying.name
                        && $0.component == String(components.first!)
                        && $0.axis == .horizontal
                }),
                let vertical = single(scales, where: {
                    $0.varyingName == varying.name
                        && $0.component == String(components.last!)
                        && $0.axis == .vertical
                }),
                let copy = single(statements, where: {
                    authoredCopy(
                        statement: $0,
                        varying: varying,
                        unit: unit
                    ).map {
                        $0.copiedComponents.contains(components)
                            && $0.range.upperBound <= min(
                                horizontal.range.lowerBound,
                                vertical.range.lowerBound
                            )
                    } == true
                }).flatMap({
                    authoredCopy(statement: $0, varying: varying, unit: unit)
                })
                else { continue }

                results.append(.init(
                    attributeName: copy.attributeName,
                    varyingName: varying.name,
                    sourceComponents: "xy",
                    mappedComponents: components,
                    allowedVertexRanges: [
                        copy.range,
                        horizontal.range,
                        vertical.range,
                    ]
                ))
            }
        }
        return results
    }

    private enum Axis {
        case horizontal
        case vertical
    }

    private static func componentScale(
        statement: Range<Int>,
        slot: Int,
        unit: Unit
    ) -> (
        varyingName: String,
        component: String,
        axis: Axis,
        range: Range<Int>
    )? {
        let expression = Array(unit.tokens[statement].dropLast()).map(\.text)
        guard expression.count >= 7,
              let left = lvalue(expression),
              let component = left.components,
              component.count == 1,
              left.nextIndex < expression.count,
              expression[left.nextIndex] == "*=",
              unit.declarations.contains(where: {
                  $0.storage == .varying && $0.name == left.name
              })
        else { return nil }

        let ratio = compact(Array(expression.dropFirst(left.nextIndex + 1)))
        let resolution = "g_Texture\(slot)Resolution"
        if ratio == [
            resolution, ".", "z", "/", resolution, ".", "x",
        ], ["x", "z"].contains(component) {
            return (left.name, component, .horizontal, statement)
        }
        if ratio == [
            resolution, ".", "w", "/", resolution, ".", "y",
        ], ["y", "w"].contains(component) {
            return (left.name, component, .vertical, statement)
        }
        return nil
    }

    private static func authoredCopy(
        statement: Range<Int>,
        varying: Unit.Declaration,
        unit: Unit
    ) -> AuthoredCopy? {
        let expression = Array(unit.tokens[statement].dropLast()).map(\.text)
        guard let left = lvalue(expression),
              left.name == varying.name,
              left.nextIndex < expression.count,
              expression[left.nextIndex] == "="
        else { return nil }

        let right = compact(Array(expression.dropFirst(left.nextIndex + 1)))
        let copiedComponents: Set<String>
        let attributeName: String
        if right.count == 1 {
            attributeName = right[0]
            copiedComponents = [
                left.components ?? (varying.typeName == "vec2" ? "xy" : ""),
            ]
        } else if right.count == 3,
                  right[1] == ".",
                  right[2] == "xy" {
            attributeName = right[0]
            copiedComponents = [
                left.components ?? (varying.typeName == "vec2" ? "xy" : ""),
            ]
        } else if right.count == 3,
                  right[1] == ".",
                  right[2] == "xyxy",
                  left.components == nil,
                  varying.typeName == "vec4" {
            attributeName = right[0]
            copiedComponents = ["xy", "zw"]
        } else {
            return nil
        }
        guard !copiedComponents.contains(""),
              attributeDeclaration(name: attributeName, in: unit) != nil
        else { return nil }
        return .init(
            attributeName: attributeName,
            copiedComponents: copiedComponents,
            range: statement
        )
    }

    private static func ratioSource(
        x: [String],
        y: [String],
        slot: Int
    ) -> (name: String, components: String)? {
        let horizontal = compact(x)
        let vertical = compact(y)
        let resolution = "g_Texture\(slot)Resolution"
        guard horizontal.count == 11,
              vertical.count == 11,
              horizontal[1] == ".",
              vertical[1] == ".",
              horizontal[3...] == [
                  "*", resolution, ".", "z", "/", resolution, ".", "x",
              ],
              vertical[3...] == [
                  "*", resolution, ".", "w", "/", resolution, ".", "y",
              ],
              horizontal[0] == vertical[0]
        else { return nil }

        let components = horizontal[2] + vertical[2]
        guard ["xy", "zw"].contains(components) else { return nil }
        return (horizontal[0], components)
    }

    private static func exactVertexOwnership(
        mapping: Mapping,
        slot: Int,
        unit: Unit
    ) -> Bool {
        let allowed = mapping.allowedVertexRanges
        let resolutionReferences = references(
            "g_Texture\(slot)Resolution",
            in: unit
        )
        guard resolutionReferences.count == 4,
              resolutionReferences.allSatisfy({ index in
                  allowed.contains(where: { $0.contains(index) })
              })
        else { return false }

        let varyingReferences = references(mapping.varyingName, in: unit)
        guard varyingReferences.allSatisfy({ index in
            allowed.contains(where: { $0.contains(index) })
        }) else { return false }

        let attributeReferences = references(mapping.attributeName, in: unit)
        return !attributeReferences.isEmpty && attributeReferences.allSatisfy {
            index in allowed.contains(where: { $0.contains(index) })
        }
    }

    private static func linkedVarying(
        mapping: Mapping,
        vertex: Unit,
        fragment: Unit
    ) -> Bool {
        guard let vertexDeclaration = single(vertex.declarations, where: {
            $0.storage == .varying
                && $0.name == mapping.varyingName
                && $0.arraySize == nil
        }) else { return false }
        return single(fragment.declarations, where: {
            $0.storage == .varying
                && $0.name == mapping.varyingName
                && $0.typeName == vertexDeclaration.typeName
                && $0.arraySize == nil
        }) != nil
    }

    private static func exactSingleSample(
        samplerName: String,
        mapping: Mapping,
        main: Unit.Function,
        unit: Unit
    ) -> Range<Int>? {
        let samplerReferences = references(samplerName, in: unit)
        guard samplerReferences.count == 1,
              let samplerIndex = samplerReferences.first,
              samplerIndex >= 2,
              unit.tokens[samplerIndex - 1].text == "(",
              ["texSample2D", "texture2D"].contains(
                  unit.tokens[samplerIndex - 2].text
              ),
              let close = matchingDelimiter(
                  at: samplerIndex - 1,
                  upperBound: unit.tokens.count,
                  tokens: unit.tokens
              )
        else { return nil }

        let range = (samplerIndex - 2)..<(close + 1)
        guard main.bodyRange.contains(range.lowerBound),
              main.bodyRange.contains(range.upperBound - 1),
              let parsed = call(Array(unit.tokens[range]).map(\.text)),
              parsed.arguments.count == 2,
              parsed.arguments[0] == [samplerName],
              exactCoordinate(
                  parsed.arguments[1],
                  varyingName: mapping.varyingName,
                  components: mapping.mappedComponents,
                  unit: unit
              )
        else { return nil }
        return range
    }

    private static func exactCoordinate(
        _ expression: [String],
        varyingName: String,
        components: String,
        unit: Unit
    ) -> Bool {
        let compacted = compact(expression)
        if compacted == [varyingName, ".", components] { return true }
        guard compacted == [varyingName], components == "xy" else {
            return false
        }
        return unit.declarations.contains {
            $0.storage == .varying
                && $0.name == varyingName
                && $0.typeName == "vec2"
        }
    }

    private static func mappedComponentsHaveOnlyConsumer(
        mapping: Mapping,
        consumerRange: Range<Int>,
        unit: Unit
    ) -> Bool {
        let references = references(mapping.varyingName, in: unit)
        guard references.contains(where: consumerRange.contains) else {
            return false
        }
        for index in references where !consumerRange.contains(index) {
            guard index + 2 < unit.tokens.count,
                  unit.tokens[index + 1].text == ".",
                  !swizzle(
                      unit.tokens[index + 2].text,
                      overlaps: mapping.mappedComponents
                  )
            else { return false }
        }
        return true
    }

    private static func swizzle(
        _ swizzle: String,
        overlaps components: String
    ) -> Bool {
        let aliases: [Character: Set<Character>] = [
            "x": ["x", "r", "s"],
            "y": ["y", "g", "t"],
            "z": ["z", "b", "p"],
            "w": ["w", "a", "q"],
        ]
        let target = Set(components.compactMap { aliases[$0] }.flatMap { $0 })
        return swizzle.contains(where: target.contains)
    }

    private static func hasAmbiguousControlFlow(_ unit: Unit) -> Bool {
        let identifiers: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case", "default",
        ]
        return unit.tokens.contains {
            ($0.kind == .identifier && identifiers.contains($0.text))
                || $0.text == "?"
        }
    }

    private static func containsEarlyReturn(
        in function: Unit.Function,
        unit: Unit
    ) -> Bool {
        unit.tokens[function.bodyRange].contains {
            $0.kind == .identifier && $0.text == "return"
        }
    }

    private static func varyingDeclaration(
        name: String,
        components: String?,
        in unit: Unit
    ) -> Unit.Declaration? {
        single(unit.declarations, where: {
            guard $0.storage == .varying,
                  $0.name == name,
                  $0.arraySize == nil else { return false }
            if $0.typeName == "vec2" {
                return components == nil || components == "xy"
            }
            return $0.typeName == "vec4"
                && ["xy", "zw"].contains(components ?? "")
        })
    }

    private static func varyingSupports(
        _ declaration: Unit.Declaration,
        components: String
    ) -> Bool {
        guard declaration.arraySize == nil else { return false }
        if declaration.typeName == "vec2" { return components == "xy" }
        return declaration.typeName == "vec4"
            && ["xy", "zw"].contains(components)
    }

    private static func attributeDeclaration(
        name: String,
        in unit: Unit
    ) -> Unit.Declaration? {
        single(unit.declarations, where: {
            $0.storage == .attribute
                && $0.typeName == "vec2"
                && $0.name == name
                && $0.arraySize == nil
        })
    }

    private static func lvalue(
        _ expression: [String]
    ) -> (name: String, components: String?, nextIndex: Int)? {
        guard expression.first.map({ !$0.isEmpty }) == true else { return nil }
        if expression.count >= 3, expression[1] == "." {
            return (expression[0], expression[2], 3)
        }
        return (expression[0], nil, 1)
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
                if depth < 0 { return nil }
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

import Foundation

/// Removes prepared-variant resource bindings only when their remaining
/// vertex work is proven to feed fragment-dead varying components.
nonisolated enum SceneAuthoredShaderDeadBindingAnalyzer {
    struct Projection {
        let activeSamplerNames: Set<String>
        let omittedUniformNames: Set<String>
        let omittedVertexStatementRanges: [Range<Int>]
    }

    static func analyze(
        vertex: SceneAuthoredShaderSyntaxUnit,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Projection {
        let units = [vertex, fragment]
        let samplerNames = Set(units.flatMap { unit in
            unit.declarations.compactMap { declaration in
                declaration.storage == .uniform && declaration.typeName == "sampler2D"
                    ? declaration.name
                    : nil
            }
        })
        var activeSamplerNames = Set(samplerNames.filter { name in
            units.contains { referenced(name, in: $0) }
        })
        let inactiveSamplerNames = samplerNames.subtracting(activeSamplerNames)
        let directlyActiveSlots = Set(activeSamplerNames.compactMap(textureSlot))
        let neutralTextureResolution =
            SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
                vertex: vertex,
                fragment: fragment,
                activeSamplerSlots: directlyActiveSlots
            )
        let fragmentReads = varyingComponentReads(in: fragment)
        let vertexVaryings = Dictionary(uniqueKeysWithValues: vertex.declarations.compactMap {
            declaration -> (String, Int)? in
            guard declaration.storage == .varying,
                  declaration.arraySize == nil,
                  let count = componentCount(declaration.typeName) else { return nil }
            return (declaration.name, count)
        })

        var omittedUniformNames: Set<String> = []
        var omittedRanges: [Range<Int>] = []
        for samplerName in inactiveSamplerNames.sorted() {
            let resolutionName = samplerName + "Resolution"
            let vertexReferences = referenceIndices(
                resolutionName,
                in: vertex
            )
            let fragmentReferences = referenceIndices(resolutionName, in: fragment)
            if !fragmentReferences.isEmpty {
                activeSamplerNames.insert(samplerName)
                continue
            }
            guard !vertexReferences.isEmpty else {
                continue
            }
            if neutralTextureResolution?.resolutionSlot == textureSlot(samplerName) {
                continue
            }
            let ranges = Set(vertexReferences.compactMap {
                removableStatement(
                    containing: $0,
                    resolutionName: resolutionName,
                    vertex: vertex,
                    vertexVaryings: vertexVaryings,
                    fragmentReads: fragmentReads
                )
            })
            guard !ranges.isEmpty,
                  vertexReferences.allSatisfy({ index in
                      ranges.contains(where: { $0.contains(index) })
                  }) else {
                activeSamplerNames.insert(samplerName)
                continue
            }
            omittedUniformNames.insert(resolutionName)
            omittedRanges.append(contentsOf: ranges)
        }
        return Projection(
            activeSamplerNames: activeSamplerNames,
            omittedUniformNames: omittedUniformNames,
            omittedVertexStatementRanges: Array(Set(omittedRanges)).sorted {
                $0.lowerBound < $1.lowerBound
            }
        )
    }

    static func activeSamplerNames(
        vertexSource: String,
        fragmentSource: String,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds = .none
    ) -> Set<String>? {
        let (vertex, fragment) = syntaxOutputs(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            runtimeLoopBounds: runtimeLoopBounds
        )
        guard vertex.diagnostics.isEmpty,
              fragment.diagnostics.isEmpty,
              let vertexUnit = vertex.unit,
              let fragmentUnit = fragment.unit else { return nil }
        return analyze(vertex: vertexUnit, fragment: fragmentUnit).activeSamplerNames
    }

    /// Projects active sampler names for schema construction when the bounded
    /// frontend is otherwise healthy but a runtime loop remains unresolved.
    ///
    /// The normal `activeSamplerNames` path intentionally returns `nil` for a
    /// dynamic loop so executable frontend admission remains fail-closed.  A
    /// prepared generic artifact still needs a conservative resource schema in
    /// order to report the actual sampler envelope, however.  In that narrow
    /// case we lex top-level sampler declarations and retain every lexical use;
    /// this is an over-approximation for metadata only and never authorizes
    /// frontend compilation or execution.
    static func activeSamplerNamesForSchema(
        vertexSource: String,
        fragmentSource: String,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds = .none
    ) -> Set<String>? {
        if let names = activeSamplerNames(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            runtimeLoopBounds: runtimeLoopBounds
        ) {
            return names
        }

        let (vertex, fragment) = syntaxOutputs(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource,
            runtimeLoopBounds: runtimeLoopBounds
        )
        let diagnostics = vertex.diagnostics + fragment.diagnostics
        guard !diagnostics.isEmpty,
              diagnostics.allSatisfy({ $0.code == .dynamicLoop }) else {
            return nil
        }
        let vertexLex = SceneAuthoredShaderLexer.lex(
            source: vertexSource,
            stage: .vertex
        )
        let fragmentLex = SceneAuthoredShaderLexer.lex(
            source: fragmentSource,
            stage: .fragment
        )
        guard vertexLex.diagnostics.isEmpty,
              fragmentLex.diagnostics.isEmpty else {
            return nil
        }
        guard let vertexProjection = lexicalSamplerProjection(vertexLex.tokens),
              let fragmentProjection = lexicalSamplerProjection(fragmentLex.tokens) else {
            return nil
        }
        let declarations = vertexProjection.declarations.union(
            fragmentProjection.declarations
        )
        let references = vertexProjection.references.union(
            fragmentProjection.references
        )
        return declarations.intersection(references)
    }

    private static func syntaxOutputs(
        vertexSource: String,
        fragmentSource: String,
        runtimeLoopBounds: SceneAuthoredShaderRuntimeLoopBounds
    ) -> (
        vertex: SceneAuthoredShaderSyntaxAnalyzer.Output,
        fragment: SceneAuthoredShaderSyntaxAnalyzer.Output
    ) {
        let vertex = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: vertexSource,
                stage: .vertex
            ),
            stage: .vertex,
            provenRuntimeLoopBounds: runtimeLoopBounds.vertex
        )
        let fragment = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: fragmentSource,
                stage: .fragment
            ),
            stage: .fragment,
            provenRuntimeLoopBounds: runtimeLoopBounds.fragment
        )
        return (vertex, fragment)
    }

    private struct LexicalSamplerProjection {
        let declarations: Set<String>
        let references: Set<String>
    }

    private static func lexicalSamplerProjection(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> LexicalSamplerProjection? {
        var declarations: [String: Range<Int>] = [:]
        var declarationRanges: [Range<Int>] = []
        var braceDepth = 0
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.text == "{" {
                braceDepth += 1
                index += 1
                continue
            }
            if token.text == "}" {
                guard braceDepth > 0 else { return nil }
                braceDepth -= 1
                index += 1
                continue
            }
            guard braceDepth == 0,
                  token.text == "uniform",
                  index + 3 < tokens.count,
                  tokens[index + 1].kind == .identifier,
                  tokens[index + 1].text.caseInsensitiveCompare("sampler2D")
                      == .orderedSame,
                  tokens[index + 2].kind == .identifier else {
                index += 1
                continue
            }
            var end = index + 3
            if tokens[end].text == "[" {
                guard end + 2 < tokens.count,
                      tokens[end + 1].kind == .number,
                      tokens[end + 2].text == "]" else {
                    return nil
                }
                end += 3
            }
            guard end < tokens.count, tokens[end].text == ";" else {
                return nil
            }
            let name = tokens[index + 2].text
            guard declarations[name] == nil else { return nil }
            let range = index..<(end + 1)
            declarations[name] = range
            declarationRanges.append(range)
            index = end + 1
        }
        guard braceDepth == 0 else { return nil }
        guard !declarations.isEmpty else {
            return .init(declarations: [], references: [])
        }
        let references = Set(tokens.indices.compactMap { index -> String? in
            guard tokens[index].kind == .identifier,
                  !declarationRanges.contains(where: { $0.contains(index) }) else {
                return nil
            }
            return tokens[index].text
        })
        return .init(declarations: Set(declarations.keys), references: references)
    }

    private static func removableStatement(
        containing index: Int,
        resolutionName: String,
        vertex: SceneAuthoredShaderSyntaxUnit,
        vertexVaryings: [String: Int],
        fragmentReads: [String: Set<Int>]
    ) -> Range<Int>? {
        guard let function = vertex.functions.first(where: {
            $0.bodyRange.contains(index)
        }),
        let range = statementRange(containing: index, in: function.bodyRange, tokens: vertex.tokens)
        else { return nil }
        let tokens = vertex.tokens
        guard range.count >= 6,
              let componentCount = vertexVaryings[tokens[range.lowerBound].text],
              tokens[range.lowerBound + 1].text == ".",
              tokens[range.lowerBound + 2].kind == .identifier,
              tokens[range.lowerBound + 3].text == "=",
              tokens[range.upperBound - 1].text == ";",
              let written = componentMask(
                  tokens[range.lowerBound + 2].text,
                  componentCount: componentCount
              ),
              written.isDisjoint(with: fragmentReads[tokens[range.lowerBound].text] ?? []),
              range.contains(where: { tokens[$0].text == resolutionName }),
              !range.contains(where: {
                  isOtherTextureResolution(tokens[$0].text, than: resolutionName)
              }),
              safeExpression(
                  range: (range.lowerBound + 4)..<(range.upperBound - 1),
                  tokens: tokens
              ),
              varyingComponentsRemainDead(
                  name: tokens[range.lowerBound].text,
                  written: written,
                  omitting: range,
                  in: vertex
              ) else { return nil }
        return range
    }

    private static func statementRange(
        containing index: Int,
        in body: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Range<Int>? {
        var start = index
        while start > body.lowerBound,
              ![";", "{"].contains(tokens[start - 1].text) {
            start -= 1
        }
        var end = index
        while end < body.upperBound, tokens[end].text != ";" { end += 1 }
        guard end < body.upperBound else { return nil }
        return start..<(end + 1)
    }

    private static func safeExpression(
        range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        for index in range {
            if ["=", "+=", "-=", "*=", "/=", "%="].contains(tokens[index].text) {
                return false
            }
            if index + 1 < range.upperBound, tokens[index + 1].text == "(",
               SceneAuthoredShaderValueType(authoredName: tokens[index].text) == nil {
                return false
            }
        }
        return true
    }

    private static func varyingComponentsRemainDead(
        name: String,
        written: Set<Int>,
        omitting range: Range<Int>,
        in vertex: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        for index in referenceIndices(name, in: vertex) where !range.contains(index) {
            let read = componentMask(at: index, in: vertex, componentCount: 4)
            if !written.isDisjoint(with: read) { return false }
        }
        for index in referenceIndices(name, in: vertex)
            where range.contains(index) && index != range.lowerBound {
            let read = componentMask(at: index, in: vertex, componentCount: 4)
            if !written.isDisjoint(with: read) { return false }
        }
        return true
    }

    private static func varyingComponentReads(
        in unit: SceneAuthoredShaderSyntaxUnit
    ) -> [String: Set<Int>] {
        var result: [String: Set<Int>] = [:]
        for declaration in unit.declarations where declaration.storage == .varying {
            guard declaration.arraySize == nil,
                  let count = componentCount(declaration.typeName) else { continue }
            for index in referenceIndices(declaration.name, in: unit) {
                result[declaration.name, default: []].formUnion(
                    componentMask(at: index, in: unit, componentCount: count)
                )
            }
        }
        return result
    }

    private static func componentMask(
        at index: Int,
        in unit: SceneAuthoredShaderSyntaxUnit,
        componentCount: Int
    ) -> Set<Int> {
        guard index + 2 < unit.tokens.count,
              unit.tokens[index + 1].text == ".",
              let mask = componentMask(
                  unit.tokens[index + 2].text,
                  componentCount: componentCount
              ) else { return Set(0..<componentCount) }
        return mask
    }

    private static func componentMask(
        _ swizzle: String,
        componentCount: Int
    ) -> Set<Int>? {
        let mapping: [Character: Int] = [
            "x": 0, "r": 0, "s": 0,
            "y": 1, "g": 1, "t": 1,
            "z": 2, "b": 2, "p": 2,
            "w": 3, "a": 3, "q": 3,
        ]
        let values = swizzle.compactMap { mapping[$0] }
        guard values.count == swizzle.count,
              !values.isEmpty,
              values.allSatisfy({ $0 < componentCount }) else { return nil }
        return Set(values)
    }

    private static func componentCount(_ type: String) -> Int? {
        switch SceneAuthoredShaderValueType(authoredName: type) {
        case .float: 1
        case .float2: 2
        case .float3: 3
        case .float4: 4
        default: nil
        }
    }

    private static func referenced(
        _ name: String,
        in unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        !referenceIndices(name, in: unit).isEmpty
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

    private static func isOtherTextureResolution(
        _ name: String,
        than expected: String
    ) -> Bool {
        name != expected && name.hasPrefix("g_Texture") && name.hasSuffix("Resolution")
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture") else { return nil }
        return Int(name.dropFirst("g_Texture".count))
    }
}

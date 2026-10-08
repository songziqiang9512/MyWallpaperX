import Foundation

/// Removes prepared-variant resource bindings only when their remaining
/// vertex work is proven to feed fragment-dead varying components.
nonisolated enum SceneAuthoredShaderDeadBindingAnalyzer {
    private static let maximumProjectionStatements = 512
    private static let maximumProjectionWork = 1_000_000
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
        guard !inactiveSamplerNames.isEmpty else {
            return .init(activeSamplerNames: activeSamplerNames,
                         omittedUniformNames: [], omittedVertexStatementRanges: [])
        }
        let directlyActiveSlots = Set(activeSamplerNames.compactMap(textureSlot))
        let neutralTextureResolution =
            SceneAuthoredShaderNeutralTextureResolutionAnalyzer.analyze(
                vertex: vertex,
                fragment: fragment,
                activeSamplerSlots: directlyActiveSlots
            )
        let needsProjection = inactiveSamplerNames.contains { name in
            neutralTextureResolution?.resolutionSlot != textureSlot(name)
                && referenced(name + "Resolution", in: vertex)
                && !referenced(name + "Resolution", in: fragment)
        }
        let removableRanges: [Range<Int>]
        if needsProjection {
            let vertexVaryings = Dictionary(uniqueKeysWithValues: vertex.declarations.compactMap {
                declaration -> (String, Int)? in
                guard declaration.storage == .varying, declaration.arraySize == nil,
                      let count = componentCount(declaration.typeName) else { return nil }
                return (declaration.name, count)
            })
            removableRanges = removableMainStatements(
                vertex: vertex, vertexVaryings: vertexVaryings,
                fragmentReads: varyingComponentReads(in: fragment)
            )
        } else {
            removableRanges = []
        }
        var omittedUniformNames: Set<String> = []
        var omittedRanges: [Range<Int>] = []
        for samplerName in inactiveSamplerNames.sorted() {
            let resolutionName = samplerName + "Resolution"
            let vertexReferences = referenceIndices(resolutionName, in: vertex)
            if !referenceIndices(resolutionName, in: fragment).isEmpty {
                activeSamplerNames.insert(samplerName)
                continue
            }
            guard !vertexReferences.isEmpty else { continue }
            if neutralTextureResolution?.resolutionSlot == textureSlot(samplerName) {
                continue
            }
            guard vertexReferences.allSatisfy({ index in
                removableRanges.contains(where: { $0.contains(index) })
            }) else {
                activeSamplerNames.insert(samplerName)
                continue
            }
            omittedUniformNames.insert(resolutionName)
            omittedRanges = removableRanges
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

    /// One deletion proof serves both the bounded emitter and compiler input.
    /// Only main's top-level statements participate; nested/control-flow work
    /// and authored helper bodies remain the compiler's responsibility.
    private static func removableMainStatements(
        vertex: SceneAuthoredShaderSyntaxUnit,
        vertexVaryings: [String: Int],
        fragmentReads: [String: Set<Int>]
    ) -> [Range<Int>] {
        guard let main = vertex.functions.first(where: { $0.name == "main" }) else {
            return []
        }
        let tokens = vertex.tokens
        guard let statementRanges = SceneAuthoredShaderUniformRGBMixAnalyzer
            .topLevelStatements(in: main.bodyRange, tokens: tokens, skippingNestedBlocks: true),
              statementRanges.count <= maximumProjectionStatements else { return [] }
        let statements = statementRanges.map { $0.lowerBound..<($0.upperBound + 1) }
        var referencesByVarying: [String: [Int]] = [:]
        for index in tokens.indices where vertexVaryings[tokens[index].text] != nil {
            referencesByVarying[tokens[index].text, default: []].append(index)
        }
        let declarationIndices = Set(vertex.declarations.flatMap { $0.range })
        var writes: [Range<Int>: (name: String, components: Set<Int>)] = [:]
        for range in statements where range.count >= 6 {
            let start = range.lowerBound
            let name = tokens[start].text
            let swizzle = tokens[start + 2].text
            guard let count = vertexVaryings[name], tokens[start + 1].text == ".",
                  let mask = componentMask(swizzle, componentCount: count),
                  mask.count == swizzle.count,
                  ["xyzw", "rgba", "stpq"].contains(where: { family in
                      swizzle.allSatisfy { family.contains($0) }
                  }),
                  ["=", "+=", "-=", "*=", "/="].contains(tokens[start + 3].text),
                  mask.isDisjoint(with: fragmentReads[name] ?? []),
                  discardable((start + 4)..<(range.upperBound - 1), in: vertex) else {
                continue
            }
            writes[range] = (name, mask)
        }
        // Consider all dead writes together, including compound writes. Any
        // read outside that set keeps the affected components and their inputs.
        var changed = true
        var remainingWork = maximumProjectionWork
        while changed {
            changed = false
            let candidateIndices = Set(writes.keys.flatMap { $0 })
            for (range, write) in writes {
                var hasLiveRead = false
                for index in referencesByVarying[write.name] ?? [] {
                    remainingWork -= 1
                    guard remainingWork >= 0 else { return [] }
                    if !declarationIndices.contains(index), !candidateIndices.contains(index),
                       !write.components.isDisjoint(with: componentMask(
                           at: index, in: vertex,
                           componentCount: vertexVaryings[write.name] ?? 4
                       )) {
                        hasLiveRead = true
                        break
                    }
                }
                if hasLiveRead {
                    writes.removeValue(forKey: range)
                    changed = true
                }
            }
        }
        var omitted = Set(writes.keys)
        let globalNames = Set(vertex.declarations.map(\.name))
        let locals: [(name: String, range: Range<Int>)] = statements.compactMap { range in
            let start = range.lowerBound
            guard range.count >= 5,
                  SceneAuthoredShaderValueType(authoredName: tokens[start].text) != nil,
                  tokens[start + 1].kind == .identifier,
                  tokens[start + 2].text == "=",
                  !globalNames.contains(tokens[start + 1].text),
                  !tokens[main.parameterRange].contains(where: {
                      $0.text == tokens[start + 1].text
                  }) else { return nil }
            let name = tokens[start + 1].text
            let initializer = (start + 3)..<(range.upperBound - 1)
            guard !initializer.contains(where: { tokens[$0].text == name }),
                  SceneAuthoredShaderTokenScanner.split(
                    initializer, separator: ",", tokens: tokens
                  )?.count == 1,
                  discardable(initializer, in: vertex) else { return nil }
            return (name, range)
        }
        var localReferences: [String: [Int]] = [:]
        let localNames = Set(locals.map(\.name))
        for index in main.bodyRange where localNames.contains(tokens[index].text) {
            localReferences[tokens[index].text, default: []].append(index)
        }
        var omittedIndices = Set(omitted.flatMap { $0 })
        // Walk backward through declaration order. Every use must already be
        // deleted; a forward reference or ambiguous definition stays live.
        // This closure evaluates no values and builds no SSA/control-flow graph.
        for local in locals.reversed() {
            guard (localReferences[local.name] ?? []).allSatisfy({ index in
                local.range.contains(index) || omittedIndices.contains(index)
            }) else { continue }
            omitted.insert(local.range)
            omittedIndices.formUnion(local.range)
        }
        return omitted.sorted { $0.lowerBound < $1.lowerBound }
    }

    private static func discardable(
        _ range: Range<Int>, in unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        SceneAuthoredShaderColorTransferAnalyzer.helperCallsArePureAndUnsampled(
            fragment: unit, expressionRanges: [range], discardingExpression: true
        )
    }

    /// Blank proven token ranges without shifting diagnostics or fragment
    /// source. A token/source mismatch (for example macro expansion) keeps the
    /// original input instead of applying offsets to unproven text.
    static func projectVertexSource(vertex: String, fragment: String) -> String {
        let outputs = syntaxOutputs(vertexSource: vertex, fragmentSource: fragment,
                                    runtimeLoopBounds: .none)
        guard outputs.vertex.diagnostics.isEmpty, outputs.fragment.diagnostics.isEmpty,
              let vertexUnit = outputs.vertex.unit, let fragmentUnit = outputs.fragment.unit else {
            return vertex
        }
        let projection = analyze(vertex: vertexUnit, fragment: fragmentUnit)
        guard !projection.omittedVertexStatementRanges.isEmpty else { return vertex }
        var scalars = Array(vertex.unicodeScalars)
        var lineStarts = [0]
        for index in scalars.indices where scalars[index] == "\n" {
            lineStarts.append(index + 1)
        }
        var ranges: [Range<Int>] = []
        for range in projection.omittedVertexStatementRanges {
            let tokens = vertexUnit.tokens[range]
            guard let first = tokens.first, let last = tokens.last,
                  lineStarts.indices.contains(first.line - 1),
                  lineStarts.indices.contains(last.line - 1) else { return vertex }
            let start = lineStarts[first.line - 1] + first.column - 1
            let end = lineStarts[last.line - 1] + last.column - 1 + last.text.unicodeScalars.count
            guard start >= 0, end <= scalars.count, start < end else { return vertex }
            for token in tokens {
                guard lineStarts.indices.contains(token.line - 1) else { return vertex }
                let offset = lineStarts[token.line - 1] + token.column - 1
                let spelling = Array(token.text.unicodeScalars)
                guard offset >= start, offset + spelling.count <= end,
                      Array(scalars[offset..<(offset + spelling.count)]) == spelling else {
                    return vertex
                }
            }
            ranges.append(start..<end)
        }
        for range in ranges {
            for index in range where scalars[index] != "\n" && scalars[index] != "\r" {
                scalars[index] = " "
            }
        }
        return String(String.UnicodeScalarView(scalars))
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

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture") else { return nil }
        return Int(name.dropFirst("g_Texture".count))
    }
}

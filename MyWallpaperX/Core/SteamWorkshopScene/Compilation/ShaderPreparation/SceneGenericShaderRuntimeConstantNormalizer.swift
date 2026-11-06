import Foundation

/// Generic-only storage lowering for readonly uniform-derived globals. The
/// authored initializer stays in place; glslang owns invocation-local storage.
nonisolated enum SceneGenericShaderRuntimeConstantNormalizer {
    private typealias Unit = SceneAuthoredShaderSyntaxUnit
    private typealias Token = SceneAuthoredShaderToken

    static func rewrite(_ source: String, stage: SceneShaderContract.StageKind) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let analysisSource = normalized.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("#version") ? "" : $0
        }.joined(separator: "\n")
        let analysis = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: analysisSource, stage: stage),
            stage: stage
        )
        guard analysis.diagnostics.isEmpty, let unit = analysis.unit else { return source }
        let tokens = unit.tokens
        let globalDeclarations = SceneAuthoredShaderGlobalReferenceAnalyzer.globalValueDeclarations(in: unit)
        let declarations = SceneAuthoredShaderSyntaxAnalyzer.uniqueValueDeclarations(from: globalDeclarations)
        let constantUses = unit.functions.flatMap { function in
            function.bodyRange.compactMap { index -> Range<Int>? in
                guard tokens[index].text == "const",
                      let end = initializerEnd(after: index, tokens: tokens, rejectsComma: false)
                else { return nil }
                return index..<end
            }
        }
        let uniformTypes = Dictionary(uniqueKeysWithValues: unit.declarations.compactMap {
            declaration -> (String, SceneAuthoredShaderValueType)? in
            guard declaration.storage == .uniform, declaration.arraySize == nil,
                  let type = SceneAuthoredShaderValueType(authoredName: declaration.typeName),
                  isFloatingValue(type),
                  declarations[declaration.name]?.index == declaration.range.lowerBound + 2
            else { return nil }
            return (declaration.name, type)
        })
        var qualifiers: [Int] = []
        var depth = 0
        for index in tokens.indices {
            if tokens[index].text == "{" { depth += 1 }
            if tokens[index].text == "}" { depth -= 1 }
            guard depth == 0, tokens[index].text == "const", index + 4 < tokens.count,
                  index == 0 || [";", "}"].contains(tokens[index - 1].text),
                  let type = SceneAuthoredShaderValueType(authoredName: tokens[index + 1].text),
                  isFloatingValue(type), tokens[index + 2].kind == .identifier,
                  tokens[index + 3].text == "=",
                  declarations[tokens[index + 2].text]?.index == index + 2,
                  let end = initializerEnd(after: index + 3, tokens: tokens),
                  invariantInitializer((index + 4)..<end, type: type, unit: unit,
                    uniforms: uniformTypes, globalDeclarations: globalDeclarations),
                  readonlyUses(of: tokens[index + 2].text, declaredAt: index + 2,
                    unit: unit, globalDeclarations: globalDeclarations, constantUses: constantUses)
            else { continue }
            qualifiers.append(index)
        }
        guard !qualifiers.isEmpty else { return source }
        var lineStarts = [0]
        for (offset, scalar) in normalized.unicodeScalars.enumerated() where scalar == "\n" {
            lineStarts.append(offset + 1)
        }
        var result = normalized
        for index in qualifiers.reversed() {
            let token = tokens[index]
            guard token.line > 0, token.line <= lineStarts.count else { return source }
            let offset = lineStarts[token.line - 1] + token.column - 1
            guard offset >= 0, offset + token.text.count <= result.unicodeScalars.count else {
                return source
            }
            let lower = result.unicodeScalars.index(result.unicodeScalars.startIndex, offsetBy: offset)
            let upper = result.unicodeScalars.index(lower, offsetBy: token.text.count)
            guard let start = String.Index(lower, within: result),
                  let end = String.Index(upper, within: result), result[start..<end] == "const"
            else { return source }
            result.removeSubrange(start..<end)
        }
        return result
    }

    private static func isFloatingValue(_ type: SceneAuthoredShaderValueType) -> Bool {
        [.float, .float2, .float3, .float4].contains(type)
    }

    /// A qualifier cannot be removed from just one sibling of a declaration.
    /// Calls and constructors keep their argument commas inside their span.
    private static func initializerEnd(
        after assignment: Int, tokens: [Token], rejectsComma: Bool = true
    ) -> Int? {
        var cursor = assignment + 1
        while cursor < tokens.count {
            if tokens[cursor].text == ";" { return cursor }
            if rejectsComma, tokens[cursor].text == "," { return nil }
            if ["(", "[", "{"].contains(tokens[cursor].text) {
                guard let end = SceneAuthoredShaderSyntaxAnalyzer.matchingDelimiter(
                    at: cursor, tokens: tokens) else { return nil }
                cursor = end + 1
            } else { cursor += 1 }
        }
        return nil
    }

    private static func invariantInitializer(
        _ range: Range<Int>, type: SceneAuthoredShaderValueType, unit: Unit,
        uniforms: [String: SceneAuthoredShaderValueType],
        globalDeclarations: SceneAuthoredShaderSyntaxAnalyzer.ValueDeclarationFacts
    ) -> Bool {
        let tokens = unit.tokens
        func valueExpression(_ range: Range<Int>) -> SceneAuthoredShaderBuiltInVectorConversion.Expression? {
            // Keep the existing constructor/narrowing analysis first. The
            // nontruncating analysis additionally proves scalar built-ins;
            // purity and exact uniform ownership are checked below.
            SceneAuthoredShaderBuiltInVectorConversion.componentExpression(
                range, tokens: tokens, unit: unit, valueTypes: uniforms,
                permitsScalarVectorAddition: true, permitsVectorTruncation: true
            ) ?? SceneAuthoredShaderBuiltInVectorConversion.componentExpression(
                range, tokens: tokens, unit: unit, valueTypes: uniforms,
                permitsScalarVectorAddition: true, permitsVectorTruncation: false
            )
        }
        guard let expression = valueExpression(range),
              expression.type == type, expression.conversions.isEmpty,
              tokens[range].allSatisfy({ $0.kind == .identifier || $0.kind == .number
                || ["+", "-", "*", "/", "%", "(", ")", ",", "."].contains($0.text) })
        else { return false }
        var readsUniform = false
        for index in range where tokens[index].kind == .identifier {
            let name = tokens[index].text
            if index > range.lowerBound, tokens[index - 1].text == "." { continue }
            if index + 1 < range.upperBound, tokens[index + 1].text == "(" {
                let constructor = SceneAuthoredShaderValueType(authoredName: name)
                guard globalDeclarations[name] == nil,
                      SceneAuthoredShaderBuiltInVectorConversion.unshadowedCall(
                        at: index, tokens: tokens, unit: unit),
                      let close = SceneAuthoredShaderTokenScanner.matchingParenthesis(
                        tokens: tokens, opening: index + 1), close < range.upperBound,
                      (constructor.map(isFloatingValue) == true
                       || ["CAST2", "CAST3", "CAST4"].contains(name)
                       || SceneAuthoredShaderColorTransferAnalyzer.helperCallsArePureAndUnsampled(
                           fragment: unit, expressionRanges: [index..<(close + 1)],
                           discardingExpression: true, permitsUnexpandedBlendingHelper: false,
                           permitsAuthoredHelpers: false)),
                      let arguments = SceneAuthoredShaderTokenScanner.argumentRanges(
                        in: (index + 2)..<close, tokens: tokens),
                      arguments.allSatisfy({ argument in
                          // A constructor fixes its result type even when a
                          // child is unknown; purity also requires every child.
                          guard let value = valueExpression(argument)
                          else { return false }
                          return value.conversions.isEmpty
                      })
                else { return false }
                continue
            }
            guard uniforms[name] != nil,
                  let references = SceneAuthoredShaderGlobalReferenceAnalyzer
                    .exactReferenceIndices(name, in: unit), references.contains(index) else { return false }
            readsUniform = true
        }
        return readsUniform
    }

    private static func readonlyUses(
        of name: String, declaredAt declaration: Int, unit: Unit,
        globalDeclarations: SceneAuthoredShaderSyntaxAnalyzer.ValueDeclarationFacts,
        constantUses: [Range<Int>]
    ) -> Bool {
        let tokens = unit.tokens
        guard let references = SceneAuthoredShaderGlobalReferenceAnalyzer
                .exactReferenceIndices(name, in: unit) else { return false }
        for index in references where index != declaration {
            // Other global initializers and dimensions are not runtime
            // value consumers; dependent const graphs remain unmodified.
            guard let function = unit.functions.first(where: { $0.bodyRange.contains(index) }),
                  !constantUses.contains(where: { $0.contains(index) }),
                  readonlyValue(at: index, body: function.bodyRange, unit: unit,
                    globalDeclarations: globalDeclarations) else { return false }
        }
        return true
    }

    private static func readonlyValue(
        at index: Int, body: Range<Int>, unit: Unit,
        globalDeclarations: SceneAuthoredShaderSyntaxAnalyzer.ValueDeclarationFacts
    ) -> Bool {
        let tokens = unit.tokens
        var end = index + 1
        if end + 1 < body.upperBound, tokens[end].text == ".",
           tokens[end + 1].kind == .identifier {
            guard !tokens[end + 1].text.isEmpty,
                  tokens[end + 1].text.allSatisfy({ "xyzwrgba".contains($0) }) else { return false }
            end += 2
        }
        guard end >= body.upperBound || tokens[end].text != "(",
              SceneAuthoredShaderTokenScanner.isReadOnlyValueUse(
                start: index, end: end, tokens: tokens, body: body, permitsReturn: true)
        else { return false }
        var lower = index
        var upper = end
        while lower > body.lowerBound, upper < body.upperBound,
              tokens[lower - 1].text == "(", tokens[upper].text == ")",
              lower < 2 || tokens[lower - 2].kind != .identifier || tokens[lower - 2].text == "return" {
            lower -= 1; upper += 1
        }
        guard upper >= body.upperBound || !["&=", "|=", "^=", "<<=", ">>="].contains(tokens[upper].text)
        else { return false }
        var openings: [Int] = []
        for cursor in body.lowerBound..<index {
            switch tokens[cursor].text {
            case "(", "[": openings.append(cursor)
            case ")", "]":
                guard !openings.isEmpty else { return false }
                openings.removeLast()
            default: break
            }
        }
        for opening in openings {
            guard tokens[opening].text != "[" else { return false }
            guard opening > body.lowerBound, tokens[opening - 1].kind == .identifier else { continue }
            let name = tokens[opening - 1].text
            if ["if", "for", "while", "switch", "return"].contains(name) { continue }
            guard opening < 2 || tokens[opening - 2].text != ".",
                  let close = SceneAuthoredShaderTokenScanner.matchingParenthesis(tokens: tokens, opening: opening),
                  close < body.upperBound,
                  let arguments = SceneAuthoredShaderTokenScanner.argumentRanges(
                    in: (opening + 1)..<close, tokens: tokens),
                  let ordinal = arguments.firstIndex(where: { $0.contains(index) }) else { return false }
            guard globalDeclarations[name] == nil else { return false }
            let definitions = unit.functions.filter { $0.name == name }
            if !definitions.isEmpty {
                guard let callReferences = SceneAuthoredShaderGlobalReferenceAnalyzer
                        .exactReferenceIndices(name, in: unit), callReferences.contains(opening - 1),
                      definitions.count == 1, let function = definitions.first,
                      let parameters = SceneAuthoredShaderTokenScanner.argumentRanges(
                        in: function.parameterRange, tokens: tokens),
                      parameters.count == arguments.count,
                      let type = SceneAuthoredShaderFunctionSemantics.valueInputType(
                        in: parameters[ordinal], tokens: tokens, permitsConst: true),
                      isFloatingValue(type) else { return false }
                continue
            }
            guard SceneAuthoredShaderBuiltInVectorConversion.unshadowedCall(
                at: opening - 1, tokens: tokens, unit: unit) else { return false }
            if SceneAuthoredShaderValueType(authoredName: name) != nil { continue }
            if let count = SceneAuthoredShaderMetalEmitter.textureSampleArgumentCount(name, functionNames: []),
               arguments.count == count, ordinal > 0 { continue }
            guard SceneAuthoredShaderColorTransferAnalyzer.helperCallsArePureAndUnsampled(
                fragment: unit, expressionRanges: [(opening - 1)..<(close + 1)],
                discardingExpression: true, permitsUnexpandedBlendingHelper: false,
                permitsAuthoredHelpers: false) else { return false }
        }
        return true
    }

}

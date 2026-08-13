import Foundation

/// Proves a bounded whole-RGBA filter in the straight-color domain. Every
/// color leaf must sample one texture slot; auxiliary samples may only reach
/// scalar control values. The caller supplies the UNorm clamp/premultiply
/// boundary represented by the returned transfer fact.
nonisolated enum SceneAuthoredShaderStraightWholeColorFilterAnalyzer {
    static func analyze(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Int? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output, tokens: tokens, body: main.bodyRange
              ),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output, in: tokens, body: main.bodyRange
                ),
              outputExpression.count == 1,
              outputExpression.first?.kind == .identifier,
              let outputName = outputExpression.first?.text,
              let definition = uniqueVectorDefinition(
                  named: outputName, before: output,
                  tokens: tokens, body: main.bodyRange
              ),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  definition, tokens: tokens, body: main.bodyRange
              ),
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: definition, in: tokens, body: main.bodyRange
                ),
              let colorSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(initializer),
              mainHasBoundedReplacement(
                  outputName: outputName,
                  definition: definition,
                  output: output,
                  colorSlot: colorSlot,
                  fragment: fragment,
                  main: main
              ) else {
            return nil
        }
        return colorSlot
    }

    private static func mainHasBoundedReplacement(
        outputName: String,
        definition: Int,
        output: Int,
        colorSlot: Int,
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        let body = main.bodyRange
        guard !body.contains(where: {
            ["for", "while", "do", "switch", "discard", "return", "else"]
                .contains(tokens[$0].text)
        }) else { return false }
        let vectorDefinitions = body.filter { index in
            index > body.lowerBound && index + 1 < body.upperBound
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index].kind == .identifier
                && tokens[index + 1].text == "="
        }
        guard vectorDefinitions == [definition] else { return false }

        let replacements = body.filter { index in
            index > definition && index < output
                && tokens[index].text == outputName
                && index + 1 < body.upperBound
                && tokens[index + 1].text == "="
        }
        guard replacements.count == 1,
              let replacement = replacements.first,
              !SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  replacement, tokens: tokens, body: body
              ),
              isSingleStatementIf(at: replacement, tokens: tokens, body: body),
              let replacementExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: replacement, in: tokens, body: body
                ),
              let call = functionCall(replacementExpression),
              call.arguments.count == 2,
              isCoordinate(call.arguments[0], fragment: fragment),
              isScalarControl(
                  call.arguments[1],
                  before: replacement,
                  fragment: fragment,
                  main: main,
                  outputName: outputName
              ),
              let helper = fragment.functions.first(where: {
                  $0.name == call.name && $0.name != "main"
              }),
              helper.returnType == "vec4" || helper.returnType == "float4",
              fragment.functions.filter({ $0.name == call.name }).count == 1,
              tokens.filter({ $0.text == call.name }).count == 2,
              helperProvesWholeColor(
                  helper, colorSlot: colorSlot, fragment: fragment
              ) else {
            return false
        }
        let allowedCalls = Set([call.name, "texSample2D", "texture2D"])
        for index in body where index + 1 < body.upperBound
            && tokens[index].kind == .identifier
            && tokens[index + 1].text == "(" {
            guard allowedCalls.contains(tokens[index].text)
                    || ["if", "vec2", "float2"].contains(tokens[index].text) else {
                return false
            }
        }

        let sampleSlots = textureSampleSlots(in: body, tokens: tokens)
        guard sampleSlots?.count == 2,
              sampleSlots?.filter({ $0 == colorSlot }).count == 1,
              sampleSlots?.filter({ $0 != colorSlot }).count == 1 else {
            return false
        }
        let assignmentOperators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        let permittedUses = Set([
            definition,
            replacement,
            output + 2,
        ])
        for use in body where tokens[use].text == outputName {
            if use + 1 < body.upperBound,
               assignmentOperators.contains(tokens[use + 1].text) {
                guard use == definition || use == replacement else { return false }
            }
            if use + 1 < body.upperBound, tokens[use + 1].text == "." {
                return false
            }
            let declarationUse = use > body.lowerBound
                && ["vec4", "float4"].contains(tokens[use - 1].text)
            guard permittedUses.contains(use) || declarationUse else { return false }
        }
        return true
    }

    private static func helperProvesWholeColor(
        _ helper: SceneAuthoredShaderSyntaxUnit.Function,
        colorSlot: Int,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        let tokens = fragment.tokens
        guard !helper.bodyRange.contains(where: {
            ["if", "else", "for", "while", "do", "switch", "discard"]
                .contains(tokens[$0].text)
        }), let parameters = parameterKinds(helper, tokens: tokens) else {
            return false
        }
        var scalarNames = Set(fragment.declarations.compactMap {
            scalarType($0.typeName) ? $0.name : nil
        })
        scalarNames.formUnion(parameters.scalars)
        var colorNames: Set<String> = []
        var sampledNames: Set<String> = []
        var returnCount = 0
        var statementCount = 0
        let statements = topLevelStatements(in: helper.bodyRange, tokens: tokens)
        guard let statements, (3 ... 20).contains(statements.count) else {
            return false
        }
        for index in helper.bodyRange where index + 1 < helper.bodyRange.upperBound
            && tokens[index].kind == .identifier
            && tokens[index + 1].text == "(" {
            guard ["texSample2D", "texture2D", "vec2", "float2"]
                .contains(tokens[index].text) else { return false }
        }
        for statement in statements {
            statementCount += 1
            let value = Array(tokens[statement])
            if value.first?.text == "return" {
                returnCount += 1
                guard statementCount == statements.count,
                      expressionKind(
                          value.dropFirst(),
                          scalarNames: scalarNames,
                          colorNames: colorNames
                      ) == .color else { return false }
                continue
            }
            guard value.count >= 4,
                  value[1].kind == .identifier,
                  value[2].text == "=" else { return false }
            let type = value[0].text
            let name = value[1].text
            let expression = value[3...]
            if ["vec4", "float4"].contains(type) {
                if let slot = SceneAuthoredShaderColorTransferAnalyzer
                    .directTextureSampleSlot(expression) {
                    guard slot == colorSlot,
                          sampledNames.insert(name).inserted else { return false }
                } else {
                    guard expressionKind(
                        expression,
                        scalarNames: scalarNames,
                        colorNames: colorNames
                    ) == .color else { return false }
                }
                guard colorNames.insert(name).inserted else { return false }
            } else if scalarType(type) {
                guard expressionKind(
                    expression,
                    scalarNames: scalarNames,
                    colorNames: colorNames
                ) == .scalar,
                scalarNames.insert(name).inserted else { return false }
            } else {
                return false
            }
        }
        return returnCount == 1 && (2 ... 16).contains(sampledNames.count)
    }

    private static func expressionKind(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        scalarNames: Set<String>,
        colorNames: Set<String>
    ) -> SceneAuthoredShaderWholeVectorAffineParser.ValueKind? {
        SceneAuthoredShaderWholeVectorAffineParser.parse(
            expression,
            scalarNames: scalarNames,
            colorNames: colorNames
        )
    }

    private static func parameterKinds(
        _ function: SceneAuthoredShaderSyntaxUnit.Function,
        tokens: [SceneAuthoredShaderToken]
    ) -> (scalars: Set<String>, count: Int)? {
        guard !function.parameterRange.contains(where: {
            ["out", "inout"].contains(tokens[$0].text)
        }) else { return nil }
        let slices = commaSeparated(function.parameterRange, tokens: tokens)
        guard let slices, slices.count == 2 else { return nil }
        var scalars: Set<String> = []
        for slice in slices {
            let values = slice.map { tokens[$0] }.filter {
                !["const", "in"].contains($0.text)
            }
            guard values.count == 2,
                  values[0].kind == .identifier,
                  values[1].kind == .identifier else { return nil }
            if scalarType(values[0].text) { scalars.insert(values[1].text) }
        }
        return (scalars, slices.count)
    }

    private static func topLevelStatements(
        in body: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        guard body.count >= 2,
              tokens[body.lowerBound].text == "{",
              tokens[body.upperBound - 1].text == "}" else { return nil }
        var statements: [Range<Int>] = []
        var start = body.lowerBound + 1
        var depth = 0
        for index in start..<(body.upperBound - 1) {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "{", "}": return nil
            case ";" where depth == 0:
                guard start < index else { return nil }
                statements.append(start..<index)
                start = index + 1
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return depth == 0 && start == body.upperBound - 1 ? statements : nil
    }

    private static func uniqueVectorDefinition(
        named name: String,
        before boundary: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Int? {
        let definitions = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < body.upperBound && tokens[index + 1].text == "="
        }
        return definitions.count == 1 ? definitions[0] : nil
    }

    private static func isSingleStatementIf(
        at assignment: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>
    ) -> Bool {
        for index in body where tokens[index].text == "if" {
            guard index + 1 < assignment, tokens[index + 1].text == "(",
                  let close = matchingDelimiter(at: index + 1, tokens: tokens) else {
                continue
            }
            if close + 1 == assignment { return true }
        }
        return false
    }

    private static func isScalarControl(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        before boundary: Int,
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function,
        outputName: String
    ) -> Bool {
        guard expression.count == 1,
              let name = expression.first?.text,
              expression.first?.kind == .identifier,
              name != outputName else { return false }
        if fragment.declarations.contains(where: {
            $0.name == name && scalarType($0.typeName)
        }) { return true }
        let tokens = fragment.tokens
        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound && index < boundary
                && tokens[index].text == name
                && scalarType(tokens[index - 1].text)
                && index + 1 < boundary && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  definition, tokens: tokens, body: main.bodyRange
              ),
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: definition, in: tokens, body: main.bodyRange
                ) else { return false }
        return initializer.first.map {
            ["texSample2D", "texture2D"].contains($0.text)
        } == true || SceneAuthoredShaderWholeVectorAffineParser.parse(
            initializer,
            scalarNames: Set(fragment.declarations.compactMap {
                scalarType($0.typeName) ? $0.name : nil
            }),
            colorNames: []
        ) == .scalar
    }

    private static func scalarType(_ name: String) -> Bool {
        ["bool", "int", "uint", "float"].contains(name)
    }

}

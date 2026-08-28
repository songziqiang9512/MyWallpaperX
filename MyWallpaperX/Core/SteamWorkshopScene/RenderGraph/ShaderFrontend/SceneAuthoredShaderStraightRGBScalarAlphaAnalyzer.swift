import Foundation

nonisolated enum SceneAuthoredShaderStraightColorTerminalTransform:
    Equatable, Sendable
{
    case nonNegativeRGBPreservedAlpha
    case saturateRGBA
}

/// Proves a straight-color source whose RGB is preserved (apart from a
/// terminal clamp) while its alpha is multiplied by a bounded scalar graph.
/// Zero auxiliary textures is valid when the scalar comes entirely from
/// uniforms or linked varyings; any auxiliary texture reads must be distinct
/// direct red-channel scalar reads. One optional direct red-channel opacity
/// mask may restore the original carrier after the alpha mutation.
nonisolated enum SceneAuthoredShaderStraightRGBScalarAlphaAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let sourceSlot: Int
        let scalarAuxiliarySlots: Set<Int>
        let maskSlot: Int?
        let maskFactorName: String?
        let terminalTransform: SceneAuthoredShaderStraightColorTerminalTransform

        var auxiliarySlots: Set<Int> {
            scalarAuxiliarySlots.union(maskSlot.map { [$0] } ?? [])
        }
    }

    static func analyze(
        outputUses: [Int],
        fragment: Unit,
        main: Unit.Function
    ) -> Fact? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              let statements = topLevelStatements(in: main.bodyRange, tokens: tokens),
              (6 ... 20).contains(statements.count),
              statements.last?.contains(output) == true,
              noShadowedBuiltins(fragment),
              !main.bodyRange.contains(where: {
                  ["if", "else", "for", "while", "do", "switch", "discard", "return"]
                      .contains(tokens[$0].text)
              }) else { return nil }

        let globals = Dictionary(uniqueKeysWithValues: fragment.declarations.compactMap {
            declaration -> (String, String)? in
            guard declaration.arraySize == nil,
                  declaration.typeName != "sampler2D" else { return nil }
            return (declaration.name, declaration.typeName)
        })
        var sourceName: String?
        var colorName: String?
        var colorSlot: Int?
        var scalarNames: Set<String> = []
        var scalarAuxiliarySlots: [Int] = []
        var alphaWritten = false
        var pendingMask: (slot: Int, factorName: String)?
        var maskMixed = false
        var terminalTransform: SceneAuthoredShaderStraightColorTerminalTransform?

        for (position, range) in statements.enumerated() {
            let statement = Array(tokens[range])
            if position == statements.count - 1 {
                guard let colorName,
                      let transform = outputStatement(
                          statement, colorName: colorName
                      ) else {
                    return nil
                }
                terminalTransform = transform
                continue
            }
            if let declaration = vectorDeclaration(statement) {
                if sourceName == nil {
                    guard let sample = directColorSample(
                        declaration.expression,
                        globals: globals
                    ) else { return nil }
                    sourceName = declaration.name
                    colorSlot = sample
                } else {
                    guard colorName == nil,
                          declaration.expression.count == 1,
                          declaration.expression[0].text == sourceName else {
                        return nil
                    }
                    colorName = declaration.name
                }
                continue
            }
            guard let sourceName, let colorName, let colorSlot else { return nil }
            if alphaWritten {
                if pendingMask == nil, !maskMixed,
                   let mask = opacityMaskDeclaration(
                       statement,
                       fragment: fragment,
                       sourceName: sourceName,
                       colorName: colorName
                   ), !scalarNames.contains(mask.factorName) {
                    pendingMask = mask
                    continue
                }
                guard let mask = pendingMask,
                      !maskMixed,
                      opacityMaskMix(
                          statement,
                          sourceName: sourceName,
                          colorName: colorName,
                          factorName: mask.factorName
                      ) else { return nil }
                maskMixed = true
                continue
            }
            let context = ScalarContext(
                globals: globals,
                locals: scalarNames,
                colorNames: [sourceName, colorName],
                colorSlot: colorSlot
            )
            if let declaration = scalarDeclaration(statement) {
                guard !scalarNames.contains(declaration.name),
                      let slots = scalarExpression(
                          declaration.expression,
                          context: context
                      ) else { return nil }
                scalarNames.insert(declaration.name)
                scalarAuxiliarySlots.append(contentsOf: slots)
                continue
            }
            if let assignment = scalarAssignment(statement),
               scalarNames.contains(assignment.name) {
                guard ["=", "+="].contains(assignment.operation),
                      let slots = scalarExpression(
                          assignment.expression,
                          context: context
                      ) else { return nil }
                scalarAuxiliarySlots.append(contentsOf: slots)
                continue
            }
            if alphaMultiplication(statement, colorName: colorName) != nil {
                guard !alphaWritten,
                      let expression = alphaMultiplication(
                          statement, colorName: colorName
                      ),
                      let slots = scalarExpression(expression, context: context) else {
                    return nil
                }
                alphaWritten = true
                scalarAuxiliarySlots.append(contentsOf: slots)
                continue
            }
            return nil
        }

        guard let sourceName, let colorName, let colorSlot,
              let terminalTransform,
              alphaWritten,
              (pendingMask == nil && !maskMixed)
                || (pendingMask != nil && maskMixed),
              (0 ... 3).contains(scalarAuxiliarySlots.count),
              Set(scalarAuxiliarySlots).count == scalarAuxiliarySlots.count,
              !scalarAuxiliarySlots.contains(colorSlot),
              pendingMask?.slot != colorSlot,
              pendingMask.map({ !scalarAuxiliarySlots.contains($0.slot) }) ?? true
        else { return nil }
        let body = tokens[main.bodyRange]
        let hasMask = pendingMask != nil
        let terminalColorUseCount = terminalTransform == .saturateRGBA ? 1 : 2
        let identityUseCountsAreExact =
            body.filter({ $0.text == sourceName }).count == (hasMask ? 3 : 2)
            && body.filter({ $0.text == colorName }).count
                == (hasMask ? 4 : 2) + terminalColorUseCount
        let maskFactorUseCountIsExact = pendingMask.map({ mask in
                body.filter({ $0.text == mask.factorName }).count == 2
            }) ?? true
        return identityUseCountsAreExact && maskFactorUseCountIsExact
            ? Fact(
                sourceSlot: colorSlot,
                scalarAuxiliarySlots: Set(scalarAuxiliarySlots),
                maskSlot: pendingMask?.slot,
                maskFactorName: pendingMask?.factorName,
                terminalTransform: terminalTransform
            ) : nil
    }

    private static func opacityMaskDeclaration(
        _ tokens: [Token],
        fragment: Unit,
        sourceName: String,
        colorName: String
    ) -> (slot: Int, factorName: String)? {
        guard let declaration = scalarDeclaration(tokens),
              declaration.name != sourceName,
              declaration.name != colorName,
              declaration.expression.count >= 8,
              declaration.expression.suffix(2).map(\.text) == [".", "r"],
              let slot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(declaration.expression.dropLast(2)),
              fragment.declarations.filter({
                  $0.storage == .uniform && $0.arraySize == nil
                      && $0.typeName == "sampler2D"
                      && $0.name == "g_Texture\(slot)"
              }).count == 1 else { return nil }
        return (slot, declaration.name)
    }

    private static func opacityMaskMix(
        _ tokens: [Token],
        sourceName: String,
        colorName: String,
        factorName: String
    ) -> Bool {
        guard tokens.count >= 8,
              tokens[0].text == colorName,
              tokens[1].text == "=",
              let call = SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .call(tokens[2...]),
              ["mix", "lerp"].contains(call.name),
              call.arguments.count == 3 else { return false }
        return SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .identifier(call.arguments[0]) == sourceName
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(call.arguments[1]) == colorName
            && SceneAuthoredShaderConditionalStraightUnionAnalyzer
                .identifier(call.arguments[2]) == factorName
    }

    private static func noShadowedBuiltins(_ fragment: Unit) -> Bool {
        let protected: Set<String> = [
            "CAST3", "float3", "float4", "lerp", "max", "min", "mix",
            "pow", "sin", "smoothstep", "texSample2D", "texture2D",
            "saturate", "vec3", "vec4",
        ]
        return fragment.functions.allSatisfy {
            $0.name == "main" || !protected.contains($0.name)
        }
    }

    private static func vectorDeclaration(
        _ tokens: [Token]
    ) -> (name: String, expression: [Token])? {
        guard tokens.count >= 4,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].kind == .identifier,
              tokens[2].text == "=" else { return nil }
        return (tokens[1].text, Array(tokens.dropFirst(3)))
    }

    private static func scalarDeclaration(
        _ tokens: [Token]
    ) -> (name: String, expression: [Token])? {
        guard tokens.count >= 4,
              tokens[0].text == "float",
              tokens[1].kind == .identifier,
              tokens[2].text == "=" else { return nil }
        return (tokens[1].text, Array(tokens.dropFirst(3)))
    }

    private static func scalarAssignment(
        _ tokens: [Token]
    ) -> (name: String, operation: String, expression: [Token])? {
        guard tokens.count >= 3,
              tokens[0].kind == .identifier else { return nil }
        return (tokens[0].text, tokens[1].text, Array(tokens.dropFirst(2)))
    }

    private static func alphaMultiplication(
        _ tokens: [Token],
        colorName: String
    ) -> [Token]? {
        guard tokens.count >= 5,
              tokens[0].text == colorName,
              tokens[1].text == ".",
              tokens[2].text == "a",
              tokens[3].text == "*=" else { return nil }
        return Array(tokens.dropFirst(4))
    }

    private static func directColorSample(
        _ expression: [Token],
        globals: [String: String]
    ) -> Int? {
        guard let call = call(expression),
              ["texSample2D", "texture2D"].contains(call.name),
              call.arguments.count == 2,
              call.arguments[0].count == 1,
              let sampler = call.arguments[0].first?.text,
              let slot = textureSlot(sampler),
              safeCoordinate(call.arguments[1], globals: globals, locals: []) else {
            return nil
        }
        return slot
    }

    private static func outputStatement(
        _ statement: [Token],
        colorName: String
    ) -> SceneAuthoredShaderStraightColorTerminalTransform? {
        guard statement.count >= 5,
              statement[0].text == "gl_FragColor",
              statement[1].text == "=",
              let terminal = call(Array(statement.dropFirst(2))) else {
            return nil
        }
        if terminal.name == "saturate",
           terminal.arguments.count == 1,
           texts(terminal.arguments[0]) == [colorName] {
            return .saturateRGBA
        }
        guard ["vec4", "float4"].contains(terminal.name),
              terminal.arguments.count == 2,
              texts(terminal.arguments[1]) == [colorName, ".", "a"],
              let clamp = call(terminal.arguments[0]),
              clamp.name == "max", clamp.arguments.count == 2 else {
            return nil
        }
        let rgb = [colorName, ".", "rgb"]
        return (zeroVector(clamp.arguments[0]) && texts(clamp.arguments[1]) == rgb)
            || (zeroVector(clamp.arguments[1]) && texts(clamp.arguments[0]) == rgb)
            ? .nonNegativeRGBPreservedAlpha : nil
    }

    private static func zeroVector(_ tokens: [Token]) -> Bool {
        guard let value = call(tokens),
              ["vec3", "float3", "CAST3"].contains(value.name),
              value.arguments.count == 1,
              value.arguments[0].count == 1,
              value.arguments[0][0].kind == .number else { return false }
        return Double(value.arguments[0][0].text) == 0
    }

    private static func topLevelStatements(
        in body: Range<Int>,
        tokens: [Token]
    ) -> [Range<Int>]? {
        guard body.count >= 2,
              tokens[body.lowerBound].text == "{",
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

    private static func texts(_ tokens: [Token]) -> [String] {
        tokens.map(\.text)
    }
}

import Foundation

nonisolated extension SceneAuthoredShaderColorTransferAnalyzer {
    /// Proves one unconditional whole-output scalar splat. The scalar may be a
    /// literal or a local `float`; attachment/output ABI separately decides
    /// whether this is color or preserved-channel data. This fact contains no
    /// effect, material, path, or source identity.
    static func isScalarSplatOutput(fragmentSource source: String) -> Bool {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty,
              let fragment = syntax.unit,
              let main = fragment.functions.first(where: { $0.name == "main" }) else {
            return false
        }
        let tokens = fragment.tokens
        let outputUses = tokens.indices.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard outputUses.count == 1,
              let output = outputUses.first,
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              isUnconditionalWrite(output, tokens: tokens, body: main.bodyRange),
              let expression = assignmentExpression(
                  after: output,
                  in: tokens,
                  body: main.bodyRange
              ) else { return false }
        let value = Array(expression)
        guard value.count == 4,
              ["CAST4", "vec4", "float4"].contains(value[0].text),
              value[1].text == "(", value[3].text == ")" else {
            return false
        }
        if value[2].kind == .number { return true }
        guard value[2].kind == .identifier else { return false }
        let scalar = value[2].text
        let declarations = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound
                && index + 1 < output
                && tokens[index].text == scalar
                && tokens[index - 1].text == "float"
                && tokens[index + 1].text == "="
        }
        return declarations.count == 1
    }

    /// Proves an opaque local carrier whose alpha starts at one and whose only
    /// intermediate accesses are RGB-member reads or writes. The RGB math may
    /// be arbitrarily authored; no operation can observe or mutate alpha, so
    /// the final whole-vector output remains opaque without an effect-specific
    /// interpretation.
    static func isOpaqueCarrierOutput(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              output + 1 < tokens.count,
              tokens[output + 1].text == "=",
              main.bodyRange.contains(output),
              isUnconditionalWrite(output, tokens: tokens, body: main.bodyRange),
              let expression = assignmentExpression(
                  after: output,
                  in: tokens,
                  body: main.bodyRange
              ), expression.count == 1,
              let carrierToken = expression.first,
              carrierToken.kind == .identifier else {
            return false
        }
        let carrier = carrierToken.text
        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound && index < output
                && tokens[index].text == carrier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              isUnconditionalWrite(
                  definition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let initializer = assignmentExpression(
                  after: definition,
                  in: tokens,
                  body: main.bodyRange
              ), isOpaqueCarrierInitializer(initializer) else {
            return false
        }
        for use in (definition + 1)..<output where tokens[use].text == carrier {
            guard use + 2 < output,
                  tokens[use + 1].text == ".",
                  ["rgb", "xyz"].contains(tokens[use + 2].text) else {
                return false
            }
        }
        return true
    }

    private static func isOpaqueCarrierInitializer(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        if isOpaqueVectorConstruction(expression) { return true }
        let tokens = Array(expression)
        guard tokens.count == 4,
              ["CAST4", "vec4", "float4"].contains(tokens[0].text),
              tokens[1].text == "(", tokens[3].text == ")",
              tokens[2].kind == .number,
              Double(tokens[2].text) == 1 else {
            return false
        }
        return true
    }

    static func isOpaqueVectorConstruction(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        let tokens = Array(expression)
        guard tokens.count >= 6,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens),
              let comma = topLevelCommas(tokens).last,
              comma + 2 == tokens.count - 1,
              tokens[comma + 1].kind == .number,
              Double(tokens[comma + 1].text) == 1 else {
            return false
        }
        return true
    }

    static func outerCallClosesAtEnd(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        var depth = 0
        for index in 1..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index == tokens.count - 1 }
                if depth < 0 { return false }
            }
        }
        return false
    }

    static func topLevelCommas(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> [Int] {
        var depth = 0
        var result: [Int] = []
        for index in tokens.indices {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" { depth -= 1 }
            if tokens[index].text == ",", depth == 1 { result.append(index) }
        }
        return result
    }
    static func carrierDefinitionIsTopLevel(
        _ definition: Int,
        statements: [Range<Int>]
    ) -> Bool {
        statements.contains { $0.contains(definition) }
    }

    static func containsForbiddenDirectCarrierControlFlow(
        _ body: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        let forbidden: Set<String> = [
            "if", "else", "for", "while", "do", "switch", "case",
            "discard", "return", "break", "continue", "goto", "?",
        ]
        return body.contains { forbidden.contains(tokens[$0].text) }
    }

    static func memberAssignmentExpression(
        after operatorIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        body: Range<Int>,
        boundary: Int
    ) -> ArraySlice<SceneAuthoredShaderToken>? {
        let start = operatorIndex + 1
        guard start < boundary, body.contains(start) else { return nil }
        var parentheses = 0
        var brackets = 0
        var braces = 0
        for index in start..<min(boundary, body.upperBound) {
            switch tokens[index].text {
            case "(": parentheses += 1
            case ")": parentheses -= 1
            case "[": brackets += 1
            case "]": brackets -= 1
            case "{": braces += 1
            case "}": braces -= 1
            case ";" where parentheses == 0 && brackets == 0 && braces == 0:
                return start < index ? tokens[start..<index] : nil
            default: break
            }
            guard parentheses >= 0, brackets >= 0, braces >= 0 else {
                return nil
            }
        }
        return nil
    }

    static func expressionContainsTextureSample(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        expression.contains {
            ["texSample2D", "texture2D"].contains($0.text)
        }
    }

    static func directCarrierRGBExpressionIsSafe(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        carrier: String,
        operation: String,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        guard !expression.contains(where: { $0.text == "?" }),
              !containsBareIdentifier(carrier, in: expression),
              !containsMember(carrier, member: "a", in: expression),
              helperCallsArePureAndUnsampled(
                  fragment: fragment,
                  expressionRanges: [expression.startIndex..<expression.endIndex]
              ) else { return false }
        if operation == "=" {
            return containsMember(carrier, member: "rgb", in: expression)
        }
        return true
    }

    static func directCarrierAlphaExpressionIsSafe(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        carrier: String,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        guard !expression.contains(where: { $0.text == "?" }),
              !containsBareIdentifier(carrier, in: expression),
              !containsMember(carrier, member: "rgb", in: expression),
              !containsOtherMemberAccess(
                  expression, excluding: (carrier, "a")
              ),
              helperCallsArePureAndUnsampled(
                  fragment: fragment,
                  expressionRanges: [expression.startIndex..<expression.endIndex]
              ) else { return false }
        return true
    }

    static func expressionIsOne(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        let values = expression.filter { $0.text != "(" && $0.text != ")" }
        guard values.count == 1, values[0].kind == .number else { return false }
        return Double(values[0].text) == 1
    }

    private static func containsBareIdentifier(
        _ name: String,
        in expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        expression.indices.contains { index in
            expression[index].text == name
                && !(index + 2 < expression.endIndex
                    && expression[index + 1].text == "."
                    && ["rgb", "a"].contains(expression[index + 2].text))
        }
    }

    private static func containsMember(
        _ name: String,
        member: String,
        in expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        expression.indices.contains { index in
            index + 2 < expression.endIndex
                && expression[index].text == name
                && expression[index + 1].text == "."
                && expression[index + 2].text == member
        }
    }

    private static func containsOtherMemberAccess(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        excluding allowed: (String, String)
    ) -> Bool {
        expression.indices.contains { index in
            guard index + 2 < expression.endIndex,
                  expression[index + 1].text == ".",
                  expression[index].kind == .identifier,
                  expression[index + 2].kind == .identifier else {
                return false
            }
            return (expression[index].text, expression[index + 2].text)
                != allowed
        }
    }

    static func helperCallsArePureAndUnsampled(
        fragment: SceneAuthoredShaderSyntaxUnit,
        expressionRanges: [Range<Int>],
        discardingExpression: Bool = false
    ) -> Bool {
        let tokens = fragment.tokens
        let builtins: Set<String> = [
            "abs", "ceil", "clamp", "cos", "dot", "exp", "floor",
            "fract", "length", "log", "max", "min", "mix", "mod",
            "normalize", "pow", "round", "sin", "smoothstep", "sqrt",
            "step", "tan", "saturate", "sign", "vec2", "vec3", "vec4",
            "float2", "float3", "float4", "int2", "int3", "int4",
            "uint2", "uint3", "uint4", "fast", "CAST3",
        ]
        var names: Set<String> = []
        for range in expressionRanges {
            if discardingExpression && tokens[range].contains(where: {
                ["=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
                 "<<=", ">>=", "++", "--"].contains($0.text)
            }) { return false }
            for index in range where index + 1 < range.upperBound {
                guard tokens[index].kind == .identifier,
                      tokens[index + 1].text == "("
                else { continue }
                if index > range.lowerBound && tokens[index - 1].text == "." {
                    if discardingExpression { return false }
                    continue
                }
                names.insert(tokens[index].text)
            }
        }
        for name in names {
            guard !discardingExpression || fragment.defines[name] == nil else {
                return false
            }
            guard let function = fragment.functions.first(where: {
                $0.name == name
            }) else {
                // ApplyBlending is a canonical authored include.  Some
                // prepared sources retain the include directive instead of
                // inlining its helper body, so absence of that declaration is
                // allowed.  Every other unknown call must fail closed.
                guard (builtins.contains(name)
                       && (!discardingExpression || !["fast", "CAST3"].contains(name)))
                    || (discardingExpression
                        && SceneAuthoredShaderValueType(authoredName: name) != nil)
                    || (!discardingExpression && name == "ApplyBlending") else {
                    return false
                }
                continue
            }
            // A user declaration shadows even a built-in spelling (for
            // example `mix`).  Validate that body through the same pure,
            // read-only helper closure instead of trusting the built-in name.
            // The color proof permits read-only helper closures; deletion is
            // narrower and never grants an authored helper that authority.
            guard !discardingExpression, function.name != "main",
                  !tokens[function.parameterRange].contains(where: {
                      ["out", "inout"].contains($0.text)
                  }), let closure = SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                      .safeReadOnlyHelperClosure(
                          rootName: name, fragment: fragment
                      ), closure.allSatisfy({ helper in
                          !tokens[helper.bodyRange].contains(where: {
                              ["texSample2D", "texture2D", "gl_FragColor", "discard",
                               "imageStore"].contains($0.text)
                          })
                      }) else { return false }
        }
        return true
    }


}

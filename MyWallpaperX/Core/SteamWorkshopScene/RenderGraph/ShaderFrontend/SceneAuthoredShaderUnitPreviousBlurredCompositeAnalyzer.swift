import Foundation

/// Proves a bounded two-input composite that keeps both graph colors in the
/// compositor's premultiplied representation. Identity and product effect
/// names are intentionally absent; host material facts separately prove that
/// the tint is unit-valued and both sampler slots select the required graph
/// inputs.
nonisolated enum SceneAuthoredShaderUnitPreviousBlurredCompositeAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    struct Fact: Equatable {
        let blurredSlot: Int
        let previousSlot: Int
        let unitColorUniform: String
    }

    static func analyze(fragmentSource source: String) -> Fact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source, stage: .fragment
            ), stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyze(fragment)
    }

    static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              let statements = directStatements(main.bodyRange, fragment: fragment),
              [7, 8].contains(statements.count) else { return nil }
        let tokens = fragment.tokens
        let coordinate: CoordinateAlias?
        let offset: Int
        if statements.count == 8 {
            coordinate = coordinateDeclaration(
                statements[0], fragment: fragment
            )
            offset = 1
        } else {
            coordinate = nil
            offset = 0
        }
        guard statements.count == 7 || coordinate != nil,
              let blurred = sampledDeclaration(
                  statements[offset], coordinate: coordinate?.name,
                  fragment: fragment
              ), let previous = sampledDeclaration(
                  statements[offset + 1], coordinate: nil,
                  fragment: fragment
              ),
              blurred.slot != previous.slot,
              let mask = scalarLiteralDeclaration(
                  statements[offset + 2], value: 1, tokens: tokens
              ), let divisor = divisorDeclaration(
                  statements[offset + 3], blurred: blurred.name, tokens: tokens
              ), let composite = compositeAssignment(
                  statements[offset + 4], blurred: blurred.name,
                  previous: previous.name, divisor: divisor, tokens: tokens
              ), mixAssignment(
                  statements[offset + 5], blurred: blurred.name,
                  previous: previous.name, mask: mask, tokens: tokens
              ), texts(statements[offset + 6], tokens: tokens) == [
                  "gl_FragColor", "=", blurred.name,
              ], let colorUniform = validateCompositeHelper(
                  named: composite,
                  fragment: fragment
              ), coordinate.map({ wordCount($0.name, fragment: fragment) == 2 })
                    ?? true,
              textureSampleCount(fragment) == 2 else { return nil }
        return .init(
            blurredSlot: blurred.slot,
            previousSlot: previous.slot,
            unitColorUniform: colorUniform
        )
    }

    private struct SampledDeclaration { let name: String; let slot: Int }

    private struct CoordinateAlias { let name: String }

    private static func coordinateDeclaration(
        _ statement: Range<Int>, fragment: Unit
    ) -> CoordinateAlias? {
        let tokens = fragment.tokens
        let values = texts(statement, tokens: tokens)
        guard values.count == 6,
              ["vec2", "float2"].contains(values[0]),
              values[1].isEmpty == false,
              values[2] == "=", values[3].isEmpty == false,
              values[4] == ".", ["xy", "rg"].contains(values[5]) else {
            return nil
        }
        guard hasCoordinateVarying(values[3], fragment: fragment) else {
            return nil
        }
        return .init(name: values[1])
    }

    private static func sampledDeclaration(
        _ statement: Range<Int>, coordinate: String?, fragment: Unit
    ) -> SampledDeclaration? {
        let tokens = fragment.tokens
        guard statement.count >= 9,
              ["vec4", "float4"].contains(tokens[statement.lowerBound].text),
              tokens[statement.lowerBound + 1].kind == .identifier,
              tokens[statement.lowerBound + 2].text == "=" else { return nil }
        let expression = tokens[(statement.lowerBound + 3)..<statement.upperBound]
        guard let slot = SceneAuthoredShaderColorTransferAnalyzer
            .directTextureSampleSlot(expression) else { return nil }
        if let coordinate {
            guard validateCoordinateSample(
                expression,
                slot: slot,
                coordinate: coordinate,
                fragment: fragment
            ) else {
                return nil
            }
        }
        return .init(name: tokens[statement.lowerBound + 1].text, slot: slot)
    }

    private static func validateCoordinateSample(
        _ expression: ArraySlice<Token>, slot: Int, coordinate: String,
        fragment: Unit
    ) -> Bool {
        let values = expression.map(\.text)
        guard let sampler = values.first,
              ["texSample2D", "texture2D"].contains(sampler),
              Array(values.prefix(4)) == [
                  sampler, "(", "g_Texture\(slot)", ",",
              ], values.last == ")" else { return false }
        if Array(values.dropFirst(4).dropLast()) == [coordinate] {
            return true
        }
        guard values.count == 13,
              values[4].isEmpty == false,
              values[5] == "(", values[6] == coordinate,
              values[7] == ",", values[8].isEmpty == false,
              values[9] == ".", values[10] == "xy",
              values[11] == ")", values[12] == ")",
              hasVec4Uniform(values[8], fragment: fragment),
              wordCount(values[8], fragment: fragment) == 2,
              validateCoordinateIdentityHelper(
                  named: values[4], fragment: fragment
              ) else { return false }
        return true
    }

    private static func validateCoordinateIdentityHelper(
        named name: String, fragment: Unit
    ) -> Bool {
        let matches = fragment.functions.filter { $0.name == name }
        guard matches.count == 1, let helper = matches.first,
              wordCount(name, fragment: fragment) == 2,
              let parameters = parameterNames(helper, fragment: fragment),
              parameters.count == 2,
              let statements = directStatements(
                  helper.bodyRange, fragment: fragment
              ), statements.count == 1 else { return false }
        return texts(statements[0], tokens: fragment.tokens)
            == ["return", parameters[0]]
    }

    private static func scalarLiteralDeclaration(
        _ statement: Range<Int>, value: Double, tokens: [Token]
    ) -> String? {
        guard statement.count == 4,
              tokens[statement.lowerBound].text == "float",
              tokens[statement.lowerBound + 1].kind == .identifier,
              tokens[statement.lowerBound + 2].text == "=",
              Double(tokens[statement.lowerBound + 3].text) == value else {
            return nil
        }
        return tokens[statement.lowerBound + 1].text
    }

    private static func divisorDeclaration(
        _ statement: Range<Int>, blurred: String, tokens: [Token]
    ) -> String? {
        let values = texts(statement, tokens: tokens)
        guard values.count == 20,
              values[0] == "float", values[1].isEmpty == false,
              Array(values.dropFirst(2)) == [
                  "=", "mix", "(", blurred, ".", "a", ",", "1", ",",
                  "step", "(", blurred, ".", "a", ",", "0", ")", ")",
              ] else { return nil }
        return values[1]
    }

    private static func compositeAssignment(
        _ statement: Range<Int>, blurred: String, previous: String,
        divisor: String, tokens: [Token]
    ) -> String? {
        let values = texts(statement, tokens: tokens)
        guard values.count == 19, values[0] == blurred, values[1] == "=",
              values[2].isEmpty == false,
              Array(values.dropFirst(3)) == [
                  "(", previous, ",", "vec4", "(", blurred, ".", "rgb", "/",
                  divisor, ",", blurred, ".", "a", ")", ")",
              ] else { return nil }
        return values[2]
    }

    private static func mixAssignment(
        _ statement: Range<Int>, blurred: String, previous: String,
        mask: String, tokens: [Token]
    ) -> Bool {
        texts(statement, tokens: tokens) == [
            blurred, "=", "mix", "(", previous, ",", blurred, ",", mask, ")",
        ]
    }

    private static func validateCompositeHelper(
        named name: String, fragment: Unit
    ) -> String? {
        let matches = fragment.functions.filter { $0.name == name }
        guard matches.count == 1, let helper = matches.first,
              let parameters = parameterNames(helper, fragment: fragment),
              parameters.count == 2,
              let statements = directStatements(
                  helper.bodyRange, fragment: fragment
              ), (2 ... 3).contains(statements.count) else { return nil }
        let tokens = fragment.tokens
        let base = parameters[0], effect = parameters[1]
        let mutation = texts(statements[0], tokens: tokens)
        guard mutation.count == 5,
              Array(mutation.prefix(4)) == [effect, ".", "rgb", "*="],
              mutation[4].isEmpty == false else { return nil }
        let uniform = mutation[4]
        let returns = statements.dropFirst().map { statement in
            texts(statement, tokens: tokens)
        }
        if returns.allSatisfy({ $0 == ["return", effect] }) {
            return hasVec3Uniform(uniform, fragment: fragment) ? uniform : nil
        }
        guard returns.count == 1, let returned = returns.first else {
            return nil
        }
        guard returned.count == 7, returned[0] == "return",
              returned[1].isEmpty == false,
              Array(returned.dropFirst(2)) == ["(", base, ",", effect, ")"],
              validateIdentityHelper(
                  named: returned[1], fragment: fragment
              ) else { return nil }
        return hasVec3Uniform(uniform, fragment: fragment) ? uniform : nil
    }

    private static func validateIdentityHelper(
        named name: String, fragment: Unit
    ) -> Bool {
        let matches = fragment.functions.filter { $0.name == name }
        guard matches.count == 1, let helper = matches.first,
              let parameters = parameterNames(helper, fragment: fragment),
              parameters.count == 2,
              let statements = directStatements(
                  helper.bodyRange, fragment: fragment
              ), statements.count == 1 else { return false }
        return texts(statements[0], tokens: fragment.tokens)
            == ["return", parameters[1]]
    }

    private static func parameterNames(
        _ function: Unit.Function, fragment: Unit
    ) -> [String]? {
        let tokens = fragment.tokens
        var result: [String] = [], start = function.parameterRange.lowerBound
        var depth = 0
        for index in function.parameterRange {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard let name = tokens[start..<index].last(where: {
                    $0.kind == .identifier
                })?.text else { return nil }
                result.append(name); start = index + 1
            default: break
            }
        }
        guard start < function.parameterRange.upperBound,
              let name = tokens[start..<function.parameterRange.upperBound]
                .last(where: { $0.kind == .identifier })?.text else { return nil }
        result.append(name)
        return depth == 0 ? result : nil
    }

    private static func directStatements(
        _ body: Range<Int>, fragment: Unit
    ) -> [Range<Int>]? {
        let tokens = fragment.tokens
        var result: [Range<Int>] = [], start = body.lowerBound + 1
        var depth = 0
        for index in (body.lowerBound + 1)..<(body.upperBound - 1) {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "{", "}": return nil
            case ";" where depth == 0:
                guard start < index else { return nil }
                result.append(start..<index); start = index + 1
            default: break
            }
        }
        return depth == 0 && start == body.upperBound - 1 ? result : nil
    }

    private static func hasVec3Uniform(_ name: String, fragment: Unit) -> Bool {
        let tokens = fragment.tokens
        return tokens.indices.filter { index in
            index >= 2 && tokens[index].text == name
                && tokens[index - 2].text == "uniform"
                && ["vec3", "float3"].contains(tokens[index - 1].text)
        }.count == 1
    }

    private static func hasCoordinateVarying(
        _ name: String, fragment: Unit
    ) -> Bool {
        let tokens = fragment.tokens
        return tokens.indices.filter { index in
            index >= 2 && tokens[index].text == name
                && tokens[index - 2].text == "varying"
                && ["vec2", "float2", "vec4", "float4"].contains(
                    tokens[index - 1].text
                )
        }.count == 1
    }

    private static func hasVec4Uniform(_ name: String, fragment: Unit) -> Bool {
        let tokens = fragment.tokens
        return tokens.indices.filter { index in
            index >= 2 && tokens[index].text == name
                && tokens[index - 2].text == "uniform"
                && ["vec4", "float4"].contains(tokens[index - 1].text)
        }.count == 1
    }

    private static func wordCount(_ name: String, fragment: Unit) -> Int {
        fragment.tokens.filter { $0.text == name }.count
    }

    private static func textureSampleCount(_ fragment: Unit) -> Int {
        fragment.tokens.filter {
            ["texSample2D", "texture2D"].contains($0.text)
        }.count
    }

    private static func texts(
        _ range: Range<Int>, tokens: [Token]
    ) -> [String] { range.map { tokens[$0].text } }
}

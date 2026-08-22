import Foundation

/// Proves one prepared-source RGBA signal carrier that is initialized from a
/// single whole texture sample and then updated by pure bounded helpers. The
/// fact describes independent data channels, not compositable straight color.
nonisolated enum SceneAuthoredShaderIndependentSignalCarrierAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private enum ValueRole: Equatable { case carrier, bounded01, other }
    private struct Call { let name: String; let arguments: [[Token]] }
    private struct Sample { let index: Int; let slot: Int; let projection: String? }

    static func analyze(_ fragment: Unit) -> Int? {
        guard fragment.stage == .fragment,
              let main = uniqueFunction(named: "main", fragment: fragment),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens),
              (2 ... 64).contains(statements.count),
              let samples = sampleCalls(tokens: fragment.tokens),
              let source = singleSignalSample(samples, fragment: fragment, main: main)
        else { return nil }
        let dataSlots = Set(samples.filter { $0.index != source.index }.map(\.slot))

        let outputStatements = statements.filter { range in
            range.contains { fragment.tokens[$0].text == "gl_FragColor" }
        }
        let mappedOutputUses = Set(outputStatements.flatMap { range in
            range.filter { fragment.tokens[$0].text == "gl_FragColor" }
        })
        let allOutputUses = Set(fragment.tokens.indices.filter {
            fragment.tokens[$0].text == "gl_FragColor"
        })
        guard mappedOutputUses == allOutputUses,
              (2 ... 9).contains(outputStatements.count),
              let initialization = outputStatements.first,
              let carrier = initializedCarrier(
                  statement: Array(fragment.tokens[initialization]),
                  before: initialization.lowerBound,
                  expectedSlot: source.slot,
                  dataSlots: dataSlots,
                  statements: statements,
                  fragment: fragment
              ) else { return nil }
        for range in outputStatements.dropFirst() {
            guard range.lowerBound > initialization.lowerBound,
                  safeHelperUpdate(
                      statement: Array(fragment.tokens[range]),
                      fragment: fragment
                  ) else { return nil }
        }
        guard safeCarrierUses(
            carrier,
            before: initialization.lowerBound,
            dataSlots: dataSlots,
            statements: statements,
            fragment: fragment
        ) else { return nil }
        return source.slot
    }

    private static func singleSignalSample(
        _ samples: [Sample], fragment: Unit, main: Unit.Function
    ) -> Sample? {
        let whole = samples.filter { $0.projection == nil }
        guard whole.count == 1, let source = whole.first,
              main.bodyRange.contains(source.index),
              samplerType(slot: source.slot, fragment: fragment) == "sampler2D"
        else { return nil }
        for sample in samples where sample.index != source.index {
            guard main.bodyRange.contains(sample.index),
                  sample.slot != source.slot,
                  samplerType(slot: sample.slot, fragment: fragment) == "sampler2D",
                  ["r", "x", "rg", "xy"].contains(sample.projection ?? "")
            else { return nil }
        }
        return source
    }

    private static func initializedCarrier(
        statement: [Token],
        before output: Int,
        expectedSlot: Int,
        dataSlots: Set<Int>,
        statements: [Range<Int>],
        fragment: Unit
    ) -> String? {
        guard statement.count >= 3, statement[0].text == "gl_FragColor",
              statement[1].text == "=",
              !statement.dropFirst(2).contains(where: { $0.text == "gl_FragColor" })
        else { return nil }
        let expression = Array(statement.dropFirst(2))
        let identifiers = Set(expression.filter { $0.kind == .identifier }.map(\.text))
        let definitions = statements.filter { range in
            guard range.lowerBound < output else { return false }
            let value = Array(fragment.tokens[range])
            return value.count >= 6
                && ["vec4", "float4"].contains(value[0].text)
                && identifiers.contains(value[1].text)
                && value[2].text == "="
                && directSampleSlot(Array(value.dropFirst(3))) == expectedSlot
        }
        guard definitions.count == 1, let definition = definitions.first else {
            return nil
        }
        let carrier = Array(fragment.tokens[definition])[1].text
        let state = SceneAuthoredShaderIndependentSignalScalarContract.state(
            before: output, carrier: carrier, dataSlots: dataSlots,
            statements: statements, fragment: fragment
        )
        guard expression.filter({ $0.text == carrier }).count == 1,
              scalarTransform(
                  expression, of: carrier, state: state,
                  dataSlots: dataSlots, fragment: fragment
              ) else { return nil }
        return carrier
    }

    private static func scalarTransform(
        _ expression: [Token],
        of carrier: String,
        state: SceneAuthoredShaderIndependentSignalScalarContract.State,
        dataSlots: Set<Int>,
        fragment: Unit
    ) -> Bool {
        if expression.count == 1 { return expression[0].text == carrier }
        guard expression.count >= 3, expression[0].text == carrier,
              ["/", "*"].contains(expression[1].text) else { return false }
        return SceneAuthoredShaderIndependentSignalScalarContract.isScalar(
            Array(expression.dropFirst(2)), state: state,
            dataSlots: dataSlots, fragment: fragment
        )
    }

    private static func safeCarrierUses(
        _ carrier: String,
        before output: Int,
        dataSlots: Set<Int>,
        statements: [Range<Int>],
        fragment: Unit
    ) -> Bool {
        let tokens = fragment.tokens
        let definitions = statements.filter { range in
            let value = Array(tokens[range])
            return range.lowerBound < output && value.count >= 4
                && ["vec4", "float4"].contains(value[0].text)
                && value[1].text == carrier && value[2].text == "="
        }
        guard definitions.count == 1 else { return false }
        for range in statements where range.lowerBound < output {
            let value = Array(tokens[range])
            guard value.contains(where: { $0.text == carrier }) else { continue }
            if range == definitions[0] { continue }
            if value.first?.text == carrier {
                let state = SceneAuthoredShaderIndependentSignalScalarContract.state(
                    before: range.lowerBound, carrier: carrier,
                    dataSlots: dataSlots, statements: statements,
                    fragment: fragment
                )
                guard value.count >= 3,
                      value.filter({ $0.text == carrier }).count == 1,
                      ["*=", "/="].contains(value[1].text),
                      SceneAuthoredShaderIndependentSignalScalarContract.isScalar(
                          Array(value.dropFirst(2)), state: state,
                          dataSlots: dataSlots, fragment: fragment
                      ) else { return false }
                continue
            }
            let state = SceneAuthoredShaderIndependentSignalScalarContract.state(
                before: range.lowerBound, carrier: carrier,
                dataSlots: dataSlots, statements: statements,
                fragment: fragment
            )
            guard SceneAuthoredShaderIndependentSignalScalarContract
                .isCarrierRGBScalarDeclaration(
                    value, carrier: carrier, state: state,
                    dataSlots: dataSlots, fragment: fragment
            ) else { return false }
        }
        return true
    }

    private static func safeHelperUpdate(statement: [Token], fragment: Unit) -> Bool {
        guard statement.count >= 5, statement[0].text == "gl_FragColor",
              statement[1].text == "=",
              let rootCall = call(Array(statement.dropFirst(2))),
              rootCall.arguments.filter({
                  $0.count == 1 && $0[0].text == "gl_FragColor"
              }).count == 1,
              statement.filter({ $0.text == "gl_FragColor" }).count == 2,
              let closure = SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                .safeHelperClosure(rootName: rootCall.name, fragment: fragment),
              let root = closure.first(where: { $0.name == rootCall.name }),
              let parameters = parameters(root, tokens: fragment.tokens),
              parameters.count == rootCall.arguments.count else { return false }
        let roles = Dictionary(uniqueKeysWithValues:
            zip(parameters, rootCall.arguments).map { parameter, argument in
                (parameter, role(argument, environment: [:], fragment: fragment))
            }
        )
        return safeReturn(
            root, roles: roles, closure: Set(closure.map(\.name)),
            fragment: fragment, visited: []
        )
    }

    private static func safeReturn(
        _ function: Unit.Function,
        roles initial: [String: ValueRole],
        closure: Set<String>,
        fragment: Unit,
        visited: Set<String>
    ) -> Bool {
        guard !visited.contains(function.name),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: function.bodyRange, tokens: fragment.tokens),
              (1 ... 16).contains(statements.count), let last = statements.last,
              initial.values.filter({ $0 == .carrier }).count == 1,
              let carrier = initial.first(where: { $0.value == .carrier })?.key
        else { return false }
        var roles = initial
        for range in statements.dropLast() {
            let value = Array(fragment.tokens[range])
            // A carrier is only proven when it flows directly into the
            // terminal bounded expression or the one nested helper argument.
            // Earlier reads can hide an alias and earlier writes can replace
            // the sampled value, so both fail closed.
            guard !value.contains(where: { $0.text == carrier }) else {
                return false
            }
            if value.count >= 4, value[0].text == "float",
               value[1].kind == .identifier, value[2].text == "=" {
                roles[value[1].text] = role(
                    Array(value.dropFirst(3)), environment: roles,
                    fragment: fragment
                )
            }
        }
        let returned = Array(fragment.tokens[last])
        guard returned.count >= 2, returned[0].text == "return" else { return false }
        let expression = Array(returned.dropFirst())
        guard expression.filter({ $0.text == carrier }).count == 1 else {
            return false
        }
        if boundedCarrierExpression(
            expression, roles: roles, fragment: fragment
        ) { return true }
        guard let nested = call(expression), closure.contains(nested.name),
              let callee = uniqueFunction(named: nested.name, fragment: fragment),
              let parameters = parameters(callee, tokens: fragment.tokens),
              parameters.count == nested.arguments.count,
              nested.arguments.filter({ argument in
                  argument.contains(where: { $0.text == carrier })
              }).count == 1 else { return false }
        let next = Dictionary(uniqueKeysWithValues:
            zip(parameters, nested.arguments).map { parameter, argument in
                (parameter, role(
                    argument, environment: roles, fragment: fragment
                ))
            }
        )
        return next.values.filter({ $0 == .carrier }).count == 1
            && safeReturn(
                callee, roles: next, closure: closure, fragment: fragment,
                visited: visited.union([function.name])
            )
    }

    private static func boundedCarrierExpression(
        _ tokens: [Token], roles: [String: ValueRole], fragment: Unit
    ) -> Bool {
        guard let outer = call(tokens), outer.name == "min",
              outer.arguments.count == 2,
              !hasAuthoredFunction(named: outer.name, fragment: fragment)
        else { return false }
        let firstUnit = unitVector(outer.arguments[0])
        let secondUnit = unitVector(outer.arguments[1])
        guard firstUnit != secondUnit else { return false }
        let sum = firstUnit ? outer.arguments[1] : outer.arguments[0]
        guard let operands = binary(sum, operation: "+") else { return false }
        let firstCarrier = role(
            operands.0, environment: roles, fragment: fragment
        ) == .carrier
        let secondCarrier = role(
            operands.1, environment: roles, fragment: fragment
        ) == .carrier
        guard firstCarrier != secondCarrier else { return false }
        let injected = firstCarrier ? operands.1 : operands.0
        guard let vector = call(injected),
              ["CAST4", "vec4", "float4"].contains(vector.name),
              vector.arguments.count == 1 else { return false }
        return role(
            vector.arguments[0], environment: roles, fragment: fragment
        ) == .bounded01
    }

    private static func role(
        _ tokens: [Token], environment: [String: ValueRole], fragment: Unit
    ) -> ValueRole {
        if tokens.count == 1 {
            if tokens[0].text == "gl_FragColor" { return .carrier }
            return environment[tokens[0].text] ?? .other
        }
        let builtinArities = [
            "saturate": 1, "frac": 1, "fract": 1,
            "step": 2, "smoothstep": 3,
        ]
        guard let value = call(tokens),
              builtinArities[value.name] == value.arguments.count,
              value.arguments.allSatisfy({ !$0.isEmpty }),
              !hasAuthoredFunction(named: value.name, fragment: fragment),
              !tokens.contains(where: {
                  ["gl_FragColor", "texSample2D", "texture2D", "imageStore"].contains($0.text)
              }) else { return .other }
        return .bounded01
    }

    private static func hasAuthoredFunction(
        named name: String,
        fragment: Unit
    ) -> Bool {
        fragment.functions.contains(where: { $0.name == name })
    }

    private static func unitVector(_ tokens: [Token]) -> Bool {
        guard let value = call(tokens),
              ["CAST4", "vec4", "float4"].contains(value.name),
              value.arguments.count == 1, value.arguments[0].count == 1,
              value.arguments[0][0].kind == .number,
              Double(value.arguments[0][0].text) == 1 else { return false }
        return true
    }

    private static func binary(
        _ tokens: [Token], operation: String
    ) -> ([Token], [Token])? {
        var depth = 0
        for index in tokens.indices {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case operation where depth == 0:
                guard index > 0, index + 1 < tokens.count else { return nil }
                return (Array(tokens[..<index]), Array(tokens[(index + 1)...]))
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    private static func parameters(_ function: Unit.Function, tokens: [Token]) -> [String]? {
        guard let ranges = commaRanges(function.parameterRange, tokens: tokens) else { return nil }
        var result: [String] = []
        var names = Set<String>()
        for range in ranges {
            let part = Array(tokens[range]).filter { !["const", "in"].contains($0.text) }
            guard part.count == 2, part[0].kind == .identifier,
                  part[1].kind == .identifier,
                  names.insert(part[1].text).inserted else { return nil }
            result.append(part[1].text)
        }
        return result
    }

    private static func directSampleSlot(_ tokens: [Token]) -> Int? {
        guard let value = call(tokens),
              ["texSample2D", "texture2D"].contains(value.name),
              value.arguments.count == 2, value.arguments[0].count == 1 else { return nil }
        return textureSlot(value.arguments[0][0].text)
    }

    private static func call(_ tokens: [Token]) -> Call? {
        guard tokens.count >= 3, tokens[0].kind == .identifier, tokens[1].text == "(",
              matchingDelimiter(at: 1, tokens: tokens) == tokens.count - 1,
              let ranges = commaRanges(2..<(tokens.count - 1), tokens: tokens)
        else { return nil }
        return .init(name: tokens[0].text, arguments: ranges.map { Array(tokens[$0]) })
    }

    private static func sampleCalls(tokens: [Token]) -> [Sample]? {
        var result: [Sample] = []
        for index in tokens.indices where ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 3 < tokens.count, tokens[index + 1].text == "(",
                  let slot = textureSlot(tokens[index + 2].text), tokens[index + 3].text == ",",
                  let close = matchingDelimiter(at: index + 1, tokens: tokens) else { return nil }
            let projection = close + 2 < tokens.count && tokens[close + 1].text == "."
                ? tokens[close + 2].text : nil
            result.append(.init(index: index, slot: slot, projection: projection))
        }
        return result
    }

    private static func uniqueFunction(named name: String, fragment: Unit) -> Unit.Function? {
        let matches = fragment.functions.filter { $0.name == name }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func samplerType(slot: Int, fragment: Unit) -> String? {
        fragment.declarations.first(where: {
            $0.storage == .uniform && $0.name == "g_Texture\(slot)" && $0.arraySize == nil
        })?.typeName
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ... 7).contains(slot) else { return nil }
        return slot
    }

    private static func commaRanges(_ range: Range<Int>, tokens: [Token]) -> [Range<Int>]? {
        guard !range.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if ["(", "[", "{"].contains(tokens[index].text) { depth += 1 }
            if [")", "]", "}"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == ",", depth == 0 {
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    private static func matchingDelimiter(at index: Int, tokens: [Token]) -> Int? {
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]
        guard tokens.indices.contains(index), let closing = pairs[tokens[index].text] else { return nil }
        var depth = 0
        for cursor in index..<tokens.count {
            if tokens[cursor].text == tokens[index].text { depth += 1 }
            if tokens[cursor].text == closing {
                depth -= 1
                if depth == 0 { return cursor }
            }
        }
        return nil
    }
}

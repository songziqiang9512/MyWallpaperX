import Foundation

/// Proves one prepared-source RGBA signal carrier that is initialized from a
/// single whole texture sample and then updated by pure bounded helpers. The
/// fact describes independent data channels, not compositable straight color.
nonisolated enum SceneAuthoredShaderIndependentSignalCarrierAnalyzer {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private struct AuxiliaryValue: Equatable {
        let slot: Int
        let sampleIndex: Int
        let width: Int
        let channels: UInt8 // RGB=1, alpha=2; identities may never be merged.
        var rgbUsesAlpha = false
        var hasSourceAlpha = false
    }
    private enum ValueRole: Equatable {
        case carrier, bounded01, scalar, other
        case auxiliary(AuxiliaryValue)
        case rgbaInjection(Int)
    }
    private struct ScalarContext {
        let state: SceneAuthoredShaderIndependentSignalScalarContract.State
        let dataSlots: Set<Int>
    }
    private struct Call { let name: String; let arguments: [[Token]] }
    private struct Sample { let index: Int; let slot: Int; let projection: String? }

    static func analyze(_ fragment: Unit) -> Int? {
        guard fragment.stage == .fragment,
              let main = uniqueFunction(named: "main", fragment: fragment),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer
                .topLevelStatements(in: main.bodyRange, tokens: fragment.tokens),
              (2 ... 64).contains(statements.count),
              let samples = sampleCalls(tokens: fragment.tokens),
              let auxiliarySlots = rgbaAuxiliarySlots(samples, fragment: fragment),
              let source = singleSignalSample(
                  samples, auxiliarySlots: auxiliarySlots,
                  fragment: fragment, main: main
              )
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
        let environments = auxiliaryEnvironments(
            statements: statements, samples: samples, auxiliarySlots: auxiliarySlots,
            dataSlots: dataSlots, carrier: carrier, fragment: fragment
        )
        for range in outputStatements.dropFirst() {
            let context = ScalarContext(
                state: SceneAuthoredShaderIndependentSignalScalarContract.state(
                    before: range.lowerBound, carrier: carrier,
                    dataSlots: dataSlots, statements: statements, fragment: fragment
                ), dataSlots: dataSlots
            )
            guard range.lowerBound > initialization.lowerBound,
                  safeHelperUpdate(
                      statement: Array(fragment.tokens[range]),
                      range: range,
                      environment: environments[range.lowerBound] ?? [:],
                      context: context, fragment: fragment
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
        _ samples: [Sample], auxiliarySlots: Set<Int>,
        fragment: Unit, main: Unit.Function
    ) -> Sample? {
        let whole = samples.filter {
            $0.projection == nil && !auxiliarySlots.contains($0.slot)
        }
        guard whole.count == 1, let source = whole.first,
              main.bodyRange.contains(source.index),
              samplerType(slot: source.slot, fragment: fragment) == "sampler2D"
        else { return nil }
        for sample in samples where sample.index != source.index {
            guard main.bodyRange.contains(sample.index),
                  sample.slot != source.slot,
                  samplerType(slot: sample.slot, fragment: fragment) == "sampler2D",
                  (["r", "x", "rg", "xy"].contains(sample.projection ?? "")
                    || (sample.projection == nil && auxiliarySlots.contains(sample.slot)))
            else { return nil }
        }
        return source
    }

    /// The contract parser owns annotation syntax and declaration association.
    /// An untyped second RGBA sample cannot become data from its use or name.
    private static func rgbaAuxiliarySlots(
        _ samples: [Sample], fragment: Unit
    ) -> Set<Int>? {
        guard samples.filter({ $0.projection == nil }).count > 1 else { return [] }
        guard let source = fragment.source else { return nil }
        let parsed = SceneShaderContractSourceParser().parse(source, stageRelativePath: "")
        guard parsed.diagnostics.isEmpty else { return nil }
        var result = Set<Int>()
        for slot in Set(samples.map(\.slot)) {
            let name = "g_Texture\(slot)"
            let declarations = parsed.declarations.filter { $0.name == name }
            let syntax = fragment.declarations.filter { $0.name == name }
            guard declarations.count == 1, syntax.count == 1,
                  let declaration = declarations.first,
                  declaration.type == "sampler2D", declaration.arraySize == nil,
                  declaration.line == syntax.first?.line else { return nil }
            let annotations = parsed.annotations.filter { $0.line == declaration.line }
            guard annotations.count <= 1 else { return nil }
            if let annotation = annotations.first,
               case let .object(values) = annotation.value,
               values["mode"]?.stringValue?.lowercased() == "rgbmask" {
                result.insert(slot)
            }
        }
        return result
    }

    /// Ordered local provenance reuses the existing top-level statement ranges.
    /// Unknown writes/escapes revoke a local fact before a later update uses it.
    private static func auxiliaryEnvironments(
        statements: [Range<Int>], samples: [Sample],
        auxiliarySlots: Set<Int>, dataSlots: Set<Int>,
        carrier: String, fragment: Unit
    ) -> [Int: [String: ValueRole]] {
        guard !auxiliarySlots.isEmpty else { return [:] }
        var result: [Int: [String: ValueRole]] = [:]
        var environment: [String: ValueRole] = [:]
        var declarations = Set<String>()
        for range in statements {
            let value = Array(fragment.tokens[range])
            if value.contains(where: { $0.text == "gl_FragColor" }) {
                result[range.lowerBound] = environment
                continue
            }
            let context = ScalarContext(
                state: SceneAuthoredShaderIndependentSignalScalarContract.state(
                    before: range.lowerBound, carrier: carrier, dataSlots: dataSlots,
                    statements: statements, fragment: fragment
                ), dataSlots: dataSlots
            )
            if value.count >= 4,
               ["float", "vec3", "vec4", "float3", "float4"].contains(value[0].text),
               value[1].kind == .identifier, value[2].text == "=" {
                let name = value[1].text
                guard declarations.insert(name).inserted else {
                    environment[name] = .other
                    continue
                }
                let expression = Array(value.dropFirst(3))
                if let slot = directSampleSlot(expression), auxiliarySlots.contains(slot),
                   ["vec4", "float4"].contains(value[0].text),
                   let sample = samples.first(where: { range.contains($0.index) }) {
                    environment[name] = .auxiliary(.init(
                        slot: slot, sampleIndex: sample.index,
                        width: 4, channels: 3, hasSourceAlpha: true
                    ))
                } else {
                    let resolved = role(expression, environment: environment,
                                        context: context, fragment: fragment)
                    if resolved == .other {
                        for input in environment.keys where expression.contains(where: { $0.text == input }) {
                            environment[input] = .other
                        }
                    }
                    environment[name] = resolved
                }
                continue
            }
            if value.count >= 5, value[1].text == ".",
               ["rgb", "xyz"].contains(value[2].text),
               ["=", "*="].contains(value[3].text),
               case var .auxiliary(current)? = environment[value[0].text],
               current.width == 4 {
                let rhs = role(Array(value.dropFirst(4)), environment: environment,
                               context: context, fragment: fragment)
                if case let .auxiliary(part) = rhs, part.sampleIndex == current.sampleIndex,
                   (value[3].text == "*=" && part.width == 1
                        || value[3].text == "=" && part.width == 3
                            && part.channels & 1 != 0) {
                    current.rgbUsesAlpha = current.rgbUsesAlpha || part.channels & 2 != 0
                    environment[value[0].text] = .auxiliary(current)
                    continue
                }
            }
            for name in environment.keys where value.contains(where: { $0.text == name }) {
                environment[name] = .other
            }
        }
        return result
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

    static func scalarTransform(
        _ rawExpression: [Token],
        of carrier: String,
        state: SceneAuthoredShaderIndependentSignalScalarContract.State,
        dataSlots: Set<Int>,
        fragment: Unit
    ) -> Bool {
        let expression = Array(SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(rawExpression[...]))
        if expression.count == 1 { return expression[0].text == carrier }
        // A scalar suffix may contain addition only inside parentheses:
        // carrier * x + y adds a vector, whereas carrier * (x + y) scales it.
        var depth = 0
        var product: Int?
        for index in expression.indices {
            let token = expression[index].text
            if ["(", "["].contains(token) { depth += 1 }
            if [")", "]"].contains(token) { depth -= 1 }
            if depth == 0 {
                if ["+", "-"].contains(token) { return false }
                if product == nil, ["*", "/"].contains(token) { product = index }
            }
        }
        guard let product, product > 0, product + 1 < expression.count else { return false }
        typealias Calls = SceneAuthoredShaderConditionalStraightUnionAnalyzer
        let lhs = Calls.strippingParentheses(expression[..<product])
        let rhs = Calls.strippingParentheses(expression[(product + 1)...])
        let scalar: ArraySlice<Token>
        if Calls.identifier(lhs) == carrier {
            scalar = rhs
        } else if expression[product].text == "*", Calls.identifier(rhs) == carrier {
            scalar = lhs
        } else { return false }
        return SceneAuthoredShaderIndependentSignalScalarContract.isScalar(
            Array(scalar), state: state, dataSlots: dataSlots, fragment: fragment
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

    private static func safeHelperUpdate(
        statement: [Token], range: Range<Int>, environment: [String: ValueRole],
        context: ScalarContext, fragment: Unit
    ) -> Bool {
        guard statement.count >= 5, statement[0].text == "gl_FragColor",
              statement[1].text == "=",
              statement.filter({ $0.text == "gl_FragColor" }).count == 2
        else { return false }
        let expression = Array(statement.dropFirst(2))
        var roles = environment
        roles["gl_FragColor"] = .carrier
        let expressionRange = (range.lowerBound + 2)..<range.upperBound
        if boundedCarrierExpression(expression, roles: roles,
                                    context: context, fragment: fragment),
           pureValueCalls([expressionRange], fragment: fragment) { return true }
        guard let rootCall = call(expression),
              rootCall.arguments.filter({
                  $0.count == 1 && $0[0].text == "gl_FragColor"
              }).count == 1,
              let closure = SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer
                .safeHelperClosure(rootName: rootCall.name, fragment: fragment),
              let root = closure.first(where: { $0.name == rootCall.name }),
              let parameters = parameters(root, tokens: fragment.tokens),
              parameters.count == rootCall.arguments.count else { return false }
        let parameterRoles = Dictionary(uniqueKeysWithValues:
            zip(parameters, rootCall.arguments).map { parameter, argument in
                (parameter, role(argument, environment: roles,
                                 context: context, fragment: fragment))
            }
        )
        if hasAuxiliaryValue(parameterRoles),
           !pureCallArguments(expressionRange, fragment: fragment) { return false }
        return safeReturn(
            root, roles: parameterRoles, closure: Set(closure.map(\.name)),
            context: context, fragment: fragment, visited: []
        )
    }

    private static func safeReturn(
        _ function: Unit.Function,
        roles initial: [String: ValueRole],
        closure: Set<String>,
        context: ScalarContext,
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
        let hasAuxiliaryInput = hasAuxiliaryValue(initial)
        if hasAuxiliaryInput,
           !pureValueCalls(Array(statements.dropLast()), fragment: fragment) { return false }
        for range in statements.dropLast() {
            let value = Array(fragment.tokens[range])
            if value.count >= 2,
               ["float", "vec3", "vec4", "float3", "float4"].contains(value[0].text),
               value[1].kind == .identifier {
                roles[value[1].text] = .other
            }
        }
        for range in statements.dropLast() {
            let value = Array(fragment.tokens[range])
            // A carrier is only proven when it flows directly into the
            // terminal bounded expression or the one nested helper argument.
            // Earlier reads can hide an alias and earlier writes can replace
            // the sampled value, so both fail closed.
            guard !value.contains(where: { $0.text == carrier }) else {
                return false
            }
            if value.count >= 4,
               ["float", "vec3", "vec4", "float3", "float4"].contains(value[0].text),
               value[1].kind == .identifier, value[2].text == "=" {
                roles[value[1].text] = role(Array(value.dropFirst(3)), environment: roles,
                                          context: context, fragment: fragment)
                if hasAuxiliaryInput, roles[value[1].text] == .other { return false }
            } else if hasAuxiliaryInput {
                // A raw-data argument must not escape through a statement
                // outside the existing ordered value/terminal return proof.
                return false
            }
        }
        let returned = Array(fragment.tokens[last])
        guard returned.count >= 2, returned[0].text == "return" else { return false }
        let expression = Array(returned.dropFirst())
        guard expression.filter({ $0.text == carrier }).count == 1 else {
            return false
        }
        if boundedCarrierExpression(
            expression, roles: roles, context: context, fragment: fragment
        ), !hasAuxiliaryInput || pureValueCalls([
            (last.lowerBound + 1)..<last.upperBound
        ], fragment: fragment) { return true }
        guard let nested = call(expression), closure.contains(nested.name),
              let callee = uniqueFunction(named: nested.name, fragment: fragment),
              let parameters = parameters(callee, tokens: fragment.tokens),
              parameters.count == nested.arguments.count,
              nested.arguments.filter({ argument in
                  argument.contains(where: { $0.text == carrier })
              }).count == 1 else { return false }
        if hasAuxiliaryInput,
           !pureCallArguments((last.lowerBound + 1)..<last.upperBound,
                              fragment: fragment) { return false }
        let next = Dictionary(uniqueKeysWithValues:
            zip(parameters, nested.arguments).map { parameter, argument in
                (parameter, role(
                    argument, environment: roles, context: context, fragment: fragment
                ))
            }
        )
        return next.values.filter({ $0 == .carrier }).count == 1
            && safeReturn(
            callee, roles: next, closure: closure, context: context, fragment: fragment,
                visited: visited.union([function.name])
            )
    }

    private static func boundedCarrierExpression(
        _ tokens: [Token], roles: [String: ValueRole],
        context: ScalarContext, fragment: Unit
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
            operands.0, environment: roles, context: context, fragment: fragment
        ) == .carrier
        let secondCarrier = role(
            operands.1, environment: roles, context: context, fragment: fragment
        ) == .carrier
        guard firstCarrier != secondCarrier else { return false }
        let injected = firstCarrier ? operands.1 : operands.0
        if case .rgbaInjection = role(injected, environment: roles,
                                     context: context, fragment: fragment) { return true }
        if case let .auxiliary(value) = role(injected, environment: roles,
                                            context: context, fragment: fragment),
           value.width == 4, value.channels & 1 != 0, value.hasSourceAlpha { return true }
        guard let vector = call(injected),
              ["CAST4", "vec4", "float4"].contains(vector.name),
              vector.arguments.count == 1 else { return false }
        return role(
            vector.arguments[0], environment: roles, context: context, fragment: fragment
        ) == .bounded01
    }

    private static func role(
        _ rawTokens: [Token], environment: [String: ValueRole],
        context: ScalarContext, fragment: Unit
    ) -> ValueRole {
        let tokens = Array(SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(rawTokens[...]))
        if tokens.count == 1 {
            if tokens[0].text == "gl_FragColor" { return .carrier }
            if let value = environment[tokens[0].text] { return value }
        }
        if tokens.count == 3, tokens[1].text == ".",
           case let .auxiliary(value)? = environment[tokens[0].text], value.width == 4 {
            let member = tokens[2].text
            if ["rgb", "xyz"].contains(member) {
                return .auxiliary(.init(slot: value.slot, sampleIndex: value.sampleIndex, width: 3,
                    channels: value.rgbUsesAlpha ? 3 : 1))
            }
            if ["a", "w"].contains(member) {
                return .auxiliary(.init(slot: value.slot, sampleIndex: value.sampleIndex,
                                       width: 1, channels: 2,
                                       hasSourceAlpha: true))
            }
        }
        for operation in ["+", "-", "*", "/"] {
            if let operands = binary(tokens, operation: operation) {
                let left = role(operands.0, environment: environment,
                                context: context, fragment: fragment)
                let right = role(operands.1, environment: environment,
                                 context: context, fragment: fragment)
                if case let .auxiliary(a) = left, case let .auxiliary(b) = right,
                   a.sampleIndex == b.sampleIndex,
                   a.width == b.width || a.width == 1 || b.width == 1 {
                    return .auxiliary(.init(slot: a.slot, sampleIndex: a.sampleIndex,
                        width: max(a.width, b.width),
                        channels: a.channels | b.channels,
                        hasSourceAlpha: a.hasSourceAlpha || b.hasSourceAlpha))
                }
                if case let .auxiliary(value) = left, [.scalar, .bounded01].contains(right) {
                    return .auxiliary(value)
                }
                if operation != "/", case let .auxiliary(value) = right,
                   [.scalar, .bounded01].contains(left) { return .auxiliary(value) }
            }
        }
        if let value = call(tokens), !hasAuthoredFunction(named: value.name, fragment: fragment) {
            let arguments = value.arguments.map {
                role($0, environment: environment, context: context, fragment: fragment)
            }
            if ["vec4", "float4"].contains(value.name), arguments.count == 2,
               case let .auxiliary(rgb) = arguments[0], rgb.width == 3, rgb.channels & 1 != 0,
               case let .auxiliary(alpha) = arguments[1], alpha.width == 1,
               alpha.hasSourceAlpha, rgb.sampleIndex == alpha.sampleIndex {
                return .rgbaInjection(rgb.sampleIndex)
            }
            if ["vec4", "float4"].contains(value.name), arguments.count == 2,
               case let .auxiliary(rgb) = arguments[0], rgb.width == 3,
               unitScalar(value.arguments[1]) {
                return .auxiliary(.init(slot: rgb.slot, sampleIndex: rgb.sampleIndex,
                                       width: 4, channels: rgb.channels))
            }
            if value.name == "saturate", arguments.count == 1,
               case .auxiliary = arguments[0] { return arguments[0] }
            if value.name == "dot", arguments.count == 2,
               case let .auxiliary(rgb) = arguments[0], rgb.width == 3,
               [.scalar, .bounded01].contains(arguments[1]) {
                return .auxiliary(.init(slot: rgb.slot, sampleIndex: rgb.sampleIndex,
                                       width: 1, channels: rgb.channels))
            }
            if ["CAST3", "vec3", "float3"].contains(value.name), arguments.count == 1,
               [.scalar, .bounded01].contains(arguments[0]) { return .scalar }
        }
        let builtinArities = [
            "saturate": 1, "frac": 1, "fract": 1,
            "step": 2, "smoothstep": 3,
        ]
        if let value = call(tokens),
              builtinArities[value.name] == value.arguments.count,
              value.arguments.allSatisfy({ !$0.isEmpty }),
              !hasAuthoredFunction(named: value.name, fragment: fragment),
              !tokens.contains(where: {
                  ["gl_FragColor", "texSample2D", "texture2D", "imageStore"].contains($0.text)
              }), !tokens.contains(where: { token in
                  if case .auxiliary? = environment[token.text] { return true }
                  return false
              }) { return .bounded01 }
        guard !tokens.contains(where: { environment[$0.text] == .other }) else { return .other }
        return SceneAuthoredShaderIndependentSignalScalarContract.isScalar(
            tokens, state: context.state, dataSlots: context.dataSlots, fragment: fragment
        ) ? .scalar : .other
    }

    private static func hasAuxiliaryValue(_ roles: [String: ValueRole]) -> Bool {
        roles.values.contains { value in
            switch value {
            case .auxiliary, .rgbaInjection: true
            default: false
            }
        }
    }

    /// The root callee is separately proven by safeReturn. Its arguments and
    /// all other new raw-data expressions still use the shared pure-call owner.
    private static func pureCallArguments(_ range: Range<Int>, fragment: Unit) -> Bool {
        let expression = SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(fragment.tokens[range])
        guard expression.count >= 3,
              let ranges = SceneAuthoredShaderTokenScanner.argumentRanges(
                  in: (expression.startIndex + 2)..<(expression.endIndex - 1),
                  tokens: fragment.tokens
              ) else { return false }
        return pureValueCalls(ranges, fragment: fragment)
    }

    private static func pureValueCalls(_ ranges: [Range<Int>], fragment: Unit) -> Bool {
        SceneAuthoredShaderColorTransferAnalyzer.helperCallsArePureAndUnsampled(
            fragment: fragment, expressionRanges: ranges,
            permitsUnexpandedBlendingHelper: false, permitsAuthoredHelpers: false
        )
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
              value.arguments.count == 1 else { return false }
        return unitScalar(value.arguments[0])
    }

    private static func unitScalar(_ tokens: [Token]) -> Bool {
        let value = SceneAuthoredShaderConditionalStraightUnionAnalyzer.strippingParentheses(tokens[...])
        return value.count == 1 && value.first?.kind == .number
            && value.first.flatMap({ Double($0.text) }) == 1
    }

    private static func binary(
        _ rawTokens: [Token], operation: String
    ) -> ([Token], [Token])? {
        let tokens = Array(SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(rawTokens[...]))
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
        return SceneShaderSourceTextFacts.textureSlot(value.arguments[0][0].text)
    }

    private static func call(_ rawTokens: [Token]) -> Call? {
        let tokens = Array(SceneAuthoredShaderConditionalStraightUnionAnalyzer
            .strippingParentheses(rawTokens[...]))
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
                  let slot = SceneShaderSourceTextFacts.textureSlot(tokens[index + 2].text), tokens[index + 3].text == ",",
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

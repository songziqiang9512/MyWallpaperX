import Foundation

/// Proves a bounded root-local color graph whose leaves are direct texture
/// colors and whose only color operation is scalar `mix`. Coordinate and scalar
/// expressions may consume auxiliary samplers without changing color ownership.
nonisolated enum SceneAuthoredShaderColorMixGraphAnalyzer {
    struct RGBGraphFact: Equatable {
        let colorSampleSlots: Set<Int>
        let alphaCarrierSlot: Int
        let fullColorSampleCallCounts: [Int: Int]
        let rgbSampleCallCounts: [Int: Int]
    }

    private struct GraphTrace {
        var references: Set<Int> = []
        var names: Set<String> = []

        func merging(_ other: Self) -> Self {
            .init(references: references.union(other.references), names: names.union(other.names))
        }

        func recording(_ name: String, at index: Int) -> Self {
            .init(references: references.union([index]), names: names.union([name]))
        }
    }

    private struct GraphRGB {
        var samples: Set<Int>
        var blends: Set<Int> = []
        var trace = GraphTrace()
    }

    private struct GraphScalar {
        var alphaSample: Int? = nil
        var trace = GraphTrace()
    }

    private struct GraphColor {
        var rgb: GraphRGB
        var alpha: GraphScalar?
    }

    private struct State {
        let fragment: SceneAuthoredShaderSyntaxUnit
        let main: SceneAuthoredShaderSyntaxUnit.Function
        var remainingNodes = 64
        var activeAssignments: Set<Int> = []
        var permitsRGBScalarMutation = false
        var rgbScalarMutations: Set<Int> = []
        var sampleReferences: [Int: Set<Int>] = [:]
        var carrierReferences: [String: Set<Int>] = [:]
        var graphColors: [String: GraphColor] = [:]
        var graphScalars: [String: GraphScalar] = [:]
        var graphDeclarations: [String: (type: String, index: Int)] = [:]
        var graphSamples: [Int: (slot: Int, full: Bool, reference: Int)] = [:]
    }

    /// Independent input/output fact for a root-local RGB DAG. Complete-vector
    /// samples carry separate RGB and unchanged-alpha versions; only RGB mix
    /// nodes may combine colors. Every sampled call and every local value read
    /// must close over this graph, including aliases and scalar coverage uses.
    /// This does not prove framebuffer roles, attachment alpha or PMA storage.
    static func alphaPreservingRGBGraph(
        vertex: SceneAuthoredShaderSyntaxUnit, fragment: SceneAuthoredShaderSyntaxUnit
    ) -> RGBGraphFact? {
        guard vertex.declarations.filter({ $0.typeName.hasPrefix("sampler") }).allSatisfy({
            SceneAuthoredShaderTextureChannelAnalyzer.referenceIndices($0.name, in: vertex).isEmpty
        }) else { return nil }
        return alphaPreservingRGBGraph(fragment: fragment)
    }

    /// Output transfer consumes the same fragment graph without granting a
    /// stage-wide input-purpose fact. The two-stage entry additionally closes
    /// over vertex sampler uses before sharing this single derivation.
    static func alphaPreservingRGBGraph(fragment: SceneAuthoredShaderSyntaxUnit) -> RGBGraphFact? {
        guard let main = fragment.functions.first(where: { $0.name == "main" }),
              !fragment.functions.contains(where: {
                  ["mix", "lerp", "texSample2D", "texture2D"].contains($0.name)
              }) else { return nil }
        let tokens = fragment.tokens
        let body = (main.bodyRange.lowerBound + 1)..<(main.bodyRange.upperBound - 1)
        guard !body.contains(where: {
            ["{", "}", "if", "else", "for", "return", "discard"].contains(tokens[$0].text)
        }), tokens.filter({ $0.text == "gl_FragColor" }).count == 1 else { return nil }
        var state = State(fragment: fragment, main: main)
        var output: GraphColor?
        var start = body.lowerBound
        for end in body where tokens[end].text == ";" {
            guard start < end,
                  graphStatement(tokens[start..<end], output: &output, state: &state) else {
                return nil
            }
            start = end + 1
        }
        guard start == body.upperBound, let output,
              let alpha = output.alpha, let alphaSample = alpha.alphaSample,
              let carrier = state.graphSamples[alphaSample], carrier.full,
              output.rgb.samples.contains(alphaSample), !output.rgb.blends.isEmpty else { return nil }
        let trace = output.rgb.trace.merging(alpha.trace)
        for name in trace.names {
            let actual = Set(body.filter { tokens[$0].text == name && tokens[$0 - 1].text != "." })
            guard actual == trace.references.filter({ tokens[$0].text == name }) else { return nil }
        }
        let samples = output.rgb.samples.compactMap { state.graphSamples[$0] }
        guard samples.count == output.rgb.samples.count else { return nil }
        let resourceCalls = Set(tokens.indices.filter { index in
            let name = tokens[index].text
            return index + 1 < tokens.count && tokens[index + 1].text == "("
                && (name.hasPrefix("texSample") || name.hasPrefix("texture")
                    || name.hasPrefix("texelFetch") || name.hasPrefix("image") || name == "subpassLoad")
        })
        guard resourceCalls == output.rgb.samples else { return nil }
        let slots = Set(samples.map(\.slot))
        for declaration in fragment.declarations where declaration.typeName.hasPrefix("sampler") {
            let references = Set(SceneAuthoredShaderTextureChannelAnalyzer.referenceIndices(
                declaration.name, in: fragment
            ))
            guard let slot = SceneShaderSourceTextFacts.textureSlot(declaration.name) else {
                if !references.isEmpty { return nil }
                continue
            }
            let expected = Set(samples.filter { $0.slot == slot }.map(\.reference))
            guard references == expected,
                  expected.isEmpty || (declaration.storage == .uniform
                    && declaration.typeName == "sampler2D" && declaration.arraySize == nil) else { return nil }
        }
        guard slots.allSatisfy({ slot in fragment.declarations.contains {
            $0.name == "g_Texture\(slot)" && $0.typeName == "sampler2D"
        } }) else { return nil }
        return .init(
            colorSampleSlots: slots, alphaCarrierSlot: carrier.slot,
            fullColorSampleCallCounts: samples.filter(\.full).reduce(into: [:]) { $0[$1.slot, default: 0] += 1 },
            rgbSampleCallCounts: samples.filter { !$0.full }.reduce(into: [:]) { $0[$1.slot, default: 0] += 1 }
        )
    }

    private static func graphStatement(
        _ statement: ArraySlice<SceneAuthoredShaderToken>, output: inout GraphColor?, state: inout State
    ) -> Bool {
        let tokens = state.fragment.tokens
        var left = statement.startIndex
        if ["const", "highp", "mediump", "lowp"].contains(tokens[left].text) { left += 1 }
        guard left < statement.endIndex else { return false }
        let type = SceneAuthoredShaderValueType(authoredName: tokens[left].text)
        if type != nil { left += 1 }
        guard left < statement.endIndex else { return false }
        let name = tokens[left].text
        if let type {
            guard state.graphDeclarations[name] == nil,
                  !state.fragment.declarations.contains(where: { $0.name == name }) else { return false }
            state.graphDeclarations[name] = (type.rawValue, left)
        }
        let operators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        guard let operation = statement.indices.first(where: { operators.contains(tokens[$0].text) }) else {
            return type == nil
        }
        let member = operation == left + 3 && tokens[left + 1].text == "."
            ? tokens[left + 2].text : nil
        guard operation == left + 1 || member != nil else { return false }
        let expression = tokens[(operation + 1)..<statement.endIndex]
        if name == "gl_FragColor" {
            guard output == nil, member == nil, tokens[operation].text == "=" else { return false }
            output = graphColor(expression, state: &state)
            return output != nil
        }
        if let member, state.graphColors[name] != nil {
            guard ["rgb", "xyz"].contains(member), tokens[operation].text == "=",
                  var rgb = graphRGB(expression, state: &state),
                  var color = state.graphColors[name] else { return false }
            rgb.trace = graphRecording(rgb.trace, name: name, at: left, state: state)
            color.rgb = rgb
            state.graphColors[name] = color
            return true
        }
        guard member == nil else {
            // Independent coordinate work may have member writes. Its use of
            // any color/coverage carrier still fails the complete-read closure.
            return state.graphScalars[name] == nil
        }
        let valueType = state.graphDeclarations[name]?.type
        if tokens[operation].text == "=", ["vec4", "float4"].contains(valueType ?? ""),
           var value = graphColor(expression, state: &state) {
            value.rgb.trace = graphRecording(value.rgb.trace, name: name, at: left, state: state)
            if var alpha = value.alpha {
                alpha.trace = graphRecording(alpha.trace, name: name, at: left, state: state)
                value.alpha = alpha
            }
            state.graphColors[name] = value
            return true
        }
        if tokens[operation].text == "=", ["vec3", "float3"].contains(valueType ?? ""),
           var rgb = graphRGB(expression, state: &state) {
            rgb.trace = graphRecording(rgb.trace, name: name, at: left, state: state)
            state.graphColors[name] = .init(rgb: rgb, alpha: nil)
            return true
        }
        if valueType == "float", var scalar = graphScalar(expression, state: &state) {
            if tokens[operation].text != "=" {
                guard ["*=", "+=", "-="].contains(tokens[operation].text),
                      let previous = state.graphScalars[name] else { return false }
                scalar.trace = scalar.trace.merging(previous.trace)
                scalar.alphaSample = nil
            }
            scalar.trace = graphRecording(scalar.trace, name: name, at: left, state: state)
            state.graphScalars[name] = scalar
            return true
        }
        return state.graphColors[name] == nil && state.graphScalars[name] == nil
    }

    private static func graphRecording(
        _ trace: GraphTrace, name: String, at index: Int, state: State
    ) -> GraphTrace {
        var trace = trace.recording(name, at: index)
        if let declaration = state.graphDeclarations[name] {
            trace = trace.recording(name, at: declaration.index)
        }
        return trace
    }

    private static func graphColor(
        _ expression: ArraySlice<SceneAuthoredShaderToken>, state: inout State
    ) -> GraphColor? {
        guard state.remainingNodes > 0 else { return nil }
        state.remainingNodes -= 1
        let expression = graphUnwrapped(expression)
        if let sample = graphSample(expression, full: true, state: &state) {
            return .init(rgb: .init(samples: [sample]), alpha: .init(alphaSample: sample))
        }
        if expression.count == 1, let token = expression.first,
           var value = state.graphColors[token.text], value.alpha != nil {
            value.rgb.trace = value.rgb.trace.recording(token.text, at: expression.startIndex)
            if var alpha = value.alpha {
                alpha.trace = alpha.trace.recording(token.text, at: expression.startIndex)
                value.alpha = alpha
            }
            return value
        }
        for name in ["vec4", "float4"] {
            if let arguments = callArguments(named: name, expression: expression), arguments.count == 2,
               let rgb = graphRGB(arguments[0], state: &state),
               let alpha = graphScalar(arguments[1], state: &state), alpha.alphaSample != nil {
                return .init(rgb: rgb, alpha: alpha)
            }
        }
        return nil
    }

    private static func graphRGB(
        _ expression: ArraySlice<SceneAuthoredShaderToken>, state: inout State
    ) -> GraphRGB? {
        guard state.remainingNodes > 0 else { return nil }
        state.remainingNodes -= 1
        let expression = graphUnwrapped(expression)
        if expression.count >= 3, expression[expression.endIndex - 2].text == ".",
           ["rgb", "xyz"].contains(expression.last!.text) {
            let base = graphUnwrapped(expression.dropLast(2))
            if let sample = graphSample(base, full: false, state: &state) {
                return .init(samples: [sample])
            }
            if base.count == 1, let token = base.first, var value = state.graphColors[token.text] {
                value.rgb.trace = value.rgb.trace.recording(token.text, at: base.startIndex)
                return value.rgb
            }
        }
        if expression.count == 1, let token = expression.first,
           let color = state.graphColors[token.text], color.alpha == nil {
            var rgb = color.rgb
            rgb.trace = rgb.trace.recording(token.text, at: expression.startIndex)
            return rgb
        }
        guard let name = expression.first?.text else { return nil }
        var arguments = callArguments(named: name, expression: expression)
        if !["mix", "lerp"].contains(name) {
            guard state.fragment.functions.contains(where: {
                    $0.name == name && ["vec3", "float3"].contains($0.returnType)
                  }),
                  SceneAuthoredShaderStraightBlendOutputAnalyzer.hasNormalBlendHelper(state.fragment, named: name),
                  SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer.safeReadOnlyHelperClosure(
                    rootName: name, fragment: state.fragment
                  ) != nil,
                  arguments?.count == 4, let mode = arguments?.first,
                  mode.count == 1, let number = Double(mode.first!.text), number.isFinite else { return nil }
            arguments?.removeFirst()
        }
        guard let arguments, arguments.count == 3,
              let first = graphRGB(arguments[0], state: &state),
              let second = graphRGB(arguments[1], state: &state),
              let weight = graphScalar(arguments[2], state: &state) else { return nil }
        return .init(
            samples: first.samples.union(second.samples),
            blends: first.blends.union(second.blends).union([expression.startIndex]),
            trace: first.trace.merging(second.trace).merging(weight.trace)
        )
    }

    private static func graphSample(
        _ expression: ArraySlice<SceneAuthoredShaderToken>, full: Bool, state: inout State
    ) -> Int? {
        guard let slot = SceneAuthoredShaderColorTransferAnalyzer.directTextureSampleSlot(expression) else {
            return nil
        }
        let index = expression.startIndex
        state.graphSamples[index] = (slot, full, index + 2)
        return index
    }

    private static func graphScalar(
        _ expression: ArraySlice<SceneAuthoredShaderToken>, state: inout State
    ) -> GraphScalar? {
        guard state.remainingNodes > 0 else { return nil }
        state.remainingNodes -= 1
        let expression = graphUnwrapped(expression)
        guard let first = expression.first else { return nil }
        if expression.count == 1 {
            if first.kind == .number, let number = Double(first.text), number.isFinite { return .init() }
            if var scalar = state.graphScalars[first.text] {
                scalar.trace = scalar.trace.recording(first.text, at: expression.startIndex)
                return scalar
            }
            if state.fragment.declarations.contains(where: {
                $0.name == first.text && $0.typeName == "float" && $0.arraySize == nil
            }) { return .init() }
            return nil
        }
        if expression.count == 3, expression[expression.startIndex + 1].text == "." {
            let member = expression.last!.text
            if let color = state.graphColors[first.text] {
                guard ["a", "w"].contains(member), var alpha = color.alpha else { return nil }
                alpha.trace = alpha.trace.recording(first.text, at: expression.startIndex)
                return alpha
            }
            let type = state.graphDeclarations[first.text]?.type
                ?? state.fragment.declarations.first(where: { $0.name == first.text })?.typeName
            let components: [String: String] = [
                "vec2": "xy", "float2": "xy", "vec3": "xyz", "float3": "xyz",
                "vec4": "xyzw", "float4": "xyzw",
            ]
            if let type, member.count == 1, components[type]?.contains(member) == true { return .init() }
            return nil
        }
        if let split = graphScalarOperator(expression) {
            guard let first = graphScalar(expression[..<split], state: &state),
                  let second = graphScalar(expression[(split + 1)...], state: &state) else { return nil }
            if expression[split].text == "/" {
                let denominator = graphUnwrapped(expression[(split + 1)...])
                guard denominator.count == 1, let value = Double(denominator.first!.text), value != 0 else {
                    return nil
                }
            }
            return .init(trace: first.trace.merging(second.trace))
        }
        if ["+", "-"].contains(first.text), let scalar = graphScalar(expression.dropFirst(), state: &state) {
            return .init(trace: scalar.trace)
        }
        let counts: [String: Int] = ["abs": 1, "saturate": 1, "min": 2, "max": 2, "step": 2, "clamp": 3, "smoothstep": 3]
        guard let count = counts[first.text],
              !state.fragment.functions.contains(where: { $0.name == first.text }),
              let arguments = callArguments(named: first.text, expression: expression),
              arguments.count == count else { return nil }
        var trace = GraphTrace()
        for argument in arguments {
            guard let scalar = graphScalar(argument, state: &state) else { return nil }
            trace = trace.merging(scalar.trace)
        }
        return .init(trace: trace)
    }

    private static func graphScalarOperator(_ expression: ArraySlice<SceneAuthoredShaderToken>) -> Int? {
        var depth = 0
        var additive: Int?
        var multiplicative: Int?
        for index in expression.indices {
            let text = expression[index].text
            if ["(", "["].contains(text) { depth += 1 }
            if [")", "]"].contains(text) { depth -= 1 }
            guard depth == 0, index > expression.startIndex,
                  !["+", "-", "*", "/", "("].contains(expression[index - 1].text) else { continue }
            if ["+", "-"].contains(text) { additive = index }
            if ["*", "/"].contains(text) { multiplicative = index }
        }
        return additive ?? multiplicative
    }

    private static func graphUnwrapped(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> ArraySlice<SceneAuthoredShaderToken> {
        var result = expression
        while result.count >= 2, result.first?.text == "(", result.last?.text == ")",
              SceneAuthoredShaderTokenScanner.matchingParenthesis(
                tokens: Array(result), opening: 0
              ) == result.count - 1 {
            result = result.dropFirst().dropLast()
        }
        return result
    }

    /// A purpose fact, independent of output color transfer: a complete-vector
    /// sample graph may receive one unconditional RGB scalar multiplication.
    /// Every sampled leaf and carrier use must belong to this graph; alpha,
    /// data extraction, alias escapes and helper mutation remain unproven.
    static func straightColorInputSlots(
        vertexSource: String, fragmentSource: String
    ) -> Set<Int> {
        guard let syntax = SceneAuthoredShaderSyntaxAnalyzer.validatedStages(
            vertexSource: vertexSource, fragmentSource: fragmentSource
        ) else { return [] }
        return straightColorInputSlots(vertex: syntax.vertex, fragment: syntax.fragment)
    }

    static func straightColorInputSlots(
        vertex: SceneAuthoredShaderSyntaxUnit, fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Set<Int> {
        guard let main = fragment.functions.first(where: { $0.name == "main" }) else { return [] }
        let tokens = fragment.tokens
        let outputs = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard outputs.count == 1, let output = outputs.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                output, tokens: tokens, body: main.bodyRange
              ),
              let expression = SceneAuthoredShaderColorTransferAnalyzer.assignmentExpression(
                after: output, in: tokens, body: main.bodyRange
              ) else { return [] }
        var state = State(fragment: fragment, main: main, permitsRGBScalarMutation: true)
        guard let slots = colorSlots(expression, before: output, state: &state),
              !slots.isEmpty, state.rgbScalarMutations.count == 1 else { return [] }
        for slot in slots {
            let name = "g_Texture\(slot)"
            guard fragment.declarations.contains(where: {
                $0.name == name && $0.storage == .uniform && $0.typeName == "sampler2D"
            }), SceneAuthoredShaderTextureChannelAnalyzer.referenceIndices(name, in: vertex).isEmpty,
            Set(SceneAuthoredShaderTextureChannelAnalyzer.referenceIndices(name, in: fragment))
                == state.sampleReferences[slot] else { return [] }
        }
        for (name, references) in state.carrierReferences {
            guard Set(tokens.indices.filter { tokens[$0].text == name }) == references else { return [] }
        }
        return slots
    }

    static func analyze(
        outputUses: [Int],
        fragment: SceneAuthoredShaderSyntaxUnit,
        main: SceneAuthoredShaderSyntaxUnit.Function
    ) -> [Int]? {
        let tokens = fragment.tokens
        guard outputUses.count == 1,
              let output = outputUses.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: output,
                      in: tokens,
                      body: main.bodyRange
                  ) else {
            return nil
        }
        var state = State(fragment: fragment, main: main)
        guard let slots = colorSlots(
            expression,
            before: output,
            state: &state
        ), !slots.isEmpty else {
            return nil
        }
        return slots.sorted()
    }

    private static func colorSlots(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        before boundary: Int,
        state: inout State
    ) -> Set<Int>? {
        guard state.remainingNodes > 0 else { return nil }
        state.remainingNodes -= 1
        let expression = unwrapped(expression)
        if let slot = SceneAuthoredShaderColorTransferAnalyzer
            .directTextureSampleSlot(expression) {
            if state.permitsRGBScalarMutation {
                state.sampleReferences[slot, default: []].insert(expression.startIndex + 2)
            }
            return [slot]
        }
        if let arguments = callArguments(named: "mix", expression: expression),
           arguments.count == 3,
           isScalar(arguments[2], before: boundary, state: state),
           let first = colorSlots(arguments[0], before: boundary, state: &state),
           let second = colorSlots(arguments[1], before: boundary, state: &state) {
            return first.union(second)
        }
        guard expression.count == 1,
              let token = expression.first,
              token.kind == .identifier,
              let assignment = reachingVectorAssignment(
                  named: token.text,
                  before: boundary,
                  state: &state
              ),
              state.activeAssignments.insert(assignment).inserted,
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                  .assignmentExpression(
                      after: assignment,
                      in: state.fragment.tokens,
                      body: state.main.bodyRange
                  ),
              isDeclaration(assignment, state: state)
                  || isSelfMix(
                      initializer,
                      name: token.text
                  ) else {
            return nil
        }
        if state.permitsRGBScalarMutation {
            state.carrierReferences[token.text, default: []].formUnion([
                expression.startIndex, assignment
            ])
        }
        defer { state.activeAssignments.remove(assignment) }
        return colorSlots(initializer, before: assignment, state: &state)
    }

    private static func isDeclaration(
        _ assignment: Int,
        state: State
    ) -> Bool {
        assignment > state.main.bodyRange.lowerBound
            && ["vec4", "float4"].contains(
                state.fragment.tokens[assignment - 1].text
            )
    }

    private static func isSelfMix(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        name: String
    ) -> Bool {
        guard let arguments = callArguments(
            named: "mix",
            expression: unwrapped(expression)
        ), arguments.count == 3 else { return false }
        return arguments.prefix(2).contains {
            $0.count == 1 && $0.first?.text == name
        }
    }

    private static func reachingVectorAssignment(
        named name: String,
        before boundary: Int,
        state: inout State
    ) -> Int? {
        let tokens = state.fragment.tokens
        let body = state.main.bodyRange
        let declarations = body.filter { index in
            index > body.lowerBound && index < boundary
                && tokens[index].text == name
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
        }
        guard declarations.count == 1 else { return nil }
        let assignments = body.filter { index in
            index >= declarations[0] && index < boundary
                && tokens[index].text == name
                && index + 1 < tokens.count
                && tokens[index + 1].text == "="
                && (index == body.lowerBound || tokens[index - 1].text != ".")
        }
        guard let assignment = assignments.last,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  assignment,
                  tokens: tokens,
                  body: body
              ),
              !hasMutation(
                  named: name,
                  after: assignment,
                  before: boundary,
                  state: &state
              ) else {
            return nil
        }
        return assignment
    }

    private static func hasMutation(
        named name: String,
        after assignment: Int,
        before boundary: Int,
        state: inout State
    ) -> Bool {
        let tokens = state.fragment.tokens
        let operators: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for index in (assignment + 1)..<boundary where tokens[index].text == name {
            if index + 1 < boundary, operators.contains(tokens[index + 1].text) {
                return true
            }
            guard index + 3 < boundary, tokens[index + 1].text == ".",
                  operators.contains(tokens[index + 3].text) else { continue }
            guard state.permitsRGBScalarMutation,
                  ["rgb", "xyz"].contains(tokens[index + 2].text),
                  tokens[index + 3].text == "*=",
                  SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                    index, tokens: tokens, body: state.main.bodyRange
                  ),
                  let end = (index + 4..<boundary).first(where: { tokens[$0].text == ";" }),
                  isScalar(tokens[index + 4..<end], before: index, state: state) else { return true }
            state.rgbScalarMutations.insert(index)
            state.carrierReferences[name, default: []].insert(index)
        }

        // A user function may mutate an lvalue through an `inout` parameter.
        // The color graph intentionally does not infer interprocedural alias
        // effects, so any authored helper call that receives this local makes
        // the reaching value unprovable rather than silently passthrough.
        let authoredFunctions = Set(state.fragment.functions.map(\.name))
        return (assignment + 1 ..< boundary).contains { index in
            guard authoredFunctions.contains(tokens[index].text),
                  index + 1 < boundary, tokens[index + 1].text == "(",
                  let closing = SceneAuthoredShaderTokenScanner
                    .matchingParenthesis(tokens: tokens, opening: index + 1),
                  closing < boundary else { return false }
            return ((index + 2) ..< closing).contains {
                tokens[$0].text == name
            }
        }
    }

    private static func isScalar(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        before boundary: Int,
        state: State
    ) -> Bool {
        let expression = unwrapped(expression)
        guard let first = expression.first else { return false }
        if expression.count == 1 {
            if first.kind == .number { return true }
            guard first.kind == .identifier else { return false }
            return state.fragment.declarations.contains {
                $0.name == first.text && $0.typeName == "float" && $0.arraySize == nil
            } || localType(
                named: first.text,
                before: boundary,
                state: state
            ) == "float"
        }
        if expression.count == 3,
           expression[expression.startIndex + 1].text == ".",
           expression.last?.text.count == 1,
           let type = expressionType(
               named: first.text,
               before: boundary,
               state: state
           ), ["vec2", "vec3", "vec4", "float2", "float3", "float4"]
               .contains(type) {
            return true
        }
        let componentwise: Set<String> = [
            "abs", "acos", "asin", "atan", "ceil", "cos", "exp", "floor",
            "fract", "frac", "log", "round", "saturate", "sign", "sin", "sqrt",
        ]
        if componentwise.contains(first.text),
           let arguments = callArguments(named: first.text, expression: expression),
           arguments.count == 1 {
            return isScalar(arguments[0], before: boundary, state: state)
        }
        let scalarResults: Set<String> = ["distance", "dot", "length"]
        if scalarResults.contains(first.text),
           callArguments(named: first.text, expression: expression) != nil {
            return true
        }
        let scalarArguments: Set<String> = ["clamp", "max", "min", "mix", "pow", "smoothstep", "step"]
        guard scalarArguments.contains(first.text),
              let arguments = callArguments(named: first.text, expression: expression),
              !arguments.isEmpty else { return false }
        return arguments.allSatisfy {
            isScalar($0, before: boundary, state: state)
        }
    }

    private static func expressionType(
        named name: String,
        before boundary: Int,
        state: State
    ) -> String? {
        state.fragment.declarations.first { $0.name == name }?.typeName
            ?? localType(named: name, before: boundary, state: state)
    }

    private static func localType(
        named name: String,
        before boundary: Int,
        state: State
    ) -> String? {
        let tokens = state.fragment.tokens
        let types = state.main.bodyRange.compactMap { index -> String? in
            guard index > state.main.bodyRange.lowerBound, index < boundary,
                  tokens[index].text == name,
                  tokens[index - 1].kind == .identifier,
                  SceneAuthoredShaderValueType(
                      authoredName: tokens[index - 1].text
                  ) != nil else { return nil }
            return tokens[index - 1].text
        }
        return Set(types).count == 1 ? types.first : nil
    }

    private static func unwrapped(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> ArraySlice<SceneAuthoredShaderToken> {
        guard expression.count >= 2,
              expression.first?.text == "(", expression.last?.text == ")",
              outerCallClosesAtEnd(Array(expression)) else { return expression }
        return expression.dropFirst().dropLast()
    }

    private static func callArguments(
        named name: String,
        expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> [ArraySlice<SceneAuthoredShaderToken>]? {
        let tokens = Array(expression)
        guard tokens.count >= 4, tokens[0].text == name,
              tokens[1].text == "(", tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens) else { return nil }
        var depth = 0
        var start = 2
        var ranges: [Range<Int>] = []
        for index in 2..<(tokens.count - 1) {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return nil }
                ranges.append(start..<index)
                start = index + 1
            default: break
            }
        }
        guard depth == 0, start < tokens.count - 1 else { return nil }
        ranges.append(start..<(tokens.count - 1))
        let base = expression.startIndex
        return ranges.map {
            expression[(base + $0.lowerBound)..<(base + $0.upperBound)]
        }
    }

    private static func outerCallClosesAtEnd(
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
}

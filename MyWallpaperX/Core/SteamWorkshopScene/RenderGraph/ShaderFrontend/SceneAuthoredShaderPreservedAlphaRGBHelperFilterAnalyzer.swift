import Foundation

/// Proves a preserved-alpha carrier whose replacement RGB is produced by a
/// reachable, side-effect-free helper closure. Texture roles come only from
/// source structure: one color slot and one distinct `.rg` data slot.
nonisolated enum SceneAuthoredShaderPreservedAlphaRGBHelperFilterAnalyzer {
    typealias Fact = SceneAuthoredShaderPreservedAlphaRGBFilterFact
    private typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    private struct SampleCall {
        let index: Int
        let close: Int
        let slot: Int
        let swizzle: String?
    }

    static func analyze(fragmentSource source: String) -> Fact? {
        let syntax = SceneAuthoredShaderSyntaxAnalyzer.analyze(
            lexerOutput: SceneAuthoredShaderLexer.lex(
                source: source,
                stage: .fragment
            ),
            stage: .fragment
        )
        guard syntax.diagnostics.isEmpty, let fragment = syntax.unit else {
            return nil
        }
        return analyze(fragment)
    }

    static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" })
        else { return nil }
        let tokens = fragment.tokens
        let outputs = tokens.indices.filter { tokens[$0].text == "gl_FragColor" }
        guard outputs.count == 1,
              let output = outputs.first,
              main.bodyRange.contains(output),
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  output,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let outputExpression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: output,
                    in: tokens,
                    body: main.bodyRange
                ),
              outputExpression.count == 1,
              outputExpression.first?.kind == .identifier
        else { return nil }
        let carrier = outputExpression.first!.text

        let definitions = main.bodyRange.filter { index in
            index > main.bodyRange.lowerBound
                && index + 1 < output
                && tokens[index].text == carrier
                && ["vec4", "float4"].contains(tokens[index - 1].text)
                && tokens[index + 1].text == "="
        }
        guard definitions.count == 1,
              let definition = definitions.first,
              SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  definition,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let initializer = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: definition,
                    in: tokens,
                    body: main.bodyRange
                ),
              let sourceSlot = SceneAuthoredShaderColorTransferAnalyzer
                .directTextureSampleSlot(initializer),
              samplerType(slot: sourceSlot, fragment: fragment) == "sampler2D",
              let calls = sampleCalls(tokens: tokens),
              let sourceCall = calls.first(where: {
                  initializer.indices.contains($0.index)
              }),
              sourceCall.slot == sourceSlot,
              sourceCall.swizzle == nil
        else { return nil }

        let assignments = main.bodyRange.filter { index in
            index != definition
                && index + 1 < output
                && tokens[index].text == carrier
                && tokens[index + 1].text == "="
        }
        guard assignments.count == 1,
              let assignment = assignments.first,
              isDirectIfControlled(
                  assignment,
                  function: main,
                  tokens: tokens
              ),
              let replacement = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: assignment,
                    in: tokens,
                    body: main.bodyRange
                ),
              let constructor = call(tokens: replacement),
              ["vec4", "float4"].contains(constructor.name),
              constructor.arguments.count == 2,
              member(
                  constructor.arguments[1],
                  name: carrier,
                  members: ["a", "w"]
              ),
              let filterCall = call(tokens: constructor.arguments[0]),
              let filter = uniqueFunction(
                  named: filterCall.name,
                  fragment: fragment
              ),
              ["vec3", "float3"].contains(filter.returnType),
              !["main", "ApplyBlending"].contains(filter.name),
              functionReferenceCount(filter.name, tokens: tokens) == 2,
              carrierUsesPreserveAlpha(
                  carrier: carrier,
                  definition: definition,
                  assignment: assignment,
                  output: output,
                  main: main,
                  tokens: tokens
              ),
              let closure = safeHelperClosure(
                  rootName: filter.name,
                  fragment: fragment
              )
        else { return nil }

        let helperRanges = closure.map(\.bodyRange)
        let helperCalls = calls.filter { call in
            helperRanges.contains(where: { $0.contains(call.index) })
        }
        guard (1 ... 16).contains(helperCalls.count),
              helperCalls.allSatisfy({
                  $0.slot == sourceSlot
                      && ["rgb", "xyz"].contains($0.swizzle ?? "")
              }) else { return nil }

        let mainCalls = calls.filter { main.bodyRange.contains($0.index) }
        let dataCalls = mainCalls.filter { $0.index != sourceCall.index }
        guard dataCalls.count == 1,
              let dataCall = dataCalls.first,
              dataCall.slot != sourceSlot,
              samplerType(slot: dataCall.slot, fragment: fragment) == "sampler2D",
              dataDeclaration(dataCall, tokens: tokens),
              calls.count == 1 + dataCalls.count + helperCalls.count
        else { return nil }

        return .init(
            sourceSlot: sourceSlot,
            fullColorSampleCallCounts: [sourceSlot: 1],
            rgbColorSampleCallCounts: [sourceSlot: helperCalls.count],
            dataSampleCallCounts: [dataCall.slot: 1]
        )
    }

    /// Reuses this analyzer's existing helper call-graph and side-effect proof
    /// without exposing its preserved-alpha RGB value grammar.
    static func safeHelperClosure(
        rootName: String,
        fragment: Unit
    ) -> [Unit.Function]? {
        guard let root = uniqueFunction(named: rootName, fragment: fragment),
              root.name != "main",
              let closure = reachableFunctions(from: root, fragment: fragment),
              helperClosureIsPure(closure, fragment: fragment) else {
            return nil
        }
        return closure
    }

    /// The same transitive side-effect proof without requiring the compiler-
    /// selected helper to have one syntactic return. Multiple pure return paths
    /// still do not grant texture, output, discard, out/inout, or global-write
    /// authority.
    static func safeReadOnlyHelperClosure(
        rootName: String,
        fragment: Unit
    ) -> [Unit.Function]? {
        guard let root = uniqueFunction(named: rootName, fragment: fragment),
              root.name != "main",
              let closure = reachableFunctions(from: root, fragment: fragment),
              helperClosureIsPure(
                closure,
                fragment: fragment,
                requiresSingleReturn: false
              ) else {
            return nil
        }
        return closure
    }

    private static func reachableFunctions(
        from root: Unit.Function,
        fragment: Unit
    ) -> [Unit.Function]? {
        var result: [Unit.Function] = []
        var visited: Set<String> = []
        var active: Set<String> = []
        let names = Set(fragment.functions.map(\.name)).subtracting(["main"])
        func visit(_ function: Unit.Function) -> Bool {
            if visited.contains(function.name) { return true }
            guard active.insert(function.name).inserted else { return false }
            result.append(function)
            let called = function.bodyRange.compactMap { index -> String? in
                guard index + 1 < fragment.tokens.count,
                      fragment.tokens[index].kind == .identifier,
                      fragment.tokens[index + 1].text == "(",
                      names.contains(fragment.tokens[index].text) else {
                    return nil
                }
                return fragment.tokens[index].text
            }
            for name in Set(called) {
                guard let callee = uniqueFunction(
                    named: name,
                    fragment: fragment
                ), visit(callee) else { return false }
            }
            active.remove(function.name)
            visited.insert(function.name)
            return true
        }
        return visit(root) ? result : nil
    }

    private static func helperClosureIsPure(
        _ functions: [Unit.Function],
        fragment: Unit,
        requiresSingleReturn: Bool = true
    ) -> Bool {
        let tokens = fragment.tokens
        let effectfulCalls: Set<String> = [
            "EmitVertex", "EndPrimitive", "barrier", "groupMemoryBarrier",
            "imageStore", "memoryBarrier", "memoryBarrierAtomicCounter",
            "memoryBarrierBuffer", "memoryBarrierImage", "memoryBarrierShared",
        ]
        return functions.allSatisfy { function in
            !tokens[function.parameterRange].contains(where: {
                ["out", "inout"].contains($0.text)
            })
                && !tokens[function.bodyRange].contains(where: {
                    ["gl_FragColor", "discard"].contains($0.text)
                })
                && (!requiresSingleReturn || function.bodyRange.filter({
                    tokens[$0].text == "return"
                }).count == 1)
                && !function.bodyRange.contains(where: { index in
                    guard index + 1 < tokens.count,
                          tokens[index + 1].text == "(" else { return false }
                    let name = tokens[index].text
                    return effectfulCalls.contains(name)
                        || name.hasPrefix("atomic")
                        || name.hasPrefix("imageAtomic")
                        || isUnprovenResourceCall(name)
                })
                && writesOnlyLocalState(function, tokens: tokens)
        }
    }

    private static func isUnprovenResourceCall(_ name: String) -> Bool {
        if name.hasPrefix("texture") { return name != "texture2D" }
        if name.hasPrefix("texSample") { return name != "texSample2D" }
        return name.hasPrefix("texelFetch")
            || name.hasPrefix("image")
            || name == "subpassLoad"
    }

    static func writesOnlyLocalState(
        _ function: Unit.Function,
        tokens: [SceneAuthoredShaderToken],
        allowingExternalWrites: Set<String> = []
    ) -> Bool {
        let valueTypes: Set<String> = [
            "bool", "int", "uint", "float", "double",
            "bvec2", "bvec3", "bvec4", "ivec2", "ivec3", "ivec4",
            "uvec2", "uvec3", "uvec4", "vec2", "vec3", "vec4",
            "float2", "float3", "float4", "mat2", "mat3", "mat4",
        ]
        let declarationRanges = [function.parameterRange, function.bodyRange]
        let locals = Set(declarationRanges.flatMap { range in
            range.compactMap { index -> String? in
                guard index > range.lowerBound,
                      tokens[index].kind == .identifier,
                      valueTypes.contains(tokens[index - 1].text) else {
                    return nil
                }
                return tokens[index].text
            }
        })
        for index in function.bodyRange where
            tokens[index].kind == .identifier
                && isWriteTarget(index, body: function.bodyRange, tokens: tokens) {
            if !locals.contains(tokens[index].text),
               !allowingExternalWrites.contains(tokens[index].text) {
                return false
            }
        }
        return true
    }

    private static func isWriteTarget(
        _ index: Int,
        body: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        let writes: Set<String> = [
            "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
            "<<=", ">>=",
        ]
        // A member token is not itself a storage root. The preceding local or
        // global identifier owns the component write and is checked below.
        if index > body.lowerBound, tokens[index - 1].text == "." {
            return false
        }
        if index > body.lowerBound,
           ["++", "--"].contains(tokens[index - 1].text) {
            return true
        }
        var cursor = index + 1
        chain: while cursor < body.upperBound {
            switch tokens[cursor].text {
            case ".":
                guard cursor + 1 < body.upperBound,
                      tokens[cursor + 1].kind == .identifier else {
                    return false
                }
                cursor += 2
            case "[":
                guard let close = matchingDelimiter(
                    at: cursor, tokens: tokens[...]
                ), close < body.upperBound else { return false }
                cursor = close + 1
            default:
                break chain
            }
        }
        guard cursor < body.upperBound else { return false }
        return writes.contains(tokens[cursor].text)
            || ["++", "--"].contains(tokens[cursor].text)
    }

    private static func carrierUsesPreserveAlpha(
        carrier: String,
        definition: Int,
        assignment: Int,
        output: Int,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let writes: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for index in main.bodyRange where tokens[index].text == carrier {
            if index == definition || index == assignment || index == output + 2 {
                continue
            }
            guard index + 2 < tokens.count,
                  tokens[index + 1].text == ".",
                  ["rgb", "xyz", "a", "w"].contains(tokens[index + 2].text)
            else { return false }
            if index + 3 < tokens.count,
               writes.contains(tokens[index + 3].text) {
                return false
            }
        }
        return true
    }

    private static func isDirectIfControlled(
        _ assignment: Int,
        function: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        var openBraces: [Int] = []
        for index in function.bodyRange.lowerBound..<assignment {
            if tokens[index].text == "{" { openBraces.append(index) }
            if tokens[index].text == "}" {
                guard !openBraces.isEmpty else { return false }
                openBraces.removeLast()
            }
        }
        guard openBraces.count == 2,
              let controlledBlock = openBraces.last,
              controlledBlock > function.bodyRange.lowerBound + 1,
              tokens[controlledBlock - 1].text == ")",
              let conditionOpen = matchingOpeningDelimiter(
                  at: controlledBlock - 1,
                  tokens: tokens
              ),
              conditionOpen > function.bodyRange.lowerBound,
              tokens[conditionOpen - 1].text == "if"
        else { return false }
        return true
    }

    private struct ParsedCall {
        let name: String
        let arguments: [ArraySlice<Token>]
    }

    private static func call(tokens: ArraySlice<Token>) -> ParsedCall? {
        guard tokens.count >= 3,
              let first = tokens.indices.first,
              tokens[first].kind == .identifier,
              tokens[tokens.index(after: first)].text == "(",
              tokens.last?.text == ")",
              matchingDelimiter(
                  at: tokens.index(after: first),
                  tokens: tokens
              ) == tokens.indices.last else { return nil }
        var arguments: [ArraySlice<Token>] = []
        var start = tokens.index(first, offsetBy: 2)
        var depth = 0
        for index in start..<tokens.index(before: tokens.endIndex) {
            if ["(", "[", "{"].contains(tokens[index].text) { depth += 1 }
            if [")", "]", "}"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == ",", depth == 0 {
                guard index > start else { return nil }
                arguments.append(tokens[start..<index])
                start = tokens.index(after: index)
            }
        }
        guard start < tokens.index(before: tokens.endIndex) else { return nil }
        arguments.append(tokens[start..<tokens.index(before: tokens.endIndex)])
        return .init(name: tokens[first].text, arguments: arguments)
    }

    private static func member(
        _ tokens: ArraySlice<Token>,
        name: String,
        members: Set<String>
    ) -> Bool {
        let text = tokens.map(\.text)
        return text.count == 3
            && text[0] == name
            && text[1] == "."
            && members.contains(text[2])
    }

    private static func sampleCalls(tokens: [Token]) -> [SampleCall]? {
        var result: [SampleCall] = []
        for index in tokens.indices where
            ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 3 < tokens.count,
                  tokens[index + 1].text == "(",
                  let slot = textureSlot(tokens[index + 2].text),
                  tokens[index + 3].text == ",",
                  let close = matchingDelimiter(
                      at: index + 1,
                      tokens: tokens[...]
                  ) else { return nil }
            let swizzle = close + 2 < tokens.count
                && tokens[close + 1].text == "."
                ? tokens[close + 2].text : nil
            result.append(.init(
                index: index,
                close: close,
                slot: slot,
                swizzle: swizzle
            ))
        }
        return result
    }

    private static func dataDeclaration(
        _ call: SampleCall,
        tokens: [Token]
    ) -> Bool {
        call.index >= 3
            && ["vec2", "float2"].contains(tokens[call.index - 3].text)
            && tokens[call.index - 2].kind == .identifier
            && tokens[call.index - 1].text == "="
            && ["rg", "xy"].contains(call.swizzle ?? "")
            && call.close + 3 < tokens.count
            && tokens[call.close + 3].text == ";"
    }

    private static func uniqueFunction(
        named name: String,
        fragment: Unit
    ) -> Unit.Function? {
        let matches = fragment.functions.filter { $0.name == name }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func functionReferenceCount(
        _ name: String,
        tokens: [Token]
    ) -> Int {
        tokens.indices.filter {
            tokens[$0].text == name
                && $0 + 1 < tokens.count
                && tokens[$0 + 1].text == "("
        }.count
    }

    private static func samplerType(slot: Int, fragment: Unit) -> String? {
        fragment.declarations.first(where: {
            $0.storage == .uniform && $0.name == "g_Texture\(slot)"
        })?.typeName
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ... 7).contains(slot) else { return nil }
        return slot
    }

    private static func matchingDelimiter(
        at index: Int,
        tokens: ArraySlice<Token>
    ) -> Int? {
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]
        guard tokens.indices.contains(index),
              let closing = pairs[tokens[index].text] else { return nil }
        var depth = 0
        for cursor in index..<tokens.endIndex {
            if tokens[cursor].text == tokens[index].text { depth += 1 }
            if tokens[cursor].text == closing {
                depth -= 1
                if depth == 0 { return cursor }
            }
        }
        return nil
    }

    private static func matchingOpeningDelimiter(
        at index: Int,
        tokens: [Token]
    ) -> Int? {
        let pairs: [String: String] = [")": "(", "]": "[", "}": "{"]
        guard tokens.indices.contains(index),
              let opening = pairs[tokens[index].text] else { return nil }
        var depth = 0
        for cursor in stride(from: index, through: 0, by: -1) {
            if tokens[cursor].text == tokens[index].text { depth += 1 }
            if tokens[cursor].text == opening {
                depth -= 1
                if depth == 0 { return cursor }
            }
        }
        return nil
    }
}

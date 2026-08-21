import Foundation

/// Source proof for a straight-RGB filter that keeps one sampled alpha intact.
/// Color samples may feed RGB math while `.rg` samples remain typed data. The
/// proof is structural and never inspects effect, material, path, or sample IDs.
nonisolated struct SceneAuthoredShaderPreservedAlphaRGBFilterFact: Equatable, Sendable {
    let sourceSlot: Int
    let fullColorSampleCallCounts: [Int: Int]
    let rgbColorSampleCallCounts: [Int: Int]
    let dataSampleCallCounts: [Int: Int]

    var colorSampleCallCounts: [Int: Int] {
        fullColorSampleCallCounts.merging(
            rgbColorSampleCallCounts,
            uniquingKeysWith: +
        )
    }
}

nonisolated enum SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer {
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
              calls.allSatisfy({ main.bodyRange.contains($0.index) }),
              calls.allSatisfy({ $0.index < output }),
              let sourceCall = calls.first(where: {
                  initializer.indices.contains($0.index)
              }),
              sourceCall.slot == sourceSlot,
              sourceCall.swizzle == nil
        else { return nil }

        let fullDeclarations = calls.compactMap { call -> (String, SampleCall)? in
            guard call.index >= 3,
                  ["vec4", "float4"].contains(tokens[call.index - 3].text),
                  tokens[call.index - 2].kind == .identifier,
                  tokens[call.index - 1].text == "=",
                  call.swizzle == nil,
                  call.close + 1 < tokens.count,
                  tokens[call.close + 1].text == ";" else { return nil }
            return (tokens[call.index - 2].text, call)
        }
        guard fullDeclarations.contains(where: {
            $0.0 == carrier && $0.1.index == sourceCall.index
        }) else { return nil }
        let bases = fullDeclarations.filter { $0.0 != carrier }
        guard bases.count <= 1,
              bases.allSatisfy({ $0.1.slot != sourceSlot }) else { return nil }

        var fullColorCounts: [Int: Int] = [sourceSlot: 1]
        var rgbColorCounts: [Int: Int] = [:]
        var dataCounts: [Int: Int] = [:]
        for call in calls where call.index != sourceCall.index {
            if let base = bases.first, call.index == base.1.index {
                fullColorCounts[call.slot, default: 0] += 1
                continue
            }
            if dataDeclaration(call, tokens: tokens) {
                guard call.slot != sourceSlot,
                      !bases.contains(where: { $0.1.slot == call.slot }) else {
                    return nil
                }
                dataCounts[call.slot, default: 0] += 1
                continue
            }
            if rgbAccumulation(
                call,
                carrier: carrier,
                body: main.bodyRange,
                tokens: tokens
            ) {
                guard call.slot == sourceSlot else { return nil }
                rgbColorCounts[call.slot, default: 0] += 1
                continue
            }
            return nil
        }
        let colorCounts = fullColorCounts.merging(
            rgbColorCounts,
            uniquingKeysWith: +
        )
        guard !dataCounts.isEmpty,
              colorCounts.values.allSatisfy({ (1 ... 16).contains($0) }),
              dataCounts.values.allSatisfy({ (1 ... 16).contains($0) }),
              colorCounts.values.reduce(0, +) + dataCounts.values.reduce(0, +) <= 32,
              Set(colorCounts.keys).isDisjoint(with: dataCounts.keys)
        else { return nil }

        let wholeAssignments = main.bodyRange.filter { index in
            index != definition
                && index + 1 < output
                && tokens[index].text == carrier
                && tokens[index + 1].text == "="
        }
        let blendAssignment: Int?
        if let base = bases.first {
            guard wholeAssignments.count == 1,
                  let assignment = wholeAssignments.first,
                  terminalRGBBlend(
                      at: assignment,
                      carrier: carrier,
                      base: base.0,
                      fragment: fragment,
                      main: main
                  ),
                  main.bodyRange.filter({ tokens[$0].text == base.0 }).count == 2
            else { return nil }
            blendAssignment = assignment
        } else {
            guard wholeAssignments.isEmpty else { return nil }
            blendAssignment = nil
        }
        guard carrierUsesAreAlphaPreserving(
            carrier: carrier,
            definition: definition,
            blendAssignment: blendAssignment,
            output: output,
            main: main,
            tokens: tokens
        ) else { return nil }

        return .init(
            sourceSlot: sourceSlot,
            fullColorSampleCallCounts: fullColorCounts,
            rgbColorSampleCallCounts: rgbColorCounts,
            dataSampleCallCounts: dataCounts
        )
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
                      tokens: tokens
                  ) else { return nil }
            let swizzle: String?
            if close + 2 < tokens.count, tokens[close + 1].text == "." {
                swizzle = tokens[close + 2].text
            } else {
                swizzle = nil
            }
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

    private static func rgbAccumulation(
        _ call: SampleCall,
        carrier: String,
        body: Range<Int>,
        tokens: [Token]
    ) -> Bool {
        guard ["rgb", "xyz"].contains(call.swizzle ?? ""),
              call.close + 3 < tokens.count,
              tokens[call.close + 3].text == ";" else { return false }
        var start = call.index
        while start > body.lowerBound + 1,
              ![";", "{", "}"].contains(tokens[start - 1].text) {
            start -= 1
        }
        return Array(tokens[start..<call.index]).map(\.text)
            == [carrier, ".", "rgb", "+="]
    }

    private static func terminalRGBBlend(
        at assignment: Int,
        carrier: String,
        base: String,
        fragment: Unit,
        main: Unit.Function
    ) -> Bool {
        let tokens = fragment.tokens
        guard SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                  assignment,
                  tokens: tokens,
                  body: main.bodyRange
              ),
              let expression = SceneAuthoredShaderColorTransferAnalyzer
                .assignmentExpression(
                    after: assignment,
                    in: tokens,
                    body: main.bodyRange
                ),
              let constructor = call(
                  named: ["vec4", "float4"],
                  tokens: Array(expression)
              ),
              constructor.count == 2,
              member(constructor[1], name: carrier, members: ["a", "w"]),
              let blend = call(
                  named: ["ApplyBlending"],
                  tokens: constructor[0]
              ),
              blend.count == 4,
              numericMode(blend[0], defines: fragment.defines),
              Set([
                  memberName(blend[1]),
                  memberName(blend[2]),
              ].compactMap({ $0 })) == Set([base, carrier]),
              member(blend[1], name: memberName(blend[1]) ?? "", members: ["rgb", "xyz"]),
              member(blend[2], name: memberName(blend[2]) ?? "", members: ["rgb", "xyz"]),
              !blend[3].contains(where: {
                  ["texSample2D", "texture2D", "gl_FragColor"].contains($0.text)
              }),
              fragment.functions.filter({ $0.name == "ApplyBlending" }).count == 1,
              let helper = fragment.functions.first(where: {
                  $0.name == "ApplyBlending"
              }),
              ["vec3", "float3"].contains(helper.returnType),
              !fragment.tokens[helper.parameterRange].contains(where: {
                  ["out", "inout"].contains($0.text)
              }),
              !fragment.tokens[helper.bodyRange].contains(where: {
                  ["texSample2D", "texture2D", "gl_FragColor"].contains($0.text)
              }) else { return false }
        let laterCarrierWrites = (assignment + 1)..<main.bodyRange.upperBound
        return !laterCarrierWrites.contains { index in
            index + 1 < tokens.count
                && tokens[index].text == carrier
                && (tokens[index + 1].text == "="
                    || (tokens[index + 1].text == "."
                        && index + 3 < tokens.count
                        && ["=", "+=", "-=", "*=", "/="].contains(
                            tokens[index + 3].text
                        )))
        }
    }

    private static func carrierUsesAreAlphaPreserving(
        carrier: String,
        definition: Int,
        blendAssignment: Int?,
        output: Int,
        main: Unit.Function,
        tokens: [Token]
    ) -> Bool {
        let assignments: Set<String> = ["=", "+=", "-=", "*=", "/="]
        for index in main.bodyRange where tokens[index].text == carrier {
            if index == definition || index == blendAssignment || index == output + 2 {
                continue
            }
            if index + 2 < tokens.count, tokens[index + 1].text == "." {
                let member = tokens[index + 2].text
                guard ["rgb", "xyz", "a", "w"].contains(member) else {
                    return false
                }
                if ["a", "w"].contains(member),
                   index + 3 < tokens.count,
                   assignments.contains(tokens[index + 3].text) {
                    return false
                }
                continue
            }
            if index >= 3,
               tokens[index - 1].text == "=",
               tokens[index - 2].kind == .identifier,
               ["vec4", "float4"].contains(tokens[index - 3].text),
               index + 1 < tokens.count,
               tokens[index + 1].text == ";" {
                let alias = tokens[index - 2].text
                guard main.bodyRange.filter({ tokens[$0].text == alias }).count == 1 else {
                    return false
                }
                continue
            }
            return false
        }
        return true
    }

    private static func call(named names: Set<String>, tokens: [Token]) -> [[Token]]? {
        guard tokens.count >= 3,
              names.contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")",
              matchingDelimiter(at: 1, tokens: tokens) == tokens.count - 1 else {
            return nil
        }
        var arguments: [[Token]] = []
        var start = 2
        var depth = 0
        for index in 2..<(tokens.count - 1) {
            if ["(", "[", "{"].contains(tokens[index].text) { depth += 1 }
            if [")", "]", "}"].contains(tokens[index].text) { depth -= 1 }
            if tokens[index].text == ",", depth == 0 {
                guard index > start else { return nil }
                arguments.append(Array(tokens[start..<index]))
                start = index + 1
            }
        }
        guard start < tokens.count - 1 else { return nil }
        arguments.append(Array(tokens[start..<(tokens.count - 1)]))
        return arguments
    }

    private static func member(
        _ tokens: [Token],
        name: String,
        members: Set<String>
    ) -> Bool {
        tokens.count == 3
            && tokens[0].text == name
            && tokens[1].text == "."
            && members.contains(tokens[2].text)
    }

    private static func memberName(_ tokens: [Token]) -> String? {
        guard tokens.count == 3, tokens[1].text == ".",
              ["rgb", "xyz"].contains(tokens[2].text) else { return nil }
        return tokens[0].text
    }

    private static func numericMode(
        _ tokens: [Token],
        defines: [String: String]
    ) -> Bool {
        guard tokens.count == 1 else { return false }
        let raw = defines[tokens[0].text] ?? tokens[0].text
        return Int(raw).map({ (0 ... 31).contains($0) }) == true
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
        tokens: [Token]
    ) -> Int? {
        let pairs: [String: String] = ["(": ")", "[": "]", "{": "}"]
        guard tokens.indices.contains(index),
              let closing = pairs[tokens[index].text] else { return nil }
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

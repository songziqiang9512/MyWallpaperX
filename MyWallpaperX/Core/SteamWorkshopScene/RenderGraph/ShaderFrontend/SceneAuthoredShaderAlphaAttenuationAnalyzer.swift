import Foundation

/// A source-derived proof that one prepared fragment preserves its sampled RGB
/// and changes coverage only by multiplying alpha with a bounded scalar graph.
/// The fact contains no effect, material, sample, path, or shader identity.
nonisolated struct SceneAuthoredShaderAlphaAttenuationFact: Equatable, Sendable {
    let sourceSlot: Int
    let auxiliaryRedSlots: Set<Int>
}

nonisolated enum SceneAuthoredShaderAlphaAttenuationAnalyzer {
    typealias Fact = SceneAuthoredShaderAlphaAttenuationFact
    private typealias Token = SceneAuthoredShaderToken
    private typealias Unit = SceneAuthoredShaderSyntaxUnit

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

    private static func analyze(_ fragment: Unit) -> Fact? {
        guard fragment.stage == .fragment,
              let main = fragment.functions.first(where: { $0.name == "main" }),
              let statements = topLevelStatements(
                  in: main.bodyRange,
                  tokens: fragment.tokens
              ),
              !statements.isEmpty else {
            return nil
        }
        let tokens = fragment.tokens
        let outputUses = main.bodyRange.filter {
            tokens[$0].text == "gl_FragColor"
        }
        guard outputUses.count == 1,
              let outputIndex = outputUses.first,
              statements.last?.contains(outputIndex) == true,
              let outputName = outputCarrier(
                  Array(tokens[statements[statements.count - 1]])
              ) else {
            return nil
        }

        let declarations = declarationFacts(fragment)
        var source: (name: String, slot: Int, statement: Int)?
        var scalarLocals: [String: [Int]] = [:]
        var attenuation: (statement: Int, auxiliarySlots: [Int])?

        for (position, range) in statements.dropLast().enumerated() {
            let statement = Array(tokens[range])
            if let color = colorSampleDeclaration(
                statement,
                declarations: declarations
            ) {
                guard source == nil,
                      color.name == outputName,
                      SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                          range.lowerBound + 1,
                          tokens: tokens,
                          body: main.bodyRange
                      ) else {
                    return nil
                }
                source = (color.name, color.slot, position)
                continue
            }

            guard let source else { return nil }
            if let scalar = scalarDeclaration(statement) {
                guard scalarLocals[scalar.name] == nil,
                      scalar.name != source.name,
                      let parsed = parseScalar(
                          tokens: scalar.expression,
                          floatUniforms: declarations.floatUniforms,
                          coordinateRoots: declarations.coordinateRoots,
                          scalarLocals: scalarLocals,
                          sourceName: source.name,
                          sourceSlot: source.slot
                      ) else {
                    return nil
                }
                scalarLocals[scalar.name] = parsed
                continue
            }
            if let factor = alphaMultiplication(
                statement,
                carrier: source.name
            ) {
                guard attenuation == nil,
                      SceneAuthoredShaderColorTransferAnalyzer.isUnconditionalWrite(
                          range.lowerBound,
                          tokens: tokens,
                          body: main.bodyRange
                      ), let parsed = parseScalar(
                          tokens: factor,
                          floatUniforms: declarations.floatUniforms,
                          coordinateRoots: declarations.coordinateRoots,
                          scalarLocals: scalarLocals,
                          sourceName: source.name,
                          sourceSlot: source.slot
                      ) else {
                    return nil
                }
                attenuation = (position, parsed)
                continue
            }
            return nil
        }

        guard let source, let attenuation,
              source.statement < attenuation.statement,
              exactCarrierUses(
                  source.name,
                  definitionStatement: statements[source.statement],
                  attenuationStatement: statements[attenuation.statement],
                  outputStatement: statements[statements.count - 1],
                  tokens: tokens,
                  body: main.bodyRange
              ), sampleCallCount(tokens: tokens, body: main.bodyRange)
                == 1 + attenuation.auxiliarySlots.count else {
            return nil
        }
        return Fact(
            sourceSlot: source.slot,
            auxiliaryRedSlots: Set(attenuation.auxiliarySlots)
        )
    }

    private struct DeclarationFacts {
        let floatUniforms: Set<String>
        let coordinateRoots: Set<String>
        let samplerSlots: Set<Int>
    }

    private static func declarationFacts(_ fragment: Unit) -> DeclarationFacts {
        var floats: Set<String> = []
        var coordinates: Set<String> = []
        var samplers: Set<Int> = []
        for declaration in fragment.declarations where declaration.arraySize == nil {
            if declaration.storage == .uniform, declaration.typeName == "float" {
                floats.insert(declaration.name)
            }
            if declaration.typeName == "sampler2D" {
                if let slot = textureSlot(declaration.name) {
                    samplers.insert(slot)
                }
            } else {
                coordinates.insert(declaration.name)
            }
        }
        return .init(
            floatUniforms: floats,
            coordinateRoots: coordinates,
            samplerSlots: samplers
        )
    }

    private static func colorSampleDeclaration(
        _ statement: [Token],
        declarations: DeclarationFacts
    ) -> (name: String, slot: Int)? {
        guard statement.count >= 7,
              ["vec4", "float4"].contains(statement[0].text),
              statement[1].kind == .identifier,
              statement[2].text == "=",
              let sample = directSample(
                  Array(statement.dropFirst(3)),
                  projection: nil,
                  coordinateRoots: declarations.coordinateRoots,
                  scalarLocals: []
              ), declarations.samplerSlots.contains(sample.slot) else {
            return nil
        }
        return (statement[1].text, sample.slot)
    }

    private static func scalarDeclaration(
        _ statement: [Token]
    ) -> (name: String, expression: [Token])? {
        guard statement.count >= 4,
              statement[0].text == "float",
              statement[1].kind == .identifier,
              statement[2].text == "=" else {
            return nil
        }
        return (statement[1].text, Array(statement.dropFirst(3)))
    }

    private static func alphaMultiplication(
        _ statement: [Token],
        carrier: String
    ) -> [Token]? {
        guard statement.count >= 5,
              statement[0].text == carrier,
              statement[1].text == ".",
              statement[2].text == "a",
              statement[3].text == "*=" else {
            return nil
        }
        return Array(statement.dropFirst(4))
    }

    private static func outputCarrier(_ statement: [Token]) -> String? {
        guard statement.count == 3,
              statement[0].text == "gl_FragColor",
              statement[1].text == "=",
              statement[2].kind == .identifier else {
            return nil
        }
        return statement[2].text
    }

    private static func exactCarrierUses(
        _ name: String,
        definitionStatement: Range<Int>,
        attenuationStatement: Range<Int>,
        outputStatement: Range<Int>,
        tokens: [Token],
        body: Range<Int>
    ) -> Bool {
        let uses = body.filter { tokens[$0].text == name }
        guard uses.count == 3 else { return false }
        return uses.contains(definitionStatement.lowerBound + 1)
            && uses.contains(attenuationStatement.lowerBound)
            && uses.contains(outputStatement.lowerBound + 2)
    }

    private static func topLevelStatements(
        in body: Range<Int>,
        tokens: [Token]
    ) -> [Range<Int>]? {
        guard body.count >= 2,
              tokens[body.lowerBound].text == "{",
              tokens[body.upperBound - 1].text == "}" else {
            return nil
        }
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

    private static func sampleCallCount(tokens: [Token], body: Range<Int>) -> Int {
        body.filter {
            ["texSample2D", "texture2D"].contains(tokens[$0].text)
        }.count
    }

    private static func directSample(
        _ tokens: [Token],
        projection: String?,
        coordinateRoots: Set<String>,
        scalarLocals: Set<String>
    ) -> (slot: Int, end: Int)? {
        guard tokens.count >= 6,
              ["texSample2D", "texture2D"].contains(tokens[0].text),
              tokens[1].text == "(",
              let close = matchingClose(1, tokens: tokens),
              let arguments = commaRanges(2..<close, tokens: tokens),
              arguments.count == 2,
              arguments[0].count == 1,
              let slot = textureSlot(tokens[arguments[0].lowerBound].text),
              safeCoordinate(
                  Array(tokens[arguments[1]]),
                  roots: coordinateRoots.union(scalarLocals)
              ) else {
            return nil
        }
        if let projection {
            guard close + 2 < tokens.count,
                  tokens[close + 1].text == ".",
                  tokens[close + 2].text == projection else {
                return nil
            }
            return (slot, close + 3)
        }
        return close == tokens.count - 1 ? (slot, close + 1) : nil
    }

    private static func parseScalar(
        tokens: [Token],
        floatUniforms: Set<String>,
        coordinateRoots: Set<String>,
        scalarLocals: [String: [Int]],
        sourceName: String,
        sourceSlot: Int
    ) -> [Int]? {
        var parser = ScalarParser(
            tokens: tokens,
            floatUniforms: floatUniforms,
            coordinateRoots: coordinateRoots,
            scalarLocals: scalarLocals,
            sourceName: sourceName,
            sourceSlot: sourceSlot
        )
        return parser.parse()
    }

    private static func safeCoordinate(
        _ tokens: [Token],
        roots: Set<String>
    ) -> Bool {
        guard !tokens.isEmpty, tokens.count <= 64 else { return false }
        var depth = 0
        for index in tokens.indices {
            let token = tokens[index]
            if ["=", "+=", "-=", "*=", "/=", "{", "}", ";"].contains(token.text) {
                return false
            }
            if token.text == "(" { depth += 1 }
            if token.text == ")" { depth -= 1 }
            guard depth >= 0 else { return false }
            guard token.kind == .identifier else { continue }
            if index > 0, tokens[index - 1].text == "." { continue }
            guard roots.contains(token.text),
                  index + 1 >= tokens.count || tokens[index + 1].text != "(" else {
                return false
            }
        }
        return depth == 0
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0...7).contains(slot) else {
            return nil
        }
        return slot
    }

    private static func matchingClose(_ open: Int, tokens: [Token]) -> Int? {
        guard tokens.indices.contains(open), tokens[open].text == "(" else {
            return nil
        }
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
            guard depth >= 0 else { return nil }
        }
        return nil
    }

    private static func commaRanges(
        _ range: Range<Int>,
        tokens: [Token]
    ) -> [Range<Int>]? {
        guard !range.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" { depth -= 1 }
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

    private struct ScalarParser {
        let tokens: [Token]
        let floatUniforms: Set<String>
        let coordinateRoots: Set<String>
        let scalarLocals: [String: [Int]]
        let sourceName: String
        let sourceSlot: Int
        private var index = 0
        private var auxiliarySlots: [Int] = []

        init(
            tokens: [Token],
            floatUniforms: Set<String>,
            coordinateRoots: Set<String>,
            scalarLocals: [String: [Int]],
            sourceName: String,
            sourceSlot: Int
        ) {
            self.tokens = tokens
            self.floatUniforms = floatUniforms
            self.coordinateRoots = coordinateRoots
            self.scalarLocals = scalarLocals
            self.sourceName = sourceName
            self.sourceSlot = sourceSlot
        }

        mutating func parse() -> [Int]? {
            guard expression(), index == tokens.count else { return nil }
            return auxiliarySlots
        }

        private mutating func expression() -> Bool {
            guard term() else { return false }
            while index < tokens.count, ["+", "-"].contains(tokens[index].text) {
                index += 1
                guard term() else { return false }
            }
            return true
        }

        private mutating func term() -> Bool {
            guard unary() else { return false }
            while index < tokens.count, ["*", "/"].contains(tokens[index].text) {
                index += 1
                guard unary() else { return false }
            }
            return true
        }

        private mutating func unary() -> Bool {
            if index < tokens.count, ["+", "-"].contains(tokens[index].text) {
                index += 1
                return unary()
            }
            return primary()
        }

        private mutating func primary() -> Bool {
            guard index < tokens.count else { return false }
            if tokens[index].text == "(" {
                index += 1
                guard expression(), index < tokens.count,
                      tokens[index].text == ")" else {
                    return false
                }
                index += 1
                return true
            }
            if tokens[index].kind == .number {
                guard finiteNumber(tokens[index].text) else { return false }
                index += 1
                return true
            }
            guard tokens[index].kind == .identifier else { return false }
            let name = tokens[index].text
            if index + 1 < tokens.count, tokens[index + 1].text == "(" {
                let suffix = Array(tokens[index...])
                guard let sample = directSample(
                    suffix,
                    projection: "r",
                    coordinateRoots: coordinateRoots,
                    scalarLocals: Set(scalarLocals.keys)
                ), sample.slot != sourceSlot else {
                    return false
                }
                auxiliarySlots.append(sample.slot)
                index += sample.end
                return true
            }
            guard name != sourceName else { return false }
            if floatUniforms.contains(name) {
                index += 1
                return true
            }
            guard let slots = scalarLocals[name] else { return false }
            auxiliarySlots.append(contentsOf: slots)
            index += 1
            return true
        }

        private func finiteNumber(_ raw: String) -> Bool {
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "fFuU"))
            return Double(trimmed).map(\.isFinite) == true
        }
    }
}

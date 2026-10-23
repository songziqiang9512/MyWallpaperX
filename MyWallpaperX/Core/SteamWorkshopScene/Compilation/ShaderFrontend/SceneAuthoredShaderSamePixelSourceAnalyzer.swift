import Foundation

/// An optional source-domain proof, not shader execution or color admission.
/// The caller still owns engine-uniform binding and source/output raster agreement.
nonisolated enum SceneAuthoredShaderSamePixelSourceAnalyzer {
    struct Fact: Codable, Equatable, Sendable {
        let textureSlot: Int
        let sampleCallCount: Int
        let coordinateVaryingName: String
        let positionMatrixUniformName: String
    }

    private typealias Unit = SceneAuthoredShaderSyntaxUnit
    private typealias Token = SceneAuthoredShaderToken
    private typealias Scanner = SceneAuthoredShaderTokenScanner

    private enum Lane: Equatable {
        case input(String, Int)
        case scalar(Double)
    }

    private enum IdentityTask {
        case expression(Range<Int>)
        case construct(arguments: Int, width: Int)
        case select([Int])
    }

    private struct Call {
        let name: String
        let range: Range<Int>
        let arguments: [Range<Int>]
    }

    static func analyze(vertexSource: String, fragmentSource: String) -> Fact? {
        guard let vertex = unit(vertexSource, stage: .vertex),
              let fragment = unit(fragmentSource, stage: .fragment),
              let samples = sourceSamples(fragment),
              let matrix = canonicalVertex(vertex, varying: samples.varying),
              let vertexSamplerUses = references("g_Texture0", in: vertex),
              vertexSamplerUses.isEmpty else { return nil }
        return Fact(textureSlot: 0, sampleCallCount: samples.count,
                    coordinateVaryingName: samples.varying,
                    positionMatrixUniformName: matrix)
    }

    /// Geometry admission can reuse the same identity-position proof without
    /// requiring a texture sample or constraining unrelated varying math.
    static func preservesTargetPixelFootprint(vertexSource: String) -> Bool {
        guard let unit = unit(vertexSource, stage: .vertex),
              declaration("a_Position", storage: .attribute, type: "vec3", in: unit),
              let main = unit.functions.first(where: { $0.name == "main" }),
              !unit.tokens[main.bodyRange].contains(where: {
                  ["return", "discard"].contains($0.text)
              }),
              let uses = references("gl_Position", in: unit), uses.count == 1,
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer.topLevelStatements(
                  in: main.bodyRange, tokens: unit.tokens, skippingNestedBlocks: true),
              let statement = statements.first(where: { $0.lowerBound == uses[0] }),
              statement.count > 2, unit.tokens[statement.lowerBound + 1].text == "=",
              positionMatrix((statement.lowerBound + 2)..<statement.upperBound, unit: unit)
                == "g_ModelViewProjectionMatrix" else { return false }
        return onlySafeUses("a_Position", protected: [0, 1, 2], in: unit,
                            producers: [], calls: callSites(unit))
    }

    private static func unit(_ source: String, stage: SceneShaderContract.StageKind) -> Unit? {
        let output = SceneAuthoredShaderSyntaxAnalyzer.analyzeForTypeConversions(
            lexerOutput: SceneAuthoredShaderLexer.lex(source: source, stage: stage), stage: stage)
        return output.diagnostics.isEmpty ? output.unit : nil
    }

    private static func sourceSamples(_ unit: Unit) -> (varying: String, width: Int, count: Int)? {
        guard declaration("g_Texture0", storage: .uniform, type: "sampler2D", in: unit),
              let main = unit.functions.first(where: { $0.name == "main" }),
              let uses = references("g_Texture0", in: unit), !uses.isEmpty else { return nil }
        let calls = callSites(unit)
        var consumed: Set<Int> = []
        var coordinate: (name: String, width: Int)?
        var count = 0
        for call in calls {
            let samplerUses = uses.filter(call.range.contains)
            guard !samplerUses.isEmpty else { continue }
            // An outer arithmetic/helper call can enclose a valid sample. Only
            // the call whose first argument is the sampler consumes its use.
            guard let first = call.arguments.first,
                  let sampler = Scanner.identifier(unit.tokens[stripped(first, in: unit)]), sampler == "g_Texture0",
                  let use = uses.first(where: stripped(first, in: unit).contains)
            else { continue }
            guard ["texture2D", "texSample2D"].contains(call.name),
                  !unit.functions.contains(where: { $0.name == call.name }),
                  call.arguments.count == 2,
                  main.bodyRange.contains(call.range.lowerBound),
                  let lanes = identity(call.arguments[1], unit: unit,
                                       storage: .varying), lanes.count == 2,
                  case let .input(name, 0) = lanes[0],
                  lanes[1] == .input(name, 1),
                  let varying = unit.declarations.first(where: { $0.name == name }),
                  let width = vectorWidth(varying.typeName),
                  coordinate == nil || (coordinate?.name == name && coordinate?.width == width),
                  consumed.insert(use).inserted else { return nil }
            coordinate = (name, width)
            count += 1
        }
        guard consumed == Set(uses), let coordinate,
              onlySafeUses(coordinate.name, protected: [0, 1], in: unit,
                           producers: [], calls: calls) else { return nil }
        return (coordinate.name, coordinate.width, count)
    }

    private static func canonicalVertex(_ unit: Unit, varying: String) -> String? {
        guard declaration("a_Position", storage: .attribute, type: "vec3", in: unit),
              declaration("a_TexCoord", storage: .attribute, type: "vec2", in: unit),
              let varyingDeclaration = unit.declarations.first(where: {
                  $0.name == varying && $0.storage == .varying && $0.arraySize == nil
              }), let width = vectorWidth(varyingDeclaration.typeName),
              let main = unit.functions.first(where: { $0.name == "main" }),
              !unit.tokens[main.bodyRange].contains(where: {
                  ["return", "discard"].contains($0.text)
              }),
              let statements = SceneAuthoredShaderUniformRGBMixAnalyzer.topLevelStatements(
                in: main.bodyRange, tokens: unit.tokens, skippingNestedBlocks: true),
              let positionUses = references("gl_Position", in: unit), positionUses.count == 1
        else { return nil }
        var matrix: String?
        var producers: Set<Int> = []
        var written: Set<Int> = []
        for statement in statements {
            let tokens = unit.tokens
            let start = statement.lowerBound
            if tokens[start].text == "gl_Position", statement.count > 2,
               tokens[start + 1].text == "=" {
                guard matrix == nil, positionUses == [start],
                      let name = positionMatrix((start + 2)..<statement.upperBound, unit: unit)
                else { return nil }
                matrix = name
            }
            guard let target = assignment(statement, name: varying, width: width, unit: unit),
                  target.lanes.contains(where: { $0 < 2 }) else { continue }
            guard let values = identity(target.value, unit: unit, storage: .attribute),
                  values.count == target.lanes.count else { return nil }
            for (lane, value) in zip(target.lanes, values) where lane < 2 {
                guard value == .input("a_TexCoord", lane), written.insert(lane).inserted
                else { return nil }
            }
            producers.insert(start)
        }
        let calls = callSites(unit)
        guard let matrix, written == [0, 1],
              onlySafeUses(varying, protected: [0, 1], in: unit,
                           producers: producers, calls: calls),
              onlySafeUses("a_TexCoord", protected: [0, 1], in: unit,
                           producers: [], calls: calls),
              onlySafeUses("a_Position", protected: [0, 1, 2], in: unit,
                           producers: [], calls: calls) else { return nil }
        return matrix
    }

    private static func positionMatrix(_ raw: Range<Int>, unit: Unit) -> String? {
        let range = stripped(raw, in: unit)
        let tokens = unit.tokens
        let vector: Range<Int>
        let matrix: Range<Int>
        if let call = call(range, unit: unit), call.name == "mul",
           !unit.functions.contains(where: { $0.name == "mul" }), call.arguments.count == 2 {
            vector = call.arguments[0]
            matrix = call.arguments[1]
        } else if let sides = Scanner.split(range, separator: "*", tokens: tokens), sides.count == 2 {
            // GLSL's matrix-times-column-vector is the engine mul(vector,matrix).
            matrix = sides[0]
            vector = sides[1]
        } else { return nil }
        guard let name = Scanner.identifier(unit.tokens[stripped(matrix, in: unit)]),
              declaration(name, storage: .uniform, type: "mat4", in: unit),
              let index = stripped(matrix, in: unit).first,
              references(name, in: unit)?.contains(index) == true,
              identity(vector, unit: unit, storage: .attribute) == [
                .input("a_Position", 0), .input("a_Position", 1),
                .input("a_Position", 2), .scalar(1)
              ] else { return nil }
        return name
    }

    private static func assignment(
        _ range: Range<Int>, name: String, width: Int, unit: Unit
    ) -> (lanes: [Int], value: Range<Int>)? {
        let tokens = unit.tokens
        let start = range.lowerBound
        guard tokens[start].text == name,
              references(name, in: unit)?.contains(start) == true else { return nil }
        if range.count > 2, tokens[start + 1].text == "=" {
            return (Array(0..<width), (start + 2)..<range.upperBound)
        }
        guard range.count > 4, tokens[start + 1].text == ".",
              let lanes = swizzle(tokens[start + 2].text), lanes.allSatisfy({ $0 < width }),
              tokens[start + 3].text == "=" else { return nil }
        return (lanes, (start + 4)..<range.upperBound)
    }

    private static func onlySafeUses(
        _ name: String, protected: Set<Int>, in unit: Unit,
        producers: Set<Int>, calls: [Call]
    ) -> Bool {
        guard let uses = references(name, in: unit) else { return false }
        for index in uses where !producers.contains(index) {
            var start = index
            var end = index + 1
            var selected: [Int]?
            while true {
                if start > 0, end < unit.tokens.count,
                   unit.tokens[start - 1].text == "(", unit.tokens[end].text == ")",
                   Scanner.matchingParenthesis(tokens: unit.tokens, opening: start - 1) == end,
                   start < 2 || unit.tokens[start - 2].kind != .identifier {
                    start -= 1
                    end += 1
                } else if end + 1 < unit.tokens.count, unit.tokens[end].text == ".",
                          let lanes = swizzle(unit.tokens[end + 1].text) {
                    if let current = selected {
                        guard lanes.allSatisfy({ $0 < current.count }) else { return false }
                        selected = lanes.map { current[$0] }
                    } else { selected = lanes }
                    end += 2
                } else { break }
            }
            // Out/inout or writes to independent zw lanes cannot change xy.
            if let selected, protected.isDisjoint(with: selected) { continue }
            guard Scanner.isReadOnlyValueUse(start: start, end: end, tokens: unit.tokens,
                body: 0..<unit.tokens.count, permitsReturn: true) else { return false }
            for call in calls where call.arguments.contains(where: { $0.contains(index) }) {
                if ["texture2D", "texSample2D", "mul"].contains(call.name),
                   !unit.functions.contains(where: { $0.name == call.name }) { continue }
                guard SceneAuthoredShaderColorTransferAnalyzer.helperCallsArePureAndUnsampled(
                    fragment: unit, expressionRanges: [call.range],
                    permitsUnexpandedBlendingHelper: false) else { return false }
            }
        }
        return true
    }

    /// Only grouping, identity vector construction and swizzles are reduced.
    /// The explicit work list uses the existing token budget rather than the
    /// native call stack, and never evaluates general author arithmetic.
    private static func identity(
        _ range: Range<Int>, unit: Unit, storage: Unit.Storage
    ) -> [Lane]? {
        var work: [IdentityTask] = [.expression(range)]
        var values: [[Lane]] = []
        while let task = work.popLast() {
            switch task {
            case let .expression(raw):
                let part = stripped(raw, in: unit)
                guard !part.isEmpty else { return nil }
                let tokens = unit.tokens
                if part.count >= 3, tokens[part.upperBound - 2].text == ".",
                   let lanes = swizzle(tokens[part.upperBound - 1].text) {
                    work.append(.select(lanes))
                    work.append(.expression(part.lowerBound..<(part.upperBound - 2)))
                } else if part.count == 1 {
                    let token = tokens[part.lowerBound]
                    if token.kind == .number, let scalar = Double(token.text), scalar.isFinite {
                        values.append([.scalar(scalar)])
                    } else {
                        guard let declaration = unit.declarations.first(where: {
                            $0.name == token.text && $0.storage == storage && $0.arraySize == nil
                        }), let width = vectorWidth(declaration.typeName),
                              references(token.text, in: unit)?.contains(part.lowerBound) == true
                        else { return nil }
                        values.append((0..<width).map { .input(token.text, $0) })
                    }
                } else if let call = call(part, unit: unit), let width = vectorWidth(call.name),
                          !unit.functions.contains(where: { $0.name == call.name }) {
                    work.append(.construct(arguments: call.arguments.count, width: width))
                    work += call.arguments.reversed().map { .expression($0) }
                } else { return nil }
            case let .select(lanes):
                guard let source = values.popLast(), lanes.allSatisfy({ $0 < source.count })
                else { return nil }
                values.append(lanes.map { source[$0] })
            case let .construct(arguments, width):
                guard arguments > 0, values.count >= arguments else { return nil }
                let lanes = values.suffix(arguments).flatMap { $0 }
                guard lanes.count == width else { return nil }
                values.removeLast(arguments)
                values.append(lanes)
            }
        }
        return values.count == 1 ? values[0] : nil
    }

    private static func callSites(_ unit: Unit) -> [Call] {
        unit.tokens.indices.compactMap { index in
            guard unit.tokens[index].kind == .identifier,
                  !["if", "for", "while", "switch"].contains(unit.tokens[index].text),
                  index + 1 < unit.tokens.count, unit.tokens[index + 1].text == "(",
                  let close = Scanner.matchingParenthesis(tokens: unit.tokens, opening: index + 1),
                  let arguments = Scanner.argumentRanges(in: (index + 2)..<close, tokens: unit.tokens)
            else { return nil }
            return Call(name: unit.tokens[index].text, range: index..<(close + 1), arguments: arguments)
        }
    }

    private static func call(_ range: Range<Int>, unit: Unit) -> Call? {
        let range = stripped(range, in: unit)
        guard range.count >= 3, unit.tokens[range.lowerBound].kind == .identifier,
              unit.tokens[range.lowerBound + 1].text == "(",
              Scanner.matchingParenthesis(tokens: unit.tokens, opening: range.lowerBound + 1)
                == range.upperBound - 1,
              let arguments = Scanner.argumentRanges(
                in: (range.lowerBound + 2)..<(range.upperBound - 1), tokens: unit.tokens)
        else { return nil }
        return Call(name: unit.tokens[range.lowerBound].text, range: range, arguments: arguments)
    }

    private static func stripped(_ raw: Range<Int>, in unit: Unit) -> Range<Int> {
        var range = raw
        while range.count >= 2, unit.tokens[range.lowerBound].text == "(",
              Scanner.matchingParenthesis(tokens: unit.tokens, opening: range.lowerBound)
                == range.upperBound - 1 { range = (range.lowerBound + 1)..<(range.upperBound - 1) }
        return range
    }

    private static func references(_ name: String, in unit: Unit) -> [Int]? {
        SceneAuthoredShaderGlobalReferenceAnalyzer.exactReferenceIndices(name, in: unit)
    }

    private static func declaration(
        _ name: String, storage: Unit.Storage, type: String, in unit: Unit
    ) -> Bool {
        unit.declarations.contains {
            $0.name == name && $0.storage == storage && $0.typeName == type && $0.arraySize == nil
        }
    }

    private static func vectorWidth(_ name: String) -> Int? {
        ["vec2": 2, "vec3": 3, "vec4": 4][name]
    }

    private static func swizzle(_ name: String) -> [Int]? {
        let components = ["xyzw", "rgba", "stpq"]
        guard !name.isEmpty, name.count <= 4,
              let alphabet = components.first(where: { Set(name).isSubset(of: Set($0)) })
        else { return nil }
        return name.compactMap { Array(alphabet).firstIndex(of: $0) }
    }
}

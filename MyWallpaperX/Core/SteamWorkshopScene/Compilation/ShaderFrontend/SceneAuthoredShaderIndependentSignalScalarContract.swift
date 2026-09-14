import Foundation

/// Owns the narrow, ordered scalar/vector provenance used by the independent
/// signal carrier proof. It is deliberately not a general shader dataflow.
nonisolated enum SceneAuthoredShaderIndependentSignalScalarContract {
    typealias Token = SceneAuthoredShaderToken
    typealias Unit = SceneAuthoredShaderSyntaxUnit

    fileprivate enum ValueKind: Equatable {
        case scalar
        case vector
        case sampler(Int)
        case projectedSample(Int)
    }

    fileprivate enum Ownership {
        case uniform
        case host
        case local
    }

    fileprivate struct Fact {
        let kind: ValueKind
        let ownership: Ownership
        let carrierDerived: Bool
    }

    struct State {
        fileprivate var facts: [String: Fact]
        fileprivate var declaredLocals: Set<String>
    }

    private struct LocalDeclaration {
        let type: String
        let name: String
        let expression: [Token]
    }

    private struct ParsedValue {
        var kind: ValueKind
    }

    private struct Parser {
        let tokens: [Token]
        let state: State
        let dataSlots: Set<Int>
        let authoredFunctions: Set<String>
        var cursor = 0

        mutating func parse() -> ValueKind? {
            guard let value = parseAdditive(), cursor == tokens.count else {
                return nil
            }
            switch value.kind {
            case .scalar, .vector: return value.kind
            case .sampler, .projectedSample: return nil
            }
        }

        private mutating func parseAdditive() -> ParsedValue? {
            guard var result = parseMultiplicative() else { return nil }
            while cursor < tokens.count, ["+", "-"].contains(tokens[cursor].text) {
                cursor += 1
                guard let right = parseMultiplicative(),
                      let combined = arithmetic(
                          result.kind, right.kind, operation: "+"
                      ) else { return nil }
                result = .init(kind: combined)
            }
            return result
        }

        private mutating func parseMultiplicative() -> ParsedValue? {
            guard var result = parseUnary() else { return nil }
            while cursor < tokens.count, ["*", "/"].contains(tokens[cursor].text) {
                let operation = tokens[cursor].text
                cursor += 1
                guard let right = parseUnary(),
                      let combined = arithmetic(
                          result.kind, right.kind, operation: operation
                      ) else { return nil }
                result = .init(kind: combined)
            }
            return result
        }

        private mutating func parseUnary() -> ParsedValue? {
            if cursor < tokens.count, ["+", "-"].contains(tokens[cursor].text) {
                cursor += 1
                guard let value = parseUnary(),
                      [.scalar, .vector].contains(value.kind) else { return nil }
                return value
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> ParsedValue? {
            guard cursor < tokens.count else { return nil }
            var value: ParsedValue
            if tokens[cursor].kind == .number {
                guard let number = Double(tokens[cursor].text), number.isFinite else {
                    return nil
                }
                cursor += 1
                value = .init(kind: .scalar)
            } else if tokens[cursor].text == "(" {
                cursor += 1
                guard let nested = parseAdditive(), consume(")") else { return nil }
                value = nested
            } else {
                guard tokens[cursor].kind == .identifier else { return nil }
                let name = tokens[cursor].text
                cursor += 1
                if consume("(") {
                    guard let called = parseCall(named: name) else { return nil }
                    value = called
                } else if let fact = state.facts[name] {
                    value = .init(kind: fact.kind)
                } else {
                    return nil
                }
            }
            while consume(".") {
                guard cursor < tokens.count,
                      tokens[cursor].kind == .identifier,
                      let projected = projection(
                          tokens[cursor].text, from: value.kind
                      ) else { return nil }
                cursor += 1
                value = .init(kind: projected)
            }
            return value
        }

        private mutating func parseCall(named name: String) -> ParsedValue? {
            var arguments: [ValueKind] = []
            repeat {
                guard let argument = parseAdditive() else { return nil }
                arguments.append(argument.kind)
                if consume(")") { break }
                guard consume(",") else { return nil }
            } while true

            if ["texSample2D", "texture2D"].contains(name) {
                guard arguments.count == 2,
                      case let .sampler(slot) = arguments[0],
                      arguments[1] == .vector,
                      dataSlots.contains(slot) else { return nil }
                return .init(kind: .projectedSample(slot))
            }
            guard !authoredFunctions.contains(name) else { return nil }
            switch (name, arguments) {
            case ("length", [.vector]):
                return .init(kind: .scalar)
            case ("step", [.scalar, .scalar]),
                 ("min", [.scalar, .scalar]):
                return .init(kind: .scalar)
            case ("CAST2", [.scalar]),
                 ("vec2", [.scalar]),
                 ("float2", [.scalar]):
                return .init(kind: .vector)
            default:
                return nil
            }
        }

        private func projection(_ member: String, from kind: ValueKind) -> ValueKind? {
            switch kind {
            case .vector:
                if ["x", "y", "z", "w", "r", "g", "b", "a"].contains(member) {
                    return .scalar
                }
                if ["xy", "rg", "xyz", "rgb"].contains(member) {
                    return .vector
                }
                return nil
            case .projectedSample:
                if ["xy", "rg"].contains(member) { return .vector }
                return nil
            case .scalar, .sampler:
                return nil
            }
        }

        private func arithmetic(
            _ left: ValueKind, _ right: ValueKind, operation: String
        ) -> ValueKind? {
            if left == .scalar, right == .scalar { return .scalar }
            guard [.scalar, .vector].contains(left),
                  [.scalar, .vector].contains(right) else { return nil }
            if operation == "+" || operation == "-" {
                return left == .vector && right == .vector ? .vector : nil
            }
            return left == .vector || right == .vector ? .vector : nil
        }

        private mutating func consume(_ text: String) -> Bool {
            guard cursor < tokens.count, tokens[cursor].text == text else {
                return false
            }
            cursor += 1
            return true
        }
    }

    static func state(
        before boundary: Int,
        carrier: String,
        dataSlots: Set<Int>,
        statements: [Range<Int>],
        fragment: Unit
    ) -> State {
        var state = initialState(fragment: fragment, dataSlots: dataSlots)
        for range in statements where range.lowerBound < boundary {
            let statement = Array(fragment.tokens[range])
            let declaration = localDeclaration(statement)
            if let declaration {
                state.facts.removeValue(forKey: declaration.name)
            }
            invalidateUnsafeUses(
                in: statement, state: &state, dataSlots: dataSlots,
                fragment: fragment
            )
            guard let declaration,
                  !state.declaredLocals.contains(declaration.name) else {
                if let declaration { state.declaredLocals.insert(declaration.name) }
                continue
            }
            state.declaredLocals.insert(declaration.name)
            guard declaration.name != carrier else { continue }
            if scalarTypes.contains(declaration.type),
               let fact = scalarFact(
                   declaration, carrier: carrier, state: state,
                   dataSlots: dataSlots, fragment: fragment
               ) {
                state.facts[declaration.name] = fact
            } else if vectorTypes.contains(declaration.type),
                      expressionKind(
                          declaration.expression, state: state,
                          dataSlots: dataSlots, fragment: fragment
                      ) == .vector {
                state.facts[declaration.name] = .init(
                    kind: .vector, ownership: .local,
                    carrierDerived: false
                )
            }
        }
        return state
    }

    static func isScalar(
        _ expression: [Token],
        state: State,
        dataSlots: Set<Int>,
        fragment: Unit
    ) -> Bool {
        expressionKind(
            expression, state: state, dataSlots: dataSlots,
            fragment: fragment
        ) == .scalar
    }

    static func isCarrierRGBScalarDeclaration(
        _ statement: [Token],
        carrier: String,
        state: State,
        dataSlots: Set<Int>,
        fragment: Unit
    ) -> Bool {
        guard let declaration = localDeclaration(statement),
              scalarTypes.contains(declaration.type) else { return false }
        return carrierRGBScalar(
            declaration.expression, carrier: carrier, state: state,
            dataSlots: dataSlots, fragment: fragment
        )
    }

    private static let scalarTypes: Set<String> = [
        "float", "double", "int", "uint",
    ]
    private static let vectorTypes: Set<String> = [
        "vec2", "vec3", "vec4", "float2", "float3", "float4",
        "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4",
    ]

    private static func initialState(
        fragment: Unit, dataSlots: Set<Int>
    ) -> State {
        let grouped = Dictionary(grouping: fragment.declarations, by: \.name)
        var facts: [String: Fact] = [:]
        for (name, declarations) in grouped where declarations.count == 1 {
            let declaration = declarations[0]
            guard declaration.arraySize == nil else { continue }
            if declaration.storage == .uniform,
               scalarTypes.contains(declaration.typeName) {
                facts[name] = .init(
                    kind: .scalar, ownership: .uniform,
                    carrierDerived: false
                )
            } else if declaration.storage == .uniform,
                      vectorTypes.contains(declaration.typeName) {
                facts[name] = .init(
                    kind: .vector, ownership: .uniform,
                    carrierDerived: false
                )
            } else if declaration.storage == .varying,
                      vectorTypes.contains(declaration.typeName) {
                facts[name] = .init(
                    kind: .vector, ownership: .host,
                    carrierDerived: false
                )
            } else if declaration.storage == .uniform,
                      declaration.typeName == "sampler2D",
                      let slot = textureSlot(name), dataSlots.contains(slot) {
                facts[name] = .init(
                    kind: .sampler(slot), ownership: .uniform,
                    carrierDerived: false
                )
            }
        }
        return .init(facts: facts, declaredLocals: [])
    }

    private static func scalarFact(
        _ declaration: LocalDeclaration,
        carrier: String,
        state: State,
        dataSlots: Set<Int>,
        fragment: Unit
    ) -> Fact? {
        if expressionKind(
            declaration.expression, state: state, dataSlots: dataSlots,
            fragment: fragment
        ) == .scalar {
            return .init(
                kind: .scalar, ownership: .local,
                carrierDerived: false
            )
        }
        if carrierRGBScalar(
            declaration.expression, carrier: carrier, state: state,
            dataSlots: dataSlots, fragment: fragment
        ) {
            return .init(
                kind: .scalar, ownership: .local,
                carrierDerived: true
            )
        }
        return nil
    }

    private static func expressionKind(
        _ expression: [Token],
        state: State,
        dataSlots: Set<Int>,
        fragment: Unit
    ) -> ValueKind? {
        guard !expression.isEmpty else { return nil }
        var parser = Parser(
            tokens: expression, state: state, dataSlots: dataSlots,
            authoredFunctions: Set(fragment.functions.map(\.name))
        )
        return parser.parse()
    }

    private static func carrierRGBScalar(
        _ expression: [Token],
        carrier: String,
        state: State,
        dataSlots: Set<Int>,
        fragment: Unit
    ) -> Bool {
        guard expression.filter({ $0.text == carrier }).count == 1,
              let pieces = scalarRGBReadPieces(expression),
              let step = call(pieces.step), step.name == "step",
              step.arguments.count == 2,
              !hasAuthoredFunction(named: "step", fragment: fragment),
              let length = call(step.arguments[0]), length.name == "length",
              length.arguments.count == 1,
              !hasAuthoredFunction(named: "length", fragment: fragment),
              length.arguments[0].count == 3,
              length.arguments[0][0].text == carrier,
              length.arguments[0][1].text == ".",
              ["rgb", "xyz"].contains(length.arguments[0][2].text),
              isScalar(
                  step.arguments[1], state: state, dataSlots: dataSlots,
                  fragment: fragment
              ) else { return false }
        return pieces.factor.map {
            isScalar(
                $0, state: state, dataSlots: dataSlots,
                fragment: fragment
            )
        } ?? true
    }

    private static func localDeclaration(_ statement: [Token]) -> LocalDeclaration? {
        guard statement.count >= 2,
              statement[0].kind == .identifier,
              statement[1].kind == .identifier else { return nil }
        let expression = statement.count >= 4 && statement[2].text == "="
            ? Array(statement.dropFirst(3)) : []
        return .init(
            type: statement[0].text, name: statement[1].text,
            expression: expression
        )
    }

    private static func invalidateUnsafeUses(
        in statement: [Token],
        state: inout State,
        dataSlots: Set<Int>,
        fragment: Unit
    ) {
        let invalidated = state.facts.compactMap { name, fact -> String? in
            guard fact.ownership == .local else { return nil }
            return unsafeUse(
                of: name, in: statement, dataSlots: dataSlots,
                fragment: fragment
            ) ? name : nil
        }
        for name in invalidated { state.facts.removeValue(forKey: name) }
    }

    private static func unsafeUse(
        of name: String,
        in statement: [Token],
        dataSlots: Set<Int>,
        fragment: Unit
    ) -> Bool {
        let occurrences = statement.indices.filter { statement[$0].text == name }
        guard !occurrences.isEmpty else { return false }
        if occurrences.contains(where: {
            isWriteRoot(at: $0, tokens: statement)
        }) { return true }
        let calls = callRanges(tokens: statement)
        for occurrence in occurrences {
            for candidate in calls where
                candidate.arguments.contains(occurrence)
                    && !whitelistedCall(
                        candidate, tokens: statement, dataSlots: dataSlots,
                        fragment: fragment
                    ) {
                return true
            }
        }
        return false
    }

    private static func isWriteRoot(at index: Int, tokens: [Token]) -> Bool {
        let writes: Set<String> = [
            "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
            "<<=", ">>=", "++", "--",
        ]
        if index > 0, ["++", "--"].contains(tokens[index - 1].text) {
            return true
        }
        var prefixCursor = index
        while prefixCursor > 0, tokens[prefixCursor - 1].text == "(" {
            let opening = prefixCursor - 1
            guard let closing = matchingDelimiter(at: opening, tokens: tokens),
                  closing > index else { break }
            prefixCursor = opening
        }
        if prefixCursor > 0,
           ["++", "--"].contains(tokens[prefixCursor - 1].text) {
            return true
        }
        var cursor = index + 1
        while cursor < tokens.count, tokens[cursor].text == ")" { cursor += 1 }
        chain: while cursor < tokens.count {
            switch tokens[cursor].text {
            case ".":
                guard cursor + 1 < tokens.count,
                      tokens[cursor + 1].kind == .identifier else { return true }
                cursor += 2
            case "[":
                guard let close = matchingDelimiter(at: cursor, tokens: tokens) else {
                    return true
                }
                cursor = close + 1
            default:
                break chain
            }
            while cursor < tokens.count, tokens[cursor].text == ")" { cursor += 1 }
        }
        if cursor < tokens.count, writes.contains(tokens[cursor].text) {
            return true
        }
        return cursor + 1 < tokens.count
            && ["<<", ">>"].contains(tokens[cursor].text)
            && tokens[cursor + 1].text == "="
    }

    private struct CallRange {
        let name: String
        let arguments: Range<Int>
        let arity: Int
    }

    private static func callRanges(tokens: [Token]) -> [CallRange] {
        let controls: Set<String> = ["if", "for", "while", "switch"]
        return tokens.indices.compactMap { index in
            guard index + 1 < tokens.count,
                  tokens[index].kind == .identifier,
                  tokens[index + 1].text == "(",
                  !controls.contains(tokens[index].text),
                  let close = matchingDelimiter(at: index + 1, tokens: tokens),
                  let arguments = commaRanges(
                      (index + 2)..<close, tokens: tokens
                  ) else { return nil }
            return .init(
                name: tokens[index].text,
                arguments: (index + 2)..<close,
                arity: arguments.count
            )
        }
    }

    private static func whitelistedCall(
        _ call: CallRange,
        tokens: [Token],
        dataSlots: Set<Int>,
        fragment: Unit
    ) -> Bool {
        if ["texSample2D", "texture2D"].contains(call.name) {
            guard call.arity == 2,
                  call.arguments.lowerBound < call.arguments.upperBound,
                  let slot = textureSlot(tokens[call.arguments.lowerBound].text) else {
                return false
            }
            return fragment.declarations.contains {
                $0.storage == .uniform && $0.arraySize == nil
                    && $0.typeName == "sampler2D"
                    && $0.name == "g_Texture\(slot)"
            }
        }
        let arities = [
            "length": 1, "step": 2, "min": 2,
            "CAST2": 1, "vec2": 1, "float2": 1,
        ]
        return arities[call.name] == call.arity
            && !hasAuthoredFunction(named: call.name, fragment: fragment)
    }

    private struct ParsedCall {
        let name: String
        let arguments: [[Token]]
    }

    private static func call(_ tokens: [Token]) -> ParsedCall? {
        guard tokens.count >= 3, tokens[0].kind == .identifier,
              tokens[1].text == "(",
              matchingDelimiter(at: 1, tokens: tokens) == tokens.count - 1,
              let ranges = commaRanges(2..<(tokens.count - 1), tokens: tokens)
        else { return nil }
        return .init(
            name: tokens[0].text,
            arguments: ranges.map { Array(tokens[$0]) }
        )
    }

    private static func scalarRGBReadPieces(
        _ expression: [Token]
    ) -> (step: [Token], factor: [Token]?)? {
        var depth = 0
        for index in expression.indices {
            switch expression[index].text {
            case "(": depth += 1
            case ")": depth -= 1
            case "*" where depth == 0, "/" where depth == 0:
                guard index > 0, index + 1 < expression.count else { return nil }
                return (
                    Array(expression[..<index]),
                    Array(expression[(index + 1)...])
                )
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        return depth == 0 ? (expression, nil) : nil
    }

    private static func commaRanges(
        _ range: Range<Int>, tokens: [Token]
    ) -> [Range<Int>]? {
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

    private static func matchingDelimiter(
        at index: Int, tokens: [Token]
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

    private static func hasAuthoredFunction(
        named name: String, fragment: Unit
    ) -> Bool {
        fragment.functions.contains(where: { $0.name == name })
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ... 7).contains(slot) else { return nil }
        return slot
    }
}

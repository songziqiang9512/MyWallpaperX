import Foundation

nonisolated extension SceneAuthoredShaderUniformRGBMixAnalyzer {
    static func scalarValue(
        _ tokens: [Token], context: ScalarContext
    ) -> ScalarValue? {
        var parser = ScalarParser(tokens: tokens, context: context)
        return parser.parse()
    }

    static func call(
        _ tokens: [Token]
    ) -> (name: String, arguments: [[Token]])? {
        guard tokens.count >= 3, tokens[0].kind == .identifier,
              tokens[1].text == "(",
              matchingClose(1, tokens: tokens) == tokens.count - 1,
              let ranges = commaRanges(
                  2..<(tokens.count - 1), tokens: tokens
              ) else { return nil }
        return (tokens[0].text, ranges.map { Array(tokens[$0]) })
    }

    static func safeCoordinate(
        _ tokens: [Token], fragment: Unit
    ) -> Bool {
        if tokens.count == 1, let token = tokens.first,
           token.kind == .identifier {
            return fragment.declarations.contains {
                $0.name == token.text && $0.storage == .varying
                    && ["vec2", "float2"].contains($0.typeName)
            }
        }
        guard tokens.count == 3, tokens[0].kind == .identifier,
              tokens[1].text == ".", ["xy", "zw"].contains(tokens[2].text)
        else { return false }
        return fragment.declarations.contains {
            guard $0.name == tokens[0].text, $0.storage == .varying else {
                return false
            }
            if ["vec4", "float4"].contains($0.typeName) { return true }
            return tokens[2].text == "xy"
                && ["vec2", "float2"].contains($0.typeName)
        }
    }

    private struct ScalarParser {
        let tokens: [Token]
        let context: ScalarContext
        var index = 0

        mutating func parse() -> ScalarValue? {
            guard let value = addition(), index == tokens.count else { return nil }
            return value
        }

        private mutating func addition() -> ScalarValue? {
            guard var value = multiplication() else { return nil }
            while index < tokens.count,
                  ["+", "-"].contains(tokens[index].text) {
                index += 1
                guard let right = multiplication() else { return nil }
                value = .init(
                    fact: .finite,
                    dependencies: value.dependencies.union(right.dependencies)
                )
            }
            return value
        }

        private mutating func multiplication() -> ScalarValue? {
            guard var value = unary() else { return nil }
            while index < tokens.count,
                  ["*", "/"].contains(tokens[index].text) {
                let operation = tokens[index].text
                index += 1
                guard let right = unary(),
                      operation != "/" || right.fact.isStrictlyPositive else {
                    return nil
                }
                let fact: ScalarFact = value.fact == .positive
                    && right.fact == .positive ? .positive : .finite
                value = .init(
                    fact: fact,
                    dependencies: value.dependencies.union(right.dependencies)
                )
            }
            return value
        }

        private mutating func unary() -> ScalarValue? {
            if index < tokens.count,
               ["+", "-"].contains(tokens[index].text) {
                let operation = tokens[index].text
                index += 1
                guard let value = unary() else { return nil }
                return operation == "+" ? value : .init(
                    fact: .finite, dependencies: value.dependencies
                )
            }
            return primary()
        }

        private mutating func primary() -> ScalarValue? {
            guard index < tokens.count else { return nil }
            if tokens[index].text == "(" {
                index += 1
                guard let value = addition(), index < tokens.count,
                      tokens[index].text == ")" else { return nil }
                index += 1
                return value
            }
            if tokens[index].kind == .number {
                guard let number = Double(tokens[index].text), number.isFinite else {
                    return nil
                }
                index += 1
                return .init(
                    fact: number > 0 ? .positive : .finite,
                    dependencies: []
                )
            }
            guard tokens[index].kind == .identifier else { return nil }
            let name = tokens[index].text
            if index + 1 < tokens.count, tokens[index + 1].text == "(" {
                return function(name)
            }
            if let value = context.variables[name] {
                index += 1
                return .init(
                    fact: value.fact,
                    dependencies: value.dependencies.union([name])
                )
            }
            guard let type = context.globals[name], type != "sampler2D" else {
                return nil
            }
            index += 1
            if ["float", "int", "uint", "bool"].contains(type) {
                return .init(fact: .finite, dependencies: [])
            }
            guard index + 1 < tokens.count, tokens[index].text == ".",
                  tokens[index + 1].kind == .identifier,
                  tokens[index + 1].text.count == 1 else { return nil }
            index += 2
            return .init(fact: .finite, dependencies: [])
        }

        private mutating func function(_ name: String) -> ScalarValue? {
            guard let close = matchingClose(index + 1, tokens: tokens),
                  let ranges = commaRanges(
                      (index + 2)..<close, tokens: tokens
                  ) else { return nil }
            var arguments: [ScalarValue] = []
            for range in ranges {
                guard let value = scalarValue(
                    Array(tokens[range]), context: context
                ) else { return nil }
                arguments.append(value)
            }
            let dependencies = arguments.reduce(into: Set<String>()) {
                $0.formUnion($1.dependencies)
            }
            let fact: ScalarFact
            switch (name, arguments.count) {
            case ("saturate", 1), ("frac", 1), ("fract", 1),
                 ("step", 2), ("smoothstep", 3):
                fact = .bounded01
            case ("floor", 1):
                fact = .finite
            case ("max", 2):
                fact = arguments.contains(where: { $0.fact == .positive })
                    ? .positive : .finite
            case ("min", 2):
                fact = arguments.allSatisfy { $0.fact == .positive }
                    ? .positive : .finite
            case ("clamp", 3):
                fact = arguments[1].fact == .positive
                    && arguments[2].fact == .positive ? .positive : .finite
            default:
                guard let helper = evaluateHelper(
                    name: name,
                    arguments: arguments,
                    context: context
                ) else { return nil }
                index = close + 1
                return helper
            }
            index = close + 1
            return .init(fact: fact, dependencies: dependencies)
        }
    }

    private static func evaluateHelper(
        name: String,
        arguments: [ScalarValue],
        context: ScalarContext
    ) -> ScalarValue? {
        guard !context.helperStack.contains(name) else { return nil }
        let matches = context.fragment.functions.filter { $0.name == name }
        guard matches.count == 1, let helper = matches.first,
              helper.returnType == "float",
              let parameters = scalarParameters(
                  helper.parameterRange,
                  tokens: context.fragment.tokens
              ), parameters.count == arguments.count,
              let statements = topLevelStatements(
                  in: helper.bodyRange, tokens: context.fragment.tokens
              ), (2 ... 16).contains(statements.count),
              !statements.dropLast().contains(where: {
                  context.fragment.tokens[$0].contains(where: {
                      ["return", "discard", "if", "else", "for", "while"]
                          .contains($0.text)
                  })
              }) else { return nil }

        var variables: [String: ScalarValue] = [:]
        for (parameter, value) in zip(parameters, arguments) {
            variables[parameter] = .init(
                fact: value.fact,
                dependencies: [parameter]
            )
        }
        var localDefinitions: [String: ScalarValue] = [:]
        let nextStack = context.helperStack.union([name])
        for range in statements.dropLast() {
            let statement = Array(context.fragment.tokens[range])
            guard let declaration = scalarDeclaration(statement),
                  variables[declaration.name] == nil,
                  let value = scalarValue(
                      declaration.expression,
                      context: .init(
                          fragment: context.fragment,
                          variables: variables,
                          globals: context.globals,
                          helperStack: nextStack
                      )
                  ) else { return nil }
            variables[declaration.name] = value
            localDefinitions[declaration.name] = value
        }
        let result = Array(context.fragment.tokens[statements.last!])
        guard result.count >= 2, result[0].text == "return",
              let value = scalarValue(
                  Array(result.dropFirst()),
                  context: .init(
                      fragment: context.fragment,
                      variables: variables,
                      globals: context.globals,
                      helperStack: nextStack
                  )
              ) else { return nil }
        let parameterNames = Set(parameters)
        let localDependencies = value.dependencies.intersection(
            Set(localDefinitions.keys)
        )
        guard localDependencies == Set(localDefinitions.keys) else { return nil }
        let usedParameters = value.dependencies.intersection(parameterNames)
        let argumentDependencies = zip(parameters, arguments).reduce(
            into: Set<String>()
        ) { result, pair in
            guard usedParameters.contains(pair.0) else { return }
            result.formUnion(pair.1.dependencies)
        }
        return .init(
            fact: value.fact,
            dependencies: value.dependencies
                .subtracting(localDefinitions.keys)
                .subtracting(parameterNames)
                .union(argumentDependencies)
        )
    }

    private static func scalarParameters(
        _ range: Range<Int>, tokens: [Token]
    ) -> [String]? {
        guard let ranges = commaRanges(range, tokens: tokens) else { return nil }
        return ranges.map { part -> String? in
            let values = Array(tokens[part]).filter {
                !["const", "in"].contains($0.text)
            }
            guard values.count == 2, values[0].text == "float",
                  values[1].kind == .identifier else { return nil }
            return values[1].text
        }.compactMap { $0 }.count == ranges.count
            ? ranges.compactMap { part in
                Array(tokens[part]).last(where: { $0.kind == .identifier })?.text
            } : nil
    }

    static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }

    private static func matchingClose(
        _ open: Int, tokens: [Token]
    ) -> Int? {
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
        _ range: Range<Int>, tokens: [Token]
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
}

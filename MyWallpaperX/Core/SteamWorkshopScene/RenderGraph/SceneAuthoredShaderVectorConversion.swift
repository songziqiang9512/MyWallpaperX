nonisolated enum SceneAuthoredShaderVectorConversion {
    private struct Conversion: Hashable {
        let range: Range<Int>
        let suffix: String
    }

    private struct Operand: Hashable {
        let range: Range<Int>
        let type: SceneAuthoredShaderValueType
    }

    private static func conversions(
        in tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> [Conversion] {
        tokens.indices.flatMap { index -> [Conversion] in
            guard tokens[index].text == "=",
                  index > 0,
                  tokens[index - 1].kind == .identifier,
                  let end = statementEnd(after: index, in: tokens),
                  let target = declaredType(
                      of: tokens[index - 1].text,
                      before: index,
                      tokens: tokens,
                      unit: unit
                  ),
                  let operands = multiplicativeOperands(
                      tokens[(index + 1)..<end],
                      before: index,
                      allTokens: tokens,
                      unit: unit
                  ), let targetWidth = floatVectorWidth(target) else {
                return []
            }
            let vectorOperands = operands.filter { floatVectorWidth($0.type) != nil }
            guard let operationWidth = vectorOperands.compactMap({
                floatVectorWidth($0.type)
            }).min(), operationWidth >= targetWidth else { return [] }
            var result = vectorOperands.compactMap { operand -> Conversion? in
                guard let width = floatVectorWidth(operand.type),
                      width > operationWidth,
                      let suffix = narrowingSuffix(from: width, to: operationWidth)
                else { return nil }
                return Conversion(range: operand.range, suffix: suffix)
            }
            if operationWidth > targetWidth,
               let suffix = narrowingSuffix(from: operationWidth, to: targetWidth) {
                result.append(.init(range: (index + 1)..<end, suffix: suffix))
            }
            return result
        }
    }

    static func assignmentBoundaries(
        in tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> (starts: [Int: Int], ends: [Int: [String]]) {
        let values = conversions(in: tokens, unit: unit)
        let starts = Dictionary(grouping: values, by: { $0.range.lowerBound })
            .mapValues(\.count)
        let ends = Dictionary(grouping: values, by: { $0.range.upperBound })
            .mapValues { $0.sorted { $0.range.count < $1.range.count }.map(\.suffix) }
        return (starts, ends)
    }

    static func suffix(
        forIdentifierAt index: Int,
        in tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> String? {
        if let suffix = SceneAuthoredShaderBuiltInVectorConversion.suffix(
            forIdentifierAt: index,
            in: tokens,
            unit: unit
        ) { return suffix }
        guard tokens.indices.contains(index),
              tokens[index].kind == .identifier,
              let opening = enclosingCallOpening(for: index, in: tokens),
              opening > 0,
              let closing = matchingParenthesis(tokens: tokens, opening: opening),
              tokens[opening - 1].kind == .identifier,
              let argumentIndex = standaloneArgumentIndex(
                  containing: index,
                  opening: opening,
                  closing: closing,
                  tokens: tokens
              ) else { return nil }
        let candidates = unit.functions.filter { $0.name == tokens[opening - 1].text }
        let profiles = candidates.compactMap { parameterTypes(for: $0, unit: unit) }
        let targetTypes = Set(profiles.compactMap { profile in
            profile.indices.contains(argumentIndex) ? profile[argumentIndex] : nil
        })
        let sourceTypes = Set(unit.declarations.compactMap { declaration in
            declaration.name == tokens[index].text
                ? SceneAuthoredShaderValueType(authoredName: declaration.typeName)
                : nil
        })
        guard !candidates.isEmpty,
              profiles.count == candidates.count,
              targetTypes.count == 1,
              sourceTypes.count == 1,
              let target = targetTypes.first,
              let source = sourceTypes.first else { return nil }
        return narrowingSuffix(from: source, to: target)
    }

    static func suffixForTextureSample(
        tokens: [SceneAuthoredShaderToken],
        start: Int,
        closing: Int
    ) -> String? {
        guard start >= 2,
              closing + 1 < tokens.count,
              tokens[start - 1].text == "=",
              tokens[closing + 1].text == ";",
              tokens[start - 2].kind == .identifier else { return nil }
        var targets: Set<SceneAuthoredShaderValueType> = []
        for index in 0..<(start - 1) where index + 1 < tokens.count {
            guard tokens[index + 1].text == tokens[start - 2].text,
                  let type = SceneAuthoredShaderValueType(
                      authoredName: tokens[index].text
                  ) else { continue }
            targets.insert(type)
        }
        guard targets.count == 1, let target = targets.first else { return nil }
        return narrowingSuffix(from: .float4, to: target)
    }

    static func floatingModuloTarget(
        at index: Int,
        in tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        guard tokens.indices.contains(index),
              tokens[index].text == "%",
              index >= 4,
              index + 2 < tokens.count,
              tokens[index - 2].text == "=",
              tokens[index - 3].kind == .identifier,
              tokens[index - 1].kind == .identifier,
              tokens[index + 2].text == ";",
              let target = SceneAuthoredShaderValueType(
                  authoredName: tokens[index - 4].text
              ), [.float, .int, .uint].contains(target),
              let left = declaredType(
                  of: tokens[index - 1].text,
                  before: index,
                  tokens: tokens,
                  unit: unit
              ), [.float, .int, .uint].contains(left),
              let right = scalarType(
                  at: index + 1,
                  before: index,
                  tokens: tokens,
                  unit: unit
              ), [.float, .int, .uint].contains(right),
              left == .float || right == .float else {
            return nil
        }
        return target
    }

    private static func scalarType(
        at index: Int,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        let token = tokens[index]
        if token.kind == .identifier {
            return declaredType(
                of: token.text,
                before: limit,
                tokens: tokens,
                unit: unit
            )
        }
        guard token.kind == .number else { return nil }
        return token.text.contains(".")
            || token.text.contains("e")
            || token.text.contains("E") ? .float : .int
    }

    private static func multiplicativeOperands(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        before limit: Int,
        allTokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> [Operand]? {
        var operands: [Operand] = []
        var index = expression.startIndex
        var expectsOperand = true
        while index < expression.endIndex {
            let token = expression[index]
            if token.kind == .number {
                guard expectsOperand else { return nil }
                operands.append(.init(range: index..<(index + 1), type: .float))
                expectsOperand = false
            } else if token.kind == .identifier {
                guard expectsOperand,
                      let declared = declaredType(
                          of: token.text,
                          before: limit,
                          tokens: allTokens,
                          unit: unit
                      ) else { return nil }
                var valueType = declared
                let start = index
                if index + 2 < expression.endIndex,
                   expression[index + 1].text == ".",
                   expression[index + 2].kind == .identifier {
                    guard let swizzled = swizzleType(expression[index + 2].text)
                    else { return nil }
                    valueType = swizzled
                    index += 2
                }
                guard valueType == .float || floatVectorWidth(valueType) != nil else {
                    return nil
                }
                operands.append(.init(range: start..<(index + 1), type: valueType))
                expectsOperand = false
            } else if ["+", "-"].contains(token.text), expectsOperand {
                // Unary signs preserve the following operand type.
            } else if ["*", "/"].contains(token.text), !expectsOperand {
                expectsOperand = true
            } else {
                return nil
            }
            index += 1
        }
        guard !expectsOperand, operands.contains(where: {
            floatVectorWidth($0.type) != nil
        }) else { return nil }
        return operands
    }

    private static func declaredType(
        of name: String,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        var types = Set(unit.declarations.compactMap { declaration in
            declaration.name == name
                ? SceneAuthoredShaderValueType(authoredName: declaration.typeName)
                : nil
        })
        if limit > 0 {
            for index in 0..<limit where index + 1 < tokens.count {
                guard tokens[index + 1].text == name,
                      let type = SceneAuthoredShaderValueType(
                          authoredName: tokens[index].text
                      ) else { continue }
                types.insert(type)
            }
        }
        guard types.count == 1 else { return nil }
        return types.first
    }

    private static func swizzleType(_ text: String) -> SceneAuthoredShaderValueType? {
        guard (1...4).contains(text.count),
              text.allSatisfy({ "xyzwrgba".contains($0) }) else { return nil }
        switch text.count {
        case 1: return .float
        case 2: return .float2
        case 3: return .float3
        case 4: return .float4
        default: return nil
        }
    }

    private static func narrowingSuffix(
        from source: SceneAuthoredShaderValueType,
        to target: SceneAuthoredShaderValueType
    ) -> String? {
        guard let sourceWidth = floatVectorWidth(source),
              let targetWidth = floatVectorWidth(target) else { return nil }
        return narrowingSuffix(from: sourceWidth, to: targetWidth)
    }

    private static func narrowingSuffix(from source: Int, to target: Int) -> String? {
        switch (source, target) {
        case (4, 3): "xyz"
        case (4, 2), (3, 2): "xy"
        default: nil
        }
    }

    private static func floatVectorWidth(_ type: SceneAuthoredShaderValueType) -> Int? {
        switch type {
        case .float2: 2
        case .float3: 3
        case .float4: 4
        default: nil
        }
    }

    private static func statementEnd(
        after index: Int,
        in tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        var depth = 0
        for cursor in (index + 1)..<tokens.count {
            if ["(", "["].contains(tokens[cursor].text) { depth += 1 }
            if [")", "]"].contains(tokens[cursor].text) { depth -= 1 }
            if depth == 0, tokens[cursor].text == ";" { return cursor }
            if depth < 0 || (depth == 0 && tokens[cursor].text == ",") { return nil }
        }
        return nil
    }

    static func matchingParenthesis(
        tokens: [SceneAuthoredShaderToken],
        opening: Int
    ) -> Int? {
        var depth = 0
        for index in opening..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func parameterTypes(
        for function: SceneAuthoredShaderSyntaxUnit.Function,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> [SceneAuthoredShaderValueType]? {
        let tokens = unit.tokens
        guard !function.parameterRange.isEmpty else { return [] }
        var result: [SceneAuthoredShaderValueType] = []
        var start = function.parameterRange.lowerBound
        var depth = 0
        for index in function.parameterRange.lowerBound...function.parameterRange.upperBound {
            let isEnd = index == function.parameterRange.upperBound
            if !isEnd {
                if ["(", "["].contains(tokens[index].text) { depth += 1 }
                if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            }
            guard isEnd || (depth == 0 && tokens[index].text == ",") else { continue }
            let types = Set(tokens[start..<index].compactMap {
                SceneAuthoredShaderValueType(authoredName: $0.text)
            })
            guard types.count == 1, let type = types.first else { return nil }
            result.append(type)
            start = index + 1
        }
        return result
    }

    private static func enclosingCallOpening(
        for index: Int,
        in tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        var depth = 0
        for cursor in stride(from: index - 1, through: 0, by: -1) {
            if tokens[cursor].text == ")" { depth += 1 }
            if tokens[cursor].text == "(" {
                if depth == 0 { return cursor }
                depth -= 1
            }
            if depth == 0, [";", "{", "}"].contains(tokens[cursor].text) {
                return nil
            }
        }
        return nil
    }

    private static func standaloneArgumentIndex(
        containing index: Int,
        opening: Int,
        closing: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        var ranges: [Range<Int>] = []
        var start = opening + 1
        var depth = 0
        for cursor in (opening + 1)...closing {
            let isEnd = cursor == closing
            if !isEnd {
                if ["(", "["].contains(tokens[cursor].text) { depth += 1 }
                if [")", "]"].contains(tokens[cursor].text) { depth -= 1 }
            }
            guard isEnd || (depth == 0 && tokens[cursor].text == ",") else { continue }
            ranges.append(start..<cursor)
            start = cursor + 1
        }
        return ranges.firstIndex(of: index..<(index + 1))
    }
}

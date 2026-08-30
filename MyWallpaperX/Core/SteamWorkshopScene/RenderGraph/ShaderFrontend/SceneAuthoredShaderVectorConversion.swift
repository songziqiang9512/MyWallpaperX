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
            guard ["=", "+=", "-=", "*=", "/="].contains(tokens[index].text),
                  index > 0,
                  tokens[index - 1].kind == .identifier,
                  let end = statementEnd(after: index, in: tokens),
                  let target = declaredType(
                      of: tokens[index - 1].text,
                      before: index,
                      tokens: tokens,
                      unit: unit
                  ),
                  let targetWidth = assignmentWidth(target) else {
                return []
            }
            if targetWidth > 1,
               let conversion = directConstructorConversion(
                expression: (index + 1)..<end,
                targetWidth: targetWidth,
                tokens: tokens
            ) {
                return [conversion]
            }
            if targetWidth > 1,
               let conversion = componentWiseBuiltInConversion(
                   expression: (index + 1)..<end,
                   targetWidth: targetWidth,
                   before: index,
                   tokens: tokens,
                   unit: unit
               ) {
                return [conversion]
            }
            if targetWidth == 1,
               let conversion = scalarComponentWiseExpressionConversion(
                   expression: (index + 1)..<end,
                   before: index,
                   tokens: tokens,
                   unit: unit
               ) {
                return [conversion]
            }
            guard let operands = multiplicativeOperands(
                tokens[(index + 1)..<end],
                before: index,
                allTokens: tokens,
                unit: unit
            ) else {
                return targetWidth > 1
                    ? contextualComponentConversions(
                        expression: (index + 1)..<end,
                        targetWidth: targetWidth,
                        before: index,
                        tokens: tokens,
                        unit: unit
                    ) ?? []
                    : []
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

    private static func directConstructorConversion(
        expression: Range<Int>,
        targetWidth: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Conversion? {
        guard expression.count >= 3,
              tokens[expression.lowerBound].kind == .identifier,
              let source = SceneAuthoredShaderValueType(
                authoredName: tokens[expression.lowerBound].text
              ), let sourceWidth = floatVectorWidth(source),
              sourceWidth > targetWidth,
              tokens[expression.lowerBound + 1].text == "(",
              matchingParenthesis(
                tokens: tokens,
                opening: expression.lowerBound + 1
              ) == expression.upperBound - 1,
              let suffix = narrowingSuffix(
                from: sourceWidth,
                to: targetWidth
              ) else { return nil }
        return .init(range: expression, suffix: suffix)
    }

    /// Wallpaper Engine's HLSL-facing authored dialect permits a float local
    /// to take the first lane of one component-wise vector expression. Keep
    /// that conversion explicit for Metal/GLSL only when every vector operand
    /// has the same statically known width and every call is a component-wise
    /// built-in or a matching vector constructor. Unknown/user functions,
    /// mixed widths, indexing and control expressions remain unchanged so the
    /// downstream compiler can reject them.
    private static func scalarComponentWiseExpressionConversion(
        expression: Range<Int>,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Conversion? {
        let builtIns: Set<String> = [
            "abs", "clamp", "max", "min", "pow", "saturate",
            "smoothstep", "step",
        ]
        let punctuation: Set<String> = [
            "+", "-", "*", "/", "(", ")", ",",
        ]
        var vectorWidths = Set<Int>()
        var index = expression.lowerBound
        while index < expression.upperBound {
            let token = tokens[index]
            if token.kind == .number || punctuation.contains(token.text) {
                index += 1
                continue
            }
            guard token.kind == .identifier else { return nil }
            if index > expression.lowerBound, tokens[index - 1].text == "." {
                return nil
            }
            if index + 1 < expression.upperBound,
               tokens[index + 1].text == "(" {
                if let constructor = SceneAuthoredShaderValueType(
                    authoredName: token.text
                ) {
                    guard let width = floatVectorWidth(constructor), width > 1
                    else { return nil }
                    vectorWidths.insert(width)
                } else {
                    guard builtIns.contains(token.text),
                          !unit.functions.contains(where: {
                              $0.name == token.text
                          }) else { return nil }
                }
                index += 1
                continue
            }
            guard let source = declaredType(
                of: token.text,
                before: limit,
                tokens: tokens,
                unit: unit
            ) else { return nil }
            if index + 2 < expression.upperBound,
               tokens[index + 1].text == ".",
               tokens[index + 2].kind == .identifier {
                guard let swizzled = swizzleType(tokens[index + 2].text)
                else { return nil }
                if let width = floatVectorWidth(swizzled) {
                    vectorWidths.insert(width)
                } else if swizzled != .float {
                    return nil
                }
                index += 3
                continue
            }
            if let width = floatVectorWidth(source) {
                vectorWidths.insert(width)
            } else if ![.float, .int, .uint].contains(source) {
                return nil
            }
            index += 1
        }
        guard vectorWidths.count == 1,
              let width = vectorWidths.first,
              let suffix = narrowingSuffix(from: width, to: 1) else {
            return nil
        }
        return .init(range: expression, suffix: suffix)
    }

    /// Component-wise GLSL built-ins preserve the single active vector width
    /// when every other argument is scalar. If that proven result is assigned
    /// to a narrower vector, apply the same explicit shrink used elsewhere.
    /// User-defined overloads, mixed vector widths, swizzles wider than the
    /// target, and compound expressions remain closed.
    private static func componentWiseBuiltInConversion(
        expression: Range<Int>,
        targetWidth: Int,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Conversion? {
        guard expression.count >= 3,
              tokens[expression.lowerBound].kind == .identifier,
              tokens[expression.lowerBound + 1].text == "(",
              matchingParenthesis(
                  tokens: tokens,
                  opening: expression.lowerBound + 1
              ) == expression.upperBound - 1 else { return nil }
        let function = tokens[expression.lowerBound].text
        let builtIns = Set([
            "abs", "clamp", "max", "min", "pow", "saturate",
            "smoothstep", "step",
        ])
        guard builtIns.contains(function),
              !unit.functions.contains(where: { $0.name == function }) else { return nil }
        var widths = Set<Int>()
        var index = expression.lowerBound + 2
        while index < expression.upperBound - 1 {
            let token = tokens[index]
            guard token.kind == .identifier else {
                index += 1
                continue
            }
            if index + 1 < expression.upperBound,
               tokens[index + 1].text == "(" {
                guard builtIns.contains(token.text)
                        || SceneAuthoredShaderValueType(authoredName: token.text) != nil
                else { return nil }
                index += 1
                continue
            }
            if index > expression.lowerBound,
               tokens[index - 1].text == "." {
                index += 1
                continue
            }
            guard let source = declaredType(
                of: token.text,
                before: limit,
                tokens: tokens,
                unit: unit
            ) else { return nil }
            var width = floatVectorWidth(source)
            if index + 2 < expression.upperBound,
               tokens[index + 1].text == ".",
               tokens[index + 2].kind == .identifier {
                guard let swizzle = swizzleType(tokens[index + 2].text) else {
                    return nil
                }
                width = floatVectorWidth(swizzle)
                index += 2
            }
            if let width { widths.insert(width) }
            else if ![.float, .int, .uint].contains(source) { return nil }
            index += 1
        }
        guard widths.count == 1, let sourceWidth = widths.first,
              sourceWidth > targetWidth,
              let suffix = narrowingSuffix(from: sourceWidth, to: targetWidth)
        else { return nil }
        return .init(range: expression, suffix: suffix)
    }

    static func assignmentBoundaries(
        in tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> (starts: [Int: Int], ends: [Int: [String]]) {
        let values = conversions(in: tokens, unit: unit)
        var starts = Dictionary(grouping: values, by: { $0.range.lowerBound })
            .mapValues(\.count)
        var ends = Dictionary(grouping: values, by: { $0.range.upperBound })
            .mapValues { $0.sorted { $0.range.count < $1.range.count }.map(\.suffix) }
        SceneAuthoredShaderBuiltInVectorConversion.addCompoundMixBoundaries(
            starts: &starts, ends: &ends, tokens: tokens, unit: unit
        )
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
        if target == .float { return "x" }
        return narrowingSuffix(from: .float4, to: target)
    }

    static func suffixForTextureCoordinate(
        tokens: [SceneAuthoredShaderToken],
        range: Range<Int>,
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> String? {
        guard range.count == 1,
              tokens[range.lowerBound].kind == .identifier,
              let source = declaredType(
                  of: tokens[range.lowerBound].text,
                  before: range.lowerBound,
                  tokens: tokens,
                  unit: unit
              ) else { return nil }
        return narrowingSuffix(from: source, to: .float2)
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

    private static func contextualComponentConversions(
        expression: Range<Int>,
        targetWidth: Int,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> [Conversion]? {
        var result: [Conversion] = []
        var depth = 0
        var index = expression.lowerBound
        while index < expression.upperBound {
            let token = tokens[index]
            if token.kind == .number {
                index += 1
                continue
            }
            if ["+", "-", "*", "/"].contains(token.text) {
                index += 1
                continue
            }
            if token.text == "(" {
                depth += 1
                index += 1
                continue
            }
            if token.text == ")" {
                depth -= 1
                guard depth >= 0 else { return nil }
                index += 1
                continue
            }
            if token.text == "," {
                guard depth > 0 else { return nil }
                index += 1
                continue
            }
            guard token.kind == .identifier else { return nil }
            if index > expression.lowerBound, tokens[index - 1].text == "." {
                index += 1
                continue
            }
            if index + 1 < expression.upperBound, tokens[index + 1].text == "(" {
                guard let constructor = SceneAuthoredShaderValueType(
                          authoredName: token.text
                      ), constructor == .float
                        || floatVectorWidth(constructor).map({ $0 <= targetWidth }) == true
                else { return nil }
                index += 1
                continue
            }
            guard let source = declaredType(
                of: token.text,
                before: limit,
                tokens: tokens,
                unit: unit
            ) else { return nil }
            if index + 2 < expression.upperBound,
               tokens[index + 1].text == ".",
               tokens[index + 2].kind == .identifier {
                guard let explicit = swizzleType(tokens[index + 2].text),
                      explicit == .float
                        || floatVectorWidth(explicit).map({ $0 <= targetWidth }) == true
                else { return nil }
                index += 3
                continue
            }
            if [.float, .int, .uint].contains(source) {
                index += 1
                continue
            }
            guard let sourceWidth = floatVectorWidth(source) else { return nil }
            if sourceWidth > targetWidth {
                guard let suffix = narrowingSuffix(from: sourceWidth, to: targetWidth)
                else { return nil }
                result.append(.init(range: index..<(index + 1), suffix: suffix))
            }
            index += 1
        }
        guard depth == 0, !result.isEmpty else { return nil }
        return result
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
        case (2, 1), (3, 1), (4, 1): "x"
        case (4, 3): "xyz"
        case (4, 2), (3, 2): "xy"
        default: nil
        }
    }

    private static func assignmentWidth(_ type: SceneAuthoredShaderValueType) -> Int? {
        type == .float ? 1 : floatVectorWidth(type)
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

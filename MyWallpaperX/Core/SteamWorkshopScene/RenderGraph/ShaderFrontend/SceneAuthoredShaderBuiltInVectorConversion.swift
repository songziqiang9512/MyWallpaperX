nonisolated enum SceneAuthoredShaderBuiltInVectorConversion {
    private struct Conversion: Hashable {
        let range: Range<Int>
        let suffix: String
    }

    private struct Expression {
        let range: Range<Int>
        let type: SceneAuthoredShaderValueType
        let conversions: [Conversion]
        let compound: Bool
        let directlyNarrowable: Bool
    }

    static func suffix(
        forIdentifierAt index: Int,
        in tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> String? {
        guard tokens.indices.contains(index),
              tokens[index].kind == .identifier,
              let opening = enclosingCallOpening(for: index, in: tokens),
              opening > 0,
              ["mix", "lerp"].contains(tokens[opening - 1].text),
              !unit.functions.contains(where: { $0.name == tokens[opening - 1].text }),
              let closing = matchingParenthesis(tokens: tokens, opening: opening),
              let ranges = argumentRanges(opening: opening, closing: closing, tokens: tokens),
              ranges.count == 3,
              let argumentIndex = ranges.prefix(2).firstIndex(of: index..<(index + 1)),
              let first = standaloneType(
                  ranges[0], before: index, tokens: tokens, unit: unit
              ),
              let second = standaloneType(
                  ranges[1], before: index, tokens: tokens, unit: unit
              ),
              let firstWidth = floatVectorWidth(first),
              let secondWidth = floatVectorWidth(second),
              validWeight(
                  ranges[2], width: min(firstWidth, secondWidth),
                  before: index, tokens: tokens, unit: unit
              ) else { return nil }
        let sourceWidth = argumentIndex == 0 ? firstWidth : secondWidth
        return narrowingSuffix(from: sourceWidth, to: min(firstWidth, secondWidth))
    }

    static func addCompoundMixBoundaries(
        starts: inout [Int: Int],
        ends: inout [Int: [String]],
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) {
        let conversions = Set(tokens.indices.flatMap { index -> [Conversion] in
            guard tokens[index].text == "(", index > 0,
                  ["mix", "lerp"].contains(tokens[index - 1].text),
                  !unit.functions.contains(where: { $0.name == tokens[index - 1].text }),
                  let closing = matchingParenthesis(tokens: tokens, opening: index),
                  let ranges = argumentRanges(opening: index, closing: closing, tokens: tokens),
                  ranges.count == 3,
                  let first = componentExpression(ranges[0], tokens: tokens, unit: unit),
                  let second = componentExpression(ranges[1], tokens: tokens, unit: unit),
                  first.compound || second.compound,
                  let firstWidth = floatVectorWidth(first.type),
                  firstWidth == floatVectorWidth(second.type),
                  validWeight(
                      ranges[2], width: firstWidth, before: index,
                      tokens: tokens, unit: unit
                  ) else { return [] }
            return first.conversions + second.conversions
        })
        for conversion in conversions {
            starts[conversion.range.lowerBound, default: 0] += 1
            ends[conversion.range.upperBound, default: []].append(conversion.suffix)
        }
    }

    private static func componentExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        guard !range.isEmpty else { return nil }
        return additiveExpression(range, tokens: tokens, unit: unit)
    }

    private static func additiveExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        guard let ranges = split(range, operators: ["+", "-"], tokens: tokens),
              let first = ranges.first,
              let firstExpression = multiplicativeExpression(first, tokens: tokens, unit: unit)
        else { return nil }
        let expressions = [firstExpression] + ranges.dropFirst().compactMap {
            multiplicativeExpression($0, tokens: tokens, unit: unit)
        }
        guard expressions.count == ranges.count else { return nil }
        if expressions.count == 1 { return firstExpression }
        let types = Set(expressions.map(\.type))
        guard types.count == 1, let type = types.first,
              type == .float || floatVectorWidth(type) != nil else { return nil }
        return .init(
            range: range,
            type: type,
            conversions: expressions.flatMap(\.conversions),
            compound: true,
            directlyNarrowable: false
        )
    }

    private static func multiplicativeExpression(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        guard let ranges = split(range, operators: ["*", "/"], tokens: tokens),
              let first = ranges.first,
              let firstExpression = primaryExpression(first, tokens: tokens, unit: unit)
        else { return nil }
        let expressions = [firstExpression] + ranges.dropFirst().compactMap {
            primaryExpression($0, tokens: tokens, unit: unit)
        }
        guard expressions.count == ranges.count else { return nil }
        if expressions.count == 1 { return firstExpression }
        let widths = expressions.compactMap { floatVectorWidth($0.type) }
        guard expressions.allSatisfy({ $0.type == .float || floatVectorWidth($0.type) != nil }),
              let width = widths.min(),
              expressions.allSatisfy({ expression in
                  guard let sourceWidth = floatVectorWidth(expression.type) else { return true }
                  return sourceWidth <= width || expression.directlyNarrowable
              }) else { return nil }
        let type = vectorType(width: width)
        let conversions = expressions.flatMap(\.conversions) + expressions.compactMap {
            guard let sourceWidth = floatVectorWidth($0.type), sourceWidth > width,
                  let suffix = narrowingSuffix(from: sourceWidth, to: width)
            else { return nil }
            return Conversion(range: $0.range, suffix: suffix)
        }
        return .init(
            range: range,
            type: type,
            conversions: conversions,
            compound: true,
            directlyNarrowable: false
        )
    }

    private static func primaryExpression(
        _ sourceRange: Range<Int>,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Expression? {
        var range = sourceRange
        while range.count > 1, ["+", "-"].contains(tokens[range.lowerBound].text) {
            range = (range.lowerBound + 1)..<range.upperBound
        }
        if range.count >= 2, tokens[range.lowerBound].text == "(",
           tokens[range.upperBound - 1].text == ")",
           matchingParenthesis(tokens: tokens, opening: range.lowerBound) == range.upperBound - 1,
           let nested = additiveExpression(
               (range.lowerBound + 1)..<(range.upperBound - 1),
               tokens: tokens,
               unit: unit
           ) {
            return .init(
                range: sourceRange,
                type: nested.type,
                conversions: nested.conversions,
                compound: true,
                directlyNarrowable: false
            )
        }
        if range.count == 1, tokens[range.lowerBound].kind == .number {
            return .init(
                range: sourceRange,
                type: .float,
                conversions: [],
                compound: false,
                directlyNarrowable: false
            )
        }
        guard tokens[range.lowerBound].kind == .identifier,
              let declared = declaredType(
                  tokens[range.lowerBound].text,
                  before: range.lowerBound,
                  tokens: tokens,
                  unit: unit
              ) else { return nil }
        if range.count == 1 {
            return .init(
                range: sourceRange,
                type: declared,
                conversions: [],
                compound: false,
                directlyNarrowable: true
            )
        }
        guard range.count == 3, tokens[range.lowerBound + 1].text == ".",
              tokens[range.lowerBound + 2].kind == .identifier,
              let type = swizzleType(tokens[range.lowerBound + 2].text) else { return nil }
        return .init(
            range: sourceRange,
            type: type,
            conversions: [],
            compound: false,
            directlyNarrowable: true
        )
    }

    private static func split(
        _ range: Range<Int>,
        operators: Set<String>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            guard depth == 0, operators.contains(tokens[index].text), index > start else { continue }
            result.append(start..<index)
            start = (index + 1)
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    private static func vectorType(width: Int) -> SceneAuthoredShaderValueType {
        [.float2, .float3, .float4][width - 2]
    }

    private static func validWeight(
        _ range: Range<Int>,
        width: Int,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        guard let type = standaloneType(
            range, before: limit, tokens: tokens, unit: unit
        ) else { return false }
        return type == .float || floatVectorWidth(type) == width
    }

    private static func standaloneType(
        _ range: Range<Int>,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        if range.count == 1, tokens[range.lowerBound].kind == .number {
            return .float
        }
        guard tokens[range.lowerBound].kind == .identifier,
              let declared = declaredType(
                  tokens[range.lowerBound].text,
                  before: limit,
                  tokens: tokens,
                  unit: unit
              ) else { return nil }
        if range.count == 1 { return declared }
        guard range.count == 3,
              tokens[range.lowerBound + 1].text == ".",
              tokens[range.lowerBound + 2].kind == .identifier else { return nil }
        return swizzleType(tokens[range.lowerBound + 2].text)
    }

    private static func declaredType(
        _ name: String,
        before limit: Int,
        tokens: [SceneAuthoredShaderToken],
        unit: SceneAuthoredShaderSyntaxUnit
    ) -> SceneAuthoredShaderValueType? {
        var types = Set(unit.declarations.compactMap {
            $0.name == name
                ? SceneAuthoredShaderValueType(authoredName: $0.typeName) : nil
        })
        for index in 0..<limit where index + 1 < tokens.count {
            guard tokens[index + 1].text == name,
                  let type = SceneAuthoredShaderValueType(
                      authoredName: tokens[index].text
                  ) else { continue }
            types.insert(type)
        }
        return types.count == 1 ? types.first : nil
    }

    private static func argumentRanges(
        opening: Int,
        closing: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        var ranges: [Range<Int>] = []
        var start = opening + 1
        var depth = 0
        for index in (opening + 1)...closing {
            let isEnd = index == closing
            if !isEnd, ["(", "["].contains(tokens[index].text) { depth += 1 }
            if !isEnd, [")", "]"].contains(tokens[index].text) { depth -= 1 }
            guard depth >= 0 else { return nil }
            guard isEnd || (depth == 0 && tokens[index].text == ",") else { continue }
            ranges.append(start..<index)
            start = index + 1
        }
        return ranges
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
            if depth == 0, [";", "{", "}"].contains(tokens[cursor].text) { return nil }
        }
        return nil
    }

    private static func matchingParenthesis(
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

    private static func swizzleType(_ value: String) -> SceneAuthoredShaderValueType? {
        guard (1...4).contains(value.count),
              value.allSatisfy({ "xyzwrgba".contains($0) }) else { return nil }
        return [.float, .float2, .float3, .float4][value.count - 1]
    }

    private static func floatVectorWidth(_ type: SceneAuthoredShaderValueType) -> Int? {
        switch type {
        case .float2: 2
        case .float3: 3
        case .float4: 4
        default: nil
        }
    }

    private static func narrowingSuffix(from source: Int, to target: Int) -> String? {
        switch (source, target) {
        case (4, 3): "xyz"
        case (4, 2), (3, 2): "xy"
        default: nil
        }
    }
}

nonisolated enum SceneAuthoredShaderBuiltInVectorConversion {
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

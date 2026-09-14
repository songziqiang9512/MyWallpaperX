import Foundation

nonisolated extension SceneAuthoredShaderStraightWholeColorFilterAnalyzer {
    static func functionCall(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> (name: String, arguments: [ArraySlice<SceneAuthoredShaderToken>])? {
        guard expression.count >= 4,
              expression.first?.kind == .identifier,
              let name = expression.first?.text,
              expression[expression.startIndex + 1].text == "(",
              expression.last?.text == ")" else { return nil }
        let values = Array(expression)
        let range = 2..<(values.count - 1)
        guard let indices = commaSeparated(range, tokens: values) else {
            return nil
        }
        return (name, indices.map {
            expression[(expression.startIndex + $0.lowerBound)..<(
                expression.startIndex + $0.upperBound
            )]
        })
    }

    static func isCoordinate(
        _ expression: ArraySlice<SceneAuthoredShaderToken>,
        fragment: SceneAuthoredShaderSyntaxUnit
    ) -> Bool {
        let values = Array(expression)
        if values.count == 1, values[0].kind == .identifier {
            return fragment.declarations.contains {
                $0.name == values[0].text
                    && ["vec2", "float2"].contains($0.typeName)
                    && $0.arraySize == nil
            }
        }
        guard values.count == 3,
              values[0].kind == .identifier,
              values[1].text == "." else { return false }
        return ["xy", "zw"].contains(values[2].text)
    }

    static func textureSampleSlots(
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Int]? {
        var result: [Int] = []
        for index in range
        where ["texSample2D", "texture2D"].contains(tokens[index].text) {
            guard index + 2 < range.upperBound,
                  tokens[index + 1].text == "(",
                  let slot = textureSlot(tokens[index + 2].text) else {
                return nil
            }
            result.append(slot)
        }
        return result
    }

    static func matchingDelimiter(
        at open: Int,
        tokens: [SceneAuthoredShaderToken]
    ) -> Int? {
        guard open < tokens.count else { return nil }
        let pair = tokens[open].text == "(" ? ")" : "]"
        var depth = 0
        for index in open..<tokens.count {
            if tokens[index].text == tokens[open].text { depth += 1 }
            if tokens[index].text == pair {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    static func commaSeparated(
        _ range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>]? {
        guard !range.isEmpty else { return [] }
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            switch tokens[index].text {
            case "(", "[": depth += 1
            case ")", "]": depth -= 1
            case "," where depth == 0:
                guard start < index else { return nil }
                result.append(start..<index)
                start = index + 1
            default: break
            }
            guard depth >= 0 else { return nil }
        }
        guard depth == 0, start < range.upperBound else { return nil }
        result.append(start..<range.upperBound)
        return result
    }

    private static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture"),
              let slot = Int(name.dropFirst("g_Texture".count)),
              (0 ..< 8).contains(slot) else { return nil }
        return slot
    }
}

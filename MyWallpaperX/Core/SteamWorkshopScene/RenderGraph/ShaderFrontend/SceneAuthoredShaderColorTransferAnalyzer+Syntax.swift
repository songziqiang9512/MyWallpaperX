import Foundation

nonisolated extension SceneAuthoredShaderColorTransferAnalyzer {
    static func isOpaqueVectorConstruction(
        _ expression: ArraySlice<SceneAuthoredShaderToken>
    ) -> Bool {
        let tokens = Array(expression)
        guard tokens.count >= 6,
              ["vec4", "float4"].contains(tokens[0].text),
              tokens[1].text == "(",
              tokens.last?.text == ")",
              outerCallClosesAtEnd(tokens),
              let comma = topLevelCommas(tokens).last,
              comma + 2 == tokens.count - 1,
              tokens[comma + 1].kind == .number,
              Double(tokens[comma + 1].text) == 1 else {
            return false
        }
        return true
    }

    static func outerCallClosesAtEnd(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        var depth = 0
        for index in 1..<tokens.count {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" {
                depth -= 1
                if depth == 0 { return index == tokens.count - 1 }
                if depth < 0 { return false }
            }
        }
        return false
    }

    static func topLevelCommas(
        _ tokens: [SceneAuthoredShaderToken]
    ) -> [Int] {
        var depth = 0
        var result: [Int] = []
        for index in tokens.indices {
            if tokens[index].text == "(" { depth += 1 }
            if tokens[index].text == ")" { depth -= 1 }
            if tokens[index].text == ",", depth == 1 { result.append(index) }
        }
        return result
    }
}

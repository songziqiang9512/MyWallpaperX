import Foundation

nonisolated enum SceneAuthoredShaderStaticLoopAdmission {
    static func iterations(
        header: Range<Int>,
        functionBody: Range<Int>,
        loopIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String]
    ) -> Int? {
        let parts = split(range: header, separator: ";", tokens: tokens)
        guard parts.count == 3 else { return nil }

        var initialization = Array(tokens[parts[0]].map(\.text))
        if initialization.first == "int" { initialization.removeFirst() }
        guard initialization.count == 3,
              initialization[1] == "=",
              let start = integer(initialization[2], defines: defines) else {
            return nil
        }
        let variable = initialization[0]
        let condition = Array(tokens[parts[1]].map(\.text))
        guard condition.count == 3,
              condition[0] == variable,
              ["<", "<="].contains(condition[1]),
              let end = bound(
                  condition[2],
                  functionBody: functionBody,
                  before: loopIndex,
                  tokens: tokens,
                  defines: defines
              ) else {
            return nil
        }
        guard let step = incrementStep(
            Array(tokens[parts[2]].map(\.text)),
            variable: variable,
            defines: defines
        ) else {
            return nil
        }
        let distance = end - start + (condition[1] == "<=" ? 1 : 0)
        return distance <= 0 ? 0 : (distance + step - 1) / step
    }

    private static func bound(
        _ token: String,
        functionBody: Range<Int>,
        before loopIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String]
    ) -> Int? {
        if let value = integer(token, defines: defines) { return value }
        return rootConstant(
            named: token,
            functionBody: functionBody,
            before: loopIndex,
            tokens: tokens,
            defines: defines
        )
    }

    private static func rootConstant(
        named name: String,
        functionBody: Range<Int>,
        before loopIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String]
    ) -> Int? {
        var braceDepth = 0
        var declarations: [(start: Int, end: Int, value: Int)] = []
        var cursor = functionBody.lowerBound
        while cursor < functionBody.upperBound {
            let text = tokens[cursor].text
            if text == "{" {
                braceDepth += 1
                cursor += 1
                continue
            }
            if text == "}" {
                braceDepth -= 1
                cursor += 1
                continue
            }
            if text == "int",
               cursor + 1 < functionBody.upperBound,
               tokens[cursor + 1].text == name {
                return nil
            }
            if text == "const",
               cursor + 4 < functionBody.upperBound,
               tokens[cursor + 1].text == "int",
               tokens[cursor + 2].text == name {
                guard braceDepth == 1,
                      tokens[cursor + 3].text == "=",
                      let semicolon = tokens[(cursor + 4)..<functionBody.upperBound]
                        .firstIndex(where: { $0.text == ";" }),
                      semicolon == cursor + 5,
                      let value = integer(tokens[cursor + 4].text, defines: defines) else {
                    return nil
                }
                declarations.append((cursor, semicolon + 1, value))
                cursor = semicolon + 1
                continue
            }
            cursor += 1
        }
        guard declarations.count == 1,
              let declaration = declarations.first,
              declaration.start < loopIndex,
              !isWritten(
                  name,
                  in: declaration.end..<functionBody.upperBound,
                  tokens: tokens
              ) else {
            return nil
        }
        return declaration.value
    }

    private static func isWritten(
        _ name: String,
        in range: Range<Int>,
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        let assignments: Set<String> = ["=", "+=", "-=", "*=", "/=", "%="]
        for index in range where tokens[index].text == name {
            if index + 1 < range.upperBound,
               assignments.contains(tokens[index + 1].text) {
                return true
            }
            if index + 1 < range.upperBound,
               ["++", "--"].contains(tokens[index + 1].text) {
                return true
            }
            if index > range.lowerBound,
               ["++", "--"].contains(tokens[index - 1].text) {
                return true
            }
        }
        return false
    }

    private static func incrementStep(
        _ increment: [String],
        variable: String,
        defines: [String: String]
    ) -> Int? {
        if increment == [variable, "++"] || increment == ["++", variable] {
            return 1
        }
        guard increment.count == 3,
              increment[0] == variable,
              increment[1] == "+=",
              let value = integer(increment[2], defines: defines),
              value > 0 else {
            return nil
        }
        return value
    }

    private static func integer(_ token: String, defines: [String: String]) -> Int? {
        Int(defines[token] ?? token)
    }

    private static func split(
        range: Range<Int>,
        separator: String,
        tokens: [SceneAuthoredShaderToken]
    ) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var depth = 0
        for index in range {
            if ["(", "["].contains(tokens[index].text) { depth += 1 }
            if [")", "]"].contains(tokens[index].text) { depth -= 1 }
            if depth == 0, tokens[index].text == separator {
                result.append(start..<index)
                start = index + 1
            }
        }
        result.append(start..<range.upperBound)
        return result
    }
}

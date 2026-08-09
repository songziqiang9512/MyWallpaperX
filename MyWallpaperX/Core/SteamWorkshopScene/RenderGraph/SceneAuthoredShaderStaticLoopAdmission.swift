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
        guard (3 ... 4).contains(initialization.count),
              initialization[1] == "=",
              let start = SceneAuthoredShaderLoopIntegerLiteral.value(
                  Array(initialization.dropFirst(2)), defines: defines
              ) else {
            return nil
        }
        let variable = initialization[0]
        let condition = Array(tokens[parts[1]].map(\.text))
        guard condition.count == 3,
              condition[0] == variable,
              ["<", "<="].contains(condition[1]),
              let end = bound(
                  [condition[2]],
                  functionBody: functionBody,
                  before: loopIndex,
                  tokens: tokens,
                  defines: defines
              ) else {
            return nil
        }
        guard let step = incrementStep(
            Array(tokens[parts[2]].map(\.text)),
            variable: variable, defines: defines
        ) else { return nil }
        return SceneAuthoredShaderLoopIterationCount.value(
            start: start, end: end, inclusive: condition[1] == "<=", step: step
        )
    }

    static func earlyExitIterations(
        header: Range<Int>,
        functionBody: Range<Int>,
        loopIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String]
    ) -> Int? {
        let parts = split(range: header, separator: ";", tokens: tokens)
        guard parts.count == 3 else { return nil }
        var initialization = Array(tokens[parts[0]].map(\.text))
        guard initialization.first == "float" else { return nil }
        initialization.removeFirst()
        guard initialization.count == 3,
              initialization[1] == "=",
              let start = integerValue(initialization[2], defines: defines) else {
            return nil
        }
        let variable = initialization[0]
        guard let condition = boundedEarlyExitCondition(
            parts[1],
            variable: variable,
            functionBody: functionBody,
            before: loopIndex,
            tokens: tokens,
            defines: defines
        ), !isWritten(
            variable,
            in: functionBody,
            excluding: [parts[0], parts[2]],
            tokens: tokens
        ), let step = incrementStep(
            Array(tokens[parts[2]].map(\.text)),
            variable: variable, defines: defines
        ) else { return nil }
        return SceneAuthoredShaderLoopIterationCount.value(
            start: start, end: condition.end, inclusive: condition.inclusive, step: step
        )
    }

    private struct BoundedCondition {
        let end: Int
        let inclusive: Bool
    }

    /// A conjunction may stop a counted loop early, but it cannot make the
    /// loop exceed the proven induction-variable bound. Keep this admission
    /// deliberately narrow: exactly one conjunct owns the bound and every
    /// other conjunct must be independent of the induction variable.
    private static func boundedEarlyExitCondition(
        _ range: Range<Int>,
        variable: String,
        functionBody: Range<Int>,
        before loopIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String]
    ) -> BoundedCondition? {
        let conjuncts = split(range: range, separator: "&&", tokens: tokens)
        guard conjuncts.count >= 2 else { return nil }
        var result: BoundedCondition?
        for conjunct in conjuncts {
            let condition = Array(tokens[conjunct].map(\.text))
            if condition.count == 3,
               condition[0] == variable,
               ["<", "<="].contains(condition[1]),
               let end = earlyExitBound(
                   condition[2],
                   functionBody: functionBody,
                   before: loopIndex,
                   tokens: tokens,
                   defines: defines
               ) {
                guard result == nil else { return nil }
                result = .init(end: end, inclusive: condition[1] == "<=")
            } else if conjunct.contains(where: { tokens[$0].text == variable }) {
                return nil
            }
        }
        return result
    }

    private static func earlyExitBound(
        _ token: String,
        functionBody: Range<Int>,
        before loopIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String]
    ) -> Int? {
        if let value = integerValue(token, defines: defines) { return value }
        return rootInvariantFloat(
            named: token,
            functionBody: functionBody,
            before: loopIndex,
            tokens: tokens,
            defines: defines
        )
    }

    private static func bound(
        _ expression: [String],
        functionBody: Range<Int>,
        before loopIndex: Int,
        tokens: [SceneAuthoredShaderToken],
        defines: [String: String]
    ) -> Int? {
        if let value = SceneAuthoredShaderLoopIntegerLiteral.value(
            expression, defines: defines
        ) { return value }
        guard expression.count == 1 else { return nil }
        return rootConstant(
            named: expression[0],
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

    private static func rootInvariantFloat(
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
            let typeIndex: Int
            let nameIndex: Int
            let equalsIndex: Int
            let valueIndex: Int
            if text == "float" {
                typeIndex = cursor
                nameIndex = cursor + 1
                equalsIndex = cursor + 2
                valueIndex = cursor + 3
            } else if text == "const",
                      cursor + 1 < functionBody.upperBound,
                      tokens[cursor + 1].text == "float" {
                typeIndex = cursor + 1
                nameIndex = cursor + 2
                equalsIndex = cursor + 3
                valueIndex = cursor + 4
            } else {
                cursor += 1
                continue
            }
            guard typeIndex < functionBody.upperBound,
                  nameIndex < functionBody.upperBound else { return nil }
            guard tokens[nameIndex].text == name else {
                cursor += 1
                continue
            }
            guard braceDepth == 1,
                  valueIndex < functionBody.upperBound,
                  tokens[equalsIndex].text == "=",
                  let semicolon = tokens[valueIndex..<functionBody.upperBound]
                    .firstIndex(where: { $0.text == ";" }),
                  semicolon == valueIndex + 1,
                  let value = integerValue(tokens[valueIndex].text, defines: defines) else {
                return nil
            }
            declarations.append((cursor, semicolon + 1, value))
            cursor = semicolon + 1
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

    private static func isWritten(
        _ name: String,
        in range: Range<Int>,
        excluding allowedWrites: [Range<Int>],
        tokens: [SceneAuthoredShaderToken]
    ) -> Bool {
        let assignments: Set<String> = ["=", "+=", "-=", "*=", "/=", "%="]
        for index in range where tokens[index].text == name {
            if allowedWrites.contains(where: { $0.contains(index) }) { continue }
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
              let value = integerValue(increment[2], defines: defines),
              Int32(exactly: value) != nil,
              value > 0 else {
            return nil
        }
        return value
    }

    private static func integerValue(_ token: String, defines: [String: String]) -> Int? {
        let value = defines[token] ?? token
        if let integer = Int(value) { return integer }
        guard let floating = Double(value),
              floating.isFinite,
              floating.rounded(.towardZero) == floating else {
            return nil
        }
        return Int(exactly: floating)
    }

    private static func integer(_ token: String, defines: [String: String]) -> Int? {
        SceneAuthoredShaderLoopIntegerLiteral.value([token], defines: defines)
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

import Foundation

nonisolated extension SceneLaunchOriginTransitionSyntax {
    struct UpdatePlan {
        enum Condition: Equatable {
            case localHover
            case shared(String, Bool)
        }

        let condition: Condition
        let baseOffset: SIMD3<Double>
    }

    struct ApplyPlan {
        let speedDivisor: Double
        let triggerPropertyKey: String
        let usesPreviousValue: Bool
    }

    struct BodyParser {
        let tokens: [SceneLaunchOriginTransitionToken]

        func update(value: String, math: String) -> UpdatePlan? {
            var parser = Cursor(tokens: tokens)
            guard let branches = parseIfElse(&parser),
                  parser.identifier("return"), !parser.nextHasLineBreak,
                  parser.identifier(value), parser.statementTerminator() else { return nil }
            guard parser.isAtEnd,
                  let branch = parseBranch(branches, value: value, math: math) else { return nil }
            return branch
        }

        func cursor() -> String? {
            var parser = Cursor(tokens: tokens)
            guard let branch = parseIfElse(&parser), parser.isAtEnd,
                  branch.condition == [.identifier("hover")],
                  branch.secondCondition == nil,
                  hoverAssignment(branch.first, hover: false, flagValue: false),
                  hoverAssignment(branch.second, hover: true, flagValue: true),
                  let flag = assignedSharedFlag(branch.first) else { return nil }
            return assignedSharedFlag(branch.second) == flag ? flag : nil
        }

        func apply(changed: String) -> ApplyPlan? {
            var outer = Cursor(tokens: tokens)
            guard outer.identifier("if"), let condition = outer.parenthesized(),
                  let body = outer.braced(), outer.isAtEnd,
                  condition == [
                    .identifier(changed), .symbol("."), .identifier("hasOwnProperty"),
                    .symbol("("), .string("xian"), .symbol(")")
                  ] else { return nil }
            var parser = Cursor(tokens: body)
            guard let x = endpointAssignment(&parser, variable: "newScaleX", axis: "x"),
                  let y = endpointAssignment(&parser, variable: "newScaleY", axis: "y"),
                  let z = endpointAssignment(&parser, variable: "newScaleZ", axis: "z"),
                  x == y, y == z,
                  let divisor = speedAssignment(&parser), divisor == 100,
                  parser.isAtEnd else { return nil }
            return ApplyPlan(
                speedDivisor: divisor,
                triggerPropertyKey: "xian",
                usesPreviousValue: x
            )
        }

        private func parseBranch(
            _ branch: (condition: [SceneLaunchOriginTransitionToken],
                       first: [SceneLaunchOriginTransitionToken],
                       secondCondition: [SceneLaunchOriginTransitionToken]?,
                       second: [SceneLaunchOriginTransitionToken]),
            value: String,
            math: String
        ) -> UpdatePlan? {
            let condition: UpdatePlan.Condition
            if branch.condition == [.identifier("hover")] {
                guard branch.secondCondition == nil else { return nil }
                condition = .localHover
            } else if let shared = sharedCondition(branch.condition) {
                if let second = branch.secondCondition {
                    guard let complement = sharedCondition(second),
                          complement.flag == shared.flag,
                          complement.value == !shared.value else { return nil }
                }
                condition = .shared(shared.flag, shared.value)
            } else { return nil }
            guard mixAssignment(
                branch.first, value: value, math: math, endpoint: true
            ) == .zero,
                  let offset = mixAssignment(
                    branch.second, value: value, math: math, endpoint: false
                  ) else { return nil }
            return UpdatePlan(condition: condition, baseOffset: offset)
        }

        private func mixAssignment(
            _ body: [SceneLaunchOriginTransitionToken],
            value: String,
            math: String,
            endpoint: Bool
        ) -> SIMD3<Double>? {
            var parser = Cursor(tokens: body)
            guard parser.identifier(value), parser.symbol("="), parser.identifier("new"),
                  parser.identifier("Vec3"), parser.symbol("(") else { return nil }
            var offsets: [Double] = []
            for (position, axis) in ["x", "y", "z"].enumerated() {
                guard parser.identifier(math), parser.symbol("."), parser.identifier("mix"),
                      parser.symbol("("), parser.identifier(value), parser.symbol("."),
                      parser.identifier(axis), parser.symbol(",") else { return nil }
                if endpoint {
                    guard parser.identifier("newScale" + axis.uppercased()), parser.symbol("."),
                          parser.identifier(axis) else { return nil }
                    offsets.append(0)
                } else {
                    guard parser.identifier("scriptProperties"), parser.symbol("."),
                          parser.identifier("a" + axis.uppercased()) else { return nil }
                    let sign: Double
                    if parser.symbol("+") { sign = 1 }
                    else if parser.symbol("-") { sign = -1 }
                    else { sign = 0 }
                    if sign == 0 { offsets.append(0) }
                    else {
                        guard let number = parser.number() else { return nil }
                        offsets.append(sign * number)
                    }
                }
                guard parser.symbol(","), parser.identifier("speed"), parser.symbol(")") else {
                    return nil
                }
                if position < 2 { guard parser.symbol(",") else { return nil } }
            }
            _ = parser.symbol(",")
            guard parser.symbol(")") else { return nil }
            guard parser.statementTerminator(), parser.isAtEnd else { return nil }
            return SIMD3(offsets[0], offsets[1], offsets[2])
        }

        private func hoverAssignment(
            _ body: [SceneLaunchOriginTransitionToken],
            hover: Bool,
            flagValue: Bool
        ) -> Bool {
            let statements = splitTopLevel(body)
            guard statements.count == 2 else { return false }
            return statements[0] == [
                .identifier("hover"), .symbol("="), .identifier(String(hover))
            ] && statements[1].count == 5
                && statements[1][0] == .identifier("shared")
                && statements[1][1] == .symbol(".")
                && statements[1][3] == .symbol("=")
                && statements[1][4] == .identifier(String(flagValue))
        }

        private func assignedSharedFlag(
            _ body: [SceneLaunchOriginTransitionToken]
        ) -> String? {
            let statements = splitTopLevel(body)
            guard statements.count == 2, statements[1].count == 5,
                  statements[1][0] == .identifier("shared"),
                  statements[1][1] == .symbol("."),
                  let flag = statements[1][2].identifierValue,
                  statements[1][3] == .symbol("=") else { return nil }
            return flag
        }

        private func sharedCondition(
            _ tokens: [SceneLaunchOriginTransitionToken]
        ) -> (flag: String, value: Bool)? {
            if tokens.count == 3,
               tokens[0] == .identifier("shared"), tokens[1] == .symbol("."),
               let flag = tokens[2].identifierValue {
                return (flag, true)
            }
            guard tokens.count == 5,
                  tokens[0] == .identifier("shared"), tokens[1] == .symbol("."),
                  let flag = tokens[2].identifierValue, tokens[3] == .symbol("=="),
                  let value = tokens[4].identifierValue,
                  value == "true" || value == "false" else { return nil }
            return (flag, value == "true")
        }

        private func endpointAssignment(
            _ parser: inout Cursor,
            variable: String,
            axis: String
        ) -> Bool? {
            guard parser.identifier(variable), parser.symbol("="), parser.identifier("new"),
                  parser.identifier("Vec3"), parser.symbol("("), parser.identifier("initScale"),
                  parser.symbol("."), parser.identifier("add"), parser.symbol("("),
                  parser.identifier("scriptProperties"), parser.symbol("."),
                  parser.identifier("position" + axis.uppercased()), parser.symbol("-") else {
                return nil
            }
            let previous: Bool
            if parser.identifier(variable) { previous = true }
            else if parser.identifier("thisLayer") {
                previous = true
                guard parser.symbol("."), parser.identifier("origin"), parser.symbol("."),
                      parser.identifier(axis) else { return nil }
            } else { return nil }
            guard parser.symbol(")"), parser.symbol(")"),
                  parser.statementTerminator() else { return nil }
            return previous
        }

        private func speedAssignment(_ parser: inout Cursor) -> Double? {
            guard parser.identifier("speed"), parser.symbol("="),
                  parser.identifier("scriptProperties"), parser.symbol("."),
                  parser.identifier("speed"), parser.symbol("/") else { return nil }
            let result = parser.number()
            return parser.statementTerminator() ? result : nil
        }

        private func parseIfElse(
            _ parser: inout Cursor
        ) -> (condition: [SceneLaunchOriginTransitionToken], first: [SceneLaunchOriginTransitionToken],
              secondCondition: [SceneLaunchOriginTransitionToken]?,
              second: [SceneLaunchOriginTransitionToken])? {
            guard parser.identifier("if"), let condition = parser.parenthesized(),
                  let first = parser.braced(), parser.identifier("else") else { return nil }
            var secondCondition: [SceneLaunchOriginTransitionToken]?
            if parser.peekIdentifier("if") {
                guard parser.identifier("if"),
                      let parsedCondition = parser.parenthesized() else { return nil }
                secondCondition = parsedCondition
            }
            guard let second = parser.braced() else { return nil }
            return (condition, first, secondCondition, second)
        }

        private func splitTopLevel(
            _ tokens: [SceneLaunchOriginTransitionToken]
        ) -> [[SceneLaunchOriginTransitionToken]] {
            var result: [[SceneLaunchOriginTransitionToken]] = []
            var current: [SceneLaunchOriginTransitionToken] = []
            var depth = 0
            for token in tokens {
                if token.lineBreakBefore, depth == 0, !current.isEmpty {
                    result.append(current)
                    current = []
                }
                if token == .symbol("(") || token == .symbol("{") { depth += 1 }
                if token == .symbol(")") || token == .symbol("}") { depth -= 1 }
                if token == .symbol(";"), depth == 0 {
                    if !current.isEmpty { result.append(current); current = [] }
                } else { current.append(token) }
            }
            if !current.isEmpty { result.append(current) }
            return result
        }
    }

    private struct Cursor {
        let tokens: [SceneLaunchOriginTransitionToken]
        var index = 0
        var isAtEnd: Bool { index == tokens.count }
        var nextHasLineBreak: Bool {
            index < tokens.count && tokens[index].lineBreakBefore
        }

        mutating func parenthesized() -> [SceneLaunchOriginTransitionToken]? {
            balanced(open: "(", close: ")")
        }
        mutating func braced() -> [SceneLaunchOriginTransitionToken]? {
            balanced(open: "{", close: "}")
        }
        mutating func balanced(open: String, close: String) -> [SceneLaunchOriginTransitionToken]? {
            guard symbol(open) else { return nil }
            let start = index; var depth = 1
            while index < tokens.count, depth > 0 {
                if tokens[index] == .symbol(open) { depth += 1 }
                if tokens[index] == .symbol(close) { depth -= 1 }
                index += 1
            }
            guard depth == 0 else { return nil }
            return Array(tokens[start..<(index - 1)])
        }
        mutating func number() -> Double? {
            guard index < tokens.count, let value = tokens[index].numberValue else { return nil }
            index += 1; return value
        }
        mutating func statementTerminator() -> Bool {
            if symbol(";") { return true }
            return isAtEnd || nextHasLineBreak
        }
        mutating func identifier(_ value: String) -> Bool { consume(.identifier(value)) }
        func peekIdentifier(_ value: String) -> Bool {
            index < tokens.count && tokens[index] == .identifier(value)
        }
        mutating func symbol(_ value: String) -> Bool { consume(.symbol(value)) }
        mutating func consume(_ token: SceneLaunchOriginTransitionToken) -> Bool {
            guard index < tokens.count, tokens[index] == token else { return false }
            index += 1; return true
        }
    }
}

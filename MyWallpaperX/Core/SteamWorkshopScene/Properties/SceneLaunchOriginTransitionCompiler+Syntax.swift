import Foundation

/// Structural parser for the bounded launch-origin source family. Identifier
/// spelling and comments may vary; every statement, hook, branch and operand is checked.
nonisolated enum SceneLaunchOriginTransitionSyntax {
    struct Profile {
        let sharedFlag: String
        let isMaster: Bool
        let propertyNames: [String]
        let basePropertyNames: [String]
        let endpointPropertyNames: [String]
        let speedPropertyName: String
        let speedDivisor: Double
        let triggerPropertyKey: String
        let baseOffset: SIMD3<Double>
        let initialFalseUsesEndpoint: Bool
        let blocksLaunchCohort: Bool
    }

    static func parse(_ source: String) -> Profile? {
        guard source.utf8.count <= 16_384,
              let tokens = SceneLaunchOriginTransitionLexer.lex(source) else { return nil }
        var parser = Parser(tokens: tokens)
        return parser.profile()
    }

    static func parseSharedInitializer(_ source: String) -> [String: Bool]? {
        guard source.utf8.count <= 16_384,
              let tokens = SceneLaunchOriginTransitionLexer.lex(source) else { return nil }
        var parser = Parser(tokens: tokens)
        return parser.sharedInitializer()
    }

    private struct Parser {
        let tokens: [SceneLaunchOriginTransitionToken]
        var index = 0
        let baseNames = ["aX", "aY", "aZ"]
        let endpointNames = ["positionX", "positionY", "positionZ"]

        mutating func profile() -> Profile? {
            guard strictHeader(), identifier("import"), symbol("*"), identifier("as"),
                  let math = takeIdentifier(), identifier("from"), string("WEMath"), semi(),
                  propertyBuilder(), globals(),
                  let update = function("update"), update.arguments.count == 1,
                  let updatePlan = BodyParser(tokens: update.body).update(
                      value: update.arguments[0], math: math
                  ) else { return nil }
            var bindingIdentifiers = [math, update.arguments[0]]
            var cursorFlag: String?
            if peekFunctionName() == "cursorClick" {
                guard let cursor = function("cursorClick"), cursor.arguments.count == 1 else {
                    return nil
                }
                bindingIdentifiers.append(cursor.arguments[0])
                cursorFlag = BodyParser(tokens: cursor.body).cursor()
            }
            guard let apply = function("applyUserProperties"), apply.arguments.count == 1,
                  let applyPlan = BodyParser(tokens: apply.body).apply(
                      changed: apply.arguments[0]
                  ) else { return nil }
            bindingIdentifiers.append(apply.arguments[0])
            guard index == tokens.count,
                  bindingIdentifiersAreValid(bindingIdentifiers) else { return nil }
            let isMaster = updatePlan.condition == .localHover
            let sharedFlag: String
            if isMaster {
                guard let cursorFlag else { return nil }
                sharedFlag = cursorFlag
            } else {
                guard cursorFlag == nil,
                      case let .shared(flag, _) = updatePlan.condition else { return nil }
                sharedFlag = flag
            }
            guard sharedFlag != "__proto__" else { return nil }
            let initialFalseUsesEndpoint = updatePlan.condition == .shared(sharedFlag, false)
            guard !initialFalseUsesEndpoint || applyPlan.usesPreviousValue else { return nil }
            return Profile(
                sharedFlag: sharedFlag,
                isMaster: isMaster,
                propertyNames: baseNames + endpointNames + ["speed"],
                basePropertyNames: baseNames,
                endpointPropertyNames: endpointNames,
                speedPropertyName: "speed",
                speedDivisor: applyPlan.speedDivisor,
                triggerPropertyKey: applyPlan.triggerPropertyKey,
                baseOffset: updatePlan.baseOffset,
                initialFalseUsesEndpoint: initialFalseUsesEndpoint,
                blocksLaunchCohort: isMaster || !initialFalseUsesEndpoint
            )
        }

        mutating func sharedInitializer() -> [String: Bool]? {
            guard strictHeader(), identifier("shared"), symbol("="), symbol("{") else { return nil }
            var result: [String: Bool] = [:]
            while !symbol("}") {
                guard let key = takeIdentifier(), key != "__proto__",
                      result[key] == nil, symbol(":"),
                      let value = takeBool() else { return nil }
                result[key] = value
                if symbol("}") { break }
                guard symbol(",") else { return nil }
            }
            guard semi() else { return nil }
            return !result.isEmpty && index == tokens.count ? result : nil
        }

        private mutating func strictHeader() -> Bool {
            string("use strict") && semi()
        }

        private mutating func propertyBuilder() -> Bool {
            guard identifier("export"), identifier("var"), identifier("scriptProperties"),
                  symbol("="), identifier("createScriptProperties"), symbol("("), symbol(")") else {
                return false
            }
            var names: [String] = []
            while symbol(".") {
                if identifier("finish") {
                    return symbol("(") && symbol(")") && semi()
                        && Set(names) == Set(baseNames + endpointNames + ["speed"])
                        && names.count == 7
                }
                guard identifier("addSlider"), symbol("("), symbol("{"),
                      identifier("name"), symbol(":"), let name = takeString(), symbol(","),
                      identifier("label"), symbol(":"), label(), symbol(","),
                      identifier("value"), symbol(":"), signedNumber() != nil, symbol(","),
                      identifier("min"), symbol(":"), signedNumber() != nil, symbol(","),
                      identifier("max"), symbol(":"), signedNumber() != nil, symbol(","),
                      identifier("integer"), symbol(":"), identifier("false"),
                      symbol("}") else { return false }
                guard symbol(")") else { return false }
                names.append(name)
            }
            return false
        }

        private mutating func label() -> Bool {
            guard takeString() != nil else { return false }
            while symbol("+") { guard takeString() != nil else { return false } }
            return true
        }

        private mutating func globals() -> Bool {
            var declarations: [String: [SceneLaunchOriginTransitionToken]] = [:]
            while identifier("var") {
                while true {
                    guard let name = takeIdentifier(), declarations[name] == nil else { return false }
                    declarations[name] = symbol("=") ? expressionUntilDelimiter() : []
                    if symbol(",") { continue }
                    guard semi() else { return false }
                    break
                }
            }
            let property: (String) -> [SceneLaunchOriginTransitionToken] = {
                [.identifier("scriptProperties"), .symbol("."), .identifier($0)]
            }
            let initial: [SceneLaunchOriginTransitionToken] = [
                .identifier("new"), .identifier("Vec3"), .symbol("(")
            ] + property("aX") + [.symbol(",")]
                + property("aY") + [.symbol(",")]
                + property("aZ") + [.symbol(")")]
            guard declarations.count == 6,
                  let newScaleX = declarations["newScaleX"],
                  let newScaleY = declarations["newScaleY"],
                  let newScaleZ = declarations["newScaleZ"],
                  let initScale = declarations["initScale"],
                  let hover = declarations["hover"],
                  let speed = declarations["speed"] else { return false }
            return newScaleX == property("aX")
                && newScaleY == property("aY")
                && newScaleZ == property("aZ")
                && initScale == initial
                && hover == [.identifier("false")]
                && speed.isEmpty
        }

        private mutating func expressionUntilDelimiter() -> [SceneLaunchOriginTransitionToken] {
            let start = index; var depth = 0
            while index < tokens.count {
                if tokens[index] == .symbol("(") { depth += 1 }
                if tokens[index] == .symbol(")") { depth -= 1 }
                if depth == 0,
                   tokens[index] == .symbol(",") || tokens[index] == .symbol(";") {
                    break
                }
                if depth == 0, tokens[index] == .identifier("export")
                    || tokens[index] == .identifier("var") { break }
                index += 1
            }
            return Array(tokens[start..<index])
        }

        private mutating func function(
            _ expected: String
        ) -> (arguments: [String], body: [SceneLaunchOriginTransitionToken])? {
            guard identifier("export"), identifier("function"), identifier(expected), symbol("(") else {
                return nil
            }
            var arguments: [String] = []
            if !symbol(")") {
                guard let argument = takeIdentifier(), symbol(")") else { return nil }
                arguments = [argument]
            }
            guard symbol("{") else { return nil }
            let start = index; var depth = 1
            while index < tokens.count, depth > 0 {
                if tokens[index] == .symbol("{") { depth += 1 }
                if tokens[index] == .symbol("}") { depth -= 1 }
                index += 1
            }
            guard depth == 0 else { return nil }
            _ = symbol(";")
            return (arguments, Array(tokens[start..<(index - 1)]))
        }

        private func peekFunctionName() -> String? {
            guard index + 2 < tokens.count, tokens[index] == .identifier("export"),
                  tokens[index + 1] == .identifier("function"),
                  let name = tokens[index + 2].identifierValue else { return nil }
            return name
        }

        private mutating func signedNumber() -> Double? {
            let sign = symbol("-") ? -1.0 : 1.0
            guard index < tokens.count, let value = tokens[index].numberValue else { return nil }
            index += 1; return sign * value
        }
        private mutating func takeBool() -> Bool? {
            if identifier("true") { return true }
            if identifier("false") { return false }
            return nil
        }
        private mutating func takeIdentifier() -> String? {
            take(\.identifierValue)
        }
        private mutating func takeString() -> String? {
            take(\.stringValue)
        }
        private mutating func take<T>(
            _ transform: (SceneLaunchOriginTransitionToken) -> T?
        ) -> T? {
            guard index < tokens.count, let value = transform(tokens[index]) else { return nil }
            index += 1; return value
        }
        private mutating func identifier(_ value: String) -> Bool { consume(.identifier(value)) }
        private mutating func string(_ value: String) -> Bool { consume(.string(value)) }
        private mutating func symbol(_ value: String) -> Bool { consume(.symbol(value)) }
        private mutating func semi() -> Bool {
            if symbol(";") { return true }
            return index == tokens.count || tokens[index].lineBreakBefore
        }
        private mutating func consume(_ token: SceneLaunchOriginTransitionToken) -> Bool {
            guard index < tokens.count, tokens[index] == token else { return false }
            index += 1; return true
        }

        private func bindingIdentifiersAreValid(_ values: [String]) -> Bool {
            let reserved: Set<String> = [
                "arguments", "await", "break", "case", "catch", "class", "const",
                "continue", "debugger", "default", "delete", "do", "else", "enum",
                "eval", "export", "extends", "false", "finally", "for", "function",
                "if", "implements", "import", "in", "instanceof", "interface", "let",
                "new", "null", "package", "private", "protected", "public", "return",
                "static", "super", "switch", "this", "throw", "true", "try", "typeof",
                "var", "void", "while", "with", "yield",
            ]
            let fixed: Set<String> = [
                "Vec3", "applyUserProperties", "createScriptProperties", "cursorClick",
                "hover", "initScale", "newScaleX", "newScaleY", "newScaleZ",
                "scriptProperties", "shared", "speed", "thisLayer", "update",
            ]
            return Set(values).count == values.count
                && values.allSatisfy { !reserved.contains($0) && !fixed.contains($0) }
        }
    }
}

import Foundation

/// Pure evaluator for the bounded text-script AST. The step budget is defensive even
/// though the accepted grammar contains no loop or user-defined function construct.
nonisolated enum SceneTextScriptSubsetRuntime {
    private enum Value: Equatable {
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([Value])
        case date(DateComponents)
        case scriptProperties([String: SceneJSONValue])
        case undefined
    }

    private enum Execution {
        case completed
        case returned(Value)
        case failed
    }

    nonisolated static func evaluate(
        program: SceneTextScriptSubsetProgram,
        authoredValue: String,
        properties: [String: SceneJSONValue],
        wallDate: Date,
        timeZone: TimeZone
    ) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .weekday, .hour, .minute, .second],
            from: wallDate
        )
        var variables: [String: Value] = [
                program.parameterName: .string(authoredValue),
                "scriptProperties": .scriptProperties(properties),
            ]
        for name in program.outerVariableNames where variables[name] == nil {
            variables[name] = .undefined
        }
        var evaluator = Evaluator(
            variables: variables,
            wallDate: components,
            remainingSteps: 512
        )
        guard case let .returned(.string(value)) = evaluator.execute(program.statements) else {
            return nil
        }
        return value
    }

    private struct Evaluator {
        var variables: [String: Value]
        let wallDate: DateComponents
        var remainingSteps: Int

        mutating func execute(
            _ statements: [SceneTextScriptSubsetProgram.Statement]
        ) -> Execution {
            for statement in statements {
                guard step() else { return .failed }
                switch statement {
                case let .declare(name, expression):
                    if let expression {
                        guard let value = evaluate(expression) else { return .failed }
                        variables[name] = value
                    } else {
                        variables[name] = .undefined
                    }
                case let .assign(name, operation, expression):
                    guard variables[name] != nil,
                          let right = evaluate(expression) else {
                        return .failed
                    }
                    switch operation {
                    case .assign:
                        variables[name] = right
                    case .add:
                        guard let left = variables[name], let value = add(left, right) else {
                            return .failed
                        }
                        variables[name] = value
                    case .remainder:
                        guard let left = variables[name], let value = remainder(left, right) else {
                            return .failed
                        }
                        variables[name] = value
                    }
                case let .block(statements):
                    switch execute(statements) {
                    case .completed: break
                    case let .returned(value): return .returned(value)
                    case .failed: return .failed
                    }
                case let .conditional(condition, thenStatements, elseStatements):
                    guard let value = evaluate(condition), let flag = truthy(value) else {
                        return .failed
                    }
                    switch execute(flag ? thenStatements : elseStatements) {
                    case .completed: break
                    case let .returned(value): return .returned(value)
                    case .failed: return .failed
                    }
                case let .returnValue(expression):
                    guard let value = evaluate(expression) else { return .failed }
                    return .returned(value)
                }
            }
            return .completed
        }

        mutating func evaluate(
            _ expression: SceneTextScriptSubsetProgram.Expression
        ) -> Value? {
            guard step() else { return nil }
            switch expression {
            case let .bool(value): return .bool(value)
            case let .number(value): return value.isFinite ? .number(value) : nil
            case let .string(value): return .string(value)
            case let .array(values):
                let evaluated = values.compactMap { evaluate($0) }
                return evaluated.count == values.count ? .array(evaluated) : nil
            case let .identifier(name): return variables[name]
            case .newDate: return .date(wallDate)
            case let .member(base, name):
                guard let value = evaluate(base) else { return nil }
                if case let .scriptProperties(properties) = value {
                    return propertyValue(properties[name])
                }
                return .undefined
            case let .subscriptValue(base, index):
                guard case let .array(values)? = evaluate(base),
                      case let .number(number)? = evaluate(index),
                      number.isFinite,
                      number.rounded(.towardZero) == number,
                      values.indices.contains(Int(number)) else {
                    return nil
                }
                return values[Int(number)]
            case let .call(callee, arguments):
                return call(callee, arguments: arguments)
            case let .unaryNot(value):
                guard let evaluated = evaluate(value), let flag = truthy(evaluated) else {
                    return nil
                }
                return .bool(!flag)
            case let .unaryMinus(value):
                guard case let .number(number)? = evaluate(value) else { return nil }
                return .number(-number)
            case let .add(left, right):
                guard let left = evaluate(left), let right = evaluate(right) else { return nil }
                return add(left, right)
            case let .remainder(left, right):
                guard let left = evaluate(left), let right = evaluate(right) else { return nil }
                return remainder(left, right)
            case let .lessThan(left, right):
                guard case let .number(lhs)? = evaluate(left),
                      case let .number(rhs)? = evaluate(right) else {
                    return nil
                }
                return .bool(lhs < rhs)
            case let .logicalAnd(left, right):
                guard let left = evaluate(left), let flag = truthy(left) else { return nil }
                return flag ? evaluate(right) : left
            case let .equal(left, right, negated, coerces):
                guard let left = evaluate(left), let right = evaluate(right) else { return nil }
                let equal = coerces ? looseEqual(left, right) : strictEqual(left, right)
                return .bool(negated ? !equal : equal)
            }
        }

        mutating func call(
            _ callee: SceneTextScriptSubsetProgram.Expression,
            arguments: [SceneTextScriptSubsetProgram.Expression]
        ) -> Value? {
            guard case let .member(base, name) = callee,
                  let receiver = evaluate(base) else {
                return nil
            }
            let values = arguments.compactMap { evaluate($0) }
            guard values.count == arguments.count else { return nil }
            if case let .date(components) = receiver, values.isEmpty {
                switch name {
                case "getFullYear": return components.year.map { .number(Double($0)) }
                case "getMonth": return components.month.map { .number(Double($0 - 1)) }
                case "getDate": return components.day.map { .number(Double($0)) }
                case "getDay": return components.weekday.map { .number(Double($0 - 1)) }
                case "getHours": return components.hour.map { .number(Double($0)) }
                case "getMinutes": return components.minute.map { .number(Double($0)) }
                case "getSeconds": return components.second.map { .number(Double($0)) }
                default: return nil
                }
            }
            if case let .string(string) = receiver, name == "slice",
               (1...2).contains(values.count),
               case let .number(startNumber) = values[0] {
                let endNumber: Double?
                if values.count == 2, case let .number(value) = values[1] {
                    endNumber = value
                } else {
                    endNumber = nil
                }
                return .string(slice(string, start: startNumber, end: endNumber))
            }
            return nil
        }

        mutating func step() -> Bool {
            remainingSteps -= 1
            return remainingSteps >= 0
        }
    }

    private static func propertyValue(_ value: SceneJSONValue?) -> Value? {
        guard let unwrapped = unwrap(value) else { return nil }
        switch unwrapped {
        case let .bool(value): return .bool(value)
        case let .number(value): return value.isFinite ? .number(value) : nil
        case let .string(value): return .string(value)
        case .array, .object, .null: return nil
        }
    }

    private static func unwrap(_ value: SceneJSONValue?) -> SceneJSONValue? {
        guard case let .object(object)? = value, let nested = object["value"] else {
            return value
        }
        return unwrap(nested)
    }

    private static func truthy(_ value: Value) -> Bool? {
        switch value {
        case let .bool(value): return value
        case let .number(value): return value != 0 && !value.isNaN
        case let .string(value): return !value.isEmpty
        case .array, .date, .scriptProperties: return true
        case .undefined: return false
        }
    }

    private static func add(_ left: Value, _ right: Value) -> Value? {
        if case let .string(value) = left {
            return stringValue(right).map { .string(value + $0) }
        }
        if case let .string(value) = right {
            return stringValue(left).map { .string($0 + value) }
        }
        if case .array = left {
            guard let lhs = stringValue(left), let rhs = stringValue(right) else { return nil }
            return .string(lhs + rhs)
        }
        if case .array = right {
            guard let lhs = stringValue(left), let rhs = stringValue(right) else { return nil }
            return .string(lhs + rhs)
        }
        guard case let .number(lhs) = left, case let .number(rhs) = right else { return nil }
        return .number(lhs + rhs)
    }

    private static func remainder(_ left: Value, _ right: Value) -> Value? {
        guard case let .number(lhs) = left,
              case let .number(rhs) = right,
              rhs != 0 else {
            return nil
        }
        return .number(lhs.truncatingRemainder(dividingBy: rhs))
    }

    private static func looseEqual(_ left: Value, _ right: Value) -> Bool {
        if case let .number(number) = left, case let .string(string) = right {
            return numericString(string) == number
        }
        if case let .string(string) = left, case let .number(number) = right {
            return numericString(string) == number
        }
        return strictEqual(left, right)
    }

    private static func strictEqual(_ left: Value, _ right: Value) -> Bool {
        switch (left, right) {
        case let (.bool(lhs), .bool(rhs)): return lhs == rhs
        case let (.number(lhs), .number(rhs)): return lhs == rhs
        case let (.string(lhs), .string(rhs)): return lhs == rhs
        default: return false
        }
    }

    private static func numericString(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let number = Double(trimmed), number.isFinite else { return nil }
        return number
    }

    private static func stringValue(_ value: Value) -> String? {
        switch value {
        case let .string(value): return value
        case let .number(value):
            guard value.isFinite else { return nil }
            if value.rounded(.towardZero) == value { return String(Int(value)) }
            return String(value)
        case let .bool(value): return value ? "true" : "false"
        case let .array(values):
            return values.map { stringValue($0) ?? "" }.joined(separator: ",")
        case .date, .scriptProperties, .undefined: return nil
        }
    }

    private static func slice(_ value: String, start: Double, end: Double?) -> String {
        let characters = Array(value)
        func normalized(_ raw: Double, default fallback: Int) -> Int {
            guard raw.isFinite else { return fallback }
            let integer = Int(raw.rounded(.towardZero))
            return min(max(integer < 0 ? characters.count + integer : integer, 0), characters.count)
        }
        let lower = normalized(start, default: 0)
        let upper = end.map { normalized($0, default: characters.count) } ?? characters.count
        guard lower < upper else { return "" }
        return String(characters[lower..<upper])
    }
}

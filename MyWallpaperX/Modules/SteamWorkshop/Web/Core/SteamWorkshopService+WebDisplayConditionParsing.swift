import Foundation

extension SteamWorkshopService {
    enum WebDisplayConditionToken: Equatable {
        case identifier(String)
        case number(Double)
        case string(String)
        case boolean(Bool)
        case leftParen
        case rightParen
        case and
        case or
        case not
        case equal
        case notEqual
        case greaterThan
        case greaterThanOrEqual
        case lessThan
        case lessThanOrEqual
    }

    enum WebDisplayConditionValue {
        case bool(Bool)
        case number(Double)
        case string(String)
        case undefined

        var boolValue: Bool {
            switch self {
            case let .bool(value):
                return value
            case let .number(value):
                return value != 0
            case let .string(value):
                return value.isEmpty == false
            case .undefined:
                return false
            }
        }

        var numberValue: Double? {
            switch self {
            case let .number(value):
                return value
            case let .bool(value):
                return value ? 1 : 0
            case let .string(value):
                return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            case .undefined:
                return nil
            }
        }

        var stringValue: String {
            switch self {
            case let .bool(value):
                return value ? "true" : "false"
            case let .number(value):
                if floor(value) == value {
                    return String(Int(value))
                }
                return String(value)
            case let .string(value):
                return value
            case .undefined:
                return ""
            }
        }
    }

    struct WebDisplayConditionParser {
        private let tokens: [WebDisplayConditionToken]
        private let values: [String: SteamWorkshopWebPropertyValue]
        private let comboTextValues: [String: String]
        private var index = 0

        init(
            tokens: [WebDisplayConditionToken],
            values: [String: SteamWorkshopWebPropertyValue],
            comboTextValues: [String: String]
        ) {
            self.tokens = tokens
            self.values = values
            self.comboTextValues = comboTextValues
        }

        var isAtEnd: Bool {
            index >= tokens.count
        }

        mutating func parse() -> WebDisplayConditionValue? {
            parseOrExpression()
        }

        private mutating func parseOrExpression() -> WebDisplayConditionValue? {
            guard var lhs = parseAndExpression() else { return nil }
            while match(.or) {
                guard let rhs = parseAndExpression() else { return nil }
                lhs = .bool(lhs.boolValue || rhs.boolValue)
            }
            return lhs
        }

        private mutating func parseAndExpression() -> WebDisplayConditionValue? {
            guard var lhs = parseComparisonExpression() else { return nil }
            while match(.and) {
                guard let rhs = parseComparisonExpression() else { return nil }
                lhs = .bool(lhs.boolValue && rhs.boolValue)
            }
            return lhs
        }

        private mutating func parseComparisonExpression() -> WebDisplayConditionValue? {
            guard var lhs = parseUnaryExpression() else { return nil }

            while let comparator = matchComparisonOperator() {
                guard let rhs = parseUnaryExpression() else { return nil }
                lhs = .bool(compare(lhs, rhs, using: comparator))
            }

            return lhs
        }

        private mutating func parseUnaryExpression() -> WebDisplayConditionValue? {
            if match(.not) {
                guard let value = parseUnaryExpression() else { return nil }
                return .bool(value.boolValue == false)
            }
            return parsePrimaryExpression()
        }

        private mutating func parsePrimaryExpression() -> WebDisplayConditionValue? {
            guard isAtEnd == false else { return nil }
            let token = tokens[index]
            index += 1

            switch token {
            case let .identifier(identifier):
                return resolveIdentifier(identifier)
            case let .number(number):
                return .number(number)
            case let .string(string):
                return .string(string)
            case let .boolean(boolean):
                return .bool(boolean)
            case .leftParen:
                guard let nested = parseOrExpression(), match(.rightParen) else { return nil }
                return nested
            case .rightParen, .and, .or, .not, .equal, .notEqual, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual:
                return nil
            }
        }

        private mutating func match(_ token: WebDisplayConditionToken) -> Bool {
            guard index < tokens.count, tokens[index] == token else { return false }
            index += 1
            return true
        }

        private mutating func matchComparisonOperator() -> WebDisplayConditionToken? {
            guard index < tokens.count else { return nil }
            let token = tokens[index]
            switch token {
            case .equal, .notEqual, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual:
                index += 1
                return token
            default:
                return nil
            }
        }

        private func resolveIdentifier(_ identifier: String) -> WebDisplayConditionValue {
            let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "true" { return .bool(true) }
            if trimmed == "false" { return .bool(false) }

            let key: String
            let field: String?
            if trimmed.hasSuffix(".value") {
                key = String(trimmed.dropLast(".value".count))
                field = "value"
            } else if trimmed.hasSuffix(".text") {
                key = String(trimmed.dropLast(".text".count))
                field = "text"
            } else {
                key = trimmed
                field = nil
            }

            guard let value = values[key] else {
                return .undefined
            }

            if field == "text" {
                return .string(comboTextValues[key] ?? value.displayConditionTextValue)
            }

            switch value {
            case let .bool(boolean):
                return .bool(boolean)
            case let .number(number):
                return .number(number)
            case let .string(string):
                return .string(string)
            }
        }

        private func compare(_ lhs: WebDisplayConditionValue, _ rhs: WebDisplayConditionValue, using comparator: WebDisplayConditionToken) -> Bool {
            switch comparator {
            case .equal:
                if let left = lhs.numberValue, let right = rhs.numberValue {
                    return left == right
                }
                return lhs.stringValue == rhs.stringValue
            case .notEqual:
                if let left = lhs.numberValue, let right = rhs.numberValue {
                    return left != right
                }
                return lhs.stringValue != rhs.stringValue
            case .greaterThan:
                guard let left = lhs.numberValue, let right = rhs.numberValue else { return false }
                return left > right
            case .greaterThanOrEqual:
                guard let left = lhs.numberValue, let right = rhs.numberValue else { return false }
                return left >= right
            case .lessThan:
                guard let left = lhs.numberValue, let right = rhs.numberValue else { return false }
                return left < right
            case .lessThanOrEqual:
                guard let left = lhs.numberValue, let right = rhs.numberValue else { return false }
                return left <= right
            default:
                return false
            }
        }
    }

    static func tokenizeWebDisplayCondition(_ input: String) -> [WebDisplayConditionToken]? {
        var tokens: [WebDisplayConditionToken] = []
        var index = input.startIndex

        func advance(_ offset: Int = 1) {
            index = input.index(index, offsetBy: offset)
        }

        while index < input.endIndex {
            let character = input[index]

            if character.isWhitespace {
                advance()
                continue
            }

            let remaining = input[index...]
            if remaining.hasPrefix("&&") {
                tokens.append(.and)
                advance(2)
                continue
            }
            if remaining.hasPrefix("||") {
                tokens.append(.or)
                advance(2)
                continue
            }
            if remaining.hasPrefix("===") || remaining.hasPrefix("==") {
                tokens.append(.equal)
                advance(remaining.hasPrefix("===") ? 3 : 2)
                continue
            }
            if remaining.hasPrefix("!==") || remaining.hasPrefix("!=") {
                tokens.append(.notEqual)
                advance(remaining.hasPrefix("!==") ? 3 : 2)
                continue
            }
            if remaining.hasPrefix(">=") {
                tokens.append(.greaterThanOrEqual)
                advance(2)
                continue
            }
            if remaining.hasPrefix("<=") {
                tokens.append(.lessThanOrEqual)
                advance(2)
                continue
            }

            switch character {
            case "(":
                tokens.append(.leftParen)
                advance()
            case ")":
                tokens.append(.rightParen)
                advance()
            case "!":
                tokens.append(.not)
                advance()
            case ">":
                tokens.append(.greaterThan)
                advance()
            case "<":
                tokens.append(.lessThan)
                advance()
            case "'", "\"":
                let quote = character
                advance()
                let start = index
                while index < input.endIndex, input[index] != quote {
                    advance()
                }
                guard index <= input.endIndex else { return nil }
                tokens.append(.string(String(input[start..<index])))
                guard index < input.endIndex else { return nil }
                advance()
            default:
                if character.isNumber || character == "-" {
                    let hasMinus = character == "-"
                    if hasMinus {
                        advance()
                        // 跳过负号后可能存在的空白（如 "value > - 0.5"）
                        while index < input.endIndex, input[index].isWhitespace {
                            advance()
                        }
                    }
                    let numberStart = index
                    while index < input.endIndex, input[index].isNumber || input[index] == "." {
                        advance()
                    }
                    guard index > numberStart else { return nil }
                    let signPart = hasMinus ? "-" : ""
                    let digitsPart = String(input[numberStart..<index])
                    guard let value = Double(signPart + digitsPart) else { return nil }
                    tokens.append(.number(value))
                    continue
                }

                if character.isLetter || character == "_" {
                    let start = index
                    advance()
                    while index < input.endIndex {
                        let current = input[index]
                        if current.isLetter || current.isNumber || current == "_" || current == "." {
                            advance()
                        } else {
                            break
                        }
                    }
                    let identifier = String(input[start..<index])
                    if identifier == "true" {
                        tokens.append(.boolean(true))
                    } else if identifier == "false" {
                        tokens.append(.boolean(false))
                    } else {
                        tokens.append(.identifier(identifier))
                    }
                    continue
                }

                return nil
            }
        }

        return tokens
    }

    static func containsOnlySupportedConditionOperators(_ condition: String) -> Bool {
        let sanitized = condition
            .replacingOccurrences(of: "!==", with: "")
            .replacingOccurrences(of: "===", with: "")
            .replacingOccurrences(of: "!=", with: "")
            .replacingOccurrences(of: "==", with: "")
            .replacingOccurrences(of: ">=", with: "")
            .replacingOccurrences(of: "<=", with: "")
            .replacingOccurrences(of: "&&", with: "")
            .replacingOccurrences(of: "||", with: "")
        return sanitized.contains("=") == false
    }
}

import Foundation

/// Structural parser for two bounded transform callbacks:
///
/// - `value = scriptProperties.<slider>` (scalar is splatted into Vec3)
/// - `value.<axis> = scriptProperties.<slider>` for one to three axes
///
/// The complete property builder and exported update body must match. Extra
/// functions, statements, properties, or operators are rejected.
nonisolated enum ScenePropertyVectorScriptSyntax {
    nonisolated enum Operation: Equatable {
        case scalarSplat(property: String)
        case components([(component: Int, property: String)])

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.scalarSplat(left), .scalarSplat(right)):
                left == right
            case let (.components(left), .components(right)):
                left.map(\.component) == right.map(\.component)
                    && left.map(\.property) == right.map(\.property)
            default:
                false
            }
        }
    }

    nonisolated struct Profile: Equatable {
        let propertyNames: [String]
        let operation: Operation
    }

    nonisolated static func parse(_ source: String) -> Profile? {
        guard source.utf8.count <= 16_384,
              let tokens = SceneLaunchOriginTransitionLexer.lex(source) else {
            return nil
        }
        var parser = Parser(tokens: tokens)
        return parser.profile()
    }

    private struct Parser {
        let tokens: [SceneLaunchOriginTransitionToken]
        var index = 0

        mutating func profile() -> Profile? {
            guard string("use strict"), semi(),
                  identifier("export"), identifier("var"),
                  identifier("scriptProperties"), symbol("="),
                  identifier("createScriptProperties"), symbol("("), symbol(")"),
                  let propertyNames = propertyBuilder(),
                  identifier("export"), identifier("function"),
                  identifier("update"), symbol("("),
                  let value = takeIdentifier(), symbol(")"), symbol("{") else {
                return nil
            }
            let operation: Operation
            let operationStart = index
            if identifier(value), symbol("="),
               identifier("scriptProperties"), symbol("."),
               let property = takeIdentifier(), semi() {
                operation = .scalarSplat(property: property)
            } else {
                index = operationStart
                var components: [(component: Int, property: String)] = []
                while identifier(value), symbol("."),
                      let axis = takeIdentifier(), symbol("="),
                      identifier("scriptProperties"), symbol("."),
                      let property = takeIdentifier(), semi() {
                    guard let component = componentIndex(axis),
                          !components.contains(where: { $0.component == component }) else {
                        return nil
                    }
                    components.append((component, property))
                }
                guard !components.isEmpty else { return nil }
                operation = .components(components)
            }
            guard identifier("return"), identifier(value), semi(), symbol("}"),
                  optionalSemi(), index == tokens.count,
                  let referenced = referencedProperties(operation),
                  Set(referenced) == Set(propertyNames),
                  referenced.count == propertyNames.count else { return nil }
            return Profile(propertyNames: propertyNames, operation: operation)
        }

        private mutating func propertyBuilder() -> [String]? {
            var names: [String] = []
            while symbol(".") {
                if identifier("finish") {
                    guard symbol("("), symbol(")"), semi(),
                          !names.isEmpty, names.count <= 3,
                          Set(names).count == names.count else { return nil }
                    return names
                }
                guard identifier("addSlider"), symbol("("), symbol("{"),
                      identifier("name"), symbol(":"),
                      let name = takeString(), validPropertyName(name), symbol(","),
                      identifier("label"), symbol(":"), label(), symbol(","),
                      identifier("value"), symbol(":"), signedNumber() != nil,
                      symbol(","), identifier("min"), symbol(":"),
                      signedNumber() != nil, symbol(","), identifier("max"),
                      symbol(":"), signedNumber() != nil, symbol(","),
                      identifier("integer"), symbol(":"),
                      (identifier("false") || identifier("true")),
                      symbol("}"), symbol(")") else { return nil }
                names.append(name)
            }
            return nil
        }

        private func referencedProperties(_ operation: Operation) -> [String]? {
            switch operation {
            case let .scalarSplat(property):
                return validPropertyName(property) ? [property] : nil
            case let .components(values):
                let properties = values.map(\.property)
                return properties.allSatisfy(validPropertyName) ? properties : nil
            }
        }

        private func componentIndex(_ axis: String) -> Int? {
            switch axis {
            case "x": 0
            case "y": 1
            case "z": 2
            default: nil
            }
        }

        private func validPropertyName(_ value: String) -> Bool {
            guard value != "__proto__", !value.isEmpty,
                  let first = value.unicodeScalars.first,
                  first.isASCII else { return false }
            let validStart = first.value == 0x24 || first.value == 0x5F
                || 0x41...0x5A ~= first.value || 0x61...0x7A ~= first.value
            return validStart && value.unicodeScalars.dropFirst().allSatisfy {
                $0.isASCII && ($0.value == 0x24 || $0.value == 0x5F
                    || 0x30...0x39 ~= $0.value || 0x41...0x5A ~= $0.value
                    || 0x61...0x7A ~= $0.value)
            }
        }

        private mutating func label() -> Bool {
            guard takeString() != nil else { return false }
            while symbol("+") { guard takeString() != nil else { return false } }
            return true
        }

        private mutating func signedNumber() -> Double? {
            let sign = symbol("-") ? -1.0 : 1.0
            guard index < tokens.count,
                  let number = tokens[index].numberValue else { return nil }
            index += 1
            let value = sign * number
            return value.isFinite ? value : nil
        }

        private mutating func takeIdentifier() -> String? { take(\.identifierValue) }
        private mutating func takeString() -> String? { take(\.stringValue) }

        private mutating func take<T>(
            _ transform: (SceneLaunchOriginTransitionToken) -> T?
        ) -> T? {
            guard index < tokens.count,
                  let value = transform(tokens[index]) else { return nil }
            index += 1
            return value
        }

        private mutating func identifier(_ value: String) -> Bool {
            consume(.identifier(value))
        }

        private mutating func string(_ value: String) -> Bool {
            consume(.string(value))
        }

        private mutating func symbol(_ value: String) -> Bool {
            consume(.symbol(value))
        }

        private mutating func semi() -> Bool {
            if symbol(";") { return true }
            return index == tokens.count || tokens[index].lineBreakBefore
        }

        private mutating func optionalSemi() -> Bool {
            _ = symbol(";")
            return true
        }

        private mutating func consume(
            _ token: SceneLaunchOriginTransitionToken
        ) -> Bool {
            guard index < tokens.count, tokens[index] == token else { return false }
            index += 1
            return true
        }
    }
}

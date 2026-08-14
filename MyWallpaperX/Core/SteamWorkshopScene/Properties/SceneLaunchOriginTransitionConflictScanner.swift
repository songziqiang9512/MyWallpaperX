import Foundation

/// Rejection-only scan for SceneScript sources outside the admitted transition
/// profile. It never authorizes execution; it only attributes direct shared flag
/// writes or rejects sources whose shared access cannot be bounded.
nonisolated enum SceneLaunchOriginTransitionConflictScanner {
    nonisolated enum Outcome: Equatable {
        case flags(Set<String>)
        case reject
    }

    nonisolated static func scan(_ source: String) -> Outcome {
        guard source.utf8.count <= 16_384,
              let tokens = tokenize(source),
              hasExactUseStrictDirective(tokens),
              groupingIsBalanced(tokens),
              computedAccessesAreSafelyConsumed(tokens) else { return .reject }
        let indirectIdentifiers: Set<String> = [
            "Function", "Object", "Proxy", "Reflect", "constructor", "eval",
            "global", "globalThis", "require", "this", "valueOf", "window",
            "__defineGetter__", "__defineSetter__", "__lookupGetter__",
            "__lookupSetter__",
        ]
        var flags: Set<String> = []
        for index in tokens.indices {
            guard case let .identifier(identifier) = tokens[index] else { continue }
            if indirectIdentifiers.contains(identifier) { return .reject }
            if identifier == "import" || identifier == "setInterval" { return .reject }
            if identifier == "setTimeout",
               !isAllowedEngineTimeout(at: index, tokens: tokens) { return .reject }
            guard identifier == "shared" else { continue }
            guard index + 2 < tokens.count,
                  tokens[index + 1] == .symbol(0x2E),
                  case let .identifier(flag) = tokens[index + 2],
                  flag != "__proto__" else { return .reject }
            if !isBareIfCondition(at: index, tokens: tokens) { flags.insert(flag) }
        }
        return .flags(flags)
    }

    private static func hasExactUseStrictDirective(_ tokens: [Token]) -> Bool {
        guard tokens.count >= 2,
              tokens[0] == .string("use strict"),
              tokens[1] == .symbol(0x3B) else { return false }
        return true
    }

    private static func isAllowedEngineTimeout(at index: Int, tokens: [Token]) -> Bool {
        guard index >= 2, index + 6 < tokens.count,
              tokens[index - 2] == .identifier("engine"),
              tokens[index - 1] == .symbol(0x2E),
              tokens[index + 1] == .symbol(0x28),
              tokens[index + 2] == .symbol(0x28),
              tokens[index + 3] == .symbol(0x29),
              tokens[index + 4] == .symbol(0x3D),
              tokens[index + 5] == .symbol(0x3E),
              tokens[index + 6] == .symbol(0x7B) else { return false }
        return true
    }

    private static func groupingIsBalanced(_ tokens: [Token]) -> Bool {
        var stack: [UInt32] = []
        let closings: [UInt32: UInt32] = [0x29: 0x28, 0x5D: 0x5B, 0x7D: 0x7B]
        for token in tokens {
            guard case let .symbol(value) = token else { continue }
            if value == 0x28 || value == 0x5B || value == 0x7B {
                stack.append(value)
            } else if let opening = closings[value] {
                guard stack.popLast() == opening else { return false }
            }
        }
        return stack.isEmpty
    }

    private static func computedAccessesAreSafelyConsumed(_ tokens: [Token]) -> Bool {
        for index in tokens.indices where tokens[index] == .symbol(0x5B) {
            guard !isArrayLiteralStart(index, tokens: tokens) else { continue }
            guard let closing = matchingSquareBracket(index, tokens: tokens),
                  !tokens[(index + 1)..<closing].contains(where: \.isString),
                  closing + 1 < tokens.count,
                  case let .symbol(operation) = tokens[closing + 1],
                  operation == 0x2B || operation == 0x2D,
                  closing + 2 >= tokens.count
                    || tokens[closing + 2] != .symbol(operation)
                        && tokens[closing + 2] != .symbol(0x3D) else { return false }
        }
        return true
    }

    /// Treat square brackets as postfix access unless the preceding token is a
    /// narrow, unambiguous array-literal introducer. This keeps expression
    /// terminators such as `}`, `)` and optional/member `.` on the rejecting
    /// path without trying to enumerate every JavaScript expression shape.
    private static func isArrayLiteralStart(_ index: Int, tokens: [Token]) -> Bool {
        guard index > 0 else { return true }
        switch tokens[index - 1] {
        case let .identifier(identifier):
            return ["case", "else", "return", "throw", "yield"].contains(identifier)
        case .string:
            return false
        case let .symbol(value):
            return value == 0x28 || value == 0x5B || value == 0x7B
                || value == 0x2C || value == 0x3A || value == 0x3B
                || value == 0x3D || value == 0x3F || value == 0x3E
        }
    }

    private static func matchingSquareBracket(
        _ start: Int,
        tokens: [Token]
    ) -> Int? {
        var depth = 0
        for index in start..<tokens.count {
            if tokens[index] == .symbol(0x5B) { depth += 1 }
            if tokens[index] == .symbol(0x5D) {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func isBareIfCondition(
        at sharedIndex: Int,
        tokens: [Token]
    ) -> Bool {
        let after = sharedIndex + 3
        guard after < tokens.count, tokens[after] == .symbol(0x29) else { return false }
        if sharedIndex >= 2,
           tokens[sharedIndex - 2] == .identifier("if"),
           tokens[sharedIndex - 1] == .symbol(0x28) { return true }
        return sharedIndex >= 3
            && tokens[sharedIndex - 3] == .identifier("if")
            && tokens[sharedIndex - 2] == .symbol(0x28)
            && tokens[sharedIndex - 1] == .symbol(0x21)
    }

    private enum Token: Equatable {
        case identifier(String)
        case symbol(UInt32)
        case string(String)

        var isString: Bool {
            if case .string = self { return true }
            return false
        }
    }

    private static func tokenize(_ source: String) -> [Token]? {
        let scalars = Array(source.unicodeScalars)
        var tokens: [Token] = []
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.properties.isWhitespace {
                index += 1
                continue
            }
            if scalar.value == 0x2F, index + 1 < scalars.count {
                if scalars[index + 1].value == 0x2F {
                    index += 2
                    while index < scalars.count,
                          !isLineTerminator(scalars[index]) { index += 1 }
                    continue
                }
                if scalars[index + 1].value == 0x2A {
                    guard let next = blockCommentEnd(scalars, from: index + 2) else {
                        return nil
                    }
                    index = next
                    continue
                }
            }
            if scalar.value == 0x22 || scalar.value == 0x27 {
                let contentStart = index + 1
                guard let next = stringEnd(
                    scalars,
                    from: contentStart,
                    quote: scalar.value
                ) else { return nil }
                tokens.append(.string(String(
                    String.UnicodeScalarView(scalars[contentStart..<(next - 1)])
                )))
                index = next
                continue
            }
            if scalar.value == 0x5C || scalar.value == 0x60 { return nil }
            if isASCIIIdentifierStart(scalar.value) {
                let start = index
                index += 1
                while index < scalars.count,
                      isASCIIIdentifierContinue(scalars[index].value) { index += 1 }
                tokens.append(.identifier(String(
                    String.UnicodeScalarView(scalars[start..<index])
                )))
                continue
            }
            tokens.append(.symbol(scalar.value))
            index += 1
        }
        return tokens
    }

    private static func blockCommentEnd(
        _ scalars: [Unicode.Scalar],
        from start: Int
    ) -> Int? {
        var index = start
        while index + 1 < scalars.count {
            if scalars[index].value == 0x2A,
               scalars[index + 1].value == 0x2F { return index + 2 }
            index += 1
        }
        return nil
    }

    private static func stringEnd(
        _ scalars: [Unicode.Scalar],
        from start: Int,
        quote: UInt32
    ) -> Int? {
        var index = start
        while index < scalars.count {
            let value = scalars[index].value
            if value == quote { return index + 1 }
            if isLineTerminator(scalars[index]) { return nil }
            if value == 0x5C {
                index += 1
                guard index < scalars.count else { return nil }
            }
            index += 1
        }
        return nil
    }

    private static func isASCIIIdentifierStart(_ value: UInt32) -> Bool {
        value == 0x24 || value == 0x5F
            || 0x41...0x5A ~= value || 0x61...0x7A ~= value
    }

    private static func isASCIIIdentifierContinue(_ value: UInt32) -> Bool {
        isASCIIIdentifierStart(value) || 0x30...0x39 ~= value
    }

    private static func isLineTerminator(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x000A || scalar.value == 0x000D
            || scalar.value == 0x2028 || scalar.value == 0x2029
    }
}

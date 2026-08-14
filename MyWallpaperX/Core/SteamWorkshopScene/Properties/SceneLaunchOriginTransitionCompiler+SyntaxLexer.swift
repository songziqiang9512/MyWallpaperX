import Foundation

nonisolated struct SceneLaunchOriginTransitionToken: Equatable {
    nonisolated enum Kind: Equatable {
        case identifier(String)
        case number(Double)
        case string(String)
        case symbol(String)
    }

    let kind: Kind
    let lineBreakBefore: Bool

    static func identifier(_ value: String) -> Self {
        Self(kind: .identifier(value), lineBreakBefore: false)
    }

    static func number(_ value: Double) -> Self {
        Self(kind: .number(value), lineBreakBefore: false)
    }

    static func string(_ value: String) -> Self {
        Self(kind: .string(value), lineBreakBefore: false)
    }

    static func symbol(_ value: String) -> Self {
        Self(kind: .symbol(value), lineBreakBefore: false)
    }

    var identifierValue: String? {
        guard case let .identifier(value) = kind else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case let .number(value) = kind else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = kind else { return nil }
        return value
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind
    }

    func withLineBreakBefore(_ value: Bool) -> Self {
        Self(kind: kind, lineBreakBefore: value)
    }
}

nonisolated enum SceneLaunchOriginTransitionLexer {
    static func lex(_ source: String) -> [SceneLaunchOriginTransitionToken]? {
        let result = scan(source)
        return result.complete ? result.tokens : nil
    }

    private struct ScanResult {
        let tokens: [SceneLaunchOriginTransitionToken]
        let complete: Bool
    }

    private static func scan(_ source: String) -> ScanResult {
        let characters = Array(source)
        var result: [SceneLaunchOriginTransitionToken] = []
        var index = 0
        var pendingLineBreak = false
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace {
                if isLineTerminator(character) {
                    pendingLineBreak = true
                }
                index += 1
                continue
            }
            if character == "/", index + 1 < characters.count {
                if characters[index + 1] == "/" {
                    index += 2
                    while index < characters.count,
                          !isLineTerminator(characters[index]) { index += 1 }
                    continue
                }
                if characters[index + 1] == "*" {
                    index += 2
                    var closed = false
                    while index + 1 < characters.count {
                        if isLineTerminator(characters[index]) {
                            pendingLineBreak = true
                        }
                        if characters[index] == "*", characters[index + 1] == "/" {
                            index += 2; closed = true; break
                        }
                        index += 1
                    }
                    guard closed else { return .init(tokens: result, complete: false) }
                    continue
                }
            }
            let token: SceneLaunchOriginTransitionToken
            if isASCIIIdentifierStart(character) {
                let start = index; index += 1
                while index < characters.count,
                      isASCIIIdentifierContinue(characters[index]) { index += 1 }
                token = .identifier(String(characters[start..<index]))
            } else if isASCIIDigit(character) || character == "."
                && index + 1 < characters.count && isASCIIDigit(characters[index + 1]) {
                let start = index; var dots = 0
                repeat { if characters[index] == "." { dots += 1 }; index += 1 }
                while index < characters.count
                    && (isASCIIDigit(characters[index]) || characters[index] == ".")
                let raw = String(characters[start..<index])
                let hasLegacyLeadingZero = raw.first == "0" && raw.count > 1
                    && isASCIIDigit(raw[raw.index(after: raw.startIndex)])
                guard !hasLegacyLeadingZero, dots <= 1,
                      let value = Double(raw), value.isFinite else {
                    return .init(tokens: result, complete: false)
                }
                token = .number(value)
            } else if character == "\"" || character == "'" {
                let quote = character; index += 1; let start = index
                while index < characters.count, characters[index] != quote {
                    guard characters[index] != "\\",
                          !isLineTerminator(characters[index]) else {
                        return .init(tokens: result, complete: false)
                    }
                    index += 1
                }
                guard index < characters.count else {
                    return .init(tokens: result, complete: false)
                }
                token = .string(String(characters[start..<index])); index += 1
            } else {
                let two = index + 1 < characters.count
                    ? String(characters[index...index + 1]) : ""
                if ["==", "!="].contains(two) { token = .symbol(two); index += 2 }
                else {
                    guard "(){};.*+-/=<>:,".contains(character) else {
                        return .init(tokens: result, complete: false)
                    }
                    token = .symbol(String(character)); index += 1
                }
            }
            result.append(token.withLineBreakBefore(pendingLineBreak))
            pendingLineBreak = false
            guard result.count <= 4_096 else {
                return .init(tokens: result, complete: false)
            }
        }
        return .init(tokens: result, complete: true)
    }

    private static func isASCIIIdentifierStart(_ character: Character) -> Bool {
        guard let value = asciiValue(character) else { return false }
        return value == 0x24 || value == 0x5F
            || 0x41...0x5A ~= value || 0x61...0x7A ~= value
    }

    private static func isASCIIIdentifierContinue(_ character: Character) -> Bool {
        isASCIIIdentifierStart(character) || isASCIIDigit(character)
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let value = asciiValue(character) else { return false }
        return 0x30...0x39 ~= value
    }

    private static func asciiValue(_ character: Character) -> UInt32? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.isASCII else { return nil }
        return scalar.value
    }

    private static func isLineTerminator(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            $0.value == 0x000A || $0.value == 0x000D
                || $0.value == 0x2028 || $0.value == 0x2029
        }
    }
}

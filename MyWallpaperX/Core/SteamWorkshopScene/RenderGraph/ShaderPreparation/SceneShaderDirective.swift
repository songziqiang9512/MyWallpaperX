import Foundation

nonisolated enum SceneShaderDirective {
    case define(String, SceneShaderMacroValue)
    case defineFunction(SceneShaderFunctionMacro)
    case undef(String)
    case include(String)
    case require(String)
    case malformedRequire(String)
    case ifExpression(String)
    case ifdef(String, inverted: Bool)
    case elifExpression(String)
    case elseDirective
    case endif
    case unsupported(String)
    case unknown(String)
    case unsupportedFunctionMacro(String)
    case malformed(String)

    static func parse(_ line: String) -> SceneShaderDirective? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let body = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        let name = body.prefix { $0 == "_" || $0.isLetter || $0.isNumber }
        guard let first = name.first, first == "_" || first.isLetter else {
            return .malformed("Shader directive has no name.")
        }
        let operand = body.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
        switch name {
        case "define": return parseDefine(operand)
        case "undef": return identifierOnly(operand).map(SceneShaderDirective.undef)
            ?? .malformed("Malformed #undef directive.")
        case "include": return parseInclude(operand)
        case "require": return parseRequire(operand)
        case "if": return operand.isEmpty
            ? .malformed("Shader #if has no expression.")
            : .ifExpression(operand)
        case "ifdef": return identifierOnly(operand).map {
            .ifdef($0, inverted: false)
        } ?? .malformed("Malformed #ifdef directive.")
        case "ifndef": return identifierOnly(operand).map {
            .ifdef($0, inverted: true)
        } ?? .malformed("Malformed #ifndef directive.")
        case "else": return operand.isEmpty
            ? .elseDirective
            : .malformed("Shader #else has operands.")
        case "endif": return operand.isEmpty
            ? .endif
            : .malformed("Shader #endif has operands.")
        case "elif": return operand.isEmpty
            ? .malformed("Shader #elif has no expression.")
            : .elifExpression(operand)
        default: return .unknown(String(name))
        }
    }

    private static func parseDefine(_ operand: String) -> SceneShaderDirective {
        let name = operand.prefix { $0 == "_" || $0.isLetter || $0.isNumber }
        guard let identifier = identifierOnly(String(name)), !identifier.isEmpty else {
            return .malformed("Malformed #define directive.")
        }
        let suffix = operand.dropFirst(name.count)
        if suffix.first == "(" {
            switch SceneShaderFunctionMacro.parse(name: identifier, suffix: suffix) {
            case let .success(macro): return .defineFunction(macro)
            case let .failure(failure): return .unsupportedFunctionMacro(failure.message)
            }
        }
        let value = suffix.trimmingCharacters(in: .whitespaces)
        guard !value.contains("//") else {
            return .malformed("Inline comments are not valid macro values.")
        }
        if value.isEmpty { return .define(identifier, .bare) }
        if let integer = Int64(value) {
            guard value.range(
                of: #"^[+-]?(?:0|[1-9][0-9]*)$"#,
                options: .regularExpression
            ) != nil else {
                return .malformed("Ambiguous shader integer literal is unsupported.")
            }
            return .define(identifier, .integer(integer))
        }
        if SceneShaderMacroValue.isFloatingLiteral(value) {
            return .define(identifier, .floatingLiteral(value))
        }
        if SceneShaderMacroReplacement.isSupported(value) {
            return .define(identifier, .tokenSequence(value))
        }
        return .malformed("Object-like shader macro replacement is unsupported or unbalanced.")
    }

    private static func parseInclude(_ operand: String) -> SceneShaderDirective {
        guard let first = operand.first, first == "\"" || first == "<" else {
            return .malformed("Shader include must use quotes or angle brackets.")
        }
        let closing: Character = first == "\"" ? "\"" : ">"
        guard let end = operand.dropFirst().firstIndex(of: closing) else {
            return .malformed("Shader include is unterminated.")
        }
        let path = String(operand[operand.index(after: operand.startIndex)..<end])
        let tail = operand[operand.index(after: end)...]
            .trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, tail.isEmpty else {
            return .malformed("Malformed shader include.")
        }
        return .include(path)
    }

    private static func parseRequire(_ operand: String) -> SceneShaderDirective {
        guard !operand.isEmpty else {
            return .malformedRequire("Shader #require has no module identifier.")
        }
        if let identifier = identifierOnly(operand) {
            return .require(identifier)
        }
        let name = operand.prefix { $0 == "_" || $0.isLetter || $0.isNumber }
        if identifierOnly(String(name)) != nil {
            return .malformedRequire("Shader #require has extra tokens.")
        }
        return .malformedRequire("Shader #require has an invalid module identifier.")
    }

    private static func identifierOnly(_ text: String) -> String? {
        guard let first = text.first, first == "_" || first.isLetter,
              text.dropFirst().allSatisfy({
                  $0 == "_" || $0.isLetter || $0.isNumber
              }) else { return nil }
        return text
    }

    func metadataIsActive(
        currentActive: Bool,
        closingParentActive: Bool?
    ) -> Bool {
        switch self {
        case .elifExpression, .elseDirective, .endif:
            closingParentActive ?? currentActive
        default: currentActive
        }
    }
}

extension SceneShaderPreprocessor {
    nonisolated struct Limits: Codable, Equatable, Sendable {
        let maximumIncludeDepth: Int
        let maximumDependencies: Int
        let maximumInputBytes: Int
        let maximumOutputBytes: Int
        let maximumOutputLines: Int
        let maximumExpressionTokens: Int
        let maximumFunctionMacroParameters: Int
        let maximumMacroExpansionDepth: Int
        let maximumMacroExpansionTokens: Int
        let maximumMacroExpansionBytes: Int

        static let `default` = Limits(
            maximumIncludeDepth: 32,
            maximumDependencies: 256,
            maximumInputBytes: 2 * 1_024 * 1_024,
            maximumOutputBytes: 2 * 1_024 * 1_024,
            maximumOutputLines: 100_000,
            maximumExpressionTokens: 512,
            maximumFunctionMacroParameters: 16,
            maximumMacroExpansionDepth: 32,
            maximumMacroExpansionTokens: 16_384,
            maximumMacroExpansionBytes: 1_024 * 1_024
        )
    }

    nonisolated struct ConditionalFrame {
        let parentActive: Bool
        var branchWasTrue: Bool
        var isActive: Bool
        var sawElse: Bool
    }
}

extension SceneShaderPreprocessor {
    nonisolated struct PreparedDigestPayload: Encodable {
        let frontendSchemaVersion: Int
        let sourceDialect: SceneShaderSourceDialect
        let backend: SceneShaderBackendIdentity
        let stage: SceneShaderContract.StageKind
        let rootRelativePath: String
        let source: String
        let sourceMap: [SceneShaderSourceMapEntry]
        let activeAnnotations: [SceneShaderActiveAnnotation]
        let activeDeclarations: [SceneShaderActiveDeclaration]
        let dependencySHA256: String
        let moduleDependencies: [SceneShaderModuleDependency]
        let moduleDependencySHA256: String
        let variantSHA256: String
    }

    nonisolated enum DiagnosticCode: String, Codable, Equatable, Sendable {
        case missingRoot = "missing-root", sourceIdentityMismatch = "source-identity-mismatch"
        case malformedDirective = "malformed-directive", unsupportedDirective = "unsupported-directive"
        case unknownDirective = "unknown-directive", functionLikeMacro = "function-like-macro"
        case moduleDirectiveSyntax = "module-directive-syntax"
        case moduleUnknown = "module-unknown"
        case moduleCaseMismatch = "module-case-mismatch"
        case moduleLightingNonzero = "module-lighting-nonzero"
        case moduleLightingMacroMissing = "module-lighting-macro-missing"
        case moduleLightingMacroNoninteger = "module-lighting-macro-noninteger"
        case conflictingMacro = "conflicting-macro", invalidExpression = "invalid-expression"
        case unresolvedEnvironmentDefine = "unresolved-environment-define"
        case malformedSourceAnnotation = "malformed-source-annotation"
        case missingInclude = "missing-include", ambiguousInclude = "ambiguous-include"
        case rejectedInclude = "rejected-include", includeCycle = "include-cycle"
        case budgetExceeded = "budget-exceeded", unmatchedElse = "unmatched-else"
        case duplicateElse = "duplicate-else", unmatchedEndif = "unmatched-endif"
        case unmatchedElif = "unmatched-elif", elifAfterElse = "elif-after-else"
        case unterminatedConditional = "unterminated-conditional"
        case unterminatedBlockComment = "unterminated-block-comment"
        case unsupportedAnnotationPlacement = "unsupported-annotation-placement"
    }

    nonisolated struct Diagnostic: Codable, Equatable, Sendable {
        let code: DiagnosticCode
        let message: String
        let relativePath: String
        let line: Int?
    }

    nonisolated struct Failure: Error, Codable, Equatable, Sendable {
        let diagnostics: [Diagnostic]
    }

    nonisolated struct ExpressionError: Error { let message: String }

    nonisolated enum ExpressionToken: Equatable {
        case number(Int64), identifier(String)
        case not, and, or, equal, notEqual, less, lessEqual, greater, greaterEqual
        case leftParen, rightParen, end
    }

    nonisolated enum ExpressionLexer {
        static func tokenize(_ input: String, limit: Int) throws -> [ExpressionToken] {
            var tokens: [ExpressionToken] = []
            var index = input.startIndex
            func append(_ token: ExpressionToken) throws {
                tokens.append(token)
                if tokens.count > limit {
                    throw ExpressionError(message: "Shader condition exceeds its token budget.")
                }
            }
            while index < input.endIndex {
                if input[index].isWhitespace { index = input.index(after: index); continue }
                let pair = String(input[index...].prefix(2))
                let paired: [String: ExpressionToken] = [
                    "&&": .and, "||": .or, "==": .equal, "!=": .notEqual,
                    "<=": .lessEqual, ">=": .greaterEqual
                ]
                if let token = paired[pair] {
                    try append(token); index = input.index(index, offsetBy: 2); continue
                }
                let character = input[index]
                if character == "!" { try append(.not); index = input.index(after: index); continue }
                if character == "<" { try append(.less); index = input.index(after: index); continue }
                if character == ">" { try append(.greater); index = input.index(after: index); continue }
                if character == "(" { try append(.leftParen); index = input.index(after: index); continue }
                if character == ")" { try append(.rightParen); index = input.index(after: index); continue }
                if character.isNumber || (character == "-" && input.index(after: index) < input.endIndex
                    && input[input.index(after: index)].isNumber) {
                    let start = index
                    index = input.index(after: index)
                    while index < input.endIndex, input[index].isNumber { index = input.index(after: index) }
                    guard let value = Int64(input[start..<index]) else {
                        throw ExpressionError(message: "Invalid integer in shader condition.")
                    }
                    try append(.number(value)); continue
                }
                if character == "_" || character.isLetter {
                    let start = index
                    index = input.index(after: index)
                    while index < input.endIndex,
                          input[index] == "_" || input[index].isLetter || input[index].isNumber {
                        index = input.index(after: index)
                    }
                    try append(.identifier(String(input[start..<index]))); continue
                }
                throw ExpressionError(message: "Unsupported token in shader condition.")
            }
            tokens.append(.end)
            return tokens
        }
    }

    nonisolated struct ExpressionParser {
        let tokens: [ExpressionToken]
        let macros: [String: SceneShaderMacroValue]
        let definedNames: Set<String>
        var index = 0

        mutating func parse() throws -> Int64 {
            let value = try parseOr()
            guard peek == .end else {
                throw ExpressionError(message: "Unexpected trailing shader condition token.")
            }
            return value
        }

        mutating func parseOr() throws -> Int64 {
            var value = try parseAnd()
            while consume(.or) {
                let right = try parseAnd()
                value = value != 0 || right != 0 ? 1 : 0
            }
            return value
        }

        mutating func parseAnd() throws -> Int64 {
            var value = try parseEquality()
            while consume(.and) {
                let right = try parseEquality()
                value = value != 0 && right != 0 ? 1 : 0
            }
            return value
        }

        mutating func parseEquality() throws -> Int64 {
            var value = try parseRelational()
            while [.equal, .notEqual].contains(peek) {
                let operation = peek
                index += 1
                let right = try parseRelational()
                switch operation {
                case .equal: value = value == right ? 1 : 0
                case .notEqual: value = value != right ? 1 : 0
                default: break
                }
            }
            return value
        }

        mutating func parseRelational() throws -> Int64 {
            var value = try parseUnary()
            while [.less, .lessEqual, .greater, .greaterEqual].contains(peek) {
                let operation = peek
                index += 1
                let right = try parseUnary()
                switch operation {
                case .less: value = value < right ? 1 : 0
                case .lessEqual: value = value <= right ? 1 : 0
                case .greater: value = value > right ? 1 : 0
                case .greaterEqual: value = value >= right ? 1 : 0
                default: break
                }
            }
            return value
        }

        mutating func parseUnary() throws -> Int64 {
            if consume(.not) { return try parseUnary() == 0 ? 1 : 0 }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> Int64 {
            switch peek {
            case let .number(value): index += 1; return value
            case let .identifier(name):
                index += 1
                if name == "defined" {
                    let parenthesized = consume(.leftParen)
                    guard case let .identifier(identifier) = peek else {
                        throw ExpressionError(message: "defined requires an identifier.")
                    }
                    index += 1
                    if parenthesized, !consume(.rightParen) {
                        throw ExpressionError(message: "defined is missing a closing parenthesis.")
                    }
                    return definedNames.contains(identifier) ? 1 : 0
                }
                guard let macro = macros[name] else { return 0 }
                guard let value = macro.expressionValue else {
                    throw ExpressionError(message: "Non-integer macro '\(name)' is invalid in a shader condition.")
                }
                return value
            case .leftParen:
                index += 1
                let value = try parseOr()
                guard consume(.rightParen) else {
                    throw ExpressionError(message: "Shader condition is missing a closing parenthesis.")
                }
                return value
            default: throw ExpressionError(message: "Shader condition expects a value.")
            }
        }

        var peek: ExpressionToken { tokens[index] }

        mutating func consume(_ token: ExpressionToken) -> Bool {
            guard peek == token else { return false }
            index += 1
            return true
        }
    }
}

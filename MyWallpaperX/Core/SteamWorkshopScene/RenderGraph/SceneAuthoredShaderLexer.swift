import Foundation

nonisolated enum SceneAuthoredShaderLexer {
    struct Output {
        let tokens: [SceneAuthoredShaderToken]
        let defines: [String: String]
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private static let maximumSourceBytes = 512 * 1_024
    private static let maximumTokenCount = 100_000
    private static let twoCharacterSymbols: Set<String> = [
        "++", "--", "+=", "-=", "*=", "/=", "%=", "==", "!=",
        "<=", ">=", "&&", "||", "<<", ">>", "&=", "|=", "^=",
    ]

    static func lex(
        source: String,
        stage: SceneShaderContract.StageKind
    ) -> Output {
        guard source.utf8.count <= maximumSourceBytes else {
            return failure(
                .sourceTooLarge,
                "Shader source exceeds the 512 KiB frontend limit.",
                stage: stage
            )
        }
        let normalizedSource = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let directiveResult = extractDirectives(source: normalizedSource, stage: stage)
        guard directiveResult.diagnostics.isEmpty else {
            return Output(
                tokens: [],
                defines: directiveResult.defines,
                diagnostics: directiveResult.diagnostics
            )
        }
        return tokenize(
            directiveResult.source,
            defines: directiveResult.defines,
            stage: stage
        )
    }

    private struct DirectiveOutput {
        let source: String
        let defines: [String: String]
        let diagnostics: [SceneAuthoredShaderFrontendDiagnostic]
    }

    private static func extractDirectives(
        source: String,
        stage: SceneShaderContract.StageKind
    ) -> DirectiveOutput {
        var defines: [String: String] = [:]
        var diagnostics: [SceneAuthoredShaderFrontendDiagnostic] = []
        var body: [String] = []
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        for (offset, rawLine) in lines.enumerated() {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else {
                body.append(line)
                continue
            }
            let components = trimmed.split(
                maxSplits: 2,
                omittingEmptySubsequences: true,
                whereSeparator: { $0.isWhitespace }
            )
            guard components.first == "#define", components.count == 3 else {
                diagnostics.append(.init(
                    code: .unsupportedDirective,
                    message: "Only object-like numeric #define directives are supported.",
                    stage: stage,
                    line: offset + 1,
                    column: 1
                ))
                body.append("")
                continue
            }
            let name = String(components[1])
            let value = String(components[2]).trimmingCharacters(in: .whitespaces)
            guard isIdentifier(name), numericLiteral(value) != nil else {
                diagnostics.append(.init(
                    code: .malformedDefine,
                    message: "Shader #define must have an identifier and numeric value.",
                    stage: stage,
                    line: offset + 1,
                    column: 1
                ))
                body.append("")
                continue
            }
            if defines.updateValue(value, forKey: name) != nil {
                diagnostics.append(.init(
                    code: .malformedDefine,
                    message: "Shader #define '\(name)' is duplicated.",
                    stage: stage,
                    line: offset + 1,
                    column: 1
                ))
            }
            body.append("")
        }
        return DirectiveOutput(
            source: body.joined(separator: "\n"),
            defines: defines,
            diagnostics: diagnostics
        )
    }

    private static func tokenize(
        _ source: String,
        defines: [String: String],
        stage: SceneShaderContract.StageKind
    ) -> Output {
        let scalars = Array(source.unicodeScalars)
        var tokens: [SceneAuthoredShaderToken] = []
        var diagnostics: [SceneAuthoredShaderFrontendDiagnostic] = []
        var index = 0
        var line = 1
        var column = 1

        func append(_ kind: SceneAuthoredShaderToken.Kind, _ text: String, _ at: Int) {
            tokens.append(.init(kind: kind, text: text, line: line, column: at))
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\n" {
                line += 1
                column = 1
                index += 1
                continue
            }
            if CharacterSet.whitespaces.contains(scalar) {
                column += 1
                index += 1
                continue
            }
            if scalar == "/", index + 1 < scalars.count {
                if scalars[index + 1] == "/" {
                    while index < scalars.count, scalars[index] != "\n" {
                        index += 1
                        column += 1
                    }
                    continue
                }
                if scalars[index + 1] == "*" {
                    let startLine = line
                    let startColumn = column
                    index += 2
                    column += 2
                    var terminated = false
                    while index < scalars.count {
                        if scalars[index] == "\n" {
                            line += 1
                            column = 1
                            index += 1
                        } else if scalars[index] == "*", index + 1 < scalars.count,
                                  scalars[index + 1] == "/" {
                            index += 2
                            column += 2
                            terminated = true
                            break
                        } else {
                            index += 1
                            column += 1
                        }
                    }
                    if !terminated {
                        diagnostics.append(.init(
                            code: .unterminatedComment,
                            message: "Shader block comment is not terminated.",
                            stage: stage,
                            line: startLine,
                            column: startColumn
                        ))
                    }
                    continue
                }
            }
            if isIdentifierStart(scalar) {
                let start = index
                let startColumn = column
                while index < scalars.count, isIdentifierContinue(scalars[index]) {
                    index += 1
                    column += 1
                }
                append(.identifier, String(String.UnicodeScalarView(scalars[start..<index])), startColumn)
                continue
            }
            if isNumberStart(scalar, next: index + 1 < scalars.count ? scalars[index + 1] : nil) {
                let start = index
                let startColumn = column
                index = consumeNumber(scalars, from: index)
                column += index - start
                append(.number, String(String.UnicodeScalarView(scalars[start..<index])), startColumn)
                continue
            }
            let startColumn = column
            if index + 1 < scalars.count {
                let pair = String(String.UnicodeScalarView(scalars[index...index + 1]))
                if twoCharacterSymbols.contains(pair) {
                    append(.symbol, pair, startColumn)
                    index += 2
                    column += 2
                    continue
                }
            }
            let text = String(scalar)
            if "{}()[];,.?:+-*/%<>=!&|^~".contains(text) {
                append(.symbol, text, startColumn)
            } else {
                diagnostics.append(.init(
                    code: .invalidToken,
                    message: "Unsupported shader token '\(text)'.",
                    stage: stage,
                    line: line,
                    column: startColumn
                ))
            }
            index += 1
            column += 1
            if tokens.count > maximumTokenCount {
                return failure(
                    .tokenBudgetExceeded,
                    "Shader exceeds the 100,000-token frontend limit.",
                    stage: stage
                )
            }
        }
        return Output(tokens: tokens, defines: defines, diagnostics: diagnostics)
    }

    private static func failure(
        _ code: SceneAuthoredShaderFrontendDiagnostic.Code,
        _ message: String,
        stage: SceneShaderContract.StageKind
    ) -> Output {
        Output(
            tokens: [],
            defines: [:],
            diagnostics: [.init(
                code: code,
                message: message,
                stage: stage,
                line: nil,
                column: nil
            )]
        )
    }

    private static func isIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, isIdentifierStart(first) else { return false }
        return value.unicodeScalars.dropFirst().allSatisfy(isIdentifierContinue)
    }

    private static func isIdentifierStart(_ scalar: UnicodeScalar) -> Bool {
        scalar == "_" || CharacterSet.letters.contains(scalar)
    }

    private static func isIdentifierContinue(_ scalar: UnicodeScalar) -> Bool {
        isIdentifierStart(scalar) || CharacterSet.decimalDigits.contains(scalar)
    }

    private static func isNumberStart(_ scalar: UnicodeScalar, next: UnicodeScalar?) -> Bool {
        CharacterSet.decimalDigits.contains(scalar)
            || (scalar == "." && next.map(CharacterSet.decimalDigits.contains) == true)
    }

    private static func consumeNumber(_ scalars: [UnicodeScalar], from start: Int) -> Int {
        var index = start
        var allowsSign = false
        while index < scalars.count {
            let scalar = scalars[index]
            if CharacterSet.decimalDigits.contains(scalar) || scalar == "." {
                allowsSign = false
                index += 1
            } else if scalar == "e" || scalar == "E" {
                allowsSign = true
                index += 1
            } else if allowsSign && (scalar == "+" || scalar == "-") {
                allowsSign = false
                index += 1
            } else if scalar == "f" || scalar == "F" || scalar == "u" || scalar == "U" {
                index += 1
                break
            } else {
                break
            }
        }
        return index
    }

    private static func numericLiteral(_ value: String) -> Double? {
        let suffixes = CharacterSet(charactersIn: "fFuU")
        return Double(value.trimmingCharacters(in: suffixes))
    }
}

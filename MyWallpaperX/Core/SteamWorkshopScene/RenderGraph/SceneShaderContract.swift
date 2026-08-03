import Foundation

nonisolated struct SceneShaderContract: Codable, Equatable, Sendable {
    enum SourceKind: String, Codable, Equatable, Sendable {
        case authoredSource
        case hostBuiltin
    }

    enum StageKind: String, Codable, Equatable, Sendable {
        case vertex
        case fragment
    }

    enum DeclarationKind: String, Codable, Equatable, Sendable {
        case uniform
        case attribute
        case varying
    }

    enum DiagnosticCode: String, Codable, Equatable, Sendable {
        case duplicateIdentity
        case invalidReference
        case pathEscape
        case symlinkEscape
        case missingVertexStage
        case missingFragmentStage
        case unreadableSource
        case invalidUTF8
        case malformedAnnotation
        case unterminatedBlockComment
    }

    struct Include: Codable, Equatable, Sendable {
        let relativePath: String
        let raw: String
        let line: Int
    }

    struct Annotation: Codable, Equatable, Sendable {
        let marker: String?
        let value: SceneJSONValue
        /// Exact numeric view used by the R2 variant compiler. `value` remains
        /// the legacy projection encoded into `canonicalSHA256`.
        let variantValue: SceneShaderAnnotationValue
        let raw: String
        let line: Int

        private enum CodingKeys: String, CodingKey {
            case marker, value, raw, line
        }

        init(
            marker: String?,
            value: SceneJSONValue,
            variantValue: SceneShaderAnnotationValue? = nil,
            raw: String,
            line: Int
        ) {
            self.marker = marker
            self.value = value
            self.variantValue = variantValue ?? .init(legacyValue: value)
            self.raw = raw
            self.line = line
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            marker = try container.decodeIfPresent(String.self, forKey: .marker)
            value = try container.decode(SceneJSONValue.self, forKey: .value)
            raw = try container.decode(String.self, forKey: .raw)
            line = try container.decode(Int.self, forKey: .line)
            variantValue = SceneShaderAnnotationValue(
                rawAnnotation: raw,
                marker: marker
            ) ?? .init(legacyValue: value)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(marker, forKey: .marker)
            try container.encode(value, forKey: .value)
            try container.encode(raw, forKey: .raw)
            try container.encode(line, forKey: .line)
        }
    }

    struct Declaration: Codable, Equatable, Sendable {
        let kind: DeclarationKind
        let type: String
        let name: String
        let arraySuffix: String?
        let arraySize: Int?
        let raw: String
        let line: Int
    }

    struct Stage: Codable, Equatable, Sendable {
        let kind: StageKind
        let relativePath: String
        let source: String
        let rawSHA256: String
        let includes: [Include]
        let annotations: [Annotation]
        let declarations: [Declaration]
    }

    struct Diagnostic: Codable, Equatable, Sendable {
        let code: DiagnosticCode
        let message: String
        let relativePath: String?
        let line: Int?
    }

    let identity: String
    let sourceKind: SourceKind
    let stages: [Stage]
    let diagnostics: [Diagnostic]
    let canonicalSHA256: String
    /// Deterministic VFS snapshot for authored stage/include preparation. It is
    /// intentionally separate from `canonicalSHA256`, whose legacy root-stage
    /// identity remains the compatibility key used by existing strict profiles.
    let sourceGraph: SceneShaderSourceGraph?

    init(
        identity: String,
        sourceKind: SourceKind,
        stages: [Stage],
        diagnostics: [Diagnostic],
        canonicalSHA256: String,
        sourceGraph: SceneShaderSourceGraph? = nil
    ) {
        self.identity = identity
        self.sourceKind = sourceKind
        self.stages = stages
        self.diagnostics = diagnostics
        self.canonicalSHA256 = canonicalSHA256
        self.sourceGraph = sourceGraph
    }
}

/// Loss-preserving JSON view for shader annotations. Foundation can decode an
/// authored Int64 exactly even when it cannot be represented by `Double`.
nonisolated indirect enum SceneShaderAnnotationValue: Decodable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([SceneShaderAnnotationValue])
    case object([String: SceneShaderAnnotationValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Decimal.self) {
            let number = NSDecimalNumber(decimal: value)
            if let integer = Int64(number.stringValue) {
                self = .integer(integer)
            } else {
                self = .number(number.doubleValue)
            }
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SceneShaderAnnotationValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SceneShaderAnnotationValue].self))
        }
    }

    init(legacyValue: SceneJSONValue) {
        switch legacyValue {
        case .null: self = .null
        case .bool(let value): self = .bool(value)
        case .number(let value):
            self = abs(value) <= 9_007_199_254_740_991
                ? Int64(exactly: value).map(Self.integer) ?? .number(value)
                : .number(value)
        case .string(let value): self = .string(value)
        case .array(let values): self = .array(values.map(Self.init(legacyValue:)))
        case .object(let values):
            self = .object(values.mapValues(Self.init(legacyValue:)))
        }
    }

    init?(rawAnnotation: String, marker: String?) {
        guard rawAnnotation.hasPrefix("//") else { return nil }
        let body = String(rawAnnotation.dropFirst(2))
        let payload: String
        if let marker, let range = body.range(of: marker) {
            payload = String(body[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if marker.caseInsensitiveCompare("[PASS]") == .orderedSame {
                self = .string(payload)
                return
            }
        } else {
            payload = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = decoded
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var integerValue: Int64? {
        switch self {
        case .integer(let value): return value
        case .number(let value):
            guard value.isFinite,
                  abs(value) <= 9_007_199_254_740_991 else { return nil }
            return Int64(exactly: value)
        default: return nil
        }
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

nonisolated struct SceneShaderContractSourceParser {
    struct Result {
        let includes: [SceneShaderContract.Include]
        let annotations: [SceneShaderContract.Annotation]
        let declarations: [SceneShaderContract.Declaration]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated func parse(
        _ source: String,
        stageRelativePath: String
    ) -> Result {
        let includePattern = try? NSRegularExpression(
            pattern: #"^\s*#\s*include\s*[\"<]([^\">]+)[\">]"#
        )
        let declarationPattern = try? NSRegularExpression(
            pattern: #"^\s*(uniform|attribute|varying)\s+((?:(?:lowp|mediump|highp)\s+)?[A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(\[[^\]\r\n]*\])?\s*;"#,
            options: [.caseInsensitive]
        )
        let markerPattern = try? NSRegularExpression(
            pattern: #"(\[(?:COMBO_DISABLED|COMBO_OFF|COMBO|OFF_COMBO|PASS)\]|\bOFF_COMBO\b)"#,
            options: [.caseInsensitive]
        )

        var includes: [SceneShaderContract.Include] = []
        var annotations: [SceneShaderContract.Annotation] = []
        var declarations: [SceneShaderContract.Declaration] = []
        var diagnostics: [SceneShaderContract.Diagnostic] = []
        var inBlockComment = false

        for (offset, substring) in source.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        ).enumerated() {
            let lineNumber = offset + 1
            let line = String(substring)
            let lexical = SceneShaderLexicalScanner.scan(
                line,
                inBlockComment: &inBlockComment
            )
            let code = lexical.code

            if let match = firstMatch(includePattern, in: code),
               let path = capture(1, match: match, in: code) {
                includes.append(.init(relativePath: path, raw: line, line: lineNumber))
            }

            let declarationMatch = firstMatch(declarationPattern, in: code)
            if let match = declarationMatch,
               let kindRaw = capture(1, match: match, in: code)?.lowercased(),
               let kind = SceneShaderContract.DeclarationKind(rawValue: kindRaw),
               let type = capture(2, match: match, in: code),
               let name = capture(3, match: match, in: code) {
                let arraySuffix = capture(4, match: match, in: code)
                declarations.append(.init(
                    kind: kind,
                    type: type,
                    name: name,
                    arraySuffix: arraySuffix,
                    arraySize: arraySize(arraySuffix),
                    raw: code,
                    line: lineNumber
                ))
            }

            guard let raw = lexical.lineCommentRaw else { continue }
            let body = String(raw.dropFirst(2))
            let markerMatch = firstMatch(markerPattern, in: body)
            let marker = markerMatch.flatMap { capture(1, match: $0, in: body) }
            let jsonText: String?
            if let markerMatch,
               let markerRange = Range(markerMatch.range, in: body) {
                jsonText = String(body[markerRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                jsonText = declarationMatch != nil
                    && (trimmed.hasPrefix("{") || trimmed.hasPrefix("["))
                    ? trimmed
                    : nil
            }
            guard let jsonText else { continue }
            // [PASS] declares an additional pass as `<pass> <shader>`, not JSON. Keep the
            // operand verbatim instead of reporting the stock annotation as malformed.
            if !jsonText.isEmpty,
               let marker,
               marker.caseInsensitiveCompare("[PASS]") == .orderedSame {
                annotations.append(.init(
                    marker: marker,
                    value: .string(jsonText),
                    variantValue: .string(jsonText),
                    raw: raw,
                    line: lineNumber
                ))
                continue
            }
            guard !jsonText.isEmpty,
                  let jsonData = jsonText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(
                    with: jsonData,
                    options: [.fragmentsAllowed]
                  ),
                  let value = SceneJSONValue(jsonObject: object),
                  let variantValue = try? JSONDecoder().decode(
                    SceneShaderAnnotationValue.self,
                    from: jsonData
                  ) else {
                diagnostics.append(.init(
                    code: .malformedAnnotation,
                    message: "Shader annotation contains malformed JSON.",
                    relativePath: stageRelativePath,
                    line: lineNumber
                ))
                continue
            }
            annotations.append(.init(
                marker: marker,
                value: value,
                variantValue: variantValue,
                raw: raw,
                line: lineNumber
            ))
        }
        if inBlockComment {
            diagnostics.append(.init(
                code: .unterminatedBlockComment,
                message: "Shader source ends inside a block comment.",
                relativePath: stageRelativePath,
                line: nil
            ))
        }
        return Result(
            includes: includes,
            annotations: annotations,
            declarations: declarations,
            diagnostics: diagnostics
        )
    }

    nonisolated private func firstMatch(
        _ expression: NSRegularExpression?,
        in string: String
    ) -> NSTextCheckingResult? {
        expression?.firstMatch(
            in: string,
            range: NSRange(string.startIndex..., in: string)
        )
    }

    nonisolated private func capture(
        _ index: Int,
        match: NSTextCheckingResult,
        in string: String
    ) -> String? {
        guard match.numberOfRanges > index,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: string) else { return nil }
        return String(string[range])
    }

    nonisolated private func arraySize(_ suffix: String?) -> Int? {
        guard let suffix, suffix.count >= 2 else { return nil }
        return Int(suffix.dropFirst().dropLast().trimmingCharacters(in: .whitespaces))
    }
}

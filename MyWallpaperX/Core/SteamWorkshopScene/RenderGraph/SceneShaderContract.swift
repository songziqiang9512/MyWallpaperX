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
    }

    struct Include: Codable, Equatable, Sendable {
        let relativePath: String
        let raw: String
        let line: Int
    }

    struct Annotation: Codable, Equatable, Sendable {
        let marker: String?
        let value: SceneJSONValue
        let raw: String
        let line: Int
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

        for (offset, substring) in source.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        ).enumerated() {
            let lineNumber = offset + 1
            let line = String(substring)
            let code = line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line

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

            guard let commentRange = line.range(of: "//") else { continue }
            let raw = String(line[commentRange.lowerBound...])
            let body = String(line[commentRange.upperBound...])
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
                  let value = SceneJSONValue(jsonObject: object) else {
                diagnostics.append(.init(
                    code: .malformedAnnotation,
                    message: "Shader annotation contains malformed JSON.",
                    relativePath: stageRelativePath,
                    line: lineNumber
                ))
                continue
            }
            annotations.append(.init(marker: marker, value: value, raw: raw, line: lineNumber))
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

nonisolated enum SceneShaderContractPath {
    nonisolated static func normalizedRelativePath(
        base: String,
        path: String
    ) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.hasPrefix("/"), !hasDrivePrefix(normalized) else { return nil }

        var components = base.split(separator: "/").map(String.init)
        for component in normalized.split(separator: "/", omittingEmptySubsequences: false) {
            switch component {
            case "", ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }
        return components.isEmpty ? nil : components.joined(separator: "/")
    }

    nonisolated private static func hasDrivePrefix(_ path: String) -> Bool {
        guard path.count >= 2 else { return false }
        let start = path.startIndex
        let next = path.index(after: start)
        return path[start].isLetter && path[next] == ":"
    }
}

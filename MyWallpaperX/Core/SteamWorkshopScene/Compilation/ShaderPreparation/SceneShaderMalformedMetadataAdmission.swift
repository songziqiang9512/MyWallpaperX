import Foundation

/// Proves that a malformed COMBO line is a redundant editor record without
/// treating its invalid option keys as supported annotation syntax.
nonisolated enum SceneShaderMalformedMetadataAdmission {
    private struct Signature: Equatable {
        let name: String
        let outerFields: [String: SceneShaderAnnotationValue]
    }

    static func allowsDiagnostics(in contract: SceneShaderContract) -> Bool {
        let valid = contract.stages.flatMap {
            unconditionalSignatures(source: $0.source, path: $0.relativePath)
        }
        return contract.diagnostics.allSatisfy { diagnostic in
            guard diagnostic.code == .malformedAnnotation,
                  let path = diagnostic.relativePath,
                  let line = diagnostic.line else { return false }
            let stages = contract.stages.filter {
                $0.relativePath.caseInsensitiveCompare(path) == .orderedSame
            }
            guard stages.count == 1,
                  let sourceLine = sourceLine(line, in: stages[0].source),
                  let candidate = malformedSignature(in: sourceLine)
            else { return false }
            return valid.contains(candidate)
        }
    }

    static func canSkip(
        _ diagnostic: SceneShaderContract.Diagnostic,
        in graph: SceneShaderSourceGraph
    ) -> Bool {
        guard diagnostic.code == .malformedAnnotation,
              let path = diagnostic.relativePath,
              let line = diagnostic.line,
              let node = graph.node(at: path),
              let sourceLine = sourceLine(line, in: node.source),
              let candidate = malformedSignature(in: sourceLine)
        else { return false }
        let valid = graph.roots.compactMap { graph.node(at: $0.virtualPath) }
            .flatMap {
                unconditionalSignatures(source: $0.source, path: $0.virtualPath)
            }
        return valid.contains(candidate)
    }

    private static func unconditionalSignatures(
        source: String,
        path: String
    ) -> [Signature] {
        let parsed = SceneShaderContractSourceParser().parse(
            source,
            stageRelativePath: path
        )
        let annotations = Dictionary(grouping: parsed.annotations, by: \.line)
        let lines = source.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        )
        var result: [Signature] = []
        var conditionalDepth = 0
        var inBlockComment = false
        for (offset, substring) in lines.enumerated() {
            let lexical = SceneShaderLexicalScanner.scan(
                String(substring),
                inBlockComment: &inBlockComment
            )
            switch conditionalDirective(lexical.code) {
            case .open:
                conditionalDepth += 1
                continue
            case .branch:
                guard conditionalDepth > 0 else { return [] }
                continue
            case .close:
                guard conditionalDepth > 0 else { return [] }
                conditionalDepth -= 1
                continue
            case .other:
                continue
            case nil:
                break
            }
            guard conditionalDepth == 0 else { continue }
            result += (annotations[offset + 1] ?? []).compactMap(signature)
        }
        return conditionalDepth == 0 ? result : []
    }

    private enum ConditionalDirective { case open, branch, close, other }

    private static func conditionalDirective(_ code: String) -> ConditionalDirective? {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let body = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
        let name = body.prefix { $0 == "_" || $0.isLetter || $0.isNumber }
        switch name {
        case "if", "ifdef", "ifndef": return .open
        case "elif", "else": return .branch
        case "endif": return .close
        default: return .other
        }
    }

    private static func signature(
        _ annotation: SceneShaderContract.Annotation
    ) -> Signature? {
        guard annotation.marker?.caseInsensitiveCompare("[COMBO]") == .orderedSame,
              case var .object(object) = annotation.variantValue,
              object.removeValue(forKey: "options") != nil,
              let name = object["combo"]?.stringValue,
              validIdentifier(name) else { return nil }
        return .init(name: name, outerFields: object)
    }

    private static func malformedSignature(in line: String) -> Signature? {
        var inBlockComment = false
        let lexical = SceneShaderLexicalScanner.scan(
            line,
            inBlockComment: &inBlockComment
        )
        guard lexical.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let raw = lexical.lineCommentRaw else { return nil }
        let body = String(raw.dropFirst(2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = "[COMBO]"
        guard body.hasPrefix(marker),
              let fields = fieldsIgnoringMalformedOptions(
                  in: body.dropFirst(marker.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
              ) else { return nil }
        var outer: [String: SceneShaderAnnotationValue] = [:]
        for (key, value) in fields where key != "options" {
            guard let data = String(value).data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(
                      SceneShaderAnnotationValue.self,
                      from: data
                  ) else { return nil }
            outer[key] = decoded
        }
        guard let name = outer["combo"]?.stringValue,
              validIdentifier(name) else { return nil }
        return .init(name: name, outerFields: outer)
    }

    private static func fieldsIgnoringMalformedOptions(
        in payload: String
    ) -> [String: Substring]? {
        guard payload.utf8.count <= 16_384,
              let expression = try? NSRegularExpression(
                  pattern: #""options"\s*:\s*\{[^{}\[\]\r\n]*\}"#
              ) else { return nil }
        let range = NSRange(payload.startIndex..., in: payload)
        let matches = expression.matches(in: payload, range: range)
        guard matches.count == 1 else { return nil }
        let sanitized = (payload as NSString).replacingCharacters(
            in: matches[0].range,
            with: #""options":__MWX_MALFORMED_OPTIONS__"#
        )
        guard let fields = topLevelFields(in: sanitized),
              fields["options"]?.trimmingCharacters(in: .whitespaces)
                == "__MWX_MALFORMED_OPTIONS__"
        else { return nil }
        return fields
    }

    private static func topLevelFields(
        in payload: String
    ) -> [String: Substring]? {
        let value = payload[...]
        guard value.first == "{", value.last == "}" else { return nil }
        let content = value.index(after: value.startIndex)..<value.index(before: value.endIndex)
        guard let fields = splitTopLevel(value[content], separator: ",") else { return nil }
        var result: [String: Substring] = [:]
        for field in fields {
            guard let colon = topLevelColon(in: field) else { return nil }
            let keyText = field[..<colon].trimmingCharacters(in: .whitespaces)
            let rawValue = field[field.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            guard !rawValue.isEmpty,
                  let keyData = keyText.data(using: .utf8),
                  let key = try? JSONDecoder().decode(String.self, from: keyData),
                  result.updateValue(rawValue[...], forKey: key) == nil else { return nil }
        }
        return result
    }

    private static func splitTopLevel(
        _ value: Substring,
        separator: Character
    ) -> [Substring]? {
        var result: [Substring] = []
        var start = value.startIndex
        var braces = 0
        var brackets = 0
        var quote: Character?
        var escaped = false
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            if let activeQuote = quote {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == activeQuote { quote = nil }
            } else {
                switch character {
                case "\"": quote = character
                case "{": braces += 1
                case "}": braces -= 1
                case "[": brackets += 1
                case "]": brackets -= 1
                case separator where braces == 0 && brackets == 0:
                    result.append(value[start..<index])
                    start = value.index(after: index)
                default: break
                }
                guard braces >= 0, brackets >= 0 else { return nil }
            }
            index = value.index(after: index)
        }
        guard quote == nil, braces == 0, brackets == 0 else { return nil }
        result.append(value[start..<value.endIndex])
        return result
    }

    private static func topLevelColon(in value: Substring) -> Substring.Index? {
        splitTopLevel(value, separator: ":")?.count == 2
            ? value.firstIndex(of: ":") : nil
    }

    private static func sourceLine(_ line: Int, in source: String) -> String? {
        guard line > 0 else { return nil }
        let lines = source.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        )
        guard line <= lines.count else { return nil }
        return String(lines[line - 1])
    }

    private static func validIdentifier(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard !scalars.isEmpty, scalars.count <= 64 else { return false }
        func letterOrUnderscore(_ scalar: Unicode.Scalar) -> Bool {
            scalar == "_" || (65 ... 90).contains(scalar.value)
                || (97 ... 122).contains(scalar.value)
        }
        guard letterOrUnderscore(scalars[0]) else { return false }
        return scalars.dropFirst().allSatisfy {
            letterOrUnderscore($0) || (48 ... 57).contains($0.value)
        }
    }
}

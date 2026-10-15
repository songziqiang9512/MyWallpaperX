import Foundation

/// Discards only a failed, comment-only COMBO metadata record. Source,
/// declarations and diagnostics stay intact; no partial fields become values.
nonisolated enum SceneShaderMalformedMetadataAdmission {
    static func allowsDiagnostics(in contract: SceneShaderContract) -> Bool {
        contract.diagnostics.allSatisfy { diagnostic in
            guard let path = diagnostic.relativePath else { return false }
            let stages = contract.stages.filter {
                $0.relativePath.caseInsensitiveCompare(path) == .orderedSame
            }
            return stages.count == 1 && canSkip(diagnostic, source: stages[0].source)
        }
    }

    static func canSkip(
        _ diagnostic: SceneShaderContract.Diagnostic,
        in graph: SceneShaderSourceGraph
    ) -> Bool {
        guard let path = diagnostic.relativePath,
              let node = graph.node(at: path) else { return false }
        return canSkip(diagnostic, source: node.source)
    }

    private static func canSkip(
        _ diagnostic: SceneShaderContract.Diagnostic,
        source: String
    ) -> Bool {
        guard diagnostic.code == .malformedAnnotation,
              let line = diagnostic.line, line > 0 else { return false }
        var inBlockComment = false
        for (offset, substring) in source.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0.isNewline }
        ).enumerated() {
            let lexical = SceneShaderLexicalScanner.scan(
                String(substring), inBlockComment: &inBlockComment
            )
            guard offset + 1 == line else { continue }
            guard lexical.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let raw = lexical.lineCommentRaw else { return false }
            let body = raw.dropFirst(2).trimmingCharacters(in: .whitespacesAndNewlines)
            let marker = "[COMBO]"
            guard String(body.prefix(marker.count)).caseInsensitiveCompare(marker) == .orderedSame
            else { return false }
            let payload = body.dropFirst(marker.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return payload.hasPrefix("{") || payload.hasPrefix("[")
        }
        return false
    }
}

import CryptoKit
import Foundation

nonisolated struct SceneShaderContractLoader {
    private struct NormalizedReference {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let isLoadable: Bool
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    private struct ContractDraft {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        var isLoadable: Bool
        var diagnostics: [SceneShaderContract.Diagnostic]
        var isDuplicate = false
    }

    private struct CanonicalPayload: Encodable {
        let identity: String
        let sourceKind: SceneShaderContract.SourceKind
        let stages: [SceneShaderContract.Stage]
        let diagnostics: [SceneShaderContract.Diagnostic]
    }

    nonisolated init() {}

    nonisolated func loadRootStageProjection(
        shaderReferences: [String],
        root: SceneResourceView.Root?,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> [SceneShaderContract] {
        try checkCancellation?()
        var drafts: [String: ContractDraft] = [:]

        for reference in shaderReferences {
            let normalized = normalize(reference)
            if var draft = drafts[normalized.identity] {
                draft.isDuplicate = true
                draft.isLoadable = draft.isLoadable && normalized.isLoadable
                appendUnique(normalized.diagnostics, to: &draft.diagnostics)
                drafts[normalized.identity] = draft
            } else {
                drafts[normalized.identity] = ContractDraft(
                    identity: normalized.identity,
                    sourceKind: normalized.sourceKind,
                    isLoadable: normalized.isLoadable,
                    diagnostics: normalized.diagnostics
                )
            }
        }

        let shaderRootIsContained: Bool
        do {
            try root?.validatePath("shaders")
            shaderRootIsContained = true
        } catch SceneResourceView.ReadError.symlinkEscape { shaderRootIsContained = false }
        return try drafts.values.sorted { $0.identity < $1.identity }.map { draft in
            var diagnostics = draft.diagnostics
            if draft.isDuplicate {
                diagnostics.append(.init(
                    code: .duplicateIdentity,
                    message: "Shader identity '\(draft.identity)' was referenced more than once.",
                    relativePath: draft.identity,
                    line: nil
                ))
            }

            var stages: [SceneShaderContract.Stage] = []
            if draft.sourceKind == .authoredSource && draft.isLoadable {
                if !shaderRootIsContained {
                    diagnostics.append(.init(
                        code: .symlinkEscape,
                        message: "Shader root resolves outside its package root.",
                        relativePath: "shaders",
                        line: nil
                    ))
                } else {
                    for (kind, suffix, missingCode) in [
                        (SceneShaderContract.StageKind.vertex, ".vert", SceneShaderContract.DiagnosticCode.missingVertexStage),
                        (.fragment, ".frag", .missingFragmentStage)
                    ] {
                        if let stage = try loadStage(
                            identity: draft.identity,
                            suffix: suffix,
                            kind: kind,
                            missingCode: missingCode,
                            root: root,
                            checkCancellation: checkCancellation,
                            diagnostics: &diagnostics
                        ) {
                            stages.append(stage)
                        }
                    }
                }
            }

            diagnostics = sortedUnique(diagnostics)
            let canonicalSHA256 = Self.canonicalHash(
                identity: draft.identity,
                sourceKind: draft.sourceKind,
                stages: stages,
                diagnostics: diagnostics
            ) ?? ""
            if canonicalSHA256.isEmpty {
                // Appended after the projection on purpose: the empty digest is a
                // marker for this same contract, and recomputing consumers (X-Ray
                // stock identity) re-derive their own digest and stay unverified.
                diagnostics = sortedUnique(diagnostics + [
                    .init(
                        code: .malformedAnnotation,
                        message: "canonical shader contract hash unavailable",
                        relativePath: nil,
                        line: nil
                    )
                ])
            }
            return SceneShaderContract(
                identity: draft.identity,
                sourceKind: draft.sourceKind,
                stages: stages,
                diagnostics: diagnostics,
                canonicalSHA256: canonicalSHA256
            )
        }
    }

    nonisolated private func normalize(_ reference: String) -> NormalizedReference {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        let fallbackIdentity = normalized.isEmpty ? "<empty>" : normalized

        guard !normalized.isEmpty else {
            return invalidReference(
                identity: fallbackIdentity,
                code: .invalidReference,
                message: "Shader reference is empty."
            )
        }
        guard !normalized.unicodeScalars.contains(where: { $0.value < 32 }) else {
            return invalidReference(
                identity: fallbackIdentity,
                code: .invalidReference,
                message: "Shader reference contains a control character."
            )
        }
        guard !normalized.hasPrefix("/") && normalized.range(
            of: #"^[A-Za-z]:"#,
            options: .regularExpression
        ) == nil else {
            return invalidReference(
                identity: fallbackIdentity,
                code: .pathEscape,
                message: "Absolute shader references are not allowed."
            )
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0.isEmpty }) else {
            return invalidReference(
                identity: fallbackIdentity,
                code: .invalidReference,
                message: "Shader reference contains an empty path component."
            )
        }
        guard !components.contains("..") else {
            return invalidReference(
                identity: fallbackIdentity,
                code: .pathEscape,
                message: "Shader reference escapes its root."
            )
        }

        var identity = components.filter { $0 != "." }.joined(separator: "/")
        for suffix in [".vert", ".frag", ".json"] where identity.lowercased().hasSuffix(suffix) {
            identity.removeLast(suffix.count)
            break
        }
        guard !identity.isEmpty else {
            return invalidReference(
                identity: fallbackIdentity,
                code: .invalidReference,
                message: "Shader reference has no source identity."
            )
        }

        let builtinIdentity = identity.lowercased()
        if !identity.contains("/"),
           (SceneBuiltinShaderIdentity.isImage(builtinIdentity)
            || builtinIdentity == "genericparticle") {
            return NormalizedReference(
                identity: builtinIdentity,
                sourceKind: .hostBuiltin,
                isLoadable: false,
                diagnostics: []
            )
        }
        return NormalizedReference(
            identity: identity,
            sourceKind: .authoredSource,
            isLoadable: true,
            diagnostics: []
        )
    }

    nonisolated private func invalidReference(
        identity: String,
        code: SceneShaderContract.DiagnosticCode,
        message: String
    ) -> NormalizedReference {
        NormalizedReference(
            identity: identity,
            sourceKind: .authoredSource,
            isLoadable: false,
            diagnostics: [.init(code: code, message: message, relativePath: identity, line: nil)]
        )
    }

    nonisolated private func loadStage(
        identity: String,
        suffix: String,
        kind: SceneShaderContract.StageKind,
        missingCode: SceneShaderContract.DiagnosticCode,
        root: SceneResourceView.Root?,
        checkCancellation: (() throws -> Void)?,
        diagnostics: inout [SceneShaderContract.Diagnostic]
    ) throws -> SceneShaderContract.Stage? {
        let sourceRelativePath = identity + suffix
        let relativePath = "shaders/" + sourceRelativePath
        let data: Data
        do {
            guard let root, let handle = root.handle(relativePath: relativePath, exact: true) else {
                throw SceneResourceView.ReadError.missing
            }
            // The raw contract has no graph file-size budget. Both stages keep
            // the vertex-first selected Root and the original shader subtree.
            data = try root.readBytes(handle, within: "shaders", checkCancellation: checkCancellation)
        } catch let error as SceneResourceView.ReadError {
            let code: SceneShaderContract.DiagnosticCode
            let message: String
            switch error {
            case .missing: code = missingCode; message = "Shader stage is missing."
            case .invalidPath: code = .pathEscape; message = "Shader stage escapes its root."
            case .symlinkEscape: code = .symlinkEscape; message = "Shader stage resolves outside its root."
            case .unreadable, .fileTooLarge: code = .unreadableSource; message = "Shader stage could not be read."
            case .sourceChanged, .invalidHandle: throw error
            }
            diagnostics.append(.init(code: code, message: message,
                relativePath: relativePath, line: nil))
            return nil
        }
        guard let source = String(data: data, encoding: .utf8) else {
            diagnostics.append(.init(code: .invalidUTF8, message: "Shader stage is not valid UTF-8.",
                relativePath: relativePath, line: nil))
            return nil
        }

        let parsed = SceneShaderContractSourceParser().parse(
            source,
            stageRelativePath: relativePath
        )
        diagnostics.append(contentsOf: parsed.diagnostics)
        let stageDirectory = (sourceRelativePath as NSString).deletingLastPathComponent
        for include in parsed.includes {
            try validateInclude(
                include.relativePath,
                stageDirectory: stageDirectory,
                root: root,
                stageRelativePath: relativePath,
                line: include.line,
                diagnostics: &diagnostics
            )
        }
        return .init(
            kind: kind,
            relativePath: relativePath,
            source: source,
            rawSHA256: Self.sha256(data),
            includes: parsed.includes,
            annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }

    nonisolated private func validateInclude(
        _ includePath: String,
        stageDirectory: String,
        root: SceneResourceView.Root?,
        stageRelativePath: String,
        line: Int,
        diagnostics: inout [SceneShaderContract.Diagnostic]
    ) throws {
        guard let relativePath = SceneShaderContractPath.normalizedRelativePath(
            base: stageDirectory, path: includePath
        ) else {
            diagnostics.append(.init(code: .pathEscape, message: "Shader include escapes its root.",
                relativePath: stageRelativePath, line: line))
            return
        }
        do { try root?.validatePath("shaders/" + relativePath, within: "shaders") }
        catch SceneResourceView.ReadError.symlinkEscape {
            diagnostics.append(.init(code: .symlinkEscape, message: "Shader include resolves outside its root.",
                relativePath: stageRelativePath, line: line))
        }
    }

    nonisolated private func sortedUnique(
        _ diagnostics: [SceneShaderContract.Diagnostic]
    ) -> [SceneShaderContract.Diagnostic] {
        var unique: [SceneShaderContract.Diagnostic] = []
        appendUnique(diagnostics, to: &unique)
        return unique.sorted {
            ($0.code.rawValue, $0.relativePath ?? "", $0.line ?? 0, $0.message)
                < ($1.code.rawValue, $1.relativePath ?? "", $1.line ?? 0, $1.message)
        }
    }

    nonisolated private func appendUnique(
        _ diagnostics: [SceneShaderContract.Diagnostic],
        to destination: inout [SceneShaderContract.Diagnostic]
    ) {
        for diagnostic in diagnostics where !destination.contains(diagnostic) {
            destination.append(diagnostic)
        }
    }

    /// Canonical JSON projection digest for a shader contract. Shared with the
    /// X-Ray stock identity verification, which recomputes the same projection.
    /// Contract-shaped convenience for callers that recompute the digest from
    /// the stored contract instead of the loader's live fields.
    nonisolated static func canonicalHash(_ contract: SceneShaderContract) -> String? {
        canonicalHash(
            identity: contract.identity,
            sourceKind: contract.sourceKind,
            stages: contract.stages,
            diagnostics: contract.diagnostics
        )
    }

    nonisolated static func canonicalHash(
        identity: String,
        sourceKind: SceneShaderContract.SourceKind,
        stages: [SceneShaderContract.Stage],
        diagnostics: [SceneShaderContract.Diagnostic]
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalPayload(
            identity: identity,
            sourceKind: sourceKind,
            stages: stages,
            diagnostics: diagnostics
        )
        // The payload re-encodes authored annotation values, whose numeric case
        // admits a non-finite Double; a silent empty-data digest would collapse
        // distinct contracts onto one identity, so the failure stays explicit.
        // The emitted diagnostic must keep relativePath/line nil: that is what
        // makes SceneShaderMalformedMetadataAdmission treat it as fatal instead
        // of a skippable malformed COMBO annotation.
        guard let data = try? encoder.encode(payload) else { return nil }
        return Self.sha256(data)
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

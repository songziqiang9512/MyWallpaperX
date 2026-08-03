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

    nonisolated func loadLegacyProjection(
        shaderReferences: [String],
        rootURL: URL
    ) -> [SceneShaderContract] {
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

        let packageRoot = rootURL.standardizedFileURL
        let resolvedPackageRoot = packageRoot.resolvingSymlinksInPath().standardizedFileURL
        let lexicalRoot = packageRoot.appendingPathComponent("shaders", isDirectory: true)
        let resolvedRoot = lexicalRoot.resolvingSymlinksInPath().standardizedFileURL
        let shaderRootIsContained = contains(resolvedRoot, root: resolvedPackageRoot)
        return drafts.values.sorted { $0.identity < $1.identity }.map { draft in
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
                        if let stage = loadStage(
                            identity: draft.identity,
                            suffix: suffix,
                            kind: kind,
                            missingCode: missingCode,
                            lexicalRoot: lexicalRoot,
                            resolvedRoot: resolvedRoot,
                            diagnostics: &diagnostics
                        ) {
                            stages.append(stage)
                        }
                    }
                }
            }

            diagnostics = sortedUnique(diagnostics)
            let canonicalSHA256 = canonicalHash(
                identity: draft.identity,
                sourceKind: draft.sourceKind,
                stages: stages,
                diagnostics: diagnostics
            )
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
           ["genericimage2", "genericimage4", "genericparticle"].contains(builtinIdentity) {
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
        lexicalRoot: URL,
        resolvedRoot: URL,
        diagnostics: inout [SceneShaderContract.Diagnostic]
    ) -> SceneShaderContract.Stage? {
        let sourceRelativePath = identity + suffix
        let relativePath = "shaders/" + sourceRelativePath
        let candidate = lexicalRoot
            .appendingPathComponent(sourceRelativePath, isDirectory: false)
        guard contains(candidate, root: lexicalRoot) else {
            diagnostics.append(.init(
                code: .pathEscape,
                message: "Shader stage escapes its root.",
                relativePath: relativePath,
                line: nil
            ))
            return nil
        }

        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolvedCandidate, root: resolvedRoot) else {
            diagnostics.append(.init(
                code: .symlinkEscape,
                message: "Shader stage resolves outside its root.",
                relativePath: relativePath,
                line: nil
            ))
            return nil
        }
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            diagnostics.append(.init(
                code: missingCode,
                message: "Shader stage is missing.",
                relativePath: relativePath,
                line: nil
            ))
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: candidate, options: [.mappedIfSafe])
        } catch {
            diagnostics.append(.init(
                code: .unreadableSource,
                message: "Shader stage could not be read.",
                relativePath: relativePath,
                line: nil
            ))
            return nil
        }
        guard let source = String(data: data, encoding: .utf8) else {
            diagnostics.append(.init(
                code: .invalidUTF8,
                message: "Shader stage is not valid UTF-8.",
                relativePath: relativePath,
                line: nil
            ))
            return nil
        }

        let parsed = SceneShaderContractSourceParser().parse(
            source,
            stageRelativePath: relativePath
        )
        diagnostics.append(contentsOf: parsed.diagnostics)
        let stageDirectory = (sourceRelativePath as NSString).deletingLastPathComponent
        for include in parsed.includes {
            validateInclude(
                include.relativePath,
                stageDirectory: stageDirectory,
                lexicalRoot: lexicalRoot,
                resolvedRoot: resolvedRoot,
                stageRelativePath: relativePath,
                line: include.line,
                diagnostics: &diagnostics
            )
        }
        return .init(
            kind: kind,
            relativePath: relativePath,
            source: source,
            rawSHA256: sha256(data),
            includes: parsed.includes,
            annotations: parsed.annotations,
            declarations: parsed.declarations
        )
    }

    nonisolated private func validateInclude(
        _ includePath: String,
        stageDirectory: String,
        lexicalRoot: URL,
        resolvedRoot: URL,
        stageRelativePath: String,
        line: Int,
        diagnostics: inout [SceneShaderContract.Diagnostic]
    ) {
        guard let relativePath = SceneShaderContractPath.normalizedRelativePath(
            base: stageDirectory,
            path: includePath
        ) else {
            diagnostics.append(.init(
                code: .pathEscape,
                message: "Shader include escapes its root.",
                relativePath: stageRelativePath,
                line: line
            ))
            return
        }
        let candidate = lexicalRoot
            .appendingPathComponent(relativePath, isDirectory: false)
        guard contains(candidate, root: lexicalRoot) else {
            diagnostics.append(.init(
                code: .pathEscape,
                message: "Shader include escapes its root.",
                relativePath: stageRelativePath,
                line: line
            ))
            return
        }
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolvedCandidate, root: resolvedRoot) else {
            diagnostics.append(.init(
                code: .symlinkEscape,
                message: "Shader include resolves outside its root.",
                relativePath: stageRelativePath,
                line: line
            ))
            return
        }
    }

    nonisolated private func contains(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidate.path == rootPath || candidate.path.hasPrefix(prefix)
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

    nonisolated private func canonicalHash(
        identity: String,
        sourceKind: SceneShaderContract.SourceKind,
        stages: [SceneShaderContract.Stage],
        diagnostics: [SceneShaderContract.Diagnostic]
    ) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = CanonicalPayload(
            identity: identity,
            sourceKind: sourceKind,
            stages: stages,
            diagnostics: diagnostics
        )
        return sha256((try? encoder.encode(payload)) ?? Data())
    }

    nonisolated private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

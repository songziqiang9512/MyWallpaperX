import CryptoKit
import Foundation

/// Resolves one shader virtual path through the ordered Scene resource view.
/// The returned model deliberately contains no absolute filesystem identity.
nonisolated struct SceneShaderSourceResolver {
    typealias Provenance = SceneShaderSourceGraph.Provenance
    typealias Failure = SceneShaderSourceGraph.ResourceFailure

    nonisolated struct ResolvedFile: Equatable, Sendable {
        let virtualPath: String
        let provenance: Provenance
        let source: String
        let rawSHA256: String
        let byteCount: Int
    }

    nonisolated enum Resolution: Equatable, Sendable {
        case resolved(ResolvedFile)
        case failed(Failure)
    }

    nonisolated struct CandidateResolution: Equatable, Sendable {
        let provenance: Provenance
        let resolution: Resolution
    }

    nonisolated struct ResolutionSet: Equatable, Sendable {
        let selected: Resolution
        let candidates: [CandidateResolution]
    }

    nonisolated enum IncludeCandidates: Equatable, Sendable {
        case paths([String])
        case invalidPath
    }

    nonisolated init() {}

    /// Resolves an exact `shaders/...` virtual path. `SceneResourceView` owns
    /// package -> loose -> stock precedence for the same virtual path.
    nonisolated func resolve(
        virtualPath rawPath: String,
        resourceView: SceneResourceView,
        maximumBytes: Int,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> Resolution {
        try resolveWithEvidence(
            virtualPath: rawPath,
            resourceView: resourceView,
            maximumBytes: maximumBytes, checkCancellation: checkCancellation
        ).selected
    }

    /// Captures the selected source and required upper-root misses. Shadowed
    /// roots do not affect playback or dependency identity and are not read.
    nonisolated func resolveWithEvidence(
        virtualPath rawPath: String,
        resourceView: SceneResourceView,
        maximumBytes: Int,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> ResolutionSet {
        try checkCancellation?()
        guard let virtualPath = Self.normalizedShaderVirtualPath(rawPath) else {
            return .init(selected: .failed(.invalidPath), candidates: [])
        }
        guard maximumBytes >= 0 else {
            return .init(selected: .failed(.fileTooLarge), candidates: [])
        }
        // Indexed selection is authoritative even if the selected file becomes
        // unreadable or disappears. It must never expose a lower-root shader.
        if let selected = resourceView.resolvedResource(relativePath: virtualPath) {
            let resolution = try resolve(virtualPath: virtualPath, root: selected.owner,
                maximumBytes: maximumBytes, checkCancellation: checkCancellation)
            let upperMisses = resourceView.roots.prefix { !$0.owns(selected) }.map {
                CandidateResolution(provenance: Self.provenance($0.source), resolution: .failed(.missing))
            }
            return .init(selected: resolution, candidates: upperMisses
                + [.init(provenance: Self.provenance(selected.source), resolution: resolution)])
        }
        // Literal-only files, including hidden authored paths, retain the same
        // first-existing-root semantics when ordinary indexing has no entry.
        var candidates: [CandidateResolution] = []
        for root in resourceView.roots {
            let resolution = try resolve(virtualPath: virtualPath, root: root,
                maximumBytes: maximumBytes, checkCancellation: checkCancellation)
            candidates.append(.init(provenance: Self.provenance(root.source), resolution: resolution))
            if !isMissing(resolution) { return .init(selected: resolution, candidates: candidates) }
        }
        return .init(selected: .failed(.missing), candidates: candidates)
    }

    nonisolated private func resolve(
        virtualPath: String,
        root: SceneResourceView.Root,
        maximumBytes: Int,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> Resolution {
        guard let handle = root.handle(relativePath: virtualPath) else { return .failed(.invalidPath) }
        let data: Data
        do { data = try root.readBytes(handle, maximumBytes: maximumBytes, checkCancellation: checkCancellation) }
        catch let error as SceneResourceView.ReadError {
            switch error {
            case .invalidPath: return .failed(.invalidPath)
            case .missing: return .failed(.missing)
            case .symlinkEscape: return .failed(.symlinkEscape)
            case .unreadable: return .failed(.unreadable)
            case .fileTooLarge: return .failed(.fileTooLarge)
            case .sourceChanged, .invalidHandle: throw error
            }
        }
        guard let shaderSource = String(data: data, encoding: .utf8) else {
            return .failed(.invalidUTF8)
        }
        return .resolved(.init(virtualPath: virtualPath,
            provenance: Self.provenance(root.source), source: shaderSource,
            rawSHA256: sha256(data), byteCount: data.count))
    }

    nonisolated private func isMissing(_ resolution: Resolution) -> Bool {
        if case .failed(.missing) = resolution { return true }
        return false
    }

    /// Produces both include interpretations used by the Scene shader dialect:
    /// relative to the including source and relative to the shader root.
    nonisolated func includeCandidatePaths(
        request rawRequest: String,
        parentVirtualPath rawParentPath: String
    ) -> IncludeCandidates {
        guard let parentPath = Self.normalizedShaderVirtualPath(rawParentPath) else {
            return .invalidPath
        }
        let parentComponents = parentPath.split(separator: "/").map(String.init)
        guard parentComponents.count > 1 else { return .invalidPath }

        let sourceDirectory = Array(parentComponents.dropLast())
        let candidates = [sourceDirectory, ["shaders"]].compactMap {
            normalizedIncludePath(rawRequest, baseComponents: $0)
        }
        var identities: Set<String> = []
        let unique = candidates.filter {
            identities.insert(Self.identity($0)).inserted
        }
        return unique.isEmpty ? .invalidPath : .paths(unique)
    }

    nonisolated static func normalizedShaderVirtualPath(_ rawPath: String) -> String? {
        let path = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard isSafeRelativeInput(path) else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count > 1,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              components[0].lowercased() == "shaders" else {
            return nil
        }
        return components.joined(separator: "/")
    }

    nonisolated static func identity(_ virtualPath: String) -> String {
        virtualPath.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    nonisolated private func normalizedIncludePath(
        _ rawRequest: String,
        baseComponents: [String]
    ) -> String? {
        let request = rawRequest.replacingOccurrences(of: "\\", with: "/")
        guard Self.isSafeRelativeInput(request) else { return nil }
        let requestedComponents = request.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !requestedComponents.isEmpty,
              requestedComponents.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }

        var components = baseComponents
        for component in requestedComponents {
            switch component {
            case ".":
                continue
            case "..":
                guard components.count > 1 else { return nil }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }
        guard components.count > 1,
              components[0].lowercased() == "shaders" else {
            return nil
        }
        return components.joined(separator: "/")
    }

    nonisolated private static func isSafeRelativeInput(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !hasDrivePrefix(path),
              !path.unicodeScalars.contains(where: {
                  $0.value < 32 || $0.value == 127
              }) else {
            return false
        }
        return true
    }

    nonisolated private static func hasDrivePrefix(_ path: String) -> Bool {
        guard path.count >= 2 else { return false }
        let start = path.startIndex
        let next = path.index(after: start)
        return path[start].isLetter && path[next] == ":"
    }

    nonisolated static func provenance(_ source: SceneResourceView.Source) -> Provenance {
        switch source {
        case .package: .package
        case .loose: .loose
        case .stock: .stock
        }
    }

    nonisolated private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

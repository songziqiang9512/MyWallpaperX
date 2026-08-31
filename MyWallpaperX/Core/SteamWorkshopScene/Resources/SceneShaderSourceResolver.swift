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
        maximumBytes: Int
    ) -> Resolution {
        resolveWithEvidence(
            virtualPath: rawPath,
            resourceView: resourceView,
            maximumBytes: maximumBytes
        ).selected
    }

    /// Records every root candidate while preserving SceneResourceView's
    /// package -> loose -> stock first-existing-root project policy.
    nonisolated func resolveWithEvidence(
        virtualPath rawPath: String,
        resourceView: SceneResourceView,
        maximumBytes: Int
    ) -> ResolutionSet {
        guard let virtualPath = Self.normalizedShaderVirtualPath(rawPath) else {
            return .init(selected: .failed(.invalidPath), candidates: [])
        }
        guard maximumBytes >= 0 else {
            return .init(selected: .failed(.fileTooLarge), candidates: [])
        }
        let candidates = resourceView.roots.map { root in
            CandidateResolution(
                provenance: Self.provenance(root.source),
                resolution: resolve(
                    virtualPath: virtualPath,
                    root: root,
                    maximumBytes: maximumBytes
                )
            )
        }
        let indexedResource = resourceView.resource(relativePath: virtualPath)
        let indexedRoot = indexedResource.flatMap { selected in
            resourceView.rootIndex(containing: selected.url)
        }
        let selected = indexedRoot.map { candidates[$0].resolution }
            ?? candidates.first { !isMissing($0.resolution) }?.resolution
            ?? .failed(.missing)
        return .init(selected: selected, candidates: candidates)
    }

    nonisolated private func resolve(
        virtualPath: String,
        root: SceneResourceView.Root,
        maximumBytes: Int
    ) -> Resolution {
        let indexed = root.resource(relativePath: virtualPath)
        let candidate = indexed?.url.standardizedFileURL
            ?? root.url.appendingPathComponent(virtualPath).standardizedFileURL
        guard indexed != nil || FileManager.default.fileExists(atPath: candidate.path) else {
            return .failed(.missing)
        }
        let rootURL = root.url.standardizedFileURL
        guard contains(candidate, root: rootURL.standardizedFileURL) else {
            return .failed(.symlinkEscape)
        }

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard contains(resolvedCandidate, root: resolvedRoot) else {
            return .failed(.symlinkEscape)
        }

        let values: URLResourceValues
        do {
            values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            return .failed(.unreadable)
        }
        guard values.isRegularFile == true else { return .failed(.unreadable) }
        if let fileSize = values.fileSize, fileSize > maximumBytes {
            return .failed(.fileTooLarge)
        }

        let data: Data
        do {
            data = try Data(contentsOf: candidate, options: [.mappedIfSafe])
        } catch {
            return .failed(.unreadable)
        }
        guard data.count <= maximumBytes else { return .failed(.fileTooLarge) }
        guard let shaderSource = String(data: data, encoding: .utf8) else {
            return .failed(.invalidUTF8)
        }
        return .resolved(.init(
            virtualPath: virtualPath,
            provenance: Self.provenance(root.source),
            source: shaderSource,
            rawSHA256: sha256(data),
            byteCount: data.count
        ))
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

    nonisolated private func contains(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidate.path == rootPath || candidate.path.hasPrefix(prefix)
    }

    nonisolated private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

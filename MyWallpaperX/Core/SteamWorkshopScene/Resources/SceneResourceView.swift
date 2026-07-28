import Foundation

/// Read-only Scene resource namespace. Earlier roots win when the same authored
/// relative path exists in more than one source.
struct SceneResourceView {
    enum Source: String {
        case package
        case loose
        case stock
    }

    struct Root {
        let source: Source
        let url: URL
        let index: SceneResourceIndex
    }

    let roots: [Root]

    nonisolated init(
        projectRootURL: URL,
        packageRootURL: URL?,
        stockAssetsRootURL: URL? = Self.defaultStockAssetsRootURL()
    ) {
        var candidates: [(Source, URL)] = []
        if let packageRootURL {
            candidates.append((.package, packageRootURL))
        }
        candidates.append((.loose, projectRootURL))
        if let stockAssetsRootURL {
            candidates.append((.stock, stockAssetsRootURL))
        }

        var seen: Set<String> = []
        roots = candidates.compactMap { source, rawURL in
            let url = rawURL.standardizedFileURL
            guard seen.insert(url.path).inserted,
                  FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            return Root(
                source: source,
                url: url,
                index: SceneResourceIndexBuilder().build(rootURL: url)
            )
        }
    }

    nonisolated var primaryRootURL: URL {
        roots.first?.url ?? URL(fileURLWithPath: "/", isDirectory: true)
    }

    nonisolated var authorResources: [SceneResourceIndex.Resource] {
        mergedResources(from: roots.filter { $0.source != .stock })
    }

    nonisolated var availableRelativePaths: [String] {
        let virtualPaths = mergedResources(from: roots).map(\.relativePath)
        let explicitStockPaths = roots
            .filter { $0.source == .stock }
            .flatMap(\.index.resources)
            .map { "assets/" + $0.relativePath }
        return virtualPaths + explicitStockPaths
    }

    nonisolated func resource(relativePath rawPath: String) -> SceneResourceIndex.Resource? {
        guard let normalized = Self.normalizedRelativePath(rawPath) else { return nil }
        for root in roots {
            if let resource = root.index.resources.first(where: {
                Self.identity($0.relativePath) == Self.identity(normalized)
            }) {
                return resource
            }
            if root.source == .stock,
               normalized.localizedLowercase.hasPrefix("assets/"),
               let resource = root.index.resources.first(where: {
                   Self.identity($0.relativePath)
                       == Self.identity(String(normalized.dropFirst("assets/".count)))
               }) {
                return resource
            }
        }
        return nil
    }

    nonisolated func resource(forReference rawReference: String) -> SceneResourceIndex.Resource? {
        guard let reference = Self.normalizedRelativePath(rawReference) else { return nil }
        for candidate in Self.referenceCandidates(reference) {
            if let resource = resource(relativePath: candidate) {
                return resource
            }
        }
        return nil
    }

    nonisolated func rootURL(containing resourceURL: URL) -> URL? {
        root(containing: resourceURL)?.url
    }

    nonisolated func source(containing resourceURL: URL) -> Source? {
        root(containing: resourceURL)?.source
    }

    nonisolated private func root(containing resourceURL: URL) -> Root? {
        let candidate = resourceURL.standardizedFileURL.path
        return roots.first { root in
            let rootPath = root.url.path
            return candidate == rootPath || candidate.hasPrefix(rootPath + "/")
        }
    }

    nonisolated func displayPath(for resourceURL: URL) -> String {
        guard let root = roots.first(where: { root in
            let path = resourceURL.standardizedFileURL.path
            return path == root.url.path || path.hasPrefix(root.url.path + "/")
        }) else {
            return resourceURL.lastPathComponent
        }
        let relative = String(
            resourceURL.standardizedFileURL.path.dropFirst(root.url.path.count + 1)
        )
        return root.source == .package ? relative : "\(root.source.rawValue):\(relative)"
    }

    nonisolated static func defaultStockAssetsRootURL(in bundle: Bundle = .main) -> URL? {
        let bundleRoot: URL?
        if let bundled = bundle.url(forResource: "SceneStockAssets", withExtension: "bundle") {
            bundleRoot = bundled
        } else if let resourceURL = bundle.resourceURL {
            let candidate = resourceURL.appendingPathComponent(
                "SceneStockAssets.bundle",
                isDirectory: true
            )
            bundleRoot = FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        } else {
            bundleRoot = nil
        }
        guard let bundleRoot else { return nil }
        let assets = bundleRoot.appendingPathComponent("assets", isDirectory: true)
        return FileManager.default.fileExists(atPath: assets.path) ? assets : nil
    }

    nonisolated private func mergedResources(
        from selectedRoots: [Root]
    ) -> [SceneResourceIndex.Resource] {
        var identities: Set<String> = []
        return selectedRoots.flatMap(\.index.resources).filter {
            identities.insert(Self.identity($0.relativePath)).inserted
        }
    }

    nonisolated private static func referenceCandidates(_ reference: String) -> [String] {
        var candidates = [reference]
        if URL(fileURLWithPath: reference).pathExtension.isEmpty {
            candidates += [
                reference + ".json",
                "materials/" + reference + ".json",
                "materials/" + reference + ".tex",
                reference + ".tex",
            ]
        }
        return candidates
    }

    nonisolated private static func normalizedRelativePath(_ rawPath: String) -> String? {
        let path = rawPath.replacingOccurrences(of: "\\", with: "/")
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              path.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) == nil else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return path
    }

    nonisolated private static func identity(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").localizedLowercase
    }
}

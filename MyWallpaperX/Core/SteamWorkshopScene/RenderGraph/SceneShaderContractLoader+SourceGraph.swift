import Foundation

extension SceneShaderContractLoader {
    nonisolated func load(
        shaderReferences: [String],
        rootURL: URL
    ) -> [SceneShaderContract] {
        load(
            shaderReferences: shaderReferences,
            resourceView: SceneResourceView(
                projectRootURL: rootURL,
                packageRootURL: nil,
                stockAssetsRootURL: nil
            )
        )
    }

    /// Preserves the R1 vertex-first, same-root contract projection while
    /// attaching an independent R2 VFS graph for preparation and evidence.
    /// The graph must not rewrite raw stages or their canonical admission key.
    nonisolated func load(
        shaderReferences: [String],
        resourceView: SceneResourceView
    ) -> [SceneShaderContract] {
        var groups: [String: (rootURL: URL, references: [String])] = [:]
        for reference in shaderReferences {
            let rootURL = legacyRootURL(for: reference, resourceView: resourceView)
            let key = rootURL.standardizedFileURL.path
            if var group = groups[key] {
                group.references.append(reference)
                groups[key] = group
            } else {
                groups[key] = (rootURL, [reference])
            }
        }

        let contracts = groups.keys.sorted().flatMap { key in
            guard let group = groups[key] else { return [SceneShaderContract]() }
            return loadLegacyProjection(
                shaderReferences: group.references,
                rootURL: group.rootURL
            )
        }
        return contracts.sorted { $0.identity < $1.identity }.map { contract in
            guard contract.sourceKind == .authoredSource else { return contract }
            let graph = SceneShaderSourceGraphBuilder().build(
                roots: [
                    .init(
                        label: SceneShaderContract.StageKind.vertex.rawValue,
                        virtualPath: "shaders/\(contract.identity).vert"
                    ),
                    .init(
                        label: SceneShaderContract.StageKind.fragment.rawValue,
                        virtualPath: "shaders/\(contract.identity).frag"
                    ),
                ],
                resourceView: resourceView
            )
            return SceneShaderContract(
                identity: contract.identity,
                sourceKind: contract.sourceKind,
                stages: contract.stages,
                diagnostics: contract.diagnostics,
                canonicalSHA256: contract.canonicalSHA256,
                sourceGraph: graph
            )
        }
    }

    /// Mirrors the pre-R2 AssetCatalog projection exactly: the first indexed
    /// vertex wins, then fragment, otherwise the primary project/package root.
    nonisolated private func legacyRootURL(
        for reference: String,
        resourceView: SceneResourceView
    ) -> URL {
        var identity = reference.replacingOccurrences(of: "\\", with: "/")
        for suffix in [".vert", ".frag", ".json"]
        where identity.localizedLowercase.hasSuffix(suffix) {
            identity.removeLast(suffix.count)
            break
        }
        for suffix in [".vert", ".frag"] {
            if let resource = resourceView.resource(
                relativePath: "shaders/" + identity + suffix
            ), let rootURL = resourceView.rootURL(containing: resource.url) {
                return rootURL
            }
        }
        return resourceView.primaryRootURL
    }
}

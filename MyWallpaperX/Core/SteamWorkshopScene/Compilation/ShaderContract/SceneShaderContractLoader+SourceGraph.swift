import Foundation

extension SceneShaderContractLoader {
    nonisolated func load(
        shaderReferences: [String],
        rootURL: URL,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> [SceneShaderContract] {
        try load(
            shaderReferences: shaderReferences,
            resourceView: SceneResourceView(
                projectRootURL: rootURL,
                packageRootURL: nil,
                stockAssetsRootURL: nil
            ), checkCancellation: checkCancellation
        )
    }

    /// Preserves the R1 vertex-first, same-root contract projection while
    /// attaching an independent R2 VFS graph for preparation and evidence.
    /// The graph must not rewrite raw stages or their canonical admission key.
    nonisolated func load(
        shaderReferences: [String],
        resourceView: SceneResourceView,
        checkCancellation: (() throws -> Void)? = nil
    ) throws -> [SceneShaderContract] {
        try checkCancellation?()
        let mounted = resourceView.roots.contains(where: \.usesPackageNamespaceOrder)
        var groups: [SceneResourceView.Root.NamespaceIdentity: (root: SceneResourceView.Root?, references: [String])] = [:]
        for reference in shaderReferences {
            let root = sourceRoot(for: reference, resourceView: resourceView)
            let key: SceneResourceView.Root.NamespaceIdentity = mounted
                ? root?.namespaceIdentity ?? .absent
                : root?.directoryURL.map { .directory(path: $0.standardizedFileURL.path) } ?? .absent
            if var group = groups[key] {
                group.references.append(reference)
                groups[key] = group
            } else {
                groups[key] = (root, [reference])
            }
        }

        let keys = groups.keys.sorted { lhs, rhs in
            // The legacy directory projection retains its physical path order.
            // Package mounts order by resource domain, then typed namespace;
            // their retired extraction directory cannot be an authority.
            if mounted {
                let a = groups[lhs]?.root?.sourceOrder ?? 3
                let b = groups[rhs]?.root?.sourceOrder ?? 3
                if a != b { return a < b }
            }
            return lhs.sortComponents.lexicographicallyPrecedes(rhs.sortComponents)
        }
        let contracts = try keys.flatMap { key in
            guard let group = groups[key] else { return [SceneShaderContract]() }
            return try loadRootStageProjection(
                shaderReferences: group.references,
                root: group.root, checkCancellation: checkCancellation
            )
        }
        return try contracts.sorted { $0.identity < $1.identity }.map { contract in
            guard contract.sourceKind == .authoredSource else { return contract }
            let graph = try SceneShaderSourceGraphBuilder().build(
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
                resourceView: resourceView, checkCancellation: checkCancellation
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
    nonisolated private func sourceRoot(
        for reference: String,
        resourceView: SceneResourceView
    ) -> SceneResourceView.Root? {
        var identity = reference.replacingOccurrences(of: "\\", with: "/")
        for suffix in [".vert", ".frag", ".json"]
        where identity.localizedLowercase.hasSuffix(suffix) {
            identity.removeLast(suffix.count)
            break
        }
        for suffix in [".vert", ".frag"] {
            if let resource = resourceView.resolvedResource(
                relativePath: "shaders/" + identity + suffix
            ), let root = resourceView.roots.first(where: { $0.owns(resource) }) {
                return root
            }
        }
        return resourceView.roots.first
    }
}

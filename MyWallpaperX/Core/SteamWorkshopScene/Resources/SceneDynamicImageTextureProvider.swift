import Metal

struct SceneDynamicImageTextureProviderSnapshot {
    let layerSources: [Int: SceneLayerSourcePublication]
    let pendingLayerSourceIDs: Set<Int>
}

/// Surface-scoped view over launch-prepared immutable image resources. Layer
/// identities come from the VM topology transaction; resource identity and UV
/// metadata remain on the canonical texture candidate.
final class SceneDynamicImageTextureProvider {
    private let resources: [String: ScenePreparedDynamicImageResource]

    init(resources: [String: ScenePreparedDynamicImageResource]) {
        self.resources = resources
    }

    func snapshot(
        dynamicLayers: [SceneRenderDescriptor.Layer]
    ) -> SceneDynamicImageTextureProviderSnapshot {
        var layerSources: [Int: SceneLayerSourcePublication] = [:]
        var pending: Set<Int> = []
        for layer in dynamicLayers where layer.contentKind == "image" {
            guard let modelPath = layer.imagePath,
                  let resource = resources[modelPath.lowercased()],
                  let candidate = resource.loaded.candidate,
                  candidate.texture === resource.loaded.texture,
                  let layerSource = SceneLayerSourcePublication(
                    layerID: layer.id,
                    publication: .init(
                        requestIdentity: .layerSource(layer.id),
                        candidate: candidate,
                        contentGeneration: 1
                    ),
                    renderSizeWH: resource.renderSizeWH
                  ) else {
                pending.insert(layer.id)
                continue
            }
            layerSources[layer.id] = layerSource
        }
        return .init(
            layerSources: layerSources,
            pendingLayerSourceIDs: pending
        )
    }
}

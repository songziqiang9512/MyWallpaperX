import Foundation

/// Releases fail-closed alpha suppression only for scalar properties that the
/// generic QuickJS owner can represent. Callback failure still resolves to the
/// authored/property/Timeline current through the existing snapshot channel.
nonisolated enum SceneScriptScalarDisplayProjection {
    static func apply(
        admittedTargets: Set<SceneDynamicTarget>,
        to descriptor: SceneRenderDescriptor
    ) -> SceneRenderDescriptor {
        let layerIDs = Set(admittedTargets.compactMap { target -> Int? in
            guard case let .layer(layerID, .alpha) = target else { return nil }
            return layerID
        })
        guard !layerIDs.isEmpty else { return descriptor }
        var projected = descriptor
        for index in projected.layers.indices
            where layerIDs.contains(projected.layers[index].id)
        {
            guard let ownership = projected.layers[index].displayScriptOwnership,
                  ownership.alpha else { continue }
            projected.layers[index].displayScriptOwnership = .init(
                visible: ownership.visible,
                alpha: false
            )
        }
        return projected
    }
}

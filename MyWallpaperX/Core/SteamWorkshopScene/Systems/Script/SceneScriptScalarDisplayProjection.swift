import Foundation

/// First tier: releases fail-closed alpha suppression only for scalar
/// properties that the generic QuickJS owner can represent (admitted
/// targets). Callback failure still resolves to the authored/property/
/// Timeline current through the existing snapshot channel.
///
/// Second tier: `applyUnclaimedFallback(claimedTargets:to:)` releases alpha
/// ownership that no current publication path can ever claim, so an
/// unprovable binding fails soft to its authored alpha instead of keeping
/// the whole layer fail-closed forever.
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

    /// Second-tier launch release: alpha ownership that no current owner can
    /// ever claim. `claimedTargets` is the union of every alpha publication
    /// path (shared-alpha, scalar-projected, timeline); a layer whose
    /// `.layer(id, .alpha)` target is absent from it can never receive a
    /// script publication in this runtime, so retaining ownership only keeps
    /// the layer fail-closed forever. The release keeps the visible bit and
    /// the authored descriptor alpha; it does not construct any script owner
    /// and does not authorize script composition.
    nonisolated static func applyUnclaimedFallback(
        claimedTargets: Set<SceneDynamicTarget>,
        to descriptor: SceneRenderDescriptor
    ) -> SceneRenderDescriptor {
        var projected = descriptor
        for index in projected.layers.indices {
            guard let ownership = projected.layers[index].displayScriptOwnership,
                  ownership.alpha else { continue }
            let target = SceneDynamicTarget.layer(
                layerID: projected.layers[index].id,
                field: .alpha
            )
            guard !claimedTargets.contains(target) else { continue }
            projected.layers[index].displayScriptOwnership = .init(
                visible: ownership.visible,
                alpha: false
            )
        }
        return projected
    }
}

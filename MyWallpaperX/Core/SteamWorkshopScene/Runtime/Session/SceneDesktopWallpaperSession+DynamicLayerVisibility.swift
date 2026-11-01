import Foundation

#if DEBUG
extension SceneDesktopWallpaperSession {
    func logDebugDynamicLayerVisibilityIfChanged(
        descriptor: SceneRenderDescriptor,
        snapshot: SceneDynamicSnapshot,
        destroyedAuthoredLayerIDs: Set<Int>
    ) {
        guard SceneDesktopWallpaperHost.usesDebugEvidenceWindow else { return }
        let visibleLayerIDs = SceneLayerVisibility.visibleLayerIDs(
            in: descriptor,
            snapshot: snapshot
        ).subtracting(destroyedAuthoredLayerIDs)
        let records = descriptor.layers.compactMap { layer -> String? in
            let resolved = snapshot[.layer(layerID: layer.id, field: .visibility)]
            let value: Bool
            if let resolved, case let .bool(current) = resolved.value {
                value = current
            } else {
                value = layer.visible ?? true
            }
            return "layer=\(layer.id) source=\(resolved?.source.rawValue ?? "authored")"
                + " value=\(value)"
                + " effective=\(visibleLayerIDs.contains(layer.id))"
        }
        let signature = records.joined(separator: "|")
        guard signature != debugDynamicLayerVisibilitySignature else { return }
        debugDynamicLayerVisibilitySignature = signature
        for record in records {
            NSLog(
                "MWX dynamic layer visibility: schema=dynamic-layer-visibility-v1 frame=%llu generation=%llu %@",
                snapshot.frameIndex,
                snapshot.generation,
                record
            )
        }
    }
}
#endif

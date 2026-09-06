import simd

/// Resolves per-frame layer transforms from the shared dynamic snapshot.
/// Relative Timeline values have already been composed with their authored base by the runtime.
nonisolated enum SceneLayerDynamicWorldFrameResolver {
    nonisolated static func resolve(
        descriptor: SceneRenderDescriptor,
        byID: [Int: SceneRenderDescriptor.Layer],
        snapshot: SceneDynamicSnapshot,
        staticFrames: [Int: simd_float4x4],
        dynamicLayerIDs: Set<Int> = []
    ) -> [Int: simd_float4x4] {
        var overrides: [Int: SceneLayerWorldFrameResolver.TransformOverride] = [:]
        for layerID in snapshot.dynamicTransformLayerIDsForFrame {
            guard let layer = byID[layerID] else { continue }
            let origin = value(layerID: layer.id, field: .origin, snapshot: snapshot)
            let scale = value(layerID: layer.id, field: .scale, snapshot: snapshot)
            let angles = value(layerID: layer.id, field: .angles, snapshot: snapshot)
            guard origin != nil || scale != nil || angles != nil else { continue }
            overrides[layer.id] = .init(origin: origin, scale: scale, angles: angles)
        }
        if overrides.isEmpty, !dynamicLayerIDs.isEmpty {
            // Dynamic script layers are currently root layers. Their complete
            // frame record is applied to the cached descriptor projection,
            // so refresh only their local world matrices instead of walking
            // the entire authored hierarchy on every upsert.
            var result = staticFrames
            for layer in descriptor.layers
                where dynamicLayerIDs.contains(layer.id) {
                guard layer.parentID == nil else {
                    // Keep the canonical parent/attachment semantics if a
                    // future provider publishes a parented dynamic layer.
                    return SceneLayerWorldFrameResolver.compute(
                        layers: descriptor.layers,
                        byID: byID,
                        sceneOrthoHeight: descriptor.camera.orthoHeight,
                        transformOverrides: overrides
                    )
                }
                result[layer.id] = SceneLayerWorldFrameResolver.compute(
                    layers: [layer], byID: [layer.id: layer],
                    sceneOrthoHeight: descriptor.camera.orthoHeight
                )[layer.id]
            }
            return result
        }
        guard !overrides.isEmpty else { return staticFrames }
        return SceneLayerWorldFrameResolver.compute(
            layers: descriptor.layers,
            byID: byID,
            sceneOrthoHeight: descriptor.camera.orthoHeight,
            transformOverrides: overrides
        )
    }

    private nonisolated static func value(
        layerID: Int,
        field: SceneDynamicLayerField,
        snapshot: SceneDynamicSnapshot
    ) -> SIMD3<Float>? {
        let target = SceneDynamicTarget.layer(layerID: layerID, field: field)
        guard let resolved = snapshot[target],
              resolved.source != .authored,
              case let .vector3(x, y, z) = resolved.value,
              x.isFinite, y.isFinite, z.isFinite else { return nil }
        return SIMD3(Float(x), Float(y), Float(z))
    }
}

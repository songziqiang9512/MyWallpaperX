import Foundation
import simd

/// Resolves per-frame layer transforms from the shared dynamic snapshot.
/// Relative Timeline values have already been composed with their authored base by the runtime.
nonisolated enum SceneLayerDynamicWorldFrameResolver {
    nonisolated static func resolve(
        descriptor: SceneRenderDescriptor,
        byID: [Int: SceneRenderDescriptor.Layer],
        snapshot: SceneDynamicSnapshot,
        staticFrames: [Int: simd_float4x4],
        dynamicLayerIDs: Set<Int> = [],
        puppetAttachmentFrames: ScenePuppetAttachmentFrameSnapshot = .empty
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
        if overrides.isEmpty,
           puppetAttachmentFrames.framesByParentLayerID.isEmpty,
           !dynamicLayerIDs.isEmpty {
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
                        transformOverrides: overrides,
                        puppetAttachmentFrames: puppetAttachmentFrames
                    )
                }
                result[layer.id] = SceneLayerWorldFrameResolver.compute(
                    layers: [layer], byID: [layer.id: layer],
                    sceneOrthoHeight: descriptor.camera.orthoHeight
                )[layer.id]
            }
            return result
        }
        guard !overrides.isEmpty
                || !puppetAttachmentFrames.framesByParentLayerID.isEmpty else {
            return staticFrames
        }
        return SceneLayerWorldFrameResolver.compute(
            layers: descriptor.layers,
            byID: byID,
            sceneOrthoHeight: descriptor.camera.orthoHeight,
            transformOverrides: overrides,
            puppetAttachmentFrames: puppetAttachmentFrames
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
        let value = SIMD3(Float(x), Float(y), Float(z))
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
            // A finite Double outside the Float range used to reach the world
            // matrix as `inf`/`NaN` and failed the shared layer snapshot for
            // every consumer of the frame. The unit that is unsafe is this
            // layer's transform, so it keeps its authored value instead.
#if DEBUG
            NSLog(
                "MWX DEBUG SCENE: phase=dynamic-transform-out-of-range layer=%d field=%@ value=%.9g,%.9g,%.9g fallback=authored",
                layerID, field.rawValue, x, y, z
            )
#endif
            return nil
        }
        return value
    }
}

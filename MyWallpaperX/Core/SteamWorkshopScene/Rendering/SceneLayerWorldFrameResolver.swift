import simd

nonisolated enum SceneLayerWorldFrameResolver {
    nonisolated static func compute(
        descriptor: SceneRenderDescriptor,
        byID: [Int: SceneRenderDescriptor.Layer]
    ) -> [Int: simd_float4x4] {
        compute(
            layers: descriptor.layers,
            byID: byID,
            sceneOrthoHeight: descriptor.camera.orthoHeight
        )
    }

    nonisolated static func compute(
        layers: [SceneRenderDescriptor.Layer],
        byID: [Int: SceneRenderDescriptor.Layer],
        sceneOrthoHeight: Float?
    ) -> [Int: simd_float4x4] {
        var cache: [Int: simd_float4x4] = [:]

        func localFrame(_ layer: SceneRenderDescriptor.Layer) -> simd_float4x4 {
            var origin = SIMD3(layer.originXYZ ?? [], fill: 0)
            let scale = SIMD3(layer.scaleXYZ ?? [], fill: 1)
            var angles = SIMD3(layer.anglesXYZ ?? [], fill: 0)
            if layer.parentID == nil {
                if let sceneOrthoHeight, sceneOrthoHeight > 0 {
                    origin.y = sceneOrthoHeight - origin.y
                }
            } else {
                origin.y = -origin.y
            }
            angles.z = -angles.z
            return SceneMatrix.translation(origin)
                * SceneMatrix.eulerXYZ(angles)
                * SceneMatrix.scale(scale)
        }

        func attachmentFrame(_ layer: SceneRenderDescriptor.Layer) -> simd_float4x4? {
            guard let values = layer.parentAttachmentBindFrame,
                  values.count == 16,
                  values.allSatisfy(\.isFinite) else {
                return nil
            }
            return simd_float4x4(columns: (
                SIMD4(values[0], values[1], values[2], values[3]),
                SIMD4(values[4], values[5], values[6], values[7]),
                SIMD4(values[8], values[9], values[10], values[11]),
                SIMD4(values[12], values[13], values[14], values[15])
            ))
        }

        func resolve(_ layer: SceneRenderDescriptor.Layer, visiting: Set<Int>) -> simd_float4x4 {
            if let cached = cache[layer.id] { return cached }
            var nextVisiting = visiting
            nextVisiting.insert(layer.id)
            let local = localFrame(layer)
            let world: simd_float4x4
            if let parentID = layer.parentID,
               !visiting.contains(parentID),
               let parent = byID[parentID] {
                let parentWorld = resolve(parent, visiting: nextVisiting)
                if let attachment = attachmentFrame(layer) {
                    world = parentWorld * attachment * local
                } else {
                    world = parentWorld * local
                }
            } else {
                world = local
            }
            cache[layer.id] = world
            return world
        }

        for layer in layers {
            _ = resolve(layer, visiting: [])
        }
        return cache
    }
}

import simd

nonisolated enum SceneLayerWorldFrameResolver {
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

        func resolve(_ layer: SceneRenderDescriptor.Layer, visiting: Set<Int>) -> simd_float4x4 {
            if let cached = cache[layer.id] { return cached }
            var nextVisiting = visiting
            nextVisiting.insert(layer.id)
            let local = localFrame(layer)
            let world: simd_float4x4
            if let parentID = layer.parentID,
               !visiting.contains(parentID),
               let parent = byID[parentID] {
                world = resolve(parent, visiting: nextVisiting) * local
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

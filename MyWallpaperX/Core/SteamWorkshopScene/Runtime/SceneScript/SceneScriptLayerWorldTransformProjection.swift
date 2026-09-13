import simd

/// Launch-prepared projection of the renderer's canonical layer world frames
/// into the public SceneScript Mat4 ABI. This type never owns transforms: it
/// reuses the render descriptor and the shared world-frame resolvers, then
/// exposes their column-major result to the existing layer snapshot.
nonisolated struct SceneScriptLayerWorldTransformProjection: Sendable {
    let catalogSignature: String

    private let descriptor: SceneRenderDescriptor
    private let layersByID: [Int: SceneRenderDescriptor.Layer]
    private let staticWorldFrames: [Int: simd_float4x4]

    init?(
        descriptor: SceneRenderDescriptor,
        catalogSignature: String
    ) {
        var layersByID: [Int: SceneRenderDescriptor.Layer] = [:]
        layersByID.reserveCapacity(descriptor.layers.count)
        for layer in descriptor.layers {
            guard layersByID.updateValue(layer, forKey: layer.id) == nil else {
                return nil
            }
        }
        let staticWorldFrames = SceneLayerWorldFrameResolver.compute(
            descriptor: descriptor,
            byID: layersByID
        )
        guard staticWorldFrames.count == descriptor.layers.count,
              descriptor.layers.allSatisfy({ layer in
                  guard let matrix = staticWorldFrames[layer.id] else {
                      return false
                  }
                  return Self.columnMajorValues(matrix).allSatisfy(\.isFinite)
              }) else {
            return nil
        }
        self.catalogSignature = catalogSignature
        self.descriptor = descriptor
        self.layersByID = layersByID
        self.staticWorldFrames = staticWorldFrames
    }

    func worldFrames(
        for snapshot: SceneDynamicSnapshot
    ) -> [Int: simd_float4x4] {
        SceneLayerDynamicWorldFrameResolver.resolve(
            descriptor: descriptor,
            byID: layersByID,
            snapshot: snapshot,
            staticFrames: staticWorldFrames
        )
    }

    static func columnMajorValues(_ matrix: simd_float4x4) -> [Double] {
        [
            Double(matrix.columns.0.x), Double(matrix.columns.0.y),
            Double(matrix.columns.0.z), Double(matrix.columns.0.w),
            Double(matrix.columns.1.x), Double(matrix.columns.1.y),
            Double(matrix.columns.1.z), Double(matrix.columns.1.w),
            Double(matrix.columns.2.x), Double(matrix.columns.2.y),
            Double(matrix.columns.2.z), Double(matrix.columns.2.w),
            Double(matrix.columns.3.x), Double(matrix.columns.3.y),
            Double(matrix.columns.3.z), Double(matrix.columns.3.w),
        ]
    }
}

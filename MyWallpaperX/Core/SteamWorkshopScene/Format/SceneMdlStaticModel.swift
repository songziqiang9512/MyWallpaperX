import Foundation
import simd

/// Loss-preserving geometry decoded from the bounded direct MDLV0023 model
/// profile. Rendering admission remains outside Format; this IR keeps the
/// authored material identity, vertex channels, indices and bounds together.
nonisolated struct SceneMdlStaticModel: Equatable {
    struct Vertex: Equatable {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let tangent: SIMD4<Float>
        let uv: SIMD2<Float>
    }

    struct Bounds: Equatable {
        let minimum: [Float]
        let maximum: [Float]
    }

    let version: String
    let headerFormat: Int
    let vertexFormat: Int
    let vertexStride: Int
    let indexElementSize: Int
    let materialPath: String
    let bounds: Bounds
    let vertices: [Vertex]
    let indices: [UInt16]

    nonisolated var triangleCount: Int { indices.count / 3 }
}

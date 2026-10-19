import Foundation
import simd

/// Loss-preserving geometry decoded from the bounded direct MDLV0023 model
/// profile. Rendering admission remains outside Format; this IR keeps the
/// authored material identity, vertex channels, indices and bounds together.
nonisolated struct SceneMdlStaticModel: Equatable {
    enum GeometryState: String {
        case authoredStatic
        /// Only the immutable mesh is admitted; no authored animation was read.
        case bindOnlyAnimationUnqualified
    }

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
    let indices: [UInt32]
    let geometryState: GeometryState

    init(
        version: String, headerFormat: Int, vertexFormat: Int,
        vertexStride: Int, indexElementSize: Int, materialPath: String,
        bounds: Bounds, vertices: [Vertex], indices: [UInt32],
        geometryState: GeometryState = .authoredStatic
    ) {
        self.version = version
        self.headerFormat = headerFormat
        self.vertexFormat = vertexFormat
        self.vertexStride = vertexStride
        self.indexElementSize = indexElementSize
        self.materialPath = materialPath
        self.bounds = bounds
        self.vertices = vertices
        self.indices = indices
        self.geometryState = geometryState
    }

    nonisolated var triangleCount: Int { indices.count / 3 }
}

import Metal
import simd

/// Prepares immutable bind-pose mesh resources. Texture preparation remains a
/// separate product: the compositor supplies either the original atlas or the
/// atlas-space graph output when it encodes this mesh in world space.
enum ScenePuppetMeshGeometry {
    struct Output {
        let product: SceneGeometryProduct
        let vertexCount: Int
        let triangleCount: Int
    }

    enum Failure: Error, CustomStringConvertible {
        case degenerateLayerSize
        case resourceAllocationFailed

        nonisolated var description: String {
            switch self {
            case .degenerateLayerSize:
                return "degenerate layer size"
            case .resourceAllocationFailed:
                return "Metal geometry resource allocation failed"
            }
        }
    }

    private static func validAuthoredSize(
        width: Float,
        height: Float
    ) -> Bool {
        width.isFinite && height.isFinite && width >= 1 && height >= 1
    }

    static func prepare(
        layerID: Int,
        mesh: SceneMdlPuppetMesh,
        atlasTexture: MTLTexture,
        layerWidth: Float,
        layerHeight: Float,
        device: MTLDevice,
        pipeline: SceneImageLayerPipeline
    ) -> Result<Output, Failure> {
        guard validAuthoredSize(width: layerWidth, height: layerHeight) else {
            return .failure(.degenerateLayerSize)
        }

        var vertices = mesh.vertices.map { vertex in
            SceneQuadVertex(
                position: SIMD2(vertex.x, vertex.y),
                texcoord: SIMD2(vertex.u, vertex.v)
            )
        }
        var indices = mesh.indices
        guard let vertexBuffer = device.makeBuffer(
                  bytes: &vertices,
                  length: vertices.count * MemoryLayout<SceneQuadVertex>.stride
              ),
              let indexBuffer = device.makeBuffer(
                  bytes: &indices,
                  length: indices.count * MemoryLayout<UInt16>.stride
              )
        else { return .failure(.resourceAllocationFailed) }

        let indexCount = indices.count
        let renderPipelineState = pipeline.state
        let product = SceneGeometryProduct(
            ownerLayerID: layerID,
            samplingTexture: atlasTexture,
            encode: {
                encoder, sourceTexture, dependencyTexture, mvp, uniforms,
                bindColorBlend in
                if let bindColorBlend {
                    bindColorBlend(encoder, sourceTexture, mvp)
                } else {
                    ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
                    encoder.setRenderPipelineState(renderPipelineState)
                    var matrix = mvp
                    encoder.setVertexBytes(
                        &matrix,
                        length: MemoryLayout<simd_float4x4>.size,
                        index: 1
                    )
                    var uniforms = uniforms
                    encoder.setFragmentBytes(
                        &uniforms,
                        length: MemoryLayout<SceneLayerFragmentUniforms>.size,
                        index: 0
                    )
                    encoder.setFragmentTexture(sourceTexture, index: 0)
                    encoder.setFragmentTexture(
                        dependencyTexture ?? sourceTexture,
                        index: 1
                    )
                }
                encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: indexCount,
                    indexType: .uint16,
                    indexBuffer: indexBuffer,
                    indexBufferOffset: 0
                )
                ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: true)
                return true
            },
            authoredSize: SIMD2(layerWidth, layerHeight),
            effectSourceExtentContract: .exactSamplingTexture
        )
        return .success(Output(
            product: product,
            vertexCount: mesh.vertices.count,
            triangleCount: mesh.triangleCount
        ))
    }
}

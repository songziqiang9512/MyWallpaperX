import Metal
import simd

// One-shot GPU recomposition of a puppet layer's atlas texture into its
// bind-pose layout. Puppet models pack body parts into a UV atlas; drawing
// the raw atlas as a quad scatters those parts. This pass replays the mesh
// (position + UV + triangle indices) once into an offscreen texture sized to
// the authored layer, producing the static bind-pose image every downstream
// consumer (masks, effects, blends) can keep treating as a plain layer source.
//
// Warp animation, skeleton playback, and attachment transforms are NOT
// implemented here; the output is the bind pose only.
enum ScenePuppetMeshRecomposer {
    struct Output {
        let texture: MTLTexture
        let byteCost: Int
        let vertexCount: Int
        let triangleCount: Int
    }

    enum Failure: Error, CustomStringConvertible {
        case degenerateLayerSize
        case textureTooLarge(width: Int, height: Int)
        case budgetExceeded(requested: Int, remaining: Int)
        case resourceAllocationFailed
        case gpuExecutionFailed

        nonisolated var description: String {
            switch self {
            case .degenerateLayerSize:
                return "degenerate layer size"
            case .textureTooLarge(let width, let height):
                return "recompose target \(width)x\(height) exceeds limit"
            case .budgetExceeded(let requested, let remaining):
                return "recompose cost \(requested) B exceeds remaining budget \(remaining) B"
            case .resourceAllocationFailed:
                return "Metal resource allocation failed"
            case .gpuExecutionFailed:
                return "GPU recompose pass failed"
            }
        }
    }

    static let maxTextureDimension = 4096
    // Independent from the per-frame offscreen pool: bind-pose recomposition
    // happens once per load and the results are retained like layer sources.
    static let recomposeByteBudget = 128 * 1024 * 1024

    static func recompose(
        mesh: SceneMdlPuppetMesh,
        atlasTexture: MTLTexture,
        layerWidth: Float,
        layerHeight: Float,
        remainingByteBudget: Int,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipeline: SceneImageLayerPipeline
    ) -> Result<Output, Failure> {
        guard layerWidth.isFinite, layerHeight.isFinite,
              layerWidth >= 1, layerHeight >= 1 else {
            return .failure(.degenerateLayerSize)
        }
        let width = Int(layerWidth.rounded())
        let height = Int(layerHeight.rounded())
        guard width <= maxTextureDimension, height <= maxTextureDimension else {
            return .failure(.textureTooLarge(width: width, height: height))
        }
        let byteCost = width * height * 4
        guard byteCost <= remainingByteBudget else {
            return .failure(.budgetExceeded(requested: byteCost, remaining: remainingByteBudget))
        }

        var vertices: [SceneQuadVertex] = []
        vertices.reserveCapacity(mesh.vertices.count)
        for vertex in mesh.vertices {
            vertices.append(SceneQuadVertex(
                position: SIMD2(vertex.x / layerWidth, vertex.y / layerHeight),
                texcoord: SIMD2(vertex.u, vertex.v)
            ))
        }
        var indices = mesh.indices

        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        targetDescriptor.storageMode = .private
        guard let target = device.makeTexture(descriptor: targetDescriptor),
              let vertexBuffer = device.makeBuffer(
                  bytes: &vertices,
                  length: vertices.count * MemoryLayout<SceneQuadVertex>.stride
              ),
              let indexBuffer = device.makeBuffer(
                  bytes: &indices,
                  length: indices.count * MemoryLayout<UInt16>.stride
              ),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return .failure(.resourceAllocationFailed)
        }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = target
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        passDescriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return .failure(.resourceAllocationFailed)
        }
        encoder.setRenderPipelineState(pipeline.state)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        // Same "unit space fills the target" projection the neutral source
        // capture uses: mesh positions are already normalized to layer units.
        var mvp = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
        encoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.size, index: 1)
        var uniforms = SceneLayerFragmentUniforms.neutral()
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<SceneLayerFragmentUniforms>.size,
            index: 0
        )
        for slot in 0...5 {
            encoder.setFragmentTexture(atlasTexture, index: slot)
        }
        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indices.count,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            return .failure(.gpuExecutionFailed)
        }
        return .success(Output(
            texture: target,
            byteCost: byteCost,
            vertexCount: mesh.vertices.count,
            triangleCount: mesh.triangleCount
        ))
    }
}

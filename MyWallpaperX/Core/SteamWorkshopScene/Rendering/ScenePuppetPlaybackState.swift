import Metal
import simd

final class ScenePuppetPlaybackState {
    private struct SubmissionState {
        var frameSignature: [Int]?
        var nextVertexBufferIndex = 0
    }

    struct Output {
        let state: ScenePuppetPlaybackState
        let texture: MTLTexture
        let byteCost: Int
    }

    enum Failure: Error, CustomStringConvertible {
        case degenerateLayerSize
        case textureTooLarge(width: Int, height: Int)
        case budgetExceeded(requested: Int, remaining: Int)
        case evaluation(ScenePuppetAnimationEvaluationFailure)
        case resourceAllocationFailed

        nonisolated var description: String {
            switch self {
            case .degenerateLayerSize:
                return "degenerate layer size"
            case .textureTooLarge(let width, let height):
                return "animation target \(width)x\(height) exceeds limit"
            case .budgetExceeded(let requested, let remaining):
                return "animation target \(requested) B exceeds remaining budget \(remaining) B"
            case .evaluation(let failure):
                return failure.description
            case .resourceAllocationFailed:
                return "Metal animation resource allocation failed"
            }
        }
    }

    let layerID: Int
    let animationIDs: [Int]

    private let mesh: SceneMdlPuppetMesh
    private let selection: ScenePuppetAnimationSelection
    private let evaluator: ScenePuppetAnimationEvaluator
    private let atlasTexture: MTLTexture
    private let targetTexture: MTLTexture
    private let vertexBuffers: [MTLBuffer]
    private let indexBuffer: MTLBuffer
    private let renderPipelineState: MTLRenderPipelineState
    private let layerWidth: Float
    private let layerHeight: Float
    private let submissions = SceneSourceUpdateStateFIFO(
        initial: SubmissionState()
    )

    static func make(
        layerID: Int,
        mesh: SceneMdlPuppetMesh,
        rig: SceneMdlPuppetRig,
        selection: ScenePuppetAnimationSelection,
        atlasTexture: MTLTexture,
        layerWidth: Float,
        layerHeight: Float,
        remainingByteBudget: Int,
        device: MTLDevice,
        pipeline: SceneImageLayerPipeline
    ) -> Result<Output, Failure> {
        guard layerWidth.isFinite, layerHeight.isFinite,
              layerWidth >= 1, layerHeight >= 1 else {
            return .failure(.degenerateLayerSize)
        }
        let width = Int(layerWidth.rounded())
        let height = Int(layerHeight.rounded())
        guard width <= ScenePuppetMeshRecomposer.maxTextureDimension,
              height <= ScenePuppetMeshRecomposer.maxTextureDimension else {
            return .failure(.textureTooLarge(width: width, height: height))
        }
        let byteCost = width * height * 4
        guard byteCost <= remainingByteBudget else {
            return .failure(.budgetExceeded(requested: byteCost, remaining: remainingByteBudget))
        }

        let evaluator: ScenePuppetAnimationEvaluator
        do {
            evaluator = try ScenePuppetAnimationEvaluator(
                mesh: mesh,
                rig: rig,
                additiveAnimations: selection.composition == .disjointAdditive
                    ? selection.clips.map(\.animation)
                    : []
            )
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            return .failure(.evaluation(failure))
        } catch {
            return .failure(.resourceAllocationFailed)
        }
        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        targetDescriptor.storageMode = .private
        let vertexBufferLength = mesh.vertices.count * MemoryLayout<SceneQuadVertex>.stride
        var indices = mesh.indices
        guard let targetTexture = device.makeTexture(descriptor: targetDescriptor),
              let indexBuffer = device.makeBuffer(
                  bytes: &indices,
                  length: indices.count * MemoryLayout<UInt16>.stride
              ) else {
            return .failure(.resourceAllocationFailed)
        }
        let vertexBuffers = (0..<3).compactMap { _ in
            device.makeBuffer(length: vertexBufferLength)
        }
        guard vertexBuffers.count == 3 else {
            return .failure(.resourceAllocationFailed)
        }
        let state = ScenePuppetPlaybackState(
            layerID: layerID,
            animationIDs: selection.clips.map(\.animation.id),
            mesh: mesh,
            selection: selection,
            evaluator: evaluator,
            atlasTexture: atlasTexture,
            targetTexture: targetTexture,
            vertexBuffers: vertexBuffers,
            indexBuffer: indexBuffer,
            renderPipelineState: pipeline.state,
            layerWidth: layerWidth,
            layerHeight: layerHeight
        )
        return .success(Output(state: state, texture: targetTexture, byteCost: byteCost))
    }

    func encode(
        sceneTime: Double,
        dynamicValues: SceneDynamicSnapshot,
        commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    ) {
        let frameIndices: [Int?] = selection.clips.map { clip in
            guard isVisible(clip.layer, dynamicValues: dynamicValues) else { return nil }
            return ScenePuppetAnimationEvaluator.frameIndex(
                sceneTime: sceneTime,
                rate: clip.layer.rate ?? 1,
                animation: clip.animation
            )
        }
        let signature = frameIndices.map { $0 ?? -1 }
        guard let positions = try? evaluator.deformedPositions(
            selection: selection,
            frameIndices: frameIndices
        ) else { return }

        let vertices = mesh.vertices.indices.map { index in
            SceneQuadVertex(
                position: SIMD2(
                    positions[index].x / layerWidth,
                    positions[index].y / layerHeight
                ),
                texcoord: SIMD2(mesh.vertices[index].u, mesh.vertices[index].v)
            )
        }
        submissions.update(transaction: transaction) { submission in
            guard signature != submission.frameSignature else { return }
            let vertexBuffer = vertexBuffers[submission.nextVertexBufferIndex]
            submission.nextVertexBufferIndex =
                (submission.nextVertexBufferIndex + 1) % vertexBuffers.count
            vertices.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress else { return }
                vertexBuffer.contents().copyMemory(
                    from: source,
                    byteCount: bytes.count
                )
            }

            let passDescriptor = MTLRenderPassDescriptor()
            passDescriptor.colorAttachments[0].texture = targetTexture
            passDescriptor.colorAttachments[0].loadAction = .clear
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0, green: 0, blue: 0, alpha: 0
            )
            passDescriptor.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: passDescriptor
            ) else { return }
            encoder.label = "Puppet animation layer \(layerID) frames \(signature)"
            encoder.setRenderPipelineState(renderPipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            var mvp = SceneMatrix.scale(SIMD3<Float>(2, 2, 1))
            encoder.setVertexBytes(
                &mvp,
                length: MemoryLayout<simd_float4x4>.size,
                index: 1
            )
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
                indexCount: mesh.indices.count,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
            encoder.endEncoding()
            submission.frameSignature = signature
        }
    }

    private func isVisible(
        _ layer: ScenePuppetAnimationLayer,
        dynamicValues: SceneDynamicSnapshot
    ) -> Bool {
        guard layer.visibilityBinding != nil else { return layer.visible == true }
        guard let animationLayerID = layer.id,
              let resolved = dynamicValues[ScenePuppetAnimationPropertyTarget.visibility(
                  layerID: layerID,
                  animationLayerID: animationLayerID
              )],
              case let .bool(visible) = resolved.value else { return false }
        return visible
    }

    private init(
        layerID: Int,
        animationIDs: [Int],
        mesh: SceneMdlPuppetMesh,
        selection: ScenePuppetAnimationSelection,
        evaluator: ScenePuppetAnimationEvaluator,
        atlasTexture: MTLTexture,
        targetTexture: MTLTexture,
        vertexBuffers: [MTLBuffer],
        indexBuffer: MTLBuffer,
        renderPipelineState: MTLRenderPipelineState,
        layerWidth: Float,
        layerHeight: Float
    ) {
        self.layerID = layerID
        self.animationIDs = animationIDs
        self.mesh = mesh
        self.selection = selection
        self.evaluator = evaluator
        self.atlasTexture = atlasTexture
        self.targetTexture = targetTexture
        self.vertexBuffers = vertexBuffers
        self.indexBuffer = indexBuffer
        self.renderPipelineState = renderPipelineState
        self.layerWidth = layerWidth
        self.layerHeight = layerHeight
    }
}

import Metal
import simd

final class ScenePuppetPlaybackState {
    private struct FrameSignature: Equatable {
        let frameA: Int
        let frameB: Int
        let fractionBits: UInt32
        let visible: Bool

        init(
            sample: ScenePuppetAnimationEvaluator.FrameSample?,
            visible: Bool,
            timeInvariant: Bool = false
        ) {
            frameA = timeInvariant ? 0 : (sample?.frameA ?? 0)
            frameB = timeInvariant ? 0 : (sample?.frameB ?? 0)
            fractionBits = timeInvariant ? 0 : (sample?.fraction.bitPattern ?? 0)
            self.visible = visible
        }
    }

    private struct SubmissionState {
        var frameSignature: [FrameSignature]?
        var nextVertexBufferIndex = 0
    }

    struct Output {
        let state: ScenePuppetPlaybackState
        let texture: MTLTexture
        let byteCost: Int
        let coverage: ScenePuppetMeshRecomposer.CoverageExtent
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
            case let .textureTooLarge(width, height):
                return "animation target \(width)x\(height) exceeds limit"
            case let .budgetExceeded(requested, remaining):
                return "animation target \(requested) B exceeds remaining budget \(remaining) B"
            case let .evaluation(failure):
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
    private let coverageWidth: Float
    private let coverageHeight: Float
    /// Reused CPU staging storage. Puppet meshes can contain tens of
    /// thousands of vertices; allocating position and vertex arrays on every
    /// source update was a measurable part of the frame callback cost.
    private var positionScratch: [SIMD2<Float>]
    private var vertexScratch: [SceneQuadVertex]
    /// Matrix storage is also retained across source updates.  Position and
    /// vertex reuse alone still left two bone-count-sized arrays allocated for
    /// every changed frame on large rigs.
    private var localMatrixScratch: [simd_float4x4]
    private var skinMatrixScratch: [simd_float4x4]
    private var scriptBoneOverrides: [Int: simd_float4x4] = [:]
    private var scriptWorldBoneOverrides: [Int: simd_float4x4] = [:]
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
        let evaluator: ScenePuppetAnimationEvaluator
        do {
            evaluator = try ScenePuppetAnimationEvaluator(
                mesh: mesh,
                rig: rig,
                // Prepare every selected clip once.  Layered playback needs
                // the frame-0 reference pose for additive deltas as well as
                // the absolute tracks; neither is rebuilt on a normal frame.
                additiveAnimations: selection.clips.map(\.animation)
            )
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            return .failure(.evaluation(failure))
        } catch {
            return .failure(.resourceAllocationFailed)
        }
        // The render target is reused for every animated pose. Include the
        // selected clips' authored frame poses and interval midpoints in the
        // load-time coverage so a limb that swings outside the bind pose
        // cannot be clipped by the fixed target extent.
        var animatedMaxAbs = SIMD2<Float>(repeating: 0)
        func record(_ bounds: SIMD2<Float>) {
            animatedMaxAbs.x = max(animatedMaxAbs.x, bounds.x)
            animatedMaxAbs.y = max(animatedMaxAbs.y, bounds.y)
        }
        let baselineSamples = selection.clips.map { _ in
            ScenePuppetAnimationEvaluator.FrameSample(frameA: 0, frameB: 0)
        }
        var coverageSamples: [[ScenePuppetAnimationEvaluator.FrameSample?]] = []
        for (clipIndex, clip) in selection.clips.enumerated() {
            let frameCount = clip.animation.frameCount
            guard frameCount >= 0 else {
                return .failure(.evaluation(.invalidFrame(0)))
            }
            // Keep preparation bounded for malformed-but-accepted long clips
            // while retaining both endpoints and a representative interval
            // sample for every sampled segment.
            let frameStride = max(1, Int(ceil(Double(frameCount) / 512.0)))
            var sampledFrames = Array(stride(from: 0, through: frameCount, by: frameStride))
            if sampledFrames.last != frameCount { sampledFrames.append(frameCount) }
            for frame in sampledFrames {
                var samples = baselineSamples
                samples[clipIndex] = ScenePuppetAnimationEvaluator.FrameSample(
                    frameA: frame,
                    frameB: frame
                )
                coverageSamples.append(samples)
                guard frame < frameCount else { continue }
                let nextFrame = min(frame + frameStride, frameCount)
                guard nextFrame > frame else { continue }
                samples[clipIndex] = ScenePuppetAnimationEvaluator.FrameSample(
                    frameA: frame,
                    frameB: nextFrame,
                    fraction: 0.5
                )
                coverageSamples.append(samples)
            }
        }
        do {
            record(try evaluator.conservativeMaxAbsDeformedPosition(
                selection: selection,
                frameSamplesBatch: coverageSamples
            ))
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            return .failure(.evaluation(failure))
        } catch {
            return .failure(.resourceAllocationFailed)
        }
        guard let coverage = ScenePuppetMeshRecomposer.coverageExtent(
            mesh: mesh,
            layerWidth: layerWidth,
            layerHeight: layerHeight,
            additionalPositions: [
                SIMD2(animatedMaxAbs.x, 0),
                SIMD2(0, animatedMaxAbs.y),
            ]
        ) else {
            return .failure(.degenerateLayerSize)
        }
        guard let dimensions = ScenePuppetMeshRecomposer.targetDimensions(
            layerWidth: coverage.width,
            layerHeight: coverage.height,
            byteBudget: remainingByteBudget
        ) else {
            return .failure(.textureTooLarge(
                width: Int(coverage.width.rounded()),
                height: Int(coverage.height.rounded())
            ))
        }
        let width = dimensions.width
        let height = dimensions.height
        let byteCost = width * height * 4
        guard byteCost <= remainingByteBudget else {
            return .failure(.budgetExceeded(requested: byteCost, remaining: remainingByteBudget))
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
              )
        else {
            return .failure(.resourceAllocationFailed)
        }
        let vertexBuffers = (0 ..< 3).compactMap { _ in
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
            coverageWidth: coverage.width,
            coverageHeight: coverage.height
        )
        return .success(Output(
            state: state,
            texture: targetTexture,
            byteCost: byteCost,
            coverage: coverage
        ))
    }

    func encode(
        sceneTime: Double,
        dynamicValues: SceneDynamicSnapshot,
        commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    ) {
        let frameSamples: [ScenePuppetAnimationEvaluator.FrameSample?] = selection.clips.map { clip in
            guard isVisible(clip.layer, dynamicValues: dynamicValues) else { return nil }
            return ScenePuppetAnimationEvaluator.frameSample(
                sceneTime: sceneTime,
                rate: clip.layer.rate ?? 1,
                animation: clip.animation
            )
        }
        let signature = frameSamples.enumerated().map { index, sample in
            FrameSignature(
                sample: sample,
                visible: sample != nil,
                timeInvariant: evaluator.isTimeInvariant(
                    animationID: selection.clips[index].animation.id
                )
            )
        }
        submissions.update(transaction: transaction) { submission in
            guard signature != submission.frameSignature else { return }
            // Keep the expensive CPU skinning behind the frame signature
            // guard. At display rates a source frame commonly repeats; the
            // old order rebuilt every vertex array before discovering that
            // no new GPU submission was needed.
            let evaluated = positionScratch.withUnsafeMutableBufferPointer {
                positions in
                (try? evaluator.writeDeformedPositions(
                    selection: selection,
                    frameSamples: frameSamples,
                    into: positions,
                    localMatricesScratch: &localMatrixScratch,
                    skinMatricesScratch: &skinMatrixScratch,
                    boneOverrides: scriptBoneOverrides,
                    worldBoneOverrides: scriptWorldBoneOverrides
                )) != nil
            }
            guard evaluated else { return }
            for index in mesh.vertices.indices {
                let position = positionScratch[index]
                vertexScratch[index] = SceneQuadVertex(
                    position: SIMD2(
                        position.x / coverageWidth,
                        position.y / coverageHeight
                    ),
                    texcoord: SIMD2(mesh.vertices[index].u, mesh.vertices[index].v)
                )
            }
            let vertexBuffer = vertexBuffers[submission.nextVertexBufferIndex]
            submission.nextVertexBufferIndex =
                (submission.nextVertexBufferIndex + 1) % vertexBuffers.count
            vertexScratch.withUnsafeBytes { bytes in
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
            for slot in 0 ... 5 {
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

    func apply(scriptBoneMutations: [SceneScriptPuppetBoneMutation]) {
        guard scriptBoneMutations.contains(where: { $0.layerID == layerID }) else { return }
        var next = scriptBoneOverrides
        for mutation in scriptBoneMutations where mutation.layerID == layerID {
            guard mutation.boneIndex > 0, mutation.matrix.count == 16 else { continue }
            let columns = stride(from: 0, to: 16, by: 4).map { offset in
                SIMD4<Float>(Float(mutation.matrix[offset]), Float(mutation.matrix[offset + 1]), Float(mutation.matrix[offset + 2]), Float(mutation.matrix[offset + 3]))
            }
            if mutation.localSpace {
                next[mutation.boneIndex - 1] = simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3]))
            } else {
                scriptWorldBoneOverrides[mutation.boneIndex - 1] = simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3]))
            }
        }
        scriptBoneOverrides = next
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
        coverageWidth: Float,
        coverageHeight: Float
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
        self.coverageWidth = coverageWidth
        self.coverageHeight = coverageHeight
        self.positionScratch = Array(
            repeating: SIMD2<Float>.zero,
            count: mesh.vertices.count
        )
        self.vertexScratch = mesh.vertices.map { vertex in
            SceneQuadVertex(
                position: .zero,
                texcoord: SIMD2(vertex.u, vertex.v)
            )
        }
        let matrixScratchCount = evaluator.boneCount
        self.localMatrixScratch = Array(
            repeating: matrix_identity_float4x4,
            count: matrixScratchCount
        )
        self.skinMatrixScratch = Array(
            repeating: matrix_identity_float4x4,
            count: matrixScratchCount
        )
    }
}

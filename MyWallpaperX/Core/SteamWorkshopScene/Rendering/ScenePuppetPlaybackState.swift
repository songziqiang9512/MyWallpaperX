import Metal
import simd

final class ScenePuppetPlaybackState {
    private struct FrameSignature: Equatable {
        let frameA: Int
        let frameB: Int
        let fractionBits: UInt32
        let visible: Bool
        let boneRevision: UInt64

        init(
            sample: ScenePuppetAnimationEvaluator.FrameSample?,
            visible: Bool,
            timeInvariant: Bool = false,
            boneRevision: UInt64 = 0
        ) {
            frameA = timeInvariant ? 0 : (sample?.frameA ?? 0)
            frameB = timeInvariant ? 0 : (sample?.frameB ?? 0)
            fractionBits = timeInvariant ? 0 : (sample?.fraction.bitPattern ?? 0)
            self.visible = visible
            self.boneRevision = boneRevision
        }
    }

    private struct SubmissionState {
        var frameSignature: [FrameSignature]?
        var boneRevision: UInt64?
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
    var meshCoverageSize: SIMD2<Float> {
        SIMD2(coverageWidth, coverageHeight)
    }

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
    private var worldMatrixScratch: [simd_float4x4]
    private var scriptBoneOverrides: [Int: ScenePuppetBoneOverride] = [:]
#if DEBUG
    private var recordedBoneSkin = false
    private let boneEvidence = ScenePuppetBoneEvidence()
    private var boneWrittenInFrame = false
#endif
    private var boneRevision: UInt64 = 0
    private var translationMotions: [Int: ScenePuppetTranslationMotion] = [:]
    private var boneFrameBaseline: (overrides: [Int: ScenePuppetBoneOverride], revision: UInt64,
        motions: [Int: ScenePuppetTranslationMotion])?
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
                ),
                boneRevision: boneRevision
            )
        }
        submissions.update(transaction: transaction) { submission in
            guard signature != submission.frameSignature
                    || submission.boneRevision != boneRevision else { return }
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
                    worldMatricesScratch: &worldMatrixScratch,
                    boneOverrides: scriptBoneOverrides
                )) != nil
            }
            guard evaluated else { return }
#if DEBUG
            if boneRevision > 0, !recordedBoneSkin,
               SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                recordedBoneSkin = true
                let displacement = zip(positionScratch, mesh.vertices).reduce(Float(0)) {
                    max($0, simd_length($1.0 - SIMD2($1.1.x, $1.1.y)))
                }
                NSLog("MWX DEBUG SCENE: phase=puppet-bone-skin layer=%d revision=%llu vertices=%d maxBindDisplacement=%.6f",
                    layerID, boneRevision, positionScratch.count, displacement)
            }
#endif
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
            submission.boneRevision = boneRevision
        }
#if DEBUG
        if ScenePuppetBoneEvidence.isEnabled(for: layerID) {
        boneEvidence.record(layerID: layerID, revision: boneRevision,
            frame: dynamicValues.frameIndex, sceneTime: sceneTime,
            scriptWritten: boneWrittenInFrame,
            displacement: zip(positionScratch, mesh.vertices).reduce(Float(0)) {
                max($0, simd_length($1.0 - SIMD2($1.1.x, $1.1.y)))
            }, texture: targetTexture, commandBuffer: commandBuffer)
        }
#endif
    }

    /// Returns the current animated pose for SceneScript getters. This uses
    /// the same launch-selected clips and persistent override map as encode,
    /// so getters observe animation pose rather than a stale bind snapshot.
    func boneConfiguration(
        sceneTime: Double,
        dynamicValues: SceneDynamicSnapshot
    ) -> ScenePuppetLayerLoad.BoneConfiguration? {
        let frameSamples: [ScenePuppetAnimationEvaluator.FrameSample?] =
            selection.clips.map { clip in
                guard isVisible(clip.layer, dynamicValues: dynamicValues) else {
                    return nil
                }
                return ScenePuppetAnimationEvaluator.frameSample(
                    sceneTime: sceneTime,
                    rate: clip.layer.rate ?? 1,
                    animation: clip.animation
                )
            }
        guard let transforms = try? evaluator.boneTransforms(
            selection: selection,
            frameSamples: frameSamples,
            boneOverrides: scriptBoneOverrides
        ) else { return nil }
        func flatten(_ matrix: simd_float4x4) -> [Double] {
            [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
                .flatMap { [Double($0.x), Double($0.y), Double($0.z), Double($0.w)] }
        }
        return ScenePuppetLayerLoad.BoneConfiguration(
            names: evaluator.boneNames,
            parentIndices: evaluator.boneParentIndices,
            worldMatrices: transforms.world.flatMap(flatten),
            localMatrices: transforms.local.flatMap(flatten)
        )
    }

    /// The authored pose/physics is evaluated before callbacks each frame;
    /// scripts may replace that result only for the frame they write.
    func advanceBonePhysics(sceneTime: Double, deltaTime: Double,
                            dynamicValues: SceneDynamicSnapshot) {
#if DEBUG
        boneWrittenInFrame = false
#endif
        guard evaluator.rig.bones.contains(where: { $0.translationPhysics != nil }) else { return }
        if boneFrameBaseline == nil {
            boneFrameBaseline = (scriptBoneOverrides, boneRevision, translationMotions)
        }
        let samples = selection.clips.map { clip in
            isVisible(clip.layer, dynamicValues: dynamicValues)
                ? ScenePuppetAnimationEvaluator.frameSample(sceneTime: sceneTime,
                    rate: clip.layer.rate ?? 1, animation: clip.animation) : nil
        }
        guard let base = try? evaluator.boneTransforms(selection: selection, frameSamples: samples)
        else { return }
        for (index, bone) in evaluator.rig.bones.enumerated() {
            guard let configuration = bone.translationPhysics else { continue }
            var pose = base.local[index]
            if case let .local(override) = scriptBoneOverrides[index] { pose = override }
            let target = SIMD3(base.local[index].columns.3.x,
                base.local[index].columns.3.y, base.local[index].columns.3.z)
            let position = SIMD3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z)
            var motion = translationMotions[index] ?? .init()
            let next = motion.advance(position: position, target: target,
                deltaTime: deltaTime, configuration: configuration)
            translationMotions[index] = motion
            if next != position {
                pose.columns.3 = SIMD4(next, 1)
                scriptBoneOverrides[index] = .local(pose)
                boneRevision &+= 1
            }
        }
    }

    func apply(scriptBoneMutations: [SceneScriptPuppetBoneMutation]) {
        guard scriptBoneMutations.contains(where: { $0.layerID == layerID }) else { return }
        if boneFrameBaseline == nil { boneFrameBaseline = (scriptBoneOverrides, boneRevision, translationMotions) }
        var next = scriptBoneOverrides
        var accepted = false
        for mutation in scriptBoneMutations where mutation.layerID == layerID {
            guard mutation.boneIndex >= 0,
                  mutation.boneIndex < evaluator.boneCount,
                  mutation.matrix.count == 16,
                  mutation.matrix.allSatisfy(\.isFinite) else { continue }
            let values = mutation.matrix.map(Float.init)
            guard values.allSatisfy(\.isFinite) else { continue }
            let columns = stride(from: 0, to: 16, by: 4).map { offset in
                SIMD4<Float>(values[offset], values[offset + 1], values[offset + 2], values[offset + 3])
            }
            let matrix = simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3]))
            if mutation.localSpace {
                next[mutation.boneIndex] = .local(matrix)
            } else {
                next[mutation.boneIndex] = .world(matrix)
            }
            translationMotions[mutation.boneIndex]?.velocity = .zero
#if DEBUG
            boneWrittenInFrame = true
#endif
            accepted = true
        }
        scriptBoneOverrides = next
        if accepted { boneRevision &+= 1 }
    }

    func commitBoneFrame() { boneFrameBaseline = nil }

    func discardBoneFrame() {
        if let baseline = boneFrameBaseline {
            scriptBoneOverrides = baseline.overrides
            boneRevision = baseline.revision
            translationMotions = baseline.motions
        }
        boneFrameBaseline = nil
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
        self.worldMatrixScratch = Array(
            repeating: matrix_identity_float4x4,
            count: matrixScratchCount
        )
    }
}

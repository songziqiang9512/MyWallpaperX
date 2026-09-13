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
        var attachmentFrames: [String: simd_float4x4] = [:]
    }

    struct Output {
        let state: ScenePuppetPlaybackState
        let product: SceneGeometryProduct
    }

    struct PoseConfiguration {
        let bones: ScenePuppetLayerLoad.BoneConfiguration
        let attachmentFrames: [String: simd_float4x4]
    }

    enum Failure: Error, CustomStringConvertible {
        case degenerateLayerSize
        case evaluation(ScenePuppetAnimationEvaluationFailure)
        case resourceAllocationFailed

        nonisolated var description: String {
            switch self {
            case .degenerateLayerSize:
                return "degenerate layer size"
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
    private let attachments: [SceneMdlPuppetAttachment]
    private let atlasTexture: MTLTexture
    private let vertexBuffers: [MTLBuffer]
    private let indexBuffer: MTLBuffer
    private let renderPipelineState: MTLRenderPipelineState
    private let authoredSize: SIMD2<Float>
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
    /// Clip topology is launch-stable; reuse the per-frame sample/signature
    /// containers so source updates do not allocate before the change guard.
    private var frameSamplesScratch: [ScenePuppetAnimationEvaluator.FrameSample?]
    private var signatureScratch: [FrameSignature]
    private var lastPreparedVertexBufferIndex = 0
    private var scriptBoneOverrides: [Int: ScenePuppetBoneOverride] = [:]
#if DEBUG
    private var recordedBoneSkin = false
    private var recordedWorldDraw = false
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
        attachments: [SceneMdlPuppetAttachment],
        atlasTexture: MTLTexture,
        layerWidth: Float,
        layerHeight: Float,
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
        guard layerWidth.isFinite, layerHeight.isFinite,
              layerWidth >= 1, layerHeight >= 1 else {
            return .failure(.degenerateLayerSize)
        }
        let vertexBufferLength = mesh.vertices.count * MemoryLayout<SceneQuadVertex>.stride
        var indices = mesh.indices
        guard let indexBuffer = device.makeBuffer(
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
            attachments: attachments,
            atlasTexture: atlasTexture,
            vertexBuffers: vertexBuffers,
            indexBuffer: indexBuffer,
            renderPipelineState: pipeline.state,
            authoredSize: SIMD2(layerWidth, layerHeight)
        )
        return .success(Output(
            state: state,
            product: state.geometryProduct()
        ))
    }

    func encode(
        sceneTime: Double,
        dynamicValues: SceneDynamicSnapshot,
        commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    ) -> [String: simd_float4x4] {
        for index in selection.clips.indices {
            let clip = selection.clips[index]
            frameSamplesScratch[index] = isVisible(
                clip.layer, dynamicValues: dynamicValues
            ) ? ScenePuppetAnimationEvaluator.frameSample(
                sceneTime: sceneTime,
                rate: clip.layer.rate ?? 1,
                animation: clip.animation
            ) : nil
            signatureScratch[index] = FrameSignature(
                sample: frameSamplesScratch[index],
                visible: frameSamplesScratch[index] != nil,
                timeInvariant: evaluator.isTimeInvariant(
                    animationID: clip.animation.id
                ),
                boneRevision: boneRevision
            )
        }
        let frameSamples = frameSamplesScratch
        let signature = signatureScratch
        let attachmentFrames = submissions.update(transaction: transaction) { submission in
            guard signature != submission.frameSignature
                    || submission.boneRevision != boneRevision else {
                return submission.attachmentFrames
            }
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
            guard evaluated else { return submission.attachmentFrames }
            if let frames = ScenePuppetAttachmentPoseProjection.frames(
                attachments: attachments,
                boneWorldMatrices: worldMatrixScratch
            ) {
                submission.attachmentFrames = frames
            }
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
                    position: position,
                    texcoord: SIMD2(mesh.vertices[index].u, mesh.vertices[index].v)
                )
            }
            let vertexBuffer = vertexBuffers[submission.nextVertexBufferIndex]
            lastPreparedVertexBufferIndex = submission.nextVertexBufferIndex
            submission.nextVertexBufferIndex =
                (submission.nextVertexBufferIndex + 1) % vertexBuffers.count
            vertexScratch.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress else { return }
                vertexBuffer.contents().copyMemory(
                    from: source,
                    byteCount: bytes.count
                )
            }

            submission.frameSignature = signature
            submission.boneRevision = boneRevision
            return submission.attachmentFrames
        }
#if DEBUG
        if ScenePuppetBoneEvidence.isEnabled(for: layerID) {
        boneEvidence.record(layerID: layerID, revision: boneRevision,
            frame: dynamicValues.frameIndex, sceneTime: sceneTime,
            scriptWritten: boneWrittenInFrame,
            displacement: zip(positionScratch, mesh.vertices).reduce(Float(0)) {
                max($0, simd_length($1.0 - SIMD2($1.1.x, $1.1.y)))
            }, positions: positionScratch, commandBuffer: commandBuffer)
        }
#endif
        return attachmentFrames
    }

    func geometryProduct() -> SceneGeometryProduct {
        SceneGeometryProduct(encode: {
            [self] encoder, sourceTexture, dependencyTexture, mvp, uniforms,
            bindColorBlend in
#if DEBUG
            if !recordedWorldDraw,
               SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                recordedWorldDraw = true
                var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
                var maximum = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
                var visibleVertexCount = 0
                for position in positionScratch {
                    let clip = mvp * SIMD4(
                        position.x,
                        position.y,
                        0,
                        1
                    )
                    guard clip.w.isFinite, abs(clip.w) > .ulpOfOne else { continue }
                    let ndc = SIMD2(clip.x / clip.w, clip.y / clip.w)
                    guard ndc.x.isFinite, ndc.y.isFinite else { continue }
                    minimum = simd_min(minimum, ndc)
                    maximum = simd_max(maximum, ndc)
                    if abs(ndc.x) <= 1, abs(ndc.y) <= 1 {
                        visibleVertexCount += 1
                    }
                }
                NSLog(
                    "MWX DEBUG SCENE: phase=puppet-world-draw layer=%d ndcMin=%.6f,%.6f ndcMax=%.6f,%.6f visibleVertices=%d totalVertices=%d",
                    layerID, minimum.x, minimum.y, maximum.x, maximum.y,
                    visibleVertexCount, positionScratch.count
                )
            }
#endif
            if let bindColorBlend {
                bindColorBlend(encoder, sourceTexture, mvp)
            } else {
                encoder.setRenderPipelineState(renderPipelineState)
                var matrix = mvp
                encoder.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.size, index: 1)
                var uniforms = uniforms
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneLayerFragmentUniforms>.size, index: 0)
                encoder.setFragmentTexture(sourceTexture, index: 0)
                encoder.setFragmentTexture(dependencyTexture ?? sourceTexture, index: 1)
            }
            encoder.setVertexBuffer(vertexBuffers[lastPreparedVertexBufferIndex], offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indices.count,
                indexType: .uint16, indexBuffer: indexBuffer, indexBufferOffset: 0)
            return true
        }, authoredSize: authoredSize,
        effectSourceExtentContract: .exactSamplingTexture)
    }

    /// Returns the current animated pose for SceneScript getters. This uses
    /// the same launch-selected clips and persistent override map as encode,
    /// so getters observe animation pose rather than a stale bind snapshot.
    func boneConfiguration(
        sceneTime: Double,
        dynamicValues: SceneDynamicSnapshot
    ) -> ScenePuppetLayerLoad.BoneConfiguration? {
        poseConfiguration(
            sceneTime: sceneTime,
            dynamicValues: dynamicValues
        )?.bones
    }

    /// Evaluates one typed current pose for the pre-script frame snapshot.
    /// Bone handles, animated attachments and cursor/world projections all
    /// consume this result instead of evaluating independent hierarchies.
    func poseConfiguration(
        sceneTime: Double,
        dynamicValues: SceneDynamicSnapshot
    ) -> PoseConfiguration? {
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
        let bones = ScenePuppetLayerLoad.BoneConfiguration(
            names: evaluator.boneNames,
            parentIndices: evaluator.boneParentIndices,
            worldMatrices: transforms.world.flatMap(flatten),
            localMatrices: transforms.local.flatMap(flatten)
        )
        return PoseConfiguration(
            bones: bones,
            attachmentFrames: ScenePuppetAttachmentPoseProjection.frames(
                attachments: attachments,
                boneWorldMatrices: transforms.world
            ) ?? [:]
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
        attachments: [SceneMdlPuppetAttachment],
        atlasTexture: MTLTexture,
        vertexBuffers: [MTLBuffer],
        indexBuffer: MTLBuffer,
        renderPipelineState: MTLRenderPipelineState,
        authoredSize: SIMD2<Float>
    ) {
        self.layerID = layerID
        self.animationIDs = animationIDs
        self.mesh = mesh
        self.selection = selection
        self.evaluator = evaluator
        self.attachments = attachments
        self.atlasTexture = atlasTexture
        self.vertexBuffers = vertexBuffers
        self.indexBuffer = indexBuffer
        self.renderPipelineState = renderPipelineState
        self.authoredSize = authoredSize
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
        self.frameSamplesScratch = Array(
            repeating: nil, count: selection.clips.count
        )
        self.signatureScratch = Array(
            repeating: FrameSignature(sample: nil, visible: false),
            count: selection.clips.count
        )
    }
}

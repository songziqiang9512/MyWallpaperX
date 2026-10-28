import Metal
import simd

final class ScenePuppetPlaybackState {
    private struct FrameSignature: Equatable {
        let frameA: Int
        let frameB: Int
        let fractionBits: UInt32
        let visible: Bool
        let boneRevision: UInt64
        let blend: Double

        init(
            sample: ScenePuppetAnimationEvaluator.FrameSample?,
            visible: Bool,
            timeInvariant: Bool = false,
            boneRevision: UInt64 = 0,
            blend: Double = 1
        ) {
            frameA = timeInvariant ? 0 : (sample?.frameA ?? 0)
            frameB = timeInvariant ? 0 : (sample?.frameB ?? 0)
            fractionBits = timeInvariant ? 0 : (sample?.fraction.bitPattern ?? 0)
            self.visible = visible
            self.boneRevision = boneRevision
            self.blend = blend
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
        let queryLocalMatrices: [Double]
        let attachmentFrames: [String: simd_float4x4]
        let meshToWorld: simd_float4x4
    }

    enum Failure: Error, CustomStringConvertible {
        case degenerateLayerSize
        case evaluation(ScenePuppetAnimationEvaluationFailure)
        case resourceAllocationFailed
        case directModelVertexCountMismatch
        case directAttachmentBasisUnqualified
        case directModelStream(SceneStaticModelVertexStream.Failure)

        nonisolated var description: String {
            switch self {
            case .degenerateLayerSize:
                return "degenerate layer size"
            case let .evaluation(failure):
                return failure.description
            case .resourceAllocationFailed:
                return "Metal animation resource allocation failed"
            case .directAttachmentBasisUnqualified:
                return "direct model attachment basis is unqualified"
            case .directModelVertexCountMismatch:
                return "direct model bind/evaluator vertex counts do not match"
            case let .directModelStream(failure):
                return "direct model vertex stream: \(failure.rawValue)"
            }
        }
    }

    /// Geometry storage is per layer/surface; pose, clocks and script state stay
    /// on this PlaybackState for both sinks.
    final class ImageGeometry {
        let clipping: ScenePuppetClipping?
        let mesh: SceneMdlPuppetMesh
        let atlasTexture: MTLTexture
        let vertexBuffers: [MTLBuffer]
        let indexBuffer: MTLBuffer
        let renderPipelineState: MTLRenderPipelineState
        let authoredSize: SIMD2<Float>
        let hasBoneAlpha: Bool
        var positionScratch: [SIMD2<Float>]
        var vertexScratch: [SceneQuadVertex]
        var coverageScratch: [Float]
        var boneAlphaScratch: [Float]

        init(mesh: SceneMdlPuppetMesh, atlasTexture: MTLTexture,
             vertexBuffers: [MTLBuffer], indexBuffer: MTLBuffer,
             renderPipelineState: MTLRenderPipelineState, authoredSize: SIMD2<Float>,
             clipping: ScenePuppetClipping?, evaluator: ScenePuppetAnimationEvaluator,
             selection: ScenePuppetAnimationSelection) {
            self.mesh = mesh
            self.atlasTexture = atlasTexture
            self.vertexBuffers = vertexBuffers
            self.indexBuffer = indexBuffer
            self.renderPipelineState = renderPipelineState
            self.authoredSize = authoredSize
            self.clipping = clipping
            hasBoneAlpha = selection.clips.contains {
                evaluator.hasAlphaContribution(animationID: $0.animation.id)
            }
            positionScratch = Array(repeating: .zero, count: mesh.vertices.count)
            coverageScratch = Array(repeating: 1, count: mesh.vertices.count)
            boneAlphaScratch = Array(repeating: 1, count: evaluator.boneCount)
            vertexScratch = mesh.vertices.map {
                SceneQuadVertex(position: .zero, texcoord: SIMD2($0.u, $0.v))
            }
        }
    }

    enum Geometry {
        case image(ImageGeometry)
        case direct(DirectModelGeometry)
    }

    let layerID: Int
    let animationIDs: [Int]
    let selection: ScenePuppetAnimationSelection
    let geometry: Geometry
    private let evaluator: ScenePuppetAnimationEvaluator
    private let attachments: [SceneMdlPuppetAttachment]
    /// The evaluator's rig is immutable; script edits change pose, not physics membership.
    let hasTranslationPhysics: Bool
    var hasAttachments: Bool { !attachments.isEmpty }

    var isDirectModel: Bool {
        if case .direct = geometry { return true }
        return false
    }
    /// Matrix storage is also retained across source updates.  Position and
    /// vertex reuse alone still left two bone-count-sized arrays allocated for
    /// every changed frame on large rigs.
    private var localMatrixScratch: [simd_float4x4]
    private var skinMatrixScratch: [simd_float4x4]
    private var worldMatrixScratch: [simd_float4x4]
    /// Clip topology is launch-stable; reuse signatures while the launch-owned
    /// playback runtime supplies the shared frame samples.
    private var signatureScratch: [FrameSignature]
    private var preparedFrameSignature: [FrameSignature]?
    private var preparedBoneRevision: UInt64?
    private var preparedAttachmentFrames: [String: simd_float4x4] = [:]
    private var lastPreparedVertexBufferIndex: Int?
    private weak var preparedPublicationCommandBuffer: MTLCommandBuffer?
    private var renderBoneOverrides: [Int: simd_float4x4] = [:]
    /// Translation-only query overlay. Physical translation continues in the
    /// render pose after this overlay expires at the next simulation cadence.
    private var queryBoneOrigins: [Int: SIMD3<Float>] = [:]
    private var lastBonePhysicsFrameIndex: UInt64?
#if DEBUG
    private var recordedBoneSkin = false
    private var recordedWorldDraw = false
    private let boneEvidence = ScenePuppetBoneEvidence()
    private var boneWrittenInFrame = false
#endif
    private var boneRevision: UInt64 = 0
    private var translationMotions: [Int: ScenePuppetTranslationMotion] = [:]
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
        pipeline: SceneImageLayerPipeline,
        clipping: ScenePuppetClipping? = nil
    ) -> Result<Output, Failure> {
        let evaluator: ScenePuppetAnimationEvaluator
        do {
            evaluator = try ScenePuppetAnimationEvaluator(
                mesh: mesh,
                rig: rig,
                // Prepare selected absolute tracks once. Weight mixing shares
                // the evaluator's bind poses; normal frames do not rebuild tracks.
                additiveAnimations: selection.clips.map(\.animation)
            )
        } catch let failure as ScenePuppetAnimationEvaluationFailure {
            return .failure(.evaluation(failure))
        } catch {
            return .failure(.resourceAllocationFailed)
        }
        return make(
            layerID: layerID, mesh: mesh, evaluator: evaluator,
            selection: selection, attachments: attachments,
            atlasTexture: atlasTexture, layerWidth: layerWidth,
            layerHeight: layerHeight, device: device, pipeline: pipeline,
            clipping: clipping
        )
    }

    /// A prepared pose can be instantiated for more than one layer or surface.
    /// Only immutable evaluation data is shared; all CPU staging, bone state,
    /// GPU buffers and submission state below belong to the new instance.
    static func make(
        layerID: Int,
        mesh: SceneMdlPuppetMesh,
        evaluator: ScenePuppetAnimationEvaluator,
        selection: ScenePuppetAnimationSelection,
        attachments: [SceneMdlPuppetAttachment],
        atlasTexture: MTLTexture,
        layerWidth: Float,
        layerHeight: Float,
        device: MTLDevice,
        pipeline: SceneImageLayerPipeline,
        clipping: ScenePuppetClipping? = nil
    ) -> Result<Output, Failure> {
        guard layerWidth.isFinite, layerHeight.isFinite,
              layerWidth >= 1, layerHeight >= 1 else {
            return .failure(.degenerateLayerSize)
        }
        let vertexBufferLength = mesh.vertices.count * MemoryLayout<SceneQuadVertex>.stride
        var indices = mesh.indices
        guard let indexBuffer = device.makeSceneBuffer(
                  bytes: &indices,
                  length: indices.count * MemoryLayout<UInt16>.stride
              )
        else {
            return .failure(.resourceAllocationFailed)
        }
        let vertexBuffers = (0 ..< 3).compactMap { _ in
            device.makeSceneBuffer(length: vertexBufferLength)
        }
        guard vertexBuffers.count == 3 else {
            return .failure(.resourceAllocationFailed)
        }
        let image = ImageGeometry(mesh: mesh, atlasTexture: atlasTexture,
            vertexBuffers: vertexBuffers, indexBuffer: indexBuffer,
            renderPipelineState: pipeline.state, authoredSize: SIMD2(layerWidth, layerHeight),
            clipping: clipping, evaluator: evaluator, selection: selection)
        let state = ScenePuppetPlaybackState(layerID: layerID, geometry: .image(image),
            selection: selection, evaluator: evaluator, attachments: attachments)
        return .success(Output(state: state, product: state.geometryProduct(image: image)))
    }

    /// CPU pose preparation belongs to the simulation frame. Missing drawables
    /// never stop bone physics or leave child world transforms on an old pose.
    @discardableResult
    func prepareFrame(
        animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame
    ) -> [String: simd_float4x4] {
        let frameSamples = animationFrame.samples
        guard frameSamples.count == selection.clips.count else {
            if case let .direct(direct) = geometry {
                direct.useBindFallback(.invalidFrame)
                preparedFrameSignature = nil
                preparedBoneRevision = nil
                preparedAttachmentFrames = [:]
            }
            return preparedAttachmentFrames
        }
        if case let .direct(direct) = geometry,
           let blends = animationFrame.blends, blends.count != frameSamples.count {
            direct.useBindFallback(.invalidFrame)
            preparedFrameSignature = nil
            preparedBoneRevision = nil
            preparedAttachmentFrames = [:]
            return preparedAttachmentFrames
        }
        for index in selection.clips.indices {
            let clip = selection.clips[index]
            signatureScratch[index] = FrameSignature(
                sample: frameSamples[index],
                visible: frameSamples[index] != nil,
                timeInvariant: evaluator.isTimeInvariant(
                    animationID: clip.animation.id
                ),
                boneRevision: boneRevision,
                blend: animationFrame.blends?[index] ?? clip.layer.blend ?? 1
            )
        }
        let signature = signatureScratch
        guard signature != preparedFrameSignature || boneRevision != preparedBoneRevision else {
            return preparedAttachmentFrames
        }
        // Keep the expensive CPU skinning behind the frame signature
        // guard. At display rates a source frame commonly repeats; the
        // old order rebuilt every vertex array before discovering that
        // no new GPU submission was needed.
        switch geometry {
        case let .direct(direct):
            let hasCurrentWorld = direct.prepare(evaluator: evaluator, selection: selection,
                animationFrame: animationFrame, boneOverrides: renderBoneOverrides,
                localMatrices: &localMatrixScratch, skinMatrices: &skinMatrixScratch,
                worldMatrices: &worldMatrixScratch)
            preparedAttachmentFrames = hasCurrentWorld
                ? (ScenePuppetAttachmentPoseProjection.frames(attachments: attachments,
                    boneWorldMatrices: worldMatrixScratch) ?? [:]) : [:]
        case let .image(image):
            let evaluated = image.positionScratch.withUnsafeMutableBufferPointer {
                positions in
                (try? evaluator.writeDeformedPositions(
                    selection: selection,
                    frameSamples: frameSamples,
                    into: positions,
                    localMatricesScratch: &localMatrixScratch,
                    skinMatricesScratch: &skinMatrixScratch,
                    worldMatricesScratch: &worldMatrixScratch,
                    boneOverrides: renderBoneOverrides,
                    blends: animationFrame.blends
                )) != nil
            }
            guard evaluated else { return preparedAttachmentFrames }
            if image.hasBoneAlpha {
                do {
                    try evaluator.writeVertexCoverages(
                        selection: selection, frameSamples: frameSamples,
                        blends: animationFrame.blends,
                        into: &image.coverageScratch, boneScratch: &image.boneAlphaScratch
                    )
                } catch { return preparedAttachmentFrames }
            }
            if let frames = ScenePuppetAttachmentPoseProjection.frames(
                attachments: attachments,
                boneWorldMatrices: worldMatrixScratch
            ) {
                preparedAttachmentFrames = frames
            }
    #if DEBUG
            if boneRevision > 0, !recordedBoneSkin,
               SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                recordedBoneSkin = true
                let displacement = zip(image.positionScratch, image.mesh.vertices).reduce(Float(0)) {
                    max($0, simd_length($1.0 - SIMD2($1.1.x, $1.1.y)))
                }
                NSLog("MWX DEBUG SCENE: phase=puppet-bone-skin layer=%d revision=%llu vertices=%d maxBindDisplacement=%.6f",
                    layerID, boneRevision, image.positionScratch.count, displacement)
            }
    #endif
            for index in image.mesh.vertices.indices {
                let position = image.positionScratch[index]
                image.vertexScratch[index] = SceneQuadVertex(
                    position: position,
                    texcoord: SIMD2(image.mesh.vertices[index].u, image.mesh.vertices[index].v),
                    vertexCoverage: image.coverageScratch[index]
                )
            }
        }
        preparedFrameSignature = signature
        preparedBoneRevision = boneRevision
        return preparedAttachmentFrames
    }

    /// Sampling is fixed by animationFrame; sceneTime and dynamicValues only
    /// identify the DEBUG evidence attached to this GPU publication.
    func encode(
        animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
        sceneTime: Double,
        dynamicValues: SceneDynamicSnapshot,
        commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    ) -> [String: simd_float4x4] {
        let frames = prepareFrame(animationFrame: animationFrame)
        guard case let .image(image) = geometry else {
            if case let .direct(direct) = geometry {
                direct.publish(on: commandBuffer, transaction: transaction)
#if DEBUG
                if ScenePuppetBoneEvidence.isEnabled(for: layerID) {
                    direct.recordEvidence(boneEvidence, layerID: layerID,
                        frame: dynamicValues.frameIndex, sceneTime: sceneTime,
                        selection: selection, animationFrame: animationFrame,
                        commandBuffer: commandBuffer)
                }
#endif
            }
            return frames
        }
        preparedPublicationCommandBuffer = nil
        guard let preparedFrameSignature, let preparedBoneRevision else { return frames }
        let attachmentFrames = submissions.update(transaction: transaction) { submission in
            guard submission.frameSignature != preparedFrameSignature
                    || submission.boneRevision != preparedBoneRevision else {
                return submission.attachmentFrames
            }
            let vertexBuffer = image.vertexBuffers[submission.nextVertexBufferIndex]
            lastPreparedVertexBufferIndex = submission.nextVertexBufferIndex
            submission.nextVertexBufferIndex =
                (submission.nextVertexBufferIndex + 1) % image.vertexBuffers.count
            image.vertexScratch.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress else { return }
                vertexBuffer.contents().copyMemory(
                    from: source,
                    byteCount: bytes.count
                )
            }

            submission.frameSignature = preparedFrameSignature
            submission.boneRevision = preparedBoneRevision
            submission.attachmentFrames = frames
            return frames
        }
        preparedPublicationCommandBuffer = commandBuffer
#if DEBUG
        if ScenePuppetBoneEvidence.isEnabled(for: layerID) {
        let publishedPositions = image.vertexScratch.map(\.position)
        boneEvidence.record(layerID: layerID, revision: preparedBoneRevision,
            frame: dynamicValues.frameIndex, sceneTime: sceneTime,
            scriptWritten: boneWrittenInFrame && preparedBoneRevision == boneRevision,
            displacement: zip(publishedPositions, image.mesh.vertices).reduce(Float(0)) {
                max($0, simd_length($1.0 - SIMD2($1.1.x, $1.1.y)))
            }, positions: publishedPositions, commandBuffer: commandBuffer)
        }
#endif
        return attachmentFrames
    }

    private func geometryProduct(image: ImageGeometry) -> SceneGeometryProduct {
        SceneGeometryProduct(
            ownerLayerID: layerID,
            samplingTexture: image.atlasTexture,
            prepare: image.clipping.map { clipping in
                { [self, image] commandBuffer, extent, mvp, retainAuxiliary in
                    guard let index = lastPreparedVertexBufferIndex else { return }
                    clipping.prepare(commandBuffer: commandBuffer, extent: extent, mvp: mvp,
                        retainAuxiliary: retainAuxiliary,
                        vertexCoverageVaries: image.hasBoneAlpha,
                        vertices: image.vertexScratch, vertexBuffer: image.vertexBuffers[index], indexBuffer: image.indexBuffer)
                }
            },
            isPreparedForPublication: { [self] commandBuffer in
                preparedPublicationCommandBuffer === commandBuffer
            },
            encode: {
            [self, image] encoder, sourceTexture, dependencyTexture, mvp, uniforms,
            bindColorBlend in
            guard let lastPreparedVertexBufferIndex else { return false }
#if DEBUG
            if !recordedWorldDraw,
               SceneDesktopWallpaperHost.usesDebugEvidenceWindow {
                recordedWorldDraw = true
                var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
                var maximum = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
                var visibleVertexCount = 0
                for vertex in image.vertexScratch {
                    let position = vertex.position
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
                    visibleVertexCount, image.vertexScratch.count
                )
            }
#endif
            if let bindColorBlend {
                bindColorBlend(encoder, sourceTexture, mvp)
            } else {
#if DEBUG
                ScenePerformanceCounterHub.shared.bump(.pipelineStateBinds)
#endif
                encoder.setRenderPipelineState(image.renderPipelineState)
                var matrix = mvp
                encoder.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.size, index: 1)
                var uniforms = uniforms
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneLayerFragmentUniforms>.size, index: 0)
                encoder.setFragmentTexture(sourceTexture, index: 0)
                encoder.setFragmentTexture(dependencyTexture ?? sourceTexture, index: 1)
            }
            encoder.setVertexBuffer(image.vertexBuffers[lastPreparedVertexBufferIndex], offset: 0, index: 0)
            if let clipping = image.clipping {
                clipping.draw(encoder: encoder, sourceTexture: sourceTexture, indexBuffer: image.indexBuffer)
            } else {
                SceneImageLayerPipeline.bindClipMask(encoder: encoder, texture: sourceTexture)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: image.mesh.indices.count,
                    indexType: .uint16, indexBuffer: image.indexBuffer, indexBufferOffset: 0)
                #if DEBUG
                SceneGPUStageTimestampHook.drew(encoder)
                                ScenePerformanceCounterHub.shared.recordDraw(usesGeometry: true)
#endif
            }
            return true
            },
            authoredSize: image.authoredSize,
            effectSourceExtentContract: .exactSamplingTexture
        )
    }

    /// Returns the current render pose, including physical displacement.
    func boneConfiguration(
        animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame
    ) -> ScenePuppetLayerLoad.BoneConfiguration? {
        poseConfiguration(animationFrame: animationFrame)?.bones
    }

    /// Evaluates one typed current pose for the pre-script frame snapshot.
    /// Bone handles, animated attachments and cursor/world projections all
    /// consume this result instead of evaluating independent hierarchies.
    func poseConfiguration(
        animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
        meshToWorld: simd_float4x4 = matrix_identity_float4x4
    ) -> PoseConfiguration? {
        guard let transforms = try? evaluator.boneTransforms(
            selection: selection,
            frameSamples: animationFrame.samples,
            boneOverrides: renderBoneOverrides,
            blends: animationFrame.blends
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
        var queryLocalMatrices = bones.localMatrices
        for (index, origin) in queryBoneOrigins {
            let offset = index * 16 + 12
            queryLocalMatrices[offset] = Double(origin.x)
            queryLocalMatrices[offset + 1] = Double(origin.y)
            queryLocalMatrices[offset + 2] = Double(origin.z)
        }
        return PoseConfiguration(
            bones: bones,
            queryLocalMatrices: queryLocalMatrices,
            attachmentFrames: ScenePuppetAttachmentPoseProjection.frames(
                attachments: attachments,
                boneWorldMatrices: transforms.world
            ) ?? [:],
            meshToWorld: meshToWorld
        )
    }

    /// The authored pose/physics is evaluated before callbacks each frame;
    /// scripts may replace that result only for the frame they write.
    func advanceBonePhysics(animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
                            deltaTime: Double, frameIndex: UInt64,
                            meshToWorld: simd_float4x4 = matrix_identity_float4x4) {
        if let lastBonePhysicsFrameIndex, frameIndex <= lastBonePhysicsFrameIndex { return }
#if DEBUG
        boneWrittenInFrame = false
#endif
        guard hasTranslationPhysics else { return }
        do {
            try evaluator.writeLocalMatrices(selection: selection,
                frameSamples: animationFrame.samples, blends: animationFrame.blends,
                into: &localMatrixScratch)
        } catch { return }
        lastBonePhysicsFrameIndex = frameIndex
        // Rig parents precede children. Use the current physical parent as the
        // child's carrier, while retaining each bone's local distance limit.
        for index in evaluator.rig.bones.indices {
            let bone = evaluator.rig.bones[index]
            let parent = bone.parentIndex < 0
                ? matrix_identity_float4x4 : worldMatrixScratch[bone.parentIndex]
            var pose = renderBoneOverrides[index] ?? localMatrixScratch[index]
            if let configuration = bone.translationPhysics {
                let targetColumn = localMatrixScratch[index].columns.3
                let target = SIMD3(targetColumn.x, targetColumn.y, targetColumn.z)
                queryBoneOrigins[index] = target
                let column = pose.columns.3
                let position = SIMD3(column.x, column.y, column.z)
                var motion = translationMotions[index] ?? .init()
                let next = motion.advance(position: position, target: target,
                    deltaTime: deltaTime, configuration: configuration,
                    parentToWorld: meshToWorld * parent)
                translationMotions[index] = motion
                if next != position {
                    pose.columns.3 = SIMD4(next, 1)
                    renderBoneOverrides[index] = pose
                    boneRevision &+= 1
                }
            }
            worldMatrixScratch[index] = parent * pose
        }
    }

    func apply(scriptBoneMutations: [SceneScriptPuppetBoneMutation]) {
        var accepted = false
        for mutation in scriptBoneMutations where mutation.layerID == layerID {
            guard mutation.boneIndex >= 0,
                  mutation.boneIndex < evaluator.boneCount else { continue }
            switch mutation.operation {
            case let .impulse(vector):
                guard evaluator.rig.bones[mutation.boneIndex].translationPhysics != nil else { continue }
                let impulse = SIMD3<Float>(vector)
                guard impulse.x.isFinite, impulse.y.isFinite, impulse.z.isFinite else { continue }
                var motion = translationMotions[mutation.boneIndex] ?? .init()
                motion.addImpulse(impulse)
                translationMotions[mutation.boneIndex] = motion
            case let .matrix(source):
                guard source.count == 16 else { continue }
                let values = source.map(Float.init)
                guard values.allSatisfy(\.isFinite) else { continue }
                let columns = stride(from: 0, to: 16, by: 4).map { offset in
                    SIMD4<Float>(values[offset], values[offset + 1], values[offset + 2], values[offset + 3])
                }
                let matrix = simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3]))
                renderBoneOverrides[mutation.boneIndex] = matrix
                if evaluator.rig.bones[mutation.boneIndex].translationPhysics != nil {
                    let origin = SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
                    queryBoneOrigins[mutation.boneIndex] = origin
                    var motion = translationMotions[mutation.boneIndex] ?? .init()
                    motion.reset()
                    translationMotions[mutation.boneIndex] = motion
                }
                accepted = true
            }
#if DEBUG
            boneWrittenInFrame = true
#endif
        }
        if accepted { boneRevision &+= 1 }
    }

    init(layerID: Int, geometry: Geometry, selection: ScenePuppetAnimationSelection,
         evaluator: ScenePuppetAnimationEvaluator,
         attachments: [SceneMdlPuppetAttachment]) {
        self.layerID = layerID
        animationIDs = selection.clips.map(\.animation.id)
        self.geometry = geometry
        self.selection = selection
        self.evaluator = evaluator
        self.attachments = attachments
        hasTranslationPhysics = evaluator.rig.bones.contains {
            $0.translationPhysics != nil
        }
        let matrixScratchCount = evaluator.boneCount
        localMatrixScratch = Array(repeating: matrix_identity_float4x4, count: matrixScratchCount)
        skinMatrixScratch = Array(repeating: matrix_identity_float4x4, count: matrixScratchCount)
        worldMatrixScratch = Array(repeating: matrix_identity_float4x4, count: matrixScratchCount)
        signatureScratch = Array(repeating: FrameSignature(sample: nil, visible: false),
            count: selection.clips.count)
    }
}

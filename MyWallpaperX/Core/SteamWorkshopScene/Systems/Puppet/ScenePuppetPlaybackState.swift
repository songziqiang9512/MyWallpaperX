import Foundation
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

    struct RenderFrame {
        enum Geometry {
            case image(vertices: [SceneQuadVertex], vertexCoverageVaries: Bool)
            case direct(vertices: [SceneMdlStaticModel.Vertex], status: DirectModelPoseStatus)
        }
        let revision: UInt64
        let geometry: Geometry
#if DEBUG
        let boneRevision: UInt64
        let scriptWritten: Bool
#endif
    }

    struct PoseConfiguration {
        let bones: ScenePuppetLayerLoad.BoneConfiguration
        let queryLocalMatrices: [Double]
        let attachmentFrames: [String: simd_float4x4]
        let meshToWorld: simd_float4x4
    }

    enum Failure: Error, CustomStringConvertible {
        case directModelVertexCountMismatch
        case directAttachmentBasisUnqualified

        nonisolated var description: String {
            switch self {
            case .directAttachmentBasisUnqualified:
                return "direct model attachment basis is unqualified"
            case .directModelVertexCountMismatch:
                return "direct model bind/evaluator vertex counts do not match"
            }
        }
    }

    final class ImagePose {
        let mesh: SceneMdlPuppetMesh
        let hasBoneAlpha: Bool
        var positionScratch: [SIMD2<Float>]
        var vertexScratch: [SceneQuadVertex]
        var coverageScratch: [Float]
        var boneAlphaScratch: [Float]

        init(mesh: SceneMdlPuppetMesh, evaluator: ScenePuppetAnimationEvaluator,
             selection: ScenePuppetAnimationSelection) {
            self.mesh = mesh
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
        case image(ImagePose)
        case direct(DirectModelPose)
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
    private var renderRevision: UInt64?
    private var renderBoneOverrides: [Int: simd_float4x4] = [:]
    /// Translation-only query overlay. Physical translation continues in the
    /// render pose after this overlay expires at the next simulation cadence.
    private var queryBoneOrigins: [Int: SIMD3<Float>] = [:]
    private var lastBonePhysicsFrameIndex: UInt64?
#if DEBUG
    private var recordedBoneSkin = false
    private var boneWrittenInFrame = false
#endif
    private var boneRevision: UInt64 = 0
    private var translationMotions: [Int: ScenePuppetTranslationMotion] = [:]
    static func make(
        layerID: Int, mesh: SceneMdlPuppetMesh,
        evaluator: ScenePuppetAnimationEvaluator,
        selection: ScenePuppetAnimationSelection,
        attachments: [SceneMdlPuppetAttachment]
    ) -> ScenePuppetPlaybackState {
        ScenePuppetPlaybackState(layerID: layerID,
            geometry: .image(ImagePose(mesh: mesh, evaluator: evaluator, selection: selection)),
            selection: selection, evaluator: evaluator, attachments: attachments)
    }

    var renderFrame: RenderFrame? {
        guard let renderRevision else { return nil }
        let output: RenderFrame.Geometry
        switch geometry {
        case let .image(image):
            output = .image(vertices: image.vertexScratch, vertexCoverageVaries: image.hasBoneAlpha)
        case let .direct(direct):
            output = .direct(vertices: direct.outputVertices, status: direct.status)
        }
#if DEBUG
        return RenderFrame(revision: renderRevision, geometry: output,
            boneRevision: preparedBoneRevision ?? boneRevision,
            scriptWritten: boneWrittenInFrame && preparedBoneRevision == boneRevision)
#else
        return RenderFrame(revision: renderRevision, geometry: output)
#endif
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
                renderRevision = (renderRevision ?? 0) &+ 1
                preparedFrameSignature = nil
                preparedBoneRevision = nil
                preparedAttachmentFrames = [:]
            }
            return preparedAttachmentFrames
        }
        if case let .direct(direct) = geometry,
           let blends = animationFrame.blends, blends.count != frameSamples.count {
            direct.useBindFallback(.invalidFrame)
            renderRevision = (renderRevision ?? 0) &+ 1
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
            // Build a complete value once. Retained frozen frames keep their
            // storage without first copying old vertices only to overwrite them.
            image.vertexScratch = image.mesh.vertices.indices.map { index in
                SceneQuadVertex(
                    position: image.positionScratch[index],
                    texcoord: SIMD2(image.mesh.vertices[index].u, image.mesh.vertices[index].v),
                    vertexCoverage: image.coverageScratch[index]
                )
            }
        }
        renderRevision = (renderRevision ?? 0) &+ 1
        preparedFrameSignature = signature
        preparedBoneRevision = boneRevision
        return preparedAttachmentFrames
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

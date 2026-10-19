import Metal
import simd

extension ScenePuppetPlaybackState {
    enum DirectModelFallback: String {
        case notPrepared
        case invalidFrame
        case unsupportedAnimationChannels
        case invalidSkinFrame
    }

    enum DirectModelPoseStatus: Equatable {
        case animated
        case bindFallback(DirectModelFallback)
    }

    /// This sink owns geometry storage only. The parent PlaybackState keeps the
    /// shared signature, pose evaluator, bone edits, physics and attachments.
    final class DirectModelGeometry {
        let bindVertices: [SceneMdlStaticModel.Vertex]
        let stream: SceneStaticModelVertexStream
        var scratch: [SceneMdlStaticModel.Vertex]
        private(set) var status = DirectModelPoseStatus.bindFallback(.notPrepared)
        private var poseRevision: UInt64 = 0
        private weak var publicationCommandBuffer: MTLCommandBuffer?
        private var publishedRevision: UInt64?
        private var binding: SceneStaticModelVertexStream.Binding?

        init(vertices: [SceneMdlStaticModel.Vertex], stream: SceneStaticModelVertexStream) {
            bindVertices = vertices
            self.stream = stream
            scratch = vertices
        }

        func useBindFallback(_ reason: DirectModelFallback) {
            status = .bindFallback(reason)
            poseRevision &+= 1
        }

        /// A partial write never changes the selected output: only complete
        /// success selects scratch; every failure selects immutable bind data.
        func prepare(evaluator: ScenePuppetAnimationEvaluator,
                     selection: ScenePuppetAnimationSelection,
                     animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
                     boneOverrides: [Int: simd_float4x4],
                     localMatrices: inout [simd_float4x4],
                     skinMatrices: inout [simd_float4x4],
                     worldMatrices: inout [simd_float4x4]) -> Bool {
            poseRevision &+= 1
            let unsupported = selection.clips.indices.contains { index in
                let clip = selection.clips[index]
                return animationFrame.samples[index] != nil
                    && (animationFrame.blends?[index] ?? clip.layer.blend ?? 1) > 0
                    && !clip.supportsDirectModelChannels
            }
            if unsupported {
                status = .bindFallback(.unsupportedAnimationChannels)
                return (try? evaluator.writeSkinMatrices(selection: selection,
                    frameSamples: animationFrame.samples,
                    localMatricesScratch: &localMatrices, skinMatricesScratch: &skinMatrices,
                    worldMatricesScratch: &worldMatrices, boneOverrides: boneOverrides,
                    blends: animationFrame.blends)) != nil
            }
            do {
                try scratch.withUnsafeMutableBufferPointer { output in
                    try evaluator.writeDeformedVertices(bindVertices: bindVertices,
                        selection: selection, frameSamples: animationFrame.samples, into: output,
                        localMatricesScratch: &localMatrices, skinMatricesScratch: &skinMatrices,
                        worldMatricesScratch: &worldMatrices, boneOverrides: boneOverrides,
                        blends: animationFrame.blends)
                }
                status = .animated
                return true
            } catch {
                status = .bindFallback(.invalidSkinFrame)
                // These failures occur after complete world/skin evaluation.
                // Invalid pose or bind sources must not publish old attachments.
                if let failure = error as? ScenePuppetAnimationEvaluator.DirectSkinningFailure {
                    switch failure {
                    case .singularSkinFrame, .invalidVertex: return true
                    default: break
                    }
                }
                return false
            }
        }

        func publish(on commandBuffer: MTLCommandBuffer,
                     transaction: SceneSourceUpdateTransaction) {
            if publicationCommandBuffer === commandBuffer { return }
            publicationCommandBuffer = commandBuffer
            publishedRevision = poseRevision
            binding = nil
            guard commandBuffer.status == .notEnqueued,
                  transaction.belongs(to: commandBuffer) else { return }
            let vertices: [SceneMdlStaticModel.Vertex]
            switch status {
            case .bindFallback: vertices = bindVertices
            case .animated: vertices = scratch
            }
            if case let .success(value) = stream.updateBinding(vertices: vertices,
                poseRevision: poseRevision, on: commandBuffer, transaction: transaction) {
                binding = value
            }
        }

#if DEBUG
        func recordEvidence(_ evidence: ScenePuppetBoneEvidence, layerID: Int,
                            frame: UInt64, sceneTime: Double,
                            selection: ScenePuppetAnimationSelection,
                            animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
                            commandBuffer: MTLCommandBuffer) {
            guard mesh(on: commandBuffer) != nil else { return }
            let vertices: [SceneMdlStaticModel.Vertex]
            let poseStatus: String
            switch status {
            case .animated:
                vertices = scratch
                poseStatus = "animated"
            case let .bindFallback(reason):
                vertices = bindVertices
                poseStatus = "bind-fallback:" + reason.rawValue
            }
            evidence.recordDirect(layerID: layerID, revision: poseRevision, frame: frame,
                sceneTime: sceneTime, poseStatus: poseStatus, selection: selection,
                animationFrame: animationFrame, vertices: vertices,
                bindVertices: bindVertices, commandBuffer: commandBuffer)
        }
#endif

        func mesh(on commandBuffer: MTLCommandBuffer) -> SceneStaticModelMesh? {
            guard publicationCommandBuffer === commandBuffer,
                  publishedRevision == poseRevision,
                  commandBuffer.status != .completed, commandBuffer.status != .error else { return nil }
            guard let binding, binding.isValid(for: commandBuffer) else { return nil }
            return binding.mesh
        }
    }

    static func makeDirectModel(
        layerID: Int,
        vertices: [SceneMdlStaticModel.Vertex],
        mesh: SceneStaticModelMesh,
        evaluator: ScenePuppetAnimationEvaluator,
        selection: ScenePuppetAnimationSelection,
        attachments: [SceneMdlPuppetAttachment] = [],
        pipeline: SceneStaticModelPipeline
    ) -> Result<ScenePuppetPlaybackState, Failure> {
        guard attachments.isEmpty else { return .failure(.directAttachmentBasisUnqualified) }
        guard vertices.count == evaluator.vertexCount, vertices.count == mesh.vertexCount else {
            return .failure(.directModelVertexCountMismatch)
        }
        switch pipeline.makeVertexStream(mesh: mesh) {
        case let .failure(failure): return .failure(.directModelStream(failure))
        case let .success(stream):
            return .success(ScenePuppetPlaybackState(layerID: layerID,
                geometry: .direct(DirectModelGeometry(vertices: vertices, stream: stream)),
                selection: selection, evaluator: evaluator, attachments: attachments))
        }
    }

    var directModelPoseStatus: DirectModelPoseStatus? {
        guard case let .direct(direct) = geometry else { return nil }
        return direct.status
    }

    func directModelMesh(on commandBuffer: MTLCommandBuffer) -> SceneStaticModelMesh? {
        guard case let .direct(direct) = geometry else { return nil }
        return direct.mesh(on: commandBuffer)
    }
}

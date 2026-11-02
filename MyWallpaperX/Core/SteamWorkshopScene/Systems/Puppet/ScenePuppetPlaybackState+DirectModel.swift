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

    final class DirectModelPose {
        let bindVertices: [SceneMdlStaticModel.Vertex]
        var scratch: [SceneMdlStaticModel.Vertex]
        private(set) var status = DirectModelPoseStatus.bindFallback(.notPrepared)
        init(vertices: [SceneMdlStaticModel.Vertex]) {
            bindVertices = vertices
            scratch = vertices
        }

        var outputVertices: [SceneMdlStaticModel.Vertex] {
            switch status {
            case .bindFallback: bindVertices
            case .animated: scratch
            }
        }

        func useBindFallback(_ reason: DirectModelFallback) {
            status = .bindFallback(reason)
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

    }

    static func makeDirectModel(
        layerID: Int,
        vertices: [SceneMdlStaticModel.Vertex],
        evaluator: ScenePuppetAnimationEvaluator,
        selection: ScenePuppetAnimationSelection,
        attachments: [SceneMdlPuppetAttachment] = []
    ) -> Result<ScenePuppetPlaybackState, Failure> {
        guard attachments.isEmpty else { return .failure(.directAttachmentBasisUnqualified) }
        guard vertices.count == evaluator.vertexCount else {
            return .failure(.directModelVertexCountMismatch)
        }
        return .success(ScenePuppetPlaybackState(layerID: layerID,
            geometry: .direct(DirectModelPose(vertices: vertices)),
            selection: selection, evaluator: evaluator, attachments: attachments))
    }

    var directModelPoseStatus: DirectModelPoseStatus? {
        guard case let .direct(direct) = geometry else { return nil }
        return direct.status
    }

}

import Metal
import simd

/// Per-layer/surface GPU storage. CPU pose preparation publishes immutable
/// vertices; clipping reads exactly the bytes selected for this publication.
final class ScenePuppetMeshGeometry {
    struct Output {
        let product: SceneGeometryProduct
        let geometry: ScenePuppetMeshGeometry
        let vertexCount: Int
        let triangleCount: Int
    }

    struct Outcome {
        let geometryProduct: SceneGeometryProduct?
        let allowsMissingMeshTextureProduct: Bool
        let message: String
    }

    enum Failure: Error, CustomStringConvertible {
        case degenerateLayerSize
        case resourceAllocationFailed

        nonisolated var description: String {
            switch self {
            case .degenerateLayerSize: return "degenerate layer size"
            case .resourceAllocationFailed: return "Metal geometry resource allocation failed"
            }
        }
    }

    private struct ImageSubmission {
        var revision: UInt64?
        var nextVertexBufferIndex = 0
    }

    private final class ImageGeometry {
        let mesh: SceneMdlPuppetMesh
        let vertexBuffers: [MTLBuffer]
        let indexBuffer: MTLBuffer
        let renderPipelineState: MTLRenderPipelineState
        let clipping: ScenePuppetClipping?
        let submissions: SceneSourceUpdateStateFIFO<ImageSubmission>?
        var preparedVertexBufferIndex: Int?
        weak var publicationCommandBuffer: MTLCommandBuffer?
        var vertexCoverageVaries = false

        init(mesh: SceneMdlPuppetMesh, vertexBuffers: [MTLBuffer], indexBuffer: MTLBuffer,
             renderPipelineState: MTLRenderPipelineState, clipping: ScenePuppetClipping?,
             animated: Bool) {
            self.mesh = mesh
            self.vertexBuffers = vertexBuffers
            self.indexBuffer = indexBuffer
            self.renderPipelineState = renderPipelineState
            self.clipping = clipping
            submissions = animated ? SceneSourceUpdateStateFIFO(initial: ImageSubmission()) : nil
            preparedVertexBufferIndex = animated ? nil : 0
        }
    }

    private final class DirectModelGeometry {
        let stream: SceneStaticModelVertexStream
        weak var publicationCommandBuffer: MTLCommandBuffer?
        var binding: SceneStaticModelVertexStream.Binding?
#if DEBUG
        let bindMesh: SceneStaticModelMesh
        let selection: ScenePuppetAnimationSelection
#endif

        init(stream: SceneStaticModelVertexStream, mesh: SceneStaticModelMesh,
             selection: ScenePuppetAnimationSelection) {
            self.stream = stream
#if DEBUG
            bindMesh = mesh
            self.selection = selection
#endif
        }
    }

    private enum Geometry {
        case image(ImageGeometry)
        case direct(DirectModelGeometry)
    }

    private let layerID: Int
    private let geometry: Geometry
#if DEBUG
    private let boneEvidence = ScenePuppetBoneEvidence()
    private var recordedWorldDraw = false
#endif

    private init(layerID: Int, geometry: Geometry) {
        self.layerID = layerID
        self.geometry = geometry
    }

    static func prepare(
        layerID: Int,
        mesh: SceneMdlPuppetMesh,
        atlasTexture: MTLTexture,
        layerWidth: Float,
        layerHeight: Float,
        device: MTLDevice,
        pipeline: SceneImageLayerPipeline,
        clipping: ScenePuppetClipping? = nil,
        animated: Bool = false
    ) -> Result<Output, Failure> {
        guard layerWidth.isFinite, layerHeight.isFinite,
              layerWidth >= 1, layerHeight >= 1 else {
            return .failure(.degenerateLayerSize)
        }
        var indices = mesh.indices
        guard let indexBuffer = device.makeSceneBuffer(
            bytes: &indices, length: indices.count * MemoryLayout<UInt16>.stride
        ) else { return .failure(.resourceAllocationFailed) }
        let byteCount = mesh.vertices.count * MemoryLayout<SceneQuadVertex>.stride
        let vertexBuffers: [MTLBuffer]
        if animated {
            vertexBuffers = (0..<3).compactMap { _ in
                device.makeSceneBuffer(length: byteCount, options: .storageModeShared)
            }
            guard vertexBuffers.count == 3 else { return .failure(.resourceAllocationFailed) }
        } else {
            var vertices = mesh.vertices.map {
                SceneQuadVertex(position: SIMD2($0.x, $0.y), texcoord: SIMD2($0.u, $0.v))
            }
            guard let buffer = device.makeSceneBuffer(
                bytes: &vertices, length: byteCount, options: .storageModeShared
            ) else { return .failure(.resourceAllocationFailed) }
            vertexBuffers = [buffer]
        }
        let image = ImageGeometry(mesh: mesh, vertexBuffers: vertexBuffers, indexBuffer: indexBuffer,
            renderPipelineState: pipeline.state, clipping: clipping, animated: animated)
        let owner = ScenePuppetMeshGeometry(layerID: layerID, geometry: .image(image))
        return .success(Output(
            product: owner.geometryProduct(image: image, atlasTexture: atlasTexture,
                authoredSize: SIMD2(layerWidth, layerHeight)),
            geometry: owner, vertexCount: mesh.vertices.count, triangleCount: mesh.triangleCount))
    }

    static func prepareDirectModel(
        layerID: Int,
        vertices: [SceneMdlStaticModel.Vertex],
        mesh: SceneStaticModelMesh,
        pipeline: SceneStaticModelPipeline,
        selection: ScenePuppetAnimationSelection
    ) -> Result<ScenePuppetMeshGeometry, SceneStaticModelVertexStream.Failure> {
        guard vertices.count == mesh.vertexCount else { return .failure(.invalidVertices) }
        return pipeline.makeVertexStream(mesh: mesh).map { stream in
            ScenePuppetMeshGeometry(layerID: layerID,
                geometry: .direct(DirectModelGeometry(stream: stream, mesh: mesh, selection: selection)))
        }
    }

    func publish(
        frame: ScenePuppetPlaybackState.RenderFrame,
        animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
        sceneTime: Double,
        frameIndex: UInt64,
        commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    ) {
        switch (geometry, frame.geometry) {
        case let (.image(image), .image(vertices, coverageVaries)):
            image.publicationCommandBuffer = nil
            guard let submissions = image.submissions,
                  commandBuffer.status == .notEnqueued,
                  transaction.belongs(to: commandBuffer) else { return }
            let index = submissions.update(transaction: transaction) { submission in
                if submission.revision != frame.revision {
                    let buffer = image.vertexBuffers[submission.nextVertexBufferIndex]
                    vertices.withUnsafeBytes { bytes in
                        guard let source = bytes.baseAddress else { return }
                        buffer.contents().copyMemory(from: source, byteCount: bytes.count)
                    }
                    submission.nextVertexBufferIndex =
                        (submission.nextVertexBufferIndex + 1) % image.vertexBuffers.count
                    submission.revision = frame.revision
                }
                return (submission.nextVertexBufferIndex + image.vertexBuffers.count - 1)
                    % image.vertexBuffers.count
            }
            image.preparedVertexBufferIndex = index
            image.vertexCoverageVaries = coverageVaries
            image.publicationCommandBuffer = commandBuffer
#if DEBUG
            recordImageEvidence(image, frame: frame, sceneTime: sceneTime,
                frameIndex: frameIndex, commandBuffer: commandBuffer)
#endif
        case let (.direct(direct), .direct(vertices, status)):
            if direct.publicationCommandBuffer === commandBuffer { return }
            direct.publicationCommandBuffer = commandBuffer
            direct.binding = nil
            if case let .success(binding) = direct.stream.updateBinding(vertices: vertices,
                poseRevision: frame.revision, on: commandBuffer, transaction: transaction) {
                direct.binding = binding
#if DEBUG
                recordDirectEvidence(direct, status: status, animationFrame: animationFrame,
                    sceneTime: sceneTime, frameIndex: frameIndex, commandBuffer: commandBuffer)
#endif
            }
        default:
            return
        }
    }

    func directModelMesh(on commandBuffer: MTLCommandBuffer) -> SceneStaticModelMesh? {
        guard case let .direct(direct) = geometry,
              direct.publicationCommandBuffer === commandBuffer,
              let binding = direct.binding, binding.isValid(for: commandBuffer) else { return nil }
        return binding.mesh
    }

    private func geometryProduct(image: ImageGeometry, atlasTexture: MTLTexture,
                                 authoredSize: SIMD2<Float>) -> SceneGeometryProduct {
        SceneGeometryProduct(
            ownerLayerID: layerID,
            samplingTexture: atlasTexture,
            prepare: image.clipping.map { clipping in
                { [image] commandBuffer, extent, mvp, retainAuxiliary in
                    guard let index = image.preparedVertexBufferIndex else { return }
                    clipping.prepare(commandBuffer: commandBuffer, extent: extent, mvp: mvp,
                        retainAuxiliary: retainAuxiliary, vertexCoverageVaries: image.vertexCoverageVaries,
                        vertexBuffer: image.vertexBuffers[index], indexBuffer: image.indexBuffer)
                }
            },
            isPreparedForPublication: { [image] commandBuffer in
                image.submissions == nil || image.publicationCommandBuffer === commandBuffer
            },
            encode: { [self, image] encoder, sourceTexture, dependencyTexture, mvp, uniforms, bindColorBlend in
                guard let index = image.preparedVertexBufferIndex else { return false }
#if DEBUG
                recordWorldDraw(image, index: index, mvp: mvp)
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
                encoder.setVertexBuffer(image.vertexBuffers[index], offset: 0, index: 0)
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
            authoredSize: authoredSize,
            effectSourceExtentContract: .exactSamplingTexture)
    }

#if DEBUG
    private func recordImageEvidence(_ image: ImageGeometry, frame: ScenePuppetPlaybackState.RenderFrame,
                                     sceneTime: Double, frameIndex: UInt64, commandBuffer: MTLCommandBuffer) {
        guard ScenePuppetBoneEvidence.isEnabled(for: layerID),
              let index = image.preparedVertexBufferIndex else { return }
        let vertices = UnsafeBufferPointer(
            start: image.vertexBuffers[index].contents().assumingMemoryBound(to: SceneQuadVertex.self),
            count: image.mesh.vertices.count)
        let positions = vertices.map(\.position)
        let displacement = zip(vertices, image.mesh.vertices).reduce(Float(0)) {
            max($0, simd_length($1.0.position - SIMD2($1.1.x, $1.1.y)))
        }
        boneEvidence.record(layerID: layerID, revision: frame.boneRevision,
            frame: frameIndex, sceneTime: sceneTime, scriptWritten: frame.scriptWritten,
            displacement: displacement, positions: positions, commandBuffer: commandBuffer)
    }

    private func recordDirectEvidence(_ direct: DirectModelGeometry,
                                     status: ScenePuppetPlaybackState.DirectModelPoseStatus,
                                     animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
                                     sceneTime: Double, frameIndex: UInt64, commandBuffer: MTLCommandBuffer) {
        guard ScenePuppetBoneEvidence.isEnabled(for: layerID),
              let binding = direct.binding else { return }
        let vertices = UnsafeBufferPointer(
            start: binding.mesh.vertexBuffer.contents().assumingMemoryBound(to: SceneMdlStaticModel.Vertex.self),
            count: binding.mesh.vertexCount)
        let bindVertices = UnsafeBufferPointer(
            start: direct.bindMesh.vertexBuffer.contents().assumingMemoryBound(to: SceneMdlStaticModel.Vertex.self),
            count: direct.bindMesh.vertexCount)
        let poseStatus: String
        switch status {
        case .animated: poseStatus = "animated"
        case let .bindFallback(reason): poseStatus = "bind-fallback:" + reason.rawValue
        }
        boneEvidence.recordDirect(layerID: layerID, revision: binding.poseRevision,
            frame: frameIndex, sceneTime: sceneTime, poseStatus: poseStatus,
            selection: direct.selection, animationFrame: animationFrame,
            vertices: vertices, bindVertices: bindVertices, commandBuffer: commandBuffer)
    }

    private func recordWorldDraw(_ image: ImageGeometry, index: Int, mvp: simd_float4x4) {
        guard image.submissions != nil, !recordedWorldDraw,
              SceneDesktopWallpaperHost.usesDebugEvidenceWindow else { return }
        recordedWorldDraw = true
        let vertices = UnsafeBufferPointer(
            start: image.vertexBuffers[index].contents().assumingMemoryBound(to: SceneQuadVertex.self),
            count: image.mesh.vertices.count)
        var minimum = SIMD2<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        var visibleVertexCount = 0
        for vertex in vertices {
            let clip = mvp * SIMD4(vertex.position.x, vertex.position.y, 0, 1)
            guard clip.w.isFinite, abs(clip.w) > .ulpOfOne else { continue }
            let ndc = SIMD2(clip.x / clip.w, clip.y / clip.w)
            guard ndc.x.isFinite, ndc.y.isFinite else { continue }
            minimum = simd_min(minimum, ndc)
            maximum = simd_max(maximum, ndc)
            if abs(ndc.x) <= 1, abs(ndc.y) <= 1 { visibleVertexCount += 1 }
        }
        NSLog("MWX DEBUG SCENE: phase=puppet-world-draw layer=%d ndcMin=%.6f,%.6f ndcMax=%.6f,%.6f visibleVertices=%d totalVertices=%d",
            layerID, minimum.x, minimum.y, maximum.x, maximum.y, visibleVertexCount, vertices.count)
    }
#endif
}

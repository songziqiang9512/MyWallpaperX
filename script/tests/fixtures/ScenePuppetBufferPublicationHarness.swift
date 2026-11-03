
import CryptoKit
import Foundation
import Metal
import simd

// These peripheral contracts supply immutable property snapshots and
// observe allocations/evidence. Playback, evaluation, publication, FIFO state,
// geometry encoding, the image pipeline and all Metal objects are production.
enum SceneDynamicTarget: Hashable {
    case scriptInstanceProperty(layerID: Int, path: [String])
}
enum SceneDynamicValue { case bool(Bool), scalar(Double) }
enum SceneDynamicValueSource { case authored, userProperty, timeline, sceneScript }
struct SceneDynamicResolvedValue { let value: SceneDynamicValue; var source: SceneDynamicValueSource = .authored }
struct SceneDynamicSnapshot {
    let frameIndex: UInt64
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    init(frameIndex: UInt64, values: [SceneDynamicTarget: SceneDynamicResolvedValue] = [:]) {
        self.frameIndex = frameIndex
        self.values = values
    }
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { values[target] }
}
struct SceneScriptPuppetBoneMutation {
    enum Operation { case matrix([Double]), impulse(SIMD3<Double>) }
    let layerID: Int, boneIndex: Int
    let operation: Operation
}
enum ScenePuppetLayerLoad {
    struct BoneConfiguration {
        let names: [String], parentIndices: [Int]
        let worldMatrices: [Double], localMatrices: [Double]
    }
}
enum SceneDesktopWallpaperHost { static let usesDebugEvidenceWindow = false }
enum Observation {
    static var buffers: [MTLBuffer] = []
    static var evidence: [[SIMD2<Float>]] = []
    static weak var previousCommand: MTLCommandBuffer?
}
// This gate does not test optional GPU stage timing. Keep that diagnostic
// disabled at the external observation boundary; all geometry, publication,
// native encoder creation, draw commands and GPU completion remain real.
enum SceneGPUStageTimestampHook {
    static func render(_ commandBuffer: MTLCommandBuffer,
                       _ descriptor: MTLRenderPassDescriptor,
                       role: String) -> MTLRenderCommandEncoder? {
        commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    }
    static func drew(_ encoder: MTLRenderCommandEncoder) {}
}
extension MTLDevice {
    func makeSceneBuffer(length: Int, options: MTLResourceOptions = []) -> MTLBuffer? {
        guard let buffer = makeBuffer(length: length, options: options.union(.storageModeShared)) else {
            return nil
        }
        // Make an accidental pre-publication draw observably uninitialized.
        buffer.contents().initializeMemory(as: UInt8.self, repeating: 0xA5, count: length)
        Observation.buffers.append(buffer)
        return buffer
    }
    func makeSceneBuffer(bytes: UnsafeRawPointer, length: Int,
                         options: MTLResourceOptions = []) -> MTLBuffer? {
        makeBuffer(bytes: bytes, length: length, options: options.union(.storageModeShared))
    }
}
func columns(_ matrix: simd_float4x4) -> [Float] {
    (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
}
func pose(scale: Float = 1, translationX: Float = 0) -> SceneMdlPuppetAnimation.Transform {
    .init(translation: SIMD3(translationX, 0, 0), rotation: .zero,
          scale: SIMD3(scale, 1, 1))
}
func fixture(poses: [SceneMdlPuppetAnimation.Transform], weight: Double,
             wideVertex: Bool = false, alpha: [Float]? = nil,
             visibilityBinding: String? = nil)
    -> (SceneMdlPuppetMesh, SceneMdlPuppetRig, ScenePuppetAnimationSelection) {
    let mesh = SceneMdlPuppetMesh(version: "MDLV0023", vertexStride: 80,
        meshBlockOffset: 9, vertices: [
            .init(x: wideVertex ? 2 : -0.5, y: -0.5, z: 0, u: 0, v: 0),
            .init(x: wideVertex ? 1e6 : 0.5, y: -0.5, z: 0, u: 1, v: 0),
            .init(x: wideVertex ? 2 : 0, y: 0.5, z: 0, u: 0, v: 1),
        ], indices: [0, 1, 2])
    let rig = SceneMdlPuppetRig(bones: [
        .init(parentIndex: -1, bindLocalMatrixColumnMajor: columns(matrix_identity_float4x4))
    ], vertexWeights: mesh.vertices.map { _ in
        .init(boneIndices: SIMD4(0, 0, 0, 0), boneWeights: SIMD4(1, 0, 0, 0))
    })
    let animation = SceneMdlPuppetAnimation(id: 1, name: "publication", mode: "single",
        framesPerSecond: 1, frameCount: poses.count - 1, transformsByBone: [poses],
        alphaByBone: alpha.map { [$0] })
    let layer = ScenePuppetAnimationLayer(id: 1, animationID: 1, name: "publication",
        additive: true, blend: weight, blendIn: false, blendOut: false,
        blendTime: 0, rate: 1, visible: true, visibilityBinding: visibilityBinding)
    return (mesh, rig, .init(clips: [.init(layer: layer, animation: animation)],
                             composition: .layered))
}
func weightedFixture(alpha: [Float], weights: SIMD4<Float>)
    -> (SceneMdlPuppetMesh, SceneMdlPuppetRig, ScenePuppetAnimationSelection) {
    let base = fixture(poses: [pose(), pose()], weight: 1)
    // Every influence has a parent except the root. Exported alpha is already
    // inherited, so runtime parent multiplication would change the pixels.
    let rig = SceneMdlPuppetRig(bones: alpha.indices.map { index in
        .init(parentIndex: index - 1,
              bindLocalMatrixColumnMajor: columns(matrix_identity_float4x4))
    }, vertexWeights: base.0.vertices.map { _ in
        .init(boneIndices: SIMD4(0, 1, 2, 3), boneWeights: weights)
    })
    let animation = SceneMdlPuppetAnimation(id: 1, name: "coverage", mode: "single",
        framesPerSecond: 1, frameCount: 1,
        transformsByBone: alpha.map { _ in [pose(), pose()] },
        alphaByBone: alpha.map { [$0, $0] })
    return (base.0, rig, .init(clips: [.init(layer: base.2.clips[0].layer,
                                           animation: animation)], composition: .layered))
}
func pairedClips(alpha: [Float]?, peer: [Float]?, additive: [Bool] = [true, true],
                 optionalPeer: Bool = false, boundPeer: Bool = false,
                 renamed: Bool = false, peerShift: Float = 0)
    -> [ScenePuppetAnimationSelection.Clip] {
    [alpha, peer].enumerated().map { index, track in
        let id = (renamed ? 91 : 1) + index
        let sample = pose(translationX: index == 1 ? peerShift : 0)
        let name = "\(renamed ? "renamed" : "coverage")-\(id)"
        let animation = SceneMdlPuppetAnimation(id: id, name: name, mode: "single",
            framesPerSecond: 1, frameCount: 1, transformsByBone: [[sample, sample]],
            alphaByBone: track.map { [$0] })
        let layer = ScenePuppetAnimationLayer(id: id, animationID: id, name: name,
            additive: additive[index], blend: 1, blendIn: false, blendOut: false,
            blendTime: 0, rate: 1, visible: index == 0 || !optionalPeer,
            visibilityBinding: index == 1 && boundPeer ? "peer" : nil,
            hasVisibilityScript: index == 1 && optionalPeer ? true : nil)
        return .init(layer: layer, animation: animation)
    }
}
func selectionReport(_ result: Result<ScenePuppetAnimationSelection?, ScenePuppetAnimationSelectionFailure>)
    -> [String: Any] {
    switch result {
    case let .success(selection?): return ["state": "allowed", "clips": selection.clips.count]
    case .success(nil): return ["state": "inactive"]
    case .failure(.unsupportedLayer(_)): return ["state": "unsupported"]
    case let .failure(failure): return ["state": failure.description]
    }
}
func texture(_ device: MTLDevice, size: Int, renderTarget: Bool = false) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
        width: size, height: size, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = renderTarget ? [.renderTarget] : [.shaderRead]
    return device.makeTexture(descriptor: descriptor)!
}
func bufferBytes(_ buffers: [MTLBuffer]) -> [Data] {
    buffers.map { Data(bytes: $0.contents(), count: $0.length) }
}
struct Playback {
    let state: ScenePuppetPlaybackState
    let geometry: ScenePuppetMeshGeometry
    let product: SceneGeometryProduct
}
func makePlayback(_ fixture: (SceneMdlPuppetMesh, SceneMdlPuppetRig,
                              ScenePuppetAnimationSelection),
                  device: MTLDevice, pipeline: SceneImageLayerPipeline,
                  atlas: MTLTexture, clipping: ScenePuppetClipping? = nil) throws -> Playback {
    let identity = columns(matrix_identity_float4x4)
    let evaluator = try ScenePuppetAnimationEvaluator(mesh: fixture.0, rig: fixture.1,
        additiveAnimations: fixture.2.clips.map(\.animation))
    let state = ScenePuppetPlaybackState.make(layerID: 42, mesh: fixture.0,
        evaluator: evaluator, selection: fixture.2,
        attachments: [.init(boneIndex: 0, name: "tip",
            modelLocalFrameColumnMajor: identity, modelBindFrameColumnMajor: identity)])
    let output = try ScenePuppetMeshGeometry.prepare(layerID: 42, mesh: fixture.0,
        atlasTexture: atlas, layerWidth: 16, layerHeight: 16, device: device,
        pipeline: pipeline, clipping: clipping, animated: true).get()
    return Playback(state: state, geometry: output.geometry, product: output.product)
}

struct Frame {
    let readyBefore: Bool, readyAfter: Bool, drew: Bool
    let differentLiveCommandReady: Bool, previousCommandReleased: Bool
    let draws: UInt64
    let pixels: [UInt8]
    let attachments: [String: simd_float4x4]
    var report: [String: Any] {
        ["readyBefore": readyBefore, "readyAfter": readyAfter, "drew": drew,
         "differentLiveCommandReady": differentLiveCommandReady,
         "previousCommandReleased": previousCommandReleased,
         "draws": draws, "centerBGRA": Array(pixels[(16 * 32 + 16) * 4..<(16 * 32 + 17) * 4]),
         "litPixels": pixels.enumerated().filter {
             $0.offset % 4 == 3 && $0.element > 0
         }.count, "imageSHA256": SHA256.hash(data: Data(pixels)).map {
             String(format: "%02x", $0)
         }.joined()]
    }
}
func render(_ output: Playback? = nil, sceneTime: Double,
            device: MTLDevice, queue: MTLCommandQueue, atlas: MTLTexture,
            animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame? = nil,
            mvp: simd_float4x4 = matrix_identity_float4x4,
            layerAlpha: Float = 1, clipVisible: Bool? = nil,
            ordinaryPipeline: SceneImageLayerPipeline? = nil,
            colorBlendState: SceneLayerColorBlendPipelineState? = nil,
            colorBlendMode: Int = 31,
            frozenFrame: ScenePuppetPlaybackState.RenderFrame? = nil) -> Frame {
    return autoreleasepool {
        let previousCommandReleased = Observation.previousCommand == nil
        let command = queue.makeCommandBuffer()!
        let transaction = SceneSourceUpdateTransaction(on: command)
        let readyBefore = output?.product.isPreparedForPublication(command) ?? false
        // Legacy publication fixtures supply a requested pose directly; the
        // shared-runtime integration case below supplies the launch's snapshot.
        let samples = animationFrame ?? .init(samples: output?.state.selection.clips.map { clip in
            let visible = clip.layer.visibilityBinding == nil ? clip.layer.visible == true : clipVisible == true
            return visible ? ScenePuppetAnimationEvaluator.frameSample(sceneTime: sceneTime,
                rate: clip.layer.rate ?? 1, animation: clip.animation) : nil
        } ?? [])
        let attachments = frozenFrame == nil ? output?.state.prepareFrame(animationFrame: samples) ?? [:] : [:]
        if let frame = frozenFrame ?? output?.state.renderFrame {
            output?.geometry.publish(frame: frame, animationFrame: samples, sceneTime: sceneTime,
                frameIndex: UInt64(sceneTime * 10), commandBuffer: command, transaction: transaction)
        }
        let readyAfter = output?.product.isPreparedForPublication(command) ?? false
        let differentLiveCommand = queue.makeCommandBuffer()!
        let differentLiveCommandReady = output?.product.isPreparedForPublication(differentLiveCommand) ?? false
        let target = texture(device, size: 32, renderTarget: true)
        var auxiliary: [() -> Void] = []
        output?.product.prepare?(command, SIMD2(32, 32), mvp, { auxiliary.append($0) })
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        let uniforms = SceneLayerFragmentUniforms(time: Float(sceneTime), alpha: layerAlpha,
            dependencyBlendMode: 0, usesDependencyBlend: 0, cursorUV: .zero,
            sourceSampling: SIMD2(2, 0), tint: SIMD4(repeating: 1),
            textureFrame0: SIMD4(0, 0, 1, 0), textureFrame1: SIMD4(0, 1, 0, 0))
        let before = ScenePerformanceCounterHub.shared.snapshot()[.geometryDrawCalls]!
        // Invoke the real direct encoder even when publication is unavailable.
        let drew: Bool
        if let colorBlendState {
            let background = texture(device, size: 32)
            let backgroundPixels: [UInt8] = (0..<32 * 32).flatMap { _ in [16, 32, 48, 255] }
            backgroundPixels.withUnsafeBytes {
                background.replace(region: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: 32 * 4)
            }
            // Exercise the exact alternate production fragment through the
            // geometry binder hook, with only fixed test uniforms/texture binds.
            let bind: SceneGeometryProduct.ColorBlendBinder = { encoder, source, matrix in
                var mvp = matrix
                var mode = SIMD2<UInt32>(UInt32(colorBlendMode), 0)
                var distanceFog = SceneImageDistanceFogUniforms()
                encoder.setRenderPipelineState(colorBlendState.renderPipeline)
                encoder.setVertexBytes(&mvp, length: MemoryLayout<simd_float4x4>.size, index: 1)
                encoder.setFragmentBytes(&mode, length: MemoryLayout<SIMD2<UInt32>>.size, index: 0)
                encoder.setFragmentBytes(&distanceFog,
                    length: MemoryLayout<SceneImageDistanceFogUniforms>.stride, index: 2)
                encoder.setFragmentTexture(source, index: 0)
                encoder.setFragmentTexture(background, index: 1)
                SceneImageLayerPipeline.bindClipMask(encoder: encoder, texture: source)
            }
            if let output {
                drew = output.product.encode(encoder, atlas, nil, mvp, uniforms, bind)
            } else {
                bind(encoder, atlas, mvp)
                SceneImageLayerPipeline.bindQuad(encoder: encoder)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                drew = true
            }
        } else if let output {
            drew = output.product.encode(encoder, atlas, nil, mvp, uniforms, nil)
        } else {
            let pipeline = ordinaryPipeline!
            pipeline.bind(encoder: encoder)
            pipeline.drawLayer(texture: atlas, mvp: mvp, uniforms: uniforms, encoder: encoder)
            drew = true
        }
        let draws = ScenePerformanceCounterHub.shared.snapshot()[.geometryDrawCalls]! - before
        encoder.endEncoding()
        transaction.arm(on: command)
        transaction.didSubmit()
        command.commit()
        command.waitUntilCompleted()
        auxiliary.forEach { $0() }
        precondition(command.status == .completed && command.error == nil)
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        pixels.withUnsafeMutableBytes {
            target.getBytes($0.baseAddress!, bytesPerRow: 32 * 4,
                            from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
        }
        Observation.previousCommand = command
        return Frame(readyBefore: readyBefore, readyAfter: readyAfter, drew: drew,
                     differentLiveCommandReady: differentLiveCommandReady,
                     previousCommandReleased: previousCommandReleased,
                     draws: draws, pixels: pixels, attachments: attachments)
    }
}

func multiAlphaChecks(device: MTLDevice, queue: MTLCommandQueue,
                      pipeline: SceneImageLayerPipeline, atlas: MTLTexture) throws -> [String: Any] {
    let base = fixture(poses: [pose(), pose()], weight: 1)
    func select(_ clips: [ScenePuppetAnimationSelection.Clip])
        -> Result<ScenePuppetAnimationSelection?, ScenePuppetAnimationSelectionFailure> {
        ScenePuppetAnimationSelector.select(layers: clips.map(\.layer),
            animationSet: .init(boneCount: 1, animations: clips.map(\.animation)))
    }
    func record(_ clips: [ScenePuppetAnimationSelection.Clip]) throws -> [String: Any] {
        let result = select(clips)
        var row: [String: Any] = ["selection": selectionReport(result),
            "authoredOrder": clips.map { $0.animation.id }]
        if case let .success(selection?) = result {
            row["clipOrder"] = selection.clips.map { $0.animation.id }
            let output = try makePlayback((base.0, base.1, selection), device: device,
                pipeline: pipeline, atlas: atlas)
            let frame = render(output, sceneTime: 0.5, device: device, queue: queue,
                atlas: atlas, layerAlpha: 0.5)
            row["frame"] = frame.report
            row["attachmentX"] = frame.attachments["tip"]!.columns.3.x
        }
        return row
    }
    var allowed: [[String: Any]] = []
    // Equal coverage for opaque/additive variants uses identity contributor TRS;
    // the neutral peer's independent translation must still reach the attachment.
    let cases: [([Float]?, [Bool])] = [(nil, [true, true]), ([1, 1], [false, false]),
        (nil, [false, true]), ([1, 1], [true, false])]
    for (peer, flags) in cases {
        for reverse in [false, true] {
            let clips = pairedClips(alpha: [1, 0.5], peer: peer, additive: flags,
                renamed: reverse, peerShift: 0.125)
            allowed.append(try record(reverse ? Array(clips.reversed()) : clips))
        }
    }
    let opaque = try [record(pairedClips(alpha: [1, 1], peer: nil)),
                      record(pairedClips(alpha: [1, 1], peer: [1, 1]))]
    let optional = try record(pairedClips(alpha: [1, 0.5], peer: [0.5, 0.5], optionalPeer: true))
    let bound = select(pairedClips(alpha: [1, 0.5], peer: [0.5, 0.5], optionalPeer: true, boundPeer: true))
    let near = select(pairedClips(alpha: [1, 0.5], peer: [1, Float(1).nextDown]))
    let conflicting = pairedClips(alpha: [1, 0.5], peer: [0.5, 0.5])
    let manual = try makePlayback((base.0, base.1, .init(clips: conflicting, composition: .layered)),
        device: device, pipeline: pipeline, atlas: atlas)
    let manualFrame = render(manual, sceneTime: 0.5, device: device, queue: queue, atlas: atlas)
    let clips = pairedClips(alpha: [1, 0.5], peer: [1, 1])
    let output = try makePlayback((base.0, base.1, try select(clips).get()!),
        device: device, pipeline: pipeline, atlas: atlas)
    let sample = ScenePuppetAnimationEvaluator.FrameSample(frameA: 0, frameB: 1, fraction: 0.5)
    let hidden = render(output, sceneTime: 0.5, device: device, queue: queue, atlas: atlas,
        animationFrame: .init(samples: [nil, sample]), layerAlpha: 0.5)
    let restored = render(output, sceneTime: 0.5, device: device, queue: queue, atlas: atlas,
        animationFrame: .init(samples: [sample, sample]), layerAlpha: 0.5)
    return ["allowed": allowed, "opaque": opaque, "optional": optional,
        "bound": selectionReport(bound), "nearOne": selectionReport(near),
        "twoContributors": selectionReport(select(conflicting)), "manual": manualFrame.report,
        "hidden": hidden.report, "restored": restored.report]
}

func translationPoseChecks(device: MTLDevice, queue: MTLCommandQueue,
                           pipeline: SceneImageLayerPipeline, atlas: MTLTexture) throws -> [String: Any] {
    let base = fixture(poses: [pose(translationX: 0.1), pose(translationX: 0.1)], weight: 1)
    let rig = SceneMdlPuppetRig(bones: [.init(parentIndex: -1,
        bindLocalMatrixColumnMajor: columns(matrix_identity_float4x4),
        translationPhysics: .init(spring: true, stiffness: 70, friction: 5,
            inertia: 5, maxDistance: 50))], vertexWeights: base.1.vertexWeights)
    let samples = ScenePuppetAnimationPlaybackRuntime.LayerFrame(samples: [.init(frameA: 0, frameB: 0)])
    let physical = try makePlayback((base.0, rig, base.2), device: device, pipeline: pipeline, atlas: atlas)
    var written = matrix_identity_float4x4
    written.columns.0.x = 0.8; written.columns.1.y = 0.9; written.columns.3.x = 0.35
    let mutation = SceneScriptPuppetBoneMutation(layerID: 42, boneIndex: 0,
        operation: .matrix(columns(written).map(Double.init)))
    let kick=SceneScriptPuppetBoneMutation(layerID:42,boneIndex:0,operation:.impulse(SIMD3(2,0,0)))
    func configuration(_ state: ScenePuppetPlaybackState) -> [String: Any] {
        let pose = state.poseConfiguration(animationFrame: samples)!
        let basis = (0..<16).filter { !(12...14).contains($0) }
        return ["queryX": pose.queryLocalMatrices[12], "renderX": pose.bones.localMatrices[12],
            "worldX": pose.bones.worldMatrices[12],
            "queryBasis": basis.map { pose.queryLocalMatrices[$0] },
            "renderBasis": basis.map { pose.bones.localMatrices[$0] },
            "attachmentX": pose.attachmentFrames["tip"]!.columns.3.x]
    }
    func positions() -> [[Float]] { Observation.evidence.last!.map { [$0.x, $0.y] } }
    physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 1.0 / 30, frameIndex: 10)
    physical.state.apply(scriptBoneMutations: [kick,mutation])
    let firstPose = configuration(physical.state)
    let first = render(physical, sceneTime: 1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    let firstPositions = positions()
    // A second surface/publication of this cadence cannot consume the overlay
    // or integrate another physical step, even with a different requested dt.
    physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.25, frameIndex: 10)
    let samePose = configuration(physical.state)
    let same = render(physical, sceneTime: 1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    let samePositions = positions()
    physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.05, frameIndex: 11)
    let nextPose = configuration(physical.state)
    let next = render(physical, sceneTime: 1.1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    let nextPositions = positions()
    physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.25, frameIndex: 11)
    let nextAgainPose = configuration(physical.state)
    for cadence in UInt64(12)...15 {
        physical.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.05, frameIndex: cadence)
    }
    let laterPose = configuration(physical.state)
    let later = render(physical, sceneTime: 1.5, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    let laterPositions = positions()
    physical.state.apply(scriptBoneMutations:[kick])
    physical.state.advanceBonePhysics(animationFrame:samples,deltaTime:0.05,frameIndex:16)
    let kickedPose=configuration(physical.state)
    let ordinary = try makePlayback(base, device: device, pipeline: pipeline, atlas: atlas)
    ordinary.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.05, frameIndex: 10)
    ordinary.state.apply(scriptBoneMutations: [mutation,kick])
    let ordinaryFirstPose = configuration(ordinary.state)
    let ordinaryFirst = render(ordinary, sceneTime: 1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    ordinary.state.advanceBonePhysics(animationFrame: samples, deltaTime: 0.25, frameIndex: 11)
    let ordinaryNextPose = configuration(ordinary.state)
    let ordinaryNext = render(ordinary, sceneTime: 1.1, device: device, queue: queue, atlas: atlas,
        animationFrame: samples)
    return ["kickedPose":kickedPose,
        "kicked":render(physical,sceneTime:1.6,device:device,queue:queue,atlas:atlas,animationFrame:samples).report,
        "firstPose": firstPose, "samePose": samePose, "nextPose": nextPose,
        "nextAgainPose": nextAgainPose, "laterPose": laterPose,
        "first": first.report, "same": same.report, "next": next.report, "later": later.report,
        "firstPositions": firstPositions, "samePositions": samePositions,
        "nextPositions": nextPositions, "laterPositions": laterPositions,
        "ordinaryFirstPose": ordinaryFirstPose, "ordinaryNextPose": ordinaryNextPose,
        "ordinaryFirst": ordinaryFirst.report, "ordinaryNext": ordinaryNext.report]
}


func frozenImageChecks(device: MTLDevice, queue: MTLCommandQueue,
                       pipeline: SceneImageLayerPipeline) throws -> [String: Any] {
    typealias Mesh = SceneMdlPuppetMesh
    let rects = [SIMD4<Float>(-0.8, -0.8, 0.8, 0.8), SIMD4(-0.7, -0.6, -0.1, 0.6)]
    let vertices = rects.enumerated().flatMap { index, r in [SIMD2(r.x, r.y), SIMD2(r.z, r.y),
        SIMD2(r.x, r.w), SIMD2(r.z, r.w)].map {
            Mesh.Vertex(x: $0.x, y: $0.y, z: 0, u: index == 0 ? 0.25 : 0.75, v: 0.5) } }
    let atlas = texture(device, size: 2)
    let pixels: [UInt8] = [255,255,255,255,0,0,0,0,255,255,255,255,0,0,0,0]
    pixels.withUnsafeBytes {
        atlas.replace(region: MTLRegionMake2D(0,0,2,2), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 8)
    }
    let mesh = Mesh(version: "MDLV0023", vertexStride: 80, meshBlockOffset: 9,
        vertices: vertices, indices: [0,1,2,2,1,3,4,5,6,6,5,7],
        drawParts: [.init(ordinal: 0, id: 0, flags: 0, indexOffset: 0, indexCount: 6),
                    .init(ordinal: 1, id: 1, flags: 0, indexOffset: 6, indexCount: 6)],
        clipRecords: [.init(id: 17, flags: 0, reserved: 0, maskTexturePath: "owned-paint",
            targetPartOrdinals: [0], sourcePartOrdinals: [1])])
    let base = fixture(poses: [pose(), pose(translationX: 0.6)], weight: 1, alpha: [1, 0.5])
    let rig = SceneMdlPuppetRig(bones: [base.1.bones[0], base.1.bones[0]],
        vertexWeights: vertices.indices.map {
            .init(boneIndices: SIMD4($0 < 4 ? 0 : 1,0,0,0), boneWeights: SIMD4(1,0,0,0)) })
    let poses = [pose(), pose(scale: 0.5, translationX: 0.6)]
    let animation = SceneMdlPuppetAnimation(id: 1, name: "frozen-image", mode: "single",
        framesPerSecond: 1, frameCount: 1, transformsByBone: [poses, poses],
        alphaByBone: [[1,0.5], [1,1]])
    let selection = ScenePuppetAnimationSelection(clips: [
        .init(layer: base.2.clips[0].layer, animation: animation)], composition: .layered)
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 2, height: 2, mipmapped: false)
    td.storageMode = .shared; td.usage = .shaderRead
    let paint = device.makeTexture(descriptor: td)!
    // Provider UV .75 must hit an opaque texel center with linear clamp-to-zero.
    let white: [UInt8] = [255,255,255,255]
    white.withUnsafeBytes {
        paint.replace(region: MTLRegionMake2D(0,0,2,2), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 2)
    }
    var regions: [[Int]] = []
    let clipping = ScenePuppetClipping(mesh: mesh, pipeline: ScenePuppetClipping.makePipeline(device: device),
        paintTextures: [0: paint], allocate: { _, width, height, _ in
            regions.append([width, height])
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
                width: width, height: height, mipmapped: false)
            desc.storageMode = .private; desc.usage = [.renderTarget, .shaderRead]
            return device.makeTexture(descriptor: desc).map { .init(texture: $0, release: {}) }
        })
    let output = try makePlayback((mesh, rig, selection), device: device, pipeline: pipeline, atlas: atlas, clipping: clipping)
    let a = ScenePuppetAnimationPlaybackRuntime.LayerFrame(samples: [.init(frameA: 0, frameB: 0)])
    let b = ScenePuppetAnimationPlaybackRuntime.LayerFrame(samples: [.init(frameA: 1, frameB: 1)])
    output.state.prepareFrame(animationFrame: a)
    let frozen = output.state.renderFrame!
    let initial = render(output, sceneTime: 0, device: device, queue: queue, atlas: atlas, animationFrame: a, frozenFrame: frozen)
    let initialROI = regions
    output.state.prepareFrame(animationFrame: b)
    let latest = output.state.renderFrame!
    regions.removeAll()
    let held = render(output, sceneTime: 0, device: device, queue: queue, atlas: atlas, animationFrame: a, frozenFrame: frozen)
    let heldROI = regions
    let revisionAfterHeld = output.state.renderFrame!.revision
    regions.removeAll()
    let next = render(output, sceneTime: 1, device: device, queue: queue, atlas: atlas, animationFrame: b, frozenFrame: latest)
    let latestROI = regions
    guard case let .image(oldVertices, _) = frozen.geometry,
          case let .image(newVertices, _) = latest.geometry else { fatalError("image frame") }
    func maximumAlpha(_ frame: Frame) -> UInt8 {
        stride(from: 3, to: frame.pixels.count, by: 4).map { frame.pixels[$0] }.max() ?? 0
    }
    let heldMaximumAlpha = Int(maximumAlpha(held)), nextMaximumAlpha = Int(maximumAlpha(next))
    return ["frozenVertices": oldVertices[0].position != newVertices[0].position,
        "frozenCoverage": oldVertices[0].vertexCoverage == 1 && newVertices[0].vertexCoverage == 0.5,
        "frozenPixels": initial.drew && held.drew && initial.pixels == held.pixels && next.pixels != held.pixels,
        "frozenPixelCoverage": heldMaximumAlpha == 255 && abs(nextMaximumAlpha - 128) <= 1,
        "heldMaximumAlpha": heldMaximumAlpha, "nextMaximumAlpha": nextMaximumAlpha,
        "frozenROI": !initialROI.isEmpty && initialROI == heldROI && !latestROI.isEmpty && heldROI != latestROI,
        "gpuDoesNotPrepareCPU": revisionAfterHeld == latest.revision && output.state.renderFrame!.revision == latest.revision]
}

func directPublicationChecks(device: MTLDevice, queue: MTLCommandQueue) throws -> [String: Bool] {
    let base = fixture(poses: [pose(), pose(translationX: 0.75)], weight: 1)
    let vertices = base.0.vertices.map { SceneMdlStaticModel.Vertex(position: SIMD3($0.x,$0.y,0),
        normal: SIMD3(0,0,1), tangent: SIMD4(1,0,0,1), uv: SIMD2($0.u,$0.v)) }
    let evaluator = try ScenePuppetAnimationEvaluator(bindPositions: vertices.map(\.position),
        rig: base.1, additiveAnimations: base.2.clips.map(\.animation))
    func make() throws -> (ScenePuppetPlaybackState, ScenePuppetMeshGeometry, SceneStaticModelMesh) {
        let state = try ScenePuppetPlaybackState.makeDirectModel(layerID: 42, vertices: vertices,
            evaluator: evaluator, selection: base.2).get()
        var bind = vertices, indices = base.0.indices
        let mesh = SceneStaticModelMesh(vertexBuffer: device.makeSceneBuffer(bytes: &bind,
            length: bind.count * MemoryLayout<SceneMdlStaticModel.Vertex>.stride)!,
            indexBuffer: device.makeSceneBuffer(bytes: &indices, length: indices.count * 2)!,
            boundsMinimum: SIMD3(-0.5,-0.5,0), boundsMaximum: SIMD3(0.5,0.5,0),
            vertexCount: vertices.count, indexCount: indices.count, indexType: .uint16)
        let gpu = try ScenePuppetMeshGeometry.prepareDirectModel(layerID: 42, vertices: vertices,
            mesh: mesh, pipeline: SceneStaticModelPipeline(device: device), selection: base.2).get()
        return (state, gpu, mesh)
    }
    let (state, gpu, bindMesh) = try make()
    let initialBufferCount = Observation.buffers.count
    let a = ScenePuppetAnimationPlaybackRuntime.LayerFrame(samples: [.init(frameA: 0, frameB: 0)])
    let b = ScenePuppetAnimationPlaybackRuntime.LayerFrame(samples: [.init(frameA: 1, frameB: 1)])
    state.prepareFrame(animationFrame: a); let frozen = state.renderFrame!
    state.prepareFrame(animationFrame: b); let latest = state.renderFrame!
    func publish(_ gpu: ScenePuppetMeshGeometry, _ frame: ScenePuppetPlaybackState.RenderFrame,
                 _ command: MTLCommandBuffer, _ transaction: SceneSourceUpdateTransaction) {
        gpu.publish(frame: frame, animationFrame: a, sceneTime: 0, frameIndex: 1,
            commandBuffer: command, transaction: transaction)
    }
    func read(_ mesh: SceneStaticModelMesh?) -> [SceneMdlStaticModel.Vertex]? {
        mesh.map { Array(UnsafeBufferPointer(start: $0.vertexBuffer.contents()
            .assumingMemoryBound(to: SceneMdlStaticModel.Vertex.self), count: $0.vertexCount)) }
    }
    let cb = queue.makeCommandBuffer()!, tx = SceneSourceUpdateTransaction(on: cb)
    publish(gpu, frozen, cb, tx)
    let first = gpu.directModelMesh(on: cb)!
    publish(gpu, frozen, cb, tx)
    let same = gpu.directModelMesh(on: cb)!
    let copy = device.makeBuffer(length: first.vertexCount * MemoryLayout<SceneMdlStaticModel.Vertex>.stride,
        options: .storageModeShared)!
    let blit = cb.makeBlitCommandEncoder()!
    blit.copy(from: first.vertexBuffer, sourceOffset: 0, to: copy, destinationOffset: 0, size: copy.length)
    blit.endEncoding(); tx.arm(on: cb); cb.commit(); tx.didSubmit(); cb.waitUntilCompleted()
    let gpuBytes = Array(UnsafeBufferPointer(start: copy.contents()
        .assumingMemoryBound(to: SceneMdlStaticModel.Vertex.self), count: vertices.count))
    var checks = ["frozenGPUBytes": cb.status == .completed && gpuBytes == vertices,
        "repeatDoesNotPrepareCPU": state.renderFrame!.revision == latest.revision && first.vertexBuffer === same.vertexBuffer,
        "frozenBounds": first.boundsMinimum == SIMD3(-0.5,-0.5,0) && first.boundsMaximum == SIMD3(0.5,0.5,0)]
    let wrong = queue.makeCommandBuffer()!, foreign = queue.makeCommandBuffer()!
    let wrongTX = SceneSourceUpdateTransaction(on: foreign)
    publish(gpu, frozen, wrong, wrongTX)
    checks["wrongCommandAndTransaction"] = gpu.directModelMesh(on: wrong) == nil && gpu.directModelMesh(on: cb) == nil
    wrongTX.cancel()
    var pending: [(MTLCommandBuffer, SceneSourceUpdateTransaction)] = []
    for _ in 0..<4 {
        let command = queue.makeCommandBuffer()!, transaction = SceneSourceUpdateTransaction(on: command)
        publish(gpu, latest, command, transaction); pending.append((command,transaction))
    }
    checks["busyRejectsFourth"] = gpu.directModelMesh(on: pending[3].0) == nil
    pending[0].1.cancel()
    let retry = queue.makeCommandBuffer()!, retryTX = SceneSourceUpdateTransaction(on: retry)
    publish(gpu, latest, retry, retryTX)
    let recovered = gpu.directModelMesh(on: retry)
    checks["cancelRecoversSlot"] = recovered != nil && recovered?.boundsMinimum == SIMD3(0.25,-0.5,0)
        && recovered?.boundsMaximum == SIMD3(1.25,0.5,0)
    pending.forEach { $0.1.cancel() }; retryTX.cancel()
    checks["noFrameAllocation"] = Observation.buffers.count == initialBufferCount
    let (peer, peerGPU, _) = try make()
    let peerBufferCount = Observation.buffers.count
    peer.prepareFrame(animationFrame: a)
    let peerCB = queue.makeCommandBuffer()!, peerTX = SceneSourceUpdateTransaction(on: peerCB)
    publish(peerGPU, peer.renderFrame!, peerCB, peerTX)
    checks["surfaceIsolation"] = read(peerGPU.directModelMesh(on: peerCB)) == vertices
        && peerGPU.directModelMesh(on: peerCB)?.vertexBuffer !== recovered?.vertexBuffer
        && peerGPU.directModelMesh(on: retry) == nil && state.renderFrame!.revision == latest.revision
    peerTX.cancel()
    state.prepareFrame(animationFrame: .init(samples: []))
    let fallback = state.renderFrame!
    state.prepareFrame(animationFrame: b)
    let resumed = state.renderFrame!
    let fallbackCB = queue.makeCommandBuffer()!, fallbackTX = SceneSourceUpdateTransaction(on: fallbackCB)
    publish(gpu, fallback, fallbackCB, fallbackTX)
    let fallbackMesh = gpu.directModelMesh(on: fallbackCB)
    checks["frozenBindFallback"] = read(fallbackMesh) == vertices
        && fallbackMesh?.boundsMinimum == SIMD3(-0.5,-0.5,0)
        && fallbackMesh?.boundsMaximum == SIMD3(0.5,0.5,0)
        && state.directModelPoseStatus == .animated && state.renderFrame!.revision == resumed.revision
    fallbackTX.cancel()
    let resumedCB = queue.makeCommandBuffer()!, resumedTX = SceneSourceUpdateTransaction(on: resumedCB)
    publish(gpu, resumed, resumedCB, resumedTX)
    if case let .direct(expected, _) = resumed.geometry {
        checks["fallbackRecovery"] = read(gpu.directModelMesh(on: resumedCB)) == expected
            && gpu.directModelMesh(on: resumedCB)?.boundsMaximum == SIMD3(1.25,0.5,0)
    }
    resumedTX.cancel()
    let event = device.makeSharedEvent()!
    defer { event.signaledValue = 1 }
    let heldCB = queue.makeCommandBuffer()!, heldTX = SceneSourceUpdateTransaction(on: heldCB)
    publish(gpu, frozen, heldCB, heldTX)
    let heldMesh = gpu.directModelMesh(on: heldCB)!
    heldCB.encodeWaitForEvent(event, value: 1)
    let resolved = DispatchSemaphore(value: 0)
    heldTX.registerResolution(completed: { resolved.signal() }, rollback: { resolved.signal() })
    heldTX.arm(on: heldCB); heldCB.commit(); heldTX.didSubmit(); heldTX.cancel()
    var occupied: [(MTLCommandBuffer, SceneSourceUpdateTransaction)] = []
    var differentBuffers = true
    for index in 0..<3 {
        let command = queue.makeCommandBuffer()!, transaction = SceneSourceUpdateTransaction(on: command)
        publish(gpu, latest, command, transaction)
        if index < 2 {
            differentBuffers = differentBuffers && gpu.directModelMesh(on: command)?.vertexBuffer !== heldMesh.vertexBuffer
        }
        occupied.append((command, transaction))
    }
    checks["submittedCancelKeepsSlot"] = differentBuffers && read(heldMesh) == vertices
        && gpu.directModelMesh(on: occupied[2].0) == nil
    event.signaledValue = 1
    guard resolved.wait(timeout: .now() + 10) == .success else {
        throw NSError(domain: "PuppetPublication", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "submitted vertex lease did not resolve"])
    }
    let completedCB = queue.makeCommandBuffer()!, completedTX = SceneSourceUpdateTransaction(on: completedCB)
    publish(gpu, latest, completedCB, completedTX)
    checks["completionRecoversSlot"] = heldCB.status == .completed
        && gpu.directModelMesh(on: completedCB)?.vertexBuffer === heldMesh.vertexBuffer
    occupied.forEach { $0.1.cancel() }; completedTX.cancel()
    checks["noFrameAllocation"] = checks["noFrameAllocation"]! && Observation.buffers.count == peerBufferCount
    checks["repeatDoesNotPrepareCPU"] = checks["repeatDoesNotPrepareCPU"]!
        && state.renderFrame!.revision == resumed.revision
    let invalid = ScenePuppetMeshGeometry.prepareDirectModel(layerID: 42, vertices: [], mesh: bindMesh,
        pipeline: SceneStaticModelPipeline(device: device), selection: base.2)
    if case .failure(.invalidVertices) = invalid { checks["factoryCount"] = true }
    else { checks["factoryCount"] = false }
    return checks
}

@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
        let library = try device.makeLibrary(URL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let pipeline = SceneImageLayerPipeline(device: device, library: library)!
        let atlas = texture(device, size: 2)
        let white = [UInt8](repeating: 255, count: 2 * 2 * 4)
        white.withUnsafeBytes {
            atlas.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
                          withBytes: $0.baseAddress!, bytesPerRow: 2 * 4)
        }
        let validityFixture = fixture(poses: [pose(), pose(scale: 0)], weight: 1, alpha: [1, 0])
        let validity = try makePlayback(validityFixture, device: device,
                                        pipeline: pipeline, atlas: atlas)
        let initialBuffers = bufferBytes(Observation.buffers)
        let firstFailure = render(validity, sceneTime: 1, device: device, queue: queue, atlas: atlas,
            animationFrame: .init(samples: [.init(frameA: 2, frameB: 2)]))
        let rejectedEvidence = Observation.evidence.isEmpty
        let rejectedBuffers = bufferBytes(Observation.buffers) == initialBuffers
        let firstRecovery = render(validity, sceneTime: 0, device: device, queue: queue, atlas: atlas)
        let collapsed = render(validity, sceneTime: 1, device: device, queue: queue, atlas: atlas)
        let collapseRecovery = render(validity, sceneTime: 0, device: device, queue: queue, atlas: atlas)

        // Large but finite scale leaves the first vertex finite and overflows
        // the second. Verify the fixture reaches a genuinely partial write.
        let partialFixture = fixture(poses: [pose(), pose(scale: 1e6),
            pose(translationX: 5e-25)], weight: 1e30, wideVertex: true,
            alpha: [1, 0.25, 1])
        let evaluator = try ScenePuppetAnimationEvaluator(mesh: partialFixture.0,
            rig: partialFixture.1, additiveAnimations: partialFixture.2.clips.map(\.animation))
        let sentinel = SIMD2<Float>(-123, -456)
        var points = [SIMD2<Float>](repeating: sentinel, count: 3)
        var locals = [matrix_identity_float4x4], skins = locals, worlds = locals
        var partialRejected = false
        do {
            try points.withUnsafeMutableBufferPointer {
                try evaluator.writeDeformedPositions(selection: partialFixture.2,
                    frameSamples: [.init(frameA: 1, frameB: 1)], into: $0,
                    localMatricesScratch: &locals, skinMatricesScratch: &skins,
                    worldMatricesScratch: &worlds)
            }
        } catch let error as ScenePuppetAnimationEvaluationFailure {
            partialRejected = error == .invalidDeformedVertex
        }
        let verifiedPartialWrite = partialRejected && points[0] != sentinel
            && points[0].x.isFinite && points[0].y.isFinite
            && points[1] == sentinel && points[2] == sentinel
        Observation.buffers.removeAll()
        Observation.evidence.removeAll()
        let partial = try makePlayback(partialFixture, device: device,
                                       pipeline: pipeline, atlas: atlas)
        let mvp = SceneMatrix.translation(SIMD3<Float>(-0.5, 0, 0))
            * SceneMatrix.scale(SIMD3<Float>(1e-6, 1, 1))
        let good = render(partial, sceneTime: 0, device: device, queue: queue, atlas: atlas, mvp: mvp)
        let goodBuffers = bufferBytes(Observation.buffers)
        let goodEvidence = Observation.evidence.last!
        let failed = render(partial, sceneTime: 1, device: device, queue: queue, atlas: atlas, mvp: mvp)
        let retainedBuffers = bufferBytes(Observation.buffers) == goodBuffers
        let retainedEvidence = Observation.evidence.last == goodEvidence
        let recovered = render(partial, sceneTime: 2, device: device, queue: queue, atlas: atlas, mvp: mvp)
        let refreshedBuffers = bufferBytes(Observation.buffers) != goodBuffers
        let refreshedEvidence = Observation.evidence.last != goodEvidence

        // Premultiplied BGRA plus independent layer opacity makes missing or
        // repeated bone coverage observable in both color and alpha channels.
        let coloredAtlas = texture(device, size: 2)
        let coloredPixels: [UInt8] = (0..<4).flatMap { _ in [32, 64, 96, 128] }
        coloredPixels.withUnsafeBytes {
            coloredAtlas.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 2 * 4)
        }
        let ordinary = render(sceneTime: 0, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, ordinaryPipeline: pipeline)
        let opaque = try makePlayback(fixture(poses: [pose(), pose()], weight: 1),
            device: device, pipeline: pipeline, atlas: coloredAtlas)
        let absentAlpha = render(opaque, sceneTime: 0, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let opaqueBuffers = bufferBytes(Observation.buffers)
        let absentAlphaLater = render(opaque, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let staticBuffersUnchanged = bufferBytes(Observation.buffers) == opaqueBuffers

        let alphaOnly = try makePlayback(fixture(poses: [pose(), pose()], weight: 1,
            alpha: [1, 0], visibilityBinding: "enabled"), device: device,
            pipeline: pipeline, atlas: coloredAtlas)
        let fullAlpha = render(alphaOnly, sceneTime: 0, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let fullBuffers = bufferBytes(Observation.buffers)
        let halfAlpha = render(alphaOnly, sceneTime: 0.5, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let halfBuffers = bufferBytes(Observation.buffers)
        let alphaOnlyBuffersChanged = halfBuffers != fullBuffers
        let halfAgain = render(alphaOnly, sceneTime: 0.5, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let repeatedAlphaBuffersUnchanged = bufferBytes(Observation.buffers) == halfBuffers
        let zeroAlpha = render(alphaOnly, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let hiddenAlpha = render(alphaOnly, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: false)
        let visibleAgain = render(alphaOnly, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5, clipVisible: true)
        let alphaOnlyAttachmentsUnchanged = [halfAlpha, halfAgain, zeroAlpha,
            hiddenAlpha, visibleAgain].allSatisfy { $0.attachments == fullAlpha.attachments }
        let alphaOnlyPositionsUnchanged = Observation.evidence.suffix(6).allSatisfy {
            $0 == [SIMD2<Float>(-0.5, -0.5), SIMD2<Float>(0.5, -0.5), SIMD2<Float>(0, 0.5)]
        }

        let mixed = try makePlayback(weightedFixture(alpha: [0, 1, 0, 0],
            weights: SIMD4(2, 2, 2, 2)), device: device, pipeline: pipeline,
            atlas: coloredAtlas)
        let mixedFrame = render(mixed, sceneTime: 0.5, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let inherited = try makePlayback(weightedFixture(alpha: [0.5, 0.5, 0.5, 0.5],
            weights: SIMD4(0, 0, 0, 3)), device: device, pipeline: pipeline,
            atlas: coloredAtlas)
        let inheritedFrame = render(inherited, sceneTime: 0.5, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let inheritedBuffers = bufferBytes(Observation.buffers)
        let inheritedLater = render(inherited, sceneTime: 1, device: device, queue: queue,
            atlas: coloredAtlas, layerAlpha: 0.5)
        let constantAlphaBuffersUnchanged = bufferBytes(Observation.buffers) == inheritedBuffers
        var blendedAlpha: [String: [String: Any]] = [:]
        for weight in [Double(0), 0.5, 2] {
            let output = try makePlayback(fixture(poses: [pose(), pose()], weight: weight,
                alpha: [0, 0]), device: device, pipeline: pipeline, atlas: coloredAtlas)
            blendedAlpha[String(weight)] = render(output, sceneTime: 0.5,
                device: device, queue: queue, atlas: coloredAtlas, layerAlpha: 0.5).report
        }

        let fogSource = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
        let colorBlend = SceneLayerColorBlendPipelineState(device: device, fogShaderSource: fogSource)!
        let ordinaryColorBlend = render(sceneTime: 0, device: device, queue: queue,
            atlas: coloredAtlas, colorBlendState: colorBlend)
        var colorBlendFrames: [String: [String: Any]] = [:]
        var colorBlendMultiplyFrames: [String: [String: Any]] = [:]
        for (name, time) in [("full", Double(0)), ("half", 0.5), ("zero", 1)] {
            colorBlendFrames[name] = render(alphaOnly, sceneTime: time, device: device,
                queue: queue, atlas: coloredAtlas, clipVisible: true,
                colorBlendState: colorBlend).report
            colorBlendMultiplyFrames[name] = render(alphaOnly, sceneTime: time,
                device: device, queue: queue, atlas: coloredAtlas, clipVisible: true,
                colorBlendState: colorBlend, colorBlendMode: 2).report
        }
        let multiAlpha = try multiAlphaChecks(device: device, queue: queue,
            pipeline: pipeline, atlas: coloredAtlas)

        let sharedFixture = fixture(poses: [pose(), pose(translationX: 0.25)],
            weight: 1, alpha: [1, 0], visibilityBinding: "enabled")
        let sharedRuntime = ScenePuppetAnimationPlaybackRuntime()
        try sharedRuntime.register(layerID: 42, selection: sharedFixture.2,
            authoredLayers: sharedFixture.2.clips.map(\.layer)).get()
        func sharedFrame(_ index: UInt64, _ time: Double, _ visible: Bool)
            -> ScenePuppetAnimationPlaybackRuntime.LayerFrame {
            sharedRuntime.advance(frameIndex: index, sceneTime: time,
                dynamicValues: .init(frameIndex: index, values: [
                    ScenePuppetAnimationPropertyTarget.visibility(layerID: 42, animationLayerID: 1):
                        .init(value: .bool(visible))]))[42]!
        }
        let surfaceA = try makePlayback(sharedFixture, device: device, pipeline: pipeline, atlas: coloredAtlas)
        let startSamples = sharedFrame(0, 0, true)
        _ = render(surfaceA, sceneTime: 0, device: device, queue: queue, atlas: coloredAtlas,
            animationFrame: startSamples, layerAlpha: 0.5)
        _ = sharedFrame(1, 0.25, true)
        // No drawable or encode consumes these simulated cadences. Visibility
        // and position still progress at the shared simulation boundary.
        _ = sharedFrame(2, 0.5, false)
        let hiddenSamples = sharedFrame(3, 2, false)
        let hiddenShared = render(surfaceA, sceneTime: 2, device: device, queue: queue,
            atlas: coloredAtlas, animationFrame: hiddenSamples, layerAlpha: 0.5)
        let resumeSamples = sharedFrame(4, 2.25, true)
        surfaceA.state.advanceBonePhysics(animationFrame: resumeSamples, deltaTime: 0.25, frameIndex: 4)
        let resumedPose = surfaceA.state.poseConfiguration(animationFrame: resumeSamples)!
        let resumedAttachments = surfaceA.state.prepareFrame(animationFrame: resumeSamples)
        let resumedA = render(surfaceA, sceneTime: 2.25, device: device, queue: queue,
            atlas: coloredAtlas, animationFrame: resumeSamples, layerAlpha: 0.5)
        // A second surface/rebuild registers the same definition without resetting.
        try sharedRuntime.register(layerID: 42, selection: sharedFixture.2,
            authoredLayers: sharedFixture.2.clips.map(\.layer)).get()
        let surfaceB = try makePlayback(sharedFixture, device: device, pipeline: pipeline, atlas: coloredAtlas)
        let duplicateSamples = sharedFrame(4, 200, false)
        let resumedB = render(surfaceB, sceneTime: 2.25, device: device, queue: queue,
            atlas: coloredAtlas, animationFrame: duplicateSamples, layerAlpha: 0.5)
        // Pause keeps identical sample indices; blend must still invalidate the
        // prepared geometry and update alpha in the actual Metal draw.
        let controlledBase = fixture(poses: [pose(), pose()], weight: 1)
        let controlledFixture = (controlledBase.0, controlledBase.1,
            ScenePuppetAnimationSelection(clips: pairedClips(alpha: [0.5, 0.5], peer: [1, 1]), composition: .layered))
        let controlled = try makePlayback(controlledFixture, device: device,
            pipeline: pipeline, atlas: coloredAtlas)
        let controls = ScenePuppetAnimationPlaybackRuntime()
        try controls.register(layerID: 42, selection: controlledFixture.2,
            authoredLayers: controlledFixture.2.clips.map(\.layer)).get()
        let identity = ScenePuppetAnimationIdentity(layerID: 42,
            animationLayerIndex: 0, animationLayerID: 1)
        _ = controls.advance(frameIndex: 0, sceneTime: 0,
            dynamicValues: .init(frameIndex: 0, values: [:]))
        try controls.apply([
            .init(identity: identity, action: .pause, callbackEpoch: 1, ordinal: 0),
            .init(identity: identity, action: .setFrame(0), callbackEpoch: 1, ordinal: 1),
            .init(identity: identity, action: .setBlend(0.5), callbackEpoch: 1, ordinal: 2)
        ], frameIndex: 0).get()
        let halfBlend = controls.advance(frameIndex: 1, sceneTime: 1,
            dynamicValues: .init(frameIndex: 1, values: [:]))[42]!
        let dynamicHalfBlend = render(controlled, sceneTime: 1, device: device,
            queue: queue, atlas: coloredAtlas, animationFrame: halfBlend, layerAlpha: 0.5)
        let dynamicHalfBuffers = bufferBytes(Observation.buffers)
        try controls.apply([.init(identity: identity, action: .setBlend(1),
            callbackEpoch: 2, ordinal: 0)], frameIndex: 1).get()
        let fullBlend = controls.advance(frameIndex: 2, sceneTime: 2,
            dynamicValues: .init(frameIndex: 2, values: [:]))[42]!
        let dynamicFullBlend = render(controlled, sceneTime: 2, device: device,
            queue: queue, atlas: coloredAtlas, animationFrame: fullBlend, layerAlpha: 0.5)
        let dynamicBlendBuffersChanged = dynamicHalfBuffers != bufferBytes(Observation.buffers)
        let queryRenderTranslation = try translationPoseChecks(device: device, queue: queue,
            pipeline: pipeline, atlas: atlas)
        let frozenImage = try frozenImageChecks(device: device, queue: queue, pipeline: pipeline)
        let directPublication = try directPublicationChecks(device: device, queue: queue)
        let result: [String: Any] = [
            "frozenImage": frozenImage, "directPublication": directPublication,
            "queryRenderTranslation": queryRenderTranslation,
            "metalDevice": device.name,
            "dynamicHalfBlend": dynamicHalfBlend.report,
            "dynamicFullBlend": dynamicFullBlend.report,
            "dynamicBlendSamplesEqual": halfBlend.samples == fullBlend.samples,
            "dynamicBlendBuffersChanged": dynamicBlendBuffersChanged,
            "firstFailure": firstFailure.report, "firstRecovery": firstRecovery.report,
            "collapsed": collapsed.report, "collapseRecovery": collapseRecovery.report,
            "firstFailureBuffersUntouched": rejectedBuffers,
            "firstFailureHasNoEvidence": rejectedEvidence,
            "verifiedPartialWrite": verifiedPartialWrite,
            "good": good.report, "partialFailure": failed.report, "recovered": recovered.report,
            "partialFailureBuffersUnchanged": retainedBuffers,
            "partialFailurePixelsUnchanged": failed.pixels == good.pixels,
            "partialFailureAttachmentsUnchanged": failed.attachments == good.attachments,
            "partialFailureEvidenceUnchanged": retainedEvidence,
            "recoveryBuffersChanged": refreshedBuffers,
            "recoveryPixelsChanged": recovered.pixels != good.pixels,
            "recoveryAttachmentsChanged": recovered.attachments != good.attachments,
            "recoveryEvidenceChanged": refreshedEvidence,
            "quadVertexStride": MemoryLayout<SceneQuadVertex>.stride,
            "quadVertexDefaultCoverage": SceneQuadVertex(position: .zero, texcoord: .zero).vertexCoverage,
            "ordinaryQuad": ordinary.report, "absentAlpha": absentAlpha.report,
            "absentAlphaLater": absentAlphaLater.report,
            "staticBuffersUnchanged": staticBuffersUnchanged,
            "fullAlpha": fullAlpha.report, "halfAlpha": halfAlpha.report,
            "halfAlphaAgain": halfAgain.report, "zeroAlpha": zeroAlpha.report,
            "hiddenAlpha": hiddenAlpha.report, "visibleAgain": visibleAgain.report,
            "alphaOnlyBuffersChanged": alphaOnlyBuffersChanged,
            "repeatedAlphaBuffersUnchanged": repeatedAlphaBuffersUnchanged,
            "alphaOnlyAttachmentsUnchanged": alphaOnlyAttachmentsUnchanged,
            "alphaOnlyPositionsUnchanged": alphaOnlyPositionsUnchanged,
            "mixedWeights": mixedFrame.report, "inheritedAlpha": inheritedFrame.report,
            "inheritedAlphaLater": inheritedLater.report,
            "constantAlphaBuffersUnchanged": constantAlphaBuffersUnchanged,
            "blendedAlpha": blendedAlpha,
            "ordinaryColorBlend": ordinaryColorBlend.report,
            "colorBlendFrames": colorBlendFrames,
            "colorBlendMultiplyFrames": colorBlendMultiplyFrames,
            "multiAlpha": multiAlpha,
            "sharedHidden": hiddenShared.report, "sharedResumedA": resumedA.report,
            "sharedResumedB": resumedB.report,
            "sharedResumedPoseX": resumedPose.bones.localMatrices[12],
            "sharedResumedAttachmentX": resumedAttachments["tip"]!.columns.3.x,
            "sharedSurfacePixelsMatch": resumedA.pixels == resumedB.pixels,
            "sharedSurfaceAttachmentsMatch": resumedA.attachments == resumedB.attachments,
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,
            options: [.sortedKeys]), as: UTF8.self))
    }
}

final class ScenePuppetBoneEvidence {
    static func isEnabled(for layerID: Int) -> Bool { true }
    func record(layerID: Int, revision: UInt64, frame: UInt64, sceneTime: Double,
                scriptWritten: Bool, displacement: Float,
                positions: [SIMD2<Float>], commandBuffer: MTLCommandBuffer) {
        Observation.evidence.append(positions)
    }
    func recordDirect<Vertices: RandomAccessCollection, BindVertices: RandomAccessCollection>(
                      layerID: Int, revision: UInt64, frame: UInt64, sceneTime: Double,
                      poseStatus: String, selection: ScenePuppetAnimationSelection,
                      animationFrame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
                      vertices: Vertices, bindVertices: BindVertices, commandBuffer: MTLCommandBuffer)
        where Vertices.Element == SceneMdlStaticModel.Vertex, BindVertices.Element == SceneMdlStaticModel.Vertex {}
}

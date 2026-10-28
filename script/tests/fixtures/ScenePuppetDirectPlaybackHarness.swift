import Foundation
import simd

// Deterministic Metal leaves only. Image encoder leaves trap if executed;
// direct tests cannot accidentally perform an image draw or create a GPU.
protocol MTLDevice: AnyObject {}
protocol MTLBuffer: AnyObject {
    var device: MTLDevice { get }
    var length: Int { get }
    var label: String? { get set }
    func contents() -> UnsafeMutableRawPointer
}
enum MTLIndexType { case uint16, uint32 }
enum MTLPrimitiveType { case triangle }
enum MTLCommandBufferStatus { case notEnqueued, committed, completed, error }
struct MTLResourceOptions: OptionSet {
    let rawValue: Int
    static let storageModeShared = MTLResourceOptions(rawValue: 1)
}
protocol MTLCommandBuffer: AnyObject {
    var device: MTLDevice { get }
    var status: MTLCommandBufferStatus { get }
    func addCompletedHandler(_ handler: @escaping (MTLCommandBuffer) -> Void)
}
final class MTLTexture {}
final class MTLRenderPipelineState {}
final class MTLRenderCommandEncoder {
    func setRenderPipelineState(_ state: MTLRenderPipelineState) { preconditionFailure() }
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) { preconditionFailure() }
    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) { preconditionFailure() }
    func setFragmentTexture(_ texture: MTLTexture, index: Int) { preconditionFailure() }
    func setVertexBuffer(_ buffer: MTLBuffer, offset: Int, index: Int) { preconditionFailure() }
    func drawIndexedPrimitives(type: MTLPrimitiveType, indexCount: Int, indexType: MTLIndexType,
                               indexBuffer: MTLBuffer, indexBufferOffset: Int) { preconditionFailure() }
}
struct SceneImageLayerPipeline {
    let state = MTLRenderPipelineState()
    static func bindClipMask(encoder: MTLRenderCommandEncoder, texture: MTLTexture) { preconditionFailure() }
}
struct SceneLayerFragmentUniforms {}
enum SceneEffectSourceExtentContract { case exactSamplingTexture }
// PRODUCT_QUAD
final class ScenePuppetClipping {
    func prepare(commandBuffer: MTLCommandBuffer, extent: SIMD2<Int>, mvp: simd_float4x4,
                 retainAuxiliary: SceneGeometryProduct.AuxiliaryRetainer,
                 vertexCoverageVaries: Bool = true,
                 vertices: [SceneQuadVertex], vertexBuffer: MTLBuffer, indexBuffer: MTLBuffer) {
        preconditionFailure()
    }
    func draw(encoder: MTLRenderCommandEncoder, sourceTexture: MTLTexture, indexBuffer: MTLBuffer) {
        preconditionFailure()
    }
}
enum SceneDynamicTarget: Hashable { case scriptInstanceProperty(layerID: Int, path: [String]) }
enum SceneDynamicValue { case bool(Bool), scalar(Double) }
enum SceneDynamicSource: Equatable { case authored, userProperty, timeline, sceneScript }
struct SceneDynamicResolvedValue { let value: SceneDynamicValue; let source: SceneDynamicSource }
struct SceneDynamicSnapshot {
    let frameIndex: UInt64
    let values: [SceneDynamicTarget: SceneDynamicResolvedValue]
    init(frameIndex: UInt64, values: [SceneDynamicTarget: SceneDynamicResolvedValue] = [:]) {
        self.frameIndex = frameIndex; self.values = values
    }
    subscript(target: SceneDynamicTarget) -> SceneDynamicResolvedValue? { values[target] }
}
struct SceneScriptPuppetBoneMutation {
    enum Operation { case matrix([Double]), impulse(SIMD3<Double>) }
    let layerID: Int, boneIndex: Int
    let operation: Operation
    init(layerID: Int, boneIndex: Int, matrix: [Double]) {
        self.layerID = layerID
        self.boneIndex = boneIndex
        self.operation = .matrix(matrix)
    }
}
enum ScenePuppetLayerLoad {
    struct BoneConfiguration {
        let names: [String], parentIndices: [Int]
        let worldMatrices: [Double], localMatrices: [Double]
    }
}
final class Buffer: MTLBuffer {
    let device: MTLDevice
    let length: Int
    var label: String?
    let storage: UnsafeMutableRawPointer
    init(_ device: MTLDevice, _ length: Int) {
        self.device = device; self.length = length
        storage = .allocate(byteCount: length, alignment: 16)
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: length)
    }
    func contents() -> UnsafeMutableRawPointer { storage }
    deinit { storage.deallocate() }
}
final class Device: MTLDevice { var allocations = 0 }
extension MTLDevice {
    func makeSceneBuffer(length: Int, options: MTLResourceOptions = []) -> MTLBuffer? {
        (self as! Device).allocations += 1
        return Buffer(self, length)
    }
    func makeSceneBuffer(bytes: UnsafeRawPointer, length: Int) -> MTLBuffer? {
        let result = makeSceneBuffer(length: length)!
        result.contents().copyMemory(from: bytes, byteCount: length)
        return result
    }
}
final class Command: MTLCommandBuffer {
    let device: MTLDevice
    var status = MTLCommandBufferStatus.notEnqueued
    var handlers: [(MTLCommandBuffer) -> Void] = []
    init(_ device: MTLDevice) { self.device = device }
    func addCompletedHandler(_ handler: @escaping (MTLCommandBuffer) -> Void) { handlers.append(handler) }
    func complete(_ success: Bool = true) {
        status = success ? .completed : .error
        for handler in handlers { handler(self) }
    }
}
func columns(_ matrix: simd_float4x4) -> [Float] {
    (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
}
func transform(z: Float = 0, scale: Float = 1) -> SceneMdlPuppetAnimation.Transform {
    .init(translation: SIMD3(0, 0, z), rotation: .zero, scale: SIMD3(repeating: scale))
}
struct Subject {
    let state: ScenePuppetPlaybackState
    let mesh: SceneStaticModelMesh
    let vertices: [SceneMdlStaticModel.Vertex]
    let selection: ScenePuppetAnimationSelection
    let evaluator: ScenePuppetAnimationEvaluator
}
func makeSubject(_ device: Device, lateSingular: Bool = false, channel: String? = nil,
             renamed: Bool = false,
             latePosition: SIMD3<Float>? = nil,
             physics: [SceneMdlPuppetRig.TranslationPhysics?] = [nil, nil]) throws -> Subject {
    let vertices = (0..<2).map { index in
        SceneMdlStaticModel.Vertex(position: index == 1 ? latePosition ?? SIMD3(2, 2, 3) : SIMD3(1, 2, 3),
            normal: SIMD3(2, 1, 0), tangent: SIMD4(1, -2, 1, -1), uv: SIMD2(0.25, 0.75))
    }
    let identity = columns(matrix_identity_float4x4)
    let rig = SceneMdlPuppetRig(bones: physics.enumerated().map { index, configuration in
        .init(name: "bone-\(index)", parentIndex: -1, bindLocalMatrixColumnMajor: identity,
              translationPhysics: configuration)
    }, vertexWeights: (0..<2).map { index in
        .init(boneIndices: SIMD4(UInt32(index), 0, 0, 0), boneWeights: SIMD4(1, 0, 0, 0))
    })
    let animation = SceneMdlPuppetAnimation(id: 7, name: renamed ? "renamed-motion" : "motion",
        mode: "loop", framesPerSecond: 1, frameCount: 1,
        transformsByBone: physics.indices.map { index in
            [transform(), transform(z: 4, scale: lateSingular && index == 1 ? 0 : 1)]
        })
    var animations = [animation]
    var layers = [ScenePuppetAnimationLayer(id: 71, animationID: 7, name: "base", additive: false,
        blend: 1, blendIn: false, blendOut: false, blendTime: 0, rate: 1, visible: true,
        visibilityBinding: nil)]
    if let channel {
        animations.append(SceneMdlPuppetAnimation(id: 8, name: "hidden-channel", mode: "loop",
            framesPerSecond: 1, frameCount: 1,
            transformsByBone: [[transform(), transform()], [transform(), transform()]],
            alphaByBone: channel == "alpha" ? [[1, 0.5], [1, 1]] : nil,
            hasAuxiliaryScalarTrack: channel == "aux"))
        layers.append(ScenePuppetAnimationLayer(id: 72, animationID: 8, name: "optional", additive: true,
            blend: 1, blendIn: false, blendOut: false, blendTime: 0, rate: 1, visible: false,
            visibilityBinding: "toggle"))
    }
    guard case let .success(selection?) = ScenePuppetAnimationSelector.select(layers: layers,
        animationSet: .init(boneCount: 2, animations: animations)) else { fatalError("selector") }
    let evaluator = try ScenePuppetAnimationEvaluator(bindPositions: vertices.map(\.position), rig: rig,
        additiveAnimations: selection.clips.map(\.animation))
    let vertexBuffer = device.makeSceneBuffer(length: 128)!
    let mesh = SceneStaticModelMesh(vertexBuffer: vertexBuffer,
        indexBuffer: device.makeSceneBuffer(length: 6)!, boundsMinimum: SIMD3(1, 2, 3),
        boundsMaximum: SIMD3(2, 2, 3), vertexCount: 2, indexCount: 3, indexType: .uint16)
    guard case let .success(state) = ScenePuppetPlaybackState.makeDirectModel(layerID: renamed ? 989 : 42,
        vertices: vertices, mesh: mesh, evaluator: evaluator, selection: selection,
        pipeline: SceneStaticModelPipeline(device: device)) else { fatalError("factory") }
    return Subject(state: state, mesh: mesh, vertices: vertices, selection: selection, evaluator: evaluator)
}
func frame(_ index: Int, hidden: Bool = true) -> ScenePuppetAnimationPlaybackRuntime.LayerFrame {
    .init(samples: [.init(frameA: index, frameB: index), hidden ? nil : .init(frameA: index, frameB: index)])
}
func singleFrame(_ index: Int) -> ScenePuppetAnimationPlaybackRuntime.LayerFrame {
    .init(samples: [.init(frameA: index, frameB: index)])
}
@discardableResult
func encode(_ subject: Subject, _ frame: ScenePuppetAnimationPlaybackRuntime.LayerFrame,
            _ command: Command, _ transaction: SceneSourceUpdateTransaction? = nil)
    -> SceneSourceUpdateTransaction {
    let transaction = transaction ?? SceneSourceUpdateTransaction(on: command)
    _ = subject.state.encode(animationFrame: frame, sceneTime: 1,
        dynamicValues: .init(frameIndex: 1), commandBuffer: command, transaction: transaction)
    return transaction
}
func read(_ mesh: SceneStaticModelMesh?) -> [SceneMdlStaticModel.Vertex]? {
    guard let mesh else { return nil }
    let mirror = Mirror(reflecting: mesh)
    let buffer = mirror.children.first { $0.label == "vertexBuffer" }!.value as! MTLBuffer
    return Array(UnsafeBufferPointer(start: buffer.contents()
        .assumingMemoryBound(to: SceneMdlStaticModel.Vertex.self), count: mesh.vertexCount))
}

func finiteOutputFallbackChecks(_ device: Device) throws -> [String: Bool] {
    // Every bind channel and matrix is finite. Only the second current skin
    // output overflows, after a different first vertex has already been written.
    let cases: [(String, SIMD3<Float>, SIMD3<Float>)] = [
        ("latePositionOverflowFallback", SIMD3(0, 0, 3), SIMD3(1, 1, 3e38)),
        ("lateNormalOverflowFallback", .zero, SIMD3(1e-40, 1, 1)),
        ("lateTangentOverflowFallback", .zero, SIMD3(1, 3e38, 1))
    ]
    var rows: [String: Bool] = [:]
    for (name, position, scale) in cases {
        let subject = try makeSubject(device, latePosition: position)
        var matrix = matrix_identity_float4x4
        matrix.columns.0.x = scale.x; matrix.columns.1.y = scale.y; matrix.columns.2.z = scale.z
        var partial = subject.vertices
        var local = Array(repeating: matrix_identity_float4x4, count: subject.evaluator.boneCount)
        var skin = local, world = local
        var lateFailure = false
        do {
            try partial.withUnsafeMutableBufferPointer {
                try subject.evaluator.writeDeformedVertices(bindVertices: subject.vertices,
                    selection: subject.selection, frameSamples: singleFrame(1).samples, into: $0,
                    localMatricesScratch: &local, skinMatricesScratch: &skin,
                    worldMatricesScratch: &world, boneOverrides: [1: matrix])
            }
        } catch let failure as ScenePuppetAnimationEvaluator.DirectSkinningFailure {
            lateFailure = failure == .invalidVertex(1)
        }
        let firstWasWritten = partial[0].position == SIMD3(1, 2, 7)
            && partial[0].normal == subject.vertices[0].normal
            && partial[0].tangent == subject.vertices[0].tangent
            && partial[0].uv == subject.vertices[0].uv && partial[1] == subject.vertices[1]
        subject.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 1,
            matrix: columns(matrix).map(Double.init))])
        let command = Command(device), tx = encode(subject, singleFrame(1), command)
        guard let mesh = subject.state.directModelMesh(on: command) else {
            rows[name] = false; tx.cancel(); continue
        }
        let bindBytes = subject.vertices.withUnsafeBytes { Data($0) }
        let outputBytes = Data(bytes: mesh.vertexBuffer.contents(), count: bindBytes.count)
        let wholeBind = subject.state.directModelPoseStatus == .bindFallback(.invalidSkinFrame)
            && outputBytes == bindBytes && read(mesh) == subject.vertices
            && mesh.boundsMinimum == SIMD3(0, 0, position.z)
            && mesh.boundsMaximum == SIMD3(1, 2, 3)
        tx.cancel()
        subject.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 1,
            matrix: columns(matrix_identity_float4x4).map(Double.init))])
        let restored = Command(device), restoredTX = encode(subject, singleFrame(1), restored)
        let resumed = read(subject.state.directModelMesh(on: restored))
        rows[name] = lateFailure && firstWasWritten && wholeBind
            && subject.state.directModelPoseStatus == .animated
            && resumed?[0].position == SIMD3(1, 2, 7) && resumed?[1] == subject.vertices[1]
        restoredTX.cancel()
    }
    let subject = try makeSubject(device, latePosition: .zero)
    var scale = matrix_identity_float4x4
    scale.columns.0.x = 2; scale.columns.1.y = 3; scale.columns.2.z = 4
    subject.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 1,
        matrix: columns(scale).map(Double.init))])
    let command = Command(device), tx = encode(subject, singleFrame(1), command)
    let mesh = subject.state.directModelMesh(on: command), values = read(mesh)
    let expected = SceneMdlStaticModel.Vertex(position: .zero,
        normal: SIMD3(1, Float(1.0 / 3.0), 0), tangent: SIMD4(2, -6, 4, -1), uv: SIMD2(0.25, 0.75))
    rows["finiteAffineOutputAndCurrentBounds"] = subject.state.directModelPoseStatus == .animated
        && values?[0].position == SIMD3(1, 2, 7) && values?[1] == expected
        && mesh?.boundsMinimum == SIMD3<Float>.zero && mesh?.boundsMaximum == SIMD3(1, 2, 7)
    tx.cancel()
    return rows
}

func physicsSubsetChecks(_ device: Device) throws -> Bool {
    let configurations: [SceneMdlPuppetRig.TranslationPhysics?] = [nil,
        .init(spring: true, stiffness: 70, friction: 5, inertia: 5, maxDistance: 50), nil,
        .init(spring: true, stiffness: 140, friction: 9, inertia: 3, maxDistance: 50)]
    let subject = try makeSubject(device, physics: configurations)
    let written: [Float] = [0.25, 0.45, 0.65, 0.85]
    subject.state.apply(scriptBoneMutations: written.enumerated().map { index, origin in
        var matrix = matrix_identity_float4x4; matrix.columns.3.z = origin
        return .init(layerID: 42, boneIndex: index, matrix: columns(matrix).map(Double.init))
    })
    var motions = configurations.map { _ in ScenePuppetTranslationMotion() }
    var expected = written
    var valid = true
    for cadence in UInt64(10)...11 {
        for index in configurations.indices {
            guard let config = configurations[index] else { continue }
            expected[index] = motions[index].advance(
                position: SIMD3(0, 0, expected[index]), target: .zero,
                deltaTime: 0.05, configuration: config).z
        }
        subject.state.advanceBonePhysics(animationFrame: singleFrame(0), deltaTime: 0.05, frameIndex: cadence)
        let pose = subject.state.poseConfiguration(animationFrame: singleFrame(0))!
        for index in configurations.indices {
            valid = valid && abs(pose.bones.localMatrices[index * 16 + 14] - Double(expected[index])) < 1e-6
                && abs(pose.queryLocalMatrices[index * 16 + 14]
                    - Double(configurations[index] == nil ? written[index] : 0)) < 1e-6
        }
    }
    let before = subject.state.poseConfiguration(animationFrame: singleFrame(0))!.bones.localMatrices
    subject.state.advanceBonePhysics(animationFrame: singleFrame(0), deltaTime: 0.25, frameIndex: 11)
    valid = valid && before == subject.state.poseConfiguration(animationFrame: singleFrame(0))!.bones.localMatrices
        && expected[1] != written[1] && expected[3] != written[3]
    let ordinary = try makeSubject(device)
    var matrix = matrix_identity_float4x4; matrix.columns.3.z = 0.75
    ordinary.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 1,
        matrix: columns(matrix).map(Double.init))])
    ordinary.state.advanceBonePhysics(animationFrame: singleFrame(0), deltaTime: 0.05, frameIndex: 10)
    return valid && ordinary.state.poseConfiguration(animationFrame: singleFrame(0))!.bones.localMatrices[30] == 0.75
}
@main enum Main {
    static func main() throws {
        var rows: [String: Bool] = [:]
        let device = Device()
        rows.merge(try finiteOutputFallbackChecks(device)) { _, current in current }
        rows["multiplePhysicsBones"] = try physicsSubsetChecks(device)
        let subject = try makeSubject(device)
        let command = Command(device)
        let tx = encode(subject, singleFrame(1), command)
        let first = subject.state.directModelMesh(on: command)
        let firstValues = read(first)!
        _ = encode(subject, singleFrame(1), command, tx)
        let second = subject.state.directModelMesh(on: command)
        let sameStorage = Mirror(reflecting: first!).children.first { $0.label == "vertexBuffer" }!.value as! MTLBuffer
        let repeatedStorage = Mirror(reflecting: second!).children.first { $0.label == "vertexBuffer" }!.value as! MTLBuffer
        let beforeAllocations = device.allocations
        var override = matrix_identity_float4x4; override.columns.3.z = 9
        subject.state.apply(scriptBoneMutations: [.init(layerID: 42, boneIndex: 0, matrix: columns(override).map(Double.init))])
        let changed = Command(device)
        let changedTx = encode(subject, singleFrame(1), changed)
        let values = read(subject.state.directModelMesh(on: changed))!
        let query = subject.state.poseConfiguration(animationFrame: singleFrame(1))!
        rows["poseAndSignature"] = subject.state.isDirectModel && firstValues[0].position.z == 7
            && firstValues[0].normal == SIMD3(2, 1, 0) && firstValues[0].uv == SIMD2(0.25, 0.75)
            && sameStorage === repeatedStorage && values[0].position.z == 12
            && query.bones.worldMatrices[14] == 9 && device.allocations == beforeAllocations
        let otherCommand = Command(device)
        let wrongTx = SceneSourceUpdateTransaction(on: command)
        _ = encode(subject, singleFrame(1), otherCommand, wrongTx)
        rows["wrongCommandAndTransaction"] = subject.state.directModelMesh(on: otherCommand) == nil
            && subject.state.directModelMesh(on: command) == nil
        tx.cancel(); changedTx.cancel(); wrongTx.cancel()

        let renamed = try makeSubject(device, renamed: true)
        let rc = Command(device); let rt = encode(renamed, singleFrame(1), rc)
        rows["renamed"] = read(renamed.state.directModelMesh(on: rc)) == firstValues
        rt.cancel()
        let late = try makeSubject(device, lateSingular: true)
        let lc = Command(device); let lt = encode(late, singleFrame(1), lc)
        rows["lateVertexFallback"] = late.state.directModelPoseStatus == .bindFallback(.invalidSkinFrame)
            && read(late.state.directModelMesh(on: lc)) == late.vertices
        lt.cancel()
        var channels = true
        for channel in ["alpha", "aux"] {
            let value = try makeSubject(device, channel: channel)
            let hidden = Command(device); let ht = encode(value, frame(1), hidden)
            channels = channels && value.state.directModelPoseStatus == .animated
                && read(value.state.directModelMesh(on: hidden))![0].position.z == 7
            ht.cancel()
            let active = Command(device); let at = encode(value, frame(1, hidden: false), active)
            channels = channels && value.state.directModelPoseStatus == .bindFallback(.unsupportedAnimationChannels)
                && read(value.state.directModelMesh(on: active)) == value.vertices
            at.cancel()
            let restored = Command(device); let st = encode(value, frame(1), restored)
            channels = channels && value.state.directModelPoseStatus == .animated
                && read(value.state.directModelMesh(on: restored))![0].position.z == 7
            st.cancel()
        }
        rows["channelVisibility"] = channels
        let invalid = Command(device); let it = encode(renamed, .init(samples: []), invalid)
        rows["invalidFrame"] = renamed.state.directModelPoseStatus == .bindFallback(.invalidFrame)
            && read(renamed.state.directModelMesh(on: invalid)) == renamed.vertices
        it.cancel()
        let pooled = try makeSubject(device)
        let commands = (0..<4).map { _ in Command(device) }
        let transactions = commands.map { encode(pooled, singleFrame(1), $0) }
        let busy = pooled.state.directModelMesh(on: commands[3]) == nil
        transactions[0].arm(on: commands[0]); commands[0].status = .committed
        transactions[0].didSubmit(); transactions[0].cancel()
        commands[0].complete(false)
        let free = Command(device); let ft = encode(pooled, singleFrame(1), free)
        rows["busyAndResolution"] = busy && pooled.state.directModelMesh(on: free) != nil
            && read(pooled.state.directModelMesh(on: free))![0].position.z == 7
        for transaction in transactions { transaction.cancel() }; ft.cancel()
        let surface = try makeSubject(device)
        let sc = Command(device); let st = encode(surface, singleFrame(0), sc)
        rows["surfaceIsolation"] = read(surface.state.directModelMesh(on: sc)) == surface.vertices
            && surface.state.directModelMesh(on: free) == nil
        st.cancel()
        let wrongDevice = Device(); let wc = Command(wrongDevice)
        let wt = encode(surface, singleFrame(0), wc)
        rows["wrongCommandAndTransaction"] = rows["wrongCommandAndTransaction"]!
            && surface.state.directModelMesh(on: wc) == nil
        wt.cancel()
        let badCount = ScenePuppetPlaybackState.makeDirectModel(layerID: 1, vertices: [],
            mesh: subject.mesh, evaluator: subject.evaluator, selection: subject.selection,
            pipeline: SceneStaticModelPipeline(device: device))
        let attachment = SceneMdlPuppetAttachment(boneIndex: 0, name: "unqualified",
            modelLocalFrameColumnMajor: columns(matrix_identity_float4x4),
            modelBindFrameColumnMajor: columns(matrix_identity_float4x4))
        let badAttachment = ScenePuppetPlaybackState.makeDirectModel(layerID: 1,
            vertices: subject.vertices, mesh: subject.mesh, evaluator: subject.evaluator,
            selection: subject.selection, attachments: [attachment],
            pipeline: SceneStaticModelPipeline(device: device))
        if case .failure(.directModelVertexCountMismatch) = badCount,
           case .failure(.directAttachmentBasisUnqualified) = badAttachment {
            rows["factoryCount"] = true
        } else { rows["factoryCount"] = false }
        print(String(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), encoding: .utf8)!)
    }
}

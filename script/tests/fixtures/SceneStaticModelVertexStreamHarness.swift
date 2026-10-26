import Foundation
import simd

#if STREAM_CPU_TEST
// These leaves make completion/failure deterministic without creating a GPU.
// Production stream, transaction, mesh-view and factory bodies are injected or
// compiled unchanged; this is not a second resource or submission algorithm.
protocol MTLDevice: AnyObject {}
protocol MTLBuffer: AnyObject {
    var device: MTLDevice { get }
    var length: Int { get }
    var label: String? { get set }
    func contents() -> UnsafeMutableRawPointer
}
enum MTLIndexType { case uint16, uint32 }
enum MTLCommandBufferStatus { case notEnqueued, enqueued, committed, scheduled, completed, error }
struct MTLResourceOptions: OptionSet {
    let rawValue: Int
    static let storageModeShared = MTLResourceOptions(rawValue: 1)
}
protocol MTLCommandBuffer: AnyObject {
    var device: MTLDevice { get }
    var status: MTLCommandBufferStatus { get }
    func addCompletedHandler(_ handler: @escaping (MTLCommandBuffer) -> Void)
}
enum SceneMdlStaticModel {
// PRODUCT_VERTEX
}
final class Buffer: MTLBuffer {
    let device: MTLDevice
    let length: Int
    var label: String?
    let memory: UnsafeMutableRawPointer
    init(device: MTLDevice, length: Int) {
        self.device = device
        self.length = length
        memory = .allocate(byteCount: length, alignment: 16)
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: length)
    }
    func contents() -> UnsafeMutableRawPointer { memory }
    deinit { memory.deallocate() }
}
final class Device: MTLDevice {
    var allocations = 0
    var maximumAllocations = Int.max
    func allocate(_ length: Int) -> MTLBuffer? {
        guard allocations < maximumAllocations else { return nil }
        allocations += 1
        return Buffer(device: self, length: length)
    }
}
extension MTLDevice {
    func makeSceneBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        (self as! Device).allocate(length)
    }
}
final class CommandBuffer: MTLCommandBuffer {
    let device: MTLDevice
    var status = MTLCommandBufferStatus.notEnqueued
    var handlers: [(MTLCommandBuffer) -> Void] = []
    init(_ device: MTLDevice) { self.device = device }
    func addCompletedHandler(_ handler: @escaping (MTLCommandBuffer) -> Void) {
        handlers.append(handler)
    }
    func commit() { status = .committed }
    func complete(_ succeeded: Bool = true) {
        status = succeeded ? .completed : .error
        // Keep callbacks to model duplicate/late notification as well.
        for handler in handlers { handler(self) }
    }
}

// PRODUCT_MESH
final class SceneStaticModelPipeline {
    let device: MTLDevice
    init(_ device: MTLDevice) { self.device = device }
// PRODUCT_FACTORY
// PRODUCT_ABI
}

@main enum Harness {
    typealias Vertex = SceneMdlStaticModel.Vertex
    typealias Binding = SceneStaticModelVertexStream.Binding
    static let vertices = [
        Vertex(position: SIMD3(-2, 3, -4), normal: SIMD3(2, -3, 4),
               tangent: SIMD4(-5, 6, -7, -1), uv: SIMD2(0.125, 0.875)),
        Vertex(position: SIMD3(5, -6, 7), normal: .zero,
               tangent: .zero, uv: SIMD2(0.625, 0.25)),
        Vertex(position: SIMD3(1, 2, 3), normal: SIMD3(0, 0, 1),
               tangent: SIMD4(1, 0, 0, 1), uv: SIMD2(0.5, 0.5))
    ]

    static func mesh(_ device: Device) -> SceneStaticModelMesh {
        SceneStaticModelMesh(
            vertexBuffer: Buffer(device: device, length: 3 * 64),
            indexBuffer: Buffer(device: device, length: 6),
            boundsMinimum: .zero, boundsMaximum: SIMD3(repeating: 1),
            vertexCount: 3, indexCount: 3, indexType: .uint16
        )
    }
    static func stream(_ device: Device, mesh: SceneStaticModelMesh? = nil) -> SceneStaticModelVertexStream {
        try! SceneStaticModelPipeline(device).makeVertexStream(mesh: mesh ?? self.mesh(device)).get()
    }
    static func update(
        _ stream: SceneStaticModelVertexStream, _ cb: CommandBuffer,
        _ tx: SceneSourceUpdateTransaction, revision: UInt64 = 1,
        vertices: [Vertex] = vertices
    ) -> Binding {
        try! stream.updateBinding(vertices: vertices, poseRevision: revision, on: cb, transaction: tx).get()
    }
    static func rejected(
        _ result: Result<Binding, SceneStaticModelVertexStream.Failure>,
        _ expected: SceneStaticModelVertexStream.Failure
    ) -> Bool {
        if case .failure(let failure) = result { return failure == expected }
        return false
    }
    static func main() throws {
        var checks: [String: Bool] = [:]
        do {
            let device = Device(), base = mesh(device)
            let storage = stream(device, mesh: base)
            let buffers = (0..<4).map { _ in CommandBuffer(device) }
            let txs = (0..<4).map { SceneSourceUpdateTransaction(on: buffers[$0]) }
            let bindings = (0..<3).map { update(storage, buffers[$0], txs[$0], revision: UInt64($0)) }
            let full = storage.updateBinding(vertices: vertices, poseRevision: 4, on: buffers[3], transaction: txs[3])
            checks["pendingAndFull"] = device.allocations == 3 && rejected(full, .busy)
                && bindings.enumerated().allSatisfy { $0.element.isValid(for: buffers[$0.offset]) }
                && bindings[0].mesh.vertexBuffer !== bindings[1].mesh.vertexBuffer
                && bindings[1].mesh.vertexBuffer !== bindings[2].mesh.vertexBuffer
            for tx in txs { tx.cancel() }
        }
        do {
            let device = Device(), storage = stream(device)
            let cb = CommandBuffer(device)
            let tx = SceneSourceUpdateTransaction(on: cb)
            let first = update(storage, cb, tx)
            tx.cancel(); tx.cancel()
            let nextCB = CommandBuffer(device)
            let nextTX = SceneSourceUpdateTransaction(on: nextCB)
            let next = update(storage, nextCB, nextTX)
            nextTX.arm(on: nextCB)
            nextTX.cancel()
            cb.complete() // No arm callback exists for the first candidate.
            let lastCB = CommandBuffer(device), lastTX: SceneSourceUpdateTransaction
            lastTX = SceneSourceUpdateTransaction(on: lastCB)
            checks["cancelBeforeSubmit"] = !first.isValid(for: cb) && !next.isValid(for: nextCB)
                && update(storage, lastCB, lastTX).poseRevision == 1
            lastTX.cancel()
        }
        do {
            let device = Device(), storage = stream(device)
            let cbs = (0..<4).map { _ in CommandBuffer(device) }
            let txs = (0..<4).map { SceneSourceUpdateTransaction(on: cbs[$0]) }
            let bindings = (0..<3).map { update(storage, cbs[$0], txs[$0]) }
            for i in 0..<3 { txs[i].arm(on: cbs[i]); cbs[i].commit(); txs[i].didSubmit(); txs[i].cancel() }
            let pending = rejected(storage.updateBinding(vertices: vertices, poseRevision: 4,
                on: cbs[3], transaction: txs[3]), .busy)
            cbs[0].complete(false)
            let next = update(storage, cbs[3], txs[3], revision: 9)
            cbs[0].complete(false)
            checks["submittedAndFailedCompletion"] = pending && !bindings[0].isValid(for: cbs[0])
                && next.isValid(for: cbs[3]) && bindings[1].isValid(for: cbs[1])
            cbs[1].complete(); cbs[2].complete(); txs[3].cancel()
        }
        do {
            let device = Device(), storage = stream(device), cb = CommandBuffer(device)
            let oldTX = SceneSourceUpdateTransaction(on: cb)
            var old: Binding? = update(storage, cb, oldTX)
            weak var oldLease = old?.lease
            oldTX.arm(on: cb); oldTX.cancel()
            let nextTX = SceneSourceUpdateTransaction(on: cb)
            let current = update(storage, cb, nextTX, revision: 2)
            old = nil // Deinit tries to release the old generation on the same CB.
            checks["lateGeneration"] = oldLease == nil && current.isValid(for: cb)
                && current.poseRevision == 2
            nextTX.arm(on: cb); cb.commit(); nextTX.didSubmit()
            cb.complete(); cb.complete()
            checks["lateGeneration"] = checks["lateGeneration"]! && !current.isValid(for: cb)
        }
        do {
            let device = Device(), base = mesh(device)
            var first: SceneStaticModelVertexStream? = stream(device, mesh: base)
            weak var retained = first
            let second = stream(device, mesh: base)
            let cb = CommandBuffer(device)
            let tx = SceneSourceUpdateTransaction(on: cb)
            var a: Binding? = update(first!, cb, tx, revision: 10)
            let bcb = CommandBuffer(device)
            let btx = SceneSourceUpdateTransaction(on: bcb)
            let b = update(second, bcb, btx, revision: 20)
            let different = a!.mesh.vertexBuffer !== b.mesh.vertexBuffer
            tx.arm(on: cb); cb.commit(); tx.didSubmit()
            a = nil; first = nil
            let retainedUntilCompletion = retained != nil
            cb.complete(false)
            checks["instancesAndLifetime"] = different && retainedUntilCompletion && retained == nil
                && b.isValid(for: bcb) && b.poseRevision == 20
            btx.cancel()
        }
        do {
            let device = Device(), base = mesh(device), storage = stream(device, mesh: base)
            let cb = CommandBuffer(device)
            let tx = SceneSourceUpdateTransaction(on: cb)
            let binding = update(storage, cb, tx, revision: 55)
            let raw = binding.mesh.vertexBuffer.contents().assumingMemoryBound(to: Vertex.self)
            let preserved = raw[0].position == vertices[0].position
                && raw[0].normal == vertices[0].normal && raw[0].tangent == vertices[0].tangent
                && raw[0].uv == vertices[0].uv && raw[1].normal == .zero
                && binding.mesh.indexBuffer === base.indexBuffer
                && binding.mesh.vertexCount == 3 && binding.mesh.indexCount == 3
                && binding.mesh.boundsMinimum == SIMD3(-2, -6, -4)
                && binding.mesh.boundsMaximum == SIMD3(5, 3, 7)
            // Reader owns immutable channels; Skinning/DirectModel tests cover
            // bad current output and complete bind fallback at the producer.
            let count = rejected(storage.updateBinding(vertices: Array(vertices.dropLast()),
                poseRevision: 1, on: cb, transaction: tx), .invalidVertices)
            let empty = rejected(storage.updateBinding(vertices: [], poseRevision: 1,
                on: cb, transaction: tx), .invalidVertices)
            let foreign = CommandBuffer(Device())
            let wrongDevice = rejected(storage.updateBinding(vertices: vertices,
                poseRevision: 1, on: foreign, transaction: tx), .invalidCommandBuffer)
            let otherCB = CommandBuffer(device)
            let wrongTransaction = rejected(storage.updateBinding(vertices: vertices,
                poseRevision: 1, on: otherCB, transaction: tx), .invalidCommandBuffer)
            let unbound = rejected(storage.updateBinding(vertices: vertices,
                poseRevision: 1, on: cb, transaction: SceneSourceUpdateTransaction()), .invalidCommandBuffer)
            tx.arm(on: otherCB)
            let wrongArm = otherCB.handlers.isEmpty
            otherCB.commit()
            let queued = rejected(storage.updateBinding(vertices: vertices, poseRevision: 1,
                on: otherCB, transaction: SceneSourceUpdateTransaction(on: otherCB)), .invalidCommandBuffer)
            let failedDevice = Device(); failedDevice.maximumAllocations = 2
            let allocationFailure: Bool
            switch SceneStaticModelPipeline(failedDevice).makeVertexStream(mesh: mesh(failedDevice)) {
            case .failure(.allocationFailed): allocationFailure = true
            default: allocationFailure = false
            }
            let invalidMesh: Bool
            switch SceneStaticModelPipeline(Device()).makeVertexStream(mesh: base) {
            case .failure(.invalidMesh): invalidMesh = true
            default: invalidMesh = false
            }
            checks["validationAndMeshView"] = preserved && count && empty && wrongDevice
                && queued && allocationFailure && invalidMesh && !binding.isValid(for: otherCB)
                && wrongTransaction && unbound && wrongArm
            tx.cancel()
        }
        do {
            let device = Device(), storage = stream(device)
            var cb: CommandBuffer? = CommandBuffer(device)
            var tx: SceneSourceUpdateTransaction? = SceneSourceUpdateTransaction(on: cb!)
            weak var weakCB = cb
            weak var weakTX = tx
            _ = update(storage, cb!, tx!)
            tx!.arm(on: cb!)
            tx!.cancel()
            cb = nil; tx = nil
            let released = weakCB == nil && weakTX == nil

            var expiredCB: CommandBuffer? = CommandBuffer(device)
            let bound = SceneSourceUpdateTransaction(on: expiredCB!)
            expiredCB = nil
            let foreign = CommandBuffer(device)
            bound.arm(on: foreign)
            checks["uncommittedArmCancelLifetime"] = released
                && !bound.belongs(to: foreign) && foreign.handlers.isEmpty
            bound.cancel()
        }
        print(String(data: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
#else
import Metal

// PRODUCT_MESH
final class SceneStaticModelPipeline {
    let device: MTLDevice
    init(_ device: MTLDevice) { self.device = device }
// PRODUCT_FACTORY
// PRODUCT_ABI
}
extension MTLDevice {
    func makeSceneBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        makeBuffer(length: length, options: options)
    }
}

/// Real GPU bytes and submitted lease lifetime. An event holds the blit until
/// the CPU has proved that cancelling a submitted transaction cannot recycle it.
@main enum MetalHarness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(), let event = device.makeSharedEvent() else {
            print("{\"skipped\":\"Metal device/queue/shared event unavailable\"}")
            return
        }
        defer { event.signaledValue = 1 }
        let model = try SceneMdlStaticModelReader.readParts(
            data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))[0]
        let vertices = model.vertices
        let expectedBytes = vertices.withUnsafeBytes { Data($0) }
        let base = SceneStaticModelMesh(
            vertexBuffer: device.makeBuffer(length: expectedBytes.count, options: .storageModeShared)!,
            indexBuffer: device.makeBuffer(length: 6, options: .storageModeShared)!,
            boundsMinimum: SIMD3(repeating: -10), boundsMaximum: SIMD3(repeating: 10),
            vertexCount: vertices.count, indexCount: 3, indexType: .uint16)
        let stream = try SceneStaticModelPipeline(device).makeVertexStream(mesh: base).get()
        let commands = (0..<4).map { _ in queue.makeCommandBuffer()! }
        let transactions = commands.map { SceneSourceUpdateTransaction(on: $0) }
        let bindings = try (0..<3).map { index in
            try stream.updateBinding(vertices: vertices, poseRevision: UInt64(index),
                on: commands[index], transaction: transactions[index]).get()
        }
        let readback = device.makeBuffer(length: expectedBytes.count, options: .storageModeShared)!
        let command = commands[0], transaction = transactions[0], binding = bindings[0]
        command.encodeWaitForEvent(event, value: 1)
        let blit = command.makeBlitCommandEncoder()!
        blit.copy(from: binding.mesh.vertexBuffer, sourceOffset: 0,
            to: readback, destinationOffset: 0, size: expectedBytes.count)
        blit.endEncoding()
        let resolved = DispatchSemaphore(value: 0)
        transaction.registerResolution(completed: { resolved.signal() }, rollback: { resolved.signal() })
        transaction.arm(on: command)
        command.commit()
        transaction.didSubmit()
        transaction.cancel()
        let pendingLease = binding.isValid(for: command)
            && command.status != .completed && command.status != .error
        let full = stream.updateBinding(vertices: vertices, poseRevision: 4,
            on: commands[3], transaction: transactions[3])
        let busy: Bool
        if case .failure(.busy) = full { busy = true } else { busy = false }
        event.signaledValue = 1
        guard resolved.wait(timeout: .now() + 10) == .success else {
            throw NSError(domain: "SceneStaticModelVertexStreamMetalTest", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "source resolution timed out"])
        }
        let outputBytes = Data(bytes: readback.contents(), count: expectedBytes.count)
        let completionRevokedLease = !binding.isValid(for: command)
        let next = try stream.updateBinding(vertices: vertices, poseRevision: 5,
            on: commands[3], transaction: transactions[3]).get()
        let slotReused = next.mesh.vertexBuffer === binding.mesh.vertexBuffer
            && next.isValid(for: commands[3]) && !binding.isValid(for: commands[3])
        transactions[3].cancel()
        let cancelledNext = !next.isValid(for: commands[3])
        transactions[1].cancel(); transactions[2].cancel()
        let rows = ["gpuCompleted": command.status == .completed && command.error == nil,
            "allBufferBytes": outputBytes == expectedBytes,
            "currentBounds": binding.mesh.boundsMinimum == SIMD3(-2, -6, -4)
                && binding.mesh.boundsMaximum == SIMD3(5, 3, 7),
            "pendingLease": pendingLease && busy,
            "completionRevokedLease": completionRevokedLease,
            "slotReused": slotReused, "cancelledNext": cancelledNext]
        print(String(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
            encoding: .utf8)!)
    }
}
#endif

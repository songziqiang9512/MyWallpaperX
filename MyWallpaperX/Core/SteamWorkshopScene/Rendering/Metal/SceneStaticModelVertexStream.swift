import Foundation
import Metal
import simd

/// Storage belongs to one layer/surface. Pose evaluation and submission remain
/// with PlaybackState and SourceUpdateTransaction respectively.
final class SceneStaticModelVertexStream: @unchecked Sendable {
    enum Failure: String, Error {
        case invalidVertexABI
        case invalidMesh
        case allocationFailed
        case invalidCommandBuffer
        case invalidVertices
        case busy
        case generationExhausted
    }

    struct Binding {
        let mesh: SceneStaticModelMesh
        let poseRevision: UInt64
        let lease: SceneStaticModelVertexLease

        func isValid(for commandBuffer: MTLCommandBuffer) -> Bool {
            lease.isValid(for: commandBuffer)
        }
    }

    static let maximumSlots = 3

    private struct Reservation {
        let owner: ObjectIdentifier
        let generation: UInt64
    }

    private struct Slot {
        let buffer: MTLBuffer
        var reservation: Reservation?
    }

    private let mesh: SceneStaticModelMesh
    private let device: MTLDevice
    private let lock = NSLock()
    private var slots: [Slot]
    private var generation: UInt64 = 0

    /// Only the pipeline constructs streams, after ABI/count/budget admission.
    init(mesh: SceneStaticModelMesh, buffers: [MTLBuffer], device: MTLDevice) {
        self.mesh = mesh
        self.device = device
        slots = buffers.map { Slot(buffer: $0) }
    }

    /// Called by the existing source-update phase, before any model encoder.
    /// No storage allocation or completion handler is added to ordinary frames.
    func updateBinding(
        vertices: [SceneMdlStaticModel.Vertex],
        poseRevision: UInt64,
        on commandBuffer: MTLCommandBuffer,
        transaction: SceneSourceUpdateTransaction
    ) -> Result<Binding, Failure> {
        guard commandBuffer.status == .notEnqueued,
              commandBuffer.device === device,
              transaction.belongs(to: commandBuffer) else { return .failure(.invalidCommandBuffer) }
        guard vertices.count == mesh.vertexCount,
              let bounds = Self.validatedBounds(vertices) else {
            return .failure(.invalidVertices)
        }
        lock.lock()
        defer { lock.unlock() }
        guard let index = slots.firstIndex(where: { $0.reservation == nil }) else {
            return .failure(.busy)
        }
        let (nextGeneration, overflow) = generation.addingReportingOverflow(1)
        guard !overflow else { return .failure(.generationExhausted) }
        generation = nextGeneration
        slots[index].reservation = Reservation(
            owner: ObjectIdentifier(commandBuffer), generation: generation
        )
        let buffer = slots[index].buffer
        vertices.withUnsafeBytes { bytes in
            buffer.contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        let lease = SceneStaticModelVertexLease(
            stream: self, slotIndex: index, generation: generation,
            commandBuffer: commandBuffer
        )
        // Both outcomes release the exact GPU-storage lease. CPU signature
        // commit/rollback stays in the producer's existing transaction actions.
        transaction.registerResolution(
            completed: { lease.resolve() }, rollback: { lease.resolve() }
        )
        return .success(Binding(
            mesh: mesh.replacingVertices(
                buffer: buffer, boundsMinimum: bounds.minimum, boundsMaximum: bounds.maximum
            ),
            poseRevision: poseRevision, lease: lease
        ))
    }

    fileprivate func contains(
        slotIndex: Int, generation: UInt64, commandBuffer: MTLCommandBuffer
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return slots[slotIndex].reservation.map {
            $0.generation == generation && $0.owner == ObjectIdentifier(commandBuffer)
        } ?? false
    }

    fileprivate func release(
        slotIndex: Int, generation: UInt64, commandBuffer: MTLCommandBuffer
    ) {
        // A pre-submit rollback may recycle immediately. Once enqueued, only
        // terminal GPU completion (including error) makes the storage reusable.
        guard commandBuffer.status == .notEnqueued || commandBuffer.status == .completed
                || commandBuffer.status == .error else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let reservation = slots[slotIndex].reservation,
              reservation.generation == generation,
              reservation.owner == ObjectIdentifier(commandBuffer) else { return }
        slots[slotIndex].reservation = nil
    }

    private static func validatedBounds(
        _ vertices: [SceneMdlStaticModel.Vertex]
    ) -> (minimum: SIMD3<Float>, maximum: SIMD3<Float>)? {
        guard let first = vertices.first else { return nil }
        var minimum = first.position
        var maximum = first.position
        for vertex in vertices {
            guard vertex.position.x.isFinite, vertex.position.y.isFinite,
                  vertex.position.z.isFinite, vertex.normal.x.isFinite,
                  vertex.normal.y.isFinite, vertex.normal.z.isFinite,
                  vertex.tangent.x.isFinite, vertex.tangent.y.isFinite,
                  vertex.tangent.z.isFinite, vertex.tangent.w.isFinite,
                  vertex.uv.x.isFinite, vertex.uv.y.isFinite else { return nil }
            minimum = simd_min(minimum, vertex.position)
            maximum = simd_max(maximum, vertex.position)
        }
        return (minimum, maximum)
    }
}

/// The transaction retains this token through cancellation or GPU completion.
/// A late resolution cannot free a newer reservation of the same storage slot.
final class SceneStaticModelVertexLease: @unchecked Sendable {
    private let stream: SceneStaticModelVertexStream
    private let slotIndex: Int
    private let generation: UInt64
    private let commandBuffer: MTLCommandBuffer

    fileprivate init(
        stream: SceneStaticModelVertexStream, slotIndex: Int, generation: UInt64,
        commandBuffer: MTLCommandBuffer
    ) {
        self.stream = stream
        self.slotIndex = slotIndex
        self.generation = generation
        self.commandBuffer = commandBuffer
    }

    func isValid(for commandBuffer: MTLCommandBuffer) -> Bool {
        commandBuffer === self.commandBuffer
            && commandBuffer.status != .completed && commandBuffer.status != .error
            && stream.contains(
                slotIndex: slotIndex, generation: generation, commandBuffer: commandBuffer
            )
    }

    fileprivate func resolve() {
        stream.release(slotIndex: slotIndex, generation: generation, commandBuffer: commandBuffer)
    }

    deinit { resolve() }
}

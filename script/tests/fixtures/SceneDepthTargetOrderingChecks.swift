import Foundation
import Metal
import Darwin

enum SceneDepthTargetOrderingChecks {
    enum ProbeFailure: Error { case failed(String) }

    private static func queue(_ device: MTLDevice) throws -> MTLCommandQueue {
        guard let value = device.makeCommandQueue() else { throw ProbeFailure.failed("makeCommandQueue") }
        return value
    }
    private static func buffer(_ queue: MTLCommandQueue, _ buffers: inout [MTLCommandBuffer]) throws -> MTLCommandBuffer {
        guard let value = queue.makeCommandBuffer() else { throw ProbeFailure.failed("makeCommandBuffer") }
        buffers.append(value)
        return value
    }
    private static func acquired(_ value: SceneParticleDepthTargetPool.Acquisition) throws -> SceneParticleDepthTargetLease {
        guard case let .acquired(lease) = value else { throw ProbeFailure.failed("acquire: \(outcome(value))") }
        return lease
    }
    private static func outcome(_ value: SceneParticleDepthTargetPool.Acquisition) -> String {
        switch value {
        case .acquired: return "acquired"
        case .busyOtherFrame: return "busyOtherFrame"
        case .currentFrameCapacityExceeded: return "currentFrameCapacityExceeded"
        case .invalidExtent: return "invalidExtent"
        case .allocationFailed: return "allocationFailed"
        }
    }
    private static func token(_ texture: MTLTexture) -> String { String(UInt(bitPattern: ObjectIdentifier(texture))) }
    private static func drain(_ buffers: [MTLCommandBuffer]) {
        // An enqueued buffer is never abandoned, even if preparation throws.
        for b in buffers where b.status == .notEnqueued || b.status == .enqueued { b.commit() }
        for b in buffers { b.waitUntilCompleted() }
    }
    private static func complete(_ buffers: [MTLCommandBuffer]) throws {
        for b in buffers { b.waitUntilCompleted() }
        guard buffers.allSatisfy({ $0.status == .completed && $0.error == nil }) else {
            throw ProbeFailure.failed("GPU completion: \(buffers.map { String(describing: $0.error) })")
        }
    }
    private static func clear(_ texture: MTLTexture, _ value: Double, _ cb: MTLCommandBuffer) throws {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.depthAttachment.texture = texture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = value
        guard let encoder = cb.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw ProbeFailure.failed("depth clear encoder")
        }
        encoder.endEncoding()
    }
    private static func read(_ texture: MTLTexture, _ cb: MTLCommandBuffer, _ device: MTLDevice) throws -> MTLBuffer {
        guard let bytes = device.makeBuffer(length: 256, options: .storageModeShared),
              let encoder = cb.makeBlitCommandEncoder() else { throw ProbeFailure.failed("readback") }
        memset(bytes.contents(), 0xA5, 256)
        encoder.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: 1, height: 1, depth: 1),
            to: bytes, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
        encoder.endEncoding()
        return bytes
    }
    private static func value(_ bytes: MTLBuffer) -> [String: Any] {
        let v = bytes.contents().load(as: Float.self)
        return ["value": Double(v), "bits": UInt64(v.bitPattern)]
    }
    private static func base(_ name: String, _ pool: SceneParticleDepthTargetPool,
              _ leases: [SceneParticleDepthTargetLease], _ buffers: [MTLCommandBuffer]) -> [String: Any] {
        ["name": name, "logicalResidentBytes": pool.residentByteCost,
         "textureTokens": leases.map { token($0.texture) },
         "uniqueTextureCount": Set(leases.map { token($0.texture) }).count,
         "allTracked": leases.allSatisfy { $0.texture.hazardTrackingMode == .tracked },
         "allDepth32PrivateRenderTarget": leases.allSatisfy {
            $0.texture.pixelFormat == .depth32Float && $0.texture.storageMode == .private
                && $0.texture.usage == .renderTarget && $0.texture.sampleCount == 1
         }, "completedCBs": buffers.filter { $0.status == .completed && $0.error == nil }.count,
         "commandBuffers": buffers.count]
    }

    private static func ordered(_ device: MTLDevice) throws -> [String: Any] {
        let q = try queue(device), pool = SceneParticleDepthTargetPool()
        var bs: [MTLCommandBuffer] = []; defer { drain(bs) }
        let a = try buffer(q, &bs); a.enqueue()
        let la = try acquired(pool.acquire(device: device, width: 64, height: 64, on: a))
        try clear(la.texture, 0.75, a); let ra = try read(la.texture, a, device); la.arm(on: a)
        let b = try buffer(q, &bs)
        let lb = try acquired(pool.acquire(device: device, width: 64, height: 64, on: b))
        try clear(lb.texture, 0.25, b); let rb = try read(lb.texture, b, device); lb.arm(on: b)
        let before = [a.status.rawValue, b.status.rawValue]
        b.commit(); a.commit(); try complete(bs)
        var r = base("ordered", pool, [la, lb], bs)
        r["beforeCommitStatuses"] = before; r["commitOrder"] = [2, 1]
        r["readbacks"] = [value(ra), value(rb)]; return r
    }
    private static func sameBuffer(_ device: MTLDevice) throws -> [String: Any] {
        let q = try queue(device), pool = SceneParticleDepthTargetPool()
        var bs: [MTLCommandBuffer] = []; defer { drain(bs) }
        let a = try buffer(q, &bs)
        let x = try acquired(pool.acquire(device: device, width: 64, height: 64, on: a))
        let y = try acquired(pool.acquire(device: device, width: 64, height: 64, on: a))
        // Both pass contents remain live when B overwrites its own attachment.
        try clear(x.texture, 0.625, a); try clear(y.texture, 0.375, a)
        let rx = try read(x.texture, a, device), ry = try read(y.texture, a, device)
        x.arm(on: a); y.arm(on: a); a.commit(); try complete(bs)
        var r = base("same-buffer-pass-isolation", pool, [x, y], bs)
        r["readbacks"] = [value(rx), value(ry)]; return r
    }
    private static func separate(_ device: MTLDevice, crossQueue: Bool) throws -> [String: Any] {
        let q = try queue(device)
        let other: MTLCommandQueue
        if crossQueue { other = try queue(device) } else { other = q }
        let pool = SceneParticleDepthTargetPool()
        var bs: [MTLCommandBuffer] = []; defer { drain(bs) }
        let a = try buffer(q, &bs)
        if crossQueue { a.enqueue() }
        let x = try acquired(pool.acquire(device: device, width: 64, height: 64, on: a))
        try clear(x.texture, 0.75, a); let rx = try read(x.texture, a, device); x.arm(on: a)
        let b = try buffer(other, &bs)
        let y = try acquired(pool.acquire(device: device, width: 64, height: 64, on: b))
        try clear(y.texture, 0.25, b); let ry = try read(y.texture, b, device); y.arm(on: b)
        b.commit(); a.commit(); try complete(bs)
        var r = base(crossQueue ? "cross-queue-isolation" : "not-enqueued-predecessor", pool, [x, y], bs)
        r["sameQueue"] = q === other; r["readbacks"] = [value(rx), value(ry)]; return r
    }
    private static func cancelNew(_ device: MTLDevice) throws -> [String: Any] {
        let q = try queue(device), other = try queue(device), pool = SceneParticleDepthTargetPool()
        var bs: [MTLCommandBuffer] = []; defer { drain(bs) }
        let a = try buffer(q, &bs); a.enqueue()
        let old = try acquired(pool.acquire(device: device, width: 64, height: 64, on: a))
        try clear(old.texture, 0.75, a); let ro = try read(old.texture, a, device); old.arm(on: a)
        let pending = try buffer(q, &bs)
        let next = try acquired(pool.acquire(device: device, width: 64, height: 64, on: pending))
        let stateAtCancel = pending.status.rawValue
        next.cancel() // No work was encoded, and this CB has never been enqueued.
        let c = try buffer(other, &bs)
        let cross = try acquired(pool.acquire(device: device, width: 64, height: 64, on: c))
        try clear(cross.texture, 0.25, c); let rc = try read(cross.texture, c, device); cross.arm(on: c)
        c.commit(); a.commit(); pending.commit(); try complete(bs)
        var r = base("cancel-new-preserves-old", pool, [old, next, cross], bs)
        r["oldAndCrossQueueDistinct"] = old.texture !== cross.texture
        r["cancelledStatusWasNotEnqueued"] = stateAtCancel == MTLCommandBufferStatus.notEnqueued.rawValue
        r["readbacks"] = [value(ro), value(rc)]; return r
    }
    private static func completionKeepsPending(_ device: MTLDevice) throws -> [String: Any] {
        let q = try queue(device), pool = SceneParticleDepthTargetPool()
        var bs: [MTLCommandBuffer] = []; defer { drain(bs) }
        let a = try buffer(q, &bs); a.enqueue()
        let old = try acquired(pool.acquire(device: device, width: 64, height: 64, on: a))
        try clear(old.texture, 0.75, a); let ro = try read(old.texture, a, device); old.arm(on: a)
        let b = try buffer(q, &bs)
        let pending = try acquired(pool.acquire(device: device, width: 64, height: 64, on: b))
        a.commit(); try complete([a])
        // Old completion has run while B still owns an unsubmitted reservation.
        let x = try acquired(pool.acquire(device: device, width: 64, height: 64, on: b))
        let y = try acquired(pool.acquire(device: device, width: 64, height: 64, on: b))
        let fourth = outcome(pool.acquire(device: device, width: 64, height: 64, on: b))
        let live = [pending, x, y]
        let values: [Double] = [0.25, 0.5, 0.875]
        for (lease, v) in zip(live, values) { try clear(lease.texture, v, b) }
        let reads = try live.map { try read($0.texture, b, device) }
        live.forEach { $0.arm(on: b) }; b.commit(); try complete(bs)
        var r = base("old-completion-preserves-pending", pool, live, bs)
        r["fourthSameBuffer"] = fourth; r["readbacks"] = [value(ro)] + reads.map(value); return r
    }
    private static func capacity(_ device: MTLDevice) throws -> [String: Any] {
        let q = try queue(device), pool = SceneParticleDepthTargetPool()
        var bs: [MTLCommandBuffer] = []; defer { drain(bs) }
        var leases: [SceneParticleDepthTargetLease] = [], reads: [MTLBuffer] = []
        for v in [0.125, 0.5, 0.875] {
            let cb = try buffer(q, &bs)
            let lease = try acquired(pool.acquire(device: device, width: 64, height: 64, on: cb))
            leases.append(lease); try clear(lease.texture, v, cb)
            reads.append(try read(lease.texture, cb, device)); lease.arm(on: cb); cb.enqueue()
        }
        let fourth = try buffer(q, &bs)
        let rejection = outcome(pool.acquire(device: device, width: 64, height: 64, on: fourth))
        fourth.commit(); for cb in bs.prefix(3).reversed() { cb.commit() }; try complete(bs)
        var r = base("global-three-reservations", pool, leases, bs)
        r["fourthOtherBuffer"] = rejection; r["readbacks"] = reads.map(value); return r
    }
    private static func mixedCapacity(_ device: MTLDevice) throws -> [String: Any] {
        let q = try queue(device), pool = SceneParticleDepthTargetPool()
        var bs: [MTLCommandBuffer] = []; defer { drain(bs) }
        let literals: [[Double]] = [[0.125, 0.25, 0.375], [0.5, 0.625, 0.75], [0.875, 0.25, 0.5]]
        var groups: [[SceneParticleDepthTargetLease]] = [], readGroups: [[MTLBuffer]] = []
        var outcomes: [[String]] = [], fourthSameBuffer = ""
        for index in 0..<3 {
            let cb = try buffer(q, &bs)
            if index == 0 { cb.enqueue() }
            var leases: [SceneParticleDepthTargetLease] = [], states: [String] = []
            for _ in 0..<3 {
                let result = pool.acquire(device: device, width: 64, height: 64, on: cb)
                states.append(outcome(result))
                guard case let .acquired(lease) = result else { break }
                leases.append(lease)
            }
            for (lease, v) in zip(leases, literals[index]) { try clear(lease.texture, v, cb) }
            readGroups.append(try leases.map { try read($0.texture, cb, device) })
            leases.forEach { $0.arm(on: cb) }; groups.append(leases); outcomes.append(states)
            if index == 2 {
                fourthSameBuffer = outcome(pool.acquire(device: device, width: 64, height: 64, on: cb))
            }
            if index != 0 { cb.enqueue() }
        }
        let fourth = try buffer(q, &bs)
        let fourthOtherBuffer = outcome(pool.acquire(device: device, width: 64, height: 64, on: fourth))
        fourth.commit(); for cb in bs.prefix(3).reversed() { cb.commit() }; try complete(bs)
        var r = base("three-buffers-three-passes", pool, groups.flatMap { $0 }, bs)
        r["acquisitionOutcomes"] = outcomes
        r["passTextureGroups"] = groups.map { $0.map { token($0.texture) } }
        r["leasesByBuffer"] = groups.map { $0.count }
        r["readbackGroups"] = readGroups.map { $0.map(value) }
        r["fourthSameBuffer"] = fourthSameBuffer; r["fourthOtherBuffer"] = fourthOtherBuffer
        return r
    }
    private static func invalid(_ device: MTLDevice) throws -> [String: Any] {
        let q = try queue(device), pool = SceneParticleDepthTargetPool()
        var bs: [MTLCommandBuffer] = []; defer { drain(bs) }
        let cb = try buffer(q, &bs)
        let requests = [(0, 64), (64, 0), (-1, 64), (Int.max, 2)]
        let outcomes = requests.map { outcome(pool.acquire(device: device, width: $0.0, height: $0.1, on: cb)) }
        cb.commit(); try complete(bs)
        var r = base("invalid-extent", pool, [], bs); r["outcomes"] = outcomes; return r
    }
    private static func resize(_ device: MTLDevice) throws -> [String: Any] {
        let q = try queue(device), pool = SceneParticleDepthTargetPool()
        var bs: [MTLCommandBuffer] = []; defer { drain(bs) }
        let a = try buffer(q, &bs); a.enqueue()
        let x = try acquired(pool.acquire(device: device, width: 64, height: 64, on: a))
        try clear(x.texture, 0.75, a); let rx = try read(x.texture, a, device); x.arm(on: a)
        let b = try buffer(q, &bs)
        let y = try acquired(pool.acquire(device: device, width: 128, height: 64, on: b))
        try clear(y.texture, 0.25, b); let ry = try read(y.texture, b, device); y.arm(on: b)
        b.commit(); a.commit(); try complete([a, b])
        let c = try buffer(q, &bs)
        let z = try acquired(pool.acquire(device: device, width: 128, height: 64, on: c))
        try clear(z.texture, 0.5, c); let rz = try read(z.texture, c, device); z.arm(on: c)
        c.commit(); try complete(bs)
        var r = base("resize-and-warm", pool, [x, y, z], bs)
        r["inflightDifferentExtentDistinct"] = x.texture !== y.texture
        r["warmMatchingTextureReused"] = y.texture === z.texture
        r["dimensions"] = [x, y, z].map { [$0.texture.width, $0.texture.height] }
        r["readbacks"] = [value(rx), value(ry), value(rz)]; return r
    }

    static func run(device: MTLDevice) throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        rows.append(try autoreleasepool { try ordered(device) })
        rows.append(try autoreleasepool { try sameBuffer(device) })
        rows.append(try autoreleasepool { try separate(device, crossQueue: true) })
        rows.append(try autoreleasepool { try separate(device, crossQueue: false) })
        rows.append(try autoreleasepool { try cancelNew(device) })
        rows.append(try autoreleasepool { try completionKeepsPending(device) })
        rows.append(try autoreleasepool { try capacity(device) })
        rows.append(try autoreleasepool { try mixedCapacity(device) })
        rows.append(try autoreleasepool { try invalid(device) })
        rows.append(try autoreleasepool { try resize(device) })
        return rows
    }
}

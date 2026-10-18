import Foundation
import Metal

final class SceneParticleDepthTargetLease: @unchecked Sendable {
    let texture: MTLTexture

    private weak var pool: SceneParticleDepthTargetPool?
    private let slotIndex: Int
    private let reservationCommandBuffer: MTLCommandBuffer
    private var reservationOwner: ObjectIdentifier { ObjectIdentifier(reservationCommandBuffer) }
    private let lock = NSLock()
    private var disposition: Disposition = .reserved

    private enum Disposition {
        case reserved
        case completionOwned
        case released
    }

    init(texture: MTLTexture, slotIndex: Int, commandBuffer: MTLCommandBuffer,
         pool: SceneParticleDepthTargetPool) {
        self.texture = texture
        self.slotIndex = slotIndex
        self.reservationCommandBuffer = commandBuffer
        self.pool = pool
    }

    func arm(on commandBuffer: MTLCommandBuffer) {
        guard commandBuffer === reservationCommandBuffer else { return }
        let shouldArm = withLock { () -> Bool in
            guard disposition == .reserved else { return false }
            disposition = .completionOwned
            return true
        }
        guard shouldArm else { return }
        let completionPool = pool
        let completionSlot = slotIndex
        let completionOwner = reservationOwner
        commandBuffer.addCompletedHandler { _ in
            completionPool?.release(completionSlot, owner: completionOwner)
        }
    }

    func cancel() {
        let shouldRelease = withLock { () -> Bool in
            guard disposition == .reserved else { return false }
            disposition = .released
            return true
        }
        if shouldRelease { pool?.release(slotIndex, owner: reservationOwner) }
    }

    deinit { cancel() }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

final class SceneParticleDepthTargetPool: @unchecked Sendable {
    enum Acquisition {
        case acquired(SceneParticleDepthTargetLease)
        case busyOtherFrame
        case currentFrameCapacityExceeded
        case invalidExtent
        case allocationFailed
    }

    private struct Slot {
        var texture: MTLTexture
        var byteCost: Int
        var reservationOwner: ObjectIdentifier?
    }

    private let lock = NSLock()
    private var slots: [Slot] = []
    private let maximumSlots = 3

    /// At most three fixed slots are visited, and only by the daemon's 1 Hz
    /// resource sampler.
    var residentByteCost: Int {
        withLock { slots.reduce(0) { $0 + $1.byteCost } }
    }

    func acquire(device: MTLDevice, width: Int, height: Int,
                 on commandBuffer: MTLCommandBuffer) -> Acquisition {
        guard width > 0, height > 0, Self.byteCost(width: width, height: height) != nil
        else { return .invalidExtent }
        let owner = ObjectIdentifier(commandBuffer)
        return withLock {
            let matching = slots.indices.first {
                slots[$0].reservationOwner == nil
                    && slots[$0].texture.width == width
                    && slots[$0].texture.height == height
            }
            let reusable = matching ?? slots.indices.first { slots[$0].reservationOwner == nil }
            let index: Int
            if let reusable {
                if matching == nil {
                    guard let texture = makeTexture(
                        device: device,
                        width: width,
                        height: height,
                        slot: reusable
                    ) else { return .allocationFailed }
                    slots[reusable].texture = texture
                    slots[reusable].byteCost = Self.byteCost(
                        width: width,
                        height: height
                    ) ?? 0
                }
                index = reusable
            } else {
                guard slots.count < maximumSlots else {
                    return slots.allSatisfy { $0.reservationOwner == owner }
                        ? .currentFrameCapacityExceeded : .busyOtherFrame
                }
                guard let texture = makeTexture(
                          device: device,
                          width: width,
                          height: height,
                          slot: slots.count
                      ) else { return .allocationFailed }
                index = slots.count
                slots.append(Slot(
                    texture: texture,
                    byteCost: Self.byteCost(width: width, height: height) ?? 0,
                    reservationOwner: nil
                ))
            }
            slots[index].reservationOwner = owner
            return .acquired(SceneParticleDepthTargetLease(
                texture: slots[index].texture,
                slotIndex: index,
                commandBuffer: commandBuffer,
                pool: self
            ))
        }
    }

    fileprivate func release(_ index: Int, owner: ObjectIdentifier) {
        withLock {
            guard slots.indices.contains(index), slots[index].reservationOwner == owner else { return }
            slots[index].reservationOwner = nil
        }
    }

    private func makeTexture(
        device: MTLDevice,
        width: Int,
        height: Int,
        slot: Int
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = .renderTarget
        let texture = device.makeSceneTexture(descriptor: descriptor)
        texture?.label = "Scene particle depth slot \(slot)"
        return texture
    }

    private static func byteCost(width: Int, height: Int) -> Int? {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        return pixelOverflow || byteOverflow ? nil : bytes
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

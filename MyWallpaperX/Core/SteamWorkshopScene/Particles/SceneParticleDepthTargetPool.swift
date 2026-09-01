import Foundation
import Metal

final class SceneParticleDepthTargetLease: @unchecked Sendable {
    let texture: MTLTexture

    private weak var pool: SceneParticleDepthTargetPool?
    private let slotIndex: Int
    private let lock = NSLock()
    private var disposition: Disposition = .reserved

    private enum Disposition {
        case reserved
        case completionOwned
        case released
    }

    init(texture: MTLTexture, slotIndex: Int, pool: SceneParticleDepthTargetPool) {
        self.texture = texture
        self.slotIndex = slotIndex
        self.pool = pool
    }

    func arm(on commandBuffer: MTLCommandBuffer) {
        let shouldArm = withLock { () -> Bool in
            guard disposition == .reserved else { return false }
            disposition = .completionOwned
            return true
        }
        guard shouldArm else { return }
        let completionPool = pool
        let completionSlot = slotIndex
        commandBuffer.addCompletedHandler { _ in
            completionPool?.release(completionSlot)
        }
    }

    func cancel() {
        let shouldRelease = withLock { () -> Bool in
            guard disposition == .reserved else { return false }
            disposition = .released
            return true
        }
        if shouldRelease { pool?.release(slotIndex) }
    }

    deinit { cancel() }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

final class SceneParticleDepthTargetPool: @unchecked Sendable {
    private struct Slot {
        var texture: MTLTexture
        var isReserved: Bool
    }

    private let lock = NSLock()
    private var slots: [Slot] = []
    private let maximumSlots = 3

    func acquire(device: MTLDevice, width: Int, height: Int) -> SceneParticleDepthTargetLease? {
        guard width > 0, height > 0 else { return nil }
        return withLock {
            let matching = slots.indices.first {
                !slots[$0].isReserved
                    && slots[$0].texture.width == width
                    && slots[$0].texture.height == height
            }
            let reusable = matching ?? slots.indices.first { !slots[$0].isReserved }
            let index: Int
            if let reusable {
                if matching == nil {
                    guard let texture = makeTexture(
                        device: device,
                        width: width,
                        height: height,
                        slot: reusable
                    ) else { return nil }
                    slots[reusable].texture = texture
                }
                index = reusable
            } else {
                guard slots.count < maximumSlots,
                      let texture = makeTexture(
                          device: device,
                          width: width,
                          height: height,
                          slot: slots.count
                      ) else { return nil }
                index = slots.count
                slots.append(Slot(texture: texture, isReserved: false))
            }
            slots[index].isReserved = true
            return SceneParticleDepthTargetLease(
                texture: slots[index].texture,
                slotIndex: index,
                pool: self
            )
        }
    }

    fileprivate func release(_ index: Int) {
        withLock {
            guard slots.indices.contains(index) else { return }
            slots[index].isReserved = false
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
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "Scene particle depth slot \(slot)"
        return texture
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

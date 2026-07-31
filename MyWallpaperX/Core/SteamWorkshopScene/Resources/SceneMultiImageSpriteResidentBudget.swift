import Foundation
import Metal

struct SceneMultiImageSpriteTextureCost {
    let source: Int
    let destination: Int

    static func estimate(
        container: SceneTexContainer,
        pixelFormat: MTLPixelFormat,
        outputWidth: Int,
        outputHeight: Int,
        device: MTLDevice
    ) -> SceneMultiImageSpriteTextureCost? {
        var sourceCost = 0
        for image in container.images {
            guard let mip = image.mips.first,
                  let cost = allocationCost(
                      pixelFormat: pixelFormat,
                      width: mip.width,
                      height: mip.height,
                      usage: .shaderRead,
                      storageMode: .shared,
                      device: device
                  ) else {
                return nil
            }
            let (nextCost, overflow) = sourceCost.addingReportingOverflow(cost)
            guard !overflow else { return nil }
            sourceCost = nextCost
        }
        guard let destinationCost = allocationCost(
            pixelFormat: .rgba8Unorm,
            width: outputWidth,
            height: outputHeight,
            usage: [.shaderRead, .shaderWrite],
            storageMode: .private,
            device: device
        ) else {
            return nil
        }
        return SceneMultiImageSpriteTextureCost(
            source: sourceCost,
            destination: destinationCost
        )
    }

    private static func allocationCost(
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage,
        storageMode: MTLStorageMode,
        device: MTLDevice
    ) -> Int? {
        guard width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = storageMode
        let sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: descriptor)
        guard sizeAndAlign.size > 0 else { return nil }
        return sizeAndAlign.size
    }
}

final class SceneMultiImageSpriteResidentBudget {
    final class Reservation {
        private var owner: SceneMultiImageSpriteResidentBudget?
        let cost: Int

        fileprivate init(
            owner: SceneMultiImageSpriteResidentBudget,
            cost: Int
        ) {
            self.owner = owner
            self.cost = cost
        }

        deinit {
            owner?.release(cost: cost)
        }
    }

    private let limit: Int
    private let lock = NSLock()
    private var residentCost = 0

    init(limit: Int) {
        self.limit = max(limit, 0)
    }

    func reserve(cost: Int) -> Reservation? {
        guard cost >= 0 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard cost <= limit - residentCost else { return nil }
        residentCost += cost
        return Reservation(owner: self, cost: cost)
    }

    var remainingCost: Int {
        lock.lock()
        defer { lock.unlock() }
        return limit - residentCost
    }

    private func release(cost: Int) {
        lock.lock()
        residentCost = max(residentCost - cost, 0)
        lock.unlock()
    }
}

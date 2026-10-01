import Foundation
import Metal
import CoreVideo
import ObjectiveC

/// Single process-wide admission account for application-owned Scene residency.
/// Resource identity and eviction remain with their existing owners.
nonisolated final class SceneResourceBudget: @unchecked Sendable {
    static let shared = SceneResourceBudget(maximumBytes: {
        let recommended = MTLCreateSystemDefaultDevice()?.recommendedMaxWorkingSetSize ?? 0
        return recommended == 0 ? 512 * 1_024 * 1_024
            : Int(min(recommended / 4, 3 * 1_024 * 1_024 * 1_024))
    }())

    enum Kind { case gpu, decoded }
    private let lock = NSLock()
    let maximumBytes: Int
    private var reserved = 0
    private var decoded = 0
    private var rejections = 0

    init(maximumBytes: Int) { self.maximumBytes = max(0, maximumBytes) }

    var snapshot: (residentBytes: Int, decodedBytes: Int, rejectionCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (reserved, decoded, rejections)
    }

    func reserve(_ bytes: Int, kind: Kind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Producers are native allocation requirements or decoded cache sizes.
        guard bytes >= 0, bytes <= maximumBytes - reserved,
              kind != .decoded || bytes <= maximumBytes / 4 - decoded else {
            rejections += 1
            return false
        }
        reserved += bytes
        if kind == .decoded { decoded += bytes }
        return true
    }

    func release(_ bytes: Int, kind: Kind) {
        lock.lock()
        defer { lock.unlock() }
        precondition(bytes >= 0 && bytes <= reserved)
        reserved -= bytes
        if kind == .decoded {
            precondition(bytes <= decoded)
            decoded -= bytes
        }
    }
}

nonisolated private final class SceneResourceLease {
    let budget: SceneResourceBudget
    let bytes: Int
    init(budget: SceneResourceBudget, bytes: Int) {
        self.budget = budget
        self.bytes = bytes
    }
    deinit { budget.release(bytes, kind: .gpu) }
}

nonisolated private final class SceneVideoResourceLifetime {
    let backing: CVPixelBuffer
    init(_ backing: CVPixelBuffer) { self.backing = backing }
}

nonisolated enum SceneResourceAllocation {
    nonisolated(unsafe) private static var leaseKey: UInt8 = 0
    private static let importLock = NSLock()

    fileprivate static func make<Resource: MTLResource>(
        bytes: Int, budget: SceneResourceBudget, allocate: () -> Resource?
    ) -> Resource? {
        guard budget.reserve(bytes, kind: .gpu) else { return nil }
        let lease = SceneResourceLease(budget: budget, bytes: bytes)
        guard let resource = allocate() else { return nil }
        objc_setAssociatedObject(resource, &leaseKey, lease, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return resource
    }

    static func importVideo(
        _ pixelBuffer: CVPixelBuffer, cache: CVMetalTextureCache,
        budget: SceneResourceBudget = .shared
    ) -> CVMetalTexture? {
        let bytes = CVPixelBufferGetDataSize(pixelBuffer)
        var imported: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &imported
        )
        guard status == kCVReturnSuccess, let imported,
              let texture = CVMetalTextureGetTexture(imported) else { return nil }
        importLock.lock()
        defer { importLock.unlock() }
        // CV may create several texture views for one backing buffer. Account
        // the backing once, and retain it for every GPU-visible view.
        if objc_getAssociatedObject(pixelBuffer, &leaseKey) == nil {
            guard budget.reserve(bytes, kind: .gpu) else { return nil }
            let lease = SceneResourceLease(budget: budget, bytes: bytes)
            objc_setAssociatedObject(pixelBuffer, &leaseKey, lease, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        objc_setAssociatedObject(texture, &leaseKey, SceneVideoResourceLifetime(pixelBuffer), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return imported
    }
}

extension MTLDevice {
    nonisolated func makeSceneTexture(
        descriptor: MTLTextureDescriptor, budget: SceneResourceBudget = .shared
    ) -> MTLTexture? {
        SceneResourceAllocation.make(bytes: heapTextureSizeAndAlign(descriptor: descriptor).size, budget: budget) {
            makeTexture(descriptor: descriptor)
        }
    }

    nonisolated func makeSceneBuffer(
        length: Int, options: MTLResourceOptions = [], budget: SceneResourceBudget = .shared
    ) -> MTLBuffer? {
        SceneResourceAllocation.make(bytes: heapBufferSizeAndAlign(length: length, options: options).size, budget: budget) {
            makeBuffer(length: length, options: options)
        }
    }

    nonisolated func makeSceneBuffer(
        bytes: UnsafeRawPointer, length: Int, options: MTLResourceOptions = [],
        budget: SceneResourceBudget = .shared
    ) -> MTLBuffer? {
        SceneResourceAllocation.make(bytes: heapBufferSizeAndAlign(length: length, options: options).size, budget: budget) {
            makeBuffer(bytes: bytes, length: length, options: options)
        }
    }
}

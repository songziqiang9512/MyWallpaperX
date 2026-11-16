import Foundation
import Metal

/// Exercises cohort allocation, actual depth storage and failure recovery together.
enum SceneShadowCohortResourceChecks {
    static func run(
        device: MTLDevice, queue: MTLCommandQueue,
        clear: (MTLTexture, Double, MTLCommandBuffer) -> Void,
        readback: (MTLTexture, MTLCommandBuffer, MTLDevice) -> MTLBuffer
    ) -> [String: Bool] {
        var checks: [String: Bool] = [:]
        let cohortDimensions = [(slot: 0, width: 8, height: 8), (slot: 1, width: 4, height: 8),
                                (slot: 2, width: 8, height: 4), (slot: 3, width: 4, height: 4)]
        let cohortPool = SceneOffscreenTexturePool(device: device, residentByteBudget: 576)
        let cohortCB = queue.makeCommandBuffer()!, cohortEvent = device.makeSharedEvent()!
        cohortCB.encodeWaitForEvent(cohortEvent, value: 1)
        let cohort = cohortPool.reserveModelShadows(dimensions: cohortDimensions, commandBuffer: cohortCB)!
        let cohortAgain = cohortPool.reserveModelShadows(dimensions: Array(cohortDimensions.reversed()), commandBuffer: cohortCB)!
        checks["cohort-mixed-slots-and-extents"] = cohort.count == 4 && cohortAgain.count == 4
            && cohortPool.residentByteCost == 576 && cohortDimensions.allSatisfy { d in
                cohort[d.slot]?.texture.width == d.width && cohort[d.slot]?.texture.height == d.height
                    && cohort[d.slot]?.texture.pixelFormat == .depth32Float
            }
        cohortAgain.values.forEach { $0.pin.release() }
        checks["cohort-other-cb-cannot-overwrite"] = cohortPool.reserveModelShadows(
            dimensions: cohortDimensions, commandBuffer: queue.makeCommandBuffer()!) == nil
            && cohortPool.residentByteCost == 576
        let cohortPixels = cohort.map { slot, target in
            clear(target.texture, 0.25 + Double(slot) * 0.125, cohortCB)
            return (slot, readback(target.texture, cohortCB, device))
        }
        let cohortDone = DispatchSemaphore(value: 0)
        cohortCB.addCompletedHandler { _ in
            cohort.values.forEach { $0.pin.release() }
            cohortDone.signal()
        }
        cohortCB.commit(); cohortPool.reset()
        checks["cohort-reset-retains-inflight"] = cohortCB.status != .completed && cohortPool.residentByteCost == 576
        cohortEvent.signaledValue = 1
        cohortCB.waitUntilCompleted(); cohortDone.wait()
        checks["cohort-completion-keeps-keyed-depths"] = cohortCB.status == .completed && cohortCB.error == nil
            && cohortPixels.allSatisfy { slot, buffer in
                buffer.contents().bindMemory(to: Float.self, capacity: 1).pointee == 0.25 + Float(slot) * 0.125
            } && cohortPool.residentByteCost == 0
        let failingCohort = SceneOffscreenTexturePool(device: device, residentByteBudget: 1024)
        let stagedBudget = SceneResourceBudget(maximumBytes: Int.max)
        var cohortAttempts = 0
        autoreleasepool {
            let failed = failingCohort.reserveModelShadows(dimensions: cohortDimensions,
                commandBuffer: queue.makeCommandBuffer()!, textureFactory: { descriptor in
                    cohortAttempts += 1
                    return cohortAttempts == 1 ? device.makeSceneTexture(descriptor: descriptor, budget: stagedBudget) : nil
                })
            checks["cohort-factory-failure-rolls-back"] = failed == nil && cohortAttempts >= 2
                && failingCohort.residentByteCost == 0 && failingCohort.residentAllocationCount == 0
        }
        checks["cohort-staged-physical-lease-released"] = stagedBudget.snapshot.residentBytes == 0
        let limitedCohort = SceneOffscreenTexturePool(device: device, residentByteBudget: 256)
        var cohortFactories = 0
        let desired = limitedCohort.reserveModelShadows(dimensions: cohortDimensions,
            commandBuffer: queue.makeCommandBuffer()!, textureFactory: { cohortFactories += 1; return device.makeTexture(descriptor: $0) })
        checks["cohort-budget-denies-without-publication"] = desired == nil && cohortFactories == 0
            && limitedCohort.residentByteCost == 0 && limitedCohort.residentAllocationCount == 0
        let fallbackCB = queue.makeCommandBuffer()!
        let fallback = (0..<4).map { limitedCohort.reserveModelShadow(slot: $0, width: 4, height: 4, commandBuffer: fallbackCB)! }
        checks["cohort-denial-preserves-four-baseline-slots"] = fallback.count == 4 && limitedCohort.residentByteCost == 256
        limitedCohort.reset(); fallback.forEach { $0.pin.release() }
        checks["cohort-cancel-releases-baseline-pins"] = limitedCohort.residentByteCost == 0

        let warmPool = SceneOffscreenTexturePool(device: device, residentByteBudget: 1024)
        let warmBudget = SceneResourceBudget(maximumBytes: Int.max)
        let fallbackDimensions = (0..<4).map { (slot: $0, width: 4, height: 4) }
        let originalIDs: [Int: ObjectIdentifier] = autoreleasepool {
            let cb = queue.makeCommandBuffer()!
            var targets: [Int: SceneOffscreenTexturePool.PinnedTexture] = [:]
            var pixels: [Int: MTLBuffer] = [:]
            for d in fallbackDimensions {
                if let target = warmPool.reserveModelShadow(slot: d.slot, width: d.width,
                    height: d.height, commandBuffer: cb,
                    textureFactory: { device.makeSceneTexture(descriptor: $0, budget: warmBudget) }) {
                    targets[d.slot] = target
                    clear(target.texture, 0.25 + Double(d.slot) * 0.125, cb)
                    pixels[d.slot] = readback(target.texture, cb, device)
                }
            }
            cb.commit(); cb.waitUntilCompleted()
            checks["cohort-warm-baseline-completed"] = targets.count == 4 && pixels.count == 4
                && cb.status == .completed && cb.error == nil && pixels.allSatisfy { slot, buffer in
                    buffer.contents().bindMemory(to: Float.self, capacity: 1).pointee == 0.25 + Float(slot) * 0.125
                }
            let identities = targets.mapValues { ObjectIdentifier($0.texture) }
            targets.values.forEach { $0.pin.release() }
            return identities
        }
        let warmPhysicalBytes = warmBudget.snapshot.residentBytes
        checks["cohort-warm-idle-retained"] = warmPool.residentByteCost == 256
            && warmPool.residentAllocationCount == 4 && warmPhysicalBytes > 0
        var highFactories = 0
        let neverAllocate: (MTLTextureDescriptor) -> MTLTexture? = { _ in highFactories += 1; return nil }
        autoreleasepool {
#if MWX_SHADOW_COHORT_OLD_API
            let denied = warmPool.reserveModelShadows(dimensions: cohortDimensions,
                commandBuffer: queue.makeCommandBuffer()!, textureFactory: neverAllocate)
#else
            let denied = warmPool.reserveModelShadows(dimensions: cohortDimensions,
                fallbackDimensions: fallbackDimensions, commandBuffer: queue.makeCommandBuffer()!,
                textureFactory: neverAllocate)
#endif
            checks["cohort-warm-high-failure-not-published"] = denied == nil && highFactories > 0
        }
        checks["cohort-warm-fallback-residency-preserved"] = warmPool.residentByteCost == 256
            && warmPool.residentAllocationCount == 4 && warmBudget.snapshot.residentBytes == warmPhysicalBytes
        var fallbackFactories = 0
        autoreleasepool {
            let cb = queue.makeCommandBuffer()!
            var targets: [Int: SceneOffscreenTexturePool.PinnedTexture] = [:]
            var pixels: [Int: MTLBuffer] = [:]
            for d in fallbackDimensions {
                if let target = warmPool.reserveModelShadow(slot: d.slot, width: d.width,
                    height: d.height, commandBuffer: cb, textureFactory: { descriptor in
                        fallbackFactories += 1
                        return device.makeSceneTexture(descriptor: descriptor, budget: warmBudget)
                    }) {
                    targets[d.slot] = target
                    if ObjectIdentifier(target.texture) == originalIDs[d.slot] {
                        pixels[d.slot] = readback(target.texture, cb, device)
                    }
                }
            }
            cb.commit(); cb.waitUntilCompleted()
            checks["cohort-warm-fallback-zero-allocation-same-textures"] = targets.count == 4
                && fallbackFactories == 0 && targets.allSatisfy { slot, target in
                    ObjectIdentifier(target.texture) == originalIDs[slot]
                }
            checks["cohort-warm-fallback-depth-content-preserved"] = pixels.count == 4
                && cb.status == .completed && cb.error == nil && pixels.allSatisfy { slot, buffer in
                    buffer.contents().bindMemory(to: Float.self, capacity: 1).pointee == 0.25 + Float(slot) * 0.125
                }
            warmPool.reset(); targets.values.forEach { $0.pin.release() }
        }
        checks["cohort-warm-final-logical-physical-release"] = warmPool.residentByteCost == 0
            && warmBudget.snapshot.residentBytes == 0
        return checks
    }
}

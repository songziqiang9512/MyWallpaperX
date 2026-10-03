import Foundation
import Metal

extension SceneOffscreenTexturePool {
    nonisolated enum SceneColorIntent: Hashable {
        case persistence
        case snapshot
    }

    var sceneColorResetEpoch: UUID { allocationCache.locked { allocationCache.resetEpoch } }

    /// Surface-local storage in the existing residency domain. Only the
    /// submission coordinator decides which raw member is completed/current.
    struct SceneColorTargets {
        let first: MTLTexture
        let second: MTLTexture
        let display: MTLTexture?
        let intent: SceneColorIntent
        let identity: SceneOffscreenTexturePhysicalIdentity

        func raw(_ member: Int) -> MTLTexture { member == 0 ? first : second }
    }

    struct SceneColorLease {
        let targets: SceneColorTargets
        let key: CacheKey
        let resetEpoch: UUID
        let retention: SceneGraphRenderTargetResidencyPin
        let submission: SceneGraphRenderTargetResidencyPin

        func release() {
            retention.release()
            submission.release()
        }
    }

    /// Cleared scenes need one exact scratch surface, held through the same
    /// completion pin domain. This reuses composition storage, not raw history.
    func reserveDisplayScratch(width: Int, height: Int, commandBuffer: MTLCommandBuffer)
        -> (texture: MTLTexture, pin: SceneGraphRenderTargetResidencyPin)? {
        guard let target = compositionTarget(width: width, height: height, commandBuffer: commandBuffer,
            extentPolicy: .init(maximumDimensionClass: .poolLimit,
                                requiresExactInputExtent: true)) else { return nil }
        guard let pin = target.pin else { return nil }
        return (target.texture, pin)
    }

    /// Exact terminal extent: unlike a layer effect this may never silently
    /// downscale, because admission and the compositor share the same target.
    func reserveSceneColor(
        width: Int, height: Int,
        intent: SceneColorIntent = .persistence,
        textureFactory: ((MTLTextureDescriptor) -> MTLTexture?)? = nil
    ) -> SceneColorLease? {
        let textureCount = intent == .persistence ? 3 : 2
        guard width > 0, height > 0, width <= maxDimension, height <= maxDimension,
              [.bgra8Unorm, .rgba8Unorm, .rgba16Float].contains(pixelFormat),
              intent == .snapshot || pixelFormat == .rgba16Float,
              let cost = byteCost(width: width, height: height, textureCount: textureCount),
              cost <= residentByteBudget else { return nil }
        let key = CacheKey.sceneColor(width: width, height: height,
                                      pixelFormat: pixelFormat, intent: intent)
        if allocationCache.allocation(for: key) == nil {
            guard var expectedRevision = allocationCache.locked({ () -> UUID? in
                var proposed = allocationCache.residents
                guard allocationCache.evictToFit(&proposed, incomingCost: cost,
                    protected: [key]) else { return nil }
                return allocationCache.revision
            }) else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .renderTarget]
            let factory = textureFactory ?? { [device] in
                device.makeSceneTexture(descriptor: $0)
            }
            var attemptedRecovery = false
            func allocate() -> MTLTexture? {
                if let texture = factory(descriptor) { return texture }
                guard !attemptedRecovery else { return nil }
                attemptedRecovery = true
                guard let revision = allocationCache.reclaimIdleAllocations(
                    expectedRevision: expectedRevision, protectedKeys: [key])
                else { return nil }
                expectedRevision = revision
                return factory(descriptor)
            }
            guard let first = allocate(), let second = allocate() else { return nil }
            let display: MTLTexture?
            if intent == .persistence {
                guard let target = allocate() else { return nil }
                display = target
            } else {
                display = nil
            }
            guard let identity = allocationCache.issuePhysicalIdentity(
                    textures: [first, second] + (display.map { [$0] } ?? [])) else { return nil }
            let targets = SceneColorTargets(first: first, second: second,
                                           display: display, intent: intent, identity: identity)
            guard allocationCache.locked({
                guard allocationCache.revision == expectedRevision,
                      let staged = allocationCache.stageCandidates([.init(key: key,
                        allocation: .sceneColor(targets), byteCost: cost)],
                        protectedKeys: [key]) else { return false }
                allocationCache.apply(staged)
                return true
            }) else { return nil }
        }
        return allocationCache.locked {
            guard var entry = allocationCache.residents[.current(key)],
                  !entry.isResetInvalidated, entry.submissionPins.isEmpty,
                  case .sceneColor(let targets) = entry.allocation else { return nil }
            let retentionID = UUID(), submissionID = UUID()
            entry.sceneColorPins.insert(retentionID)
            entry.submissionPins[submissionID] = .init(orderingContext: nil)
            allocationCache.residents[.current(key)] = entry
            allocationCache.revision = UUID()
            return SceneColorLease(targets: targets, key: key,
                resetEpoch: allocationCache.resetEpoch,
                retention: .init(identity: retentionID, purpose: .sceneColor,
                    generation: targets.identity.generation, cache: allocationCache),
                submission: .init(identity: submissionID, purpose: .submission,
                    generation: targets.identity.generation, cache: allocationCache))
        }
    }
}

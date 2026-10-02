import Foundation
import Metal

extension SceneOffscreenTexturePool {
    var sceneColorResetEpoch: UUID { allocationCache.locked { allocationCache.resetEpoch } }

    /// Surface-local storage in the existing residency domain. Only the
    /// submission coordinator decides which raw member is completed/current.
    struct SceneColorTargets {
        let first: MTLTexture
        let second: MTLTexture
        let display: MTLTexture
        let identity: SceneOffscreenTexturePhysicalIdentity

        func raw(_ member: Int) -> MTLTexture { member == 0 ? first : second }
    }

    struct SceneColorLease {
        let targets: SceneColorTargets
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
        textureFactory: ((MTLTextureDescriptor) -> MTLTexture?)? = nil
    ) -> SceneColorLease? {
        guard width > 0, height > 0, width <= maxDimension, height <= maxDimension,
              pixelFormat == .rgba16Float,
              let cost = byteCost(width: width, height: height, textureCount: 3),
              cost <= residentByteBudget else { return nil }
        let key = CacheKey.sceneColor(width: width, height: height)
        if allocationCache.allocation(for: key) == nil {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .renderTarget]
            let factory = textureFactory ?? { [device] in
                device.makeSceneTexture(descriptor: $0)
            }
            guard let first = factory(descriptor), let second = factory(descriptor),
                  let display = factory(descriptor),
                  let identity = allocationCache.issuePhysicalIdentity(
                    textures: [first, second, display]) else { return nil }
            let targets = SceneColorTargets(first: first, second: second,
                                           display: display, identity: identity)
            guard allocationCache.commit([.init(key: key,
                allocation: .sceneColor(targets), byteCost: cost)]) else { return nil }
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
            return SceneColorLease(targets: targets,
                resetEpoch: allocationCache.resetEpoch,
                retention: .init(identity: retentionID, purpose: .sceneColor,
                    generation: targets.identity.generation, cache: allocationCache),
                submission: .init(identity: submissionID, purpose: .submission,
                    generation: targets.identity.generation, cache: allocationCache))
        }
    }
}

import Foundation
import Metal

/// Calls the real pool and native budget. No cache or accounting model lives here.
@main enum AllocationRecoveryHarness {
    enum Kind: String, CaseIterable { case frame, single, group, environment, shadow, snapshot, persistence }
    final class Witness { weak var texture: MTLTexture? }
    static func descriptor(_ format: MTLPixelFormat, _ width: Int, _ height: Int,
                           mipmapped: Bool = false) -> MTLTextureDescriptor {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
            width: width, height: height, mipmapped: mipmapped)
        d.storageMode = .private; d.usage = [.shaderRead, .renderTarget]
        return d
    }
    static func format(_ kind: Kind) -> MTLPixelFormat { kind == .persistence ? .rgba16Float : .rgba8Unorm }
    static func count(_ kind: Kind) -> Int { kind == .snapshot ? 2 : kind == .persistence ? 3 : 1 }
    static func logical(_ d: MTLTextureDescriptor) -> Int {
        var total = 0, w = d.width, h = d.height
        for _ in 0..<d.mipmapLevelCount {
            total += w * h * (d.pixelFormat == .rgba16Float ? 8 : 4)
            w = max(w / 2, 1); h = max(h / 2, 1)
        }
        return total
    }
    static func request(_ kind: Kind, _ pool: SceneOffscreenTexturePool,
                        _ cb: MTLCommandBuffer, _ factory: @escaping (MTLTextureDescriptor) -> MTLTexture?) -> Bool {
        switch kind {
        case .frame:
            guard let values = pool.reserveCompositionTargets(dimensions: [(512,256)], commandBuffer: cb,
                textureFactory: factory) else { return false }
            values.forEach { $0.pin.release() }; return true
        case .single:
            guard let value = pool.compositionTarget(width: 512, height: 256, commandBuffer: cb,
                textureFactory: factory) else { return false }
            value.pin?.release(); return true
        case .group:
            guard let value = pool.compositionGroupTarget(layerID: 7, width: 512, height: 256,
                commandBuffer: cb, textureFactory: factory) else { return false }
            value.pin.release(); return true
        case .environment:
            guard let value = pool.reserveEnvironment(width: 512, height: 256, commandBuffer: cb,
                textureFactory: factory) else { return false }
            value.pin.release(); return true
        case .shadow:
            guard let value = pool.reserveModelShadow(slot: 1, width: 512, height: 256,
                commandBuffer: cb, textureFactory: factory) else { return false }
            value.pin.release(); return true
        case .snapshot, .persistence:
            guard let value = pool.reserveSceneColor(width: 512, height: 256,
                intent: kind == .snapshot ? .snapshot : .persistence,
                textureFactory: factory) else { return false }
            value.release(); return true
        }
    }
    static func seed(_ pool: SceneOffscreenTexturePool, _ queue: MTLCommandQueue,
                     _ account: SceneResourceBudget, snapshot: Bool, _ witness: Witness) {
        autoreleasepool {
            let factory = { pool.device.makeSceneTexture(descriptor: $0, budget: account) }
            if snapshot {
                let value = pool.reserveSceneColor(width: 64, height: 64, intent: .snapshot,
                    textureFactory: factory)!
                witness.texture = value.targets.first; value.release()
            } else {
                let value = pool.reserveEnvironment(width: 64, height: 64,
                    commandBuffer: queue.makeCommandBuffer()!, textureFactory: factory)!
                witness.texture = value.texture; value.pin.release()
            }
        }
    }
    static func pressure(_ device: MTLDevice, _ queue: MTLCommandQueue,
                         kind: Kind, wide: Bool, snapshot: Bool) -> [String: Any] {
        let f = format(kind)
        let d = descriptor(kind == .shadow ? .depth32Float : f, 512, 256, mipmapped: kind == .environment)
        let charge = device.heapTextureSizeAndAlign(descriptor: d).size * count(kind)
        let pool = SceneOffscreenTexturePool(device: device, pixelFormat: f,
            residentByteBudget: logical(d) * count(kind) * (wide ? 16 : 1))
        let account = SceneResourceBudget(maximumBytes: charge), witness = Witness()
        seed(pool, queue, account, snapshot: snapshot, witness)
        let before = account.snapshot.residentBytes
        var calls = 0
        let success = autoreleasepool {
            request(kind, pool, queue.makeCommandBuffer()!) {
                calls += 1; return device.makeSceneTexture(descriptor: $0, budget: account)
            }
        }
        let resident = account.snapshot.residentBytes, oldReleased = witness.texture == nil
        let rejects = account.snapshot.rejectionCount
        autoreleasepool { pool.reset() }
        return ["kind":kind.rawValue, "wide":wide, "snapshot":snapshot, "success":success,
            "calls":calls, "expectedCalls":count(kind)+1, "rejections":rejects,
            "oldCharge":before, "nativeCharge":charge, "resident":resident,
            "oldReleased":oldReleased, "finalBytes":account.snapshot.residentBytes]
    }
    static func externalReference(_ device: MTLDevice, _ queue: MTLCommandQueue) -> [String: Any] {
        let charge = device.heapTextureSizeAndAlign(descriptor: descriptor(.rgba8Unorm,512,256)).size
        let account = SceneResourceBudget(maximumBytes: charge)
        let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba8Unorm, residentByteBudget: charge * 16)
        let witness = Witness(); seed(pool, queue, account, snapshot: false, witness)
        var external: MTLTexture? = witness.texture
        let oldCharge = account.snapshot.residentBytes
        var calls = 0
        let success = autoreleasepool {
            request(.frame, pool, queue.makeCommandBuffer()!) {
                calls += 1; return device.makeSceneTexture(descriptor:$0,budget:account)
            }
        }
        let retained = account.snapshot.residentBytes == oldCharge && witness.texture != nil
        let empty = pool.allocationCache.residentAllocationCount == 0
        withExtendedLifetime(external) {}
        external = nil
        let released = account.snapshot.residentBytes == 0 && witness.texture == nil
        let retry = autoreleasepool {
            request(.frame, pool, queue.makeCommandBuffer()!) { device.makeSceneTexture(descriptor:$0,budget:account) }
        }
        autoreleasepool { pool.reset() }
        return ["failed": !success, "calls":calls, "cacheEmpty":empty, "retained":retained,
            "released":released, "retry":retry, "finalBytes":account.snapshot.residentBytes]
    }
    static func failureBoundary(_ device: MTLDevice, _ queue: MTLCommandQueue) -> [String: Any] {
        let pool = SceneOffscreenTexturePool(device:device,pixelFormat:.rgba16Float,residentByteBudget:32*1024*1024)
        let account = SceneResourceBudget(maximumBytes:32*1024*1024), witness = Witness()
        seed(pool, queue, account, snapshot:false,witness)
        var calls = 0
        let prefix = Witness(), retried = Witness()
        let success = autoreleasepool {
            request(.persistence,pool,queue.makeCommandBuffer()!) { d in
                calls += 1
                if calls == 2 || calls == 4 { return nil }
                let value = device.makeSceneTexture(descriptor:d,budget:account)
                if calls == 1 { prefix.texture = value } else { retried.texture = value }
                return value
            }
        }
        // Injected nil tests transaction behavior; this is not a budget rejection.
        return ["failed": !success,"calls":calls,"empty":pool.allocationCache.residentAllocationCount == 0,
            "prefixReleased":prefix.texture == nil,"retryReleased":retried.texture == nil,
            "victimReleased":witness.texture == nil,"finalBytes":account.snapshot.residentBytes,
            "quotaRejections":account.snapshot.rejectionCount]
    }
    static func revisionRaces(_ device: MTLDevice, _ queue: MTLCommandQueue) -> [[String: Any]] {
        Kind.allCases.flatMap { kind in [true,false].map { factoryNil in
            let pool = SceneOffscreenTexturePool(device:device,pixelFormat:format(kind),residentByteBudget:32*1024*1024)
            let account = SceneResourceBudget(maximumBytes:32*1024*1024), witness = Witness()
            seed(pool,queue,account,snapshot:false,witness)
            var calls = 0
            let success = autoreleasepool {
                request(kind,pool,queue.makeCommandBuffer()!) { d in
                    calls += 1
                    if calls == 1 { pool.reset() }
                    return factoryNil ? nil : device.makeSceneTexture(descriptor:d,budget:account)
                }
            }
            return ["kind":kind.rawValue,"nil":factoryNil,"failed": !success,"calls":calls,
                "expectedCalls":factoryNil ? 1 : count(kind),
                "empty":pool.allocationCache.residentAllocationCount == 0,
                "finalBytes":account.snapshot.residentBytes]
        } }
    }
    static func noVictim(_ device: MTLDevice, _ queue: MTLCommandQueue) -> [String: Any] {
        let pool = SceneOffscreenTexturePool(device:device,pixelFormat:.rgba8Unorm,residentByteBudget:32*1024*1024)
        var calls = 0
        let failed = !request(.snapshot,pool,queue.makeCommandBuffer()!) { _ in calls += 1; return nil }
        return ["failed":failed,"calls":calls,"empty":pool.allocationCache.residentAllocationCount == 0]
    }
    static func retainedSceneColor(_ device: MTLDevice, _ queue: MTLCommandQueue) -> [String: Any] {
        let charge = device.heapTextureSizeAndAlign(descriptor:descriptor(.rgba8Unorm,512,256)).size
        let account = SceneResourceBudget(maximumBytes:charge)
        let pool = SceneOffscreenTexturePool(device:device,pixelFormat:.rgba8Unorm,residentByteBudget:charge*16)
        var lease: SceneOffscreenTexturePool.SceneColorLease? = pool.reserveSceneColor(width:64,height:64,
            intent:.snapshot,textureFactory:{device.makeSceneTexture(descriptor:$0,budget:account)})!
        let generation = lease!.targets.identity.generation
        lease!.submission.release()
        var calls = 0
        let success = autoreleasepool {
            request(.frame,pool,queue.makeCommandBuffer()!) { calls += 1;return device.makeSceneTexture(descriptor:$0,budget:account) }
        }
        let retained = pool.allocationCache.locked {
            pool.allocationCache.residents.values.contains { $0.allocation.generation == generation && !$0.sceneColorPins.isEmpty }
        }
        lease!.retention.release();lease = nil
        let retry = autoreleasepool {
            request(.frame,pool,queue.makeCommandBuffer()!) {device.makeSceneTexture(descriptor:$0,budget:account)}
        }
        autoreleasepool {pool.reset()}
        return ["failed": !success,"calls":calls,"retained":retained,"retry":retry,"finalBytes":account.snapshot.residentBytes]
    }
    static func inFlight(_ device: MTLDevice, _ queue: MTLCommandQueue) -> [String: Any] {
        let charge = device.heapTextureSizeAndAlign(descriptor:descriptor(.rgba8Unorm,512,256)).size
        let account = SceneResourceBudget(maximumBytes:charge)
        let pool = SceneOffscreenTexturePool(device:device,pixelFormat:.rgba8Unorm,residentByteBudget:charge*16)
        let event = device.makeSharedEvent()!, complete = DispatchSemaphore(value:0)
        var buffer: MTLCommandBuffer? = queue.makeCommandBuffer()!
        buffer!.encodeWaitForEvent(event,value:1)
        weak var texture: MTLTexture?
        autoreleasepool {
            let value = pool.reserveEnvironment(width:64,height:64,commandBuffer:buffer!,
                textureFactory:{device.makeSceneTexture(descriptor:$0,budget:account)})!
            texture = value.texture
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = value.texture
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0.25,0.5,0.75,1)
            buffer!.makeRenderCommandEncoder(descriptor:pass)!.endEncoding()
            let pin = value.pin
            buffer!.addCompletedHandler { _ in pin.release();complete.signal() }
        }
        buffer!.commit()
        var calls = 0
        let success = autoreleasepool {
            request(.frame,pool,queue.makeCommandBuffer()!) {calls += 1;return device.makeSceneTexture(descriptor:$0,budget:account)}
        }
        let blocked = buffer!.status != .completed && texture != nil
        event.signaledValue = 1;buffer!.waitUntilCompleted()
        let signaled = complete.wait(timeout:.now()+10) == .success
        let completed = buffer!.status == .completed && buffer!.error == nil && signaled
        buffer = nil
        let retry = autoreleasepool {
            request(.frame,pool,queue.makeCommandBuffer()!) {device.makeSceneTexture(descriptor:$0,budget:account)}
        }
        autoreleasepool {pool.reset()}
        return ["failed": !success,"calls":calls,"blocked":blocked,"completed":completed,
            "retry":retry,"finalBytes":account.snapshot.residentBytes]
    }
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}");return
        }
        var rows: [[String:Any]] = []
        for kind in Kind.allCases { for wide in [false,true] { for snapshot in [false,true] {
            rows.append(autoreleasepool {pressure(device,queue,kind:kind,wide:wide,snapshot:snapshot)})
        } } }
        let report: [String:Any] = ["pressure":rows,
            "external":autoreleasepool {externalReference(device,queue)},
            "failure":autoreleasepool {failureBoundary(device,queue)},
            "races":autoreleasepool {revisionRaces(device,queue)},
            "noVictim":autoreleasepool {noVictim(device,queue)},
            "retention":autoreleasepool {retainedSceneColor(device,queue)},
            "inFlight":autoreleasepool {inFlight(device,queue)}]
        print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:.sortedKeys),as:UTF8.self))
    }
}

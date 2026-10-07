"""R8 clip coverage shares the production pool's identity and pin lifecycle."""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile
import unittest

from .test_scene_offscreen_texture_pool import SWIFT_SOURCES


SUPPORT = (Path(__file__).with_name("fixtures") / "SceneOffscreenPoolSupport.swift").read_text()
HARNESS = r'''
@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}"); return
        }
        var checks: [String: Bool] = [:]
        let domain = UUID(), otherDomain = UUID()
        let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float,
                                            residentByteBudget: 120)
        let cb = queue.makeCommandBuffer()!
        func reserve(_ layer: Int, _ clip: Int, _ space: UUID) -> SceneOffscreenTexturePool.PinnedTexture {
            pool.reservePuppetClipping(layerID: layer, clipID: clip, domain: space,
                width: 6, height: 5, commandBuffer: cb)!
        }
        let first = reserve(1, 0, domain), same = reserve(1, 0, domain)
        let otherClip = reserve(1, 1, domain), otherLayer = reserve(2, 0, domain)
        let otherSpace = reserve(1, 0, otherDomain)
        let leases = [first, otherClip, otherLayer, otherSpace]
        checks["identity-isolates-all-axes"] = Set(leases.map { ObjectIdentifier($0.texture) }).count == 4
            && Set(leases.map { $0.pin.generation }).count == 4
        checks["same-cb-reuses-exact-key"] = first.texture === same.texture
            && first.pin.generation == same.pin.generation
        checks["r8-descriptor-and-exact-budget"] = pool.residentByteCost == 120
            && pool.residentTextureCount == 4 && leases.allSatisfy {
                $0.texture.pixelFormat == .r8Unorm && $0.texture.mipmapLevelCount == 1
                    && $0.texture.storageMode == .private && $0.texture.sampleCount == 1
                    && $0.texture.usage.contains([.renderTarget, .shaderRead])
            }
        first.pin.release()
        pool.reset()
        checks["reset-preserves-remaining-pins"] = pool.residentByteCost == 120
        same.pin.release()
        checks["last-pin-releases-reset-generation"] = pool.residentByteCost == 90
        leases.dropFirst().forEach { $0.pin.release() }
        checks["cancel-clears-reset-residency"] = pool.residentByteCost == 0

        let limited = SceneOffscreenTexturePool(device: device, maxDimension: 8, residentByteBudget: 60)
        let healthy = limited.reservePuppetClipping(layerID: 3, clipID: 0, domain: domain,
            width: 6, height: 5, commandBuffer: cb)!
        var calls = 0
        let revision = limited.allocationCache.revision
        let denied = limited.reservePuppetClipping(layerID: 3, clipID: 1, domain: domain,
            width: 7, height: 5, commandBuffer: cb, textureFactory: {
                calls += 1; return device.makeTexture(descriptor: $0)
            })
        checks["budget-rejects-before-allocation"] = denied == nil && calls == 0
            && limited.residentByteCost == 30 && limited.allocationCache.revision == revision
        for (width, height) in [(0, 5), (-1, 5), (6, 0), (9, 5), (6, 9)] {
            let invalid = limited.reservePuppetClipping(layerID: 3, clipID: 2, domain: domain,
                width: width, height: height, commandBuffer: cb, textureFactory: {
                    calls += 1; return device.makeTexture(descriptor: $0)
                })
            checks["invalid-extent-\(width)-\(height)"] = invalid == nil && calls == 0
                && limited.residentByteCost == 30
        }
        let failed = limited.reservePuppetClipping(layerID: 3, clipID: 2, domain: domain,
            width: 5, height: 5, commandBuffer: cb, textureFactory: { _ in calls += 1; return nil })
        let stillHealthy = limited.reservePuppetClipping(layerID: 3, clipID: 0, domain: domain,
            width: 6, height: 5, commandBuffer: cb)!
        checks["allocation-failure-keeps-healthy-pin"] = failed == nil && calls == 1
            && stillHealthy.texture === healthy.texture && limited.residentByteCost == 30
        healthy.pin.release(); stillHealthy.pin.release()
        checks["released-mask-remains-reusable"] = limited.residentByteCost == 30
        let replacement = limited.reservePuppetClipping(layerID: 3, clipID: 1, domain: domain,
            width: 7, height: 5, commandBuffer: cb)!
        checks["idle-mask-is-budget-evictable"] = limited.residentByteCost == 35
            && limited.residentTextureCount == 1
        replacement.pin.release(); limited.reset()

        let raced = SceneOffscreenTexturePool(device: device, residentByteBudget: 30)
        let stale = raced.reservePuppetClipping(layerID: 4, clipID: 0, domain: domain,
            width: 6, height: 5, commandBuffer: cb, textureFactory: {
                let texture = device.makeTexture(descriptor: $0); raced.reset(); return texture
            })
        checks["reset-during-allocation-rejects-stale-stage"] = stale == nil
            && raced.residentByteCost == 0 && raced.residentAllocationCount == 0
        let wrong = raced.reservePuppetClipping(layerID: 4, clipID: 0, domain: domain,
            width: 6, height: 5, commandBuffer: cb, textureFactory: { descriptor in
                descriptor.pixelFormat = .rgba8Unorm
                return device.makeTexture(descriptor: descriptor)
            })
        checks["wrong-format-never-enters-r8-residency"] = wrong == nil && raced.residentByteCost == 0

        // Both old and replacement storage are used by real GPU commands. Reset
        // retains the exact generations until completion or explicit cancellation.
        let lifecycle = SceneOffscreenTexturePool(device: device, residentByteBudget: 48)
        let oldCB = queue.makeCommandBuffer()!, nextCB = queue.makeCommandBuffer()!
        let old = lifecycle.reservePuppetClipping(layerID: 5, clipID: 0, domain: domain,
            width: 4, height: 3, commandBuffer: oldCB)!
        let next = lifecycle.reservePuppetClipping(layerID: 5, clipID: 0, domain: domain,
            width: 4, height: 3, commandBuffer: nextCB)!
        checks["different-cb-keeps-old-generation"] = old.texture !== next.texture
            && old.pin.generation != next.pin.generation && lifecycle.residentByteCost == 24
        let resized = lifecycle.reservePuppetClipping(layerID: 5, clipID: 0, domain: domain,
            width: 5, height: 3, commandBuffer: nextCB)!
        checks["resize-keeps-pinned-extents"] = resized.texture !== next.texture
            && lifecycle.residentByteCost == 39
        func clearAndRead(_ texture: MTLTexture, red: Double, on buffer: MTLCommandBuffer) -> MTLBuffer {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(red, 0, 0, 1)
            buffer.makeRenderCommandEncoder(descriptor: pass)!.endEncoding()
            let output = device.makeBuffer(length: 256 * texture.height, options: .storageModeShared)!
            let blit = buffer.makeBlitCommandEncoder()!
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(),
                sourceSize: .init(width: texture.width, height: texture.height, depth: 1),
                to: output, destinationOffset: 0, destinationBytesPerRow: 256,
                destinationBytesPerImage: 256 * texture.height)
            blit.endEncoding()
            return output
        }
        let oldRead = clearAndRead(old.texture, red: 1, on: oldCB)
        let nextRead = clearAndRead(next.texture, red: 0, on: nextCB)
        lifecycle.reset()
        checks["reset-retains-all-inflight-extents"] = lifecycle.residentByteCost == 39
        let oldDone = DispatchSemaphore(value: 0)
        oldCB.addCompletedHandler { _ in old.pin.release(); oldDone.signal() }
        oldCB.commit(); oldCB.waitUntilCompleted(); oldDone.wait()
        checks["completion-releases-only-old-generation"] = lifecycle.residentByteCost == 27
        let nextDone = DispatchSemaphore(value: 0)
        nextCB.addCompletedHandler { _ in next.pin.release(); nextDone.signal() }
        nextCB.commit(); nextCB.waitUntilCompleted(); nextDone.wait()
        checks["gpu-coverage-is-independent"] = oldCB.status == .completed && nextCB.status == .completed
            && (0..<3).allSatisfy { y in (0..<4).allSatisfy { x in
                oldRead.contents().load(fromByteOffset: y * 256 + x, as: UInt8.self) == 255
                    && nextRead.contents().load(fromByteOffset: y * 256 + x, as: UInt8.self) == 0
            }}
        checks["completion-keeps-other-cancel-pin"] = lifecycle.residentByteCost == 15
        resized.pin.release()
        checks["completion-and-cancel-close-residency"] = lifecycle.residentByteCost == 0
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class ScenePuppetClippingPoolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-puppet-clip-pool-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(SUPPORT + HARNESS)
            binary = root / "pool"
            compiled = subprocess.run([
                "xcrun", "--sdk", "macosx", "swiftc", *map(str, SWIFT_SOURCES), str(harness),
                "-module-cache-path", str(root / "module-cache"), "-framework", "Metal", "-o", str(binary)
            ], capture_output=True, text=True)
            if compiled.returncode:
                raise RuntimeError(compiled.stderr)
            ran = subprocess.run([str(binary)], capture_output=True, text=True)
            if ran.returncode:
                raise RuntimeError(ran.stderr)
            cls.checks = json.loads(ran.stdout)
        if cls.checks.get("metalUnavailable"):
            raise unittest.SkipTest("Metal unavailable")

    def assert_checks(self, *keys):
        for key in keys:
            self.assertTrue(self.checks[key], key)

    def test_r8_identity_isolates_clip_layer_and_sampling_domain(self):
        self.assert_checks("identity-isolates-all-axes", "same-cb-reuses-exact-key",
                           "r8-descriptor-and-exact-budget")

    def test_budget_and_extent_failures_leave_healthy_mask_available(self):
        self.assert_checks("budget-rejects-before-allocation", "allocation-failure-keeps-healthy-pin",
                           "released-mask-remains-reusable", "idle-mask-is-budget-evictable")
        self.assert_checks(*(f"invalid-extent-{w}-{h}" for w, h in [(0, 5), (-1, 5), (6, 0), (9, 5), (6, 9)]))

    def test_stale_or_wrong_allocation_cannot_publish_mask_residency(self):
        self.assert_checks("reset-during-allocation-rejects-stale-stage",
                           "wrong-format-never-enters-r8-residency")

    def test_reset_and_cancel_release_only_the_matching_pins(self):
        self.assert_checks("reset-preserves-remaining-pins", "last-pin-releases-reset-generation",
                           "cancel-clears-reset-residency")

    def test_real_gpu_submission_retains_generations_across_resize_and_reset(self):
        self.assert_checks("different-cb-keeps-old-generation", "resize-keeps-pinned-extents",
                           "reset-retains-all-inflight-extents", "completion-releases-only-old-generation",
                           "gpu-coverage-is-independent", "completion-keeps-other-cancel-pin",
                           "completion-and-cancel-close-residency")

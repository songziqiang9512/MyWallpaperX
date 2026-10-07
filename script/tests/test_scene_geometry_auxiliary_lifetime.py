"""Geometry auxiliaries use the real MainPass completion/cancel owner."""
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
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let color = device.makeTexture(descriptor: descriptor)!
        let domain = UUID()
        var checks: [String: Bool] = [:]
        func pass(_ command: MTLCommandBuffer, owner: SceneMainPassEncoder? = nil) -> SceneMainPassEncoder {
            SceneMainPassEncoder(commandBuffer: command, target: color,
                clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: true,
                submissionOwner: owner)
        }
        func clear(_ texture: MTLTexture, command: MTLCommandBuffer) {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = texture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            command.makeRenderCommandEncoder(descriptor: descriptor)!.endEncoding()
        }

        // Real mask commands have been encoded, but the host declines the frame.
        // The unsubmitted buffer stays alive while a different clip needs the
        // exact same budget; completion cannot be the source of this release.
        let pool = SceneOffscreenTexturePool(device: device, residentByteBudget: 16)
        let cancelled = queue.makeCommandBuffer()!
        let root = pass(cancelled), group = pass(cancelled, owner: root)
        let mask = pool.reservePuppetClipping(layerID: 1, clipID: 0, domain: domain,
            width: 4, height: 4, commandBuffer: cancelled)!
        var cancelledReleases = 0
        group.retainAuxiliaryRelease { cancelledReleases += 1; mask.pin.release() }
        group.encodeOffscreen { clear(mask.texture, command: $0) }
        let blocked = pool.reservePuppetClipping(layerID: 1, clipID: 1, domain: domain,
            width: 4, height: 4, commandBuffer: cancelled)
        checks["pending-mask-protects-budget"] = blocked == nil && cancelledReleases == 0
        group.cancelCompositionPins()
        checks["group-delegates-to-root"] = cancelledReleases == 0
        root.cancelCompositionPins(); root.cancelCompositionPins()
        let healthy = pool.reservePuppetClipping(layerID: 1, clipID: 1, domain: domain,
            width: 4, height: 4, commandBuffer: cancelled)
        checks["cancel-releases-without-submitting"] = cancelled.status == .notEnqueued
            && cancelledReleases == 1 && healthy != nil && pool.residentByteCost == 16
        healthy?.pin.release(); pool.reset()
        checks["cancelled-residency-closes"] = pool.residentByteCost == 0

        // Existing composition pins and new auxiliary callbacks share one
        // completion. Calling cancel after arming cannot release GPU storage.
        let submittedPool = SceneOffscreenTexturePool(device: device, residentByteBudget: 32)
        let submitted = queue.makeCommandBuffer()!
        let submittedRoot = pass(submitted), submittedGroup = pass(submitted, owner: submittedRoot)
        let submittedMask = submittedPool.reservePuppetClipping(layerID: 2, clipID: 0, domain: domain,
            width: 4, height: 4, commandBuffer: submitted)!
        let composition = submittedPool.compositionTarget(width: 2, height: 2,
            commandBuffer: submitted)!
        let released = DispatchSemaphore(value: 0)
        submittedGroup.retainCompositionPin(composition.pin)
        submittedGroup.retainAuxiliaryRelease { submittedMask.pin.release(); released.signal() }
        submittedRoot.encodeOffscreen {
            clear(submittedMask.texture, command: $0); clear(composition.texture, command: $0)
        }
        submittedRoot.armCompositionPins()
        submittedRoot.cancelCompositionPins()
        submittedPool.reset()
        checks["armed-resources-survive-until-completion"] = submittedPool.residentByteCost == 32
            && released.wait(timeout: .now()) == .timedOut
        submitted.commit(); submitted.waitUntilCompleted()
        let completed = released.wait(timeout: .now() + 5) == .success
        checks["gpu-completion-releases-both-resource-kinds"] = completed
            && submitted.status == .completed && submitted.error == nil
            && submittedPool.residentByteCost == 0

        var abandonedReleases = 0
        var abandoned: SceneMainPassEncoder? = pass(queue.makeCommandBuffer()!)
        abandoned?.retainAuxiliaryRelease { abandonedReleases += 1 }
        abandoned = nil
        checks["unarmed-owner-deinit-cancels"] = abandonedReleases == 1
        print(String(decoding: try JSONSerialization.data(withJSONObject: checks,
            options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class SceneGeometryAuxiliaryLifetimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("swiftc"):
            raise unittest.SkipTest("swiftc unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-geometry-auxiliary-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(SUPPORT + HARNESS)
            binary = root / "auxiliary"
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

    def test_cancelled_group_auxiliary_releases_budget_without_submission(self):
        self.assert_checks("pending-mask-protects-budget", "group-delegates-to-root",
                           "cancel-releases-without-submitting", "cancelled-residency-closes")

    def test_submitted_auxiliary_and_composition_pin_live_until_gpu_completion(self):
        self.assert_checks("armed-resources-survive-until-completion",
                           "gpu-completion-releases-both-resource-kinds")

    def test_abandoned_unarmed_owner_runs_release_callback(self):
        self.assert_checks("unarmed-owner-deinit-cancels")


if __name__ == "__main__":
    unittest.main()

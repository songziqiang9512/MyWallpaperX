#!/usr/bin/env python3
"""RF07 direct product-owner checks and the pre-change terminal-output red case.

GPU: python3.12 -m unittest script.tests.test_scene_persistent_color_output.ScenePersistentColorOutputTests

The pre-change terminal primitive red is frozen in /private/tmp/mwx-rf07.
This gate now compiles the real target pool and submission coordinator together.
The fixture never implements its own history or completion state machine.
The GPU-failure case injects the existing completion seam after real commands
complete; it is not a hardware GPU-failure reproduction.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests.test_scene_material_copy_history_rendering import (
    SWIFT_SOURCES as OWNER_SOURCES, SUPPORT as OWNER_SUPPORT,
)

from script.tests.test_scene_bloom_post_process import FAULT_HEADER, FAULT_SOURCE

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
FIXTURES = Path(__file__).parent / "fixtures"
MAPPING = SCENE / "Rendering/Composition/SceneDisplayMappingPostProcess.swift"
RESOURCE_BUDGET = SCENE / "Resources/Textures/SceneResourceBudget.swift"


# Stored dependencies only. All color flow, outcome, pool and history logic is
# compiled from production files; this carrier avoids unrelated app systems.
TERMINAL_SUPPORT = r'''
struct TerminalRenderDescriptor {
    struct Camera { let clearColor: [Float]; let bloom: SceneBloomConfiguration }
    let hdrEnabled: Bool
    let camera: Camera
}
struct TerminalCompositor {
    let resolvedMaterialRuntime: SceneResolvedMaterialSubmissionCoordinator?
    func endResolvedMaterialFrame(on buffer: MTLCommandBuffer) -> Bool {
        guard let runtime = resolvedMaterialRuntime else { return false }
        let sealed = runtime.sealFrame(on: buffer)
        _ = runtime.endFrame()
        return sealed
    }
}
// Terminal-only carrier: these frame/group entrypoints are outside this
// gate's asserted source and deliberately trap if accidentally exercised.
final class SceneCompositionGroupFrameRuntime {
    init(parentPass: SceneMainPassEncoder, commandBuffer: MTLCommandBuffer,
         offscreenTexturePool: SceneOffscreenTexturePool,
         memberRootsByLayerID: [Int: Int], membersByRootID: [Int: [Int]], viewportSize: CGSize) {
        fatalError("terminal fixture must not prepare composition groups")
    }
    func reserveSources(orderedRootIDs: [Int], visibleLayerIDs: Set<Int>) {
        fatalError("terminal fixture must not reserve composition groups")
    }
    func closeAllGroupEncoders() {
        fatalError("terminal fixture must not capture reflection prefixes")
    }
}
struct SceneMetalRenderer {
    let compositionGroupMemberRootsByLayerID: [Int: Int] = [:]
    let compositionGroupMembersByRootID: [Int: [Int]] = [:]
    let compositionGroupRootIDs: [Int] = []
    let renderDescriptor: TerminalRenderDescriptor
    let imageCompositor: TerminalCompositor
    let bloomPostProcess: SceneBloomPostProcess?
    let displayMappingPostProcess: SceneDisplayMappingPostProcess?
}
'''
BLIT_FAULT_HEADER = "void MWXArmBlitFault(id<MTLCommandBuffer> buffer, NSUInteger mask);"
BLIT_FAULT_SOURCE = r'''
static id blitBuffer;
static NSUInteger blitMask, blitAttempts;
static IMP blitOriginal;
static id faultBlit(id receiver, SEL selector) {
    if (receiver == blitBuffer && (blitMask & (1UL << blitAttempts++))) return nil;
    return ((id (*)(id, SEL))blitOriginal)(receiver, selector);
}
void MWXArmBlitFault(id<MTLCommandBuffer> buffer, NSUInteger mask) {
    if (!blitOriginal) {
        Method method = class_getInstanceMethod(object_getClass(buffer), @selector(blitCommandEncoder));
        blitOriginal = method_setImplementation(method, (IMP)faultBlit);
    }
    blitBuffer = buffer;
    blitMask = mask;
    blitAttempts = 0;
}
'''


def _run(command: list[str], *, cwd: Path, timeout: int = 120) -> str:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                            timeout=timeout, check=False)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout


def _compile_and_run(name: str, *, source: str | None = None) -> dict:
    with tempfile.TemporaryDirectory(prefix="mwx-persistent-color-") as directory:
        folder = Path(directory)
        _run(["xcrun", "-sdk", "macosx", "metal", "-c",
              str(MAPPING.with_suffix(".metal")), "-o", str(folder / "mapping.air")],
             cwd=folder)
        _run(["xcrun", "-sdk", "macosx", "metal", "-c",
              str(MAPPING.with_name("SceneBloomPostProcess.metal")), "-o", str(folder / "bloom.air")], cwd=folder)
        (folder / "Fault.h").write_text(FAULT_HEADER + BLIT_FAULT_HEADER)
        (folder / "Fault.m").write_text(FAULT_SOURCE + BLIT_FAULT_SOURCE)
        _run(["xcrun", "clang", "-fobjc-arc", "-c", str(folder / "Fault.m"),
              "-o", str(folder / "fault.o")], cwd=folder)
        _run(["xcrun", "-sdk", "macosx", "metallib", str(folder / "mapping.air"), str(folder / "bloom.air"),
              "-o", str(folder / "default.metallib")], cwd=folder)
        support = folder / "Support.swift"
        support.write_text(OWNER_SUPPORT + TERMINAL_SUPPORT, encoding="utf-8")
        harness = FIXTURES / name
        if source is not None:
            harness = folder / name
            harness.write_text(source, encoding="utf-8")
        sources = list(dict.fromkeys([*OWNER_SOURCES, MAPPING, MAPPING.with_name("SceneBloomPostProcess.swift"), RESOURCE_BUDGET,
                   SCENE / "Rendering/Composition/SceneMainPassEncoder.swift",
                   SCENE / "Rendering/Frame/SceneMetalRenderer+ClearColor.swift",
                   SCENE / "Rendering/Frame/SceneMetalRenderer+FrameOutcome.swift", support, harness]))
        binary = folder / "persistent-color"
        compile_command = ["xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library", "-whole-module-optimization", "-D", "SCENE_GRAPH_TESTING",
              "-import-objc-header", str(folder / "Fault.h"), str(folder / "fault.o"),
              *map(str, sources), "-module-cache-path", str(folder / "module-cache"),
              "-o", str(binary)]
        _run(compile_command, cwd=folder, timeout=300)
        evidence = os.environ.get("MWX_REFLECTION_PRODUCER_EVIDENCE") if source is not None else None
        if evidence:
            destination = Path(evidence); destination.mkdir(parents=True, exist_ok=True)
            (destination / "Harness.swift").write_text(source, encoding="utf-8")
            (destination / "Support.swift").write_text(support.read_text(), encoding="utf-8")
            (destination / "source-manifest.json").write_text(json.dumps({
                "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "compileCommand": compile_command, "runCommand": [str(binary)], "cwd": str(folder),
                "sources": [{"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()} for path in sources],
                "binarySHA256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "metallibSHA256": hashlib.sha256((folder / "default.metallib").read_bytes()).hexdigest(),
            }, indent=2) + "\n")
        output = _run([str(binary)], cwd=folder, timeout=30)
        result = json.loads(output.strip().splitlines()[-1])
        if evidence:
            (Path(evidence) / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        return result


class ScenePersistentColorOutputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = _compile_and_run("ScenePersistentColorOutputHarness.swift")

    def test_accumulating_hdr_is_bounded_on_every_terminal_export(self):
        # Hardcoded independent shoulder golden; this fails before RF07.
        self.assertEqual(len(self.result["accumulatingFrames"]), 8)
        for frame in self.result["accumulatingFrames"]:
            self.assertTrue(frame["gpuCompleted"])
            self.assertAlmostEqual(frame["rgb"][0], 11 / 12, delta=1 / 1024)
            self.assertAlmostEqual(frame["rgb"][1], 0.25, delta=1 / 1024)
            self.assertAlmostEqual(frame["rgb"][2], 0.5, delta=1 / 1024)
            self.assertEqual(frame["alpha"], 1)

    def test_real_target_and_submission_owner_lifecycle(self):
        for name, passed in self.result["ownerChecks"].items():
            with self.subTest(name=name):
                self.assertTrue(passed, name)

    def test_half_alpha_authored_draw_accumulates_only_in_raw(self):
        expected = [[1.5, .625, .25, 1, 5/6, .6, .25, 1],
                    [.75, .8125, .125, 1, 2/3, 9/13, .125, 1]]
        for actual, golden in zip(self.result["alphaFrames"], expected, strict=True):
            for value, target in zip(actual, golden, strict=True):
                self.assertAlmostEqual(value, target, delta=1/1024)

    def test_existing_clear_true_and_non_hdr_routes_are_unchanged(self):
        self.assertTrue(self.result["clearedHDR"]["gpuCompleted"])
        self.assertAlmostEqual(self.result["clearedHDR"]["rgb"][0], 11 / 12, delta=1 / 1024)
        self.assertEqual(self.result["nonHDR"]["rgb"], [3, 0.25, 0.5])
        self.assertEqual(self.result["nonHDR"]["alpha"], 1)


REFLECTION_PRODUCER = r'''
import Foundation
import Metal

@main enum ReflectionProducerProbe {
    static func main() throws {
        let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
        let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float,
            maxDimension: 16, residentByteBudget: 4096)
        func texture(_ width: Int, _ height: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: width, height: height, mipmapped: false)
            d.storageMode = .shared; d.usage = [.shaderRead, .renderTarget]
            return device.makeSceneTexture(descriptor: d)!
        }
        let source = texture(4, 2)
        var pixels: [Float16] = []
        for _ in 0..<2 { for x in 0..<4 {
            pixels += x < 2 ? [2, 0, 0, 0.25] : [0, 4, 0, 0.75]
        } }
        pixels.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0, 0, 4, 2),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 32) }
        func makeFrame(_ epoch: UInt64) -> (SceneMetalRenderer.ReflectionFrame, SceneMainPassEncoder, MTLCommandBuffer) {
            let cb = queue.makeCommandBuffer()!
            let pass = SceneMainPassEncoder(commandBuffer: cb, target: source,
                clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: false)
            let frame = SceneMetalRenderer.ReflectionFrame(pool: pool, mainPass: pass,
                groupRuntime: nil, commandBuffer: cb, frameEpoch: epoch)
            frame.admit(pool.reserveCompositionTargets(dimensions: [(4, 2)], commandBuffer: cb)!)
            return (frame, pass, cb)
        }
        func readMip(_ source: MTLTexture, _ level: Int) -> [Float] {
            let w = max(1, source.width >> level), h = max(1, source.height >> level)
            let target = texture(w, h), cb = queue.makeCommandBuffer()!, blit = cb.makeBlitCommandEncoder()!
            blit.copy(from: source, sourceSlice: 0, sourceLevel: level, sourceOrigin: MTLOriginMake(0, 0, 0),
                sourceSize: MTLSizeMake(w, h, 1), to: target, destinationSlice: 0,
                destinationLevel: 0, destinationOrigin: MTLOriginMake(0, 0, 0))
            blit.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            precondition(cb.status == .completed && cb.error == nil)
            var values = [Float16](repeating: 0, count: w * h * 4)
            values.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: w * 8,
                from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
            return values.prefix(4).map(Float.init)
        }
        var checks: [String: Bool] = [:]
        let (first, firstPass, firstCB) = makeFrame(1)
        let a = first.resolve(firstCB)!
        checks["fullRealMipChain"] = a.publication.texture.mipmapLevelCount == 3
        checks["typedPublished"] = a.publication.isComplete && a.publication.requestIdentity == .sceneEnvironment
            && a.publication.contentGeneration == 1
        // Change the actual main source after capture. A second resolver call
        // in this frame must preserve the original red/green prefix.
        let clear = MTLRenderPassDescriptor()
        clear.colorAttachments[0].texture = source
        clear.colorAttachments[0].loadAction = .clear
        clear.colorAttachments[0].storeAction = .store
        clear.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 3, 1)
        firstCB.makeRenderCommandEncoder(descriptor: clear)!.endEncoding()
        let again = first.resolve(firstCB)!
        checks["sameFrameSameResource"] = again.publication.texture === a.publication.texture
            && again.resourceGeneration == a.resourceGeneration
        precondition(firstPass.finishEnsuringClear())
        first.arm(); firstCB.commit(); firstCB.waitUntilCompleted()
        checks["firstCompleted"] = firstCB.status == .completed && firstCB.error == nil
        let firstBase = readMip(a.publication.texture, 0), firstLast = readMip(a.publication.texture, 2)
        checks["firstPrefixNotRecaptured"] = firstBase == [2, 0, 0, 0.25]
        checks["gpuGeneratedAverage"] = firstLast == [1, 2, 0, 0.5]

        let (second, secondPass, secondCB) = makeFrame(2)
        let b = second.resolve(secondCB)!
        checks["completionAllowsStorageReuse"] = b.publication.texture === a.publication.texture
        checks["newFramePublication"] = b.publication.contentGeneration == 2
        pool.reset()
        checks["resetRetainsInFlightMipAndScratch"] = pool.residentByteCost == 152
        precondition(secondPass.finishEnsuringClear())
        second.arm(); secondCB.commit(); secondCB.waitUntilCompleted()
        checks["secondCompleted"] = secondCB.status == .completed && secondCB.error == nil
        checks["completionReleasesResetResidency"] = pool.residentByteCost == 0
        let nextLast = readMip(b.publication.texture, 2)
        checks["nextFrameFreshPrefix"] = nextLast == [0, 0, 3, 1]

        let (cancelled, cancelPass, cancelCB) = makeFrame(3)
        _ = cancelled.resolve(cancelCB)!
        precondition(cancelPass.finishEnsuringClear())
        pool.reset()
        checks["unsubmittedCommandsRemainPinned"] = pool.residentByteCost == 152
        cancelled.cancel(); cancelled.cancel()
        checks["cancelReleasesExactlyOnce"] = pool.residentByteCost == 0 && cancelCB.status == .notEnqueued

        let (failed, failurePass, failureCB) = makeFrame(4)
        MWXArmBlitFault(failureCB, 1)
        let missing = failed.resolve(failureCB)
        MWXArmBlitFault(failureCB, 0)
        checks["failedAttemptNotRetriedInFrame"] = missing == nil && failed.resolve(failureCB) == nil
        precondition(failurePass.finishEnsuringClear())
        pool.reset(); failed.cancel()
        checks["failedAttemptCancelReleases"] = pool.residentByteCost == 0
        let result: [String: Any] = ["checks": checks, "firstBase": firstBase,
            "firstLastMip": firstLast, "nextLastMip": nextLast,
            "generatedMipLevels": a.publication.texture.mipmapLevelCount]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


class SceneReflectionEnvironmentProducerTests(unittest.TestCase):
    def test_actual_prefix_copy_generates_mips_and_obeys_submission_lifetime(self):
        result = _compile_and_run("ReflectionProducer.swift", source=REFLECTION_PRODUCER)
        for name, passed in result["checks"].items():
            with self.subTest(name=name):
                self.assertTrue(passed, name)
        self.assertEqual(result["firstBase"], [2, 0, 0, .25])
        self.assertEqual(result["firstLastMip"], [1, 2, 0, .5])
        self.assertEqual(result["nextLastMip"], [0, 0, 3, 1])


if __name__ == "__main__":
    unittest.main()

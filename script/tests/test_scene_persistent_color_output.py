#!/usr/bin/env python3
"""RF07 terminal-output and RF04 completed-raw environment product-owner checks.

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
enum SceneUtilityLayerRuntimePlanner {
    struct Execution {
        let memberRootsByLayerID: [Int: Int]
        let membersByRootID: [Int: [Int]]
        let orderedRootIDs: [Int]
        let copyBackgroundRootIDs: Set<Int>
    }
}
final class SceneCompositionGroupFrameRuntime {
    init(parentPass: SceneMainPassEncoder, commandBuffer: MTLCommandBuffer,
         offscreenTexturePool: SceneOffscreenTexturePool,
         memberRootsByLayerID: [Int: Int], membersByRootID: [Int: [Int]], viewportSize: CGSize,
         copyBackgroundRootIDs: Set<Int> = []) {
        fatalError("terminal fixture must not prepare composition groups")
    }
    func reserveSources(orderedRootIDs: [Int], visibleLayerIDs: Set<Int>) {
        fatalError("terminal fixture must not reserve composition groups")
    }
    func closeAllGroupEncoders() {
        fatalError("terminal fixture must not close composition groups")
    }
    func terminalScratch(matching target: MTLTexture, on commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        fatalError("terminal fixture must not borrow composition groups")
    }
}
struct SceneMetalRenderer {
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
        # Display saturation must not alter the retained HDR source.
        self.assertEqual(len(self.result["accumulatingFrames"]), 8)
        for frame in self.result["accumulatingFrames"]:
            self.assertTrue(frame["gpuCompleted"])
            self.assertAlmostEqual(frame["rgb"][0], 1, delta=1 / 1024)
            self.assertAlmostEqual(frame["rgb"][1], 0.25, delta=1 / 1024)
            self.assertAlmostEqual(frame["rgb"][2], 0.5, delta=1 / 1024)
            self.assertEqual(frame["alpha"], 1)

    def test_real_target_and_submission_owner_lifecycle(self):
        for name, passed in self.result["ownerChecks"].items():
            with self.subTest(name=name):
                self.assertTrue(passed, name)

    def test_half_alpha_authored_draw_accumulates_only_in_raw(self):
        expected = [[1.5, .625, .25, 1, 1, .625, .25, 1],
                    [.75, .8125, .125, 1, .75, .8125, .125, 1]]
        for actual, golden in zip(self.result["alphaFrames"], expected, strict=True):
            for value, target in zip(actual, golden, strict=True):
                self.assertAlmostEqual(value, target, delta=1/1024)

    def test_existing_clear_true_and_non_hdr_routes_are_unchanged(self):
        self.assertTrue(self.result["clearedHDR"]["gpuCompleted"])
        self.assertAlmostEqual(self.result["clearedHDR"]["rgb"][0], 1, delta=1 / 1024)
        self.assertEqual(self.result["nonHDR"]["rgb"], [3, 0.25, 0.5])
        self.assertEqual(self.result["nonHDR"]["alpha"], 1)


REFLECTION_PRODUCER = r'''
import Foundation
import Metal

@main enum ReflectionCompletedSceneProbe {
    typealias Coordinator = SceneResolvedMaterialSubmissionCoordinator
    struct Frame {
        let reflection: SceneMetalRenderer.ReflectionFrame
        let pass: SceneMainPassEncoder
        let commandBuffer: MTLCommandBuffer
        let reservation: Coordinator.SceneColorReservation
        let main: MTLTexture
        let dynamic: SceneDynamicSnapshot
    }

    static func main() throws {
        let device = MTLCreateSystemDefaultDevice()!, queue = device.makeCommandQueue()!
        let pool = SceneOffscreenTexturePool(device: device, pixelFormat: .rgba16Float,
            maxDimension: 16, residentByteBudget: 4096)
        let owner = Coordinator(device: device, capabilities: .init(admissionCandidates: [],
            materialCatalog: .init(entries: [:], resourceDemandIssues: [])),
            capturesExecutionObservations: false, logSink: { _ in })
        let renderer = SceneMetalRenderer(renderDescriptor: .init(hdrEnabled: false,
            camera: .init(clearColor: [0, 0, 0], bloom: .init(enabled: false, strength: 0,
                threshold: 1, tint: SIMD3(1, 1, 1)))),
            imageCompositor: .init(resolvedMaterialRuntime: owner),
            bloomPostProcess: nil, displayMappingPostProcess: nil)
        func texture(_ width: Int = 4, _ height: Int = 2,
                     color: [Float16]? = nil) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float,
                width: width, height: height, mipmapped: false)
            d.storageMode = .shared; d.usage = [.shaderRead, .renderTarget]
            let result = device.makeSceneTexture(descriptor: d)!
            if let color {
                let values = Array(repeating: color, count: width * height).flatMap { $0 }
                values.withUnsafeBytes { result.replace(region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 8) }
            }
            return result
        }
        func prepare(_ index: UInt64, _ epoch: UInt64, main: MTLTexture) -> Frame {
            let dynamic = SceneDynamicSnapshotResolver().resolve(
                frameIndex: index, generation: epoch, definitions: []).snapshot
            owner.beginFrame(textureSnapshot: .init(frameEpoch: epoch, frameIndex: index, entries: [:]),
                dynamicSnapshot: dynamic, frameInputs: .init(frameIndex: index,
                    screenSize: CGSize(width: 4, height: 2), sceneTime: Float(index),
                    dayTime: 0, frameTime: 1 / 60, pointerCurrentNDC: .zero, pointerPreviousNDC: .zero))
            let cb = queue.makeCommandBuffer()!
            // Protect actual mandatory capacity before optional history in
            // the production pool's existing pin and residency domain.
            let targets = pool.reserveCompositionTargets(dimensions: [(4, 2)], commandBuffer: cb)!
            let reservation = owner.reserveSceneColor(pool: pool, width: 4, height: 2,
                frameIndex: index, commandBuffer: cb, intent: .snapshot)!
            let pass = SceneMainPassEncoder(commandBuffer: cb, target: main,
                clearColor: MTLClearColorMake(0, 0, 0, 0), clearEnabled: false)
            let reflection = SceneMetalRenderer.ReflectionFrame(pool: pool, mainPass: pass,
                groupRuntime: nil, commandBuffer: cb, frameEpoch: epoch)
            reflection.admit(targets, sceneColor: reservation)
            return Frame(reflection: reflection, pass: pass, commandBuffer: cb,
                reservation: reservation, main: main, dynamic: dynamic)
        }
        func capture(_ value: Frame, failingBlit: Bool = false) -> SceneMetalRenderer.FrameOutcome? {
            // Only the actual main owner determines whether its raw source
            // has finished. The carrier does not assert fake drawing success.
            value.reflection.mainSourceCompleted = value.pass.finishEnsuringClear()
            if failingBlit { MWXArmBlitFault(value.commandBuffer, 1) }
            let outcome = renderer.encodeReflectionSnapshot(value.reflection,
                source: value.main, commandBuffer: value.commandBuffer)
            if failingBlit { MWXArmBlitFault(value.commandBuffer, 0) }
            return outcome
        }
        func seal(_ value: Frame) -> Bool {
            renderer.encodeTerminalColor(sceneColor: nil, target: value.main,
                offscreenTexturePool: pool, dynamicValues: value.dynamic,
                commandBuffer: value.commandBuffer) == nil
        }
        func complete(_ value: Frame, status: SceneGraphExecutionGPUCompletionStatus = .completed,
                      alreadyArmed: Bool = false) -> Bool {
            let id = ObjectIdentifier(value.commandBuffer)
            let observation = owner.commandBufferRecords[id]!.observationID
            if !alreadyArmed { value.reflection.arm() }
            value.commandBuffer.commit(); value.commandBuffer.waitUntilCompleted()
            let succeeded = value.commandBuffer.status == .completed && value.commandBuffer.error == nil
            precondition(succeeded)
            // Real commands complete first. The explicit failed case injects
            // only the existing completion seam, not a hardware device fault.
            owner.completeCommandBuffer(identity: id, observationID: observation, status: status)
            return succeeded
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
        // Self-authored measurement consumers read the product mip at distinct
        // slots and LODs. They do not open B's authored Program sampler route.
        let consumerLibrary = try device.makeLibrary(source: """
            #include <metal_stdlib>
            using namespace metal;
            kernel void sampleHistory(texture2d<float> nearColor [[texture(1)]],
                                      texture2d<float> farColor [[texture(7)]],
                                      device float4* result [[buffer(0)]]) {
                constexpr sampler s(coord::normalized, address::clamp_to_edge,
                                    filter::linear, mip_filter::linear);
                result[0] = nearColor.sample(s, float2(0.125, 0.5), level(0));
                result[1] = farColor.sample(s, float2(0.5, 0.5), level(2));
            }
            """, options: nil)
        let consumers = try device.makeComputePipelineState(
            function: consumerLibrary.makeFunction(name: "sampleHistory")!)
        func sample(_ resource: SceneFrameTextureResource, on cb: MTLCommandBuffer) -> MTLBuffer {
            let result = device.makeBuffer(length: 32, options: .storageModeShared)!
            let encoder = cb.makeComputeCommandEncoder()!
            encoder.setComputePipelineState(consumers)
            encoder.setTexture(resource.publication.texture, index: 1)
            encoder.setTexture(resource.publication.texture, index: 7)
            encoder.setBuffer(result, offset: 0, index: 0)
            encoder.dispatchThreads(MTLSizeMake(1, 1, 1), threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
            encoder.endEncoding()
            return result
        }
        func sampled(_ buffer: MTLBuffer) -> [Float] {
            Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: Float.self, capacity: 8), count: 8))
        }
        var checks: [String: Bool] = [:]
        let patternedMain = texture()
        var pixels: [Float16] = []
        for _ in 0..<2 { for x in 0..<4 {
            pixels += x < 2 ? [2, 0, 0, 0.25] : [0, 4, 0, 0.75]
        } }
        pixels.withUnsafeBytes { patternedMain.replace(region: MTLRegionMake2D(0, 0, 4, 2),
            mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 32) }
        let first = prepare(1, 101, main: patternedMain)
        checks["bootstrapHasNoReadableHistory"] = first.reservation.previous == nil
            && first.reservation.previousReceipt == nil && owner.completedSceneColor == nil
            && first.reflection.resolve(first.commandBuffer) == nil
            && first.reflection.resolve(first.commandBuffer) == nil
        let firstReceipt = first.reservation.producerReceipt
        checks["receiptComesFromRealSubmission"] = firstReceipt.frameIndex == 1
            && firstReceipt.frameEpoch == 101 && firstReceipt.executionEpoch == owner.executionEpoch
            && firstReceipt.commandBufferObservationID == owner.commandBufferRecords[ObjectIdentifier(first.commandBuffer)]!.sourceObservationID
            && firstReceipt.allocationGeneration == first.reservation.lease.targets.identity.generation
            && firstReceipt.resetEpoch == pool.sceneColorResetEpoch
        checks["terminalCapturesRaw"] = capture(first) == nil
            && first.reflection.mainSourceCompleted && owner.preparedSceneColor?.snapshotCopied == true
            && owner.preparedSceneColor?.displayMapped == nil
        checks["pendingCannotPublishHistory"] = seal(first) && owner.completedSceneColor == nil
            && owner.pendingSubmissions.count == 1 && owner.shouldDeferFrame
        checks["firstGPUCompleted"] = complete(first)
        checks["completedSnapshotStoresOnlyMetadata"] = owner.completedSceneColor?.producerReceipt == firstReceipt
            && owner.completedSceneColor?.persistenceReservation == nil
        checks["armClearsFrameHistory"] = first.reflection.snapshot == nil
            && !first.reflection.scratchReady && first.reflection.resolve(first.commandBuffer) == nil

        // Same simulation frame redraws into the other member with a distinct
        // actual submission receipt; snapshot is not a paused raw export.
        let second = prepare(1, 102, main: texture(color: [0, 0, 7, 1]))
        checks["completedRawIsFrozenBeforeCurrentDraw"] = second.reservation.previous === first.reservation.raw
            && second.reservation.previousReceipt == firstReceipt
            && second.reservation.member != first.reservation.member && second.reservation.requiresDraw
        let a = second.reflection.resolve(second.commandBuffer)!
        checks["fullRealMipChain"] = a.publication.texture.mipmapLevelCount == 3
        checks["typedPublicationPreservesProducer"] = a.publication.isComplete
            && a.publication.requestIdentity == .sceneEnvironment && a.publication.contentGeneration == 102
            && a.publication.candidate.identity == .provider(.sceneEnvironment(frameEpoch: 102,
                allocationGeneration: a.resourceGeneration, source: firstReceipt))
            && a.resourceGeneration == pool.allocationCache.allocation(for: .environment(width: 4, height: 2))?.generation
            && a.publication.texture.width == 4 && a.publication.texture.height == 2
            && firstReceipt.frameEpoch != a.publication.contentGeneration
        let beforeSuffix = sample(a, on: second.commandBuffer)
        second.pass.encodeOffscreen { cb in
            let clear = MTLRenderPassDescriptor()
            clear.colorAttachments[0].texture = second.main
            clear.colorAttachments[0].loadAction = .clear
            clear.colorAttachments[0].storeAction = .store
            clear.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 3, 1)
            cb.makeRenderCommandEncoder(descriptor: clear)!.endEncoding()
        }
        let again = second.reflection.resolve(second.commandBuffer)!
        checks["sameCommandBufferConsumersShareAtom"] = a.publication.isSameAtom(as: again.publication)
            && a.publication.texture === again.publication.texture && a.resourceGeneration == again.resourceGeneration
        checks["foreignCommandBufferCannotRead"] = second.reflection.resolve(queue.makeCommandBuffer()!) == nil
        let afterSuffix = sample(again, on: second.commandBuffer)
        let secondObservation = owner.commandBufferRecords[ObjectIdentifier(second.commandBuffer)]!.sourceObservationID
        checks["secondTerminalAndGPUCompleted"] = capture(second) == nil && seal(second) && complete(second)
        let firstBase = readMip(a.publication.texture, 0), firstLast = readMip(a.publication.texture, 2)
        let secondReceipt = second.reservation.producerReceipt
        checks["currentMainDoesNotChangeHistoricalMips"] = firstBase == [2, 0, 0, 0.25]
            && firstLast == [1, 2, 0, 0.5] && sampled(beforeSuffix) == sampled(afterSuffix)
        checks["sameFrameRedrawHasDistinctProductionReceipt"] = secondReceipt.frameIndex == firstReceipt.frameIndex
            && secondReceipt.commandBufferObservationID != firstReceipt.commandBufferObservationID
            && secondReceipt.commandBufferObservationID == secondObservation
            && secondReceipt.allocationGeneration == second.reservation.lease.targets.identity.generation
            && secondReceipt.frameEpoch == 102 && owner.completedSceneColor?.producerReceipt == secondReceipt
        checks["terminalIncludesLateLayerInNextRaw"] = readMip(second.reservation.raw, 0) == [0, 0, 3, 1]

        let third = prepare(2, 103, main: texture(color: [7, 0, 0, 1]))
        let blue = third.reflection.resolve(third.commandBuffer)!
        let nextSample = sample(blue, on: third.commandBuffer)
        checks["completionAllowsMipStorageReuse"] = blue.publication.texture === a.publication.texture
            && blue.publication.contentGeneration == 103
            && blue.publication.candidate.identity == .provider(.sceneEnvironment(frameEpoch: 103,
                allocationGeneration: blue.resourceGeneration, source: secondReceipt))
        third.pass.encodeOffscreen { cb in
            precondition(renderer.copySceneColor(second.reservation.raw, to: third.main, commandBuffer: cb))
        }
        checks["nextTerminalAndGPUCompleted"] = capture(third) == nil && seal(third) && complete(third)
        let nextLast = readMip(blue.publication.texture, 2)
        checks["nextReadsCompletedLateLayer"] = nextLast == [0, 0, 3, 1]
        let latestReceipt = third.reservation.producerReceipt

        let abandoned = prepare(3, 104, main: texture(color: [9, 0, 0, 1]))
        _ = abandoned.reflection.resolve(abandoned.commandBuffer)!
        checks["cancelCandidateWasReallySealed"] = capture(abandoned) == nil && seal(abandoned)
            && owner.pendingSubmissions.count == 1
        abandoned.reflection.cancel(); owner.cancelUnsubmittedFrame(on: abandoned.commandBuffer)
        abandoned.reflection.cancel(); owner.cancelUnsubmittedFrame(on: abandoned.commandBuffer)
        checks["cancelKeepsCompletedAndClearsFrameHistory"] = owner.completedSceneColor?.producerReceipt == latestReceipt
            && owner.pendingSubmissions.isEmpty && !owner.shouldDeferFrame
            && abandoned.reflection.snapshot == nil && !abandoned.reflection.scratchReady
            && abandoned.reflection.resolve(abandoned.commandBuffer) == nil
            && abandoned.commandBuffer.status == .notEnqueued

        let failedMip = prepare(3, 105, main: texture(color: [8, 0, 0, 1]))
        MWXArmBlitFault(failedMip.commandBuffer, 1)
        let missing = failedMip.reflection.resolve(failedMip.commandBuffer)
        MWXArmBlitFault(failedMip.commandBuffer, 0)
        checks["failedMipAttemptIsNotRetried"] = missing == nil
            && failedMip.reflection.resolve(failedMip.commandBuffer) == nil
        checks["failedMipStillAllowsTerminalCapture"] = capture(failedMip) == nil && seal(failedMip)
        checks["failedGPUSeamUsesRealCompletedCommands"] = complete(failedMip, status: .failed)
        checks["failedCompletionKeepsPriorRawAndReceipt"] = owner.completedSceneColor?.producerReceipt == latestReceipt
            && readMip(third.reservation.raw, 0) == [0, 0, 3, 1]

        let failedCapture = prepare(3, 106, main: texture(color: [6, 0, 0, 1]))
        _ = failedCapture.reflection.resolve(failedCapture.commandBuffer)!
        checks["failedCaptureDetachesOnlySnapshot"] = capture(failedCapture, failingBlit: true) == nil
            && owner.preparedSceneColor?.snapshotPublicationDetached == true
            && owner.preparedSceneColor?.snapshotCopied == false
        checks["detachedCaptureHasHealthyTerminal"] = seal(failedCapture) && complete(failedCapture)
        checks["detachedCaptureCannotPromote"] = owner.completedSceneColor?.producerReceipt == latestReceipt
            && readMip(third.reservation.raw, 0) == [0, 0, 3, 1]

        let reset = prepare(4, 107, main: texture(color: [0, 5, 0, 1]))
        _ = reset.reflection.resolve(reset.commandBuffer)!
        checks["resetCandidateWasReallySealed"] = capture(reset) == nil && seal(reset)
        reset.reflection.arm()
        owner.invalidate(reason: .allocationReprepare); pool.reset()
        // 2 raw x 4x2x8 + mandatory 4x2x8 + mip (8+2+1)x8.
        checks["resetRetainsAllInFlightPins"] = pool.residentByteCost == 280
            && owner.completedSceneColor == nil
        checks["resetBufferReallyCompletes"] = complete(reset, alreadyArmed: true)
        checks["resetCompletionCannotPromoteAndReleasesPins"] = owner.completedSceneColor == nil
            && pool.residentByteCost == 0 && owner.pendingSubmissions.isEmpty

        let cancelledReset = prepare(5, 108, main: texture(color: [1, 0, 0, 1]))
        checks["newResetEpochHasNoPrior"] = cancelledReset.reservation.previous == nil
            && cancelledReset.reservation.previousReceipt == nil
            && cancelledReset.reservation.producerReceipt.resetEpoch != latestReceipt.resetEpoch
        checks["cancelResetCandidateWasReallySealed"] = capture(cancelledReset) == nil && seal(cancelledReset)
        pool.reset()
        checks["unsubmittedCommandsRemainPinned"] = pool.residentByteCost == 192
        cancelledReset.reflection.cancel(); owner.cancelUnsubmittedFrame(on: cancelledReset.commandBuffer)
        cancelledReset.reflection.cancel(); owner.cancelUnsubmittedFrame(on: cancelledReset.commandBuffer)
        checks["cancelResetReleasesExactlyOnce"] = pool.residentByteCost == 0
            && cancelledReset.commandBuffer.status == .notEnqueued && owner.completedSceneColor == nil
        let result: [String: Any] = ["checks": checks, "firstBase": firstBase,
            "firstLastMip": firstLast, "nextLastMip": nextLast,
            "firstConsumerSlots": sampled(beforeSuffix), "afterSuffixConsumerSlots": sampled(afterSuffix),
            "nextConsumerSlots": sampled(nextSample),
            "generatedMipLevels": a.publication.texture.mipmapLevelCount]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
'''


class SceneReflectionEnvironmentProducerTests(unittest.TestCase):
    def test_completed_raw_history_generates_shared_mips_and_obeys_submission_lifetime(self):
        result = _compile_and_run("ReflectionProducer.swift", source=REFLECTION_PRODUCER)
        for name, passed in result["checks"].items():
            with self.subTest(name=name):
                self.assertTrue(passed, name)
        self.assertEqual(result["firstBase"], [2, 0, 0, .25])
        self.assertEqual(result["firstLastMip"], [1, 2, 0, .5])
        self.assertEqual(result["nextLastMip"], [0, 0, 3, 1])
        self.assertEqual(result["firstConsumerSlots"], [2, 0, 0, .25, 1, 2, 0, .5])
        self.assertEqual(result["afterSuffixConsumerSlots"], result["firstConsumerSlots"])
        self.assertEqual(result["nextConsumerSlots"], [0, 0, 3, 1] * 2)


if __name__ == "__main__":
    unittest.main()

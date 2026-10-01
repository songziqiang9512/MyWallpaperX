#!/usr/bin/env python3
"""Run the real image uploader with process-local Metal failure injection."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift"
RESAMPLE_SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader+Resample.swift"
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
LOADER_SOURCES = [
    SCENE / "Format/SceneTexContainer.swift",
    SCENE / "Format/SceneTexDataReader.swift",
    SCENE / "Format/SceneBCTextureDecoder.swift",
    SCENE / "Resources/Textures/SceneTextureMipUploader.swift",
    SCENE / "Resources/Textures/SceneCompressedTextureUploader.swift",
    SCENE / "Resources/Textures/SceneTextureLoader.swift",
]

HEADER = r'''
#import <Metal/Metal.h>
void MWXSetUploadFault(id<MTLDevice> device, int fault);
'''

# Only the test process replaces Objective-C methods. GPU work remains real;
# fault 4 changes the reported terminal status after actual GPU completion.
FAULTS = r'''
#import <Metal/Metal.h>
#import <objc/runtime.h>

static int faultMode;
static IMP originalQueue, originalBuffer, originalEncoder, originalStatus, originalTexture;

static void replaceMethod(id object, SEL selector, IMP replacement, IMP *original) {
    if (*original) return;
    Class cls = object_getClass(object);
    Method method = class_getInstanceMethod(cls, selector);
    *original = method_getImplementation(method);
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
}

static NSUInteger bufferStatus(id object, SEL selector) {
    NSUInteger status = ((NSUInteger (*)(id, SEL))originalStatus)(object, selector);
    return faultMode == 4 && status == MTLCommandBufferStatusCompleted
        ? MTLCommandBufferStatusError : status;
}

static id blitEncoder(id object, SEL selector) {
    if (faultMode == 3) return nil;
    return ((id (*)(id, SEL))originalEncoder)(object, selector);
}

static id commandBuffer(id object, SEL selector) {
    if (faultMode == 2) return nil;
    id buffer = ((id (*)(id, SEL))originalBuffer)(object, selector);
    if (buffer) {
        replaceMethod(buffer, @selector(blitCommandEncoder), (IMP)blitEncoder, &originalEncoder);
        replaceMethod(buffer, @selector(status), (IMP)bufferStatus, &originalStatus);
    }
    return buffer;
}

static id commandQueue(id object, SEL selector) {
    if (faultMode == 1) return nil;
    id queue = ((id (*)(id, SEL))originalQueue)(object, selector);
    if (queue) {
        replaceMethod(queue, @selector(commandBuffer), (IMP)commandBuffer, &originalBuffer);
    }
    return queue;
}

static id texture(id object, SEL selector, id descriptor) {
    if (faultMode == 5) return nil;
    return ((id (*)(id, SEL, id))originalTexture)(object, selector, descriptor);
}

void MWXSetUploadFault(id<MTLDevice> device, int fault) {
    faultMode = fault;
    replaceMethod(device, @selector(newCommandQueue), (IMP)commandQueue, &originalQueue);
    replaceMethod(device, @selector(newTextureWithDescriptor:), (IMP)texture, &originalTexture);
}
'''

HARNESS = r'''
import CoreGraphics
import Foundation
import ImageIO
import Metal

@main enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }
        let image = makeImage(size: 8)
        let encoded = NSMutableData()
        let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-recovery-\(UUID().uuidString).png")
        try (encoded as Data).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let texURL = url.deletingPathExtension().appendingPathExtension("tex")
        var tex = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { tex.append(contentsOf: $0) }
        }
        for value: UInt32 in [0, 2, 8, 8, 8, 8, 0] { append(value) }
        tex.append(Data("TEXB0001\0".utf8))
        for value: UInt32 in [1, 1, 8, 8, 256] { append(value) }
        tex.append(Data(repeating: 255, count: 256))
        try tex.write(to: texURL)
        defer { try? FileManager.default.removeItem(at: texURL) }
        var results: [String: Any] = [:]
        for fault in 0...4 {
            MWXSetUploadFault(device, Int32(fault))
            let loader = SceneTextureLoader()
            results["loaderFailure\(fault)"] = describe(loader.load(from: url, device: device))
            MWXSetUploadFault(device, 0)
            let recovered = loader.load(from: url, device: device)
            results["loaderRecovery\(fault)"] = describe(recovered)
            let cached = loader.load(from: url, device: device)
            if case let .loaded(first) = recovered, case let .loaded(second) = cached {
                results["loaderReusesTexture\(fault)"] = first === second
            }
            results["loaderDecodeAttempts\(fault)"] = loader.directImageDecodeAttemptCount
            MWXSetUploadFault(device, Int32(fault))
            let queue = SceneTextureUploadCommandQueue()
            let color = SceneImageTextureUploader.upload(
                image: image, purpose: .premultipliedColor, maxDimension: 8,
                uploadCommandQueue: queue, device: device
            )
            results["color\(fault)"] = describe(color)
            let preserved = SceneImageTextureUploader.uploadEncodedPreservedChannels(
                encoded as Data, uploadCommandQueue: queue, device: device
            )
            switch preserved {
            case let .success(texture): results["preserved\(fault)"] = describe(texture)
            case let .failure(error): results["preserved\(fault)"] = String(describing: error)
            }
            results["queueAttempts\(fault)"] = queue.creationAttemptCount

            MWXSetUploadFault(device, 0)
            results["sameOwnerRecovery\(fault)"] = describe(SceneImageTextureUploader.upload(
                image: image, purpose: .premultipliedColor, maxDimension: 8,
                uploadCommandQueue: queue, device: device
            ))
            let recoveredPreserved = SceneImageTextureUploader.uploadEncodedPreservedChannels(
                encoded as Data, uploadCommandQueue: queue, device: device
            )
            if case let .success(texture) = recoveredPreserved {
                results["sameOwnerPreservedRecovery\(fault)"] = describe(texture)
            }
            results["recoveredQueueAttempts\(fault)"] = queue.creationAttemptCount
            MWXSetUploadFault(device, Int32(fault))

            let baseQueue = SceneTextureUploadCommandQueue()
            results["base\(fault)"] = describe(SceneImageTextureUploader.upload(
                image: image, purpose: .premultipliedColor, maxDimension: 8,
                mipmapGeneration: .baseLevelOnly, uploadCommandQueue: baseQueue, device: device
            ))
            results["one\(fault)"] = describe(SceneImageTextureUploader.upload(
                image: makeImage(size: 1), purpose: .premultipliedColor, maxDimension: 1,
                uploadCommandQueue: baseQueue, device: device
            ))
            results["baseQueueAttempts\(fault)"] = baseQueue.creationAttemptCount
        }
        for source in [url, texURL] {
            let key = source.pathExtension
            let loader = SceneTextureLoader()
            MWXSetUploadFault(device, 5)
            results["allocationFailure-\(key)"] = describe(loader.load(from: source, device: device))
            MWXSetUploadFault(device, 0)
            results["allocationRecovery-\(key)"] = describe(loader.load(from: source, device: device))
            // A successful cached texture survives a subsequent allocation
            // fault because reloading it must not allocate another texture.
            MWXSetUploadFault(device, 5)
            results["cachedDuringFailure-\(key)"] = describe(loader.load(from: source, device: device))
        }
        MWXSetUploadFault(device, 0)
        results["recovery"] = describe(SceneImageTextureUploader.upload(
            image: image, purpose: .premultipliedColor, maxDimension: 8, device: device
        ))
        // AS2 experiment 1: a load batch defers every mipmap generation to
        // one command buffer flushed once at batch end.
        let batchQueue = SceneTextureUploadCommandQueue()
        batchQueue.beginMipmapBatch()
        var batchTextures: [MTLTexture] = []
        for _ in 0..<3 {
            if case let .loaded(texture) = SceneImageTextureUploader.upload(
                image: image, purpose: .premultipliedColor, maxDimension: 8,
                uploadCommandQueue: batchQueue, device: device
            ) {
                batchTextures.append(texture)
            }
        }
        results["batchDeferCount"] = batchQueue.mipmapDeferCount
        let flushed = batchQueue.flushMipmapBatch()
        results["batchFlushSucceeded"] = flushed.succeeded
        results["batchFlushCount"] = batchQueue.mipmapBatchFlushCount
        results["batchTextureCount"] = batchTextures.count
        results["batchMipLevels"] = batchTextures.map { $0.mipmapLevelCount }
        var level1NonZero = true
        for texture in batchTextures {
            let width = max(texture.width >> 1, 1)
            let height = max(texture.height >> 1, 1)
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(
                &pixels, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 1
            )
            if pixels.allSatisfy({ $0 == 0 }) { level1NonZero = false }
        }
        results["batchLevel1Generated"] = level1NonZero
        // Uncommitted-command-buffer lane (BC premultiply path probe):
        // enqueue three fully-encoded buffers, flush once, all completed.
        batchQueue.beginMipmapBatch()
        var probeBuffers: [MTLCommandBuffer] = []
        var probeDestination: MTLTexture?
        if case let .loaded(destination) = SceneImageTextureUploader.upload(
            image: makeImage(size: 2),
            purpose: .premultipliedColor,
            maxDimension: 2,
            mipmapGeneration: .baseLevelOnly,
            uploadCommandQueue: batchQueue,
            device: device
        ) {
            probeDestination = destination
        }
        if let probeDestination,
           let probeQueue = batchQueue.commandQueue(for: device) {
            for index in 0..<3 {
                guard let cb = probeQueue.makeCommandBuffer() else { continue }
                cb.label = "uncommitted-probe-\(index)"
                if batchQueue.enqueueUncommittedIfBatching(
                    cb, conversionTexture: probeDestination
                ) {
                    probeBuffers.append(cb)
                }
            }
        }
        results["uncommittedEnqueueCount"] = batchQueue.uncommittedEnqueueCount
        results["uncommittedFlushedOK"] =
            batchQueue.flushUncommittedCommandBuffers().isEmpty
        results["uncommittedAllCompleted"] = probeBuffers.allSatisfy {
            $0.status == .completed
        }
        // Flush-failure reclamation contract (fault 4: the terminal status
        // reports error after real GPU completion). A failed mipmap flush
        // must return the failed texture identities — not just a count —
        // so the prepare pass can reclaim their entries; the queue then
        // recovers for later loads.
        batchQueue.beginMipmapBatch()
        var faultedTextures: [MTLTexture] = []
        for _ in 0..<2 {
            if case let .loaded(texture) = SceneImageTextureUploader.upload(
                image: image, purpose: .premultipliedColor, maxDimension: 8,
                uploadCommandQueue: batchQueue, device: device
            ) {
                faultedTextures.append(texture)
            }
        }
        MWXSetUploadFault(device, 4)
        let faultedFlush = batchQueue.flushMipmapBatch()
        MWXSetUploadFault(device, 0)
        results["faultedDeferCount"] = batchQueue.mipmapDeferCount
        results["faultedFlushSucceeded"] = faultedFlush.succeeded
        results["faultedFlushCount"] = faultedFlush.failedTextures.count
        results["faultedFlushReportsIdentities"] =
            faultedTextures.count == 2
            && faultedTextures.allSatisfy { texture in
                faultedFlush.failedTextures.contains { $0 === texture }
            }
        results["flushRecovery"] = describe(SceneImageTextureUploader.upload(
            image: image, purpose: .premultipliedColor, maxDimension: 8,
            uploadCommandQueue: batchQueue, device: device
        ))
        // BC-lane failure identity: a failed uncommitted conversion returns
        // its destination texture for reclamation.
        batchQueue.beginMipmapBatch()
        var faultedConversions: [MTLTexture] = []
        if let probeQueue = batchQueue.commandQueue(for: device) {
            for index in 0..<2 {
                guard let cb = probeQueue.makeCommandBuffer(),
                      case let .loaded(destination) = SceneImageTextureUploader.upload(
                            image: makeImage(size: 2),
                            purpose: .premultipliedColor,
                            maxDimension: 2,
                            mipmapGeneration: .baseLevelOnly,
                            uploadCommandQueue: batchQueue,
                            device: device
                        ) else { continue }
                cb.label = "uncommitted-fault-probe-\(index)"
                if batchQueue.enqueueUncommittedIfBatching(
                    cb, conversionTexture: destination
                ) {
                    faultedConversions.append(destination)
                }
            }
        }
        MWXSetUploadFault(device, 4)
        let faultedConversionsFlush = batchQueue
            .flushUncommittedCommandBuffers()
        MWXSetUploadFault(device, 0)
        results["faultedConversionCount"] = faultedConversionsFlush.count
        results["faultedConversionReportsIdentities"] =
            faultedConversions.count == 2
            && faultedConversions.allSatisfy { texture in
                faultedConversionsFlush.contains { $0 === texture }
            }
        // End-to-end reclamation: a texture whose deferred publication
        // fails is evicted from the loader's GPU cache, so the next load
        // re-decodes and retries generation instead of serving the
        // unproven texture.
        let reclamationLoader = SceneTextureLoader(uploadCommandQueue: batchQueue)
        batchQueue.beginMipmapBatch()
        var reclamationBefore: MTLTexture?
        if case let .loaded(before) = reclamationLoader.load(
            from: url, device: device
        ) {
            reclamationBefore = before
        }
        MWXSetUploadFault(device, 4)
        let reclamationFlush = batchQueue.flushMipmapBatch()
        MWXSetUploadFault(device, 0)
        let evictedCount = reclamationLoader.evictTextures(
            containedIn: reclamationFlush.failedTextures
        )
        results["reclamationFlushReported"] =
            reclamationFlush.failedTextures.count
        results["reclamationEvicted"] = evictedCount
        var reclamationAfter: MTLTexture?
        if let before = reclamationBefore,
           case let .loaded(after) = reclamationLoader.load(
               from: url, device: device
           ) {
            reclamationAfter = after
            results["reclamationRetriesWithNewTexture"] = before !== after
            results["reclamationRetryHasMips"] = after.mipmapLevelCount > 1
        }
        // A repeat load after the retry keeps serving the proven texture.
        if let after = reclamationAfter,
           case let .loaded(repeatLoad) = reclamationLoader.load(
               from: url, device: device
           ) {
            results["reclamationRepeatStable"] = repeatLoad === after
        }
        // Decoded-cache eviction: CPU bytes release at the GPU-ready point
        // while the GPU cache keeps serving identical textures; a different
        // source re-decodes from its file after eviction.
        let evictBudget = SceneTextureDecodeCacheBudget(maximumBytes: 1 << 30)
        let evictLoader = SceneTextureLoader(
            uploadCommandQueue: SceneTextureUploadCommandQueue(),
            decodeCacheBudget: evictBudget
        )
        if case let .loaded(evictFirst) = evictLoader.load(from: url, device: device) {
            results["evictAdmittedBefore"] = evictBudget.residentBytes > 0
            evictLoader.evictDecodedCaches()
            results["evictResidentAfter"] = evictBudget.residentBytes == 0
            if case let .loaded(evictSecond) = evictLoader.load(from: url, device: device) {
                results["evictReloadSameTexture"] = evictFirst === evictSecond
                results["evictReloadAdmitted"] = evictBudget.residentBytes == 0
            }
            let secondURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("evict-redecode-\(UUID().uuidString).png")
            try? (encoded as Data).write(to: secondURL)
            defer { try? FileManager.default.removeItem(at: secondURL) }
            if case .loaded = evictLoader.load(from: secondURL, device: device) {
                results["evictSecondDecodeSucceeded"] = true
                results["evictSecondAdmitted"] = evictBudget.residentBytes > 0
            }
            // Parsed-container path: the .tex source re-parses after eviction
            // and its GPU texture keeps its identity across the round trip.
            if case let .loaded(texFirst) = evictLoader.load(from: texURL, device: device) {
                evictLoader.evictDecodedCaches()
                if let reparsed = evictLoader.texContainer(from: texURL),
                   case let .loaded(texSecond) = evictLoader.load(from: texURL, device: device) {
                    results["evictTexReparse"] = reparsed.images.count
                    results["evictTexIdentityStable"] = texFirst === texSecond
                }
                evictLoader.evictDecodedCaches()
                results["evictIdempotent"] = evictBudget.residentBytes == 0
            }
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: results))
    }

    static func makeImage(size: Int) -> CGImage {
        let rgba = Data(repeating: 255, count: size * size * 4)
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: CGDataProvider(data: rgba as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    static func describe(_ outcome: SceneTextureLoadOutcome) -> String {
        switch outcome {
        case let .loaded(texture): return describe(texture)
        case let .decodeFailed(reason): return reason
        case .textureAllocationFailed: return "allocation-failed"
        default: return "unexpected-outcome"
        }
    }

    static func describe(_ texture: MTLTexture) -> String {
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &pixel, bytesPerRow: 4, from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: texture.mipmapLevelCount - 1
        )
        return "loaded:\(texture.mipmapLevelCount):\(pixel)"
    }
}
'''


class SceneImageUploadCompletionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None or shutil.which("clang") is None:
            raise unittest.SkipTest("Swift/Clang are unavailable")
        with tempfile.TemporaryDirectory(prefix="mwx-image-completion-") as folder:
            root = Path(folder)
            header = root / "faults.h"
            implementation = root / "faults.m"
            harness = root / "harness.swift"
            header.write_text(HEADER)
            implementation.write_text(FAULTS)
            harness.write_text(HARNESS)
            source = SOURCE
            resample_source = RESAMPLE_SOURCE
            loader_sources = list(LOADER_SOURCES)
            if baseline := os.environ.get("SCENE_TEXTURE_LOADER_BASE_REF"):
                original = loader_sources[-1]
                replacement = root / original.name
                replacement.write_bytes(subprocess.check_output(
                    ["git", "show", f"{baseline}:{original.relative_to(ROOT)}"], cwd=ROOT
                ))
                loader_sources[-1] = replacement
            if baseline := os.environ.get("SCENE_IMAGE_UPLOADER_BASE_REF"):
                source = root / SOURCE.name
                source.write_bytes(subprocess.check_output(
                    ["git", "show", f"{baseline}:{SOURCE.relative_to(ROOT)}"], cwd=ROOT
                ))
            if os.environ.get("SCENE_IMAGE_UPLOADER_BASE_REF"):
                # 拆分(2026-10-01)后的 Uploader 需要 +Resample 伴生；baseline ref
                # 早于拆分时主文件自包含（不含伴生符号），跳过伴生避免重复定义。
                if b"premultipliedBoxResampledRGBA" not in source.read_bytes():
                    resample_source = None
            for command in (
                ["clang", "-c", str(implementation), "-o", str(root / "faults.o")],
                ["swiftc", "-import-objc-header", str(header), str(source),
                 *([str(resample_source)] if resample_source else []),
                 *map(str, loader_sources), str(harness),
                 str(root / "faults.o"), "-o", str(root / "harness")],
            ):
                run = subprocess.run(command, capture_output=True, text=True, timeout=120)
                if run.returncode:
                    raise AssertionError(run.stderr)
            run = subprocess.run([str(root / "harness")], capture_output=True, text=True, timeout=60)
            if run.returncode:
                raise AssertionError(run.stderr)
            if run.stdout.strip() == "SKIP":
                raise unittest.SkipTest("Metal device unavailable")
            cls.result = json.loads(run.stdout)

    def test_load_batch_defers_mipmaps_to_one_flush(self) -> None:
        output = self.result
        self.assertEqual(output["batchDeferCount"], 3)
        self.assertEqual(output["batchFlushCount"], 1)
        self.assertEqual(output["batchTextureCount"], 3)
        self.assertTrue(output["batchFlushSucceeded"])
        self.assertTrue(all(levels > 1 for levels in output["batchMipLevels"]))
        self.assertTrue(output["batchLevel1Generated"])

    def test_uncommitted_command_buffers_flush_commits_all(self) -> None:
        output = self.result
        self.assertEqual(output["uncommittedEnqueueCount"], 3)
        self.assertTrue(output["uncommittedFlushedOK"])
        self.assertTrue(output["uncommittedAllCompleted"])

    def test_failed_mipmap_flush_reports_texture_identities(self) -> None:
        output = self.result
        self.assertFalse(output["faultedFlushSucceeded"])
        self.assertEqual(output["faultedFlushCount"], 2)
        self.assertTrue(output["faultedFlushReportsIdentities"])
        self.assertTrue(str(output["flushRecovery"]).startswith("loaded:"))

    def test_failed_uncommitted_flush_reports_conversion_identities(self) -> None:
        output = self.result
        self.assertEqual(output["faultedConversionCount"], 2)
        self.assertTrue(output["faultedConversionReportsIdentities"])

    def test_flush_failure_evicts_unproven_texture_and_retries(self) -> None:
        output = self.result
        self.assertEqual(output["reclamationFlushReported"], 1)
        self.assertEqual(output["reclamationEvicted"], 1)
        self.assertTrue(output["reclamationRetriesWithNewTexture"])
        self.assertTrue(output["reclamationRetryHasMips"])
        self.assertTrue(output["reclamationRepeatStable"])

    def test_failed_upload_never_publishes_a_texture(self) -> None:
        reasons = ["command queue unavailable", "command buffer unavailable",
                   "blit encoder unavailable", "GPU completion failed"]
        for fault, reason in enumerate(reasons, start=1):
            with self.subTest(fault=fault):
                self.assertEqual(self.result[f"color{fault}"], f"GPU mipmap generation failed: {reason}")
                self.assertIn("mipmapGenerationFailed", self.result[f"preserved{fault}"])
                self.assertIn(reason, self.result[f"preserved{fault}"])

    def test_base_only_and_single_pixel_do_not_need_gpu_submission(self) -> None:
        self.assertTrue(self.result["evictAdmittedBefore"])
        self.assertTrue(self.result["evictResidentAfter"])
        self.assertTrue(self.result["evictReloadSameTexture"])
        self.assertTrue(self.result["evictReloadAdmitted"])
        self.assertTrue(self.result["evictSecondDecodeSucceeded"])
        self.assertTrue(self.result["evictSecondAdmitted"])
        self.assertGreaterEqual(self.result["evictTexReparse"], 1)
        self.assertTrue(self.result["evictTexIdentityStable"])
        self.assertTrue(self.result["evictIdempotent"])

        for fault in range(5):
            for route in ("base", "one"):
                self.assertEqual(self.result[f"{route}{fault}"], "loaded:1:[255, 255, 255, 255]")
            self.assertEqual(self.result[f"baseQueueAttempts{fault}"], 0)

    def test_queue_remains_shared_for_color_and_preserved_uploads(self) -> None:
        for fault in range(5):
            self.assertEqual(self.result[f"queueAttempts{fault}"], 2 if fault == 1 else 1)

    def test_same_owner_recovers_after_transient_failure(self) -> None:
        for fault in range(5):
            with self.subTest(fault=fault):
                self.assertEqual(self.result[f"sameOwnerRecovery{fault}"],
                                 "loaded:4:[255, 255, 255, 255]")
                self.assertEqual(self.result.get(f"sameOwnerPreservedRecovery{fault}"),
                                 "loaded:4:[255, 255, 255, 255]")
                self.assertEqual(self.result[f"recoveredQueueAttempts{fault}"],
                                 3 if fault == 1 else 1)

    def test_loader_retries_upload_without_redecoding_or_replacing_success(self) -> None:
        for fault in range(5):
            with self.subTest(fault=fault):
                if fault:
                    self.assertIn("GPU mipmap generation failed", self.result[f"loaderFailure{fault}"])
                self.assertEqual(self.result[f"loaderRecovery{fault}"],
                                 "loaded:4:[255, 255, 255, 255]")
                self.assertTrue(self.result.get(f"loaderReusesTexture{fault}"))
                self.assertEqual(self.result[f"loaderDecodeAttempts{fault}"], 1)

    def test_file_load_recovers_from_allocation_failure_and_retains_success(self) -> None:
        for extension, levels in (("png", 4), ("tex", 1)):
            with self.subTest(extension=extension):
                self.assertEqual(self.result[f"allocationFailure-{extension}"], "allocation-failed")
                expected = f"loaded:{levels}:[255, 255, 255, 255]"
                self.assertEqual(self.result[f"allocationRecovery-{extension}"], expected)
                self.assertEqual(self.result[f"cachedDuringFailure-{extension}"], expected)


if __name__ == "__main__":
    unittest.main()

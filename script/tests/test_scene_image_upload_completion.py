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
            for command in (
                ["clang", "-c", str(implementation), "-o", str(root / "faults.o")],
                ["swiftc", "-import-objc-header", str(header), str(source),
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

    def test_full_chain_has_initialized_terminal_mip(self) -> None:
        for route in ("color0", "preserved0", "recovery"):
            self.assertEqual(self.result[route], "loaded:4:[255, 255, 255, 255]")

    def test_failed_upload_never_publishes_a_texture(self) -> None:
        reasons = ["command queue unavailable", "command buffer unavailable",
                   "blit encoder unavailable", "GPU completion failed"]
        for fault, reason in enumerate(reasons, start=1):
            with self.subTest(fault=fault):
                self.assertEqual(self.result[f"color{fault}"], f"GPU mipmap generation failed: {reason}")
                self.assertIn("mipmapGenerationFailed", self.result[f"preserved{fault}"])
                self.assertIn(reason, self.result[f"preserved{fault}"])

    def test_base_only_and_single_pixel_do_not_need_gpu_submission(self) -> None:
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

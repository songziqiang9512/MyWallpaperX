#!/usr/bin/env python3
"""A load batch must not hold more uncommitted conversion buffers than the
device's command queue can allocate.

Metal blocks ``makeCommandBuffer`` once a serial queue holds ~64 uncompleted
command buffers. A prepare pass that enqueues every BC premultiply conversion
without committing therefore blocks inside the load loop, and the batch-end
flush that would release the buffers becomes unreachable. The harness drives
a real ``MTLDevice`` past that boundary inside one ``beginMipmapBatch`` /
flush pass and must finish within the subprocess timeout.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/Textures/SceneImageTextureUploader+Resample.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureMipUploader.swift",
    SCENE_ROOT / "Resources/Textures/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/Textures/SceneTextureLoader.swift",
]

# 70 two-image BC3 conversions exceed the observed 64-buffer uncommitted
# capacity with margin, so the pass only completes when the upload queue
# bounds its uncommitted lane instead of deferring every commit to the
# batch end. Keep in sync with the literal in HARNESS below.
CONVERSION_COUNT = 70

HARNESS = r'''
import CoreGraphics
import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }
        let conversionCount = 70
        let queue = SceneTextureUploadCommandQueue()
        queue.beginMipmapBatch()
        var destinations: [MTLTexture] = []
        var loadedCount = 0
        var interleavedMips: [MTLTexture] = []
        for index in 0..<conversionCount {
            // The mipmap defer lane shares the batch (and its command
            // queue) with the uncommitted conversion lane: the batch end
            // allocates one more buffer for the mipmap flush after the
            // conversion pass, so both lanes must fit the capacity.
            if index % 20 == 7 {
                if case let .loaded(texture) = SceneImageTextureUploader.upload(
                    image: makeImage(size: 8), purpose: .premultipliedColor,
                    maxDimension: 8, uploadCommandQueue: queue, device: device
                ) {
                    interleavedMips.append(texture)
                }
            }
            if case let .loaded(destination) = SceneCompressedTextureUploader.upload(
                container: makeTwoImageBC3Container(),
                pixelFormat: .bc3_rgba,
                purpose: .premultipliedColor,
                uploadCommandQueue: queue,
                device: device
            ) {
                destinations.append(destination)
                loadedCount += 1
            }
        }
        let mipmapFlush = queue.flushMipmapBatch()
        let conversionFailures = queue.flushUncommittedCommandBuffers()
        var result: [String: Any] = [:]
        result["loadedCount"] = loadedCount
        result["interleavedMipCount"] = interleavedMips.count
        result["mipmapFlushSucceeded"] = mipmapFlush.succeeded
        result["conversionFailureCount"] = conversionFailures.count
        result["enqueueCount"] = queue.uncommittedEnqueueCount
        // Every destination must be GPU-published once the pass returns:
        // read real premultiplied pixels back through a blit.
        result["destinationPixels"] = try destinations
            .prefix(3).map { try readFirstPixel(texture: $0, device: device) }
        result["interleavedLevelCounts"] = interleavedMips.map {
            $0.mipmapLevelCount
        }
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: result)
        )
    }

    static func makeTwoImageBC3Container() -> SceneTexContainer {
        // BC3 block: alpha 128, color 0xF800 (red). 4x4 = one block.
        let block = Data([
            128, 128, 0, 0, 0, 0, 0, 0,
            0x00, 0xF8, 0, 0, 0, 0, 0, 0,
        ])
        let mip = SceneTexContainer.Mip(width: 4, height: 4, data: block)
        let frame0 = SceneTexContainer.SpriteFrame(
            imageIndex: 0, duration: 0.035, origin: .zero,
            xAxis: SIMD2(1, 0), yAxis: SIMD2(0, 1)
        )
        let frame1 = SceneTexContainer.SpriteFrame(
            imageIndex: 1, duration: 0.035, origin: .zero,
            xAxis: SIMD2(1, 0), yAxis: SIMD2(0, 1)
        )
        return SceneTexContainer(
            format: 4, flags: 4,
            textureWidth: 4, textureHeight: 4,
            imageWidth: 4, imageHeight: 4,
            containerVersion: .texb0002,
            freeImageFormat: -1, isVideoMp4: false,
            images: [.init(mips: [mip]), .init(mips: [mip])],
            spriteFrames: [frame0, frame1]
        )
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

    static func readFirstPixel(
        texture: MTLTexture, device: MTLDevice
    ) throws -> [UInt8] {
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let buffer = device.makeBuffer(length: 4) else {
            throw HarnessError.noDevice
        }
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(
            from: texture, sourceSlice: 0, sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: 1, height: 1, depth: 1),
            to: buffer, destinationOffset: 0,
            destinationBytesPerRow: 4, destinationBytesPerImage: 4
        )
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { throw HarnessError.gpu }
        let pointer = buffer.contents().bindMemory(to: UInt8.self, capacity: 4)
        return Array(UnsafeBufferPointer(start: pointer, count: 4))
    }

    enum HarnessError: Error { case noDevice, gpu }
}
'''


class SceneBCUploadBatchCapacityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory(prefix="mwx-bc-batch-capacity-")
        root = Path(cls._tmp.name)
        (root / "harness.swift").write_text(HARNESS)
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), "harness.swift", "-o", "harness"],
            capture_output=True,
            text=True,
            timeout=300,
            cwd=str(root),
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")
        # The timeout is the deadlock assertion: an unbounded uncommitted
        # lane blocks inside the load loop on a real Metal queue.
        completed = subprocess.run(
            ["./harness"], capture_output=True, text=True, timeout=90, cwd=str(root)
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        if completed.stdout.strip() == "SKIP":
            raise unittest.SkipTest("Metal device unavailable")
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_over_capacity_batch_completes_with_all_conversions(self) -> None:
        self.assertEqual(self.result["loadedCount"], CONVERSION_COUNT)
        self.assertEqual(self.result["enqueueCount"], CONVERSION_COUNT)

    def test_over_capacity_batch_publishes_gpu_content(self) -> None:
        for pixel in self.result["destinationPixels"]:
            red, green, blue, alpha = pixel
            self.assertLessEqual(abs(red - 128), 1)
            self.assertEqual((green, blue), (0, 0))
            self.assertLessEqual(abs(alpha - 128), 1)

    def test_mixed_mipmap_lane_flushes_clean_after_conversions(self) -> None:
        self.assertEqual(self.result["interleavedMipCount"], 4)
        self.assertTrue(self.result["mipmapFlushSucceeded"])
        self.assertTrue(all(count > 1 for count in self.result["interleavedLevelCounts"]))
        self.assertEqual(self.result["conversionFailureCount"], 0)


if __name__ == "__main__":
    unittest.main()

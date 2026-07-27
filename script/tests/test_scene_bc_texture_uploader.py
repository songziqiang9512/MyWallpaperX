#!/usr/bin/env python3

"""Metal tests for over-budget BC color upload and static sprite fallback."""

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
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
]

HARNESS = r'''
import Foundation
import Metal

enum SceneTextureLoadOutcome {
    case loaded(MTLTexture)
    case decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}

@main
enum Harness {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw HarnessError.noDevice }
        let width = 4096
        let height = 4097
        let block = [UInt8](
            [128, 128, 0, 0, 0, 0, 0, 0]
            + [0x00, 0xF8, 0, 0, 0, 0, 0, 0]
        )
        let blockCount = ((width + 3) / 4) * ((height + 3) / 4)
        var data = Data(count: blockCount * block.count)
        data.withUnsafeMutableBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for index in 0 ..< blockCount {
                for offset in block.indices {
                    bytes[index * block.count + offset] = block[offset]
                }
            }
        }
        let mip = SceneTexContainer.Mip(width: width, height: height, data: data)
        let frame0 = SceneTexContainer.SpriteFrame(
            imageIndex: 0,
            duration: 0.035,
            origin: .zero,
            xAxis: SIMD2(4.0 / Float(width), 0),
            yAxis: SIMD2(0, 4.0 / Float(height))
        )
        let frame1 = SceneTexContainer.SpriteFrame(
            imageIndex: 1,
            duration: 0.035,
            origin: .zero,
            xAxis: frame0.xAxis,
            yAxis: frame0.yAxis
        )
        let container = makeContainer(mip: mip, frames: [frame0, frame1])
        let outcome = SceneCompressedTextureUploader.upload(
            container: container,
            pixelFormat: .bc3_rgba,
            device: device
        )
        var result: [String: Any] = [:]
        if case let .loaded(texture) = outcome {
            result["loaded"] = true
            result["width"] = texture.width
            result["height"] = texture.height
            result["pixelFormat"] = texture.pixelFormat.rawValue
            result["firstPixel"] = try readFirstPixel(texture: texture, device: device)
        } else {
            result["loaded"] = false
        }

        let rotated = SceneTexContainer.SpriteFrame(
            imageIndex: 0,
            duration: 0.035,
            origin: .zero,
            xAxis: SIMD2(0, 4.0 / Float(height)),
            yAxis: SIMD2(4.0 / Float(width), 0)
        )
        let rejected = SceneCompressedTextureUploader.upload(
            container: makeContainer(mip: mip, frames: [rotated, frame1]),
            pixelFormat: .bc3_rgba,
            device: device
        )
        if case let .decodeFailed(message) = rejected {
            result["rotatedFailure"] = message
        }

        let mipmapped = SceneCompressedTextureUploader.upload(
            container: makeMipmappedContainer(),
            pixelFormat: .bc1_rgba,
            device: device
        )
        if case let .loaded(texture) = mipmapped {
            result["mipmapLevelCount"] = texture.mipmapLevelCount
            result["secondMipPixel"] = try readFirstPixel(
                texture: texture,
                level: 1,
                device: device
            )
        }
        let parsed = try SceneTexContainerReader().read(data: makeTwoImageTex())
        result["parsedImageCount"] = parsed.images.count
        result["parsedMipCounts"] = parsed.images.map { $0.mips.count }
        result["parsedFirstBytes"] = parsed.images.map { Int($0.mips[0].data[0]) }
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: result)
        )
    }

    static func makeContainer(
        mip: SceneTexContainer.Mip,
        frames: [SceneTexContainer.SpriteFrame]
    ) -> SceneTexContainer {
        SceneTexContainer(
            format: 4,
            flags: 4,
            textureWidth: mip.width,
            textureHeight: mip.height,
            imageWidth: mip.width,
            imageHeight: mip.height,
            containerVersion: .texb0002,
            freeImageFormat: -1,
            isVideoMp4: false,
            images: [.init(mips: [mip]), .init(mips: [mip])],
            spriteFrames: frames
        )
    }

    static func makeMipmappedContainer() -> SceneTexContainer {
        let redBlock = Data([0x00, 0xF8, 0, 0, 0, 0, 0, 0])
        let greenBlock = Data([0xE0, 0x07, 0, 0, 0, 0, 0, 0])
        return SceneTexContainer(
            format: 7,
            flags: 2,
            textureWidth: 8,
            textureHeight: 8,
            imageWidth: 8,
            imageHeight: 8,
            containerVersion: .texb0002,
            freeImageFormat: -1,
            isVideoMp4: false,
            images: [.init(mips: [
                .init(width: 8, height: 8, data: redBlock + redBlock + redBlock + redBlock),
                .init(width: 4, height: 4, data: greenBlock)
            ])],
            spriteFrames: []
        )
    }

    static func makeTwoImageTex() -> Data {
        var data = Data("TEXV0005\0TEXI0001\0".utf8)
        func append(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(7)
        append(0)
        append(4)
        append(4)
        append(4)
        append(4)
        append(0)
        data.append(Data("TEXB0002\0".utf8))
        append(2)
        for marker: UInt8 in [17, 29] {
            append(1)
            append(4)
            append(4)
            append(0)
            append(0)
            append(8)
            data.append(Data(repeating: marker, count: 8))
        }
        return data
    }

    static func readFirstPixel(
        texture: MTLTexture,
        level: Int = 0,
        device: MTLDevice
    ) throws -> [UInt8] {
        guard let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer(),
              let buffer = device.makeBuffer(length: 4) else { throw HarnessError.noDevice }
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: level,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: 1, height: 1, depth: 1),
            to: buffer,
            destinationOffset: 0,
            destinationBytesPerRow: 4,
            destinationBytesPerImage: 4
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


class SceneBCTextureUploaderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        harness = tmp / "harness.swift"
        harness.write_text(HARNESS)
        binary = tmp / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")
        completed = subprocess.run([str(binary)], capture_output=True, text=True)
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_over_budget_multi_image_bc3_uses_premultiplied_static_first_frame(self) -> None:
        self.assertTrue(self.result["loaded"])
        self.assertEqual((self.result["width"], self.result["height"]), (4, 4))
        red, green, blue, alpha = self.result["firstPixel"]
        self.assertLessEqual(abs(red - 128), 1)
        self.assertEqual((green, blue), (0, 0))
        self.assertLessEqual(abs(alpha - 128), 1)

    def test_rotated_cross_image_first_frame_fails_closed(self) -> None:
        self.assertIn("static first-frame region", self.result["rotatedFailure"])

    def test_single_image_bc_upload_preserves_authored_mip_chain(self) -> None:
        self.assertEqual(self.result["mipmapLevelCount"], 2)
        red, green, blue, alpha = self.result["secondMipPixel"]
        self.assertEqual((red, green, blue, alpha), (0, 255, 0, 255))

    def test_tex_reader_preserves_every_image_payload(self) -> None:
        self.assertEqual(self.result["parsedImageCount"], 2)
        self.assertEqual(self.result["parsedMipCounts"], [1, 1])
        self.assertEqual(self.result["parsedFirstBytes"], [17, 29])


if __name__ == "__main__":
    unittest.main()

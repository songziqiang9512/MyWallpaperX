#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SOURCE_ROOT / "Effects/SceneTintPipeline.swift",
    SOURCE_ROOT / "Effects/SceneGaussianBlurPipeline.swift",
]

HARNESS = r'''
import Foundation
import Metal
import simd

@main
enum Harness {
    static let size = 16

    static func texture(
        device: MTLDevice,
        usage: MTLTextureUsage
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func sourceBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 6...9 {
            for x in 6...9 {
                let offset = (y * size + x) * 4
                bytes[offset] = 16
                bytes[offset + 1] = 32
                bytes[offset + 2] = 96
                bytes[offset + 3] = 128
            }
        }
        return bytes
    }

    static func upload(_ bytes: [UInt8], to texture: MTLTexture) {
        bytes.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: size * 4
            )
        }
    }

    static func read(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return bytes
    }

    static func pixel(_ bytes: [UInt8], x: Int, y: Int) -> [UInt8] {
        let offset = (y * size + x) * 4
        return Array(bytes[offset..<(offset + 4)])
    }

    static func allPixelsArePremultiplied(_ bytes: [UInt8]) -> Bool {
        stride(from: 0, to: bytes.count, by: 4).allSatisfy { offset in
            let alpha = Int(bytes[offset + 3])
            return Int(bytes[offset]) <= alpha + 1
                && Int(bytes[offset + 1]) <= alpha + 1
                && Int(bytes[offset + 2]) <= alpha + 1
        }
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let tint = SceneTintPipeline(device: device),
              let blur = SceneGaussianBlurPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let source = texture(device: device, usage: .shaderRead)
        upload(sourceBytes(), to: source)
        let tinted = texture(device: device, usage: [.shaderRead, .renderTarget])
        let blurred = texture(device: device, usage: [.shaderRead, .renderTarget])
        let command = queue.makeCommandBuffer()!
        precondition(tint.encode(
            source: source,
            target: tinted,
            color: SIMD3(repeating: 1),
            alpha: 1,
            blendMode: 29,
            commandBuffer: command
        ))
        precondition(blur.encode(
            source: tinted,
            target: blurred,
            step: SIMD2(0.02, 0),
            commandBuffer: command
        ))
        command.commit()
        command.waitUntilCompleted()
        precondition(command.status == .completed)
        let tintBytes = read(tinted)
        let blurBytes = read(blurred)
        let result: [String: Any] = [
            "metalUnavailable": false,
            "tintCorner": pixel(tintBytes, x: 0, y: 0),
            "blurCorner": pixel(blurBytes, x: 0, y: 0),
            "tintCenter": pixel(tintBytes, x: 7, y: 7),
            "tintPremultiplied": allPixelsArePremultiplied(tintBytes),
            "blurPremultiplied": allPixelsArePremultiplied(blurBytes),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneTintRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-tint-rendering-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-tint-rendering"
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-module-cache-path",
                str(root / "module-cache"),
                "-framework",
                "Metal",
                "-o",
                str(binary),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        executed = subprocess.run(
            [str(binary)],
            check=False,
            capture_output=True,
            text=True,
        )
        if executed.returncode != 0:
            raise RuntimeError(executed.stderr)
        cls.result = json.loads(executed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_tint_preserves_transparent_pixels_and_premultiplied_output(self) -> None:
        self.assertEqual(self.result["tintCorner"], [0, 0, 0, 0])
        self.assertTrue(self.result["tintPremultiplied"])
        self.assertGreater(self.result["tintCenter"][3], 0)

    def test_following_blur_cannot_spread_hidden_rgb_into_transparency(self) -> None:
        self.assertEqual(self.result["blurCorner"], [0, 0, 0, 0])
        self.assertTrue(self.result["blurPremultiplied"])


if __name__ == "__main__":
    unittest.main()

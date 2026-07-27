#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = [
    SCENE_ROOT / "Effects/SceneBlendModeShaderSource.swift",
    SCENE_ROOT / "Effects/SceneFilmGrainPipeline.swift",
]

HARNESS = r'''
import Foundation
import Metal

struct SceneFilmGrainExecutionPlan {
    let blendMode: Int
    let greyscale: Bool
    let scale: Float
    let strength: Float
    let exponent: Float
}

@main
enum Harness {
    static let size = 2

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat = .bgra8Unorm,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget]
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: size, height: size, mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func upload(_ bytes: [UInt8], to texture: MTLTexture) {
        var value = bytes
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
            withBytes: &value, bytesPerRow: size * 4
        )
    }

    static func read(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(
            &bytes, bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0
        )
        return bytes
    }

    static func render(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneFilmGrainPipeline
    ) -> [UInt8] {
        let source = texture(device: device)
        let noise = texture(device: device, format: .rgba8Unorm, usage: [.shaderRead])
        let target = texture(device: device)
        upload([
            0, 0, 0, 0,
            16, 32, 48, 64,
            32, 64, 96, 128,
            64, 128, 255, 255,
        ], to: source)
        upload(Array(repeating: [UInt8(40), 120, 220, 255], count: 4).flatMap { $0 }, to: noise)
        let plan = SceneFilmGrainExecutionPlan(
            blendMode: 14, greyscale: false, scale: 12.75,
            strength: 1.79, exponent: 3.8
        )
        let command = queue.makeCommandBuffer()!
        guard pipeline.encode(
            source: source, noise: noise, target: target,
            plan: plan, time: 0.25, commandBuffer: command
        ) else { fatalError("valid Film Grain render rejected") }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { fatalError("GPU command failed") }
        return read(target)
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneFilmGrainPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let output = render(device: device, queue: queue, pipeline: pipeline)
        let alpha = stride(from: 3, to: output.count, by: 4).map { output[$0] }
        let premultiplied = stride(from: 0, to: output.count, by: 4).allSatisfy { offset in
            max(output[offset], output[offset + 1], output[offset + 2]) <= output[offset + 3]
        }
        let result: [String: Any] = [
            "metalUnavailable": false,
            "alpha": alpha,
            "premultiplied": premultiplied,
            "transparentPixel": Array(output[0..<4]),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneFilmGrainRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-film-grain-rendering-")
        root = Path(cls.temp.name)
        harness = root / "Harness.swift"
        binary = root / "film-grain-rendering"
        harness.write_text(HARNESS, encoding="utf-8")
        completed = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SOURCES), str(harness),
                "-framework", "Metal", "-o", str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        rendered = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(rendered.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def test_preserves_alpha_and_premultiplied_output(self) -> None:
        self.assertEqual(self.result["alpha"], [0, 64, 128, 255])
        self.assertTrue(self.result["premultiplied"], self.result)
        self.assertEqual(self.result["transparentPixel"], [0, 0, 0, 0])


if __name__ == "__main__":
    unittest.main()

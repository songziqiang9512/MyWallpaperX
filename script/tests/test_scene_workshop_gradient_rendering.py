#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneWorkshopGradientPipeline.swift"
)


HARNESS = r'''
import Foundation
import Metal

@main
enum Harness {
    static let size = 64

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat = .bgra8Unorm,
        width: Int = size,
        mipmapped: Bool = false,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget]
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: size, mipmapped: mipmapped
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func render(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWorkshopGradientPipeline
    ) -> [UInt8] {
        let source = texture(device: device)
        let target = texture(device: device)
        var input = [UInt8](repeating: 0, count: size * size * 4)
        for pixel in 0..<(size * size) {
            input[pixel * 4 + 3] = UInt8(pixel % 256)
        }
        source.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: &input,
            bytesPerRow: size * 4
        )
        let command = queue.makeCommandBuffer()!
        guard pipeline.encode(source: source, target: target, commandBuffer: command) else {
            fatalError("valid gradient rejected")
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { fatalError("GPU command failed") }
        var output = [UInt8](repeating: 0, count: input.count)
        target.getBytes(
            &output,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return output
    }

    static func metrics(_ pixels: [UInt8]) -> [String: Any] {
        var colors = Set<String>()
        var alphaPreserved = true
        var premultiplied = true
        var saturated = 0
        for pixel in 0..<(size * size) {
            let offset = pixel * 4
            let b = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let r = Int(pixels[offset + 2])
            let a = Int(pixels[offset + 3])
            colors.insert("\(r),\(g),\(b)")
            if a != pixel % 256 { alphaPreserved = false }
            if max(r, g, b) > a + 1 { premultiplied = false }
            if max(r, g, b) - min(r, g, b) > 100 { saturated += 1 }
        }
        return [
            "colorCount": colors.count,
            "alphaPreserved": alphaPreserved,
            "premultiplied": premultiplied,
            "saturated": saturated,
        ]
    }

    static func rejections(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWorkshopGradientPipeline
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let wrongFormat = texture(device: device, format: .rgba8Unorm)
        let wrongExtent = texture(device: device, width: size / 2)
        let mipmapped = texture(device: device, mipmapped: true)
        let noRead = texture(device: device, usage: [.renderTarget])
        let noWrite = texture(device: device, usage: [.shaderRead])
        let command = queue.makeCommandBuffer()!
        func accepts(
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target
        ) -> Bool {
            pipeline.encode(
                source: candidateSource,
                target: candidateTarget,
                commandBuffer: command
            )
        }
        return [
            "same": !accepts(source: source, target: source),
            "sourceFormat": !accepts(source: wrongFormat),
            "targetFormat": !accepts(target: wrongFormat),
            "extent": !accepts(target: wrongExtent),
            "sourceMip": !accepts(source: mipmapped),
            "targetMip": !accepts(target: mipmapped),
            "sourceUsage": !accepts(source: noRead),
            "targetUsage": !accepts(target: noWrite),
            "formatInit": SceneWorkshopGradientPipeline(
                device: device, pixelFormat: .rgba8Unorm
            ) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneWorkshopGradientPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let result: [String: Any] = [
            "metalUnavailable": false,
            "metrics": metrics(render(device: device, queue: queue, pipeline: pipeline)),
            "rejections": rejections(device: device, queue: queue, pipeline: pipeline),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneWorkshopGradientRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-workshop-gradient-")
        root = Path(cls.temp.name)
        harness = root / "Harness.swift"
        binary = root / "workshop-gradient"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", str(SOURCE), str(harness),
                "-framework", "Metal", "-o", str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def test_exact_profile_produces_a_multicolor_gradient(self) -> None:
        metrics = self.result["metrics"]
        self.assertGreater(metrics["colorCount"], 100, metrics)
        self.assertGreater(metrics["saturated"], 1000, metrics)

    def test_source_alpha_is_preserved(self) -> None:
        self.assertTrue(self.result["metrics"]["alphaPreserved"])
        self.assertTrue(self.result["metrics"]["premultiplied"])

    def test_invalid_resources_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()), self.result["rejections"])


if __name__ == "__main__":
    unittest.main()

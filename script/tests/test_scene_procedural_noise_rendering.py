#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneProceduralNoisePipeline.swift"

HARNESS = r'''
import Foundation
import Metal
import simd

@main
enum Harness {
    static let size = 64

    static func texture(
        _ device: MTLDevice,
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

    static func sourceBytes(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                bytes[offset] = UInt8((x * 4) % 256)
                bytes[offset + 1] = UInt8((y * 4) % 256)
                bytes[offset + 2] = UInt8(((x / 5 + y / 7) % 2) * 255)
                bytes[offset + 3] = 255
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
            withBytes: bytes, bytesPerRow: size * 4
        )
        return bytes
    }

    static func uniforms(variant: UInt32, time: Float) -> SceneProceduralNoisePipeline.Uniforms {
        SceneProceduralNoisePipeline.Uniforms(
            scale: variant == 0 ? SIMD2(repeating: 0.27) : SIMD2(repeating: 1),
            offset: variant == 2 ? SIMD2(repeating: 0.93) : .zero,
            magnitude: SIMD2(repeating: 1), thresholds: SIMD2(0, 1),
            colorsMin: SIMD4(0, 0, 0, 0), colorsMax: SIMD4(1, 1, 1, 0),
            params0: SIMD4(1, variant == 2 ? 0.1 : 1, 2, variant == 0 ? 0.05 : 0.5),
            params1: SIMD4(1, 0, variant == 0 ? 2 : 1, 0),
            params2: SIMD4(0, 0, 1, time), variant: variant,
            fractals: variant == 2 ? 5 : 1
        )
    }

    static func render(
        device: MTLDevice, queue: MTLCommandQueue,
        pipeline: SceneProceduralNoisePipeline, source: MTLTexture,
        variant: UInt32, time: Float
    ) -> [UInt8] {
        let target = texture(device)
        let command = queue.makeCommandBuffer()!
        guard pipeline.encode(
            source: source, target: target,
            uniforms: uniforms(variant: variant, time: time), commandBuffer: command
        ) else { fatalError("valid noise render rejected") }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { fatalError("GPU noise render failed") }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        target.getBytes(
            &bytes, bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0
        )
        return bytes
    }

    static func changed(_ lhs: [UInt8], _ rhs: [UInt8], threshold: Int = 8) -> Int {
        stride(from: 0, to: lhs.count, by: 4).reduce(0) { count, offset in
            let difference = (0..<3).reduce(0) {
                $0 + abs(Int(lhs[offset + $1]) - Int(rhs[offset + $1]))
            }
            return count + (difference > threshold ? 1 : 0)
        }
    }

    static func rejections(
        device: MTLDevice, queue: MTLCommandQueue, pipeline: SceneProceduralNoisePipeline
    ) -> [String: Bool] {
        let source = texture(device)
        let target = texture(device)
        let command = queue.makeCommandBuffer()!
        let valid = uniforms(variant: 0, time: 1)
        func accepted(
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target,
            uniforms candidateUniforms: SceneProceduralNoisePipeline.Uniforms = valid
        ) -> Bool {
            pipeline.encode(
                source: candidateSource, target: candidateTarget,
                uniforms: candidateUniforms, commandBuffer: command
            )
        }
        var badVariant = valid; badVariant.variant = 3
        var badFractals = valid; badFractals.fractals = 0
        var badScale = valid; badScale.scale.x = 0
        var badTime = valid; badTime.params2.w = .nan
        return [
            "same": !accepted(source: source, target: source),
            "format": !accepted(source: texture(device, format: .rgba8Unorm)),
            "extent": !accepted(target: texture(device, width: size / 2)),
            "mip": !accepted(source: texture(device, mipmapped: true)),
            "readUsage": !accepted(source: texture(device, usage: [.renderTarget])),
            "writeUsage": !accepted(target: texture(device, usage: [.shaderRead])),
            "variant": !accepted(uniforms: badVariant),
            "fractals": !accepted(uniforms: badFractals),
            "scale": !accepted(uniforms: badScale),
            "time": !accepted(uniforms: badTime),
            "formatInit": SceneProceduralNoisePipeline(
                device: device, pixelFormat: .rgba8Unorm
            ) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneProceduralNoisePipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let source = texture(device)
        let original = sourceBytes(source)
        let color0 = render(device: device, queue: queue, pipeline: pipeline, source: source, variant: 0, time: 0)
        let color1 = render(device: device, queue: queue, pipeline: pipeline, source: source, variant: 0, time: 0.75)
        let curl0 = render(device: device, queue: queue, pipeline: pipeline, source: source, variant: 1, time: 0)
        let curl1 = render(device: device, queue: queue, pipeline: pipeline, source: source, variant: 1, time: 0.75)
        let worley0 = render(device: device, queue: queue, pipeline: pipeline, source: source, variant: 2, time: 0)
        let worley1 = render(device: device, queue: queue, pipeline: pipeline, source: source, variant: 2, time: 0.75)
        let result: [String: Any] = [
            "metalUnavailable": false,
            "colorChanged": changed(original, color0),
            "colorMotion": changed(color0, color1),
            "curlChanged": changed(original, curl0),
            "curlMotion": changed(curl0, curl1),
            "worleyChanged": changed(original, worley0),
            "worleyMotion": changed(worley0, worley1),
            "variantsDiffer": changed(curl0, worley0),
            "rejections": rejections(device: device, queue: queue, pipeline: pipeline),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneProceduralNoiseRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-procedural-noise-")
        root = Path(cls.temp.name)
        harness = root / "Harness.swift"
        binary = root / "procedural-noise-rendering"
        harness.write_text(HARNESS, encoding="utf-8")
        completed = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", str(SOURCE), str(harness),
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

    def test_three_exact_variants_are_visible_and_time_driven(self) -> None:
        for key in (
            "colorChanged", "colorMotion", "curlChanged", "curlMotion",
            "worleyChanged", "worleyMotion", "variantsDiffer",
        ):
            self.assertGreater(self.result[key], 600, (key, self.result))

    def test_invalid_resources_and_uniforms_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()), self.result["rejections"])


if __name__ == "__main__":
    unittest.main()

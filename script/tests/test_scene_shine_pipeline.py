#!/usr/bin/env python3
"""GPU validation for the project-owned five-pass Shine composition."""

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
    SOURCE_ROOT / "Effects/SceneShinePipeline.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneShineExecutionPlan {
    let threshold: Float
    let noiseAmount: Float
    let noiseScale: Float
    let noiseSpeed: Float
    let edgeCount: Int
    let sampleCount: Int
    let direction: Float
    let rotationSpeed: Float
    let rayLength: Float
    let rayIntensity: Float
    let rayColor: SIMD3<Float>
    let kernelRadius: Int
    let blurScaleX: SIMD2<Float>
    let blurScaleY: SIMD2<Float>
    let blendMode: Int
}

@main
enum Harness {
    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat,
        width: Int,
        height: Int,
        usage: MTLTextureUsage
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func fillColor(
        _ texture: MTLTexture,
        brightCenter: Bool = false
    ) {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        for y in 0 ..< texture.height {
            for x in 0 ..< texture.width {
                let offset = y * bytesPerRow + x * 4
                let bright = brightCenter
                    && abs(x - texture.width / 2) <= 4
                    && abs(y - texture.height / 2) <= 4
                let value: UInt8 = bright ? 255 : 0
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
    }

    static func fillMono(_ texture: MTLTexture, byte: UInt8) {
        let bytesPerRow = texture.width
        let bytes = [UInt8](repeating: byte, count: bytesPerRow * texture.height)
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
    }

    static func outsideRGBSum(_ texture: MTLTexture) -> Int {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        var sum = 0
        for y in 0 ..< texture.height {
            for x in 0 ..< texture.width {
                guard abs(x - texture.width / 2) > 6
                        || abs(y - texture.height / 2) > 6 else {
                    continue
                }
                let offset = y * bytesPerRow + x * 4
                sum += Int(bytes[offset])
                    + Int(bytes[offset + 1])
                    + Int(bytes[offset + 2])
            }
        }
        return sum
    }

    static func encode(
        pipeline: SceneShinePipeline,
        queue: MTLCommandQueue,
        source: MTLTexture,
        firstHalf: MTLTexture,
        secondHalf: MTLTexture,
        output: MTLTexture,
        mask: MTLTexture?,
        noise: MTLTexture,
        plan: SceneShineExecutionPlan
    ) -> Bool {
        guard let commandBuffer = queue.makeCommandBuffer() else { return false }
        let encoded = pipeline.encodeDownsample(
            source: source,
            mask: mask,
            maskUVScale: SIMD2(repeating: 1),
            noise: noise,
            target: firstHalf,
            plan: plan,
            time: 1.25,
            commandBuffer: commandBuffer
        ) && pipeline.encodeCast(
            source: firstHalf,
            target: secondHalf,
            plan: plan,
            time: 1.25,
            commandBuffer: commandBuffer
        ) && pipeline.encodeGaussian(
            source: secondHalf,
            target: firstHalf,
            plan: plan,
            vertical: false,
            commandBuffer: commandBuffer
        ) && pipeline.encodeGaussian(
            source: firstHalf,
            target: secondHalf,
            plan: plan,
            vertical: true,
            commandBuffer: commandBuffer
        ) && pipeline.encodeCombine(
            rays: secondHalf,
            source: source,
            target: output,
            plan: plan,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return encoded && commandBuffer.status == .completed
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneShinePipeline(device: device) else {
            print(#"{"available":false}"#)
            return
        }
        let source = texture(
            device: device, format: .bgra8Unorm, width: 128, height: 72,
            usage: [.shaderRead]
        )
        let firstHalf = texture(
            device: device, format: .bgra8Unorm, width: 64, height: 36,
            usage: [.shaderRead, .renderTarget]
        )
        let secondHalf = texture(
            device: device, format: .bgra8Unorm, width: 64, height: 36,
            usage: [.shaderRead, .renderTarget]
        )
        let output = texture(
            device: device, format: .bgra8Unorm, width: 128, height: 72,
            usage: [.shaderRead, .renderTarget]
        )
        let mask = texture(
            device: device, format: .r8Unorm, width: 128, height: 72,
            usage: [.shaderRead]
        )
        let noise = texture(
            device: device, format: .r8Unorm, width: 32, height: 32,
            usage: [.shaderRead]
        )
        fillColor(source, brightCenter: true)
        fillMono(mask, byte: 255)
        fillMono(noise, byte: 127)

        let plan = SceneShineExecutionPlan(
            threshold: 0.5,
            noiseAmount: 0,
            noiseScale: 2,
            noiseSpeed: 0,
            edgeCount: 5,
            sampleCount: 30,
            direction: 0.35,
            rotationSpeed: 0,
            rayLength: 0.35,
            rayIntensity: 2,
            rayColor: SIMD3(repeating: 1),
            kernelRadius: 3,
            blurScaleX: SIMD2(repeating: 1),
            blurScaleY: SIMD2(repeating: 1),
            blendMode: 9
        )
        let unmaskedEncoded = encode(
            pipeline: pipeline, queue: queue, source: source,
            firstHalf: firstHalf, secondHalf: secondHalf, output: output,
            mask: nil, noise: noise, plan: plan
        )
        let unmaskedOutsideSum = outsideRGBSum(output)

        fillMono(mask, byte: 0)
        let zeroMaskEncoded = encode(
            pipeline: pipeline, queue: queue, source: source,
            firstHalf: firstHalf, secondHalf: secondHalf, output: output,
            mask: mask, noise: noise, plan: plan
        )
        let zeroMaskOutsideSum = outsideRGBSum(output)

        let result: [String: Any] = [
            "available": true,
            "unmaskedEncoded": unmaskedEncoded,
            "unmaskedOutsideSum": unmaskedOutsideSum,
            "zeroMaskEncoded": zeroMaskEncoded,
            "zeroMaskOutsideSum": zeroMaskOutsideSum,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneShinePipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("xcrun is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-shine-pipeline-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        cls.binary = root / "scene-shine-pipeline"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(source) for source in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)
        if not cls.result["available"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_five_pass_pipeline_spreads_rays_beyond_bright_source(self) -> None:
        self.assertTrue(self.result["unmaskedEncoded"])
        self.assertGreater(self.result["unmaskedOutsideSum"], 0)

    def test_zero_mask_blocks_rays_without_blocking_source_composition(self) -> None:
        self.assertTrue(self.result["zeroMaskEncoded"])
        self.assertEqual(self.result["zeroMaskOutsideSum"], 0)


if __name__ == "__main__":
    unittest.main()

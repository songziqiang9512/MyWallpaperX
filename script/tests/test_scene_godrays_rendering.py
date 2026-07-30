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
    SOURCE_ROOT / "Effects/SceneGodraysPipeline.swift",
    SOURCE_ROOT / "Effects/SceneGodraysPipeline+Encoding.swift",
]

HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneGodraysPlan {
    let threshold: Float
    let noiseAmount: Float
    let noiseScale: Float
    let noiseSpeed: Float
    let noiseSmoothness: Float
    let center: SIMD2<Float>
    let colorRays: SIMD3<Float>
    let rayLength: Float
    let rayIntensity: Float
    let samples50: Bool
    let kernel13: Bool
    let direction: Float?
    let legacyGaussianWeights: Bool
    let blurScaleX: SIMD2<Float>
    let blurScaleY: SIMD2<Float>
    let blendMode: Int
}

@main
enum Harness {
    static let size = 32

    static func texture(
        device: MTLDevice,
        usage: MTLTextureUsage,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func plan(
        direction: Float?,
        legacyGaussianWeights: Bool = true
    ) -> SceneGodraysPlan {
        .init(
            threshold: 0,
            noiseAmount: 0,
            noiseScale: 1,
            noiseSpeed: 0,
            noiseSmoothness: 0,
            center: SIMD2(repeating: 0.5),
            colorRays: SIMD3(repeating: 1),
            rayLength: 0.8,
            rayIntensity: 1,
            samples50: false,
            kernel13: false,
            direction: direction,
            legacyGaussianWeights: legacyGaussianWeights,
            blurScaleX: SIMD2(repeating: 1),
            blurScaleY: SIMD2(repeating: 1),
            blendMode: 0
        )
    }

    static func impulseBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 15...16 {
            for x in 15...16 {
                let offset = (y * size + x) * 4
                bytes[offset] = 255
                bytes[offset + 1] = 255
                bytes[offset + 2] = 255
                bytes[offset + 3] = 255
            }
        }
        return bytes
    }

    static func bottomEdgeBytes() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 30...31 {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                bytes[offset] = 255
                bytes[offset + 1] = 255
                bytes[offset + 2] = 255
                bytes[offset + 3] = 255
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

    static func renderCast(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneGodraysPipeline,
        source: MTLTexture,
        direction: Float
    ) -> [UInt8] {
        let target = texture(device: device, usage: [.shaderRead, .renderTarget])
        let command = queue.makeCommandBuffer()!
        precondition(pipeline.encodeCast(
            source: source,
            target: target,
            plan: plan(direction: direction),
            commandBuffer: command
        ))
        command.commit()
        command.waitUntilCompleted()
        precondition(command.status == .completed)
        return read(target)
    }

    static func renderGaussian(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneGodraysPipeline,
        source: MTLTexture,
        vertical: Bool = false
    ) -> [UInt8] {
        let target = texture(device: device, usage: [.shaderRead, .renderTarget])
        let command = queue.makeCommandBuffer()!
        precondition(pipeline.encodeGaussian(
            source: source,
            target: target,
            plan: plan(direction: 0),
            vertical: vertical,
            commandBuffer: command
        ))
        command.commit()
        command.waitUntilCompleted()
        precondition(command.status == .completed)
        return read(target)
    }

    static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        (0..<(lhs.count / 4)).filter { pixel in
            let offset = pixel * 4
            return (0..<4).contains {
                abs(Int(lhs[offset + $0]) - Int(rhs[offset + $0])) > 1
            }
        }.count
    }

    static func channel(_ bytes: [UInt8], x: Int, y: Int) -> Int {
        Int(bytes[(y * size + x) * 4])
    }

    static func channelSum(
        _ bytes: [UInt8],
        rows: ClosedRange<Int>
    ) -> Int {
        rows.reduce(0) { total, y in
            total + (0..<size).reduce(0) { rowTotal, x in
                rowTotal + channel(bytes, x: x, y: y)
            }
        }
    }

    static func channelRowSum(_ bytes: [UInt8], row: Int) -> Int {
        (0..<size).reduce(0) {
            $0 + channel(bytes, x: $1, y: row)
        }
    }

    static func invalidDirectionRejected(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneGodraysPipeline,
        source: MTLTexture
    ) -> Bool {
        let target = texture(device: device, usage: .renderTarget)
        let command = queue.makeCommandBuffer()!
        return !pipeline.encodeCast(
            source: source,
            target: target,
            plan: plan(direction: .nan),
            commandBuffer: command
        )
    }

    static func renderLegacyRGBAChain(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneGodraysPipeline,
        source: MTLTexture
    ) -> Bool {
        let half = texture(
            device: device, usage: [.shaderRead, .renderTarget], pixelFormat: .rgba8Unorm
        )
        let otherHalf = texture(
            device: device, usage: [.shaderRead, .renderTarget], pixelFormat: .rgba8Unorm
        )
        let output = texture(
            device: device, usage: [.shaderRead, .renderTarget], pixelFormat: .bgra8Unorm
        )
        let command = queue.makeCommandBuffer()!
        guard pipeline.encodeDownsample(
            source: source, mask: nil, maskUVScale: SIMD2(repeating: 1), noise: nil,
            target: half, plan: plan(direction: 0), time: 0, commandBuffer: command
        ), pipeline.encodeCast(
            source: half, target: otherHalf, plan: plan(direction: 0), commandBuffer: command
        ), pipeline.encodeGaussian(
            source: otherHalf, target: half, plan: plan(direction: 0), vertical: false,
            commandBuffer: command
        ), pipeline.encodeGaussian(
            source: half, target: otherHalf, plan: plan(direction: 0), vertical: true,
            commandBuffer: command
        ), pipeline.encodeCombine(
            rays: otherHalf, source: source, target: output, plan: plan(direction: 0),
            commandBuffer: command
        ) else {
            return false
        }
        command.commit()
        command.waitUntilCompleted()
        return command.status == .completed
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneGodraysPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let source = texture(device: device, usage: .shaderRead)
        let input = impulseBytes()
        upload(input, to: source)
        let vertical = renderCast(
            device: device, queue: queue, pipeline: pipeline,
            source: source, direction: 0
        )
        let horizontal = renderCast(
            device: device, queue: queue, pipeline: pipeline,
            source: source, direction: Float.pi / 2
        )
        let upward = renderCast(
            device: device, queue: queue, pipeline: pipeline,
            source: source, direction: Float.pi
        )
        let gaussian = renderGaussian(
            device: device, queue: queue, pipeline: pipeline, source: source
        )
        upload(bottomEdgeBytes(), to: source)
        let edgeCast = renderCast(
            device: device, queue: queue, pipeline: pipeline,
            source: source, direction: 0
        )
        let edgeGaussian = renderGaussian(
            device: device, queue: queue, pipeline: pipeline,
            source: source, vertical: true
        )
        let result: [String: Any] = [
            "metalUnavailable": false,
            "directionChangedPixels": changedPixels(vertical, horizontal),
            "directionZeroUpperSum": channelSum(vertical, rows: 0...12),
            "directionZeroLowerSum": channelSum(vertical, rows: 19...31),
            "directionPiUpperSum": channelSum(upward, rows: 0...12),
            "directionPiLowerSum": channelSum(upward, rows: 19...31),
            "gaussianChangedPixels": changedPixels(input, gaussian),
            "gaussianCenter": channel(gaussian, x: 15, y: 15),
            "gaussianNearLeft": channel(gaussian, x: 14, y: 15),
            "gaussianNearRight": channel(gaussian, x: 17, y: 15),
            "gaussianFar": channel(gaussian, x: 8, y: 15),
            "edgeCastInnerSum": channelRowSum(edgeCast, row: 22),
            "edgeCastBoundarySum": channelRowSum(edgeCast, row: 31),
            "edgeGaussianInnerSum": channelRowSum(edgeGaussian, row: 30),
            "edgeGaussianBoundarySum": channelRowSum(edgeGaussian, row: 31),
            "invalidDirectionRejected": invalidDirectionRejected(
                device: device, queue: queue, pipeline: pipeline, source: source
            ),
            "legacyRGBAChainCompleted": renderLegacyRGBAChain(
                device: device, queue: queue, pipeline: pipeline, source: source
            ),
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
class SceneGodraysRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-godrays-rendering-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-godrays-rendering"
        completed = subprocess.run(
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
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
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

    def test_direction_rotates_the_cast_axis(self) -> None:
        self.assertGreater(self.result["directionChangedPixels"], 20)

    def test_legacy_direction_matches_official_rotation_orientation(self) -> None:
        self.assertGreater(
            self.result["directionZeroUpperSum"],
            self.result["directionZeroLowerSum"],
        )
        self.assertGreater(
            self.result["directionPiLowerSum"],
            self.result["directionPiUpperSum"],
        )

    def test_legacy_gaussian_spreads_a_symmetric_impulse(self) -> None:
        self.assertGreater(self.result["gaussianChangedPixels"], 10)
        self.assertGreater(self.result["gaussianCenter"], self.result["gaussianFar"])
        self.assertAlmostEqual(
            self.result["gaussianNearLeft"],
            self.result["gaussianNearRight"],
            delta=2,
        )

    def test_directional_cast_fades_at_the_framebuffer_boundary(self) -> None:
        self.assertLess(
            self.result["edgeCastBoundarySum"],
            self.result["edgeCastInnerSum"] * 1.5,
        )

    def test_gaussian_pass_does_not_repeat_an_opaque_framebuffer_edge(self) -> None:
        self.assertLess(
            self.result["edgeGaussianBoundarySum"],
            32 * 255 * 0.5,
        )

    def test_nonfinite_direction_fails_closed(self) -> None:
        self.assertTrue(self.result["invalidDirectionRejected"])

    def test_legacy_rgba_half_targets_complete_without_pipeline_mismatch(self) -> None:
        self.assertTrue(self.result["legacyRGBAChainCompleted"])


if __name__ == "__main__":
    unittest.main()

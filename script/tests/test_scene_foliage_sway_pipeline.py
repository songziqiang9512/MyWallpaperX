#!/usr/bin/env python3
"""GPU pixel contract for the project-owned Foliage Sway pipeline."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PIPELINE_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneFoliageSwayPipeline.swift"
)


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneFoliageSwayPlan {
    let strength: Float
    let speed: Float
    let phase: Float
    let power: Float
    let noiseScale: Float
    let ratio: Float
    let direction: Float
}

@main
enum Harness {
    struct Difference {
        let sum: Int
        let maximum: Int
        let changedBytes: Int
    }

    static let width = 128
    static let height = 96

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

    static func sourceTexture(device: MTLDevice) -> MTLTexture {
        let result = texture(
            device: device,
            format: .bgra8Unorm,
            width: width,
            height: height,
            usage: [.shaderRead]
        )
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = y * bytesPerRow + x * 4
                bytes[offset] = UInt8((x * 17 + y * 3) & 255)
                bytes[offset + 1] = UInt8((x * 5 + y * 11) & 255)
                bytes[offset + 2] = UInt8((x * 13 + y * 7) & 255)
                bytes[offset + 3] = 255
            }
        }
        result.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
        return result
    }

    static func noiseTexture(
        device: MTLDevice,
        red: UInt8,
        green: UInt8,
        patternedGreen: Bool = false
    ) -> MTLTexture {
        let size = 64
        let result = texture(
            device: device,
            format: .rgba8Unorm,
            width: size,
            height: size,
            usage: [.shaderRead]
        )
        let bytesPerRow = size * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * size)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let offset = y * bytesPerRow + x * 4
                let border = x < 4 || y < 4 || x >= size - 4 || y >= size - 4
                bytes[offset] = red
                bytes[offset + 1] = patternedGreen && !border ? 192 : green
                bytes[offset + 2] = 0
                bytes[offset + 3] = 255
            }
        }
        result.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
        return result
    }

    static func maskTexture(device: MTLDevice, value: UInt8) -> MTLTexture {
        let result = texture(
            device: device,
            format: .r8Unorm,
            width: width,
            height: height,
            usage: [.shaderRead]
        )
        let bytes = [UInt8](repeating: value, count: width * height)
        result.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: width
        )
        return result
    }

    static func outputTexture(device: MTLDevice) -> MTLTexture {
        texture(
            device: device,
            format: .bgra8Unorm,
            width: width,
            height: height,
            usage: [.shaderRead, .renderTarget]
        )
    }

    static func bytes(_ texture: MTLTexture) -> [UInt8] {
        let bytesPerRow = texture.width * 4
        var result = [UInt8](
            repeating: 0,
            count: bytesPerRow * texture.height
        )
        texture.getBytes(
            &result,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return result
    }

    static func difference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Difference {
        precondition(lhs.count == rhs.count)
        var sum = 0
        var maximum = 0
        var changedBytes = 0
        for (left, right) in zip(lhs, rhs) {
            let delta = abs(Int(left) - Int(right))
            sum += delta
            maximum = max(maximum, delta)
            if delta != 0 {
                changedBytes += 1
            }
        }
        return Difference(sum: sum, maximum: maximum, changedBytes: changedBytes)
    }

    static func plan(noiseScale: Float) -> SceneFoliageSwayPlan {
        SceneFoliageSwayPlan(
            strength: 1,
            speed: 2,
            phase: 1,
            power: 1,
            noiseScale: noiseScale,
            ratio: 0.7,
            direction: 0.73
        )
    }

    static func render(
        pipeline: SceneFoliageSwayPipeline,
        queue: MTLCommandQueue,
        source: MTLTexture,
        mask: MTLTexture?,
        noise: MTLTexture,
        plan: SceneFoliageSwayPlan
    ) -> (Bool, [UInt8]) {
        let target = outputTexture(device: source.device)
        guard let commandBuffer = queue.makeCommandBuffer() else {
            return (false, [])
        }
        let encoded = pipeline.encode(
            source: source,
            mask: mask,
            noise: noise,
            target: target,
            plan: plan,
            maskUVScale: SIMD2(repeating: 1),
            time: 0.37,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return (
            encoded && commandBuffer.status == .completed,
            bytes(target)
        )
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneFoliageSwayPipeline(device: device) else {
            print(#"{"available":false}"#)
            return
        }

        let source = sourceTexture(device: device)
        let sourceBytes = bytes(source)
        let whiteMask = maskTexture(device: device, value: 255)
        let zeroMask = maskTexture(device: device, value: 0)
        let redZeroGreenQuarter = noiseTexture(
            device: device, red: 0, green: 64
        )
        let redThreeQuarterGreenQuarter = noiseTexture(
            device: device, red: 192, green: 64
        )
        let redThreeQuarterGreenThreeQuarter = noiseTexture(
            device: device, red: 192, green: 192
        )
        let scalePattern = noiseTexture(
            device: device, red: 0, green: 64, patternedGreen: true
        )

        let channelPlan = plan(noiseScale: 0.25)
        let scalePlan = plan(noiseScale: 1.0 / 32.0)

        let unmasked = render(
            pipeline: pipeline,
            queue: queue,
            source: source,
            mask: nil,
            noise: redThreeQuarterGreenQuarter,
            plan: channelPlan
        )
        let whiteMasked = render(
            pipeline: pipeline,
            queue: queue,
            source: source,
            mask: whiteMask,
            noise: redThreeQuarterGreenQuarter,
            plan: channelPlan
        )
        let zeroMasked = render(
            pipeline: pipeline,
            queue: queue,
            source: source,
            mask: zeroMask,
            noise: redThreeQuarterGreenQuarter,
            plan: channelPlan
        )
        let redZero = render(
            pipeline: pipeline,
            queue: queue,
            source: source,
            mask: nil,
            noise: redZeroGreenQuarter,
            plan: channelPlan
        )
        let greenChanged = render(
            pipeline: pipeline,
            queue: queue,
            source: source,
            mask: nil,
            noise: redThreeQuarterGreenThreeQuarter,
            plan: channelPlan
        )
        let scaleReference = render(
            pipeline: pipeline,
            queue: queue,
            source: source,
            mask: nil,
            noise: redZeroGreenQuarter,
            plan: scalePlan
        )
        let scalePatterned = render(
            pipeline: pipeline,
            queue: queue,
            source: source,
            mask: nil,
            noise: scalePattern,
            plan: scalePlan
        )

        let nilVersusWhite = difference(unmasked.1, whiteMasked.1)
        let zeroVersusSource = difference(zeroMasked.1, sourceBytes)
        let motionVersusSource = difference(unmasked.1, sourceBytes)
        let redChannelOnly = difference(unmasked.1, redZero.1)
        let greenChannel = difference(unmasked.1, greenChanged.1)
        let authoredScale = difference(scaleReference.1, scalePatterned.1)

        let result: [String: Any] = [
            "available": true,
            "allEncoded": [
                unmasked.0,
                whiteMasked.0,
                zeroMasked.0,
                redZero.0,
                greenChanged.0,
                scaleReference.0,
                scalePatterned.0,
            ].allSatisfy { $0 },
            "nilWhiteDifferenceSum": nilVersusWhite.sum,
            "nilWhiteDifferenceMax": nilVersusWhite.maximum,
            "zeroSourceDifferenceSum": zeroVersusSource.sum,
            "zeroSourceDifferenceMax": zeroVersusSource.maximum,
            "motionSourceDifferenceSum": motionVersusSource.sum,
            "motionSourceChangedBytes": motionVersusSource.changedBytes,
            "redOnlyDifferenceSum": redChannelOnly.sum,
            "redOnlyDifferenceMax": redChannelOnly.maximum,
            "greenDifferenceSum": greenChannel.sum,
            "greenChangedBytes": greenChannel.changedBytes,
            "scaleDifferenceSum": authoredScale.sum,
            "scaleDifferenceMax": authoredScale.maximum,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneFoliageSwayPipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("xcrun is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-foliage-pipeline-",
            dir="/private/tmp",
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        cls.binary = root / "scene-foliage-sway-pipeline"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                str(PIPELINE_SOURCE),
                str(harness),
                "-framework",
                "Metal",
                "-module-cache-path",
                str(root / "module-cache"),
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

    def test_masked_and_unmasked_amplitude_contract(self) -> None:
        self.assertTrue(self.result["allEncoded"])
        self.assertLessEqual(self.result["nilWhiteDifferenceMax"], 1)
        self.assertLessEqual(self.result["zeroSourceDifferenceMax"], 1)
        self.assertGreater(self.result["motionSourceDifferenceSum"], 1_000)
        self.assertGreater(self.result["motionSourceChangedBytes"], 100)

    def test_noise_uses_green_channel_instead_of_red(self) -> None:
        self.assertLessEqual(self.result["redOnlyDifferenceMax"], 1)
        self.assertGreater(self.result["greenDifferenceSum"], 1_000)
        self.assertGreater(self.result["greenChangedBytes"], 100)

    def test_noise_uv_uses_authored_scale_without_legacy_multiplier(self) -> None:
        self.assertLessEqual(self.result["scaleDifferenceMax"], 1)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3

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
    / "MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneCursorRipplePipeline.swift"
)

HARNESS = r'''
import Foundation
import Metal

struct SceneCursorRippleExecutionPlan {
    let simulationResolution: Int
    let rippleScale: Float
    let decay: Float
    let speed: Float
    let strength: Float
    let maskTexturePath: String?
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

    static func clear(_ texture: MTLTexture, byte: UInt8 = 0) {
        let channels = texture.pixelFormat == .r8Unorm ? 1 : 4
        let bytesPerRow = texture.width * channels
        let bytes = [UInt8](
            repeating: byte,
            count: bytesPerRow * texture.height
        )
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: bytesPerRow
        )
    }

    static func byteSum(_ texture: MTLTexture) -> Int {
        let bytesPerRow = texture.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * texture.height)
        texture.getBytes(
            &bytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return bytes.reduce(0) { $0 + Int($1) }
    }

    static func encode(
        pipeline: SceneCursorRipplePipeline,
        queue: MTLCommandQueue,
        history: MTLTexture,
        intermediate: MTLTexture,
        source: MTLTexture,
        output: MTLTexture,
        mask: MTLTexture?,
        plan: SceneCursorRippleExecutionPlan,
        current: SIMD2<Float>,
        previous: SIMD2<Float>
    ) -> Bool {
        guard let commandBuffer = queue.makeCommandBuffer() else { return false }
        let encoded = pipeline.encode(
            history: history,
            intermediate: intermediate,
            source: source,
            output: output,
            mask: mask,
            maskUVScale: SIMD2(repeating: 1),
            plan: plan,
            currentCursorUV: current,
            previousCursorUV: previous,
            pointerIsInside: true,
            previousPointerIsInside: true,
            frameTime: 1 / 60,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return encoded && commandBuffer.status == .completed
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneCursorRipplePipeline(device: device) else {
            print(#"{"available":false}"#)
            return
        }
        let history = texture(
            device: device, format: .rgba8Unorm, width: 64, height: 36,
            usage: [.shaderRead, .renderTarget]
        )
        let intermediate = texture(
            device: device, format: .rgba8Unorm, width: 64, height: 36,
            usage: [.shaderRead, .renderTarget]
        )
        let source = texture(
            device: device, format: .bgra8Unorm, width: 128, height: 72,
            usage: [.shaderRead, .renderTarget]
        )
        let output = texture(
            device: device, format: .bgra8Unorm, width: 128, height: 72,
            usage: [.shaderRead, .renderTarget]
        )
        let mask = texture(
            device: device, format: .r8Unorm, width: 64, height: 36,
            usage: [.shaderRead]
        )
        clear(history)
        clear(intermediate)
        clear(source, byte: 127)
        clear(output)
        clear(mask, byte: 255)

        let unmasked = SceneCursorRippleExecutionPlan(
            simulationResolution: 256,
            rippleScale: 0.4,
            decay: 0.4,
            speed: 0.2,
            strength: 0.25,
            maskTexturePath: nil
        )
        let unmaskedEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: history, intermediate: intermediate,
            source: source, output: output, mask: nil, plan: unmasked,
            current: SIMD2(0.7, 0.5), previous: SIMD2(0.3, 0.5)
        )
        let unmaskedSum = byteSum(history)
        let stationaryEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: history, intermediate: intermediate,
            source: source, output: output, mask: nil, plan: unmasked,
            current: SIMD2(0.7, 0.5), previous: SIMD2(0.7, 0.5)
        )
        let stationarySum = byteSum(history)

        clear(history)
        clear(intermediate)
        let masked = SceneCursorRippleExecutionPlan(
            simulationResolution: 256,
            rippleScale: 0.4,
            decay: 0.4,
            speed: 0.2,
            strength: 0.25,
            maskTexturePath: "masks/collision"
        )
        let maskedEncoded = encode(
            pipeline: pipeline, queue: queue,
            history: history, intermediate: intermediate,
            source: source, output: output, mask: mask, plan: masked,
            current: SIMD2(0.7, 0.5), previous: SIMD2(0.3, 0.5)
        )
        let result: [String: Any] = [
            "available": true,
            "unmaskedEncoded": unmaskedEncoded,
            "unmaskedSum": unmaskedSum,
            "stationaryEncoded": stationaryEncoded,
            "stationarySum": stationarySum,
            "maskedEncoded": maskedEncoded,
            "maskedSum": byteSum(history),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneCursorRipplePipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("xcrun") is None:
            raise unittest.SkipTest("xcrun is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-cursor-ripple-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        cls.binary = root / "scene-cursor-ripple"
        harness.write_text(HARNESS)
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                str(PIPELINE_SOURCE),
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

    def test_motion_seeds_history_and_stationary_frame_preserves_wave(self) -> None:
        self.assertTrue(self.result["unmaskedEncoded"])
        self.assertGreater(self.result["unmaskedSum"], 0)
        self.assertTrue(self.result["stationaryEncoded"])
        self.assertGreater(self.result["stationarySum"], 0)

    def test_white_collision_mask_blocks_wave_state(self) -> None:
        self.assertTrue(self.result["maskedEncoded"])
        self.assertEqual(self.result["maskedSum"], 0)


if __name__ == "__main__":
    unittest.main()

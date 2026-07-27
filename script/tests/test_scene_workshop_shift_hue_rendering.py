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
    SOURCE_ROOT / "Effects/SceneWorkshopShiftHuePipeline.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopShiftHueRenderer.swift",
]


HARNESS = r'''
import Foundation
import Metal

struct SceneWorkshopShiftHueExecutionPlan { let speed: Float }

@main
enum Harness {
    static let size = 2

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat = .bgra8Unorm,
        width: Int = size,
        mipmapped: Bool = false,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget]
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: size,
            mipmapped: mipmapped
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func upload(_ rgba: [UInt8], to texture: MTLTexture) {
        var bgra = rgba
        for index in stride(from: 0, to: rgba.count, by: 4) {
            bgra[index] = rgba[index + 2]
            bgra[index + 2] = rgba[index]
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: &bgra,
            bytesPerRow: size * 4
        )
    }

    static func read(_ texture: MTLTexture) -> [UInt8] {
        var bgra = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(
            &bgra,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        var rgba = bgra
        for index in stride(from: 0, to: bgra.count, by: 4) {
            rgba[index] = bgra[index + 2]
            rgba[index + 2] = bgra[index]
        }
        return rgba
    }

    static func render(
        input: [UInt8],
        speed: Float,
        time: Float,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWorkshopShiftHuePipeline
    ) -> [UInt8] {
        let source = texture(device: device)
        let target = texture(device: device)
        upload(input, to: source)
        let command = queue.makeCommandBuffer()!
        guard SceneWorkshopShiftHueRenderer.render(
            plan: .init(speed: speed),
            time: time,
            inputTexture: source,
            outputTexture: target,
            pipeline: pipeline,
            commandBuffer: command
        ) === target else { fatalError("valid render rejected") }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { fatalError("GPU command failed") }
        return read(target)
    }

    static func renderOffset(
        input: [UInt8],
        offset: Float,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWorkshopShiftHuePipeline
    ) -> [UInt8] {
        let source = texture(device: device)
        let target = texture(device: device)
        upload(input, to: source)
        let command = queue.makeCommandBuffer()!
        guard pipeline.encodeHueOffset(
            source: source,
            target: target,
            offset: offset,
            commandBuffer: command
        ) else { fatalError("valid hue offset rejected") }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { fatalError("GPU command failed") }
        return read(target)
    }

    static func rejections(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWorkshopShiftHuePipeline
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let wrongFormat = texture(device: device, format: .rgba8Unorm)
        let wrongExtent = texture(device: device, width: 1)
        let mipmapped = texture(device: device, mipmapped: true)
        let noRead = texture(device: device, usage: [.renderTarget])
        let noWrite = texture(device: device, usage: [.shaderRead])
        let command = queue.makeCommandBuffer()!
        func accepts(
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target,
            speed: Float = 0.5,
            time: Float = 1
        ) -> Bool {
            pipeline.encode(
                source: candidateSource,
                target: candidateTarget,
                speed: speed,
                time: time,
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
            "speedLow": !accepts(speed: -0.01),
            "speedHigh": !accepts(speed: 1.01),
            "speedNaN": !accepts(speed: .nan),
            "timeNaN": !accepts(time: .nan),
            "offsetLow": !pipeline.encodeHueOffset(
                source: source, target: target, offset: -0.01, commandBuffer: command
            ),
            "offsetHigh": !pipeline.encodeHueOffset(
                source: source, target: target, offset: 2.01, commandBuffer: command
            ),
            "offsetNaN": !pipeline.encodeHueOffset(
                source: source, target: target, offset: .nan, commandBuffer: command
            ),
            "formatInit": SceneWorkshopShiftHuePipeline(
                device: device,
                pixelFormat: .rgba8Unorm
            ) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneWorkshopShiftHuePipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let input: [UInt8] = [
            255, 0, 0, 255,
            0, 255, 0, 200,
            0, 0, 255, 128,
            96, 96, 96, 64,
        ]
        let result: [String: Any] = [
            "metalUnavailable": false,
            "input": input,
            "identity": render(input: input, speed: 0.5, time: 0, device: device,
                               queue: queue, pipeline: pipeline),
            "yellow": render(input: input, speed: 0.5, time: 1.0 / 3.0, device: device,
                             queue: queue, pipeline: pipeline),
            "green": render(input: input, speed: 0.5, time: 2.0 / 3.0, device: device,
                            queue: queue, pipeline: pipeline),
            "wrapped": render(input: input, speed: 1, time: 1, device: device,
                              queue: queue, pipeline: pipeline),
            "audioYellow": renderOffset(
                input: input, offset: 1.0 / 6.0, device: device,
                queue: queue, pipeline: pipeline
            ),
            "audioWrappedYellow": renderOffset(
                input: input, offset: 1.0 + 1.0 / 6.0, device: device,
                queue: queue, pipeline: pipeline
            ),
            "rejections": rejections(device: device, queue: queue, pipeline: pipeline),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneWorkshopShiftHueRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-shift-hue-")
        root = Path(cls.temp.name)
        harness = root / "Harness.swift"
        binary = root / "shift-hue"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-framework", "Metal", "-o", str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def test_zero_time_and_full_wrap_preserve_rgb_and_alpha(self) -> None:
        for key in ("identity", "wrapped"):
            for actual, expected in zip(self.result[key], self.result["input"]):
                self.assertAlmostEqual(actual, expected, delta=1)

    def test_red_rotates_to_yellow_then_green(self) -> None:
        yellow = self.result["yellow"][:4]
        green = self.result["green"][:4]
        self.assertGreaterEqual(yellow[0], 254)
        self.assertGreaterEqual(yellow[1], 254)
        self.assertLessEqual(yellow[2], 1)
        self.assertEqual(yellow[3], 255)
        self.assertLessEqual(green[0], 1)
        self.assertGreaterEqual(green[1], 254)
        self.assertLessEqual(green[2], 1)
        self.assertEqual(green[3], 255)

    def test_audio_offset_can_exceed_one_and_wrap(self) -> None:
        for key in ("audioYellow", "audioWrappedYellow"):
            pixel = self.result[key][:4]
            self.assertGreaterEqual(pixel[0], 254)
            self.assertGreaterEqual(pixel[1], 254)
            self.assertLessEqual(pixel[2], 1)
            self.assertEqual(pixel[3], 255)

    def test_gray_and_alpha_are_stable(self) -> None:
        self.assertEqual(self.result["green"][-4:], [96, 96, 96, 64])
        self.assertEqual(self.result["yellow"][7], 200)
        self.assertEqual(self.result["yellow"][11], 128)

    def test_invalid_parameters_and_resources_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()), self.result["rejections"])


if __name__ == "__main__":
    unittest.main()

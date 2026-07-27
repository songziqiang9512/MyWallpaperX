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
    / "MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneSpinPipeline.swift"
)


HARNESS = r'''
import Foundation
import Metal
import simd

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

    static func fillSource(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                bytes[offset] = UInt8((x * 4) % 256)
                bytes[offset + 1] = UInt8((y * 4) % 256)
                bytes[offset + 2] = UInt8(((x / 8 + y / 8) % 2) * 255)
                bytes[offset + 3] = UInt8(128 + ((x + y) % 128))
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: size * 4
        )
        return bytes
    }

    static func render(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneSpinPipeline,
        source: MTLTexture,
        ratio: Float = 1,
        angle: Float = 0,
        phase: Float = 0,
        time: Float = 0,
        size radius: Float = 0.36,
        feather: Float = 0.04
    ) -> [UInt8] {
        let target = texture(device: device)
        let command = queue.makeCommandBuffer()!
        let uniforms = SceneSpinPipeline.Uniforms(
            center: SIMD2(0.5, 0.5),
            size: radius,
            feather: feather,
            speed: 1,
            ratio: ratio,
            angle: angle,
            phase: phase,
            time: time
        )
        guard pipeline.encode(
            source: source,
            target: target,
            uniforms: uniforms,
            commandBuffer: command
        ) else { fatalError("valid Spin render rejected") }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { fatalError("GPU command failed") }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        target.getBytes(
            &bytes,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return bytes
    }

    static func pixelDifference(_ lhs: [UInt8], _ rhs: [UInt8], x: Int, y: Int) -> Int {
        let offset = (y * size + x) * 4
        return (0..<4).reduce(0) { $0 + abs(Int(lhs[offset + $1]) - Int(rhs[offset + $1])) }
    }

    static func metrics(
        source: [UInt8],
        rotated: [UInt8],
        elliptical: [UInt8],
        phased: [UInt8]
    ) -> [String: Any] {
        var innerChanged = 0
        var outerUnchanged = 0
        var transitionMixed = 0
        var ellipseDifference = 0
        var phaseMaximumDifference = 0
        for y in 0..<size {
            for x in 0..<size {
                let dx = (Float(x) + 0.5) / Float(size) - 0.5
                let dy = (Float(y) + 0.5) / Float(size) - 0.5
                let radius = sqrt(dx * dx + dy * dy)
                let sourceDifference = pixelDifference(source, rotated, x: x, y: y)
                if radius < 0.24 && sourceDifference > 12 { innerChanged += 1 }
                if radius > 0.47 && sourceDifference <= 2 { outerUnchanged += 1 }
                if radius > 0.32 && radius < 0.40
                    && sourceDifference > 2 && sourceDifference < 500 {
                    transitionMixed += 1
                }
                if pixelDifference(rotated, elliptical, x: x, y: y) > 12 {
                    ellipseDifference += 1
                }
                phaseMaximumDifference = max(
                    phaseMaximumDifference,
                    pixelDifference(rotated, phased, x: x, y: y)
                )
            }
        }
        return [
            "innerChanged": innerChanged,
            "outerUnchanged": outerUnchanged,
            "transitionMixed": transitionMixed,
            "ellipseDifference": ellipseDifference,
            "phaseMaximumDifference": phaseMaximumDifference,
        ]
    }

    static func rejections(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneSpinPipeline
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let wrongFormat = texture(device: device, format: .rgba8Unorm)
        let wrongExtent = texture(device: device, width: size / 2)
        let mipmapped = texture(device: device, mipmapped: true)
        let noRead = texture(device: device, usage: [.renderTarget])
        let noWrite = texture(device: device, usage: [.shaderRead])
        let valid = SceneSpinPipeline.Uniforms(
            center: SIMD2(0.5, 0.5), size: 0.36, feather: 0.04,
            speed: 1, ratio: 1, angle: 0, phase: 0, time: 1
        )
        let command = queue.makeCommandBuffer()!
        func accepts(
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target,
            uniforms: SceneSpinPipeline.Uniforms = valid
        ) -> Bool {
            pipeline.encode(
                source: candidateSource,
                target: candidateTarget,
                uniforms: uniforms,
                commandBuffer: command
            )
        }
        var zeroRatio = valid; zeroRatio.ratio = 0
        var invalidTime = valid; invalidTime.time = .nan
        return [
            "same": !accepts(source: source, target: source),
            "sourceFormat": !accepts(source: wrongFormat),
            "targetFormat": !accepts(target: wrongFormat),
            "extent": !accepts(target: wrongExtent),
            "sourceMip": !accepts(source: mipmapped),
            "targetMip": !accepts(target: mipmapped),
            "sourceUsage": !accepts(source: noRead),
            "targetUsage": !accepts(target: noWrite),
            "ratio": !accepts(uniforms: zeroRatio),
            "time": !accepts(uniforms: invalidTime),
            "formatInit": SceneSpinPipeline(device: device, pixelFormat: .rgba8Unorm) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneSpinPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let source = texture(device: device)
        let input = fillSource(source)
        let rotated = render(
            device: device, queue: queue, pipeline: pipeline, source: source,
            time: .pi / 2
        )
        let elliptical = render(
            device: device, queue: queue, pipeline: pipeline, source: source,
            ratio: 0.55, angle: 0.35, time: .pi / 2
        )
        let phased = render(
            device: device, queue: queue, pipeline: pipeline, source: source,
            phase: 0.25, time: 0
        )
        let result: [String: Any] = [
            "metalUnavailable": false,
            "metrics": metrics(
                source: input,
                rotated: rotated,
                elliptical: elliptical,
                phased: phased
            ),
            "rejections": rejections(device: device, queue: queue, pipeline: pipeline),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneSpinRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-spin-rendering-")
        root = Path(cls.temp.name)
        harness = root / "Harness.swift"
        binary = root / "spin-rendering"
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

    def test_local_rotation_preserves_the_exterior_and_softens_the_boundary(self) -> None:
        metrics = self.result["metrics"]
        self.assertGreater(metrics["innerChanged"], 500, metrics)
        self.assertGreater(metrics["outerUnchanged"], 500, metrics)
        self.assertGreater(metrics["transitionMixed"], 100, metrics)

    def test_elliptical_axis_changes_the_warp(self) -> None:
        self.assertGreater(self.result["metrics"]["ellipseDifference"], 400)

    def test_phase_uses_one_turn_units(self) -> None:
        self.assertLessEqual(self.result["metrics"]["phaseMaximumDifference"], 1)

    def test_invalid_resources_and_uniforms_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()), self.result["rejections"])


if __name__ == "__main__":
    unittest.main()

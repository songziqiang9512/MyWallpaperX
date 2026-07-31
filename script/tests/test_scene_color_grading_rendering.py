#!/usr/bin/env python3

from __future__ import annotations

import json
import math
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import numpy as np


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
PIPELINE_SOURCE = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Core/SteamWorkshopScene/Effects/SceneColorGradingPipeline.swift"
)

PIXELS = [
    (0.75, 0.40, 0.20, 1.0),
    (0.30, 0.30, 0.30, 1.0),
    (0.0, 0.0, 0.0, 1.0),
    (1 / 255, 1 / 255, 1 / 255, 1.0),
    (0.20, 0.10, 0.05, 0.5),
]
CASES = [
    ("identity", 0.0, 0.0, 0.0, 1.0, (1.0, 1.0, 1.0)),
    ("luminance", 0.1, 0.0, 0.0, 1.0, (1.0, 1.0, 1.0)),
    ("darken", -0.1, 0.0, 0.0, 1.0, (1.0, 1.0, 1.0)),
    ("saturation", 0.0, 0.4, 0.0, 1.0, (1.0, 1.0, 1.0)),
    ("vibrance", 0.0, 0.0, 0.5, 1.0, (1.0, 1.0, 1.0)),
    ("opacityZero", 0.2, 0.5, 0.5, 0.0, (1.0, 1.0, 1.0)),
    ("channelRed", 0.0, 0.4, 0.0, 1.0, (1.0, 0.0, 0.0)),
]


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneColorGradingExecutionPlan {
    let luminance: Float
    let saturation: Float
    let vibrance: Float
    let opacity: Float
    let channelInfluence: SIMD3<Float>
}

@main
enum Harness {
    static let width = 5

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat = .bgra8Unorm,
        width: Int = width,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget],
        mipmapped: Bool = false
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: 1,
            mipmapped: mipmapped
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func sourceBytes() -> [UInt8] {
        let rgba: [[Float]] = [
            [0.75, 0.40, 0.20, 1.0],
            [0.30, 0.30, 0.30, 1.0],
            [0.0, 0.0, 0.0, 1.0],
            [1.0 / 255.0, 1.0 / 255.0, 1.0 / 255.0, 1.0],
            [0.20, 0.10, 0.05, 0.5],
        ]
        return rgba.flatMap { color in
            [color[2], color[1], color[0], color[3]].map {
                UInt8((Double($0) * 255.0).rounded())
            }
        }
    }

    static func read(_ texture: MTLTexture) -> [[Int]] {
        var bytes = [UInt8](repeating: 0, count: width * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, 1),
            mipmapLevel: 0
        )
        return (0 ..< width).map { index in
            let offset = index * 4
            return [
                Int(bytes[offset + 2]), Int(bytes[offset + 1]),
                Int(bytes[offset]), Int(bytes[offset + 3]),
            ]
        }
    }

    static func render(
        source: MTLTexture,
        target: MTLTexture,
        plan: SceneColorGradingExecutionPlan,
        pipeline: SceneColorGradingPipeline,
        queue: MTLCommandQueue
    ) -> [[Int]] {
        let command = queue.makeCommandBuffer()!
        guard pipeline.encode(
            source: source,
            target: target,
            plan: plan,
            commandBuffer: command
        ) else {
            fatalError("valid Color Grading fixture rejected")
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            fatalError("Color Grading fixture GPU command failed")
        }
        return read(target)
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneColorGradingPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let source = texture(device: device)
        let target = texture(device: device)
        var bytes = sourceBytes()
        source.replace(
            region: MTLRegionMake2D(0, 0, width, 1),
            mipmapLevel: 0,
            withBytes: &bytes,
            bytesPerRow: width * 4
        )
        let cases: [(String, SceneColorGradingExecutionPlan)] = [
            ("identity", .init(
                luminance: 0, saturation: 0, vibrance: 0, opacity: 1,
                channelInfluence: SIMD3(repeating: 1)
            )),
            ("luminance", .init(
                luminance: 0.1, saturation: 0, vibrance: 0, opacity: 1,
                channelInfluence: SIMD3(repeating: 1)
            )),
            ("darken", .init(
                luminance: -0.1, saturation: 0, vibrance: 0, opacity: 1,
                channelInfluence: SIMD3(repeating: 1)
            )),
            ("saturation", .init(
                luminance: 0, saturation: 0.4, vibrance: 0, opacity: 1,
                channelInfluence: SIMD3(repeating: 1)
            )),
            ("vibrance", .init(
                luminance: 0, saturation: 0, vibrance: 0.5, opacity: 1,
                channelInfluence: SIMD3(repeating: 1)
            )),
            ("opacityZero", .init(
                luminance: 0.2, saturation: 0.5, vibrance: 0.5, opacity: 0,
                channelInfluence: SIMD3(repeating: 1)
            )),
            ("channelRed", .init(
                luminance: 0, saturation: 0.4, vibrance: 0, opacity: 1,
                channelInfluence: SIMD3(1, 0, 0)
            )),
        ]
        var outputs: [String: [[Int]]] = [:]
        for (name, plan) in cases {
            outputs[name] = render(
                source: source,
                target: target,
                plan: plan,
                pipeline: pipeline,
                queue: queue
            )
        }

        let wrongFormat = texture(device: device, format: .rgba8Unorm)
        let wrongExtent = texture(device: device, width: width - 1)
        let noRead = texture(device: device, usage: [.renderTarget])
        let noWrite = texture(device: device, usage: [.shaderRead])
        let mipmapped = texture(device: device, mipmapped: true)
        let command = queue.makeCommandBuffer()!
        let valid = SceneColorGradingExecutionPlan(
            luminance: 0, saturation: 0, vibrance: 0, opacity: 1,
            channelInfluence: SIMD3(repeating: 1)
        )
        func rejected(
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target,
            plan: SceneColorGradingExecutionPlan = valid
        ) -> Bool {
            !pipeline.encode(
                source: candidateSource,
                target: candidateTarget,
                plan: plan,
                commandBuffer: command
            )
        }
        let rejections: [String: Bool] = [
            "sameTexture": rejected(source: source, target: source),
            "sourceFormat": rejected(source: wrongFormat),
            "targetFormat": rejected(target: wrongFormat),
            "extent": rejected(target: wrongExtent),
            "sourceUsage": rejected(source: noRead),
            "targetUsage": rejected(target: noWrite),
            "mipmapped": rejected(source: mipmapped),
            "luminance": rejected(plan: .init(
                luminance: .nan, saturation: 0, vibrance: 0, opacity: 1,
                channelInfluence: SIMD3(repeating: 1)
            )),
            "saturation": rejected(plan: .init(
                luminance: 0, saturation: 1.01, vibrance: 0, opacity: 1,
                channelInfluence: SIMD3(repeating: 1)
            )),
            "vibrance": rejected(plan: .init(
                luminance: 0, saturation: 0, vibrance: -1.01, opacity: 1,
                channelInfluence: SIMD3(repeating: 1)
            )),
            "opacity": rejected(plan: .init(
                luminance: 0, saturation: 0, vibrance: 0, opacity: 1.01,
                channelInfluence: SIMD3(repeating: 1)
            )),
            "influence": rejected(plan: .init(
                luminance: 0, saturation: 0, vibrance: 0, opacity: 1,
                channelInfluence: SIMD3(1, .infinity, 1)
            )),
            "pipelineFormat": SceneColorGradingPipeline(
                device: device,
                pixelFormat: .rgba8Unorm
            ) == nil,
        ]
        let result: [String: Any] = [
            "metalUnavailable": false,
            "outputs": outputs,
            "rejections": rejections,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: result,
            options: [.sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


def reference(case: tuple[str, float, float, float, float, tuple[float, ...]]):
    _, luminance, saturation, vibrance, opacity, influence = case
    result = []
    for premul_r, premul_g, premul_b, alpha in PIXELS:
        if alpha <= 1e-6:
            result.append([0, 0, 0, 0])
            continue
        base = np.clip(
            np.array([premul_r, premul_g, premul_b], dtype=np.float64) / alpha,
            0,
            1,
        )
        luma = float(np.dot(base, np.array([0.2126, 0.7152, 0.0722])))
        if luminance == 0:
            graded = base.copy()
        elif luma > 1e-6:
            graded = base * (max(luma + luminance, 0.0) / luma)
        else:
            graded = np.full(3, luminance if luminance > 0 else 0.0)
        graded = luma + (graded - luma) * (1 + saturation)
        chroma = float(np.max(graded) - np.min(graded))
        sign = 0 if vibrance == 0 else math.copysign(1, vibrance)
        weight = 1 + vibrance * (1 - sign * chroma)
        graded = luma + (graded - luma) * weight
        channel_weight = np.array(influence) * opacity
        straight = base + (graded - base) * channel_weight
        output = np.clip(straight, 0, 1) * alpha
        result.append(
            [
                int(round(output[0] * 255)),
                int(round(output[1] * 255)),
                int(round(output[2] * 255)),
                int(round(alpha * 255)),
            ]
        )
    return result


class SceneColorGradingRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-color-grading-render-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-color-grading-render"
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
                "-o",
                str(binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(binary)],
            check=True,
            capture_output=True,
            text=True,
        )
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_each_tools_two_adjustment_matches_independent_reference(self) -> None:
        for case in CASES:
            with self.subTest(case=case[0]):
                actual = np.array(self.result["outputs"][case[0]], dtype=np.int16)
                expected = np.array(reference(case), dtype=np.int16)
                self.assertLessEqual(int(np.max(np.abs(actual - expected))), 2)

    def test_opacity_zero_gray_black_and_premultiplied_boundaries(self) -> None:
        self.assertEqual(
            self.result["outputs"]["opacityZero"],
            self.result["outputs"]["identity"],
        )
        for name, pixels in self.result["outputs"].items():
            self.assertEqual(pixels[4][3], 128, name)
            self.assertLessEqual(pixels[4][0], pixels[4][3], name)
            self.assertLessEqual(pixels[4][1], pixels[4][3], name)
            self.assertLessEqual(pixels[4][2], pixels[4][3], name)
        self.assertEqual(
            self.result["outputs"]["saturation"][1],
            self.result["outputs"]["identity"][1],
        )
        self.assertEqual(
            self.result["outputs"]["vibrance"][1],
            self.result["outputs"]["identity"][1],
        )
        self.assertTrue(all(math.isfinite(channel) for row in self.result["outputs"]["luminance"] for channel in row))

    def test_invalid_gpu_contracts_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()))


if __name__ == "__main__":
    unittest.main()

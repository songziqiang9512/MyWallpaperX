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
    SOURCE_ROOT / "SceneWorkshopShadowPipeline.swift",
    SOURCE_ROOT / "SceneWorkshopShadowRenderer.swift",
]


HARNESS = r'''
import Foundation
import Metal
import simd

struct SceneWorkshopShadowExecutionPlan {
    let alpha: Float
    let color: SIMD3<Float>
    let drawBorder: Float
    let offset: SIMD2<Float>
}

@main
enum Harness {
    static let width = 5
    static let height = 5

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat = .bgra8Unorm,
        width: Int = width,
        height: Int = height
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .renderTarget]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            fatalError("texture allocation failed")
        }
        return texture
    }

    static func uploadRGBA(_ rgba: [UInt8], to texture: MTLTexture) {
        var bgra = rgba
        for index in stride(from: 0, to: rgba.count, by: 4) {
            bgra[index] = rgba[index + 2]
            bgra[index + 2] = rgba[index]
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0,
            withBytes: &bgra,
            bytesPerRow: texture.width * 4
        )
    }

    static func readRGBA(_ texture: MTLTexture) -> [UInt8] {
        var bgra = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &bgra,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        var rgba = bgra
        for index in stride(from: 0, to: bgra.count, by: 4) {
            rgba[index] = bgra[index + 2]
            rgba[index + 2] = bgra[index]
        }
        return rgba
    }

    static func pixel(_ rgba: [UInt8], x: Int, y: Int) -> [UInt8] {
        let index = (y * width + x) * 4
        return Array(rgba[index..<(index + 4)])
    }

    static func pixels(_ values: [(Int, Int, [UInt8])]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: width * height * 4)
        for (x, y, rgba) in values {
            let index = (y * width + x) * 4
            result.replaceSubrange(index..<(index + 4), with: rgba)
        }
        return result
    }

    static func render(
        input: [UInt8],
        plan: SceneWorkshopShadowExecutionPlan,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWorkshopShadowPipeline
    ) -> (output: [UInt8], rendererReturnedOutput: Bool) {
        let source = texture(device: device)
        let target = texture(device: device)
        uploadRGBA(input, to: source)
        guard let command = queue.makeCommandBuffer() else {
            fatalError("command allocation failed")
        }
        let rendered = SceneWorkshopShadowRenderer.render(
            plan: plan,
            inputTexture: source,
            outputTexture: target,
            pipeline: pipeline,
            commandBuffer: command
        )
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            fatalError("shadow command failed: \(String(describing: command.error))")
        }
        return (readRGBA(target), rendered === target)
    }

    static func rejectionChecks(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWorkshopShadowPipeline
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let rgbaTarget = texture(device: device, format: .rgba8Unorm)
        let shortTarget = texture(device: device, width: width - 1)
        guard let command = queue.makeCommandBuffer() else {
            fatalError("command allocation failed")
        }
        let valid = SceneWorkshopShadowExecutionPlan(
            alpha: 0.5,
            color: SIMD3(0, 0, 0),
            drawBorder: 0.5,
            offset: SIMD2(2, -2)
        )
        func encoded(_ plan: SceneWorkshopShadowExecutionPlan) -> Bool {
            pipeline.encode(
                source: source,
                target: target,
                plan: plan,
                commandBuffer: command
            )
        }
        return [
            "sameTexture": !pipeline.encode(
                source: source, target: source, plan: valid, commandBuffer: command
            ),
            "wrongFormat": !pipeline.encode(
                source: source, target: rgbaTarget, plan: valid, commandBuffer: command
            ),
            "wrongExtent": !pipeline.encode(
                source: source, target: shortTarget, plan: valid, commandBuffer: command
            ),
            "nanAlpha": !encoded(.init(
                alpha: .nan, color: SIMD3(0, 0, 0), drawBorder: 0.5,
                offset: SIMD2(2, -2)
            )),
            "invalidColor": !encoded(.init(
                alpha: 0.5, color: SIMD3(0, 0, 1.1), drawBorder: 0.5,
                offset: SIMD2(2, -2)
            )),
            "invalidBorder": !encoded(.init(
                alpha: 0.5, color: SIMD3(0, 0, 0), drawBorder: -0.1,
                offset: SIMD2(2, -2)
            )),
            "infiniteOffset": !encoded(.init(
                alpha: 0.5, color: SIMD3(0, 0, 0), drawBorder: 0.5,
                offset: SIMD2(.infinity, 0)
            )),
            "wrongPipelineFormat": SceneWorkshopShadowPipeline(
                device: device, pixelFormat: .rgba8Unorm
            ) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneWorkshopShadowPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let plan = SceneWorkshopShadowExecutionPlan(
            alpha: 0.5,
            color: SIMD3(0, 0, 0),
            drawBorder: 0.5,
            offset: SIMD2(20, 0)
        )
        let impulseInput = pixels([(2, 2, [255, 255, 255, 255])])
        let impulse = render(
            input: impulseInput, plan: plan, device: device, queue: queue,
            pipeline: pipeline
        )
        let partialInput = pixels([
            (2, 2, [102, 0, 0, 102]),
            (3, 2, [255, 255, 255, 255]),
        ])
        let partial = render(
            input: partialInput, plan: plan, device: device, queue: queue,
            pipeline: pipeline
        )
        let boundaryInput = pixels([(4, 2, [64, 0, 0, 64])])
        let boundary = render(
            input: boundaryInput, plan: plan, device: device, queue: queue,
            pipeline: pipeline
        )
        let zeroAlpha = render(
            input: partialInput,
            plan: .init(
                alpha: 0,
                color: SIMD3(0, 0, 0),
                drawBorder: 0.5,
                offset: SIMD2(20, 0)
            ),
            device: device,
            queue: queue,
            pipeline: pipeline
        )
        let result: [String: Any] = [
            "metalUnavailable": false,
            "impulseShadow": pixel(impulse.output, x: 1, y: 2),
            "impulseSource": pixel(impulse.output, x: 2, y: 2),
            "partialShadow": pixel(partial.output, x: 2, y: 2),
            "boundary": pixel(boundary.output, x: 4, y: 2),
            "zeroAlphaInput": partialInput,
            "zeroAlphaOutput": zeroAlpha.output,
            "premultiplied": partial.output.enumerated().allSatisfy { index, value in
                index % 4 == 3 || value <= partial.output[(index / 4) * 4 + 3]
            },
            "rendererReturnedOutput": impulse.rendererReturnedOutput,
            "rejections": rejectionChecks(
                device: device, queue: queue, pipeline: pipeline
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneWorkshopShadowRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-scene-workshop-shadow-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-workshop-shadow-rendering"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Metal",
                "-o", str(binary),
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
        cls.temporary_directory.cleanup()

    def test_offset_creates_black_half_alpha_shadow_and_preserves_source(self) -> None:
        self.assertEqual(self.result["impulseShadow"], [0, 0, 0, 128])
        self.assertEqual(self.result["impulseSource"], [255, 255, 255, 255])
        self.assertTrue(self.result["rendererReturnedOutput"])

    def test_border_branch_matches_authored_formula_in_premultiplied_space(self) -> None:
        actual = self.result["partialShadow"]
        expected = [115, 0, 0, 230]
        for value, reference in zip(actual, expected):
            self.assertAlmostEqual(value, reference, delta=1)
        self.assertTrue(self.result["premultiplied"])

    def test_clamp_uv_addressing_extends_edge_pixels(self) -> None:
        expected = [48, 0, 0, 96]
        for value, reference in zip(self.result["boundary"], expected):
            self.assertAlmostEqual(value, reference, delta=1)

    def test_zero_alpha_is_identity(self) -> None:
        for actual, reference in zip(
            self.result["zeroAlphaOutput"], self.result["zeroAlphaInput"]
        ):
            self.assertAlmostEqual(actual, reference, delta=1)

    def test_invalid_resources_and_uniforms_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()))


if __name__ == "__main__":
    unittest.main()

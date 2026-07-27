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
    SOURCE_ROOT / "Effects/SceneColorKeyPipeline.swift",
    SOURCE_ROOT / "Effects/SceneColorKeyRenderer.swift",
]


HARNESS = r'''
import Foundation
import Metal

struct SceneColorKeyExecutionPlan {
    let keyAlpha: Float
    let fuzziness: Float
    let tolerance: Float
    let keyColor: SIMD3<Float>
    let invert: Bool
    let flatten: Bool
}

@main
enum Harness {
    static let width = 2
    static let height = 2

    static func texture(
        device: MTLDevice,
        format: MTLPixelFormat = .bgra8Unorm,
        width: Int = width,
        mipmapped: Bool = false,
        usage: MTLTextureUsage = [.shaderRead, .renderTarget]
    ) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: width,
            height: height,
            mipmapped: mipmapped
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
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

    static func plan(
        alpha: Float = 0,
        fuzziness: Float = 0,
        tolerance: Float = 0.1,
        color: SIMD3<Float> = .zero,
        invert: Bool = false,
        flatten: Bool = false
    ) -> SceneColorKeyExecutionPlan {
        SceneColorKeyExecutionPlan(
            keyAlpha: alpha,
            fuzziness: fuzziness,
            tolerance: tolerance,
            keyColor: color,
            invert: invert,
            flatten: flatten
        )
    }

    static func render(
        input: [UInt8],
        plan: SceneColorKeyExecutionPlan,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneColorKeyPipeline
    ) -> [UInt8] {
        let source = texture(device: device)
        let target = texture(device: device)
        uploadRGBA(input, to: source)
        let command = queue.makeCommandBuffer()!
        guard SceneColorKeyRenderer.render(
            plan: plan,
            inputTexture: source,
            outputTexture: target,
            pipeline: pipeline,
            commandBuffer: command
        ) === target else {
            fatalError("renderer rejected valid plan")
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { fatalError("GPU command failed") }
        return readRGBA(target)
    }

    static func rejectionChecks(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneColorKeyPipeline
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
            _ candidate: SceneColorKeyExecutionPlan = plan(),
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target
        ) -> Bool {
            pipeline.encode(
                source: candidateSource,
                target: candidateTarget,
                plan: candidate,
                commandBuffer: command
            )
        }
        return [
            "sameTexture": !accepts(source: source, target: source),
            "wrongSourceFormat": !accepts(source: wrongFormat),
            "wrongTargetFormat": !accepts(target: wrongFormat),
            "wrongExtent": !accepts(target: wrongExtent),
            "mipSource": !accepts(source: mipmapped),
            "mipTarget": !accepts(target: mipmapped),
            "sourceUsage": !accepts(source: noRead),
            "targetUsage": !accepts(target: noWrite),
            "alphaNaN": !accepts(plan(alpha: .nan)),
            "alphaRange": !accepts(plan(alpha: 1.01)),
            "fuzzRange": !accepts(plan(fuzziness: 3.01)),
            "toleranceRange": !accepts(plan(tolerance: -0.01)),
            "colorRange": !accepts(plan(color: SIMD3(1.01, 0, 0))),
            "wrongPipelineFormat": SceneColorKeyPipeline(
                device: device,
                pixelFormat: .rgba8Unorm
            ) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneColorKeyPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let input: [UInt8] = [
            0, 0, 0, 255,
            255, 0, 0, 255,
            0, 255, 0, 128,
            255, 255, 255, 64,
        ]
        let result: [String: Any] = [
            "metalUnavailable": false,
            "input": input,
            "keyed": render(input: input, plan: plan(), device: device, queue: queue,
                            pipeline: pipeline),
            "quarter": render(input: input, plan: plan(alpha: 0.25), device: device,
                              queue: queue, pipeline: pipeline),
            "inverted": render(input: input, plan: plan(invert: true), device: device,
                               queue: queue, pipeline: pipeline),
            "flattenedRed": render(
                input: input,
                plan: plan(alpha: 0.25, color: SIMD3(1, 0, 0), flatten: true),
                device: device,
                queue: queue,
                pipeline: pipeline
            ),
            "rejections": rejectionChecks(device: device, queue: queue, pipeline: pipeline),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneColorKeyRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-colorkey-")
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-colorkey"
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
        cls.temporary_directory.cleanup()

    def test_key_color_clears_alpha_without_changing_rgb(self) -> None:
        keyed = self.result["keyed"]
        self.assertEqual(keyed[:3], self.result["input"][:3])
        self.assertEqual(keyed[3], 0)
        self.assertEqual(keyed[4:], self.result["input"][4:])

    def test_key_alpha_is_mixed_only_for_matching_pixels(self) -> None:
        quarter = self.result["quarter"]
        self.assertAlmostEqual(quarter[3], 64, delta=1)
        self.assertEqual(quarter[7:], self.result["input"][7:])

    def test_invert_reverses_key_selection(self) -> None:
        inverted = self.result["inverted"]
        self.assertEqual(inverted[3], 255)
        self.assertEqual(inverted[7], 0)
        self.assertEqual(inverted[11], 0)
        self.assertEqual(inverted[15], 0)

    def test_flatten_multiplies_rgb_by_result_alpha(self) -> None:
        flattened = self.result["flattenedRed"]
        self.assertAlmostEqual(flattened[4], 64, delta=1)
        self.assertEqual(flattened[5:7], [0, 0])
        self.assertAlmostEqual(flattened[7], 64, delta=1)

    def test_invalid_parameters_and_resources_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()), self.result["rejections"])


if __name__ == "__main__":
    unittest.main()

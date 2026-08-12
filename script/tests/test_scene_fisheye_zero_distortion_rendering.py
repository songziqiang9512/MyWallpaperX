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
PIPELINE_SOURCE = (
    SOURCE_ROOT / "Effects/SceneFisheyeZeroDistortionPipeline.swift"
)
CHAIN_RENDERER_SOURCE = (
    SOURCE_ROOT / "RenderGraph/EffectExecution/SceneEffectStageRenderer+Transform.swift"
)


HARNESS = r'''
import Foundation
import Metal

@main
enum Harness {
    static let width = 64
    static let height = 64

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
            height: height,
            mipmapped: mipmapped
        )
        descriptor.storageMode = .shared
        descriptor.usage = usage
        return device.makeTexture(descriptor: descriptor)!
    }

    static func fill(_ texture: MTLTexture) {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: &pixels,
            bytesPerRow: width * 4
        )
    }

    static func pixels(_ texture: MTLTexture) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &result,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return result
    }

    static func rgba(_ pixels: [UInt8], x: Int, y: Int) -> [Int] {
        let offset = (y * width + x) * 4
        return [
            Int(pixels[offset + 2]),
            Int(pixels[offset + 1]),
            Int(pixels[offset]),
            Int(pixels[offset + 3]),
        ]
    }

    static func render(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneFisheyeZeroDistortionPipeline
    ) -> [UInt8] {
        let source = texture(device: device)
        let target = texture(device: device)
        fill(source)
        let command = queue.makeCommandBuffer()!
        guard pipeline.encode(
            source: source,
            target: target,
            uniforms: .init(center: SIMD2(0.5, 0.5), size: 1.2),
            commandBuffer: command
        ) else {
            fatalError("valid zero-distortion Fisheye render rejected")
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            fatalError("zero-distortion Fisheye GPU command failed")
        }
        return pixels(target)
    }

    static func rejections(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneFisheyeZeroDistortionPipeline
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let wrongFormat = texture(device: device, format: .rgba8Unorm)
        let wrongExtent = texture(device: device, width: width / 2)
        let noRead = texture(device: device, usage: [.renderTarget])
        let noWrite = texture(device: device, usage: [.shaderRead])
        let mipmapped = texture(device: device, mipmapped: true)
        let command = queue.makeCommandBuffer()!
        let valid = SceneFisheyeZeroDistortionPipeline.Uniforms(
            center: SIMD2(0.5, 0.5),
            size: 1.2
        )
        func accepts(
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target,
            uniforms: SceneFisheyeZeroDistortionPipeline.Uniforms = valid
        ) -> Bool {
            pipeline.encode(
                source: candidateSource,
                target: candidateTarget,
                uniforms: uniforms,
                commandBuffer: command
            )
        }
        return [
            "sameTexture": !accepts(source: source, target: source),
            "sourceFormat": !accepts(source: wrongFormat),
            "targetFormat": !accepts(target: wrongFormat),
            "extent": !accepts(target: wrongExtent),
            "sourceUsage": !accepts(source: noRead),
            "targetUsage": !accepts(target: noWrite),
            "mipmapped": !accepts(source: mipmapped),
            "centerNaN": !accepts(uniforms: .init(
                center: SIMD2(.nan, 0.5),
                size: 1.2
            )),
            "centerRange": !accepts(uniforms: .init(
                center: SIMD2(1.01, 0.5),
                size: 1.2
            )),
            "sizeZero": !accepts(uniforms: .init(
                center: SIMD2(0.5, 0.5),
                size: 0
            )),
            "sizeNaN": !accepts(uniforms: .init(
                center: SIMD2(0.5, 0.5),
                size: .nan
            )),
            "sizeBound": !accepts(uniforms: .init(
                center: SIMD2(0.5, 0.5),
                size: 4.01
            )),
            "pipelineFormat": SceneFisheyeZeroDistortionPipeline(
                device: device,
                pixelFormat: .rgba8Unorm
            ) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneFisheyeZeroDistortionPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let output = render(device: device, queue: queue, pipeline: pipeline)
        let result: [String: Any] = [
            "metalUnavailable": false,
            "center": rgba(output, x: 32, y: 32),
            "edgeCenter": rgba(output, x: 63, y: 32),
            "corner": rgba(output, x: 63, y: 63),
            "insideBoundary": rgba(output, x: 58, y: 58),
            "outsideBoundary": rgba(output, x: 59, y: 59),
            "rejections": rejections(
                device: device,
                queue: queue,
                pipeline: pipeline
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


class SceneFisheyeZeroDistortionRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temporary_directory = tempfile.TemporaryDirectory(
            prefix="mwx-fisheye-zero-distortion-render-"
        )
        root = Path(cls.temporary_directory.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "scene-fisheye-zero-distortion-render"
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

    def test_center_and_horizontal_edge_are_preserved(self) -> None:
        self.assertEqual(self.result["center"], [255, 255, 255, 255])
        self.assertEqual(self.result["edgeCenter"], [255, 255, 255, 255])

    def test_corner_is_transparent_with_an_explicit_hard_radial_edge(self) -> None:
        self.assertEqual(self.result["corner"], [0, 0, 0, 0])
        self.assertEqual(self.result["insideBoundary"], [255, 255, 255, 255])
        self.assertEqual(self.result["outsideBoundary"], [0, 0, 0, 0])

    def test_invalid_resources_and_uniforms_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()))

    def test_chain_renderer_captures_source_before_radial_clip(self) -> None:
        source = CHAIN_RENDERER_SOURCE.read_text(encoding="utf-8")
        fisheye_case = source.split(
            "case .fisheyeZeroDistortion", maxsplit=1
        )[1].split("default:", maxsplit=1)[0]
        self.assertIn("target: targets.inputTexture", fisheye_case)
        self.assertIn("fisheyePipeline.encode(", fisheye_case)
        self.assertIn("source: targets.inputTexture", fisheye_case)
        self.assertIn("target: targets.outputTexture", fisheye_case)


if __name__ == "__main__":
    unittest.main()

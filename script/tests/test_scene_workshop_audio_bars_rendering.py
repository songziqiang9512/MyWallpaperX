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
    SOURCE_ROOT / "Runtime/SceneAudioSpectrum.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopAudioBarsPipeline.swift",
]


HARNESS = r'''
import Foundation
import Metal

@main
enum Harness {
    static let size = 128

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

    static func pixels(_ texture: MTLTexture) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(
            &result,
            bytesPerRow: size * 4,
            from: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0
        )
        return result
    }

    static func render(
        shape: Int,
        spectrum: SceneAudioSpectrumSnapshot,
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWorkshopAudioBarsPipeline
    ) -> [UInt8] {
        let source = texture(device: device)
        let target = texture(device: device)
        let command = queue.makeCommandBuffer()!
        guard pipeline.encode(
            source: source,
            target: target,
            shape: shape,
            spectrum: spectrum,
            commandBuffer: command
        ) else { fatalError("valid Audio Bars render rejected") }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { fatalError("GPU command failed") }
        return pixels(target)
    }

    static func metrics(_ pixels: [UInt8]) -> [String: Int] {
        var visible = 0
        var magenta = 0
        var transparentRGB = 0
        var center = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let b = Int(pixels[offset])
            let g = Int(pixels[offset + 1])
            let r = Int(pixels[offset + 2])
            let a = Int(pixels[offset + 3])
            if a > 0 { visible += 1 }
            if a > 0 && r > 0 && b > 0 && g == 0 { magenta += 1 }
            if a == 0 && (r != 0 || g != 0 || b != 0) { transparentRGB += 1 }
        }
        let centerOffset = ((size / 2) * size + size / 2) * 4
        center = Int(pixels[centerOffset + 3])
        return [
            "visible": visible,
            "magenta": magenta,
            "transparentRGB": transparentRGB,
            "centerAlpha": center,
        ]
    }

    static func invalidResources(
        device: MTLDevice,
        queue: MTLCommandQueue,
        pipeline: SceneWorkshopAudioBarsPipeline,
        spectrum: SceneAudioSpectrumSnapshot
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let wrongFormat = texture(device: device, format: .rgba8Unorm)
        let wrongExtent = texture(device: device, width: size / 2)
        let mipmapped = texture(device: device, mipmapped: true)
        let noRead = texture(device: device, usage: [.renderTarget])
        let noWrite = texture(device: device, usage: [.shaderRead])
        let command = queue.makeCommandBuffer()!
        func accepts(
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target,
            shape: Int = 4
        ) -> Bool {
            pipeline.encode(
                source: candidateSource,
                target: candidateTarget,
                shape: shape,
                spectrum: spectrum,
                commandBuffer: command
            )
        }
        return [
            "shape": !accepts(shape: 3),
            "same": !accepts(source: source, target: source),
            "sourceFormat": !accepts(source: wrongFormat),
            "targetFormat": !accepts(target: wrongFormat),
            "extent": !accepts(target: wrongExtent),
            "sourceMip": !accepts(source: mipmapped),
            "targetMip": !accepts(target: mipmapped),
            "sourceUsage": !accepts(source: noRead),
            "targetUsage": !accepts(target: noWrite),
            "formatInit": SceneWorkshopAudioBarsPipeline(
                device: device, pixelFormat: .rgba8Unorm
            ) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneWorkshopAudioBarsPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let bands = Array(repeating: Float(1), count: 64)
        let active = SceneAudioSpectrumSnapshot(
            left: Array(repeating: 0, count: 16),
            right: Array(repeating: 0, count: 16),
            left64: bands,
            right64: bands,
            generation: 1
        )
        let innerPixels = render(
            shape: 4, spectrum: active, device: device, queue: queue, pipeline: pipeline
        )
        let outerPixels = render(
            shape: 5, spectrum: active, device: device, queue: queue, pipeline: pipeline
        )
        let silentPixels = render(
            shape: 4, spectrum: .silent, device: device, queue: queue, pipeline: pipeline
        )
        let result: [String: Any] = [
            "metalUnavailable": false,
            "silent": metrics(silentPixels),
            "inner": metrics(innerPixels),
            "outer": metrics(outerPixels),
            "shapesDiffer": innerPixels != outerPixels,
            "rejections": invalidResources(
                device: device, queue: queue, pipeline: pipeline, spectrum: active
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneWorkshopAudioBarsRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-audio-bars-")
        root = Path(cls.temp.name)
        harness = root / "Harness.swift"
        binary = root / "audio-bars"
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
        completed = subprocess.run(
            [str(binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)
        if cls.result["metalUnavailable"]:
            raise unittest.SkipTest("Metal is unavailable")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def test_silence_is_transparent(self) -> None:
        self.assertEqual(self.result["silent"]["visible"], 0)
        self.assertEqual(self.result["silent"]["transparentRGB"], 0)

    def test_native_64_band_input_draws_segmented_magenta_pixels(self) -> None:
        for shape in ("inner", "outer"):
            self.assertGreater(self.result[shape]["visible"], 0, self.result[shape])
            self.assertEqual(self.result[shape]["transparentRGB"], 0, self.result[shape])
            self.assertEqual(
                self.result[shape]["visible"],
                self.result[shape]["magenta"],
                self.result[shape],
            )

    def test_inner_and_outer_shapes_differ(self) -> None:
        self.assertTrue(self.result["shapesDiffer"])

    def test_invalid_shape_and_resources_fail_closed(self) -> None:
        self.assertTrue(all(self.result["rejections"].values()), self.result["rejections"])


if __name__ == "__main__":
    unittest.main()

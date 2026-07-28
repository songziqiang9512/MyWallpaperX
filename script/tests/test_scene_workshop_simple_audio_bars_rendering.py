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
    SOURCE_ROOT / "Format/SceneJSONValue.swift",
    SOURCE_ROOT / "Properties/SceneDynamicSnapshot.swift",
    SOURCE_ROOT / "Runtime/SceneAudioSpectrum.swift",
    SOURCE_ROOT / "RenderGraph/SceneAuthoredEffectRenderPlan.swift",
    SOURCE_ROOT / "RenderGraph/SceneWorkshopAudioBarsExecutionPlan.swift",
    SOURCE_ROOT / "Effects/SceneWorkshopSimpleAudioBarsPipeline.swift",
]


HARNESS = r'''
import Foundation
import Metal

@main
enum Harness {
    typealias Parameters = SceneWorkshopAudioBarsExecutionPlan.SimpleParameters
    static let width = 128
    static let height = 64

    static func texture(
        device: MTLDevice,
        width: Int = width,
        format: MTLPixelFormat = .bgra8Unorm,
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

    static func parameters(
        profile: Parameters.Profile,
        color: SIMD3<Float> = SIMD3(1, 0, 0),
        spacing: Float = 0.3,
        lower: Float = 0,
        upper: Float = 0.8,
        opacity: Float = 0.75,
        barCount: Int = 16
    ) -> Parameters {
        .init(
            profile: profile,
            barCount: barCount,
            staticOrFallbackColor: color,
            colorBinding: nil,
            barSpacing: spacing,
            lowerBound: lower,
            upperBound: upper,
            opacity: opacity
        )
    }

    static func spectrum() -> SceneAudioSpectrumSnapshot {
        let medium = (0 ..< 32).map { index in
            index.isMultiple(of: 2) ? Float(1) : Float(0.25)
        }
        let extended = (0 ..< 64).map { index in
            index.isMultiple(of: 3) ? Float(0.8) : Float(0.1)
        }
        return .init(
            left: Array(repeating: 0, count: 16),
            right: Array(repeating: 0, count: 16),
            left32: medium,
            right32: medium,
            left64: extended,
            right64: extended,
            generation: 1
        )
    }

    static func spectrum32(
        fill: Float = 0,
        activeBand: Int? = nil
    ) -> SceneAudioSpectrumSnapshot {
        var medium = Array(repeating: fill, count: 32)
        if let activeBand {
            medium[activeBand] = 1
        }
        return .init(
            left: Array(repeating: 0, count: 16),
            right: Array(repeating: 0, count: 16),
            left32: medium,
            right32: medium,
            left64: Array(repeating: 0, count: 64),
            right64: Array(repeating: 0, count: 64),
            generation: 1
        )
    }

    static func pixels(_ texture: MTLTexture) -> [UInt8] {
        var result = Array(repeating: UInt8(0), count: width * height * 4)
        texture.getBytes(
            &result,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        return result
    }

    static func alpha(_ pixels: [UInt8], x: Int, y: Int) -> Int {
        Int(pixels[(y * width + x) * 4 + 3])
    }

    static func render(
        pipeline: SceneWorkshopSimpleAudioBarsPipeline,
        queue: MTLCommandQueue,
        device: MTLDevice,
        parameters: Parameters,
        color: SIMD3<Float>,
        spectrum: SceneAudioSpectrumSnapshot
    ) -> [UInt8] {
        let source = texture(device: device)
        let target = texture(device: device)
        let command = queue.makeCommandBuffer()!
        guard pipeline.encode(
            source: source,
            target: target,
            parameters: parameters,
            color: color,
            spectrum: spectrum,
            commandBuffer: command
        ) else {
            fatalError("valid Simple Audio Bars render rejected")
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            fatalError("Simple Audio Bars GPU command failed")
        }
        return pixels(target)
    }

    static func metrics(_ pixels: [UInt8]) -> [String: Int] {
        var visible = 0
        var transparentRGB = 0
        var nonPremultiplied = 0
        var red = 0
        var green = 0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let blue = Int(pixels[offset])
            let greenValue = Int(pixels[offset + 1])
            let redValue = Int(pixels[offset + 2])
            let alpha = Int(pixels[offset + 3])
            if alpha > 0 { visible += 1 }
            if alpha == 0 && (redValue != 0 || greenValue != 0 || blue != 0) {
                transparentRGB += 1
            }
            if redValue > alpha || greenValue > alpha || blue > alpha {
                nonPremultiplied += 1
            }
            if redValue > greenValue { red += 1 }
            if greenValue > redValue { green += 1 }
        }
        return [
            "visible": visible,
            "transparentRGB": transparentRGB,
            "nonPremultiplied": nonPremultiplied,
            "red": red,
            "green": green,
        ]
    }

    static func rejections(
        pipeline: SceneWorkshopSimpleAudioBarsPipeline,
        queue: MTLCommandQueue,
        device: MTLDevice
    ) -> [String: Bool] {
        let source = texture(device: device)
        let target = texture(device: device)
        let wrongFormat = texture(device: device, format: .rgba8Unorm)
        let wrongExtent = texture(device: device, width: width / 2)
        let noRead = texture(device: device, usage: [.renderTarget])
        let command = queue.makeCommandBuffer()!
        let validParameters = parameters(profile: .bottomReplace32ClipLow)
        func accepts(
            source candidateSource: MTLTexture = source,
            target candidateTarget: MTLTexture = target,
            parameters candidateParameters: Parameters = validParameters,
            color: SIMD3<Float> = SIMD3(1, 0, 0)
        ) -> Bool {
            pipeline.encode(
                source: candidateSource,
                target: candidateTarget,
                parameters: candidateParameters,
                color: color,
                spectrum: spectrum(),
                commandBuffer: command
            )
        }
        return [
            "same": !accepts(source: source, target: source),
            "format": !accepts(source: wrongFormat),
            "extent": !accepts(target: wrongExtent),
            "usage": !accepts(source: noRead),
            "count": !accepts(parameters: parameters(
                profile: .bottomReplace32ClipLow,
                barCount: 0
            )),
            "bounds": !accepts(parameters: parameters(
                profile: .bottomReplace32ClipLow,
                lower: 0.8,
                upper: 0.2
            )),
            "color": !accepts(color: SIMD3(2, 0, 0)),
            "formatInit": SceneWorkshopSimpleAudioBarsPipeline(
                device: device,
                pixelFormat: .rgba8Unorm
            ) == nil,
        ]
    }

    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let pipeline = SceneWorkshopSimpleAudioBarsPipeline(device: device) else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let active = spectrum()
        let profile32 = parameters(
            profile: .bottomReplace32ClipLow,
            lower: 0.2
        )
        let profile64 = parameters(profile: .bottomReplace64ClipHigh)
        let pixels32 = render(
            pipeline: pipeline,
            queue: queue,
            device: device,
            parameters: profile32,
            color: SIMD3(1, 0, 0),
            spectrum: active
        )
        let pixels64 = render(
            pipeline: pipeline,
            queue: queue,
            device: device,
            parameters: profile64,
            color: SIMD3(0, 1, 0),
            spectrum: active
        )
        let silent = render(
            pipeline: pipeline,
            queue: queue,
            device: device,
            parameters: profile64,
            color: SIMD3(1, 0, 0),
            spectrum: .silent
        )
        let centeredSpacing = render(
            pipeline: pipeline,
            queue: queue,
            device: device,
            parameters: parameters(
                profile: .bottomReplace32ClipLow,
                spacing: 0.5,
                lower: 0,
                upper: 1,
                opacity: 1,
                barCount: 2
            ),
            color: SIMD3(1, 0, 0),
            spectrum: spectrum32(fill: 1)
        )
        let firstBand = render(
            pipeline: pipeline,
            queue: queue,
            device: device,
            parameters: parameters(
                profile: .bottomReplace32ClipLow,
                spacing: 0,
                lower: 0,
                upper: 1,
                opacity: 1,
                barCount: 3
            ),
            color: SIMD3(1, 0, 0),
            spectrum: spectrum32(activeBand: 0)
        )
        let interpolatedBand = render(
            pipeline: pipeline,
            queue: queue,
            device: device,
            parameters: parameters(
                profile: .bottomReplace32ClipLow,
                spacing: 0,
                lower: 0,
                upper: 1,
                opacity: 1,
                barCount: 3
            ),
            color: SIMD3(1, 0, 0),
            spectrum: spectrum32(activeBand: 11)
        )
        let result: [String: Any] = [
            "metalUnavailable": false,
            "profile32": metrics(pixels32),
            "profile64": metrics(pixels64),
            "silent": metrics(silent),
            "centeredSpacing": [
                "leftGapAlpha": alpha(centeredSpacing, x: 6, y: 63),
                "centerAlpha": alpha(centeredSpacing, x: 32, y: 63),
                "rightGapAlpha": alpha(centeredSpacing, x: 58, y: 63),
            ],
            "frequencyMapping": [
                "firstBandAlpha": alpha(firstBand, x: 20, y: 20),
                "interpolatedAlpha": alpha(interpolatedBand, x: 64, y: 20),
                "aboveInterpolatedAlpha": alpha(interpolatedBand, x: 64, y: 10),
            ],
            "profilesDiffer": pixels32 != pixels64,
            "rejections": rejections(
                pipeline: pipeline,
                queue: queue,
                device: device
            ),
        ]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneWorkshopSimpleAudioBarsRenderingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-simple-audio-bars-gpu-")
        root = Path(cls.temp.name)
        harness = root / "Harness.swift"
        binary = root / "simple-audio-bars-gpu"
        harness.write_text(HARNESS, encoding="utf-8")
        compilation = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
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
        cls.temp.cleanup()

    def test_silence_is_stably_transparent(self) -> None:
        self.assertEqual(self.result["silent"]["visible"], 0)
        self.assertEqual(self.result["silent"]["transparentRGB"], 0)

    def test_32_and_64_band_profiles_draw_premultiplied_color(self) -> None:
        self.assertGreater(self.result["profile32"]["visible"], 0)
        self.assertGreater(self.result["profile64"]["visible"], 0)
        self.assertGreater(self.result["profile32"]["red"], 0)
        self.assertGreater(self.result["profile64"]["green"], 0)
        for profile in ("profile32", "profile64"):
            self.assertEqual(self.result[profile]["transparentRGB"], 0)
            self.assertEqual(self.result[profile]["nonPremultiplied"], 0)
        self.assertTrue(self.result["profilesDiffer"])

    def test_bar_spacing_is_centered_within_each_slot(self) -> None:
        spacing = self.result["centeredSpacing"]
        self.assertEqual(spacing["leftGapAlpha"], 0)
        self.assertGreater(spacing["centerAlpha"], 0)
        self.assertEqual(spacing["rightGapAlpha"], 0)

    def test_bar_frequency_starts_at_the_slot_and_interpolates(self) -> None:
        frequency = self.result["frequencyMapping"]
        self.assertGreater(frequency["firstBandAlpha"], 0)
        self.assertGreater(frequency["interpolatedAlpha"], 0)
        self.assertEqual(frequency["aboveInterpolatedAlpha"], 0)

    def test_invalid_parameters_and_resources_fail_closed(self) -> None:
        self.assertTrue(
            all(self.result["rejections"].values()),
            self.result["rejections"],
        )


if __name__ == "__main__":
    unittest.main()

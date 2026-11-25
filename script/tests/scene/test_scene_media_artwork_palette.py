#!/usr/bin/env python3
"""Validate the stateless palette with owned images and real ImageIO decoding."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "MyWallpaperX/Core/Playback/SystemMedia/SystemMediaArtworkPalette.swift"

HARNESS = r'''
import CoreGraphics
import Foundation
import ImageIO

nonisolated enum Fixtures {
    static let red: [UInt8] = [255, 0, 0, 255]
    static let green: [UInt8] = [0, 255, 0, 255]
    static let blue: [UInt8] = [0, 0, 255, 255]
    static let black: [UInt8] = [0, 0, 0, 255]
    static let white: [UInt8] = [255, 255, 255, 255]

    static func png(width: Int, height: Int, pixels: [[UInt8]], linear: Bool = false) -> Data {
        precondition(pixels.count == width * height && pixels.allSatisfy { $0.count == 4 })
        let data = Data(pixels.flatMap { $0 })
        let provider = CGDataProvider(data: data as CFData)!
        let space = CGColorSpace(name: linear ? CGColorSpace.linearSRGB : CGColorSpace.sRGB)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return encode(image)
    }

    static func grayPNG(width: Int, height: Int) -> Data {
        let data = Data(repeating: 128, count: width * height)
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: CGDataProvider(data: data as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
        return encode(image)
    }

    static func encode(_ image: CGImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func regions(_ colors: [([UInt8], Int)]) -> Data {
        let pixels = colors.flatMap { Array(repeating: $0.0, count: $0.1) }
        return png(width: pixels.count, height: 1, pixels: pixels)
    }
}

nonisolated enum PaletteCases {
    static let red = SIMD3<Double>(1, 0, 0)
    static let green = SIMD3<Double>(0, 1, 0)
    static let blue = SIMD3<Double>(0, 0, 1)
    static let black = SIMD3<Double>.zero
    static let white = SIMD3<Double>(repeating: 1)

    static func close(_ actual: SIMD3<Double>, _ expected: SIMD3<Double>, tolerance: Double = 0.012) {
        for index in 0..<3 {
            precondition(abs(actual[index] - expected[index]) <= tolerance,
                         "color \(actual) differs from \(expected)")
        }
    }

    static func luminance(_ color: SIMD3<Double>) -> Double {
        var linear = SIMD3<Double>.zero
        for index in 0..<3 {
            let c = color[index]
            linear[index] = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return linear.x * 0.2126 + linear.y * 0.7152 + linear.z * 0.0722
    }

    static func contrast(_ first: SIMD3<Double>, _ second: SIMD3<Double>) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    static func extract(_ data: Data) -> SystemMediaArtworkPalette {
        guard let palette = SystemMediaArtworkPalette.extract(from: data) else {
            preconditionFailure("owned valid PNG rejected")
        }
        let colors = [palette.primaryColor, palette.secondaryColor, palette.tertiaryColor,
                      palette.textColor, palette.highContrastColor]
        for color in colors {
            for index in 0..<3 { precondition(color[index].isFinite && (0...1).contains(color[index])) }
        }
        precondition(contrast(palette.primaryColor, palette.textColor) >= 2.5)
        precondition(palette.highContrastColor == (contrast(palette.primaryColor, black) >= 2.5 ? black : white))
        return palette
    }

    static func run(_ mode: String) {
        switch mode {
        case "solid":
            let pixel: [UInt8] = [37, 126, 219, 255]
            let data = Fixtures.png(width: 7, height: 5, pixels: Array(repeating: pixel, count: 35))
            let palette = extract(data)
            close(palette.primaryColor, SIMD3<Double>(37, 126, 219) / 255)
            precondition(palette.secondaryColor == black && palette.tertiaryColor == black)
            precondition(palette == extract(data))
            for pixel in [Fixtures.black, [128, 128, 128, 255], Fixtures.white] {
                let value = extract(Fixtures.regions([(pixel, 1)]))
                precondition(value.primaryColor == black && value.textColor == white)
            }
        case "areas":
            let data = Fixtures.regions([(Fixtures.red, 16), (Fixtures.green, 8),
                                        (Fixtures.blue, 6), ([255, 255, 0, 255], 2)])
            let palette = extract(data)
            close(palette.primaryColor, red)
            close(palette.secondaryColor, green)
            close(palette.tertiaryColor, blue)
            let widePixels = (0..<8).flatMap { _ in
                Array(repeating: Fixtures.red, count: 48) + Array(repeating: Fixtures.blue, count: 16)
            }
            let wide = extract(Fixtures.png(width: 64, height: 8, pixels: widePixels))
            close(wide.primaryColor, red)
            close(wide.secondaryColor, blue)
            let blueAccent: [UInt8] = [38, 75, 224, 255]
            let greenAccent: [UInt8] = [24, 207, 99, 255]
            let blueAnchor = extract(Fixtures.regions([([87, 125, 227, 255], 86),
                                                       (blueAccent, 36), (greenAccent, 28)]))
            let greenAnchor = extract(Fixtures.regions([([27, 157, 76, 255], 86),
                                                        (blueAccent, 36), (greenAccent, 28)]))
            close(blueAnchor.secondaryColor, SIMD3<Double>(24, 207, 97) / 255)
            close(greenAnchor.secondaryColor, SIMD3<Double>(38, 75, 223) / 255)
        case "quantization":
            let palette = extract(Fixtures.regions([(Fixtures.red, 3), ([245, 0, 0, 255], 2),
                                                   (Fixtures.green, 4)]))
            close(palette.primaryColor, SIMD3<Double>(251.0 / 255.0, 0, 0), tolerance: 0.004)
            close(palette.secondaryColor, green)
            precondition(palette.tertiaryColor == black)
            // The official published duo-orange thumbnail contains these uniform rows.
            let bands: [([UInt8], Int)] = [
                ([233, 27, 63, 255], 100), ([233, 27, 62, 255], 1), ([232, 26, 63, 255], 2),
                ([240, 71, 42, 255], 1), ([242, 80, 38, 255], 1), ([241, 78, 39, 255], 1),
                ([242, 79, 39, 255], 44)
            ]
            let closeAccents = extract(Fixtures.png(width: 150, height: 150,
                pixels: bands.flatMap { Array(repeating: $0.0, count: 150 * $0.1) }))
            close(closeAccents.secondaryColor, SIMD3<Double>(241, 76, 38) / 255, tolerance: 1.0 / 255)
            close(closeAccents.tertiaryColor, SIMD3<Double>(242, 78, 38) / 255, tolerance: 1.0 / 255)
        case "alpha":
            let weighted = extract(Fixtures.regions([(Fixtures.red, 1), ([0, 0, 255, 64], 2),
                                                     ([0, 255, 0, 0], 8)]))
            close(weighted.primaryColor, blue)
            close(weighted.secondaryColor, red)
            precondition(weighted.tertiaryColor == black)
            let boundary = extract(Fixtures.regions([(Fixtures.red, 3), ([0, 0, 255, 16], 2),
                                                     ([0, 255, 0, 15], 2)]))
            close(boundary.secondaryColor, blue)
            precondition(boundary.tertiaryColor == black)
            let half = extract(Fixtures.regions([([200, 80, 40, 128], 4)]))
            close(half.primaryColor, SIMD3<Double>(200, 80, 40) / 255)
            let transparent = extract(Fixtures.regions([([255, 0, 0, 0], 2), ([0, 255, 0, 0], 3)]))
            precondition(transparent.primaryColor == black && transparent.secondaryColor == black)
            precondition(transparent.tertiaryColor == black && transparent.textColor == white)
            precondition(transparent.highContrastColor == white)
            let alphaMean = extract(Fixtures.regions([([240, 0, 0, 255], 1), ([254, 0, 0, 128], 1)]))
            close(alphaMean.primaryColor, SIMD3<Double>(247.0 / 255, 0, 0), tolerance: 1.0 / 255)
        case "contrast":
            let moderate = extract(Fixtures.regions([([167, 0, 0, 255], 4)]))
            precondition(moderate.textColor == black && moderate.highContrastColor == black)
            precondition(contrast(moderate.primaryColor, black) < contrast(moderate.primaryColor, white))
            let dark = extract(Fixtures.regions([([0, 0, 128, 255], 20)]))
            precondition(dark.textColor == white && dark.highContrastColor == white)
            let accents = extract(Fixtures.regions([([0, 0, 128, 255], 20), (Fixtures.red, 5),
                                                    (Fixtures.green, 3)]))
            close(accents.secondaryColor, red)
            close(accents.tertiaryColor, green)
            close(accents.textColor, green)
        case "tie":
            let first = extract(Fixtures.regions([(Fixtures.red, 1), (Fixtures.green, 1), (Fixtures.blue, 1)]))
            let reverse = extract(Fixtures.regions([(Fixtures.blue, 1), (Fixtures.green, 1), (Fixtures.red, 1)]))
            precondition(first == reverse)
            close(first.primaryColor, red)
            close(first.secondaryColor, blue)
            close(first.tertiaryColor, green)
        case "srgb":
            let palette = extract(Fixtures.png(width: 2, height: 2,
                pixels: Array(repeating: [64, 128, 192, 255], count: 4), linear: true))
            // An embedded linear sRGB profile must be converted, not treated
            // as already encoded sRGB bytes.
            close(palette.primaryColor, SIMD3<Double>(0.538, 0.737, 0.882))
        case "bounds":
            precondition(SystemMediaArtworkPalette.extract(from: Data()) == nil)
            precondition(SystemMediaArtworkPalette.extract(from: Data("not an image".utf8)) == nil)
            let small = Fixtures.regions([(Fixtures.red, 1)])
            precondition(SystemMediaArtworkPalette.extract(from: small.prefix(16)) == nil)
            let maximumBytes = 16 * 1_024 * 1_024
            var boundary = small
            boundary.append(Data(count: maximumBytes - boundary.count))
            close(extract(boundary).primaryColor, red)
            boundary.append(0)
            precondition(SystemMediaArtworkPalette.extract(from: boundary) == nil)
            _ = extract(Fixtures.grayPNG(width: 8_192, height: 1))
            _ = extract(Fixtures.grayPNG(width: 1, height: 8_192))
            precondition(SystemMediaArtworkPalette.extract(from: Fixtures.grayPNG(width: 8_193, height: 1)) == nil)
            precondition(SystemMediaArtworkPalette.extract(from: Fixtures.grayPNG(width: 1, height: 8_193)) == nil)
            _ = extract(Fixtures.grayPNG(width: 4_096, height: 4_096))
            precondition(SystemMediaArtworkPalette.extract(from: Fixtures.grayPNG(width: 4_096, height: 4_097)) == nil)
        default:
            preconditionFailure("unknown palette fixture")
        }
    }
}

@main
struct PaletteHarness {
    static func main() async {
        let mode = CommandLine.arguments[1]
        await Task.detached {
            precondition(!Thread.isMainThread)
            autoreleasepool { PaletteCases.run(mode) }
        }.value
        print("{\"result\":\"PASS\",\"case\":\"\(mode)\",\"worker\":true}")
    }
}
'''


class SystemMediaArtworkPaletteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None or shutil.which("xcrun") is None:
            raise unittest.SkipTest("macOS Swift/SDK are unavailable")
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-media-palette-test-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        harness = root / "harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "palette-test"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        compiled = subprocess.run(
            ["swiftc", "-swift-version", "6", "-default-isolation", "MainActor",
             "-module-cache-path", str(root / "swift-cache"), str(SOURCE), str(harness),
             "-o", str(cls.binary)], capture_output=True, text=True, env=environment, cwd=ROOT)
        if compiled.returncode:
            raise AssertionError(compiled.stderr)

    def run_case(self, mode):
        result = subprocess.run([str(self.binary), mode], capture_output=True, text=True, timeout=45)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["result"], "PASS")
        self.assertEqual(report["case"], mode)
        self.assertTrue(report["worker"])

    def test_solid_color_keeps_accent_slots_empty(self):
        self.run_case("solid")

    def test_dominant_areas_select_three_colors(self):
        self.run_case("areas")

    def test_close_colors_share_a_quantized_bucket(self):
        self.run_case("quantization")

    def test_alpha_threshold_and_straight_colors(self):
        self.run_case("alpha")

    def test_contrast_priority_and_black_white_fallback(self):
        self.run_case("contrast")

    def test_ties_have_stable_color_order(self):
        self.run_case("tie")

    def test_input_profile_is_converted_to_srgb(self):
        self.run_case("srgb")

    def test_invalid_data_and_byte_dimension_pixel_boundaries(self):
        self.run_case("bounds")


if __name__ == "__main__":
    unittest.main()

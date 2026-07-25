#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SOURCE_ROOT / "Particles/SceneParticleTextureSource.swift",
    SOURCE_ROOT / "Particles/SceneParticleBuiltInTextureRegistry.swift",
]


HARNESS_SOURCE = r'''
import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        let keys: [SceneParticleBuiltInTexture] = [
            .beam1, .chromaticDot, .drop, .fire1, .fog1, .leaves7, .leaves8,
            .lightShafts0, .lightShafts6, .lightning3, .halo, .halo2, .halo4,
            .rippleSingle, .rosePetals,
        ]
        let sources: [String: Bool] = [
            "beam": SceneParticleTextureSource(
                reference: "particle/beam/beam_1"
            ) == .builtIn(.beam1),
            "chromatic": SceneParticleTextureSource(
                reference: "particle/chromaticdot"
            ) == .builtIn(.chromaticDot),
            "direct": SceneParticleTextureSource(reference: "particle/drop") == .builtIn(.drop),
            "fire": SceneParticleTextureSource(
                reference: "materials/particle/fire/fire1"
            ) == .builtIn(.fire1),
            "normalized": SceneParticleTextureSource(
                reference: "  .\\Materials\\PARTICLE\\DROP  "
            ) == .builtIn(.drop),
            "fog": SceneParticleTextureSource(reference: "particle/fog/fog1") == .builtIn(.fog1),
            "leaves7": SceneParticleTextureSource(reference: "particle/nature/leaves7") == .builtIn(.leaves7),
            "leaves8": SceneParticleTextureSource(reference: "particle/nature/leaves8") == .builtIn(.leaves8),
            "lightShaft0": SceneParticleTextureSource(reference: "particle/light/light_shafts_0") == .builtIn(.lightShafts0),
            "lightShaft6": SceneParticleTextureSource(reference: "particle/light/light_shafts_6") == .builtIn(.lightShafts6),
            "lightning": SceneParticleTextureSource(reference: "particle/lightning/lightning3") == .builtIn(.lightning3),
            "halo": SceneParticleTextureSource(reference: "particle/halo") == .builtIn(.halo),
            "halo2": SceneParticleTextureSource(reference: "particle/halo_2") == .builtIn(.halo2),
            "halo4": SceneParticleTextureSource(reference: "particle/halo_4") == .builtIn(.halo4),
            "ripple": SceneParticleTextureSource(reference: "particle/water/ripple_single") == .builtIn(.rippleSingle),
            "rosePetals": SceneParticleTextureSource(
                reference: "materials/particle/nature/rosepetals"
            ) == .builtIn(.rosePetals),
            "unknownBuiltInFails": SceneParticleTextureSource(reference: "particle/not-supported") == nil,
            "emptyFails": SceneParticleTextureSource(reference: "  ") == nil,
            "fileCase": SceneParticleTextureSource.file(
                URL(fileURLWithPath: "/tmp/drop.tex")
            ) == .file(URL(fileURLWithPath: "/tmp/drop.tex")),
        ]

        guard let device = MTLCreateSystemDefaultDevice() else {
            try printJSON(["sources": sources, "metalAvailable": false])
            return
        }
        let registry = SceneParticleBuiltInTextureRegistry(device: device)
        let comparisonRegistry = SceneParticleBuiltInTextureRegistry(device: device)
        var summaries: [String: Any] = [:]
        for key in keys {
            guard let first = registry.texture(for: key),
                  let second = registry.texture(for: key),
                  let comparison = comparisonRegistry.texture(for: key) else {
                try printJSON(["sources": sources, "metalAvailable": true, "created": false])
                return
            }
            let pixels = readPixels(first)
            let comparisonPixels = readPixels(comparison)
            let alphaValues = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            summaries[key.rawValue] = [
                "width": first.width,
                "height": first.height,
                "pixelFormat": first.pixelFormat.rawValue,
                "cached": first === second,
                "deterministic": pixels == comparisonPixels,
                "checksum": checksum(pixels),
                "edgeTransparent": edgeIsTransparent(pixels, width: first.width, height: first.height),
                "premultiplied": pixelsArePremultiplied(pixels),
                "nonzeroAlphaCount": alphaValues.filter { $0 > 0 }.count,
                "highAlphaCount": alphaValues.filter { $0 >= 220 }.count,
                "nonGrayPixelCount": nonGrayPixelCount(pixels),
                "hasSoftPixels": alphaValues.contains { $0 > 0 && $0 < 255 },
                "centerAlpha": pixel(pixels, width: first.width, x: first.width / 2, y: first.height / 2)[3],
                "maxAlpha": alphaValues.max() ?? 0,
                "upperWidth": nonzeroWidth(pixels, width: first.width, y: first.height / 4),
                "lowerWidth": nonzeroWidth(pixels, width: first.width, y: first.height * 3 / 4),
                "middleUpperWidth": nonzeroWidth(pixels, width: first.width, y: first.height * 2 / 5),
                "middleLowerWidth": nonzeroWidth(pixels, width: first.width, y: first.height * 3 / 5),
            ]
        }

        try printJSON([
            "sources": sources,
            "metalAvailable": true,
            "created": true,
            "textures": summaries,
        ])
    }

    private static func readPixels(_ texture: MTLTexture) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: texture.width * 4,
            from: MTLRegionMake2D(0, 0, texture.width, texture.height),
            mipmapLevel: 0
        )
        return pixels
    }

    private static func pixel(_ pixels: [UInt8], width: Int, x: Int, y: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(pixels[offset..<(offset + 4)])
    }

    private static func pixelsArePremultiplied(_ pixels: [UInt8]) -> Bool {
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[offset + 3]
            if pixels[offset] > alpha
                || pixels[offset + 1] > alpha
                || pixels[offset + 2] > alpha {
                return false
            }
        }
        return true
    }

    private static func nonGrayPixelCount(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).filter { offset in
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            return pixels[offset + 3] > 0 && (red != green || green != blue)
        }.count
    }

    private static func edgeIsTransparent(
        _ pixels: [UInt8],
        width: Int,
        height: Int
    ) -> Bool {
        for x in 0..<width {
            if pixel(pixels, width: width, x: x, y: 0)[3] != 0
                || pixel(pixels, width: width, x: x, y: height - 1)[3] != 0 {
                return false
            }
        }
        for y in 0..<height {
            if pixel(pixels, width: width, x: 0, y: y)[3] != 0
                || pixel(pixels, width: width, x: width - 1, y: y)[3] != 0 {
                return false
            }
        }
        return true
    }

    private static func nonzeroWidth(_ pixels: [UInt8], width: Int, y: Int) -> Int {
        (0..<width).filter { pixel(pixels, width: width, x: $0, y: y)[3] > 0 }.count
    }

    private static func checksum(_ pixels: [UInt8]) -> String {
        var value: UInt64 = 1_469_598_103_934_665_603
        for byte in pixels {
            value ^= UInt64(byte)
            value &*= 1_099_511_628_211
        }
        return String(value, radix: 16)
    }

    private static func printJSON(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''


class SceneParticleBuiltInTextureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary_directory = tempfile.TemporaryDirectory(prefix="mwx-particle-builtins-")
        directory = Path(cls.temporary_directory.name)
        harness = directory / "Harness.swift"
        harness.write_text(HARNESS_SOURCE, encoding="utf-8")
        cls.binary = directory / "scene-particle-builtins"
        compilation = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES), str(harness),
                "-framework", "Metal", "-o", str(cls.binary),
            ],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        completed = subprocess.run(
            [str(cls.binary)], check=True, capture_output=True, text=True
        )
        cls.result = json.loads(completed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary_directory.cleanup()

    def test_reference_normalization_and_closed_set(self) -> None:
        self.assertTrue(all(self.result["sources"].values()), self.result["sources"])

    def test_all_generated_textures_have_safe_common_contract(self) -> None:
        self.assertTrue(self.result["metalAvailable"])
        self.assertTrue(self.result["created"])
        textures = self.result["textures"]
        self.assertEqual(len(textures), 15)
        for name, summary in textures.items():
            with self.subTest(name=name):
                self.assertTrue(summary["cached"])
                self.assertTrue(summary["deterministic"])
                self.assertTrue(summary["edgeTransparent"])
                self.assertTrue(summary["premultiplied"])
                self.assertTrue(summary["hasSoftPixels"])
                self.assertGreater(summary["nonzeroAlphaCount"], 0)
                self.assertGreater(summary["maxAlpha"], 0)

    def test_generated_families_have_distinct_shapes(self) -> None:
        textures = self.result["textures"]
        expected_sizes = {
            "particle/beam/beam_1": 128,
            "particle/chromaticdot": 64,
            "particle/drop": 32,
            "particle/fire/fire1": 128,
            "particle/fog/fog1": 128,
            "particle/nature/leaves7": 64,
            "particle/nature/leaves8": 64,
            "particle/light/light_shafts_0": 128,
            "particle/light/light_shafts_6": 128,
            "particle/lightning/lightning3": 128,
            "particle/halo": 64,
            "particle/halo_2": 64,
            "particle/halo_4": 64,
            "particle/water/ripple_single": 64,
            "particle/nature/rosepetals": 64,
        }
        for name, size in expected_sizes.items():
            self.assertEqual((textures[name]["width"], textures[name]["height"]), (size, size))
        self.assertEqual(len({value["checksum"] for value in textures.values()}), 15)
        chromatic = textures["particle/chromaticdot"]
        self.assertEqual(chromatic["nonGrayPixelCount"], 0)
        self.assertGreaterEqual(chromatic["centerAlpha"], 250)
        self.assertGreaterEqual(textures["particle/drop"]["centerAlpha"], 250)
        fire = textures["particle/fire/fire1"]
        self.assertGreater(fire["middleLowerWidth"], fire["middleUpperWidth"])
        self.assertGreaterEqual(fire["maxAlpha"], 30)
        self.assertLessEqual(fire["maxAlpha"], 45)
        self.assertLess(fire["nonzeroAlphaCount"], 128 * 128 // 10)
        halo4 = textures["particle/halo_4"]
        self.assertGreaterEqual(halo4["centerAlpha"], 250)
        self.assertGreater(halo4["highAlphaCount"], 0)
        self.assertLess(halo4["highAlphaCount"], 64 * 64 // 4)
        self.assertLess(halo4["nonzeroAlphaCount"], 64 * 64 // 16)
        self.assertLessEqual(textures["particle/water/ripple_single"]["centerAlpha"], 2)
        shaft0 = textures["particle/light/light_shafts_0"]
        self.assertGreater(shaft0["lowerWidth"], shaft0["upperWidth"])
        self.assertGreaterEqual(shaft0["maxAlpha"], 35)
        self.assertLessEqual(shaft0["maxAlpha"], 50)
        shaft6 = textures["particle/light/light_shafts_6"]
        self.assertGreater(shaft6["lowerWidth"], shaft6["upperWidth"])
        lightning = textures["particle/lightning/lightning3"]
        self.assertGreater(lightning["highAlphaCount"], 0)
        self.assertLess(lightning["highAlphaCount"], 128 * 128 // 10)
        beam = textures["particle/beam/beam_1"]
        self.assertGreaterEqual(beam["centerAlpha"], 240)
        self.assertLess(beam["nonzeroAlphaCount"], 128 * 128 // 2)
        rose = textures["particle/nature/rosepetals"]
        self.assertGreaterEqual(rose["centerAlpha"], 220)
        self.assertLess(rose["nonzeroAlphaCount"], 64 * 64 // 2)


if __name__ == "__main__":
    unittest.main()

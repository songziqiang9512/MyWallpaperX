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
            .beam1, .chromaticDot, .drop, .fire1, .fog1, .fog3,
            .leaves7, .leaves8, .snow, .lightShafts0, .lightShafts6, .lightning3,
            .halo, .halo2, .halo3, .halo4, .halo6, .star, .flare1, .rippleSingle,
            .rosePetals, .smoke2,
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
            "fog3": SceneParticleTextureSource(reference: "particle/fog/fog3") == .builtIn(.fog3),
            "leaves7": SceneParticleTextureSource(reference: "particle/nature/leaves7") == .builtIn(.leaves7),
            "leaves8": SceneParticleTextureSource(reference: "particle/nature/leaves8") == .builtIn(.leaves8),
            "snow": SceneParticleTextureSource(reference: "particle/nature/snow") == .builtIn(.snow),
            "lightShaft0": SceneParticleTextureSource(reference: "particle/light/light_shafts_0") == .builtIn(.lightShafts0),
            "lightShaft6": SceneParticleTextureSource(reference: "particle/light/light_shafts_6") == .builtIn(.lightShafts6),
            "lightning": SceneParticleTextureSource(reference: "particle/lightning/lightning3") == .builtIn(.lightning3),
            "halo": SceneParticleTextureSource(reference: "particle/halo") == .builtIn(.halo),
            "halo2": SceneParticleTextureSource(reference: "particle/halo_2") == .builtIn(.halo2),
            "halo3": SceneParticleTextureSource(reference: "particle/halo_3") == .builtIn(.halo3),
            "halo4": SceneParticleTextureSource(reference: "particle/halo_4") == .builtIn(.halo4),
            "halo6": SceneParticleTextureSource(reference: "particle/halo_6") == .builtIn(.halo6),
            "star": SceneParticleTextureSource(reference: "particle/star") == .builtIn(.star),
            "flare1": SceneParticleTextureSource(reference: "particle/light/flare_1") == .builtIn(.flare1),
            "ripple": SceneParticleTextureSource(reference: "particle/water/ripple_single") == .builtIn(.rippleSingle),
            "rosePetals": SceneParticleTextureSource(
                reference: "materials/particle/nature/rosepetals"
            ) == .builtIn(.rosePetals),
            "smoke2": SceneParticleTextureSource(reference: "particle/smoke/smoke2") == .builtIn(.smoke2),
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
        self.assertEqual(len(textures), 22)
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
        # 尺寸对齐官方 .tex 的 imageWidth/imageHeight，非方形纹理不得按方形近似。
        expected_sizes = {
            "particle/beam/beam_1": (32, 128),
            "particle/chromaticdot": (64, 64),
            "particle/drop": (32, 128),
            "particle/fire/fire1": (128, 128),
            "particle/fog/fog1": (128, 128),
            "particle/fog/fog3": (128, 128),
            "particle/nature/leaves7": (64, 64),
            "particle/nature/leaves8": (64, 64),
            "particle/nature/snow": (64, 64),
            "particle/light/light_shafts_0": (256, 512),
            "particle/light/light_shafts_6": (128, 512),
            "particle/lightning/lightning3": (128, 128),
            "particle/halo": (64, 64),
            "particle/halo_2": (64, 64),
            "particle/halo_3": (64, 64),
            "particle/halo_4": (128, 128),
            "particle/halo_6": (128, 128),
            "particle/star": (64, 64),
            "particle/light/flare_1": (256, 256),
            "particle/water/ripple_single": (64, 64),
            "particle/nature/rosepetals": (64, 64),
            "particle/smoke/smoke2": (128, 128),
        }
        for name, size in expected_sizes.items():
            with self.subTest(name=name):
                self.assertEqual((textures[name]["width"], textures[name]["height"]), size)
        self.assertEqual(len({value["checksum"] for value in textures.values()}), 22)
        chromatic = textures["particle/chromaticdot"]
        self.assertEqual(chromatic["nonGrayPixelCount"], 0)
        self.assertGreaterEqual(chromatic["centerAlpha"], 250)
        # drop 是头部在上的彗形，峰值不在几何中心，只能约束峰值本身。
        self.assertGreaterEqual(textures["particle/drop"]["maxAlpha"], 250)
        self.assertGreater(
            textures["particle/drop"]["middleUpperWidth"],
            textures["particle/drop"]["lowerWidth"],
        )
        fire = textures["particle/fire/fire1"]
        self.assertGreater(fire["middleLowerWidth"], fire["middleUpperWidth"])
        self.assertGreaterEqual(fire["maxAlpha"], 30)
        self.assertLessEqual(fire["maxAlpha"], 45)
        self.assertLess(fire["nonzeroAlphaCount"], 128 * 128 // 10)
        # halo_4 是极小亮核叠一层覆盖整幅的低幅外晕，外晕面积占多数。
        halo4 = textures["particle/halo_4"]
        self.assertGreaterEqual(halo4["centerAlpha"], 220)
        self.assertGreater(halo4["highAlphaCount"], 0)
        self.assertLess(halo4["highAlphaCount"], 128 * 128 // 64)
        self.assertGreater(halo4["nonzeroAlphaCount"], 128 * 128 // 2)
        # halo_3 是无亮核的暗弱宽晕，靠峰值幅度与 halo_4 区分。
        halo3 = textures["particle/halo_3"]
        self.assertGreaterEqual(halo3["centerAlpha"], 30)
        self.assertLessEqual(halo3["maxAlpha"], 50)
        self.assertLess(halo3["maxAlpha"], halo4["centerAlpha"])
        # halo_6 是实心白盘，仅 alpha 随半径衰减，满值区占相当面积。
        halo6 = textures["particle/halo_6"]
        self.assertGreaterEqual(halo6["centerAlpha"], 250)
        self.assertGreater(halo6["highAlphaCount"], 128 * 128 // 4)
        fog3 = textures["particle/fog/fog3"]
        self.assertGreaterEqual(fog3["maxAlpha"], 1)
        self.assertLessEqual(fog3["maxAlpha"], 3)
        self.assertGreater(fog3["nonzeroAlphaCount"], 128 * 128 // 10)
        self.assertLess(fog3["nonzeroAlphaCount"], 128 * 128 * 3 // 4)
        # flare_1 是水平细长光斑，纵向 σ≈0.065，h/4 与 3h/4 两行都在包络外。
        flare1 = textures["particle/light/flare_1"]
        self.assertGreaterEqual(flare1["centerAlpha"], 220)
        self.assertGreater(flare1["highAlphaCount"], 0)
        self.assertLess(flare1["highAlphaCount"], 256 * 256 // 64)
        self.assertLess(flare1["nonzeroAlphaCount"], 256 * 256 // 8)
        self.assertEqual(flare1["upperWidth"], 0)
        self.assertEqual(flare1["lowerWidth"], 0)
        self.assertLessEqual(textures["particle/water/ripple_single"]["centerAlpha"], 2)
        # 两族光柱都是上宽下窄（峰值在 y≈-0.6~-0.7 后向下渐淡），不是下宽上窄。
        shaft0 = textures["particle/light/light_shafts_0"]
        self.assertGreater(shaft0["upperWidth"], shaft0["lowerWidth"])
        self.assertGreaterEqual(shaft0["maxAlpha"], 200)
        self.assertLessEqual(shaft0["maxAlpha"], 240)
        shaft6 = textures["particle/light/light_shafts_6"]
        self.assertGreater(shaft6["upperWidth"], shaft6["lowerWidth"])
        self.assertEqual(shaft6["lowerWidth"], 0)
        lightning = textures["particle/lightning/lightning3"]
        self.assertGreater(lightning["highAlphaCount"], 0)
        self.assertLess(lightning["highAlphaCount"], 128 * 128 // 10)
        # beam_1 是上下对称的椭圆径向光斑，横向铺满全幅而非细线。
        beam = textures["particle/beam/beam_1"]
        self.assertGreaterEqual(beam["centerAlpha"], 230)
        self.assertEqual(beam["upperWidth"], beam["lowerWidth"])
        self.assertGreater(beam["nonzeroAlphaCount"], 32 * 128 // 2)
        self.assertLess(beam["nonzeroAlphaCount"], 32 * 128)
        # star 是偏心实心亮斑挂低幅碎芒，星芒向下延伸更远。
        star = textures["particle/star"]
        self.assertGreaterEqual(star["centerAlpha"], 240)
        self.assertGreater(star["middleLowerWidth"], star["middleUpperWidth"])
        self.assertLess(star["nonzeroAlphaCount"], 64 * 64 // 2)
        rose = textures["particle/nature/rosepetals"]
        self.assertGreaterEqual(rose["centerAlpha"], 220)
        self.assertLess(rose["nonzeroAlphaCount"], 64 * 64 // 2)
        snow = textures["particle/nature/snow"]
        self.assertGreaterEqual(snow["centerAlpha"], 80)
        self.assertGreaterEqual(snow["maxAlpha"], 100)
        self.assertLessEqual(snow["maxAlpha"], 150)
        self.assertLess(snow["nonzeroAlphaCount"], 64 * 64 // 3)
        smoke2 = textures["particle/smoke/smoke2"]
        self.assertGreaterEqual(smoke2["maxAlpha"], 8)
        self.assertLessEqual(smoke2["maxAlpha"], 14)
        self.assertGreater(smoke2["nonzeroAlphaCount"], 128 * 128 // 8)
        self.assertLess(smoke2["nonzeroAlphaCount"], 128 * 128 * 3 // 4)


if __name__ == "__main__":
    unittest.main()

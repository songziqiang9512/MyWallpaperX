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
    SOURCE_ROOT / "SceneParticleTextureSource.swift",
    SOURCE_ROOT / "SceneParticleBuiltInTextureRegistry.swift",
]


HARNESS_SOURCE = r'''
import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        let sources: [String: Bool] = [
            "direct": SceneParticleTextureSource(reference: "particle/drop") == .builtIn(.drop),
            "normalized": SceneParticleTextureSource(
                reference: "  .\\Materials\\PARTICLE\\DROP  "
            ) == .builtIn(.drop),
            "unknownBuiltInFails": SceneParticleTextureSource(reference: "particle/halo") == nil,
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
        guard let first = registry.texture(for: .drop),
              let second = registry.texture(for: .drop) else {
            try printJSON(["sources": sources, "metalAvailable": true, "created": false])
            return
        }

        var pixels = [UInt8](repeating: 0, count: first.width * first.height * 4)
        first.getBytes(
            &pixels,
            bytesPerRow: first.width * 4,
            from: MTLRegionMake2D(0, 0, first.width, first.height),
            mipmapLevel: 0
        )
        let corner = pixel(pixels, width: first.width, x: 0, y: 0)
        let center = pixel(pixels, width: first.width, x: 15, y: 15)
        let alphaValues = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        let premultiplied = pixelsArePremultiplied(pixels)

        try printJSON([
            "sources": sources,
            "metalAvailable": true,
            "created": true,
            "width": first.width,
            "height": first.height,
            "pixelFormat": first.pixelFormat.rawValue,
            "reused": first === second,
            "corner": corner,
            "center": center,
            "premultiplied": premultiplied,
            "alphaLevelCount": Set(alphaValues).count,
            "hasSoftPixels": alphaValues.contains { $0 > 0 && $0 < 255 },
        ])
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
        self.assertEqual(
            self.result["sources"],
            {
                "direct": True,
                "emptyFails": True,
                "fileCase": True,
                "normalized": True,
                "unknownBuiltInFails": True,
            },
        )

    def test_drop_texture_is_cached_and_has_expected_shape(self) -> None:
        self.assertTrue(self.result["metalAvailable"])
        self.assertTrue(self.result["created"])
        self.assertEqual((self.result["width"], self.result["height"]), (32, 32))
        self.assertTrue(self.result["reused"])
        self.assertEqual(self.result["corner"], [0, 0, 0, 0])
        self.assertGreaterEqual(self.result["center"][3], 250)
        self.assertGreater(self.result["alphaLevelCount"], 16)
        self.assertTrue(self.result["hasSoftPixels"])

    def test_drop_pixels_are_premultiplied_white(self) -> None:
        self.assertTrue(self.result["premultiplied"])
        center = self.result["center"]
        self.assertEqual(center[:3], [center[3]] * 3)


if __name__ == "__main__":
    unittest.main()

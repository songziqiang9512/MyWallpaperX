#!/usr/bin/env python3

"""Pixel tests for SceneBCTextureDecoder.

Encodes small BC1/BC2/BC3 blocks with known palettes on the Python side and
asserts the Swift decoder reproduces the exact RGBA bytes, including the
BC1 punch-through transparent mode, both BC3 alpha ramps, and cropping the
padded block grid to the authored image size.
"""

from __future__ import annotations

import json
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        let request = try JSONSerialization.jsonObject(
            with: FileHandle.standardInput.readDataToEndOfFile()
        ) as! [[String: Any]]
        var results: [[String: Any]] = []
        for item in request {
            let name = item["name"] as! String
            let blockData = Data(base64Encoded: item["blocks"] as! String)!
            let format: SceneBCTextureDecoder.Format
            switch item["format"] as! String {
            case "bc1": format = .bc1
            case "bc2": format = .bc2
            default: format = .bc3
            }
            let decoded = SceneBCTextureDecoder.decode(
                blockData: blockData,
                storedWidth: item["storedWidth"] as! Int,
                storedHeight: item["storedHeight"] as! Int,
                imageWidth: item["imageWidth"] as! Int,
                imageHeight: item["imageHeight"] as! Int,
                format: format
            )
            if let decoded {
                results.append([
                    "name": name,
                    "ok": true,
                    "width": decoded.width,
                    "height": decoded.height,
                    "rgba": decoded.rgba.base64EncodedString(),
                ])
            } else {
                results.append(["name": name, "ok": false])
            }
        }
        FileHandle.standardOutput.write(
            try JSONSerialization.data(withJSONObject: results)
        )
    }
}
'''


def rgb565(r8: int, g8: int, b8: int) -> int:
    return ((r8 >> 3) << 11) | ((g8 >> 2) << 5) | (b8 >> 3)


def expand565(value: int) -> tuple[int, int, int]:
    r5 = (value >> 11) & 0x1F
    g6 = (value >> 5) & 0x3F
    b5 = value & 0x1F
    return (
        (r5 << 3) | (r5 >> 2),
        (g6 << 2) | (g6 >> 4),
        (b5 << 3) | (b5 >> 2),
    )


def bc1_block(c0: int, c1: int, index_rows: list[int]) -> bytes:
    return struct.pack("<HH4B", c0, c1, *index_rows)


def bc3_block(a0: int, a1: int, alpha_indices: list[int], color: bytes) -> bytes:
    bits = 0
    for i, idx in enumerate(alpha_indices):
        bits |= (idx & 0b111) << (i * 3)
    alpha_bytes = struct.pack("<BB", a0, a1) + bits.to_bytes(6, "little")
    return alpha_bytes + color


def bc2_block(alpha_rows: list[int], color: bytes) -> bytes:
    return struct.pack("<4H", *alpha_rows) + color


class SceneBCTextureDecoderTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        harness = tmp / "harness.swift"
        harness.write_text(HARNESS)
        binary = tmp / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")

        red = rgb565(255, 0, 0)
        blue = rgb565(0, 0, 255)
        # BC1 four-color mode: c0 > c1 so indices 2/3 interpolate.
        four_color = bc1_block(max(red, blue), min(red, blue), [0b00000000] * 4)
        # BC1 punch-through: c0 <= c1, index 3 decodes transparent black.
        punch = bc1_block(min(red, blue), max(red, blue), [0b11111111] * 4)
        # BC3: opaque gradient alpha (a0 > a1 -> 8-entry ramp), red color.
        bc3_opaque = bc3_block(255, 0, [0] * 16, bc1_block(red, 0, [0] * 4))
        # BC3: a0 <= a1 mode where index 6 is forced 0 and 7 is forced 255.
        bc3_modes = bc3_block(10, 20, [6] * 8 + [7] * 8, bc1_block(red, 0, [0] * 4))
        # BC2: explicit 4-bit alpha 0xF (255) on the first row, 0x0 elsewhere.
        bc2 = bc2_block([0xFFFF, 0, 0, 0], bc1_block(red, 0, [0] * 4))
        # Crop: 8x8 stored grid (4 blocks) down to a 6x6 image.
        crop_blocks = b"".join(
            bc1_block(rgb565(shade, shade, shade), 0, [0] * 4)
            for shade in (255, 199, 127, 63)
        )

        requests = [
            {"name": "bc1-four-color", "format": "bc1", "blocks": _b64(four_color),
             "storedWidth": 4, "storedHeight": 4, "imageWidth": 4, "imageHeight": 4},
            {"name": "bc1-punch-through", "format": "bc1", "blocks": _b64(punch),
             "storedWidth": 4, "storedHeight": 4, "imageWidth": 4, "imageHeight": 4},
            {"name": "bc3-opaque", "format": "bc3", "blocks": _b64(bc3_opaque),
             "storedWidth": 4, "storedHeight": 4, "imageWidth": 4, "imageHeight": 4},
            {"name": "bc3-forced-endpoints", "format": "bc3", "blocks": _b64(bc3_modes),
             "storedWidth": 4, "storedHeight": 4, "imageWidth": 4, "imageHeight": 4},
            {"name": "bc2-explicit-alpha", "format": "bc2", "blocks": _b64(bc2),
             "storedWidth": 4, "storedHeight": 4, "imageWidth": 4, "imageHeight": 4},
            {"name": "crop", "format": "bc1", "blocks": _b64(crop_blocks),
             "storedWidth": 8, "storedHeight": 8, "imageWidth": 6, "imageHeight": 6},
            {"name": "size-mismatch", "format": "bc1", "blocks": _b64(four_color),
             "storedWidth": 8, "storedHeight": 8, "imageWidth": 8, "imageHeight": 8},
        ]
        completed = subprocess.run(
            [str(binary)],
            input=json.dumps(requests),
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.results = {entry["name"]: entry for entry in json.loads(completed.stdout)}
        cls.red = expand565(red)
        cls.blue = expand565(blue)

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def pixels(self, name: str) -> list[tuple[int, int, int, int]]:
        import base64

        entry = self.results[name]
        self.assertTrue(entry["ok"], entry)
        raw = base64.b64decode(entry["rgba"])
        return [tuple(raw[i : i + 4]) for i in range(0, len(raw), 4)]

    def test_bc1_four_color_mode_decodes_endpoint_zero(self):
        pixels = self.pixels("bc1-four-color")
        expected = (*max(self.red, self.blue), 255)
        self.assertEqual(pixels, [expected] * 16)

    def test_bc1_punch_through_index_three_is_transparent_black(self):
        pixels = self.pixels("bc1-punch-through")
        self.assertEqual(pixels, [(0, 0, 0, 0)] * 16)

    def test_bc3_opaque_alpha_ramp(self):
        pixels = self.pixels("bc3-opaque")
        self.assertEqual(pixels, [(*self.red, 255)] * 16)

    def test_bc3_low_mode_forces_zero_and_full_alpha(self):
        pixels = self.pixels("bc3-forced-endpoints")
        alphas = [pixel[3] for pixel in pixels]
        self.assertEqual(alphas[:8], [0] * 8)
        self.assertEqual(alphas[8:], [255] * 8)

    def test_bc2_explicit_alpha_expands_4bit(self):
        pixels = self.pixels("bc2-explicit-alpha")
        alphas = [pixel[3] for pixel in pixels]
        self.assertEqual(alphas[:4], [255] * 4)
        self.assertEqual(alphas[4:], [0] * 12)

    def test_crop_trims_padded_blocks_to_image_size(self):
        entry = self.results["crop"]
        self.assertEqual((entry["width"], entry["height"]), (6, 6))
        pixels = self.pixels("crop")
        self.assertEqual(len(pixels), 36)
        # Top-left block shade fills the first 4 columns; the second block
        # contributes the remaining 2 columns of row 0.
        self.assertEqual(pixels[0][:3], expand565(rgb565(255, 255, 255)))
        self.assertEqual(pixels[5][:3], expand565(rgb565(199, 199, 199)))
        # Row 5 comes from the bottom block row.
        self.assertEqual(pixels[30][:3], expand565(rgb565(127, 127, 127)))

    def test_block_size_mismatch_returns_nil(self):
        self.assertFalse(self.results["size-mismatch"]["ok"])


def _b64(data: bytes) -> str:
    import base64

    return base64.b64encode(data).decode("ascii")


if __name__ == "__main__":
    unittest.main()

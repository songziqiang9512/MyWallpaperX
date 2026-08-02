#!/usr/bin/env python3

"""Bounded parser/uploader tests for Wallpaper Engine 3D LUT TEX assets."""

from __future__ import annotations

import binascii
import json
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
STOCK_NEUTRAL = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneStockAssets.bundle/assets/materials/lut/neutral.tex"
)
STOCK_LUT_DIRECTORY = STOCK_NEUTRAL.parent
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneBCTextureDecoder.swift",
    SCENE_ROOT / "Format/SceneTexDataReader.swift",
    SCENE_ROOT / "Format/SceneTexContainer.swift",
    SCENE_ROOT / "Resources/SceneCompressedTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneImageTextureUploader.swift",
    SCENE_ROOT / "Resources/SceneTextureLoader.swift",
    SCENE_ROOT / "Resources/SceneTextureMipUploader.swift",
]


HARNESS = r'''
import Foundation
import Metal

@main
enum Harness {
    static func main() throws {
        guard CommandLine.arguments.count == 6 else { throw HarnessError.badArguments }
        let reader = SceneTexContainerReader()
        let owned = try reader.read(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let stock = try reader.read(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        let headerRejected = rejects(URL(fileURLWithPath: CommandLine.arguments[3]), reader: reader)
        let mipRejected = rejects(URL(fileURLWithPath: CommandLine.arguments[4]), reader: reader)
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("SKIP")
            return
        }
        let loader = SceneTextureLoader()
        let ownedURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let stockURL = URL(fileURLWithPath: CommandLine.arguments[2])
        guard case let .loaded(ownedTexture) = loader.load(
                  from: ownedURL,
                  purpose: .lookupTable,
                  device: device
              ),
              case let .loaded(stockTexture) = loader.load(
                  from: stockURL,
                  purpose: .lookupTable,
                  device: device
              ) else {
            throw HarnessError.uploadFailed
        }
        let twoDRejected: Bool
        if case let .decodeFailed(reason) = loader.load(from: ownedURL, device: device) {
            twoDRejected = reason == "3D TEX requires a lookup-table consumer"
        } else {
            twoDRejected = false
        }
        let stockDirectory = URL(fileURLWithPath: CommandLine.arguments[5])
        let stockURLs = try FileManager.default.contentsOfDirectory(
            at: stockDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "tex" }
        var stockFailures: [String] = []
        for url in stockURLs {
            guard case let .loaded(texture) = loader.load(
                      from: url,
                      purpose: .lookupTable,
                      device: device
                  ),
                  texture.textureType == .type3D,
                  texture.width == 32,
                  texture.height == 32,
                  texture.depth == 32 else {
                stockFailures.append(url.lastPathComponent)
                continue
            }
        }
        var voxels = [UInt8](repeating: 0, count: 2 * 2 * 2 * 4)
        ownedTexture.getBytes(
            &voxels,
            bytesPerRow: 2 * 4,
            bytesPerImage: 2 * 2 * 4,
            from: MTLRegionMake3D(0, 0, 0, 2, 2, 2),
            mipmapLevel: 0,
            slice: 0
        )
        let result: [String: Any] = [
            "ownedHeader": [owned.textureWidth, owned.textureHeight, owned.textureDepth],
            "ownedMapped": [owned.imageWidth, owned.imageHeight],
            "ownedMip": [owned.mips[0].width, owned.mips[0].height, owned.mips[0].depth],
            "ownedTexture": [ownedTexture.width, ownedTexture.height, ownedTexture.depth],
            "ownedIs3D": ownedTexture.textureType == .type3D,
            "ownedVoxels": voxels,
            "stockHeader": [stock.textureWidth, stock.textureHeight, stock.textureDepth],
            "stockMip": [stock.mips[0].width, stock.mips[0].height, stock.mips[0].depth],
            "stockTexture": [stockTexture.width, stockTexture.height, stockTexture.depth],
            "stockIs3D": stockTexture.textureType == .type3D,
            "headerRejected": headerRejected,
            "mipRejected": mipRejected,
            "twoDRejected": twoDRejected,
            "stockVolumeCount": stockURLs.count,
            "stockFailures": stockFailures.sorted(),
        ]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result))
    }

    static func rejects(_ url: URL, reader: SceneTexContainerReader) -> Bool {
        do {
            _ = try reader.read(data: Data(contentsOf: url))
            return false
        } catch {
            return true
        }
    }

    enum HarnessError: Error { case badArguments, uploadFailed }
}
'''


def png_rgba(width: int, height: int, pixels: bytes) -> bytes:
    assert len(pixels) == width * height * 4

    def chunk(kind: bytes, payload: bytes) -> bytes:
        checksum = binascii.crc32(kind + payload) & 0xFFFFFFFF
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)

    rows = b"".join(
        b"\x00" + pixels[row * width * 4 : (row + 1) * width * 4]
        for row in range(height)
    )
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


def volume_tex(png: bytes, *, image_width: int = 4, mip_depth: int = 2) -> bytes:
    data = bytearray(b"TEXV0005\0TEXI0001\0")
    for value in (0, 0x42, 2, 2, image_width, 2, 2, 0):
        data += struct.pack("<I", value)
    data += b"TEXB0004\0"
    for value in (1, 13, 0, 1, 2, 2, mip_depth, 0, 0, len(png)):
        data += struct.pack("<I", value)
    data += png
    return bytes(data)


class SceneTexVolumeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        pixels = bytes(
            [
                255, 0, 0, 255,
                0, 255, 0, 255,
                0, 0, 255, 255,
                255, 255, 255, 255,
                10, 20, 30, 255,
                40, 50, 60, 255,
                70, 80, 90, 255,
                100, 110, 120, 255,
            ]
        )
        png = png_rgba(2, 4, pixels)
        owned = tmp / "owned.tex"
        bad_header = tmp / "bad-header.tex"
        bad_mip = tmp / "bad-mip.tex"
        owned.write_bytes(volume_tex(png))
        bad_header.write_bytes(volume_tex(png, image_width=5))
        bad_mip.write_bytes(volume_tex(png, mip_depth=3))
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
        execution = subprocess.run(
            [
                str(binary), str(owned), str(STOCK_NEUTRAL), str(bad_header),
                str(bad_mip), str(STOCK_LUT_DIRECTORY),
            ],
            capture_output=True,
            text=True,
        )
        if execution.returncode != 0:
            raise AssertionError(f"harness execution failed:\n{execution.stderr}")
        if execution.stdout.strip() == "SKIP":
            raise unittest.SkipTest("Metal device is unavailable")
        cls.result = json.loads(execution.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "_tmp"):
            cls._tmp.cleanup()

    def test_project_fixture_parses_and_uploads_as_a_3d_texture(self) -> None:
        self.assertEqual(self.result["ownedHeader"], [2, 2, 2])
        self.assertEqual(self.result["ownedMapped"], [4, 2])
        self.assertEqual(self.result["ownedMip"], [2, 2, 2])
        self.assertEqual(self.result["ownedTexture"], [2, 2, 2])
        self.assertTrue(self.result["ownedIs3D"])

    def test_vertical_slice_order_preserves_all_owned_fixture_voxels(self) -> None:
        self.assertEqual(
            self.result["ownedVoxels"],
            [
                255, 0, 0, 255, 0, 255, 0, 255,
                0, 0, 255, 255, 255, 255, 255, 255,
                10, 20, 30, 255, 40, 50, 60, 255,
                70, 80, 90, 255, 100, 110, 120, 255,
            ],
        )

    def test_official_stock_neutral_lut_uses_the_same_public_route(self) -> None:
        self.assertEqual(self.result["stockHeader"], [32, 32, 32])
        self.assertEqual(self.result["stockMip"], [32, 32, 32])
        self.assertEqual(self.result["stockTexture"], [32, 32, 32])
        self.assertTrue(self.result["stockIs3D"])

    def test_every_bundled_stock_lut_uses_the_same_volume_route(self) -> None:
        self.assertGreater(self.result["stockVolumeCount"], 0)
        self.assertEqual(self.result["stockFailures"], [])

    def test_inconsistent_header_and_mip_depth_fail_closed(self) -> None:
        self.assertTrue(self.result["headerRejected"])
        self.assertTrue(self.result["mipRejected"])

    def test_volume_asset_cannot_enter_the_ordinary_2d_loader_route(self) -> None:
        self.assertTrue(self.result["twoDRejected"])


if __name__ == "__main__":
    unittest.main()

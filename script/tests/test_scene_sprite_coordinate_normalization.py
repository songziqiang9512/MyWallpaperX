"""TEX sprite pixel bases must survive UV normalization on rectangular atlases."""

import json
import os
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORMAT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Format"


def fixture(version: int, width: int, height: int, coordinates: tuple) -> bytes:
    data = b"TEXV0005\0TEXI0001\0" + struct.pack(
        "<7I", 9, 4, width, height, width, height, 0
    )
    data += b"TEXB0002\0" + struct.pack("<2I", 1, 1)
    data += struct.pack("<5I", width, height, 0, width * height, width * height)
    data += bytes(width * height)
    data += f"TEXS000{version}\0".encode() + struct.pack("<I", 1)
    if version == 3:
        data += struct.pack("<2I", width, height)
    data += struct.pack("<if", 0, 0.1)
    data += struct.pack("<6i" if version == 1 else "<6f", *coordinates)
    return data


class SceneSpriteCoordinateNormalizationTests(unittest.TestCase):
    def test_pixel_corners_survive_rectangular_atlas_normalization(self) -> None:
        cases = [
            (128, 64, (32, 16, 0, 32, 16, 0)),
            (64, 128, (16, 64, 0, -32, 16, 0)),
            (128, 64, (16, 8, 32, 0, 0, 16)),
            (64, 64, (16, 8, 0, 32, 16, 0)),
            (128, 64, (16, 8, 32, 8, 16, 24)),
        ]
        with tempfile.TemporaryDirectory(prefix="scene-sprite-coordinates-") as directory:
            temp = Path(directory)
            harness = temp / "Harness.swift"
            harness.write_text('''
import Foundation
@main enum Harness {
    static func main() throws {
        var results: [[[Float]]] = []
        for path in CommandLine.arguments.dropFirst() {
            let container = try SceneTexContainerReader().read(
                data: Data(contentsOf: URL(fileURLWithPath: path))
            )
            let frame = container.spriteFrames[0]
            let size = SIMD2(Float(container.textureWidth), Float(container.textureHeight))
            let corners = [frame.origin, frame.origin + frame.xAxis,
                frame.origin + frame.yAxis, frame.origin + frame.xAxis + frame.yAxis]
            results.append(corners.map { let pixel = $0 * size; return [pixel.x, pixel.y] })
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
''', encoding="utf-8")
            binary = temp / "reader"
            env = os.environ.copy()
            env["CLANG_MODULE_CACHE_PATH"] = str(temp / "clang-cache")
            env["SWIFT_MODULECACHE_PATH"] = str(temp / "swift-cache")
            compilation = subprocess.run([
                "xcrun", "swiftc", "-parse-as-library",
                str(FORMAT / "SceneTexContainer.swift"),
                str(FORMAT / "SceneTexDataReader.swift"),
                str(harness), "-o", str(binary),
            ], capture_output=True, text=True, env=env)
            self.assertEqual(compilation.returncode, 0, compilation.stderr)
            paths = []
            expected = []
            for version in range(1, 4):
                for width, height, coordinates in cases:
                    path = temp / f"{len(paths)}.tex"
                    path.write_bytes(fixture(version, width, height, coordinates))
                    paths.append(str(path))
                    x, y, xx, xy, yx, yy = coordinates
                    expected.append([[x, y], [x + xx, y + xy],
                                     [x + yx, y + yy], [x + xx + yx, y + xy + yy]])
            result = subprocess.run([str(binary), *paths], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), expected)


if __name__ == "__main__":
    unittest.main()

"""Every truncated TEX prefix must fail locally instead of trapping."""

import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORMAT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Format"


def fixture(version: int, sprite_version: int | None = None, volume: bool = False) -> bytes:
    header = b"TEXV0005\0TEXI0001\0" + struct.pack(
        "<7I", 0, 4 if sprite_version else 0, 1, 1, 2 if volume else 1, 1,
        2 if volume else 0,
    )
    if volume:
        header += struct.pack("<I", 0)
    table = f"TEXB000{version}\0".encode() + struct.pack("<I", 1)
    if version >= 3:
        table += struct.pack("<i", 13)
    if version == 4:
        table += struct.pack("<I", 0 if volume else 1)
    table += struct.pack("<I", 1)
    if version == 4 and not volume:
        table += struct.pack("<2I", 1, 0) + b'{"key":"value"}\0' + struct.pack("<I", 0)
    table += struct.pack("<2I", 1, 1)
    if volume:
        table += struct.pack("<I", 2)
    if version >= 2:
        table += struct.pack("<2I", 0, 4)
    table += struct.pack("<I", 4) + b"\x01\x02\x03\x04"
    if sprite_version:
        table += f"TEXS000{sprite_version}\0".encode() + struct.pack("<I", 1)
        if sprite_version == 3:
            table += struct.pack("<2I", 1, 1)
        table += struct.pack("<if", 0, 0.1)
        table += struct.pack("<6i" if sprite_version == 1 else "<6f", 0, 0, 1, 0, 0, 1)
    return header + table


class SceneTexTruncationTests(unittest.TestCase):
    def test_all_incomplete_prefixes_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-tex-truncation-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text('''
import Foundation
@main enum Harness {
    static func main() throws {
        var checked = 0
        var acceptedPrefixes: [String] = []
        for path in CommandLine.arguments.dropFirst() {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            _ = try SceneTexContainerReader().read(data: data)
            for count in 0..<data.count {
                do {
                    _ = try SceneTexContainerReader().read(data: Data(data.prefix(count)))
                    acceptedPrefixes.append("\\(URL(fileURLWithPath: path).lastPathComponent):\\(count)")
                } catch { }
                checked += 1
            }
        }
        let result: [String: Any] = ["checked": checked, "accepted": acceptedPrefixes]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self))
    }
}
''')
            binary = root / "reader"
            subprocess.run([
                "xcrun", "swiftc", "-parse-as-library",
                str(FORMAT / "SceneTexContainer.swift"),
                str(FORMAT / "SceneTexDataReader.swift"),
                str(harness), "-o", str(binary),
            ], check=True, capture_output=True, text=True)
            fixtures = [fixture(version) for version in range(1, 5)]
            fixtures += [fixture(2, sprite_version=version) for version in range(1, 4)]
            fixtures.append(fixture(4, volume=True))
            paths = []
            for index, data in enumerate(fixtures):
                path = root / f"{index}.tex"
                path.write_bytes(data)
                paths.append(str(path))
            result = subprocess.run([str(binary), *paths], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr[-3000:])
            self.assertEqual(json.loads(result.stdout), {
                "checked": sum(map(len, fixtures)), "accepted": [],
            })

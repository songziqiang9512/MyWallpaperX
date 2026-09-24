"""Exercise TEX decompression length checks through the production reader."""

import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORMAT = ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Format"


def tex(payload: bytes, decoded_size: int) -> bytes:
    header = b"TEXV0005\0TEXI0001\0" + struct.pack("<7I", 0, 0, 1, 1, 1, 1, 0)
    table = b"TEXB0002\0" + struct.pack("<2I", 1, 1)
    return header + table + struct.pack("<5I", 1, 1, 1, decoded_size, len(payload)) + payload


class SceneTexDecompressionTests(unittest.TestCase):
    def test_declared_length_requires_complete_decompression(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-tex-decompression-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text('''
import Foundation
@main enum Harness {
    static func main() throws {
        let results = try CommandLine.arguments.dropFirst().map { path -> String in
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            do {
                let container = try SceneTexContainerReader().read(data: data)
                return container.mips[0].data.map { String(format: "%02x", $0) }.joined()
            } catch { return "rejected" }
        }
        print(String(decoding: try JSONEncoder().encode(results), as: UTF8.self))
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
            # Raw LZ4 literal blocks: high token nibble gives literal length.
            cases = [
                (b"\x40\x01\x02\x03\x04", 4, "01020304"),
                (b"\x30\x01\x02\x03", 4, "rejected"),
                (b"\x50\x01\x02\x03\x04\x05", 4, "rejected"),
                (b"\x80\x01\x02\x03\x04\x05\x06\x07\x08", 4, "rejected"),
                (b"\x1fA\x01\x00\x00\x50\x01\x02\x03\x04\x05", 25,
                 "41" * 20 + "0102030405"),
                (b"\x1fA\x01\x00\x00\x50\x01\x02\x03\x04\x05", 24, "rejected"),
                (b"", 4, "rejected"),
                (b"\x80\x01", 4, "rejected"),
            ]
            paths = []
            for index, (payload, decoded_size, _) in enumerate(cases):
                path = root / f"{index}.tex"
                path.write_bytes(tex(payload, decoded_size))
                paths.append(str(path))
            result = subprocess.run([str(binary), *paths], check=True,
                                    capture_output=True, text=True)
            self.assertEqual(json.loads(result.stdout), [case[2] for case in cases])

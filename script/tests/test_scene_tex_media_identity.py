"""Metadata-bearing images must not acquire a video provider identity."""
import json
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


def tex(payload: bytes, metadata_count: int) -> bytes:
    header = b"TEXV0005\0TEXI0001\0" + struct.pack("<7I", 0, 2, 2, 2, 2, 2, 0)
    table = b"TEXB0004\0" + struct.pack("<4I", 1, 13, metadata_count, 1)
    metadata = (struct.pack("<2I", 1, 0) + b'{}\0' + struct.pack("<I", 0)) * metadata_count
    return header + table + metadata + struct.pack("<5I", 2, 2, 0, 0, len(payload)) + payload


class SceneTexMediaIdentityTests(unittest.TestCase):
    def test_payload_identity_is_independent_of_metadata_count(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-media-identity-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text('''
import Foundation
@main enum Harness {
    static func main() throws {
        let results = try CommandLine.arguments.dropFirst().map {
            try SceneTexContainerReader().read(data: Data(contentsOf:
                URL(fileURLWithPath: $0))).isVideoMp4
        }
        print(String(decoding: try JSONEncoder().encode(results), as: UTF8.self))
    }
}
''')
            binary = root / "identity"
            subprocess.run(["xcrun", "swiftc", "-parse-as-library",
                str(SCENE / "Format/SceneTexContainer.swift"),
                str(SCENE / "Format/SceneTexDataReader.swift"),
                str(harness), "-o", str(binary)], check=True, capture_output=True)
            fixtures = []
            expected = []
            # This is only a container media signature fixture, not a playable MP4.
            for payload, video in [(b'\x89PNG\r\n\x1a\n' + bytes(16), False),
                                   (b'\xff\xd8\xff' + bytes(16), False),
                                   (bytes(16), False),
                                   (b'\0\0\0\x14ftypisom' + bytes(8), True)]:
                for count in (0, 1, 2):
                    path = root / f"fixture-{len(fixtures)}.tex"
                    path.write_bytes(tex(payload, count))
                    fixtures.append(str(path))
                    expected.append(video)
            result = subprocess.run([str(binary), *fixtures], check=True,
                                    capture_output=True, text=True)
            self.assertEqual(json.loads(result.stdout), expected)
            registry = (SCENE / "Resources/SceneVideoTextureSourceRegistry.swift").read_text()
            self.assertIn("Self.isMP4Payload(payload)", registry)
            self.assertNotIn("container.isVideoMp4 ||", registry)

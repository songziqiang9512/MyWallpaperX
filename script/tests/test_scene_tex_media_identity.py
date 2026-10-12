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
    def test_large_video_admission_preserves_static_and_container_shape_limits(self) -> None:
        # Match the byte count and container layout of the live MP4 failure.
        # Sparse signature fixtures exercise TEX admission, not playable media.
        payload_size = 257_625_236
        mp4 = b'\0\0\0\x28ftypiso4\0\0\0\0iso4isomobs1iso2avc1mp41'
        webm = bytes.fromhex("1a45dfa3") + bytes(8)
        small_mip = struct.pack("<5I", 1280, 720, 0, 0, 4) + b'ABCD'
        with tempfile.TemporaryDirectory(prefix="mwx-large-media-identity-") as directory:
            root = Path(directory)
            paths, expected = [], []
            cases = [
                ("mp4", mp4, 0, 34, 1, 1, False, b'', True),
                ("webm", webm, 0, 34, 1, 1, False, b'', True),
                ("raw", bytes(12), 0, 34, 1, 1, False, b'', False),
                ("png", b'\x89PNG\r\n\x1a\n' + bytes(4), 0, 34, 1, 1, False, b'', False),
                ("wrong-format", mp4, 4, 34, 1, 1, False, b'', False),
                ("multi-mip", mp4, 0, 34, 1, 2, False, small_mip, False),
                ("multi-image", mp4, 0, 34, 2, 1, False,
                 struct.pack("<I", 1) + small_mip, False),
                ("sprite", mp4, 0, 4, 1, 1, False,
                 b'TEXS0002\0' + struct.pack("<I", 0), False),
                ("volume", mp4, 0, 34, 1, 1, True, b'', False),
            ]
            for name, prefix, format_code, flags, images, mips, volume, tail, admitted in cases:
                values = (format_code, flags, 2, 2, 4, 2, 2, 0) if volume else (
                    format_code, flags, 2560, 1440, 2560, 1440, 0)
                header = b'TEXV0005\0TEXI0001\0' + struct.pack(f'<{len(values)}I', *values)
                header += b'TEXB0004\0' + struct.pack('<IiII', images, 13 if volume else -1, 0, mips)
                header += struct.pack('<3I' if volume else '<2I', *([2, 2, 2] if volume else [2560, 1440]))
                header += struct.pack('<3I', 0, 0, payload_size)
                path = root / f'{name}.tex'
                with path.open('wb') as stream:
                    stream.write(header + prefix)
                    stream.seek(len(header) + payload_size - 1)
                    stream.write(b'Z' + tail)
                paths.append(str(path))
                expected.append(f'video:{payload_size}:90' if admitted else 'invalid-mip')
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
@main enum Harness {
    static func main() throws {
        let results = try CommandLine.arguments.dropFirst().map { path -> String in
            let data = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
            do {
                let container = try SceneTexContainerReader().read(data: data)
                let payload = container.mips[0].data
                guard SceneTexContainer.isVideoPayload(payload) else { return "wrong-identity" }
                return "video:\(payload.count):\(payload.last ?? 0)"
            } catch SceneTexContainerReader.ReadError.invalidMipTable {
                return "invalid-mip"
            } catch { return "other-error:\(error)" }
        }
        print(String(decoding: try JSONEncoder().encode(results), as: UTF8.self))
    }
}
''')
            binary = root / 'identity'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(SCENE / 'Format/SceneTexContainer.swift'),
                str(SCENE / 'Format/SceneTexDataReader.swift'),
                str(harness), '-o', str(binary)], check=True, capture_output=True, timeout=120)
            result = subprocess.run([str(binary), *paths], check=True,
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(json.loads(result.stdout), expected)

    def test_payload_identity_is_independent_of_metadata_count(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-media-identity-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text('''
import Foundation
@main enum Harness {
    static func main() throws {
        let results = try CommandLine.arguments.dropFirst().map {
            let container = try SceneTexContainerReader().read(data: Data(contentsOf:
                URL(fileURLWithPath: $0)))
            let payload = container.mips[0].data
            return [container.isVideoMp4, SceneTexContainer.isVideoPayload(payload),
                    SceneTexContainer.isWebMPayload(payload)]
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
            for payload, mp4, webm in [(b'\x89PNG\r\n\x1a\n' + bytes(16), False, False),
                                   (b'\xff\xd8\xff' + bytes(16), False, False),
                                   (bytes(16), False, False),
                                   (b'\0\0\0\x14ftypisom' + bytes(8), True, False),
                                   (bytes.fromhex("1a45dfa3") + bytes(8), False, True)]:
                for count in (0, 1, 2):
                    path = root / f"fixture-{len(fixtures)}.tex"
                    path.write_bytes(tex(payload, count))
                    fixtures.append(str(path))
                    expected.append([mp4, mp4 or webm, webm])
            result = subprocess.run([str(binary), *fixtures], check=True,
                                    capture_output=True, text=True)
            self.assertEqual(json.loads(result.stdout), expected)
            registry = (ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Resources/Providers/SceneVideoTextureSourceRegistry.swift").read_text()
            loader = (SCENE / "Resources/Textures/SceneTextureLoader.swift").read_text()
            # The registry now consumes the loader's prepared media declaration;
            # both consumers still use the same Format-layer signature authority.
            self.assertIn("loader.videoSourceDeclaration(from: url)", registry)
            self.assertIn("isVideoPayload(payload)", loader)
            self.assertNotIn("container.isVideoMp4 ||", registry)

    def test_small_video_payloads_keep_existing_multi_image_and_mip_behavior(self) -> None:
        payload = b'\0\0\0\x14ftypisom' + bytes(8)
        mip = struct.pack('<5I', 2, 2, 0, 0, len(payload)) + payload
        with tempfile.TemporaryDirectory(prefix='mwx-small-media-shapes-') as directory:
            root = Path(directory)
            paths, expected = [], []
            for image_count, mip_count in [(1, 2), (2, 1), (2, 2)]:
                header = b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', 0, 2, 2, 2, 2, 2, 0)
                header += b'TEXB0002\0' + struct.pack('<I', image_count)
                path = root / f'{image_count}-{mip_count}.tex'
                path.write_bytes(header + (struct.pack('<I', mip_count) + mip * mip_count) * image_count)
                paths.append(str(path))
                expected.append([image_count, mip_count, image_count * mip_count * len(payload)])
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
@main enum Harness {
    static func main() throws {
        let results = try CommandLine.arguments.dropFirst().map { path -> [Int] in
            let container = try SceneTexContainerReader().read(
                data: Data(contentsOf: URL(fileURLWithPath: path)))
            guard container.images.flatMap(\.mips).allSatisfy({
                SceneTexContainer.isMP4Payload($0.data)
            }) else { return [] }
            return [container.images.count, container.mips.count,
                    container.images.flatMap(\.mips).reduce(0) { $0 + $1.data.count }]
        }
        print(String(decoding: try JSONEncoder().encode(results), as: UTF8.self))
    }
}
''')
            binary = root / 'identity'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(SCENE / 'Format/SceneTexContainer.swift'),
                str(SCENE / 'Format/SceneTexDataReader.swift'),
                str(harness), '-o', str(binary)], check=True, capture_output=True, timeout=120)
            result = subprocess.run([str(binary), *paths], check=True,
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(json.loads(result.stdout), expected)

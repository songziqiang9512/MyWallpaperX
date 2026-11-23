"""Metadata-bearing images must not acquire a video provider identity."""
import json
import struct
import subprocess
import tempfile
import unittest
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"


def tex(payload: bytes, metadata_count: int) -> bytes:
    header = b"TEXV0005\0TEXI0001\0" + struct.pack("<7I", 0, 2, 2, 2, 2, 2, 0)
    table = b"TEXB0004\0" + struct.pack("<4I", 1, 13, metadata_count, 1)
    metadata = (struct.pack("<2I", 1, 0) + b'{}\0' + struct.pack("<I", 0)) * metadata_count
    return header + table + metadata + struct.pack("<5I", 2, 2, 0, 0, len(payload)) + payload


class SceneTexMediaIdentityTests(unittest.TestCase):
    def test_conditional_png_mips_keep_base_and_bound_optional_patches(self) -> None:
        def rgba_png(width: int, height: int, color: bytes) -> bytes:
            def chunk(kind: bytes, data: bytes = b'') -> bytes:
                return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

            return (b'\x89PNG\r\n\x1a\n'
                    + chunk(b'IHDR', struct.pack('>2I5B', width, height, 8, 6, 0, 0, 0))
                    + chunk(b'IDAT', zlib.compress((b'\0' + color * width) * height)) + chunk(b'IEND'))

        def patch(id: int, x: int, y: int, width: int, height: int, payload: bytes) -> bytes:
            return struct.pack('<8I', 1, id, x, y, width, height, 13, len(payload)) + payload

        def mip(size: int, base: bytes, *patches: bytes) -> bytes:
            return (struct.pack('<5I', size, size, 0, 0, len(base)) + base
                    + struct.pack('<2I', 1, len(patches)) + b''.join(patches))

        header = b'TEXV0005\0TEXI0001\0' + struct.pack('<7I', 0, 2, 4, 4, 4, 4, 0)
        declarations = [(21, {'condition': 'themed'}), (9, {'condition': {'condition': '2', 'name': 'style'}}),
                        (27, {'condition': {'future': True}})]
        header += b'TEXB0004\0' + struct.pack('<3I', 1, 13, len(declarations))
        for id, declaration in declarations:
            header += struct.pack('<3I', 1, id, 0) + json.dumps(declaration).encode() + b'\0'
        header += struct.pack('<I', 2)

        base0 = rgba_png(4, 4, bytes([208, 190, 133, 255]))
        base1 = rgba_png(2, 2, bytes([185, 159, 120, 255]))
        clear0 = rgba_png(2, 2, bytes(4))
        clear1 = rgba_png(1, 2, bytes(4))
        combo0 = rgba_png(1, 1, bytes([40, 91, 255, 255]))
        combo1 = rgba_png(1, 1, bytes([40, 88, 235, 255]))
        optional0 = [patch(9, 0, 3, 1, 1, combo0), patch(27, 0, 0, 1, 1, combo0)]
        tail = mip(2, base1, patch(21, 1, 0, 1, 2, clear1), patch(9, 0, 1, 1, 1, combo1))
        valid = header + mip(4, base0, patch(21, 1, 1, 2, 2, clear0), *optional0) + tail
        out_of_bounds = header + mip(4, base0, patch(21, 3, 1, 2, 2, clear0), *optional0) + tail
        bad_patch_png = header + mip(4, base0, patch(21, 1, 1, 2, 2, bytes(len(clear0))), *optional0) + tail
        combo_declaration = header.index(struct.pack('<3I', 1, 9, 0))
        unknown_kind = bytearray(valid)
        struct.pack_into('<I', unknown_kind, combo_declaration, 7)
        reserved_word = bytearray(valid)
        struct.pack_into('<I', reserved_word, combo_declaration + 8, 0xfedcba98)
        base_budget = len(base0) + len(base1)
        base = [[4, 4, base0.hex()], [2, 2, base1.hex()]]
        themed = [21, ['bool', 'themed'], [[0, 1, 1, 2, 2, clear0.hex()], [1, 1, 0, 1, 2, clear1.hex()]]]
        combo = [9, ['equals', 'style', '2'], [[0, 0, 3, 1, 1, combo0.hex()], [1, 0, 1, 1, 1, combo1.hex()]]]
        cases = [
            ('valid', valid, 10_000, [base, [themed, combo]]),
            ('unknown-declaration-kind', unknown_kind, 10_000, [base, [themed]]),
            ('unknown-reserved-word', reserved_word, 10_000, [base, [themed, combo]]),
            ('out-of-bounds', out_of_bounds, 10_000, [base, [combo]]),
            ('bad-patch-png', bad_patch_png, 10_000, [base, [combo]]),
            ('budget', valid, base_budget, [base, []]),
            ('budget-one-variant', valid, base_budget + len(clear0) + len(clear1), [base, [themed]]),
            ('base-over-budget', valid, base_budget - 1, 'budget-exceeded'),
            ('partial-final-tail', valid[:-1], 10_000, [base, []]),
        ]
        with tempfile.TemporaryDirectory(prefix='mwx-conditional-tex-') as directory:
            root = Path(directory)
            harness = root / 'Harness.swift'
            harness.write_text(r'''
import Foundation
@main enum Harness {
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    static func main() throws {
        let results = try CommandLine.arguments.dropFirst().map { argument -> Any in
            let input = argument.split(separator: "=", maxSplits: 1)
            let data = try Data(contentsOf: URL(fileURLWithPath: String(input[1])))
            do {
                let texture = try SceneTexContainerReader().read(
                    data: data, maximumDecodedByteCount: Int(input[0])!)
                let base = texture.mips.map { mip -> [Any] in [mip.width, mip.height, hex(mip.data)] }
                let variants = texture.conditionalVariants.map { variant -> [Any] in
                    let condition: [String] = switch variant.condition {
                    case .boolean(let key): ["bool", key]
                    case .equals(let key, let value): ["equals", key, value]
                    }
                    let patches = variant.mipPatches.map { patch -> [Any] in
                        [patch.mipLevel, patch.x, patch.y, patch.width, patch.height, hex(patch.data)]
                    }
                    return [variant.id, condition, patches]
                }
                return [base, variants]
            } catch SceneTexContainerReader.ReadError.decodedDataBudgetExceeded {
                return "budget-exceeded"
            }
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results), as: UTF8.self))
    }
}
''')
            binary = root / 'conditional-reader'
            subprocess.run(['xcrun', 'swiftc', '-parse-as-library',
                str(SCENE / 'Format/SceneTexContainer.swift'), str(SCENE / 'Format/SceneTexDataReader.swift'),
                str(harness), '-o', str(binary)], check=True, timeout=120)
            args = []
            for name, data, budget, _ in cases:
                path = root / f'{name}.tex'
                path.write_bytes(data)
                args.append(f'{budget}={path}')
            result = subprocess.run([str(binary), *args], check=True,
                                    capture_output=True, text=True, timeout=60)
            self.assertEqual(json.loads(result.stdout), [expected for _, _, _, expected in cases])

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

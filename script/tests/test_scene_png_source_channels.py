"""Round-trip independently encoded PNG rows through the production source reader."""
import json
from pathlib import Path
import random
import struct
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'MyWallpaperX/Core/SteamWorkshopScene/Resources/Textures/SceneImageTextureUploader.swift'
SIGNATURE = b'\x89PNG\r\n\x1a\n'
PASSES = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
          (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))


def png(width, height, pixels, interlaced=False, row_filter=0, raw=None):
    scanlines = bytearray()
    for sx, sy, dx, dy in PASSES if interlaced else [(0, 0, 1, 1)]:
        previous = None
        for y in range(sy, height, dy):
            row = b''.join(pixels[(y * width + x) * 4:(y * width + x + 1) * 4]
                           for x in range(sx, width, dx))
            if not row:
                continue
            previous = previous or bytes(len(row))
            encoded = bytearray()
            for i, value in enumerate(row):
                left = row[i - 4] if i >= 4 else 0
                above = previous[i]
                corner = previous[i - 4] if i >= 4 else 0
                p = left + above - corner
                paeth = min((left, above, corner), key=lambda v: abs(p - v))
                prediction = [0, left, above, (left + above) // 2, paeth][row_filter]
                encoded.append((value - prediction) % 256)
            scanlines.extend(bytes([row_filter]) + encoded)
            previous = row
    header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, int(interlaced))
    return (SIGNATURE + chunk(b'IHDR', header)
            + chunk(b'IDAT', zlib.compress(bytes(scanlines) if raw is None else raw))
            + chunk(b'IEND', b''))


class PNGSourceChannelsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='mwx-png-source-')
        cls.root = Path(cls.directory.name)
        harness = cls.root / 'main.swift'
        harness.write_text('''import Foundation
import CoreGraphics
import Metal
enum SceneTextureLoadOutcome {
    case loaded(MTLTexture), decodeFailed(String)
    case textureAllocationFailed(width: Int, height: Int)
}
for path in CommandLine.arguments.dropFirst() {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    if let image = SceneImageTextureUploader.decodeSourceImage(data),
       let bytes = image.dataProvider?.data {
        print(String(decoding: try JSONEncoder().encode(Array(bytes as Data)), as: UTF8.self))
    } else { print("null") }
}
''')
        cls.binary = cls.root / 'decode'
        compiled = subprocess.run(['xcrun', 'swiftc', str(SOURCE), str(harness), '-o', str(cls.binary)],
                                  capture_output=True, text=True, timeout=60)
        if compiled.returncode:
            cls.directory.cleanup()
            raise RuntimeError(compiled.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def decode(self, *sources):
        paths = []
        for index, source in enumerate(sources):
            path = self.root / f'{index}.png'
            path.write_bytes(source)
            paths.append(str(path))
        run = subprocess.run([str(self.binary), *paths], capture_output=True, text=True, timeout=15)
        self.assertEqual(run.returncode, 0, run.stderr)
        return [json.loads(line) for line in run.stdout.splitlines()]

    def test_every_filter_and_interlace_retains_all_four_channels(self):
        for width, height in [(1, 1), (2, 3), (9, 11)]:
            rng = random.Random(4231)
            pixels = bytes(v for _ in range(width * height)
                           for v in [rng.randrange(256), rng.randrange(256), rng.randrange(256), rng.choice([0, 64, 255])])
            for interlaced in [False, True]:
                with self.subTest(size=(width, height), interlaced=interlaced):
                    outputs = self.decode(*(png(width, height, pixels, interlaced, f) for f in range(5)))
                    self.assertEqual(outputs, [list(pixels)] * 5)

    def test_corruption_and_bounded_decode_fail_without_image_fallback(self):
        good = png(1, 1, bytes([231, 17, 149, 0]))
        bad_crc = bytearray(good); bad_crc[29] ^= 1
        huge = SIGNATURE + chunk(b'IHDR', struct.pack('>IIBBBBB', 16384, 16384, 8, 6, 0, 0, 0)) + good[33:]
        unknown = good[:33] + chunk(b'NOPE', b'') + good[33:]
        invalid = [bytes(bad_crc), good[:-12], huge, unknown,
                   png(1, 1, b'', raw=b'\x05\x01\x02\x03\x04'),
                   png(1, 1, b'', raw=b'\x00\x01\x02\x03'),
                   png(1, 1, b'', raw=b'\x00\x01\x02\x03\x04\x05')]
        self.assertEqual(self.decode(*invalid), [None] * len(invalid))

    def test_consecutive_split_idat_is_accepted_but_separated_data_is_rejected(self):
        pixels = bytes([231, 17, 149, 0])
        good = png(1, 1, pixels)
        compressed = zlib.compress(b'\x00' + pixels)
        first, second = chunk(b'IDAT', compressed[:4]), chunk(b'IDAT', compressed[4:])
        split = good[:33] + first + second + chunk(b'IEND', b'')
        separated = good[:33] + first + chunk(b'tEXt', b'note\x00text') + second + chunk(b'IEND', b'')
        self.assertEqual(self.decode(split, separated), [list(pixels), None])

    def test_animated_png_retains_first_animation_frame_instead_of_excluded_poster(self):
        header = chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0))
        animation = chunk(b'acTL', struct.pack('>II', 1, 0))
        poster = chunk(b'IDAT', zlib.compress(bytes([0, 255, 0, 0, 255])))
        control = chunk(b'fcTL', struct.pack('>IIIIIHHBB', 0, 1, 1, 0, 0, 1, 10, 0, 0))
        frame = chunk(b'fdAT', struct.pack('>I', 1) + zlib.compress(bytes([0, 0, 255, 0, 255])))
        source = SIGNATURE + header + animation + poster + control + frame + chunk(b'IEND', b'')
        self.assertEqual(self.decode(source), [[0, 255, 0, 255]])

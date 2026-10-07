#!/usr/bin/env python3
"""Behavior tests for prepared MDLV0023 part ranges and raw clipping relations."""
from __future__ import annotations
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

from script.tests.test_scene_puppet_mesh import build_mdl

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / 'MyWallpaperX/Core/SteamWorkshopScene/Format/SceneMdlPuppetMeshReader.swift'

HARNESS = r'''
import Foundation

@main enum Harness {
    static func main() throws {
        let output = try CommandLine.arguments.dropFirst().map { path -> [String: Any] in
            var row: [String: Any] = ["file": (path as NSString).lastPathComponent]
            let input = try Data(contentsOf: URL(fileURLWithPath: path))
            do {
                // Nonzero Data indices must not affect authored absolute ranges.
                let wrapped = Data([99]) + input
                let mesh = try SceneMdlPuppetMeshReader.read(data: wrapped.dropFirst())
                row["ok"] = true
                row["vertices"] = mesh.vertices.map { [Double($0.x), Double($0.y)] }
                row["indexCount"] = mesh.indices.count
                row["parts"] = mesh.drawParts.map {
                    ["ordinal": $0.ordinal, "id": Int($0.id), "flags": Int($0.flags),
                     "start": $0.indexOffset, "count": $0.indexCount]
                }
                row["clips"] = mesh.clipRecords.map {
                    ["id": Int($0.id), "flags": Int($0.flags),
                     "options": [Int($0.rawOptions.x), Int($0.rawOptions.y)],
                     "path": $0.maskTexturePath, "target": $0.targetPartOrdinal,
                     "sources": $0.sourcePartOrdinals] as [String: Any]
                }
            } catch {
                row["ok"] = false
                row["error"] = String(describing: error)
            }
            return row
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output))
    }
}
'''


def record(target=1, sources=(0, 1, 2), path=b'masks/paint', options=(0, 1), flags=0, identifier=17):
    return struct.pack('<2I', identifier, flags) + path + b'\0' + struct.pack(
        '<4I', *options, target, len(sources)) + struct.pack('<' + 'I' * len(sources), *sources)


def suffix(*, extra=True, parts=None, records=None, extra_count=1, extra_size=36):
    if parts is None:
        parts = [(33, 0, 0, 3), (18, 0, 3, 3), (9, 0, 6, 3)]
    if records is None:
        records = [record()]
    result = bytearray(bytes([extra]))
    if extra:
        result += struct.pack('<2I', extra_count, extra_size) + bytes(extra_size)
    result += bytes([bool(parts)])
    if parts:
        result += struct.pack('<I', len(parts) * 16)
        result += b''.join(struct.pack('<4I', *p) for p in parts)
    result += struct.pack('<I', len(records)) + b''.join(records)
    return bytes(result)


def fixture(tail, magic=b'MDLV0023', stride=80):
    return build_mdl(magic=magic, stride=stride, include_mdls=False,
                     indices=[0, 1, 2] * 3) + tail + b'MDLS0004\0' + bytes(8)


class ScenePuppetClippingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which('swiftc'):
            raise unittest.SkipTest('swiftc unavailable')
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        harness = root / 'Harness.swift'
        harness.write_text(HARNESS)
        cls.binary = root / 'harness'
        result = subprocess.run(['swiftc', str(SOURCE), str(harness), '-o', str(cls.binary)],
                                capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stderr)
        fixtures = {
            'clip': fixture(suffix()),
            'no-extra': fixture(suffix(extra=False)),
            'no-clip': fixture(suffix(records=[])),
            'no-parts': fixture(suffix(extra=False, parts=[], records=[])),
            'bare-modern': fixture(b''),
            'legacy': fixture(b'uninterpreted old-version suffix', b'MDLV0016', 52),
            'multi': fixture(suffix(records=[record(0, (2,)), record(2, (0, 1), identifier=18)])),
            'duplicates': fixture(suffix(records=[record(1, (0, 0, 1))])),
            'huge-id': fixture(suffix(parts=[(0xffffffff, 0, 0, 3), (18, 0, 3, 3), (9, 0, 6, 3)])),
            'target-oob': fixture(suffix(records=[record(3)])),
            'source-oob': fixture(suffix(records=[record(sources=(0xffffffff,))])),
            'source-empty': fixture(suffix(records=[record(sources=())])),
            'duplicate-target': fixture(suffix(records=[record(), record(identifier=18)])),
            'unsupported-options': fixture(suffix(records=[record(options=(0, 2))])),
            'unsupported-flags': fixture(suffix(records=[record(flags=1)])),
            'path-empty': fixture(suffix(records=[record(path=b'')])),
            'path-invalid-utf8': fixture(suffix(records=[record(path=b'\xff')])),
            'truncated-record': fixture(suffix()[:-1]),
            'truncated-envelope': fixture(b'\1'),
            'extra-track-count': fixture(suffix(extra_count=2)),
            'extra-size': fixture(suffix(extra_size=24)),
            'trailing-byte': fixture(suffix() + b'\0'),
            'empty-seven': fixture(bytes(7)),
            'empty-seven-nonzero': fixture(bytes(6) + b'\1'),
            'empty-eight': fixture(bytes(8)),
            'empty-parts': fixture(suffix(parts=[
                (10, 0, 0, 0), (11, 0, 0, 3), (12, 0, 3, 0),
                (13, 0, 3, 6), (14, 0, 9, 0)], records=[record(3, (1, 2))])),
        }
        for label, changed in [
            ('range-gap', (18, 0, 6, 3)), ('range-overlap', (18, 0, 0, 3)),
            ('range-misaligned', (18, 0, 3, 2)), ('range-oob', (18, 0, 3, 0xffffffff)),
            ('part-flags', (18, 1, 3, 3)), ('range-zero', (18, 0, 3, 0)),
        ]:
            fixtures[label] = fixture(suffix(parts=[(33, 0, 0, 3), changed, (9, 0, 6, 3)]))
        fixtures['missing-index-tail'] = fixture(suffix(parts=[(33, 0, 0, 3), (18, 0, 3, 3)], records=[]))
        malformed = bytearray(suffix())
        malformed[45] = 2  # draw-part presence, after one 36-byte opaque stream
        fixtures['presence'] = fixture(bytes(malformed))
        malformed = bytearray(suffix())
        struct.pack_into('<I', malformed, 46, 47)
        fixtures['part-byte-count'] = fixture(bytes(malformed))
        for size in range(0, len(suffix())):
            fixtures[f'cut-{size}'] = fixture(suffix()[:size])
        paths = []
        for label, data in fixtures.items():
            path = root / (label + '.mdl')
            path.write_bytes(data)
            paths.append(str(path))
        result = subprocess.run([str(cls.binary), *paths], capture_output=True, text=True)
        if result.returncode:
            raise AssertionError(result.stderr)
        cls.results = {row['file'].removesuffix('.mdl'): row for row in json.loads(result.stdout)}

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_part_order_ranges_and_uninterpreted_identity_are_retained(self):
        value = self.results['clip']
        self.assertTrue(value['ok'], value)
        self.assertEqual(value['parts'], [
            dict(ordinal=0, id=33, flags=0, start=0, count=3),
            dict(ordinal=1, id=18, flags=0, start=3, count=3),
            dict(ordinal=2, id=9, flags=0, start=6, count=3),
        ])
        self.assertEqual(value['vertices'], [[-10, -20], [10, -20], [0, 20]])
        self.assertEqual(self.results['huge-id']['parts'][0]['id'], 0xffffffff)

    def test_self_and_duplicate_source_candidates_are_preserved_without_fake_dag(self):
        self.assertEqual(self.results['clip']['clips'], [
            dict(id=17, flags=0, options=[0, 1], path='masks/paint', target=1, sources=[0, 1, 2])])
        self.assertEqual(self.results['duplicates']['clips'][0]['sources'], [0, 0, 1])
        self.assertTrue(self.results['multi']['ok'], self.results['multi'])

    def test_optional_stream_and_empty_clip_layout_keep_geometry(self):
        self.assertTrue(self.results['no-extra']['ok'], self.results['no-extra'])
        self.assertEqual(len(self.results['no-clip']['parts']), 3)
        self.assertEqual(self.results['no-clip']['clips'], [])
        self.assertEqual(self.results['no-parts']['parts'], [])
        self.assertEqual(self.results['no-parts']['clips'], [])

    def test_old_and_bare_layouts_keep_existing_mesh_contract(self):
        for label in ['legacy', 'bare-modern', 'empty-seven']:
            self.assertTrue(self.results[label]['ok'], self.results[label])
            self.assertEqual(self.results[label]['parts'], [])
            self.assertEqual(self.results[label]['clips'], [])

    def test_empty_parts_preserve_ordinals_and_clipping_references(self):
        value = self.results['empty-parts']
        self.assertTrue(value['ok'], value)
        self.assertEqual([p['count'] for p in value['parts']], [0, 3, 0, 6, 0])
        self.assertEqual([p['ordinal'] for p in value['parts']], list(range(5)))
        self.assertEqual(value['clips'][0]['target'], 3)
        self.assertEqual(value['clips'][0]['sources'], [1, 2])

    def test_ranges_must_partition_the_original_triangle_indices_in_order(self):
        for label in ['range-gap', 'range-overlap', 'range-misaligned', 'range-oob',
                      'range-zero', 'part-flags', 'missing-index-tail']:
            with self.subTest(label=label):
                self.assertFalse(self.results[label]['ok'], self.results[label])
                self.assertIn('draw-part', self.results[label]['error'])

    def test_relation_indices_paths_and_options_are_bounded(self):
        for label in ['target-oob', 'source-oob', 'source-empty', 'duplicate-target',
                      'unsupported-options', 'unsupported-flags', 'path-empty', 'path-invalid-utf8']:
            with self.subTest(label=label):
                self.assertFalse(self.results[label]['ok'], self.results[label])

    def test_every_nonempty_truncated_suffix_and_unknown_shape_fails_closed(self):
        labels = [key for key in self.results if key.startswith('cut-') and key != 'cut-0']
        labels += ['truncated-record', 'truncated-envelope', 'extra-track-count',
                   'extra-size', 'trailing-byte', 'presence', 'part-byte-count',
                   'empty-seven-nonzero', 'empty-eight']
        for label in labels:
            with self.subTest(label=label):
                self.assertFalse(self.results[label]['ok'], self.results[label])


if __name__ == '__main__':
    unittest.main()

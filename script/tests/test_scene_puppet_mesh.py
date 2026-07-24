#!/usr/bin/env python3

"""Contract tests for SceneMdlPuppetMeshReader.

Builds synthetic MDLV binaries covering the verified mesh-block shape
(stride 80 and 84, position at offset 0, UV in the trailing 8 bytes,
uint16 triangle indices) plus the fail-closed rejections, then checks the
Swift reader against them through a compiled harness.
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
    SCENE_ROOT / "Format/SceneMdlPuppetMeshReader.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        var results: [[String: Any]] = []
        for path in CommandLine.arguments.dropFirst() {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            var entry: [String: Any] = ["file": (path as NSString).lastPathComponent]
            do {
                let mesh = try SceneMdlPuppetMeshReader.read(data: data)
                entry["ok"] = true
                entry["version"] = mesh.version
                entry["stride"] = mesh.vertexStride
                entry["blockOffset"] = mesh.meshBlockOffset
                entry["vertexCount"] = mesh.vertices.count
                entry["triangleCount"] = mesh.triangleCount
                entry["indices"] = mesh.indices.map(Int.init)
                entry["vertices"] = mesh.vertices.map { vertex in
                    [
                        Double(vertex.x), Double(vertex.y), Double(vertex.z),
                        Double(vertex.u), Double(vertex.v),
                    ]
                }
            } catch let error as SceneMdlPuppetMeshReadError {
                entry["ok"] = false
                entry["error"] = error.description
            }
            results.append(entry)
        }
        let payload = try JSONSerialization.data(withJSONObject: results)
        FileHandle.standardOutput.write(payload)
    }
}
'''


def build_mdl(
    magic: bytes = b"MDLV0023",
    stride: int = 80,
    vertices=None,
    indices=None,
    prefix_noise: bytes = b"\x00" * 24,
    include_mdls: bool = True,
    suffix: bytes = b"",
) -> bytes:
    """Assembles a minimal MDLV binary with one mesh block."""
    if vertices is None:
        vertices = [
            (-10.0, -20.0, 0.0, 0.25, 0.75),
            (10.0, -20.0, 0.0, 0.5, 0.75),
            (0.0, 20.0, 0.0, 0.375, 0.25),
        ]
    if indices is None:
        indices = [0, 1, 2, 2, 1, 0]
    vertex_blob = b""
    for x, y, z, u, v in vertices:
        record = struct.pack("<3f", x, y, z)
        record += b"\x00" * (stride - 20)
        record += struct.pack("<2f", u, v)
        vertex_blob += record
    index_blob = struct.pack("<%dH" % len(indices), *indices)
    body = magic + b"\x00" + prefix_noise
    body += struct.pack("<II", 0, len(vertex_blob))
    body += vertex_blob
    body += struct.pack("<I", len(index_blob))
    body += index_blob
    if include_mdls:
        body += b"MDLS" + b"\x00" * 16
    body += suffix
    return body


class SceneMdlPuppetMeshReaderTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory()
        tmp = Path(cls._tmp.name)
        harness = tmp / "harness.swift"
        harness.write_text(HARNESS)
        cls.binary = tmp / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")

        cls.fixtures = {
            "stride80.mdl": build_mdl(),
            "stride84.mdl": build_mdl(stride=84),
            "mdlv0021.mdl": build_mdl(magic=b"MDLV0021"),
            "bad-magic.mdl": build_mdl(magic=b"MDLX0001"),
            "no-block.mdl": b"MDLV0023\x00" + b"\x00" * 64 + b"MDLS",
            # max(index) == 1 while the vertex bytes describe 3 vertices, so
            # no stride candidate can satisfy max == count-1.
            "sparse-indices.mdl": build_mdl(indices=[0, 1, 1, 1, 0, 0]),
            "nan-vertex.mdl": build_mdl(
                vertices=[
                    (float("nan"), 0.0, 0.0, 0.0, 0.0),
                    (1.0, 0.0, 0.0, 1.0, 0.0),
                    (0.0, 1.0, 0.0, 0.0, 1.0),
                ]
            ),
            # A fake block after the MDLS marker must not be scanned.
            "after-mdls.mdl": b"MDLV0023\x00" + b"\x00" * 8 + b"MDLS"
            + build_mdl()[9:],
        }
        for name, blob in cls.fixtures.items():
            (tmp / name).write_bytes(blob)
        completed = subprocess.run(
            [str(cls.binary), *[str(tmp / name) for name in cls.fixtures]],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.results = {entry["file"]: entry for entry in json.loads(completed.stdout)}

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_stride_80_block_parses_positions_uv_and_indices(self):
        entry = self.results["stride80.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["version"], "MDLV0023")
        self.assertEqual(entry["stride"], 80)
        self.assertEqual(entry["vertexCount"], 3)
        self.assertEqual(entry["triangleCount"], 2)
        self.assertEqual(entry["indices"], [0, 1, 2, 2, 1, 0])
        self.assertEqual(
            entry["vertices"][0], [-10.0, -20.0, 0.0, 0.25, 0.75]
        )
        self.assertEqual(entry["vertices"][2], [0.0, 20.0, 0.0, 0.375, 0.25])

    def test_stride_84_block_reads_uv_from_trailing_bytes(self):
        entry = self.results["stride84.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["stride"], 84)
        self.assertEqual(entry["vertices"][1], [10.0, -20.0, 0.0, 0.5, 0.75])

    def test_mdlv0021_magic_is_accepted(self):
        entry = self.results["mdlv0021.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["version"], "MDLV0021")

    def test_unknown_magic_fails_closed(self):
        entry = self.results["bad-magic.mdl"]
        self.assertFalse(entry["ok"])
        self.assertIn("unsupported puppet mdl magic", entry["error"])

    def test_missing_block_fails_closed(self):
        entry = self.results["no-block.mdl"]
        self.assertFalse(entry["ok"])
        self.assertIn("no strict bind-pose mesh block", entry["error"])

    def test_partial_index_coverage_fails_closed(self):
        entry = self.results["sparse-indices.mdl"]
        self.assertFalse(entry["ok"])
        self.assertIn("no strict bind-pose mesh block", entry["error"])

    def test_non_finite_vertex_fails_closed(self):
        entry = self.results["nan-vertex.mdl"]
        self.assertFalse(entry["ok"])
        self.assertIn("non-finite vertex data", entry["error"])

    def test_blocks_after_mdls_marker_are_not_scanned(self):
        entry = self.results["after-mdls.mdl"]
        self.assertFalse(entry["ok"])
        self.assertIn("no strict bind-pose mesh block", entry["error"])


if __name__ == "__main__":
    unittest.main()

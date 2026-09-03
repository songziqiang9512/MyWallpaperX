#!/usr/bin/env python3
"""Contract tests for the bounded direct MDLV0016/MDLV0023 model reader."""

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
    SCENE_ROOT / "Format/SceneMdlStaticModel.swift",
    SCENE_ROOT / "Format/SceneMdlStaticModelReader.swift",
]

HARNESS = r'''
import Foundation

@main
enum Harness {
    static func main() throws {
        var results: [[String: Any]] = []
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            var entry: [String: Any] = ["file": url.lastPathComponent]
            do {
                let data = try Data(contentsOf: url)
                entry["metadataMaterialPath"] = try? SceneMdlStaticModelReader
                    .readMaterialPathMetadata(data: data)
                let model = try SceneMdlStaticModelReader.read(data: data)
                entry["ok"] = true
                entry["version"] = model.version
                entry["headerFormat"] = model.headerFormat
                entry["vertexFormat"] = model.vertexFormat
                entry["vertexStride"] = model.vertexStride
                entry["indexElementSize"] = model.indexElementSize
                entry["materialPath"] = model.materialPath
                entry["vertexMemoryStride"] = MemoryLayout<SceneMdlStaticModel.Vertex>.stride
                entry["positionOffset"] = MemoryLayout<SceneMdlStaticModel.Vertex>.offset(
                    of: \SceneMdlStaticModel.Vertex.position
                )
                entry["normalOffset"] = MemoryLayout<SceneMdlStaticModel.Vertex>.offset(
                    of: \SceneMdlStaticModel.Vertex.normal
                )
                entry["tangentOffset"] = MemoryLayout<SceneMdlStaticModel.Vertex>.offset(
                    of: \SceneMdlStaticModel.Vertex.tangent
                )
                entry["uvOffset"] = MemoryLayout<SceneMdlStaticModel.Vertex>.offset(
                    of: \SceneMdlStaticModel.Vertex.uv
                )
                entry["boundsMinimum"] = model.bounds.minimum.map(Double.init)
                entry["boundsMaximum"] = model.bounds.maximum.map(Double.init)
                entry["triangleCount"] = model.triangleCount
                entry["indices"] = model.indices.map(Int.init)
                entry["vertices"] = model.vertices.map { vertex in
                    [
                        "position": [
                            vertex.position.x, vertex.position.y, vertex.position.z,
                        ].map(Double.init),
                        "normal": [
                            vertex.normal.x, vertex.normal.y, vertex.normal.z,
                        ].map(Double.init),
                        "tangent": [
                            vertex.tangent.x, vertex.tangent.y,
                            vertex.tangent.z, vertex.tangent.w,
                        ].map(Double.init),
                        "uv": [vertex.uv.x, vertex.uv.y].map(Double.init),
                    ]
                }
            } catch let error as SceneMdlStaticModelReadError {
                entry["ok"] = false
                entry["error"] = error.description
            }
            results.append(entry)
        }
        let payload = try JSONSerialization.data(
            withJSONObject: results,
            options: [.sortedKeys]
        )
        FileHandle.standardOutput.write(payload)
    }
}
'''


DEFAULT_VERTICES = [
    (
        (-1.0, -1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 0.0, -1.0),
        (0.0, 0.0),
    ),
    (
        (1.0, -1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 0.0, -1.0),
        (1.0, 0.0),
    ),
    (
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 0.0, -1.0),
        (0.5, 1.0),
    ),
]


def build_model(
    *,
    magic: bytes = b"MDLV0023\0",
    header_format: int = 15,
    mesh_count: int = 1,
    material_count: int = 1,
    material: bytes = b"materials/models/fixture/default.json",
    index_flag: int = 0,
    bounds=(-1.0, -1.0, -1.0, 1.0, 1.0, 1.0),
    vertex_format: int = 15,
    vertices=DEFAULT_VERTICES,
    indices=(0, 1, 2),
    declared_vertex_byte_count: int | None = None,
    declared_index_byte_count: int | None = None,
    trailer: bytes = b"\0" * 7,
) -> bytes:
    vertex_blob = b"".join(
        struct.pack("<12f", *(position + normal + tangent + uv))
        for position, normal, tangent, uv in vertices
    )
    if index_flag == 1:
        index_blob = struct.pack(f"<{len(indices)}I", *indices)
    else:
        index_blob = struct.pack(f"<{len(indices)}H", *indices)
    return b"".join(
        [
            magic,
            struct.pack("<III", header_format, mesh_count, material_count),
            material,
            b"\0",
            struct.pack(
                "<I6fII",
                index_flag,
                *bounds,
                vertex_format,
                declared_vertex_byte_count
                if declared_vertex_byte_count is not None
                else len(vertex_blob),
            ),
            vertex_blob,
            struct.pack(
                "<I",
                declared_index_byte_count
                if declared_index_byte_count is not None
                else len(index_blob),
            ),
            index_blob,
            trailer,
        ]
    )


def build_legacy_model(
    *,
    material: bytes = b"materials/models/fixture/legacy.json",
    vertices=DEFAULT_VERTICES,
    indices=(0, 1, 2),
    trailer: bytes = b"\0",
) -> bytes:
    vertex_blob = b"".join(
        struct.pack("<12f", *(position + normal + tangent + uv))
        for position, normal, tangent, uv in vertices
    )
    index_blob = struct.pack(f"<{len(indices)}H", *indices)
    return b"".join(
        [
            b"MDLV0016\0",
            struct.pack("<III", 15, 1, 1),
            material,
            b"\0",
            struct.pack("<III", 0, 15, len(vertex_blob)),
            vertex_blob,
            struct.pack("<I", len(index_blob)),
            index_blob,
            trailer,
        ]
    )


class SceneMdlStaticModelReaderTests(unittest.TestCase):
    maxDiff = None

    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls._tmp = tempfile.TemporaryDirectory(prefix="mwx-static-model-reader-")
        root = Path(cls._tmp.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "harness"
        compilation = subprocess.run(
            ["swiftc", *map(str, SWIFT_SOURCES), str(harness), "-o", str(cls.binary)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if compilation.returncode != 0:
            raise AssertionError(f"harness compilation failed:\n{compilation.stderr}")

        fixtures = {
            "valid.mdl": build_model(),
            "legacy-valid.mdl": build_legacy_model(),
            "windows-material.mdl": build_model(
                material=b"materials\\models\\fixture\\default.json"
            ),
            "old-version.mdl": build_model(magic=b"MDLV0015\0"),
            "bad-nul.mdl": build_model(magic=b"MDLV0023X"),
            "bad-header-format.mdl": build_model(header_format=14),
            "multi-mesh.mdl": build_model(mesh_count=2),
            "multi-material.mdl": build_model(material_count=2),
            "unsafe-material.mdl": build_model(material=b"../escape.json"),
            "invalid-utf8-material.mdl": build_model(material=b"materials/\xff.json"),
            "uint32-indices.mdl": build_model(index_flag=1),
            "nan-bounds.mdl": build_model(
                bounds=(float("nan"), -1, -1, 1, 1, 1)
            ),
            "inverted-bounds.mdl": build_model(bounds=(2, -1, -1, 1, 1, 1)),
            "bad-vertex-format.mdl": build_model(vertex_format=7),
            "empty-vertices.mdl": build_model(vertices=[]),
            "bad-vertex-bytes.mdl": build_model(declared_vertex_byte_count=47),
            "vertex-budget.mdl": build_model(
                declared_vertex_byte_count=67_108_896
            ),
            "nan-vertex.mdl": build_model(
                vertices=[
                    (
                        (float("nan"), -1, 0),
                        (0, 0, 1),
                        (1, 0, 0, -1),
                        (0, 0),
                    ),
                    *DEFAULT_VERTICES[1:],
                ]
            ),
            "outside-bounds.mdl": build_model(
                vertices=[
                    (
                        (-2, -1, 0),
                        (0, 0, 1),
                        (1, 0, 0, -1),
                        (0, 0),
                    ),
                    *DEFAULT_VERTICES[1:],
                ]
            ),
            "extreme-channel.mdl": build_model(
                vertices=[
                    (
                        (-1, -1, 0),
                        (2_000_000, 0, 1),
                        (1, 0, 0, -1),
                        (0, 0),
                    ),
                    *DEFAULT_VERTICES[1:],
                ]
            ),
            "bad-index.mdl": build_model(indices=(0, 1, 3)),
            "non-triangle-indices.mdl": build_model(indices=(0, 1)),
            "index-budget.mdl": build_model(
                declared_index_byte_count=33_554_436
            ),
            "nonzero-trailer.mdl": build_model(trailer=b"\0" * 6 + b"\1"),
            "extra-tail.mdl": build_model(trailer=b"\0" * 8),
            "legacy-nonzero-trailer.mdl": build_legacy_model(trailer=b"\1"),
            "legacy-extra-tail.mdl": build_legacy_model(trailer=b"\0\0"),
            "truncated.mdl": build_model()[:-1],
        }
        for name, value in fixtures.items():
            (root / name).write_bytes(value)
        completed = subprocess.run(
            [str(cls.binary), *(str(root / name) for name in fixtures)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.results = {
            result["file"]: result for result in json.loads(completed.stdout)
        }

    @classmethod
    def tearDownClass(cls) -> None:
        cls._tmp.cleanup()

    def test_valid_profile_preserves_all_geometry_channels(self) -> None:
        result = self.results["valid.mdl"]
        self.assertTrue(result["ok"], result)
        self.assertEqual(
            result["metadataMaterialPath"],
            "materials/models/fixture/default.json",
        )
        self.assertEqual(result["version"], "MDLV0023")
        self.assertEqual((result["headerFormat"], result["vertexFormat"]), (15, 15))
        self.assertEqual((result["vertexStride"], result["indexElementSize"]), (48, 2))
        self.assertEqual(result["vertexMemoryStride"], 64)
        self.assertEqual(
            [
                result["positionOffset"], result["normalOffset"],
                result["tangentOffset"], result["uvOffset"],
            ],
            [0, 16, 32, 48],
        )
        self.assertEqual(result["materialPath"], "materials/models/fixture/default.json")
        self.assertEqual(result["boundsMinimum"], [-1, -1, -1])
        self.assertEqual(result["boundsMaximum"], [1, 1, 1])
        self.assertEqual(result["triangleCount"], 1)
        self.assertEqual(result["indices"], [0, 1, 2])
        self.assertEqual(result["vertices"][0], {
            "position": [-1, -1, 0],
            "normal": [0, 0, 1],
            "tangent": [1, 0, 0, -1],
            "uv": [0, 0],
        })

    def test_material_path_is_normalized_without_identity_dispatch(self) -> None:
        result = self.results["windows-material.mdl"]
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["materialPath"], "materials/models/fixture/default.json")

    def test_legacy_profile_derives_bounds_from_validated_vertices(self) -> None:
        result = self.results["legacy-valid.mdl"]
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["version"], "MDLV0016")
        self.assertEqual(
            result["metadataMaterialPath"],
            "materials/models/fixture/legacy.json",
        )
        self.assertEqual(result["boundsMinimum"], [-1, -1, 0])
        self.assertEqual(result["boundsMaximum"], [1, 1, 0])
        self.assertEqual(result["indices"], [0, 1, 2])

    def test_unsupported_versions_flags_and_counts_fail_closed(self) -> None:
        for name, token in (
            ("old-version.mdl", "magic MDLV0015"),
            ("bad-nul.mdl", "magic MDLV0023"),
            ("bad-header-format.mdl", "header format 14"),
            ("multi-mesh.mdl", "mesh count 2"),
            ("multi-material.mdl", "material count 2"),
            ("uint32-indices.mdl", "index flag 1"),
            ("bad-vertex-format.mdl", "vertex format 7"),
        ):
            with self.subTest(name=name):
                result = self.results[name]
                self.assertFalse(result["ok"], result)
                self.assertIn(token, result["error"])

    def test_invalid_paths_bounds_and_vertex_values_fail_closed(self) -> None:
        for name, token in (
            ("unsafe-material.mdl", "material path"),
            ("invalid-utf8-material.mdl", "material path"),
            ("nan-bounds.mdl", "bounds"),
            ("inverted-bounds.mdl", "bounds"),
            ("nan-vertex.mdl", "non-finite"),
            ("outside-bounds.mdl", "out of range"),
            ("extreme-channel.mdl", "out of range"),
        ):
            with self.subTest(name=name):
                result = self.results[name]
                self.assertFalse(result["ok"], result)
                self.assertIn(token, result["error"])

    def test_empty_or_invalid_geometry_fails_closed(self) -> None:
        for name, token in (
            ("empty-vertices.mdl", "vertex byte count"),
            ("bad-vertex-bytes.mdl", "vertex byte count"),
            ("vertex-budget.mdl", "vertex byte budget"),
            ("bad-index.mdl", "exceeds vertex count"),
            ("non-triangle-indices.mdl", "index byte count"),
            ("index-budget.mdl", "index byte budget"),
        ):
            with self.subTest(name=name):
                result = self.results[name]
                self.assertFalse(result["ok"], result)
                self.assertIn(token, result["error"])

    def test_truncation_nonzero_trailer_and_extra_tail_fail_closed(self) -> None:
        for name in (
            "truncated.mdl",
            "nonzero-trailer.mdl",
            "extra-tail.mdl",
            "legacy-nonzero-trailer.mdl",
            "legacy-extra-tail.mdl",
        ):
            with self.subTest(name=name):
                self.assertFalse(self.results[name]["ok"], self.results[name])


if __name__ == "__main__":
    unittest.main()

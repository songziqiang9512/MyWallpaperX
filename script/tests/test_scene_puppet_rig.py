#!/usr/bin/env python3

"""Contract tests for MDLS bind hierarchy and MDLV skin weight ingestion."""

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
    SCENE_ROOT / "Format/SceneMdlPuppetRigReader.swift",
]
REAL_ASSET_ROOT = (
    REPOSITORY_ROOT
    / ".codex/scene-attachment-full45-20260725/results-v1/runtime-homes"
)

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
                let rig = try SceneMdlPuppetRigReader.read(data: data, mesh: mesh)
                entry["ok"] = true
                entry["stride"] = mesh.vertexStride
                entry["vertexCount"] = mesh.vertices.count
                entry["boneCount"] = rig.bones.count
                entry["parents"] = rig.bones.map(\.parentIndex)
                entry["bindTranslations"] = rig.bones.map {
                    [
                        Double($0.bindLocalMatrixColumnMajor[12]),
                        Double($0.bindLocalMatrixColumnMajor[13]),
                    ]
                }
                entry["weights"] = rig.vertexWeights.prefix(3).map { weights in
                    [
                        "indices": (0..<4).map { Int(weights.boneIndices[$0]) },
                        "weights": (0..<4).map { Double(weights.boneWeights[$0]) },
                    ]
                }
            } catch let error as SceneMdlPuppetRigReadError {
                entry["ok"] = false
                entry["error"] = error.description
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


def matrix(tx: float = 0, ty: float = 0, nan: bool = False) -> list[float]:
    values = [0.0] * 16
    values[0] = values[5] = values[10] = values[15] = 1.0
    values[12] = float("nan") if nan else tx
    values[13] = ty
    return values


def build_rig_mdl(
    *,
    stride: int = 80,
    bone_count: int = 2,
    bad_parent: bool = False,
    bad_matrix: bool = False,
    bad_weight_sum: bool = False,
    bad_bone_index: bool = False,
    nan_weight: bool = False,
) -> bytes:
    vertices = [
        (-10.0, -20.0, 0.0, [0, 0, 0, 0], [1.0, 0.0, 0.0, 0.0], 0.0, 1.0),
        (10.0, -20.0, 0.0, [0, 1, 0, 0], [0.25, 0.75, 0.0, 0.0], 1.0, 1.0),
        (0.0, 20.0, 0.0, [1, 0, 0, 0], [1.0, 0.0, 0.0, 0.0], 0.5, 0.0),
    ]
    vertex_blob = bytearray()
    for index, (x, y, z, bones, weights, u, v) in enumerate(vertices):
        record = bytearray(stride)
        struct.pack_into("<3f", record, 0, x, y, z)
        if bad_bone_index and index == 0:
            bones[0] = bone_count + 3
        if bad_weight_sum and index == 0:
            weights[0] = 0.5
        if nan_weight and index == 0:
            weights[0] = float("nan")
        struct.pack_into("<4I", record, stride - 40, *bones)
        struct.pack_into("<4f", record, stride - 24, *weights)
        struct.pack_into("<2f", record, stride - 8, u, v)
        vertex_blob += record
    index_blob = struct.pack("<6H", 0, 1, 2, 2, 1, 0)
    body = bytearray(b"MDLV0023\0" + b"\0" * 24)
    body += struct.pack("<II", 0, len(vertex_blob))
    body += vertex_blob
    body += struct.pack("<I", len(index_blob)) + index_blob

    mdls = bytearray(b"MDLS0004\0" + b"\0" * 4 + struct.pack("<I", bone_count))
    for bone in range(bone_count):
        parent = -1 if bone == 0 else bone - 1
        if bad_parent and bone == 1:
            parent = 1
        mdls += b"\0"
        mdls += struct.pack(
            "<IiI16f",
            1,
            parent,
            64,
            *matrix(bone * 10, bone * 20, nan=bad_matrix and bone == 0),
        )
        mdls += b"{}\0"
    mdla_offset = len(body) + len(mdls)
    struct.pack_into("<I", mdls, 9, mdla_offset)
    return bytes(body + mdls + b"MDLA0006\0")


class SceneMdlPuppetRigReaderTests(unittest.TestCase):
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
            "stride80.mdl": build_rig_mdl(),
            "stride84.mdl": build_rig_mdl(stride=84),
            "bad-parent.mdl": build_rig_mdl(bad_parent=True),
            "bad-matrix.mdl": build_rig_mdl(bad_matrix=True),
            "bad-weight-sum.mdl": build_rig_mdl(bad_weight_sum=True),
            "bad-bone-index.mdl": build_rig_mdl(bad_bone_index=True),
            "nan-weight.mdl": build_rig_mdl(nan_weight=True),
        }
        for name, blob in cls.fixtures.items():
            (tmp / name).write_bytes(blob)

        cls.real_assets = []
        patterns = [
            "3769688830/**/models/spiritblossomahribase_puppet.mdl",
            "3747492842/**/models/身体_puppet.mdl",
            "3768229922/**/models/人物_puppet.mdl",
        ]
        for pattern in patterns:
            cls.real_assets.extend(REAL_ASSET_ROOT.glob(pattern))
        paths = [tmp / name for name in cls.fixtures] + cls.real_assets
        completed = subprocess.run(
            [str(cls.binary), *map(str, paths)],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(f"harness run failed:\n{completed.stderr}")
        cls.results = {entry["file"]: entry for entry in json.loads(completed.stdout)}

    @classmethod
    def tearDownClass(cls):
        cls._tmp.cleanup()

    def test_stride_80_reads_hierarchy_and_normalized_weights(self):
        entry = self.results["stride80.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual((entry["stride"], entry["boneCount"]), (80, 2))
        self.assertEqual(entry["parents"], [-1, 0])
        self.assertEqual(entry["bindTranslations"], [[0, 0], [10, 20]])
        self.assertEqual(entry["weights"][1]["indices"], [0, 1, 0, 0])
        self.assertEqual(entry["weights"][1]["weights"], [0.25, 0.75, 0, 0])

    def test_stride_84_uses_shifted_skin_fields(self):
        entry = self.results["stride84.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["stride"], 84)
        self.assertEqual(entry["weights"][2]["indices"], [1, 0, 0, 0])

    def test_invalid_parent_fails_closed(self):
        self.assertIn("invalid rig parent", self.results["bad-parent.mdl"]["error"])

    def test_non_finite_bind_matrix_fails_closed(self):
        self.assertIn("invalid bind matrix", self.results["bad-matrix.mdl"]["error"])

    def test_weights_must_sum_to_one(self):
        self.assertIn("invalid puppet vertex weights", self.results["bad-weight-sum.mdl"]["error"])

    def test_weight_bone_index_must_exist(self):
        self.assertIn("invalid puppet vertex weights", self.results["bad-bone-index.mdl"]["error"])

    def test_non_finite_weight_fails_closed(self):
        self.assertIn("invalid puppet vertex weights", self.results["nan-weight.mdl"]["error"])

    def test_three_real_sources_parse_both_verified_strides_when_available(self):
        if len(self.real_assets) != 3:
            self.skipTest("isolated real Puppet rig assets are unavailable")
        ahri = self.results["spiritblossomahribase_puppet.mdl"]
        body = self.results["身体_puppet.mdl"]
        person = self.results["人物_puppet.mdl"]
        self.assertTrue(ahri["ok"], ahri)
        self.assertEqual((ahri["stride"], ahri["vertexCount"], ahri["boneCount"]), (84, 1522, 73))
        self.assertTrue(body["ok"], body)
        self.assertEqual((body["stride"], body["vertexCount"], body["boneCount"]), (80, 3494, 7))
        self.assertTrue(person["ok"], person)
        self.assertEqual((person["stride"], person["vertexCount"], person["boneCount"]), (80, 6112, 24))


if __name__ == "__main__":
    unittest.main()

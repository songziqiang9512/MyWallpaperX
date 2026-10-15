#!/usr/bin/env python3

"""Contract tests for MDLS bind hierarchy and MDLV skin weight ingestion."""

from __future__ import annotations

import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from scene_real_test_fixtures import runtime_homes_root


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneMdlPuppetMeshReader.swift",
    SCENE_ROOT / "Format/SceneMdlPuppetRigReader.swift",
]
REAL_ASSET_ROOT = runtime_homes_root()

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
                entry["boneNames"] = rig.bones.map(\.name)
                entry["parents"] = rig.bones.map(\.parentIndex)
                entry["bindTranslations"] = rig.bones.map {
                    [
                        Double($0.bindLocalMatrixColumnMajor[12]),
                        Double($0.bindLocalMatrixColumnMajor[13]),
                    ]
                }
                if let reference = rig.referenceLocalMatricesColumnMajor {
                    entry["referenceTranslations"] = reference.map { [Double($0[12]), Double($0[13])] }
                } else {
                    entry["referenceTranslations"] = NSNull()
                }
                entry["referenceDiagnostic"] = rig.referencePoseDiagnostic ?? ""
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
    magic: bytes = b"MDLV0023",
    skeleton_marker: bytes = b"MDLS0004\0",
    animation_marker: bytes = b"MDLA0006\0",
    stride: int = 80,
    bone_count: int = 2,
    bad_parent: bool = False,
    bad_matrix: bool = False,
    bad_weight_sum: bool = False,
    bad_bone_index: bool = False,
    nan_weight: bool = False,
    bind_matrices: list[list[float]] | None = None,
    skeleton_tail: bytes = b"",
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
    body = bytearray(magic + b"\0" + b"\0" * 24)
    body += struct.pack("<II", 0, len(vertex_blob))
    body += vertex_blob
    body += struct.pack("<I", len(index_blob)) + index_blob

    mdls = bytearray(skeleton_marker + b"\0" * 4 + struct.pack("<I", bone_count))
    for bone in range(bone_count):
        parent = -1 if bone == 0 else bone - 1
        if bad_parent and bone == 1:
            parent = 1
        bone_name = b"root" if bone == 0 else b"MouseBone"
        mdls += bone_name + b"\0"
        mdls += struct.pack(
            "<IiI16f",
            1,
            parent,
            64,
            *(bind_matrices[bone] if bind_matrices is not None else
              matrix(bone * 10, bone * 20, nan=bad_matrix and bone == 0)),
        )
        mdls += b"{}\0"
    mdls += skeleton_tail
    mdla_offset = len(body) + len(mdls)
    struct.pack_into("<I", mdls, 9, mdla_offset)
    return bytes(body + mdls + animation_marker)


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
            "mdlv0014-rig.mdl": build_rig_mdl(
                magic=b"MDLV0014",
                stride=52,
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"\0",
            ),
            "mdlv0016-rig.mdl": build_rig_mdl(
                magic=b"MDLV0016",
                stride=52,
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0003\0",
            ),
            "mdlv0017-rig.mdl": build_rig_mdl(
                magic=b"MDLV0017",
                skeleton_marker=b"MDLS0002\0",
                animation_marker=b"MDLA0004\0",
            ),
            "mdlv0017-wrong-skeleton.mdl": build_rig_mdl(
                magic=b"MDLV0017",
            ),
            "bad-parent.mdl": build_rig_mdl(bad_parent=True),
            "bad-matrix.mdl": build_rig_mdl(bad_matrix=True),
            "bad-weight-sum.mdl": build_rig_mdl(bad_weight_sum=True),
            "bad-bone-index.mdl": build_rig_mdl(bad_bone_index=True),
            "nan-weight.mdl": build_rig_mdl(nan_weight=True),
        }
        reference_matrices = [matrix(20, 30), matrix(7, 9)]
        reference_tail = b"\0\0\1" + struct.pack("<32f", *reference_matrices[0], *reference_matrices[1])
        legacy = dict(magic=b"MDLV0017", skeleton_marker=b"MDLS0002\0", animation_marker=b"MDLA0004\0")
        for version, stride, animation_marker in ((b"MDLV0014", 52, b"\0"),
                                                  (b"MDLV0016", 52, b"MDLA0003\0"),
                                                  (b"MDLV0017", 80, b"MDLA0004\0"),
                                                  (b"MDLV0019", 80, b"MDLA0005\0")):
            cls.fixtures[f"{version.decode()}-reference.mdl"] = build_rig_mdl(
                magic=version, stride=stride, skeleton_marker=b"MDLS0002\0",
                animation_marker=animation_marker, skeleton_tail=reference_tail + b"remaining author fields")
        cls.fixtures["absent-reference.mdl"] = build_rig_mdl(**legacy, skeleton_tail=b"\0\0\0ignored tail")
        cls.fixtures["unknown-reference-prefix.mdl"] = build_rig_mdl(**legacy, skeleton_tail=b"\1\0\1" + reference_tail[3:])
        cls.fixtures["unknown-reference-flag.mdl"] = build_rig_mdl(**legacy, skeleton_tail=b"\0\0\2" + reference_tail[3:])
        cls.fixtures["short-unrecognized-tail.mdl"] = build_rig_mdl(**legacy, skeleton_tail=b"\0\0")
        cls.fixtures["truncated-reference.mdl"] = build_rig_mdl(**legacy, skeleton_tail=reference_tail[:-1])
        for version, marker in ((b"MDLV0021", b"MDLS0003\0"), (b"MDLV0023", b"MDLS0004\0")):
            cls.fixtures[f"{version.decode()}-unsupported-reference.mdl"] = build_rig_mdl(
                magic=version, skeleton_marker=marker, skeleton_tail=reference_tail)
        for label, component, value in (("nan", 12, float("nan")), ("infinite", 12, float("inf")),
                                         ("oversized", 12, 1_000_001), ("non-affine", 3, 0.5)):
            changed = bytearray(reference_tail)
            struct.pack_into("<f", changed, 3 + component * 4, value)
            cls.fixtures[f"bad-reference-{label}.mdl"] = build_rig_mdl(**legacy, skeleton_tail=bytes(changed))
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
        self.assertEqual(entry["boneNames"], ["root", "MouseBone"])
        self.assertEqual(entry["parents"], [-1, 0])
        self.assertEqual(entry["bindTranslations"], [[0, 0], [10, 20]])
        self.assertEqual(entry["weights"][1]["indices"], [0, 1, 0, 0])
        self.assertEqual(entry["weights"][1]["weights"], [0.25, 0.75, 0, 0])

    def test_stride_84_uses_shifted_skin_fields(self):
        entry = self.results["stride84.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual(entry["stride"], 84)
        self.assertEqual(entry["weights"][2]["indices"], [1, 0, 0, 0])

    def test_mdlv0016_stride_52_reads_the_shared_rig_shape(self):
        entry = self.results["mdlv0016-rig.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual((entry["stride"], entry["boneCount"]), (52, 2))
        self.assertEqual(entry["parents"], [-1, 0])
        self.assertEqual(entry["weights"][1]["indices"], [0, 1, 0, 0])

    def test_mdlv0014_stride_52_reads_the_verified_mdls0002_rig(self):
        entry = self.results["mdlv0014-rig.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual((entry["stride"], entry["boneCount"]), (52, 2))
        self.assertEqual(entry["parents"], [-1, 0])
        self.assertEqual(entry["weights"][1]["indices"], [0, 1, 0, 0])

    def test_mdlv0017_reads_only_the_version_matched_mdls0002_rig(self):
        entry = self.results["mdlv0017-rig.mdl"]
        self.assertTrue(entry["ok"], entry)
        self.assertEqual((entry["stride"], entry["boneCount"]), (80, 2))
        self.assertEqual(entry["parents"], [-1, 0])
        self.assertIn(
            "version-matched skeleton block",
            self.results["mdlv0017-wrong-skeleton.mdl"]["error"],
        )

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

    def test_legacy_reference_segment_keeps_original_bind_and_uninterpreted_suffix(self):
        for version in ("MDLV0014", "MDLV0016", "MDLV0017", "MDLV0019"):
            with self.subTest(version=version):
                row = self.results[f"{version}-reference.mdl"]
                self.assertTrue(row["ok"], row)
                self.assertEqual(row["bindTranslations"], [[0, 0], [10, 20]])
                self.assertEqual(row["referenceTranslations"], [[20, 30], [7, 9]])
                self.assertEqual(row["referenceDiagnostic"], "")

    def test_absent_reference_and_unknown_prefix_preserve_existing_rig(self):
        for name in ("stride80.mdl", "absent-reference.mdl", "unknown-reference-prefix.mdl",
                     "unknown-reference-flag.mdl", "short-unrecognized-tail.mdl"):
            row = self.results[name]
            self.assertTrue(row["ok"], row)
            self.assertIsNone(row["referenceTranslations"])
            self.assertEqual(row["bindTranslations"], [[0, 0], [10, 20]])
            self.assertEqual(row["referenceDiagnostic"], "" if name in ("stride80.mdl", "absent-reference.mdl")
                             else "unsupported-reference-pose-prefix")

    def test_declared_reference_must_fit_skeleton_and_contain_finite_affine_matrices(self):
        self.assertIn("reference pose within skeleton bounds", self.results["truncated-reference.mdl"]["error"])
        for label in ("nan", "infinite", "oversized", "non-affine"):
            with self.subTest(label=label):
                self.assertIn("invalid reference matrix", self.results[f"bad-reference-{label}.mdl"]["error"])

    def test_modern_declared_reference_is_not_silently_treated_as_supported(self):
        for version in ("MDLV0021", "MDLV0023"):
            self.assertIn("reference pose is unverified", self.results[f"{version}-unsupported-reference.mdl"]["error"])

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

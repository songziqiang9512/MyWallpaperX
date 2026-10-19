#!/usr/bin/env python3
"""Strict direct bind geometry, independent of optional animation admission."""
from __future__ import annotations

import json
import math
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT))
from script.tests.test_scene_static_model_reader import (
    SWIFT_SOURCES, build_model, build_legacy_model,
)
from script.tests.test_scene_puppet_rig import build_rig_mdl

FORMAT = 0x0180000F
POSITIONS = [(-1., -1., -1.), (1., -1., 1.), (0., 1., -1.), (0., 0., 2.)]
NORMALS = [(-1/math.sqrt(3),)*3,
           (1/math.sqrt(3), -1/math.sqrt(3), 1/math.sqrt(3)),
           (0., 1/math.sqrt(2), -1/math.sqrt(2)), (0., 0., 1.)]
TANGENTS = [(1/math.sqrt(2), -1/math.sqrt(2), 0., -1.),
            (1/math.sqrt(2), 1/math.sqrt(2), 0., 1.),
            (1., 0., 0., -1.), (0., 1., 0., 1.)]
UVS = [(.125, .25), (.75, .25), (.5, .875), (.625, .75)]
INDICES = (0, 2, 1, 0, 1, 3, 1, 2, 3, 2, 0, 3)


def build_bind_model(*, material=b"materials/own/body.json", header=FORMAT,
                     vertex_format=FORMAT, material_count=1, index_flag=0,
                     suffix=bytes(6), indices=INDICES, rig_options=None):
    """Reuse the maintained rig writer's exact bones/weights, not a new parser."""
    options = rig_options or {}
    old = build_rig_mdl(**options)
    marker = options.get("skeleton_marker", b"MDLS0004\0")
    old_skeleton = old.index(marker)
    # The existing self-fixture writer uses a nine-byte marker +24-byte prefix.
    old_vertices = old[41:41+3*80]
    vertices = bytearray(old_vertices + old_vertices[:80])
    for index in range(4):
        struct.pack_into("<10f", vertices, index*80,
                         *(POSITIONS[index]+NORMALS[index]+TANGENTS[index]))
        struct.pack_into("<2f", vertices, index*80+72, *UVS[index])
    index_data = struct.pack("<" + ("I" if index_flag else "H")*len(indices), *indices)
    prefix = (b"MDLV0023\0" + struct.pack("<III", header, 1, material_count)
              + material + b"\0" + struct.pack("<I6fII", index_flag,
                  -1., -1., -1., 1., 1., 2., vertex_format, len(vertices))
              + vertices + struct.pack("<I", len(index_data)) + index_data + suffix)
    skeleton = bytearray(old[old_skeleton:])
    old_end = struct.unpack_from("<I", skeleton, 9)[0]
    struct.pack_into("<I", skeleton, 9, old_end + len(prefix) - old_skeleton)
    return bytes(prefix+skeleton)


HARNESS = r'''
import Foundation

@main enum Harness {
    static func main() throws {
        let mode = CommandLine.arguments[1]
        var rows: [[String: Any]] = []
        for path in CommandLine.arguments.dropFirst(2) {
            let loaded = try Data(contentsOf: URL(fileURLWithPath: path))
            let data = ProcessInfo.processInfo.environment["MWX_READER_SLICE"] == "1"
                ? (Data([0xA5]) + loaded).dropFirst() : loaded
            var row: [String: Any] = ["file": (path as NSString).lastPathComponent]
            if mode == "puppet" {
                do {
                    let mesh = try SceneMdlPuppetMeshReader.read(data: data)
                    let rig = try SceneMdlPuppetRigReader.read(data: data, mesh: mesh)
                    row["ok"] = true
                    row["vertices"] = mesh.vertices.count
                    row["bones"] = rig.bones.count
                    row["weights"] = rig.vertexWeights.count
                } catch { row["ok"] = false; row["error"] = String(describing: error) }
            } else {
                do { row["metadata"] = try SceneMdlStaticModelReader.readMaterialPathsMetadata(data: data) }
                catch { row["metadataError"] = String(describing: error) }
                do { row["singularMetadata"] = try SceneMdlStaticModelReader.readMaterialPathMetadata(data: data) }
                catch { row["singularError"] = String(describing: error) }
                do {
                    let parts = try SceneMdlStaticModelReader.readParts(data: data)
                    let model = parts[0]
                    row["ok"] = true
                    row["partCount"] = parts.count
                    row["material"] = model.materialPath
                    row["state"] = model.geometryState.rawValue
                    row["headerFormat"] = model.headerFormat
                    row["vertexFormat"] = model.vertexFormat
                    row["stride"] = model.vertexStride
                    row["vertexCount"] = model.vertices.count
                    row["triangleCount"] = model.triangleCount
                    row["indices"] = model.indices.count <= 12 ? model.indices.map(Int.init) : []
                    row["zRange"] = [model.vertices.map(\.position.z).min()!, model.vertices.map(\.position.z).max()!]
                    row["bounds"] = [model.bounds.minimum, model.bounds.maximum]
                    row["samples"] = model.vertices.prefix(4).map { vertex in
                        ["position": [vertex.position.x,vertex.position.y,vertex.position.z].map(Double.init),
                         "normal": [vertex.normal.x,vertex.normal.y,vertex.normal.z].map(Double.init),
                         "tangent": [vertex.tangent.x,vertex.tangent.y,vertex.tangent.z,vertex.tangent.w].map(Double.init),
                         "uv": [vertex.uv.x,vertex.uv.y].map(Double.init)]
                    }
                } catch { row["ok"] = false; row["error"] = String(describing: error) }
            }
            rows.append(row)
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]))
    }
}
'''


class DirectModelBindGeometryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls.tmp = tempfile.TemporaryDirectory(prefix="mwx-direct-bind-")
        cls.root = Path(cls.tmp.name)
        cls.binary = cls.root / "reader"
        harness = cls.root / "Harness.swift"
        harness.write_text(HARNESS)
        command = ["swiftc", "-swift-version", "5", "-default-isolation", "MainActor",
                   *map(str, SWIFT_SOURCES), str(harness), "-module-cache-path",
                   str(cls.root/"cache"), "-o", str(cls.binary)]
        result = subprocess.run(command, cwd=REPOSITORY_ROOT, capture_output=True,
                                text=True, timeout=120)
        if result.returncode:
            raise AssertionError("reader compile failed:\n"+result.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_inputs(self, inputs, *, mode="static", sliced=False):
        paths = []
        for name, data in inputs.items():
            path = self.root/name
            path.write_bytes(data)
            paths.append(path)
        environment = dict(os.environ)
        environment["MWX_READER_SLICE"] = "1" if sliced else "0"
        result = subprocess.run([str(self.binary), mode, *map(str,paths)],
                                capture_output=True, text=True, env=environment, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return {row["file"]: row for row in json.loads(result.stdout)}

    def test_bind_channels_material_and_typed_state_survive_renaming(self):
        for sliced in [False, True]:
            rows = self.run_inputs({"own.mdl": build_bind_model(),
                "equivalent-renamed.mdl": build_bind_model(material=b"renamed/geometries/other.json")},
                sliced=sliced)
            for name,row in rows.items():
                with self.subTest(name=name, sliced=sliced):
                    self.assertTrue(row["ok"], row)
                    self.assertEqual(row["state"], "bindOnlyAnimationUnqualified")
                    self.assertEqual(row["metadata"], [row["material"]])
                    self.assertEqual(row["singularMetadata"], row["material"])
                    self.assertEqual((row["headerFormat"],row["vertexFormat"],row["stride"]), (FORMAT,FORMAT,80))
                    self.assertEqual((row["partCount"],row["vertexCount"],row["triangleCount"]), (1,4,4))
                    self.assertEqual(row["indices"], list(INDICES))
                    self.assertEqual(row["zRange"], [-1,2])
                    for i,vertex in enumerate(row["samples"]):
                        for key,expected in [("position",POSITIONS[i]),("normal",NORMALS[i]),
                                             ("tangent",TANGENTS[i]),("uv",UVS[i])]:
                            for actual,value in zip(vertex[key],expected):
                                self.assertAlmostEqual(actual,value,places=6)
            self.assertEqual(rows["equivalent-renamed.mdl"]["material"], "renamed/geometries/other.json")

    def test_unknown_flags_parts_and_required_rig_reject_all_read_entries(self):
        good = build_bind_model()
        vertex_start = 21+len(b"materials/own/body.json")+1+4+24+8
        index_length = vertex_start+4*80
        skeleton = index_length+4+len(INDICES)*2+6
        def change(offset, pattern, *values):
            value = bytearray(good)
            struct.pack_into(pattern,value,offset,*values)
            return bytes(value)
        rows = self.run_inputs({
            "unknown-header.mdl": build_bind_model(header=FORMAT|0x20),
            "wrong-vertex-format.mdl": build_bind_model(vertex_format=15),
            "extra-material.mdl": build_bind_model(material_count=2),
            "wrong-index-width.mdl": build_bind_model(index_flag=1),
            "extra-stream.mdl": build_bind_model(suffix=b"\1"+bytes(5)),
            "parts.mdl": build_bind_model(suffix=b"\0\1"+bytes(4)),
            "clip.mdl": build_bind_model(suffix=bytes(2)+struct.pack("<I",1)),
            "late-marker.mdl": build_bind_model(suffix=bytes(7)),
            "missing-rig.mdl": good[:skeleton],
            "truncated-rig.mdl": good[:skeleton+14],
            "wrong-rig-version.mdl": build_bind_model(rig_options={"skeleton_marker":b"MDLS0003\0"}),
            "bad-parent.mdl": build_bind_model(rig_options={"bad_parent":True}),
            "bad-matrix.mdl": build_bind_model(rig_options={"bad_matrix":True}),
            "bad-bone-index.mdl": build_bind_model(rig_options={"bad_bone_index":True}),
            "bad-weight-sum.mdl": build_bind_model(rig_options={"bad_weight_sum":True}),
            "nan-weight.mdl": build_bind_model(rig_options={"nan_weight":True}),
            "nan-normal.mdl": change(vertex_start+12,"<f",float("nan")),
            "nan-tangent.mdl": change(vertex_start+24,"<f",float("nan")),
            "invalid-uv.mdl": change(vertex_start+72,"<f",1000001.),
            "out-of-bounds.mdl": change(vertex_start,"<f",99.),
            "bad-index.mdl": change(index_length+4,"<H",9),
            "too-many-bones.mdl": change(skeleton+13,"<I",4097),
            "bad-rig-end.mdl": change(skeleton+9,"<I",len(good)+1),
            "truncated-vertex.mdl": good[:vertex_start+70],
            "vertex-budget.mdl": change(vertex_start-4,"<I",((256*1024*1024)//80+1)*80),
            "index-budget.mdl": change(index_length,"<I",((32*1024*1024)//6+1)*6),
        })
        for name,row in rows.items():
            with self.subTest(name=name):
                self.assertFalse(row["ok"],row)
                self.assertEqual(row["error"],row["metadataError"])
                self.assertEqual(row["error"],row["singularError"])
                self.assertNotIn("state",row)
        self.assertIn("required bind rig",rows["bad-weight-sum.mdl"]["error"])
        self.assertIn("vertex byte budget",rows["vertex-budget.mdl"]["error"])
        self.assertIn("index byte budget",rows["index-budget.mdl"]["error"])

    def test_animation_absence_or_unknown_suffix_never_claims_animation(self):
        good = build_bind_model()
        end = good.index(b"MDLA0006\0")
        rows = self.run_inputs({"no-animation.mdl":good[:end],
                               "unknown-animation.mdl":good[:end]+b"MDLA9999\0unqualified"})
        for row in rows.values():
            self.assertTrue(row["ok"],row)
            self.assertEqual(row["state"],"bindOnlyAnimationUnqualified")

    def test_old_static_profiles_keep_channels_and_state(self):
        rows = self.run_inputs({"old23.mdl":build_model(),"old16.mdl":build_legacy_model()})
        for row in rows.values():
            self.assertTrue(row["ok"],row)
            self.assertEqual(row["state"],"authoredStatic")
            self.assertEqual(row["stride"],48)
            self.assertEqual(row["samples"][0]["normal"],[0,0,1])
            self.assertEqual(row["samples"][0]["tangent"],[1,0,0,-1])

    def test_existing_image_puppet_rig_entry_preserves_weights(self):
        rows = self.run_inputs({"puppet23.mdl":build_rig_mdl(),
            "puppet16.mdl":build_rig_mdl(magic=b"MDLV0016",stride=52,
                skeleton_marker=b"MDLS0002\0",animation_marker=b"MDLA0003\0")},
            mode="puppet",sliced=True)
        for row in rows.values():
            self.assertTrue(row["ok"],row)
            self.assertEqual((row["vertices"],row["weights"],row["bones"]),(3,3,2))

    def test_optional_actual_bind_model_geometry_only(self):
        value = os.environ.get("MWX_DIRECT_MODEL_BIND_FIXTURE")
        if not value:
            self.skipTest("MWX_DIRECT_MODEL_BIND_FIXTURE not supplied")
        source = Path(value)
        rows = self.run_inputs({"actual-bind.mdl":source.read_bytes()})
        row = rows["actual-bind.mdl"]
        self.assertTrue(row["ok"],row)
        self.assertEqual(row["state"],"bindOnlyAnimationUnqualified")
        self.assertEqual(row["metadata"],[row["material"]])
        self.assertEqual(row["partCount"],1)
        self.assertEqual(row["stride"],80)
        self.assertGreater(row["vertexCount"],3)
        self.assertGreater(row["triangleCount"],1)
        self.assertLess(row["zRange"][0],row["zRange"][1])


if __name__ == "__main__":
    unittest.main()

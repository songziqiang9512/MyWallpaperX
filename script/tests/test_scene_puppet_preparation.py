#!/usr/bin/env python3
"""CPU preparation through complete production Puppet sources and self-owned MDL inputs.

Metal types are linked so the entire LayerLoad/PlaybackState source is compiled.
The cases never create a device, pipeline, texture, buffer or command buffer.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

from script.tests.test_scene_puppet_mesh import build_mdl


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
LAYER_LOAD = SCENE / "Systems/Puppet/ScenePuppetLayerLoad.swift"
CASES = ROOT / "script/tests/fixtures/ScenePuppetPreparationCases.swift"
SOURCES = [
    "Format/SceneMdlPuppetMeshReader.swift",
    "Format/SceneMdlPuppetRigReader.swift",
    "Format/SceneMdlPuppetAttachmentReader.swift",
    "Format/SceneMdlPuppetAnimation.swift",
    "Format/SceneMdlPuppetAnimationReader.swift",
    "Format/ScenePuppetAnimationLayer.swift",
    "Format/ScenePuppetBoneCatalog.swift",
    "Systems/Script/ScenePuppetBoneTransformBridge.swift",
    "Systems/Puppet/ScenePuppetAnimationSelection.swift",
    "Systems/Puppet/ScenePuppetSkinMatrixProjection.swift",
    "Systems/Puppet/ScenePuppetAnimationEvaluator.swift",
    "Systems/Puppet/ScenePuppetAnimationEvaluator+Transforms.swift",
    "Systems/Puppet/ScenePuppetAnimationEvaluator+FrameSampling.swift",
    "Systems/Puppet/ScenePuppetAttachmentPoseProjection.swift",
    "Systems/Puppet/ScenePuppetTranslationMotion.swift",
    "Systems/Puppet/ScenePuppetAnimationControl.swift",
    "Systems/Puppet/ScenePuppetAnimationPlaybackRuntime.swift",
    "Systems/Puppet/ScenePuppetPlaybackState.swift",
    "Systems/Puppet/ScenePuppetClipping.swift",
    "Systems/Puppet/ScenePuppetMeshGeometry.swift",
    "Systems/Properties/ScenePuppetAnimationPropertyTarget.swift",
    "Rendering/Geometry/SceneMatrix.swift",
    "Rendering/Geometry/SceneGeometryProduct.swift",
    "Rendering/Metal/SceneMetalPipeline.swift",
    "Rendering/Frame/SceneSourceUpdateTransaction.swift",
    "Rendering/Targets/SceneOffscreenResolutionPolicy.swift",
    "Resources/Textures/SceneResourceBudget.swift",
    "Diagnostics/ScenePerformanceCounterHub.swift",
    "Runtime/Session/ScenePreparedPuppetResources.swift",
]


def matrix(x: float = 0, y: float = 0) -> list[float]:
    result = [0.0] * 16
    result[0] = result[5] = result[10] = result[15] = 1.0
    result[12], result[13] = x, y
    return result


def fixture_mdl(
    *, reference: list[list[float]] | None = None,
    root_bind: list[float] | None = None,
    animation: bool = True,
    bad_animation: bool = False,
    bad_parent: bool = False,
) -> bytes:
    """Write a small owned MDLV0017/MDLS0002/MDLA0004 fixture, not a parser."""
    vertices = bytearray()
    for x, y, u, v in ((-10, -20, 0, 1), (10, -20, 1, 1), (0, 20, 0.5, 0)):
        record = bytearray(80)
        struct.pack_into("<3f", record, 0, x, y, 0)
        struct.pack_into("<4I", record, 40, 0, 0, 0, 0)
        struct.pack_into("<4f", record, 56, 1, 0, 0, 0)
        struct.pack_into("<2f", record, 72, u, v)
        vertices += record
    indices = struct.pack("<6H", 0, 1, 2, 2, 1, 0)
    body = bytearray(b"MDLV0017\0" + b"\0" * 24)
    body += struct.pack("<II", 0, len(vertices)) + vertices
    body += struct.pack("<I", len(indices)) + indices
    skeleton = bytearray(b"MDLS0002\0" + b"\0" * 4 + struct.pack("<I", 2))
    for index, bind in enumerate((root_bind or matrix(4), matrix(2))):
        skeleton += (b"root" if index == 0 else b"child") + b"\0"
        parent = -1 if index == 0 else (1 if bad_parent else 0)
        skeleton += struct.pack("<IiI16f", 1, parent, 64, *bind) + b"{}\0"
    if reference is not None:
        skeleton += b"\0\0\1" + struct.pack("<32f", *reference[0], *reference[1])
    struct.pack_into("<I", skeleton, 9, len(body) + len(skeleton))
    if not animation:
        return bytes(body + skeleton + b"\0")
    record = bytearray(struct.pack("<II", 101, 0) + b"owned-motion\0loop\0")
    record += struct.pack("<fIII", 1, 1, 0, 2)
    for bone in range(2):
        record += struct.pack("<II", 0, 72)
        for frame in range(2):
            translation = (4 + frame * 26) if bone == 0 else 2
            record += struct.pack("<9f", translation, 0, 0, 0, 0, 0, 1, 1, 1)
    record += b"\0" * 10
    block = bytearray(b"MDLA0004\0" + b"\0" * 4 + struct.pack("<I", 1))
    block += b"invalid" if bad_animation else record
    struct.pack_into("<I", block, 9, len(body) + len(skeleton) + len(block))
    return bytes(body + skeleton + block)


class ScenePuppetPreparationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if shutil.which("swiftc") is None:
            raise unittest.SkipTest("swiftc unavailable")
        cls._temporary = tempfile.TemporaryDirectory(prefix="mwx-puppet-preparation-")
        directory = Path(cls._temporary.name)
        source_paths = [LAYER_LOAD, CASES, *(SCENE / item for item in SOURCES)]
        identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_paths}
        # Keep the complete production file unchanged; append test cases in the
        # same file only to observe its fileprivate immutable CPU products.
        harness = directory / "preparation.swift"
        harness.write_bytes(LAYER_LOAD.read_bytes() + b"\n" + CASES.read_bytes())
        binary = directory / "preparation"
        compilation = subprocess.run(
            ["swiftc", *(str(SCENE / item) for item in SOURCES), str(harness), "-o", str(binary)],
            capture_output=True, text=True, timeout=120,
        )
        if compilation.returncode:
            raise AssertionError(compilation.stdout + compilation.stderr)
        reference = [matrix(20, 30), matrix(7, 9)]
        shear = matrix(4)
        shear[4] = 0.25
        small = matrix(4)
        small[0] = 1e-8
        cls.bind_inputs = {"bind-shear.mdl": shear, "bind-small.mdl": small}
        files = {
            "shared.mdl": fixture_mdl(reference=reference),
            "renamed.mdl": fixture_mdl(reference=reference),
            "other.mdl": fixture_mdl(reference=[matrix(90, 60), matrix(3, 8)]),
            "reuse.mdl": fixture_mdl(reference=reference),
            "bind.mdl": fixture_mdl(),
            "bind-shear.mdl": fixture_mdl(root_bind=shear, animation=False),
            "bind-small.mdl": fixture_mdl(root_bind=small, animation=False),
            "bad-reference.mdl": fixture_mdl(reference=[shear, matrix(7, 9)], animation=False),
            "bad-rig.mdl": fixture_mdl(bad_parent=True),
            "bad-animation.mdl": fixture_mdl(bad_animation=True),
            "absent-animation.mdl": fixture_mdl(animation=False),
            "bad-mesh.mdl": b"owned-invalid-mesh",
            "static-uv20.mdl": build_mdl(magic=b"MDLV0016", stride=20,
                vertex_format=9, include_mdls=False, suffix=b"\0"),
        }
        for name, data in files.items():
            (directory / name).write_bytes(data)
        (directory / "directory.mdl").mkdir()
        run = subprocess.run([str(binary), str(directory)], capture_output=True, text=True, timeout=30)
        if run.returncode:
            raise AssertionError(run.stdout + run.stderr)
        current_identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_paths}
        if identity != current_identity:
            raise AssertionError("Puppet preparation sources changed during the CPU gate")
        cls.result = json.loads(run.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls._temporary.cleanup()

    def test_shared_mesh_animation_demand_is_or_in_both_source_orders(self) -> None:
        for key in ("plain-first", "animated-first", "renamed"):
            row = self.result["resource-orders"][key]
            self.assertEqual(row["assetCount"], 1, row)
            self.assertEqual(row["source"]["animationIDs"], [101], row)
            self.assertEqual(row["source"]["sampledRootX"], 30, row)
            self.assertEqual(row["default"]["animationIDs"], [], row)
            self.assertEqual(row["default"]["neutralRootX"], 20, row)

    def test_default_pose_keeps_reference_and_does_not_inherit_script_or_animation(self) -> None:
        row = self.result["default-reference"]
        self.assertEqual(row["kind"], "reference", row)
        self.assertEqual(row["animationIDs"], [], row)
        self.assertEqual(row["neutralRootX"], 20, row)
        plain = self.result["default-bind"]
        self.assertEqual(plain["kind"], "bind", plain)
        self.assertEqual(plain["fallback"], "", plain)

    def test_exact_bind_bones_preserve_shear_and_small_determinant(self) -> None:
        for name, expected in self.bind_inputs.items():
            row = self.result["exact-bind"][name]
            exact = list(struct.unpack("<16f", struct.pack("<16f", *expected)))
            self.assertTrue(row["available"], row)
            self.assertEqual(row["local"][:16], exact, row)
            self.assertEqual(row["local"][16:], matrix(2), row)
            self.assertEqual(row["world"][:16], exact, row)
            self.assertEqual(row["pose"]["kind"], "bind", row)
        self.assertFalse(self.result["bad-reference"]["bonesAvailable"])
        self.assertIn("reference", self.result["bad-reference"]["pose"]["fallback"])

    def test_prepared_asset_and_bones_survive_removing_the_input_file(self) -> None:
        row = self.result["reuse"]
        self.assertFalse(row["fileExists"], row)
        prepared_bones = row["beforeBones"]
        self.assertTrue(prepared_bones["available"], row)
        self.assertEqual(prepared_bones["names"], ["root", "child"], row)
        self.assertEqual(prepared_bones["parents"], [-1, 0], row)
        self.assertEqual(prepared_bones["local"][12:15], [20, 30, 0], row)
        self.assertEqual(prepared_bones["local"][28:31], [7, 9, 0], row)
        self.assertEqual(prepared_bones["world"][28:31], [27, 39, 0], row)
        self.assertEqual(row["beforeBones"], row["afterBones"], row)
        self.assertEqual(row["source"]["animationIDs"], [101], row)
        self.assertEqual(row["source"]["sampledRootX"], 30, row)
        self.assertEqual(row["default"]["neutralRootX"], 20, row)

    def test_missing_read_and_parse_failures_preserve_distinct_fallbacks(self) -> None:
        rows = self.result["failures"]
        self.assertTrue(rows["missing"]["allowsTexture"], rows)
        for key, text in (("read", "mesh read failed"), ("parse", "mesh rejected"),
                          ("path", "mesh path rejected")):
            self.assertFalse(rows[key]["allowsTexture"], rows[key])
            self.assertIn(text, rows[key]["message"], rows[key])
        for key, text in (("rig", "animation rig rejected"), ("animation", "animation data rejected"),
                          ("absent-animation", "MDLA is absent"), ("unprepared-animation", "not prepared")):
            self.assertEqual(rows[key]["kind"], "bind", rows[key])
            self.assertIn(text, rows[key]["fallback"], rows[key])

    def test_static_uv20_prepares_bind_without_bones_or_animation_and_survives_input_removal(self) -> None:
        row = self.result["static-uv20"]
        self.assertEqual((row["kind"], row["stride"]), ("ready", 20), row)
        self.assertEqual(row["vertices"], [[-10, -20, 0, 0.25, 0.75],
            [10, -20, 0, 0.5, 0.75], [0, 20, 0, 0.375, 0.25]], row)
        self.assertEqual(row["indices"], [0, 1, 2, 2, 1, 0], row)
        self.assertFalse(row["bonesAvailable"], row)
        self.assertFalse(row["animationsPrepared"], row)
        self.assertFalse(row["fileExists"], row)
        expected = {"kind": "bind", "fallback": "", "animationIDs": []}
        self.assertEqual(row["before"], expected, row)
        self.assertEqual(row["after"], expected, row)

    def test_resource_map_keeps_pose_attached_to_its_mesh_and_layer(self) -> None:
        row = self.result["identity"]
        self.assertEqual(row["first"]["neutralRootX"], 20, row)
        self.assertEqual(row["second"]["neutralRootX"], 90, row)
        self.assertEqual(row["default-first"]["neutralRootX"], 20, row)
        self.assertEqual(row["default-second"]["neutralRootX"], 90, row)
        self.assertFalse(row["missingLayerPresent"], row)
        self.assertFalse(row["missingMeshPresent"], row)


if __name__ == "__main__":
    unittest.main()

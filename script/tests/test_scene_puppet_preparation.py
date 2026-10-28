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
from script.tests.test_scene_puppet_direct_playback import EXTRA_SOURCES, PIPELINE, static_model_carrier_source
from script.tests.scene_pkg_fixture import make_package


ROOT = Path(__file__).resolve().parents[2]
SCENE = ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
LAYER_LOAD = SCENE / "Systems/Puppet/ScenePuppetLayerLoad.swift"
CASES = ROOT / "script/tests/fixtures/ScenePuppetPreparationCases.swift"
SOURCES = [
    "../SteamWorkshopStorage/ScenePlaybackSource.swift",
    "Format/ScenePkgReader.swift",
    "Resources/Assets/SceneResourceIdentity.swift",
    "Resources/Assets/SceneResourceView+Backing.swift",
    "Resources/Assets/SceneResourceIndex.swift",
    "Resources/Assets/SceneResourceView.swift",
    "Runtime/Frame/SceneMaterialRenderState.swift",
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

SOURCES += [item for item in EXTRA_SOURCES if item not in SOURCES]


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
    bone_names: tuple[str, str] = ("root", "child"),
    bone_order: tuple[int, int] = (0, 1),
    independent_roots: bool = False,
) -> bytes:
    """Write a small owned MDLV0017/MDLS0002/MDLA0004 fixture, not a parser."""
    vertices = bytearray()
    for x, y, u, v in ((-10, -20, 0, 1), (10, -20, 1, 1), (0, 20, 0.5, 0)):
        record = bytearray(80)
        struct.pack_into("<3f", record, 0, x, y, 0)
        struct.pack_into("<4I", record, 40, bone_order.index(0), 0, 0, 0)
        struct.pack_into("<4f", record, 56, 1, 0, 0, 0)
        struct.pack_into("<2f", record, 72, u, v)
        vertices += record
    indices = struct.pack("<6H", 0, 1, 2, 2, 1, 0)
    body = bytearray(b"MDLV0017\0" + b"\0" * 24)
    body += struct.pack("<II", 0, len(vertices)) + vertices
    body += struct.pack("<I", len(indices)) + indices
    skeleton = bytearray(b"MDLS0002\0" + b"\0" * 4 + struct.pack("<I", 2))
    bind_matrices = (root_bind or matrix(4), matrix(2))
    for index in bone_order:
        bind = bind_matrices[index]
        skeleton += bone_names[index].encode("utf-8") + b"\0"
        source_parent = -1 if index == 0 or independent_roots else (1 if bad_parent else 0)
        parent = -1 if source_parent < 0 else bone_order.index(source_parent)
        skeleton += struct.pack("<IiI16f", 1, parent, 64, *bind) + b"{}\0"
    if reference is not None:
        skeleton += b"\0\0\1" + struct.pack("<32f",
            *(value for index in bone_order for value in reference[index]))
    struct.pack_into("<I", skeleton, 9, len(body) + len(skeleton))
    if not animation:
        return bytes(body + skeleton + b"\0")
    record = bytearray(struct.pack("<II", 101, 0) + b"owned-motion\0loop\0")
    record += struct.pack("<fIII", 1, 1, 0, 2)
    for bone in bone_order:
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
        source_paths = [LAYER_LOAD, CASES, PIPELINE, Path(static_model_carrier_source.__code__.co_filename),
                        Path(make_package.__code__.co_filename), *(SCENE / item for item in SOURCES)]
        identity = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_paths}
        # Keep the complete production file unchanged; append test cases in the
        # same file only to observe its fileprivate immutable CPU products.
        harness = directory / "preparation.swift"
        harness.write_bytes(LAYER_LOAD.read_bytes() + b"\n" + CASES.read_bytes()
                            + static_model_carrier_source().encode())
        binary = directory / "preparation"
        compilation = subprocess.run(
            ["swiftc", *(str(SCENE / item) for item in SOURCES), str(harness),
             "-module-cache-path", str(directory / "module-cache"), "-o", str(binary)],
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
            "reference-bad-animation.mdl": fixture_mdl(reference=reference, bad_animation=True),
            "reference-absent-animation.mdl": fixture_mdl(reference=reference, animation=False),
            "renamed-reference-failure.mdl": fixture_mdl(
                reference=[matrix(90, 60), matrix(3, 8)], bad_animation=True,
                bone_names=("pivot-renamed", "tip-renamed")),
            "independent-reference-failure.mdl": fixture_mdl(reference=reference,
                bad_animation=True, independent_roots=True),
            "reordered-reference-failure.mdl": fixture_mdl(reference=reference,
                bad_animation=True, independent_roots=True, bone_order=(1, 0),
                bone_names=("anchor-equivalent", "free-equivalent")),
            "reference-bad-rig.mdl": fixture_mdl(reference=reference,
                bad_parent=True, bad_animation=True),
            "invalid-reference-failure.mdl": fixture_mdl(
                reference=[shear, matrix(7, 9)], bad_animation=True),
            "selected-evaluator-failure.mdl": fixture_mdl(reference=reference, root_bind=small),
            "bad-mesh.mdl": b"owned-invalid-mesh",
            "static-uv20.mdl": build_mdl(magic=b"MDLV0016", stride=20,
                vertex_format=9, include_mdls=False, suffix=b"\0"),
        }
        inputs = directory / "inputs"
        inputs.mkdir()
        for name, data in files.items():
            (inputs / name).write_bytes(data)
        (inputs / "puppet-sources.pkg").write_bytes(make_package([
            ("packaged.mdl", files["shared.mdl"]),
            ("bad.mdl", b"selected-bad-package-mesh"),
            (".hidden/rig.mdl", files["shared.mdl"]),
            ("folder.mdl/child.bin", b"directory content"),
        ]))
        (inputs / "directory.mdl").mkdir()
        run = subprocess.run([str(binary), str(inputs)], capture_output=True, text=True, timeout=30)
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
            self.assertEqual(row["source"]["kind"], "animation", row)
            self.assertEqual(row["source"]["fallback"], "", row)
            self.assertEqual(row["default"]["animationIDs"], [], row)
            self.assertEqual(row["default"]["neutralRootX"], 20, row)

    def test_optional_hidden_preparation_keeps_slots_without_enabling_pose(self) -> None:
        for key, default_kind, root_x in (("optional-hidden", "reference", 20),
                                         ("optional-hidden-bind", "bind", 4)):
            row = self.result[key]
            with self.subTest(default=default_kind):
                for active in ("activeWithBadOptional", "auxiliaryWithActive"):
                    self.assertEqual(row[active]["kind"], "animation", row)
                    self.assertEqual(row[active]["animationIDs"], [101], row)
                    self.assertEqual(row[active]["sampledRootX"], 30, row)
                self.assertEqual(row["badRequired"]["kind"], "bind", row)
                self.assertIn("bone counts", row["badRequired"]["fallback"], row)
                self.assertEqual(row["badOnly"]["points"], row["defaultPoints"], row)
                self.assertEqual(row["badOnly"]["coverage"], row["defaultCoverage"], row)
                self.assertEqual(row["badOnly"]["kind"], default_kind, row)
                self.assertIn("no prepared layer", row["badOnly"]["fallback"], row)
                self.assertEqual(row["animationIDs"], [101, 101, 203], row)
                self.assertEqual(row["slotIDs"], [7, 8, 9], row)
                self.assertEqual(row["slotIndices"], [1, 2, 3], row)
                self.assertEqual(row["visible"], [False, False, False], row)
                self.assertEqual(row["currentFrames"], [0.5, 0, 0], row)
                self.assertTrue(row["nilSamples"], row)
                self.assertEqual(row["neutralRootX"], root_x, row)
                self.assertEqual(row["points"], row["defaultPoints"], row)
                self.assertEqual(row["coverage"], row["defaultCoverage"], row)
                self.assertEqual(row["coverage"], [1, 1, 1], row)
                self.assertEqual(row["default"]["kind"], default_kind, row)
                self.assertEqual(row["default"]["animationIDs"], [], row)

    def test_resource_reads_select_authored_vfs_and_keep_selected_failures(self) -> None:
        for name, passed in self.result["resource-read-checks"].items():
            with self.subTest(name=name):
                self.assertTrue(passed)

    def test_default_pose_keeps_reference_and_does_not_inherit_script_or_animation(self) -> None:
        row = self.result["default-reference"]
        self.assertEqual(row["kind"], "reference", row)
        self.assertEqual(row["animationIDs"], [], row)
        self.assertEqual(row["neutralRootX"], 20, row)
        self.assertEqual(row["fallback"], "", row)
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
                          ("absent-animation", "MDLA is absent"), ("unprepared-animation", "not prepared"),
                          ("selector", "animation id 909 is absent"),
                          ("unsupported-selector", "outside the bounded playback profile"),
                          ("no-reference-script", "animation data rejected")):
            self.assertEqual(rows[key]["kind"], "bind", rows[key])
            self.assertIn(text, rows[key]["fallback"], rows[key])

    def test_failed_animation_requests_keep_independent_reference_and_original_diagnostic(self) -> None:
        rows = self.result["reference-fallbacks"]
        original_failures = {"bad": "animation", "absent": "absent-animation",
            "unprepared": "unprepared-animation", "unknown": "selector",
            "unsupported": "unsupported-selector"}
        for key, text in (("bad", "animation data rejected"),
                          ("absent", "MDLA is absent"), ("unprepared", "not prepared"),
                          ("unknown", "animation id 909 is absent"),
                          ("unsupported", "outside the bounded playback profile")):
            row = rows[key]
            pose = row["pose"]
            self.assertEqual(pose["kind"], "reference", row)
            self.assertEqual(pose["animationIDs"], [], row)
            self.assertIn(text, pose["fallback"], row)
            self.assertEqual(pose["fallback"],
                self.result["failures"][original_failures[key]]["fallback"], row)
            self.assertEqual(pose["points"], [[6, 10], [26, 10], [16, 50]], row)
            self.assertEqual(pose["localTranslations"], [[20, 30, 0], [7, 9, 0]], row)
            self.assertEqual(pose["worldTranslations"], [[20, 30, 0], [27, 39, 0]], row)
            self.assertEqual(row["bones"]["local"][12:15], [20, 30, 0], row)
            self.assertEqual(row["bones"]["world"][28:31], [27, 39, 0], row)
            # A default configuration uses this asset's independent reference,
            # without inheriting the source request, script or failure reason.
            self.assertEqual(row["default"]["kind"], "reference", row)
            self.assertEqual(row["default"]["animationIDs"], [], row)
            self.assertEqual(row["default"]["fallback"], "", row)
            self.assertEqual(row["default"]["points"], pose["points"], row)

    def test_reference_fallback_tracks_resource_names_and_remapped_bone_indices(self) -> None:
        rows = self.result["reference-fallbacks"]
        renamed = rows["renamed"]
        self.assertEqual(renamed["pose"]["kind"], "reference", renamed)
        self.assertIn("animation data rejected", renamed["pose"]["fallback"], renamed)
        self.assertEqual(renamed["bones"]["names"], ["pivot-renamed", "tip-renamed"], renamed)
        self.assertEqual(renamed["pose"]["points"], [[76, 40], [96, 40], [86, 80]], renamed)
        self.assertEqual(renamed["pose"]["worldTranslations"], [[90, 60, 0], [93, 68, 0]], renamed)
        ordinary, reordered = rows["independent"], rows["reordered"]
        for row in (ordinary, reordered):
            self.assertEqual(row["pose"]["kind"], "reference", row)
            self.assertEqual(row["pose"]["animationIDs"], [], row)
            self.assertIn("animation data rejected", row["pose"]["fallback"], row)
            self.assertEqual(row["bones"]["parents"], [-1, -1], row)
        self.assertEqual(reordered["bones"]["names"], ["free-equivalent", "anchor-equivalent"], reordered)
        self.assertEqual(ordinary["pose"]["localTranslations"], [[20, 30, 0], [7, 9, 0]], ordinary)
        self.assertEqual(reordered["pose"]["localTranslations"], [[7, 9, 0], [20, 30, 0]], reordered)
        self.assertEqual(ordinary["pose"]["points"], [[6, 10], [26, 10], [16, 50]], ordinary)
        self.assertEqual(ordinary["pose"]["points"], reordered["pose"]["points"], rows)

    def test_reference_and_selected_animation_safety_failures_keep_bind(self) -> None:
        rows = self.result["reference-safety"]
        for key, text in (("rig", "animation rig rejected"),
                          ("reference", "animation data rejected"),
                          ("selected-evaluator", "animation geometry rejected")):
            row = rows[key]
            self.assertEqual(row["pose"]["kind"], "bind", row)
            self.assertEqual(row["pose"]["animationIDs"], [], row)
            self.assertIn(text, row["pose"]["fallback"], row)
        # An invalid cached reference cannot turn an MDLA rejection into a
        # second evaluation attempt. The ordinary empty-reference rejection
        # remains covered by bad-reference above.
        self.assertNotIn("script pose rejected", rows["reference"]["pose"]["fallback"], rows)
        self.assertFalse(rows["rig"]["bones"]["available"], rows)
        self.assertFalse(rows["reference"]["bones"]["available"], rows)
        self.assertFalse(rows["selected-evaluator"]["bones"]["available"], rows)

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

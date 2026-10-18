#!/usr/bin/env python3
"""Default 2D camera inputs through the real parser, VM and projection."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import scene_vector_vm_test_support as vm
from script.tests import test_scene_timeline_runtime as timeline
from script.tests.test_scene_particle_camera_frame import SWIFT_SOURCES as CAMERA_SOURCES

ROOT = vm.ROOT
SCENE = vm.SCENE
FIXTURE = ROOT / "script/tests/fixtures/SceneDefault2DCameraInputChecks.swift"

# Reuse the full descriptor/parser gate, replacing its deliberately unavailable
# property resolver with the real property family used by the VM gate.
EXTRA_SOURCES = [
    *(p for p in timeline.SWIFT_SOURCES
      if p.name != "SceneUserPropertyResolutionStub.swift"),
    *CAMERA_SOURCES,
    SCENE / "Systems/Properties/SceneUserPropertyResolver.swift",
    SCENE / "Systems/Properties/SceneUserPropertyDefinitionParser.swift",
    SCENE / "Systems/Properties/ScenePropertyLiveUpdateState.swift",
    SCENE / "Systems/Properties/SceneDynamicSnapshot+Camera.swift",
    SCENE / "Systems/Properties/SceneDynamicDefinitionMerger.swift",
    SCENE / "Systems/Properties/SceneDefault2DCameraInputProfile.swift",
    SCENE / "Rendering/Geometry/SceneLayerVisibility.swift",
    SCENE / "Rendering/Frame/SceneMetalRenderer+Camera.swift",
    SCENE / "Systems/Input/SceneCameraShake.swift",
    SCENE / "Systems/Input/SceneLayerParallax.swift",
    SCENE / "Systems/Script/SceneScriptLayerTopologyProjection.swift",
]


def preamble() -> str:
    # These are existing external media/material/resource DTO leaves. The
    # Scene document, descriptor, camera profile and all numeric owners are real.
    source = vm.SWIFT_PREAMBLE
    media = source[source.index("struct SceneFrameTiming {"):
                   source.index("struct SceneTextScriptDefinition {")]
    materials = source[source.index("struct SceneShaderContract {}"):
                       source.index("enum SceneTimelinePlaybackCommand:")]
    source = timeline.HARNESS_SOURCE
    assets = source[source.index("struct ScenePkgExtractionReport {"):
                    source.index("enum HarnessError:")]
    assets = assets.replace("var shaderContracts: [Never] { [] }",
                            "var shaderContracts: [SceneShaderContract] { [] }")
    return "import Foundation\nimport simd\n" + media + materials + assets + """
enum SceneGraphRenderTargetPlan {
    enum TextureFormat { case rgba16f, rgbaBackbuffer }
}
struct SceneTextScriptProgram {
    struct Binding { let definition: SceneDynamicTargetDefinition }
    let bindings: [Binding] = []
}
"""


def run_probe(directory: Path) -> dict:
    sources = list(dict.fromkeys([*vm.SWIFT_SOURCES, *EXTRA_SOURCES]))
    inputs = [*sources, *vm.C_SOURCES, FIXTURE, Path(__file__), Path(vm.__file__),
              Path(timeline.__file__), vm.VM / "SceneQuickJS.h",
              vm.VM / "SceneQuickJSHostTypes.h", vm.VM / "SceneQuickJSInternal.h"]
    before = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in dict.fromkeys(inputs)}
    (directory / "input-freeze.json").write_text(json.dumps(before, indent=2) + "\n")
    with tempfile.TemporaryDirectory(prefix="compile-", dir=directory) as build:
        binary = vm.compile_vector_harness(Path(build), FIXTURE.read_text(),
            "default-2d-camera-inputs", extra_swift_sources=tuple(EXTRA_SOURCES),
            preamble=preamble())
        run = subprocess.run([str(binary), str(binary.parent)], capture_output=True, text=True, timeout=30)
    (directory / "stdout.json").write_text(run.stdout)
    (directory / "stderr.log").write_text(run.stderr)
    drift = [name for name, digest in before.items()
             if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
    (directory / "execution.json").write_text(json.dumps({
        "exitCode": run.returncode, "inputCount": len(before), "inputDrift": drift,
    }, indent=2) + "\n")
    if drift:
        raise AssertionError(f"focused input drift: {drift}")
    if run.returncode:
        raise AssertionError(run.stderr)
    return json.loads(run.stdout)


class SceneDefault2DCameraInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        proof = os.environ.get("MWX_SCENE_PROPERTY_PROOF")
        if proof:
            directory = Path(proof)
            directory.mkdir(parents=True, exist_ok=True)
            cls.result = run_probe(directory)
        else:
            with tempfile.TemporaryDirectory(prefix="mwx-default-camera-") as temporary:
                cls.result = run_probe(Path(temporary))

    def test_init_script_and_live_zoom_reach_the_existing_projection(self) -> None:
        for row in self.result["mixed"]:
            self.assertTrue(row["facts"])
            self.assertEqual([k for k, v in row["facts"].items() if v is not True], [], row)
            self.assertEqual(row["zooms"], [0.73, 1, 0.8])
            self.assertEqual(row["origins"], [[120, -40, 620]] * 3)

    def test_static_and_failed_script_inputs_keep_the_safe_camera(self) -> None:
        facts = self.result["fallbacks"]
        self.assertTrue(facts)
        self.assertEqual([k for k, v in facts.items() if v is not True], [], facts)

    def test_unsupported_camera_shapes_do_not_claim_default_2d_targets(self) -> None:
        facts = self.result["rejections"]
        self.assertTrue(facts)
        self.assertEqual([k for k, v in facts.items() if v is not True], [], facts)

    def test_independent_camera_fields_keep_their_clock_and_source_identity(self) -> None:
        for row in self.result["independent"]:
            self.assertTrue(row)
            self.assertEqual([k for k, v in row.items() if v is not True], [], row)

    def test_path_visibility_uses_the_settled_snapshot_without_restarting_time(self) -> None:
        facts = self.result["pathVisibility"]
        self.assertTrue(facts)
        self.assertEqual([k for k, v in facts.items() if v is not True], [], facts)

    def test_rejected_independent_fields_do_not_become_static_camera_inputs(self) -> None:
        facts = self.result["independentRejections"]
        self.assertTrue(facts)
        self.assertEqual([k for k, v in facts.items() if v is not True], [], facts)

    def test_hard_error_peers_keep_declared_references_and_local_rejection(self) -> None:
        facts = self.result["malformedPeers"]
        self.assertTrue(facts)
        self.assertEqual([k for k, v in facts.items() if v is not True], [], facts)


if __name__ == "__main__":
    unittest.main()

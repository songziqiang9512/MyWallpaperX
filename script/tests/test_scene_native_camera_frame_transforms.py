#!/usr/bin/env python3
"""Native camera consumes the same typed world transforms as scene geometry."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_default_2d_camera_inputs as shared


ROOT = shared.ROOT
SCENE = shared.SCENE
FIXTURE = ROOT / "script/tests/fixtures/SceneNativeCameraFrameTransformChecks.swift"
CAMERA_OWNER = SCENE / "Rendering/Frame/SceneMetalRenderer+Camera.swift"


def run_probe(directory: Path) -> dict:
    sources = list(dict.fromkeys([*shared.vm.SWIFT_SOURCES, *shared.EXTRA_SOURCES]))
    inputs = [*sources, *shared.vm.C_SOURCES, FIXTURE, Path(__file__),
              Path(shared.__file__), Path(shared.vm.__file__), Path(shared.timeline.__file__),
              shared.vm.VM / "SceneQuickJS.h", shared.vm.VM / "SceneQuickJSHostTypes.h",
              shared.vm.VM / "SceneQuickJSInternal.h"]
    before = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in dict.fromkeys(inputs)}
    (directory / "input-freeze.json").write_text(json.dumps(before, indent=2) + "\n")
    try:
        with tempfile.TemporaryDirectory(prefix="compile-", dir=directory) as build:
            binary = shared.vm.compile_vector_harness(Path(build), FIXTURE.read_text(),
                "native-camera-frame-transforms", extra_swift_sources=tuple(shared.EXTRA_SOURCES),
                preamble=shared.preamble())
            run = subprocess.run([str(binary), str(binary.parent)], capture_output=True,
                                 text=True, timeout=30)
            (directory / "stdout.json").write_text(run.stdout)
            (directory / "stderr.log").write_text(run.stderr)
            if run.returncode:
                raise AssertionError(run.stderr)
            return json.loads(run.stdout)
    except Exception as error:
        (directory / "failure.log").write_text(str(error) + "\n")
        raise
    finally:
        drift = [name for name, digest in before.items()
                 if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest]
        (directory / "input-after.json").write_text(json.dumps({
            "inputCount": len(before), "sourceDrift": drift,
        }, indent=2) + "\n")
        if drift:
            raise AssertionError(f"focused input drift: {drift}")


class SceneNativeCameraFrameTransformTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        proof = os.environ.get("MWX_NATIVE_CAMERA_FRAME_PROOF")
        if proof:
            directory = Path(proof)
            directory.mkdir(parents=True, exist_ok=True)
            cls.report = run_probe(directory)
        else:
            with tempfile.TemporaryDirectory(prefix="mwx-native-camera-frame-") as temporary:
                cls.report = run_probe(Path(temporary))

    def test_published_camera_and_parent_transforms_reach_the_working_view(self) -> None:
        rows = self.report["rows"]
        self.assertEqual(len(rows), 6)
        self.assertEqual({(r["name"], r["renamed"]) for r in rows},
                         {(name, renamed) for name in ("origin", "angles", "parent")
                          for renamed in (False, True)})
        for row in rows:
            for fact, passed in row["facts"].items():
                with self.subTest(case=row["name"], renamed=row["renamed"], fact=fact):
                    self.assertTrue(passed, row)

    def test_adjacent_camera_selection_and_canvas_routes_stay_unchanged(self) -> None:
        self.assertEqual(set(self.report["controls"]), {
            "staticNative", "staticGeneralMissingCamera", "hiddenDefault", "nondefault",
            "missingWorld", "orthographic2D", "unrelatedModel",
        })
        for name, passed in self.report["controls"].items():
            with self.subTest(case=name):
                self.assertTrue(passed, self.report["controls"])


if __name__ == "__main__":
    unittest.main()

"""Self-authored scale bytes and renamed sampling through the production compiler/GPU."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_generic_shader_texture_transform_compiler as compiler
from script.tests import test_scene_material_texture_transform as material


class ScenePreviousCompositeScaleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-own-scale-ruler-")
        cls.addClassCleanup(cls.temporary.cleanup)
        root = Path(cls.temporary.name)
        bundle = compiler.fixture_compiler_bundle(root)
        support = root / "Support.swift"
        support.write_text(material.SUPPORT)
        fixture = Path(__file__).with_name("fixtures") / "ScenePreviousCompositeScaleHarness.swift"
        harness = root / "RulerHarness.swift"
        harness.write_text(material.COORDINATE_HARNESS + fixture.read_text())
        sources = [*compiler.fixture_sources(root, bundle, compiler.GENERIC_SOURCES), support, harness]
        before = material.source_hashes(sources)
        environment = material.fixture_environment(root)
        command = ["swiftc", "-parse-as-library", *map(str, sources), "-module-cache-path",
                   str(root / "swift-cache"), "-o", str(root / "probe")]
        compiled = subprocess.run(command, cwd=compiler.REPOSITORY_ROOT, env=environment,
                                  capture_output=True, text=True)
        if compiled.returncode:
            raise RuntimeError(compiled.stderr)
        completed = subprocess.run([str(root / "probe"), str(bundle), str(root / "artifacts")],
                                   cwd=compiler.REPOSITORY_ROOT, env=environment,
                                   capture_output=True, text=True, timeout=60)
        if completed.returncode:
            raise RuntimeError(completed.stderr)
        if before != material.source_hashes(sources):
            raise RuntimeError("Scale ruler compilation inputs changed")
        cls.result = json.loads(completed.stdout)
        if receipt := os.environ.get("MWX_SCENE_SCALE_TEST_RECEIPT"):
            Path(receipt).write_text(completed.stdout)

    def test_scale_bytes_and_renamed_equivalent_expression_reach_next_frame_gpu(self):
        self.assertEqual(len(self.result["observations"]), 16)
        for observed in self.result["observations"]:
            with self.subTest(variant=observed["variant"], scale=observed["scale"], generation=observed["generation"]):
                value = observed["scale"]
                self.assertEqual(observed["encoded"], value)
                self.assertEqual(observed["backend"], "genericCompilerArtifact")
                expected = [(value[0] + (9 if observed["generation"] == 2 else 0)) / 255, value[1] / 255, 33 / 255, 1]
                self.assertEqual(len(observed["pixels"]), 16)
                for actual, want in zip(observed["pixels"], expected * 4):
                    self.assertAlmostEqual(actual, want, delta=0.0003)
        print(json.dumps(self.result, sort_keys=True))

    def test_invalid_numeric_abi_and_resource_color_contracts_stay_rejected(self):
        self.assertEqual(len(self.result["negatives"]), 10)
        self.assertTrue(all(self.result["negatives"].values()), self.result["negatives"])


if __name__ == "__main__":
    unittest.main()

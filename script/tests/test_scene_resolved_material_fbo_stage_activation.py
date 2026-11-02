#!/usr/bin/env python3

"""GPU proof for typed visibility activation on an admitted FBO graph."""

from __future__ import annotations

import json
import shutil
import unittest

from script.tests import test_scene_resolved_material_graph_executor as base


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneResolvedMaterialFBOStageActivationTests(unittest.TestCase):
    def test_visibility_activation_preserves_current_across_fbo_graph(self) -> None:
        harness = base.HARNESS_SUPPORT_SOURCE + base.EXECUTOR_SCENARIOS_SOURCE + (
            base.FIXTURE_ROOT / "SceneGraphExecutorFBOActivationHarness.swift"
        ).read_text(encoding="utf-8")

        compilation, completed = base.compile_harness(base.SUPPORT, harness)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        expected = [
            "activationPolicyAttachedToResolvedStage",
            "inactiveActivationPublishesPreviousCurrent",
            "inactiveActivationIsNotVisualFallback",
            "activeActivationContinuesThroughProgram",
        ]
        self.assertEqual(
            [name for name in expected if not payload["results"][name]],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()

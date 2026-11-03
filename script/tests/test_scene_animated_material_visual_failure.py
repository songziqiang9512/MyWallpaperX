#!/usr/bin/env python3

"""GPU proof for the typed animated-frame launch visual failure."""

from __future__ import annotations

import json
import unittest

from script.tests import test_scene_resolved_material_graph_executor as base


class SceneAnimatedMaterialVisualFailureTests(unittest.TestCase):
    def test_invalid_frame_metadata_preserves_previous_current(self) -> None:
        source = base.HARNESS_SUPPORT_SOURCE + base.EXECUTOR_SCENARIOS_SOURCE + (
            base.FIXTURE_ROOT / "SceneGraphExecutorAnimatedMetadataHarness.swift"
        ).read_text(encoding="utf-8")

        compilation, completed = base.compile_harness(base.SUPPORT, source)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        expected = [
            "samplerSchemaFailurePassthroughPrepared",
            "samplerSchemaFailurePassthroughEncoded",
            "samplerSchemaFailurePassthroughGPUCompleted",
            "samplerSchemaFailurePreservesPreviousAndContinuesSuffix",
        ]
        self.assertEqual(
            [name for name in expected if not payload["results"][name]],
            [],
            payload,
        )


if __name__ == "__main__":
    unittest.main()

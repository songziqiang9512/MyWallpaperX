#!/usr/bin/env python3

"""Production Metal gate for external-primary consumer visual fallback."""

from __future__ import annotations

import json
from pathlib import Path
import runpy
import shutil
import unittest


EXECUTOR_GATE = Path(__file__).with_name(
    "test_scene_resolved_material_graph_executor.py"
)
EXECUTOR_FIXTURE = runpy.run_path(str(EXECUTOR_GATE))
SUPPORT = EXECUTOR_FIXTURE["SUPPORT"]
compile_harness = EXECUTOR_FIXTURE["compile_harness"]
HARNESS = EXECUTOR_FIXTURE["HARNESS_SUPPORT_SOURCE"] + EXECUTOR_FIXTURE["EXECUTOR_SCENARIOS_SOURCE"] + (
    Path(__file__).with_name("fixtures") / "SceneGraphExecutorExternalPrimaryHarness.swift"
).read_text(encoding="utf-8")


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class ExternalPrimaryVisualFailurePassthroughTests(unittest.TestCase):
    def test_unavailable_source_preserves_history_and_clear_boundary(self) -> None:
        compilation, completed = compile_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        for key in ("unavailableHistoryResult", "unavailableClearResult"):
            self.assertEqual(payload["failureCodes"][key], "ready-rejected-preserved-recovered", (key, payload["failureCodes"][key]))
        for key in ("externalProviderSourceUnavailableLocalizesAndContinues", "externalLaunchFailureCannotMaskStaleProvider", "externalConsumerRecovers"):
            self.assertTrue(payload["results"][key], (key, payload))

    def test_consumer_failure_preserves_provider_and_continues_suffix(self) -> None:
        compilation, completed = compile_harness(SUPPORT, HARNESS)
        self.assertEqual(compilation.returncode, 0, compilation.stderr)
        self.assertIsNotNone(completed)
        assert completed is not None
        self.assertEqual(completed.returncode, 0, completed.stderr)

        payload = json.loads(completed.stdout)
        if not payload["metalAvailable"]:
            self.skipTest("Metal is unavailable")
        for key in (
            "externalLaunchFailureLocalizesAndContinues",
            "independentFramebufferFailureDoesNotRevokeDependencyStage",
            "externalRuntimeFailureLocalizesAndContinues",
            "externalProviderSourceUnavailableLocalizesAndContinues",
            "externalLaunchFailureCannotMaskStaleProvider",
            "externalConsumerRecovers",
            "crossLayerMissingProviderRejectedAtomically",
            "crossLayerWrongProviderRejectedAtomically",
            "crossLayerSecondaryRejectedAtomically",
            "crossLayerStaleEpochRejectedAtomically",
        ):
            self.assertTrue(payload["results"][key], (key, payload))
        self.assertEqual(payload["failureCodes"]["externalLaunchFailure"], "success")
        self.assertEqual(payload["failureCodes"]["externalRuntimeFailure"], "success")
        self.assertEqual(
            payload["failureCodes"]["externalProviderUnavailable"],
            "success",
        )
        self.assertEqual(
            payload["failureCodes"]["externalLaunchFailureWithStaleProvider"],
            "graph-publication-rejected",
        )


if __name__ == "__main__":
    unittest.main()

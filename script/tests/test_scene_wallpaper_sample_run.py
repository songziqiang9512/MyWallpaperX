"""Behavior of the synchronous isolated sample-to-report boundary."""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import scene_wallpaper_benchmark as benchmark
from script.tests.scene_wallpaper_benchmark_test_support import effect_execution_log
from script.tests.scene_wallpaper_sample_fixture import run_sample_fixture


class SceneWallpaperSampleRunTests(unittest.TestCase):
    def test_complete_collected_result_preserves_frozen_public_report(self) -> None:
        expected = json.loads((SCRIPT_DIR / (
            "tests/fixtures/scene_wallpaper_sample_report_golden.json"
        )).read_text())
        actual, command = run_sample_fixture(benchmark)
        self.assertEqual(actual, expected)
        self.assertTrue(actual["passed"])
        self.assertEqual(len(actual["runtime"]), len(expected["runtime"]))
        self.assertEqual(command[1], "--mwx-debug-scene-root")
        self.assertEqual(actual["runtime"]["runtime_evidence"]["visible_layer_ids"], [1])

    def test_default_observations_and_explicit_disabled_request(self) -> None:
        strict, strict_command = run_sample_fixture(benchmark)
        disabled, disabled_command = run_sample_fixture(
            benchmark, no_execution_observations=True,
        )
        option = "--mwx-debug-scene-no-execution-observations"
        self.assertNotIn(option, strict_command)
        self.assertEqual(disabled_command.count(option), 1)
        self.assertTrue(strict["passed"])
        self.assertTrue(disabled["passed"])
        self.assertTrue(disabled["runtime"]["performance"]["available"])
        graph = disabled["runtime"]["resolved_material_graph_execution"]
        self.assertFalse(graph["execution_observations_enabled"])
        self.assertFalse(graph["execution_succeeded"])
        self.assertEqual(graph["observation_status"], "unavailable")

    def test_texture_acceptance_keeps_unrounded_ratio(self) -> None:
        accepted, _ = run_sample_fixture(benchmark, sample_overrides={
            "minimum_loaded_ratio": 0.33332,
        })
        rejected, _ = run_sample_fixture(benchmark, sample_overrides={
            "minimum_loaded_ratio": 0.33334,
        })
        self.assertEqual(accepted["runtime"]["loaded_ratio"], 0.3333)
        self.assertTrue(accepted["passed"])
        self.assertFalse(rejected["passed"])
        self.assertEqual(rejected["failures"], ["loaded ratio 0.333 below minimum"])

    def test_missing_evidence_preserves_failure_order(self) -> None:
        result, _ = run_sample_fixture(benchmark, control={
            "missing_ready": True, "missing_performance": True, "black": True,
        })
        self.assertFalse(result["passed"])
        self.assertEqual(result["failures"], [
            "missing ready event",
            "performance evidence unavailable: expected one performance event, found 0",
            "missing runtime evidence path",
            "Scene runtime evidence missing or invalid",
            "Scene runtime evidence schema_version mismatch",
            "non-black window evidence missing",
        ])

    def test_timeout_exit_and_failed_frame_remain_non_pass(self) -> None:
        timed_out, _ = run_sample_fixture(benchmark, control={
            "timeout": True, "exit_code": -15,
        })
        self.assertTrue(timed_out["timed_out"])
        self.assertFalse(timed_out["passed"])
        self.assertEqual(timed_out["failures"], ["process timeout", "process exit -15"])
        failed_frame, _ = run_sample_fixture(benchmark, control={
            "log_lines": [effect_execution_log(7, [], [], status="failed")],
        })
        self.assertFalse(failed_frame["passed"])
        self.assertEqual(failed_frame["failures"], [
            "effect execution frame command buffer failed",
        ])

    def test_runtime_identity_and_static_expectations_remain_strict(self) -> None:
        cases = (
            ({"foreign_runtime_path": True}, {}, [
                "Scene runtime evidence path is outside Debug evidence directory",
            ]),
            ({"malformed_runtime": True}, {}, [
                "Scene runtime evidence missing or invalid",
                "Scene runtime evidence schema_version mismatch",
            ]),
            ({}, {"expected_visible_layer_count": 2,
                  "required_effect_files": ["effects/self-fixture/missing.json"]}, [
                "Scene runtime evidence visible_layer_count mismatch",
                "Scene effect file missing: effects/self-fixture/missing.json",
            ]),
        )
        for control, sample, expected in cases:
            with self.subTest(control=control, sample=sample):
                result, _ = run_sample_fixture(
                    benchmark, control=control, sample_overrides=sample,
                )
                self.assertFalse(result["passed"])
                self.assertEqual(result["failures"], expected)


    def test_invalid_requests_keep_exception_contracts(self) -> None:
        cases = (
            ({"hover_pointer_from_launch": True}, False, ValueError,
             "hover_pointer_from_launch requires hover_pointer_normalized"),
            ({"expected_visible_layer_count": "bad"}, False, ValueError,
             "invalid literal for int() with base 10: 'bad'"),
            ({"minimum_loaded_ratio": None}, False, TypeError,
             "float() argument must be a string or a real number, not 'NoneType'"),
            ({"expected_effect_execution_schema": 1}, True, ValueError, None),
        )
        for sample, disabled, exception, message in cases:
            with self.subTest(sample=sample):
                with self.assertRaises(exception) as raised:
                    run_sample_fixture(benchmark, sample_overrides=sample,
                                       no_execution_observations=disabled)
                if message is not None:
                    self.assertEqual(str(raised.exception), message)


if __name__ == "__main__":
    unittest.main()

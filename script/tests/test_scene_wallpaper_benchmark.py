#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from collections import defaultdict
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))
DEBUG_RUNNER_SOURCE = (
    SCRIPT_DIR.parent / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner.swift"
)
DEBUG_ARGUMENTS_RUNNER_SOURCE = (
    SCRIPT_DIR.parent
    / "MyWallpaperX/App/Debug/DebugScenePlaybackRunner+Arguments.swift"
)

import scene_wallpaper_benchmark as benchmark
import scene_preview_visual_evidence as visual
import scene_wallpaper_sample_lifecycle as lifecycle
import generate_scene_full_matrix as matrix_generator
from script.tests.scene_wallpaper_graph_output_test_support import (
    assert_named_graph_output_publication_has_one_terminal_owner,
    assert_named_provider_terminal,
    assert_visible_provider_requires_compositor_consumption,
    assert_visible_publication_execution_metrics,
    assert_utility_capture_respects_dormant_graph_members,
)

from script.tests.scene_wallpaper_benchmark_test_support import (
    static_effect_disposition,
    shader_stage,
    runtime_evidence,
    effect_runtime_disposition_preview,
    effect_cpu_event,
    effect_route_event,
    effect_execution_log,
    graph_execution_observation,
    resolved_graph_exact_evidence,
    resolved_graph_passthrough_evidence,
    resolved_graph_effect_local_failure_evidence,
    resolved_graph_effect_recovery_evidence,
    resolved_graph_effect_recovery_log,
    resolved_graph_visual_failure_log,
)


class SceneWallpaperBenchmarkTests(unittest.TestCase):
    def test_log_mode_cli_bounds_duration_and_limits_parallelism(self):
        base = ["scene_wallpaper_benchmark.py", "--app", "/tmp/App",
                "--sample-root", "/tmp/samples", "--output-dir", "/tmp/results"]
        for options, duration in (([], 7), (["--duration", "2"], 7),
                                  (["--log-only"], 4),
                                  (["--log-only", "--jobs", "9"], 4),
                                  (["--log-only", "--duration", "2"], 3),
                                  (["--log-only", "--duration", "5", "--jobs", "2"], 5)):
            with self.subTest(options=options), mock.patch.object(sys, "argv", base + options):
                self.assertEqual(benchmark.parse_args().duration, duration)
        for options in (["--jobs", "2"], ["--log-only", "--jobs", "0"],
                        ["--log-only", "--jobs", "-1"],
                        ["--log-only", "--no-execution-observations"],
                        ["--log-only", "--product-entry-audio-baseline"]):
            with self.subTest(options=options), mock.patch.object(sys, "argv", base + options), \
                    mock.patch.object(sys, "stderr", io.StringIO()), self.assertRaises(SystemExit):
                benchmark.parse_args()

    def test_parallel_scheduler_preserves_order_retires_each_worker_and_joins_on_error(self):
        for tool_error in (False, True):
            with self.subTest(tool_error=tool_error), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                matrix = root / "matrix.json"
                matrix.write_text(json.dumps({"schema_version": 1, "name": "isolated-log-audit",
                                              "samples": [{"id": value} for value in ("11", "22", "33", "bad")]}))
                output = root / "output"
                rendezvous = threading.Barrier(2)
                third_started = threading.Event()
                peer_finished = threading.Event()
                lock = threading.Lock()
                events = []
                real_run_sample = benchmark.run_sample

                def stage(app, runtime):
                    binary = runtime / "signed-app"
                    binary.write_bytes(b"owned-stage")
                    return binary, {"fixture": str(binary)}

                def run(**arguments):
                    identity = arguments["sample"]["id"]
                    if identity == "bad":
                        return real_run_sample(**arguments)
                    runtime = arguments["runtime_root"]
                    sample_path = runtime / "runtime-samples" / identity
                    home = runtime / "runtime-homes" / identity
                    sample_path.mkdir(parents=True)
                    (home / "tmp").mkdir(parents=True)
                    self.assertTrue(arguments["runtime_binary"].is_file())
                    self.assertTrue(arguments["log_only"])
                    self.assertEqual(arguments["duration"], 4)
                    with lock:
                        events.append(identity)
                    if identity in {"11", "22"}:
                        rendezvous.wait(timeout=5)
                    if identity == "11" and tool_error:
                        raise RuntimeError("unknown tool fault")
                    if identity == "22":
                        if not tool_error:
                            self.assertTrue(third_started.wait(5))
                        self.assertTrue(arguments["runtime_binary"].is_file())
                        peer_finished.set()
                    if identity == "33":
                        if not tool_error:
                            self.assertFalse((runtime / "runtime-homes/11").exists())
                            self.assertFalse((runtime / "runtime-samples/11").exists())
                        third_started.set()
                    return {"id": identity, "passed": True, "failures": [],
                            "runtime": {"loaded_ratio": 1}, "evidence": {},
                            "runtime_sample": str(sample_path), "runtime_home": str(home),
                            "runtime_retained": True}

                command = ["scene_wallpaper_benchmark.py", "--app", str(root / "App"),
                           "--sample-root", str(root / "samples"), "--matrix", str(matrix),
                           "--output-dir", str(output), "--log-only", "--jobs", "2"]
                with mock.patch.object(sys, "argv", command), \
                        mock.patch.object(sys, "stdout", io.StringIO()), \
                        mock.patch.object(benchmark, "stage_signed_app", side_effect=stage) as staged, \
                        mock.patch.object(benchmark, "verify_staged_app") as verified, \
                        mock.patch.object(benchmark, "run_sample", side_effect=run), \
                        mock.patch.object(lifecycle, "discard_staged_app") as discarded:
                    if tool_error:
                        with self.assertRaisesRegex(RuntimeError, "unknown tool fault"):
                            benchmark.main()
                    else:
                        self.assertEqual(benchmark.main(), 1)
                        report = json.loads((output / "report.json").read_text())
                        self.assertEqual([value["id"] for value in report["samples"]], ["11", "22", "33", "bad"])
                        self.assertEqual(report["samples"][-1]["input_status"], "source-invalid")
                        self.assertTrue(all(value["passed"] for value in report["samples"][:-1]))
                        self.assertTrue(all(value["runtime_home"] is None for value in report["samples"]))
                        self.assertEqual(report["summary"]["preview_visual"]["status"], "not-requested")
                        self.assertFalse(report["summary"]["performance"]["comparison_eligible"])
                        verified.assert_called_once()
                        discarded.assert_called_once()
                    staged.assert_called_once()
                self.assertEqual(set(events[:2]), {"11", "22"})
                self.assertTrue(peer_finished.is_set())
                self.assertFalse((output / "runtime").exists())

    def test_disabled_graph_observations_report_unavailable_without_execution_pass(
        self,
    ) -> None:
        preview = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
        ])
        disposition, _ = resolved_graph_passthrough_evidence(
            68, include_program=True
        )
        default = benchmark.resolved_material_graph_execution_metrics(
            preview, "", static_disposition=disposition
        )
        self.assertIn(
            "resolved material graph terminal evidence missing",
            benchmark.resolved_material_graph_execution_failures(default),
        )
        self.assertIn(
            "resolved material graph passthrough terminal evidence missing",
            default["validation_failures"],
        )
        disabled = benchmark.resolved_material_graph_execution_metrics(
            preview, "", static_disposition=disposition,
            execution_observations_enabled=False,
        )
        self.assertEqual(disabled["observation_status"], "unavailable")
        self.assertEqual(
            disabled["observation_unavailable_reason"], "explicitly-disabled"
        )
        self.assertTrue(disabled["capability"]["has_evidence"])
        self.assertEqual(disabled["capability"]["accepted_layer_ids"], [68])
        self.assertFalse(disabled["has_evidence"])
        self.assertFalse(disabled["execution_succeeded"])
        self.assertFalse(disabled["contract_succeeded"])
        self.assertEqual(disabled["succeeded_layer_ids"], [])
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(disabled), []
        )
        # A strict direct validator call still cannot turn unavailable into PASS.
        self.assertTrue(benchmark.resolved_material_graph_execution_failures(
            disabled, require_evidence=True
        ))

    def test_disabled_zero_graph_observations_do_not_claim_zero_contract_success(
        self,
    ) -> None:
        preview = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8"
        )
        for log in (
            "",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=0 encoded=0 failures=0 deferred=0 pending=0 gpuEncoded=0",
        ):
            with self.subTest(log=log):
                metrics = benchmark.resolved_material_graph_execution_metrics(
                    preview, log, execution_observations_enabled=False
                )
                self.assertFalse(metrics["has_evidence"])
                self.assertFalse(metrics["zero_contract_succeeded"])
                self.assertFalse(metrics["dormant_contract_succeeded"])
                self.assertFalse(metrics["contract_succeeded"])
                self.assertEqual(
                    benchmark.resolved_material_graph_execution_failures(metrics),
                    [],
                )

    def test_disabled_observations_preserve_invalid_static_and_seen_execution_evidence(
        self,
    ) -> None:
        aggregate = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8"
        )
        route = (
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted"
        )
        preview = aggregate + "\n" + route
        executor = (
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=1 deferred=0 pending=0 gpuEncoded=1"
        )
        cases = (
            (preview + "\n" + route, "",
             "resolved material graph accepted layer evidence duplicated"),
            (preview.replace("candidates=1", "candidates=2"), "",
             "resolved material graph capability count conservation failed"),
            (aggregate + "\n" + route + " dependency=unknown", "",
             "resolved material graph accepted layer evidence malformed"),
            (preview, executor,
             "resolved material graph executor reported failures"),
            (preview, executor.replace("gpuEncoded=1", "gpuEncoded=2"),
             "resolved material graph executor GPU encode conservation failed"),
            (preview, executor.replace("encoded=1", "encoded=invalid"),
             "resolved material graph executor evidence malformed"),
            (preview, "schema=1 axis=graph-execution invalid=payload",
             "resolved material graph observation evidence malformed"),
        )
        for current_preview, log, expected in cases:
            with self.subTest(expected=expected):
                metrics = benchmark.resolved_material_graph_execution_metrics(
                    current_preview, log, execution_observations_enabled=False
                )
                self.assertIn(
                    expected,
                    benchmark.resolved_material_graph_execution_failures(metrics),
                )
        malformed_performance = benchmark.performance_metrics(
            "phase=performance targetFPS=60 targetFPS=30", surface_count=1
        )
        self.assertEqual(benchmark.performance_failures(malformed_performance), [
            "performance evidence unavailable: duplicate performance field: targetFPS"
        ])

    def test_disabled_observations_skip_implicit_utility_and_binding_demand(
        self,
    ) -> None:
        utility = benchmark.utility_runtime_metrics("\n".join([
            "utilityLayerCount: 1", "utilityCapturePlannedCount: 1",
            "utilityDependencyEdgeCount: 1", "utilityNamedConsumerCount: 1",
            "utilityNamedTargetPlannedCount: 1", "utilityNamedBindingPlannedCount: 1",
            "utilityNamedTargetGapCount: 0", "utility layer 68: capture kind=image",
        ]))
        absent = {"succeeded_layer_ids": [], "failed_layer_ids": []}
        sample = {"expected_utility_capture_planned": 1}
        self.assertIn("utility capture execution below planned count",
                      benchmark.utility_runtime_failures(
                          sample, utility, capture_execution=absent
                      ))
        self.assertEqual(benchmark.utility_runtime_failures(
            sample, utility, capture_execution=absent,
            execution_observations_enabled=False,
        ), [])
        self.assertEqual(benchmark.named_target_binding_failures(
            {}, 1, absent, execution_observations_enabled=False,
        ), [])
        seen_failure = {"succeeded_layer_ids": [], "failed_layer_ids": [68]}
        self.assertIn("utility capture execution reported failures",
                      benchmark.utility_runtime_failures(
                          sample, utility, capture_execution=seen_failure,
                          execution_observations_enabled=False,
                      ))
        self.assertIn("named target binding execution reported failures",
                      benchmark.named_target_binding_failures(
                          {}, 1, seen_failure, execution_observations_enabled=False,
                      ))
        self.assertIn("utility capture_planned mismatch",
                      benchmark.utility_runtime_failures(
                          {"expected_utility_capture_planned": 2}, utility,
                          capture_execution=absent,
                          execution_observations_enabled=False,
                      ))

    def test_disabled_observations_reject_cli_execution_requirements(self) -> None:
        for option in ("--require-effect-execution", "--require-graph-execution"):
            with self.subTest(option=option), mock.patch.object(sys, "argv", [
                "scene_wallpaper_benchmark.py", "--app", "/tmp/MyWallpaperX",
                "--sample-root", "/tmp/samples", "--output-dir", "/tmp/results",
                "--no-execution-observations", option,
            ]), mock.patch.object(sys, "stderr"):
                with self.assertRaises(SystemExit) as error:
                    benchmark.parse_args()
                self.assertEqual(error.exception.code, 2)

    def test_disabled_observations_reject_matrix_execution_promises_before_staging(
        self,
    ) -> None:
        expectations = (
            "expected_effect_execution_schema",
            "expected_resolved_material_graph_succeeded_layer_ids",
            "expected_resolved_material_graph_local_fallbacks",
            "expected_resolved_material_graph_extent_lifecycle",
            "expected_effect_recoveries",
            "minimum_activation_passthrough_count",
            "required_utility_capture_succeeded_layer_ids",
            "required_named_target_capture_succeeded_layer_ids",
            "required_visible_graph_output_publication_succeeded_layer_ids",
            "required_named_graph_output_publication_succeeded_layer_ids",
            "required_named_target_binding_succeeded_layer_ids",
        )
        for key in expectations:
            with self.subTest(key=key):
                with self.assertRaisesRegex(ValueError, key):
                    benchmark.validate_execution_observation_policy(
                        execution_observations_enabled=False,
                        sample={"id": "fixture", key: []},
                    )
        # A zero execution promise is still a promise, and must not be ignored.
        matrix = {"name": "fixture", "samples": [{
            "id": "fixture",
            "expected_resolved_material_graph_succeeded_layer_ids": [],
        }]}
        with mock.patch.object(sys, "argv", [
            "scene_wallpaper_benchmark.py", "--app", "/tmp/MyWallpaperX",
            "--sample-root", "/tmp/samples", "--output-dir", "/tmp/results",
            "--no-execution-observations",
        ]), mock.patch.object(benchmark, "load_matrix", return_value=matrix), \
                mock.patch.object(benchmark, "require_fresh_output_dir") as output, \
                mock.patch.object(benchmark, "stage_signed_app") as stage, \
                mock.patch.object(sys, "stderr"):
            self.assertEqual(benchmark.main(), 2)
        output.assert_not_called()
        stage.assert_not_called()

    def test_resolved_material_graph_execution_can_be_required_from_cli(
        self,
    ) -> None:
        old_argv = sys.argv
        try:
            sys.argv = [
                "scene_wallpaper_benchmark.py",
                "--app", "/tmp/MyWallpaperX",
                "--sample-root", "/tmp/samples",
                "--output-dir", "/tmp/results",
                "--require-graph-execution",
            ]
            args = benchmark.parse_args()
        finally:
            sys.argv = old_argv
        self.assertTrue(args.require_graph_execution)

    def test_cursor_ripple_persistence_can_be_required_from_cli(self) -> None:
        old_argv = sys.argv
        try:
            sys.argv = [
                "scene_wallpaper_benchmark.py",
                "--app", "/tmp/MyWallpaperX",
                "--sample-root", "/tmp/samples",
                "--output-dir", "/tmp/results",
                "--require-cursor-ripple-persistence",
            ]
            args = benchmark.parse_args()
        finally:
            sys.argv = old_argv
        self.assertTrue(args.require_cursor_ripple_persistence)


if __name__ == "__main__":
    unittest.main()

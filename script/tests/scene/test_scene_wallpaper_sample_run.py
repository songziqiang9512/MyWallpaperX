"""Behavior of the synchronous isolated sample-to-report boundary."""

from __future__ import annotations

import sys as _sys
from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parents[2] / "web"))

import json
import hashlib
import os
import sys
import tempfile
import unittest
from unittest import mock
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SCRIPT_DIR))

import scene_wallpaper_benchmark as benchmark
import scene_wallpaper_sample_run as sample_run
from script.evidence import promote_scene_evidence as promotion
import web_benchmark_capture as capture
import scene_preview_visual_evidence as visual
from scene_wallpaper_graph_output_metrics import structured_runtime_observations, terminal_snapshot_metrics
from scene_capability_census_io import tree_manifest
from scene_preview_visual_evidence import _write_rgb_png
from script.tests.support.scene_wallpaper_benchmark_test_support import effect_execution_log
from script.tests.support.scene_wallpaper_sample_fixture import run_sample_fixture, write_png
from script.tests.support.scene_wallpaper_sample_fixture import PERFORMANCE_LOG


WINDOW_FIELDS = (
    "ready_non_black", "hover_non_black", "after_non_black", "flat_border_ratio",
    "motion", "hover_motion", "pointer_trajectory_non_black",
    "pointer_trajectory_motion", "puppet_interaction", "preview_visual",
)


def collect_window_evidence(root, *, hover=True, trajectory_count=7, sample=None):
    """Call the visual axis consumed by the real sample runner."""
    values = visual.collect_sample_visual_evidence(
        root / "source", root, sample=sample or {},
        hover_pointer=(0.5, 0.5) if hover else None,
        pointer_trajectory=[(0.1, 0.2)] * trajectory_count or None, log_text="",
    )
    return {field: values[field] for field in WINDOW_FIELDS}


def write_window_inputs(root, trajectory_count=7):
    source = root / "source"
    source.mkdir()
    (source / "project.json").write_text(json.dumps({"preview": "own.png"}))
    write_png(source / "own.png")
    names = ["ready", "before", "hover", "after", "drag-held", "spring-after"]
    names += [f"pointer-trajectory-{index:02d}" for index in range(trajectory_count)]
    for index, name in enumerate(names):
        write_png(root / f"scene-{name}-window.png", shifted=bool(index % 2))


def reference_window_evidence(root, *, hover=True, trajectory_count=7):
    """The report's existing public metrics, independent of caller scheduling."""
    ready = root / f"scene-{'before' if hover else 'ready'}-window.png"
    after, hovered = root / "scene-after-window.png", root / "scene-hover-window.png"
    trajectory = [root / f"scene-pointer-trajectory-{index:02d}-window.png"
                  for index in range(trajectory_count)]
    return {
        "ready_non_black": capture.png_has_non_black_pixel(ready),
        "hover_non_black": capture.png_has_non_black_pixel(hovered) if hover else None,
        "after_non_black": capture.png_has_non_black_pixel(after),
        "flat_border_ratio": {"ready": capture.png_flat_border_ratio(ready),
                              "after": capture.png_flat_border_ratio(after),
                              **({"hover": capture.png_flat_border_ratio(hovered)} if hover else {})},
        "motion": capture.png_motion_metrics(ready, after),
        "hover_motion": {"before_to_hover": capture.png_motion_metrics(ready, hovered),
                         "hover_to_after": capture.png_motion_metrics(hovered, after)} if hover else None,
        "pointer_trajectory_non_black": [capture.png_has_non_black_pixel(path) for path in trajectory],
        "pointer_trajectory_motion": visual.pointer_trajectory_motion_metrics(ready, trajectory),
        "puppet_interaction": None,
        "preview_visual": visual.collect_preview_visual_evidence(root / "source", after, root),
    }


class SceneWallpaperSampleRunTests(unittest.TestCase):
    def setUp(self):
        capture._decode_png_rows_cached.cache_clear()
        capture._png_rgb_pixels_cached.cache_clear()
        self.addCleanup(capture._decode_png_rows_cached.cache_clear)
        self.addCleanup(capture._png_rgb_pixels_cached.cache_clear)

    def test_window_schedule_preserves_all_fields_and_bounds_decode_misses(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_window_inputs(root)
            expected = reference_window_evidence(root)
            montage = (root / "preview-comparison.png").read_bytes()
            capture._decode_png_rows_cached.cache_clear()
            capture._png_rgb_pixels_cached.cache_clear()
            actual = collect_window_evidence(root)
            self.assertEqual(actual, expected)
            self.assertEqual((root / "preview-comparison.png").read_bytes(), montage)
            self.assertLessEqual(capture._decode_png_rows_cached.cache_info().misses, 12)
            self.assertEqual(capture._decode_png_rows_cached.cache_info().maxsize, 4)

    def test_window_schedule_preserves_missing_bad_and_shape_mismatch_results(self):
        for failure in ("missing", "bad", "shape"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                write_window_inputs(root)
                path = root / "scene-before-window.png"
                if failure == "missing":
                    path.unlink()
                elif failure == "bad":
                    path.write_bytes(b"not a PNG")
                else:
                    _write_rgb_png(path, 4, 8, [bytes((50, 60, 70)) * 4] * 8)
                self.assertEqual(collect_window_evidence(root), reference_window_evidence(root))

    def test_window_schedule_keeps_empty_trajectory_and_no_hover_schema(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_window_inputs(root, 0)
            self.assertEqual(collect_window_evidence(root, hover=False, trajectory_count=0),
                             reference_window_evidence(root, hover=False, trajectory_count=0))

    def test_window_schedule_preserves_roi_errors_and_missing_decode_precedence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_window_inputs(root, 0)
            valid = collect_window_evidence(root, trajectory_count=0, sample={
                "cursor_drag_response": "spring-return", "cursor_interaction_roi": (0, 0, .5, 1)})
            self.assertEqual(valid["hover_motion"]["before_to_drag"], capture.png_motion_metrics(
                root / "scene-before-window.png", root / "scene-drag-held-window.png",
                region=(0, 0, .5, 1)))
            for roi in ((-1, 0, 1, 1), (0, 0, 0.01, 1), (0, 0, float("nan"), 1)):
                with self.subTest(roi=roi), self.assertRaises(ValueError):
                    collect_window_evidence(root, trajectory_count=0, sample={
                        "cursor_drag_response": "spring-return", "cursor_interaction_roi": roi})
            (root / "scene-before-window.png").unlink()
            result = collect_window_evidence(root, trajectory_count=0, sample={
                "cursor_drag_response": "spring-return", "cursor_interaction_roi": (-1, 0, 1, 1)})
            self.assertIsNone(result["hover_motion"]["before_to_drag"])
            self.assertIsNone(result["hover_motion"]["before_to_spring_after"])

    def test_window_schedule_observes_rewrite_and_deletion_after_cached_result(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_window_inputs(root, 0)
            path = root / "scene-after-window.png"
            first = collect_window_evidence(root, trajectory_count=0)
            stat = path.stat()
            write_png(path, black=True)
            os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns + 1_000_000))
            second = collect_window_evidence(root, trajectory_count=0)
            self.assertTrue(first["after_non_black"])
            self.assertFalse(second["after_non_black"])
            self.assertNotEqual(first["motion"], second["motion"])
            path.unlink()
            third = collect_window_evidence(root, trajectory_count=0)
            self.assertFalse(third["after_non_black"])
            self.assertIsNone(third["motion"])

    def test_complete_collected_result_preserves_frozen_public_report(self) -> None:
        expected = json.loads((SCRIPT_DIR / (
            "tests/fixtures/scene_wallpaper_sample_report_golden.json"
        )).read_text())
        for field in ("composition_observations", "particle_component_observations"):
            expected["runtime"][field]["source_line_numbers"] = []
        actual, command = run_sample_fixture(benchmark)
        self.assertEqual(actual, expected)
        self.assertTrue(actual["passed"])
        self.assertEqual(len(actual["runtime"]), len(expected["runtime"]))
        self.assertEqual(command[1], "--mwx-debug-scene-root")
        self.assertEqual(actual["runtime"]["runtime_evidence"]["visible_layer_ids"], [1])

    def test_cold_start_allowance_preserves_bounded_timeout_and_report(self) -> None:
        waits = []
        result, _ = run_sample_fixture(benchmark, control={
            "startup_timeout_allowance": 180, "observed_wait_timeouts": waits,
            "timeout": True,
        })
        self.assertEqual(waits, [187, 5])
        self.assertEqual(result["startup_timeout_allowance"], 180)
        self.assertTrue(result["timed_out"])
        self.assertIn("process timeout", result["failures"])

    def test_failed_collection_promotes_actual_optional_files_without_a_projection(self):
        cases = (
            {"missing_ready": True, "missing_preview": True, "missing_runtime": True},
            {"missing_ready": True, "missing_preview": True},
            {"runtime_path": "-", "missing_runtime": True},
            {"runtime_path": "-", "missing_preview": True},
            {"runtime_path": "   ", "missing_runtime": True},
        )
        for control in cases:
            with self.subTest(control=control):
                def check_report(result, root):
                    evidence = result["evidence"]
                    expected_keys = {"app_log"}
                    for key, missing in (("preview_log", control.get("missing_preview")),
                                         ("runtime_evidence", control.get("missing_runtime"))):
                        if missing:
                            self.assertIsNone(evidence[key])
                        else:
                            self.assertTrue(Path(evidence[key]).is_file())
                            expected_keys.add(key)
                    report_path = root / "output/report.json"
                    report_path.write_text(json.dumps({"samples": [result]}))
                    with mock.patch.object(promotion, "EVIDENCE_ROOT", root / "evidence"):
                        package = promotion.promote([("failed", report_path)], Path("run"), 1)
                    self.assertEqual((package / "failed/report.json").read_bytes(),
                                     report_path.read_bytes())
                    manifest = json.loads((package / "manifest.json").read_text())
                    archived = manifest["runs"][0]["files"]
                    self.assertEqual({row["key"] for row in archived}, expected_keys)
                    for row in archived:
                        self.assertEqual((package / row["path"]).read_bytes(),
                                         Path(evidence[row["key"]]).read_bytes())

                result, _ = run_sample_fixture(benchmark, log_only=True, control={
                    **control, "timeout": True, "exit_code": -15,
                    "result_observer": check_report,
                })
                failures = ["process timeout", "process exit -15"]
                if control.get("missing_ready"):
                    failures.append("missing ready event")
                failures.append("missing runtime evidence path")
                if control.get("missing_ready"):
                    failures.append("no completed GPU frame")
                if control.get("missing_preview"):
                    failures += ["camera projection evidence missing",
                                 "particle load evidence missing"]
                if control.get("missing_runtime"):
                    failures += ["Scene runtime evidence missing or invalid",
                                 "Scene runtime evidence schema_version mismatch"]
                self.assertEqual(result["failures"], failures)
                self.assertFalse(result["passed"])
                self.assertTrue(result["timed_out"])
                self.assertEqual(result["exit_code"], -15)

    def test_declared_missing_or_foreign_runtime_files_are_still_rejected_by_promotion(self):
        for control, error in (({"missing_runtime": True}, "evidence file is missing"),
                               ({"foreign_runtime_path": True}, "evidence path escapes")):
            with self.subTest(control=control):
                def check_report(result, root):
                    self.assertIsInstance(result["evidence"]["runtime_evidence"], str)
                    report_path = root / "output/report.json"
                    report_path.write_text(json.dumps({"samples": [result]}))
                    with self.assertRaisesRegex(ValueError, error):
                        promotion.promotion_plan([("failed", report_path)])

                result, _ = run_sample_fixture(benchmark, log_only=True, control={
                    **control, "result_observer": check_report,
                })
                self.assertFalse(result["passed"])
                self.assertNotIn("missing runtime evidence path", result["failures"])

    def test_loose_run_keeps_real_tree_and_explicit_package_expectations(self) -> None:
        copied = []
        result, command = run_sample_fixture(benchmark, control={
            "loose_source": True, "expect_current_tree": True,
            "installation_marker": True, "observed_runtime_files": copied,
        })
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(command[1], "--mwx-debug-scene-root")
        self.assertIsNone(result["package_file"])
        self.assertIsNone(result["hashes"]["package_sha256"])
        self.assertEqual(len(result["hashes"]["tree_sha256"]), 64)
        self.assertIn("scene.json", copied)
        self.assertNotIn("scene.pkg", copied)
        self.assertNotIn(".mywallpaperx-steam-version.json", copied)
        self.assertIn(".mywallpaperx-steam-version.json.author", copied)
        for field in ("package_sha256", "tree_sha256"):
            with self.subTest(field=field):
                invalid, _ = run_sample_fixture(benchmark,
                    sample_overrides={field: "wrong"}, control={"loose_source": True})
                self.assertFalse(invalid["passed"])
                self.assertEqual(invalid["failures"], [f"{field} mismatch"])
                self.assertIsNone(invalid["hashes"]["package_sha256"])

    def test_invalid_start_allowance_rejected_before_launch(self) -> None:
        for allowance in (0, -1, float("inf"), float("nan")):
            with self.subTest(allowance=allowance), self.assertRaisesRegex(
                ValueError, "startup_timeout_allowance"
            ):
                run_sample_fixture(benchmark, control={"startup_timeout_allowance": allowance})

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
            "missing_ready": True, "missing_runtime": True,
            "missing_performance": True, "black": True,
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

    def test_log_only_keeps_runtime_chain_without_calling_visual_axis(self):
        with mock.patch.object(sample_run, "collect_sample_visual_evidence",
                               side_effect=AssertionError("log audit read pixels")):
            result, command = run_sample_fixture(benchmark, log_only=True,
                sample_overrides={"requires_motion": True, "minimum_changed_ratio": 1,
                                  "maximum_flat_border_ratio": 0})
        self.assertTrue(result["passed"], result["failures"])
        self.assertIn("--mwx-debug-scene-log-only", command)
        self.assertNotIn("--mwx-debug-scene-no-execution-observations", command)
        self.assertEqual(result["evidence"]["visual_status"], "not-requested")
        self.assertNotIn("ready_snapshot", result["evidence"])
        self.assertGreater(result["runtime"]["performance"]["completed_frames"], 0)
        self.assertEqual(result["runtime"]["runtime_evidence"]["schema_version"], 1)
        short, _ = run_sample_fixture(benchmark, log_only=True, control={
            "missing_performance": True,
            "log_lines": ["phase=surface-submission state=completed frame=0 surface=1 gpu=completed"],
        })
        self.assertTrue(short["passed"], short["failures"])
        self.assertFalse(short["runtime"]["performance"]["available"])

    def test_log_only_requires_real_runtime_and_drain_but_visual_missing_still_fails(self):
        for control in ({"missing_ready": True}, {"missing_drain": True},
                        {"malformed_runtime": True}, {"missing_performance": True},
                        {"performance_log": PERFORMANCE_LOG.replace("completed=409", "completed=0")},
                        {"log_lines": [effect_execution_log(7, [], [], status="failed")]}):
            with self.subTest(control=control):
                result, _ = run_sample_fixture(benchmark, log_only=True, control=control)
                self.assertFalse(result["passed"], result)
                self.assertNotIn("non-black window evidence missing", result["failures"])
        missing, _ = run_sample_fixture(benchmark, control={"missing_png": True})
        self.assertIn("non-black window evidence missing", missing["failures"])
        with self.assertRaisesRegex(ValueError, "require execution observations"):
            run_sample_fixture(benchmark, log_only=True, no_execution_observations=True)

    def test_missing_project_is_a_source_invalid_row_without_starting_process(self):
        inputs = [({"missing_project": True}, "project-json-missing"),
                  ({"project_bytes": b"{"}, "json-decode-failed"),
                  ({"project_bytes": b"[]"}, "project-root-not-object"),
                  ({"project_bytes": b"\xff{}"}, "json-decode-failed"),
                  ({"project_bytes": b'{"type":"video"}'}, "project-type-not-scene")]
        for log_only in (False, True):
            for control, reason in inputs:
                with self.subTest(log_only=log_only, reason=reason):
                    result, command = run_sample_fixture(benchmark, log_only=log_only, control=control)
                    self.assertEqual(command, [])
                    self.assertEqual(result["input_status"], "source-invalid")
                    self.assertEqual(result["input_reason_code"], reason)
                    self.assertFalse(result["passed"])
                    self.assertFalse(result["runtime_retained"])
                    self.assertIsNone(result["exit_code"])
                    expected_digest = hashlib.sha256(control["project_bytes"]).hexdigest() if "project_bytes" in control else None
                    self.assertEqual(result["hashes"]["project_sha256"], expected_digest)
                    self.assertIsNone(result["hashes"]["package_sha256"])

    def test_input_hashes_describe_frozen_copy_even_when_source_changes(self):
        expected, source_after = {}, {}

        def after_copy(source, destination):
            (destination / "authored-sidecar.bin").write_bytes(b"copied-sidecar")
            expected.update(project_sha256=hashlib.sha256((destination / "project.json").read_bytes()).hexdigest(),
                            package_sha256=hashlib.sha256((destination / "scene.pkg").read_bytes()).hexdigest(),
                            tree_sha256=tree_manifest(destination)[0])
            (source / "project.json").write_text('{"type":"scene","file":"changed.json"}')
            (source / "scene.pkg").write_bytes(b"CHANGED-SOURCE")
            source_after.update(project_sha256=hashlib.sha256((source / "project.json").read_bytes()).hexdigest(),
                                package_sha256=hashlib.sha256((source / "scene.pkg").read_bytes()).hexdigest(),
                                tree_sha256=tree_manifest(source)[0])

        result, _ = run_sample_fixture(benchmark, control={"copy_observer": after_copy})
        self.assertTrue(result["passed"], result["failures"])
        self.assertEqual(result["hashes"], expected)
        self.assertTrue(all(result["hashes"][key] != value for key, value in source_after.items()))
        self.assertEqual(result["package_file"], "scene.pkg")

    def test_inherited_scene_fault_time_and_observation_variables_do_not_enter_child(self):
        inherited = {"MWX_SCENE_DEBUG_EXECUTOR_INVALIDATE_AFTER": "2", "MWX_SCENE_PARTICLE_COMPONENT_OBSERVATION": "old",
                     "MYWALLPAPERX_SCENE_DEBUG_POINTER_SECOND": "59", "MWX_SCENE_GPU_STAGE_TIMESTAMPS_OUTPUT": "/tmp/foreign",
                     "MYWALLPAPERX_SCENE_DEBUG_TIMELINE_EVIDENCE": "foreign timeline configuration",
                     "MYWALLPAPERX_SCENE_DEBUG_PUPPET_BONE_EVIDENCE": "999,1000",
                     "MWX_SCENE_DEBUG_SCENE_SWITCH_ROOT": "/tmp/foreign", "MWX_SCENE_DEBUG_SCENE_SWITCH_AFTER": "2",
                     "USER_TOOL_FIXTURE": "preserved"}
        for terminal in (False, True):
            observed = {}
            control = {"observed_environment": observed}
            if terminal:
                control["snapshot_receipts"] = lambda result_dir: [
                    "phase=snapshot-encoded request=1 commandBufferToken=2 textureToken=3 width=8 height=8",
                    f"phase=snapshot reason=after request=1 source=metal path={result_dir / 'scene-after-window.png'}",
                ]
            with self.subTest(terminal=terminal), mock.patch.dict(os.environ, inherited):
                result, _ = run_sample_fixture(benchmark, log_only=True, terminal_snapshot=terminal,
                    sample_overrides={"cursor_start_second": 12}, control=control)
            self.assertTrue(result["passed"], result["failures"])
            for key in inherited:
                if key not in {"USER_TOOL_FIXTURE", "MYWALLPAPERX_SCENE_DEBUG_POINTER_SECOND", "MWX_SCENE_PARTICLE_COMPONENT_OBSERVATION"}:
                    self.assertNotIn(key, observed)
            self.assertEqual(observed["USER_TOOL_FIXTURE"], "preserved")
            self.assertEqual(observed["MYWALLPAPERX_SCENE_DEBUG_POINTER_SECOND"], "12.0")
            self.assertEqual(observed.get("MWX_SCENE_PARTICLE_COMPONENT_OBSERVATION"), "1" if terminal else None)
            self.assertNotIn("timeline_frame_evidence", result)

    def test_explicit_puppet_bone_targets_reach_non_cursor_child_environment(self):
        key = "MYWALLPAPERX_SCENE_DEBUG_PUPPET_BONE_EVIDENCE"
        for layers in ([28, 32], [71, 93]):
            observed = {}
            with self.subTest(layers=layers), mock.patch.dict(os.environ, {key: "999"}):
                result, command = run_sample_fixture(benchmark, log_only=True,
                    sample_overrides={"puppet_interaction_layer_ids": layers},
                    control={"observed_environment": observed})
            self.assertTrue(result["passed"], result["failures"])
            self.assertEqual(observed[key], ",".join(map(str, layers)))
            self.assertNotIn("--mwx-debug-scene-cursor-drag-to-json", command)
            self.assertNotIn("--mwx-debug-scene-hover-pointer-json", command)

    def test_cursor_start_delay_transport_and_timing_environment_isolation(self):
        delay_key = "MYWALLPAPERX_SCENE_DEBUG_POINTER_DELAY"
        second_key = "MYWALLPAPERX_SCENE_DEBUG_POINTER_SECOND"
        inherited = {delay_key: "6", second_key: "59", "USER_TOOL_FIXTURE": "preserved"}
        for declared in ({}, {"cursor_start_delay": 0}, {"cursor_start_delay": 0.125},
                         {"cursor_start_second": 12}):
            observed = {}
            with self.subTest(declared=declared), mock.patch.dict(os.environ, inherited):
                result, _ = run_sample_fixture(benchmark, sample_overrides=declared,
                    control={"observed_environment": observed})
            self.assertTrue(result["passed"], result["failures"])
            self.assertEqual(observed["USER_TOOL_FIXTURE"], "preserved")
            for field, key in (("cursor_start_delay", delay_key), ("cursor_start_second", second_key)):
                if field in declared:
                    self.assertEqual(observed[key], str(float(declared[field])))
                else:
                    self.assertNotIn(key, observed)

    def test_cursor_start_delay_rejects_invalid_or_conflicting_requests_before_launch(self):
        invalid = [{"cursor_start_delay": value}
                   for value in (-1, 7, 8, float("nan"), float("inf"), True, "1", None, [])]
        invalid.append({"cursor_start_delay": 0, "cursor_start_second": 12})
        for declared in invalid:
            observed = {}
            with self.subTest(declared=declared), self.assertRaisesRegex(ValueError, "cursor_start_delay"):
                run_sample_fixture(benchmark, sample_overrides=declared,
                    control={"observed_environment": observed})
            self.assertEqual(observed, {})

    def test_puppet_bone_targets_keep_cursor_requirement_and_reject_non_integer_before_launch(self):
        cursor = {"cursor_drag_response": "spring-return",
                  "hover_pointer_normalized": [0, 0], "cursor_drag_to_normalized": [0.25, 0]}
        for response in ("spring-return", "no-capture"):
            observed = {}
            with self.subTest(response=response), self.assertRaisesRegex(ValueError, "integer layer IDs"):
                run_sample_fixture(benchmark, log_only=True,
                    sample_overrides={**cursor, "cursor_drag_response": response},
                    control={"observed_environment": observed})
            self.assertEqual(observed, {})
        for layers in (["28"], [28.0], [True], [28, None]):
            for dragging in (False, True):
                observed = {}
                with self.subTest(layers=layers, dragging=dragging), self.assertRaisesRegex(ValueError, "integer layer IDs"):
                    run_sample_fixture(benchmark, log_only=True,
                        sample_overrides={**(cursor if dragging else {}), "puppet_interaction_layer_ids": layers},
                        control={"observed_environment": observed})
                self.assertEqual(observed, {})

    def test_explicit_timeline_evidence_uses_existing_environment_transport_and_report(self):
        key = "MYWALLPAPERX_SCENE_DEBUG_TIMELINE_EVIDENCE"
        for config in (
            {"layerIDs": [89, 233], "sceneTimeWindow": [0, 5], "interval": .2, "maxSamples": 26},
            # Swift owns its configuration schema; this adapter only carries JSON.
            {"futureNativeField": {"enabled": True}},
        ):
            observed = {}
            with self.subTest(config=config), mock.patch.dict(os.environ, {
                key: "foreign", "MYWALLPAPERX_SCENE_DEBUG_SCENE_TIME": "99",
            }):
                result, _ = run_sample_fixture(benchmark, log_only=True,
                    sample_overrides={"timeline_frame_evidence": config},
                    control={"observed_environment": observed})
            self.assertEqual(json.loads(observed[key]), config)
            self.assertNotIn("MYWALLPAPERX_SCENE_DEBUG_SCENE_TIME", observed)
            self.assertEqual(result["timeline_frame_evidence"], config)
            self.assertNotIn("timeline_frame_evidence", result["runtime"])

    def test_timeline_evidence_transport_rejects_non_object_and_nonfinite_json(self):
        for config in ([], "timeline", True, 3, {"interval": float("inf")},
                       {"sceneTimeWindow": [0, float("nan")]}):
            observed = {}
            with self.subTest(config=config), self.assertRaises(ValueError):
                run_sample_fixture(benchmark, log_only=True,
                    sample_overrides={"timeline_frame_evidence": config},
                    control={"observed_environment": observed})
            self.assertEqual(observed, {})

    def test_terminal_snapshot_uses_real_receipt_identity_dimensions_and_keeps_log_only_claim(self):
        def receipts(result_dir):
            return ["MWX DEBUG SCENE: phase=snapshot-encoded request=17 commandBufferToken=43 textureToken=67 width=16 height=16",
                    f"MWX DEBUG SCENE: phase=snapshot reason=after request=17 source=metal path={result_dir / 'scene-after-window.png'}"]
        result, command = run_sample_fixture(benchmark, log_only=True, terminal_snapshot=True, snapshot_max_edge=512,
                                            control={"snapshot_receipts": receipts})
        self.assertTrue(result["passed"], result["failures"])
        self.assertIn("--mwx-debug-scene-terminal-snapshot", command)
        self.assertEqual(command[command.index("--mwx-debug-scene-capture-max-edge") + 1], "512")
        self.assertEqual(result["observation_duration_seconds"], 7)
        evidence = result["evidence"]
        self.assertEqual(evidence["visual_status"], "not-requested")
        capture = evidence["snapshot_capture"]
        self.assertEqual(capture["status"], "captured")
        self.assertEqual((capture["request_id"], capture["command_buffer_token"], capture["texture_token"]), (17, "43", "67"))
        self.assertEqual((capture["source_width"], capture["source_height"], capture["output_width"], capture["output_height"]), (16, 16, 8, 8))
        self.assertIn("not-presented-or-per-input-visibility", capture["claim_boundary"])
        self.assertTrue(result["runtime"]["lifecycle"]["gpu_drained"])
        self.assertIsInstance(capture["encoded_line_number"], int)
        self.assertGreater(capture["encoded_line_number"], 0)
        with tempfile.TemporaryDirectory(prefix="mwx-snapshot-path-") as directory:
            root = Path(directory)
            after, periodic = root / "scene-after-window.png", root / "renamed 周期 image.png"
            write_png(after)
            write_png(periodic, shifted=True)
            for request, cb, texture, width, height in ((17, 43, 67, 16, 16), (91, 103, 211, 31, 19)):
                encoded = (f"phase=snapshot-encoded request={request} commandBufferToken={cb} "
                           f"textureToken={texture} width={width} height={height}")
                lines = [encoded, f"phase=snapshot reason=after request={request} source=metal path={after}",
                    f"phase=snapshot-encoded request={request + 1} commandBufferToken=809 textureToken=811 width=99 height=71",
                    f"phase=snapshot reason=series-0007 request={request + 1} source=metal path={periodic}"]
                text = "\n".join(lines)
                default = terminal_snapshot_metrics(root, text)
                self.assertEqual((default["request_id"], default["command_buffer_token"],
                                  default["texture_token"], default["encoded_line_number"]),
                                 (request, str(cb), str(texture), 1))
                self.assertEqual((default["source_width"], default["source_height"]), (width, height))
                selected = terminal_snapshot_metrics(root, text, snapshot_path=periodic)
                self.assertEqual(selected["status"], "captured")
                self.assertEqual((selected["path"], selected["request_id"], selected["command_buffer_token"],
                                  selected["texture_token"], selected["encoded_line_number"]),
                                 (str(periodic), request + 1, "809", "811", 3))
                self.assertEqual((selected["source_width"], selected["source_height"],
                                  selected["output_width"], selected["output_height"]), (99, 71, 8, 8))
                # Explicit paths consume the recorded reason, not a filename convention.
                renamed_reason = text.replace("reason=series-0007", "reason=renamed-phase")
                self.assertEqual(terminal_snapshot_metrics(root, renamed_reason, snapshot_path=periodic)
                                 ["request_id"], request + 1)
                self.assertEqual(terminal_snapshot_metrics(root, text, snapshot_path=root / "absent.png")
                                 ["status"], "missing-or-invalid")

    def test_ordinary_capture_forwards_explicit_edge_without_terminal_mode(self):
        for edge in (None, 512):
            with self.subTest(edge=edge):
                _, command = run_sample_fixture(benchmark, snapshot_max_edge=edge)
                self.assertNotIn("--mwx-debug-scene-log-only", command)
                self.assertNotIn("--mwx-debug-scene-terminal-snapshot", command)
                if edge is None:
                    self.assertNotIn("--mwx-debug-scene-capture-max-edge", command)
                else:
                    self.assertEqual(command[command.index("--mwx-debug-scene-capture-max-edge") + 1], "512")

    def test_pointer_phase_captures_enable_existing_component_observation(self):
        for disabled in (False, True):
            observed = {}
            with self.subTest(disabled=disabled):
                run_sample_fixture(benchmark, no_execution_observations=disabled,
                    sample_overrides={"pointer_trajectory_normalized": [[-.2, 0], [.2, 0]]},
                    control={"observed_environment": observed})
                self.assertEqual(observed.get("MWX_SCENE_PARTICLE_COMPONENT_OBSERVATION"),
                                 None if disabled else "1")

    def test_terminal_capture_missing_misrouted_or_unencoded_is_unqualified(self):
        for failure in ("missing-png", "wrong-path", "missing-encoded", "wrong-request", "missing-tokens",
                        "zero-source-size", "zero-source-height", "wrong-reason", "wrong-source",
                        "duplicate-persist", "ambiguous-reason", "duplicate-encoded", "ambiguous-encoded",
                        "encoded-after-persist"):
            def receipts(result_dir):
                path = result_dir / ("foreign.png" if failure == "wrong-path" else "scene-after-window.png")
                encoded_request = 18 if failure == "wrong-request" else 17
                reason = "series-0007" if failure == "wrong-reason" else "after"
                source = "window" if failure == "wrong-source" else "metal"
                lines = [f"MWX DEBUG SCENE: phase=snapshot reason={reason} request=17 source={source} path={path}"]
                if failure != "missing-encoded":
                    token = "" if failure == "missing-tokens" else "commandBufferToken=43 textureToken=67 "
                    width = 0 if failure == "zero-source-size" else 8
                    height = 0 if failure == "zero-source-height" else 8
                    lines.insert(0, f"MWX DEBUG SCENE: phase=snapshot-encoded request={encoded_request} {token}width={width} height={height}")
                if failure == "duplicate-persist":
                    lines.append(lines[-1])
                if failure == "ambiguous-reason":
                    lines.append(lines[-1].replace("reason=after", "reason=series-0007"))
                if failure == "duplicate-encoded":
                    lines.insert(0, lines[0])
                if failure == "ambiguous-encoded":
                    lines.insert(0, "phase=snapshot-encoded request=17 commandBufferToken=71 textureToken=73 width=9 height=7")
                if failure == "encoded-after-persist":
                    lines.reverse()
                return lines
            with self.subTest(failure=failure):
                result, _ = run_sample_fixture(benchmark, log_only=True, terminal_snapshot=True,
                    control={"snapshot_receipts": receipts, "missing_png": failure == "missing-png"})
                self.assertFalse(result["passed"])
                self.assertEqual(result["evidence"]["snapshot_capture"]["status"], "missing-or-invalid")
                self.assertIn("terminal snapshot missing or invalid", result["failures"])

    def test_structured_runtime_observations_retain_truncation_and_count_bad_json_and_schema(self):
        composition = {"schemaVersion": 1, "frameIndex": 7, "commandBufferToken": "c", "surfaceIdentity": "s",
                       "gpuStatus": "completed", "rows": [{"kind": "ordinary", "layerID": 1}], "truncatedRows": 9}
        particle = {"schemaVersion": 1, "layerID": 1, "particlePath": "particles/test.json", "componentIndex": 0,
                    "stage": "truncated", "reason": "capacity", "observationScope": "first-fact-per-template"}
        composition_prefix = "MWX SCENE COMPOSITION OBSERVATION: "
        particle_prefix = "MWX SCENE PARTICLE COMPONENT OBSERVATION: "
        lines = [composition_prefix + json.dumps(composition), particle_prefix + json.dumps(particle)]
        for prefix in (composition_prefix, particle_prefix):
            lines += [prefix + '{"schemaVersion":1,', prefix + '[]', prefix + '{"schemaVersion":2}',
                      prefix + '{"schemaVersion":"1"}']
        result, _ = run_sample_fixture(benchmark, log_only=True, control={"log_lines": lines})
        for field, event in (("composition_observations", composition), ("particle_component_observations", particle)):
            observations = result["runtime"][field]
            self.assertEqual(observations["events"], [event])
            self.assertEqual(observations["parse_errors"], 4)
            self.assertEqual(observations["observed_count"], 1)
            self.assertIn("not-per-input-visible-contribution", observations["claim_boundary"])
            self.assertEqual(len(observations["source_line_numbers"]), 1)
            self.assertGreater(observations["source_line_numbers"][0], 0)
        next_frame = {**composition, "frameIndex": 8}
        raw = "\n".join(["unrelated", composition_prefix + json.dumps(composition),
                         composition_prefix + '{"schemaVersion":1,', composition_prefix + '[]',
                         composition_prefix + json.dumps(next_frame), composition_prefix + '{"schemaVersion":2}'])
        observations = structured_runtime_observations(raw, composition_prefix)
        self.assertEqual(observations["events"], [composition, next_frame])
        self.assertEqual(observations["source_line_numbers"], [2, 5])
        self.assertEqual((observations["observed_count"], observations["parse_errors"]), (2, 3))

    def test_unknown_process_tool_error_stops_owned_child_and_is_not_a_result_row(self):
        actions, waits = [], []
        with self.assertRaisesRegex(RuntimeError, "unknown process tool failure"):
            run_sample_fixture(benchmark, control={"raise_wait": True, "process_actions": actions,
                                                  "observed_wait_timeouts": waits})
        self.assertEqual(actions, ["terminate"])
        self.assertEqual(waits, [67, 5])


if __name__ == "__main__":
    unittest.main()

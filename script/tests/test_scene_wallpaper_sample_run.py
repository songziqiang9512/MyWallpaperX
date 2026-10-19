"""Behavior of the synchronous isolated sample-to-report boundary."""

from __future__ import annotations

import ast
import inspect
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

import scene_wallpaper_benchmark as benchmark
import scene_wallpaper_sample_run as sample_run
import web_benchmark_capture as capture
from scene_preview_visual_evidence import _write_rgb_png
from script.tests.scene_wallpaper_benchmark_test_support import effect_execution_log
from script.tests.scene_wallpaper_sample_fixture import run_sample_fixture, write_png


WINDOW_FIELDS = (
    "ready_non_black", "hover_non_black", "after_non_black", "flat_border_ratio",
    "motion", "hover_motion", "pointer_trajectory_non_black",
    "pointer_trajectory_motion", "puppet_interaction", "preview_visual",
)


def collect_window_evidence(root, *, hover=True, trajectory_count=7, sample=None):
    """Execute the actual caller's post-process block without launching a process."""
    function = ast.parse(inspect.getsource(sample_run.run_sample)).body[0]
    def assigns(node, name):
        return isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == name for target in node.targets
        )
    start = next(i for i, node in enumerate(function.body) if assigns(node, "initial_reason"))
    end = next(i for i, node in enumerate(function.body) if assigns(node, "runtime_evidence_path"))
    namespace = dict(vars(sample_run), result_dir=root, runtime_sample=root / "source",
                     hover_pointer=(0.5, 0.5) if hover else None,
                     pointer_trajectory=[(0.1, 0.2)] * trajectory_count or None,
                     sample=sample or {}, log_text="")
    exec(compile(ast.Module(body=function.body[start:end], type_ignores=[]),
                 sample_run.__file__, "exec"), namespace)
    return {field: namespace[field] for field in WINDOW_FIELDS}


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
        "pointer_trajectory_motion": sample_run.pointer_trajectory_motion_metrics(ready, trajectory),
        "puppet_interaction": None,
        "preview_visual": sample_run.collect_preview_visual_evidence(root / "source", after, root),
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

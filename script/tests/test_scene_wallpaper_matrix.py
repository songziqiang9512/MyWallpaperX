#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
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

import scene_wallpaper_pointer_evidence as pointer_evidence


class SceneWallpaperMatrixTests(unittest.TestCase):
    def test_load_matrix_accepts_version_one_samples(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(
                json.dumps({"schema_version": 1, "name": "fixture", "samples": [{"id": "1"}]}),
                encoding="utf-8",
            )
            self.assertEqual(benchmark.load_matrix(path)["samples"][0]["id"], "1")

    def test_load_matrix_accepts_digest_pinned_suite(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            root = Path(directory)
            base_path = root / "base.json"
            suite_path = root / "suite.json"
            base_path.write_text(
                json.dumps({
                    "schema_version": 1,
                    "name": "base",
                    "samples": [{"id": "1", "value": "base"}],
                }),
                encoding="utf-8",
            )
            suite_path.write_text(
                json.dumps({
                    "schema_version": 2,
                    "name": "suite",
                    "base_matrix": "base.json",
                    "base_matrix_sha256": hashlib.sha256(
                        base_path.read_bytes()
                    ).hexdigest(),
                    "sample_ids": ["1"],
                    "sample_overrides": {
                        "1": {"set": {"value": "suite"}}
                    },
                }),
                encoding="utf-8",
            )

            matrix = benchmark.load_matrix(suite_path)
            self.assertEqual(matrix["name"], "suite")
            self.assertEqual(matrix["samples"], [{"id": "1", "value": "suite"}])

    def test_load_matrix_rejects_unknown_schema(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(
                json.dumps({"schema_version": 99, "samples": []}),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                benchmark.load_matrix(path)

    def test_load_matrix_requires_click_for_subframe_click(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-matrix-") as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(
                json.dumps({
                    "schema_version": 1,
                    "name": "fixture",
                    "samples": [{
                        "id": "1",
                        "cursor_primary_click_subframe": True,
                    }],
                }),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(
                ValueError,
                "cursor_primary_click_subframe requires cursor_primary_click",
            ):
                benchmark.load_matrix(path)

    def test_select_matrix_samples_reuses_tracked_matrix_for_targeted_runs(self) -> None:
        matrix = {
            "schema_version": 1,
            "name": "fixture",
            "samples": [{"id": "1"}, {"id": "2"}, {"id": "3"}],
        }
        selected = benchmark.select_matrix_samples(matrix, ["3", "1"])
        self.assertEqual([sample["id"] for sample in selected["samples"]], ["1", "3"])
        self.assertEqual(len(matrix["samples"]), 3)
        with self.assertRaisesRegex(ValueError, "9"):
            benchmark.select_matrix_samples(matrix, ["9"])

    def test_hover_pointer_contract_accepts_only_finite_normalized_pairs(self) -> None:
        self.assertEqual(
            benchmark.hover_pointer_normalized(
                {"hover_pointer_normalized": [0.1, -0.25]}
            ),
            (0.1, -0.25),
        )
        self.assertIsNone(benchmark.hover_pointer_normalized({}))
        for value in ([0], [0, 0, 0], [2, 0], [0, float("nan")], ["0", 0]):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.hover_pointer_normalized(
                        {"hover_pointer_normalized": value}
                    )

    def test_hover_pointer_stationary_entry_accepts_only_boolean(self) -> None:
        self.assertFalse(benchmark.hover_pointer_stationary_entry({}))
        self.assertTrue(benchmark.hover_pointer_stationary_entry({
            "hover_pointer_stationary_entry": True
        }))
        for value in (0, 1, "true", None):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.hover_pointer_stationary_entry({
                        "hover_pointer_stationary_entry": value
                    })

    def test_hover_pointer_from_launch_accepts_only_boolean(self) -> None:
        self.assertFalse(benchmark.hover_pointer_from_launch({}))
        self.assertTrue(benchmark.hover_pointer_from_launch({
            "hover_pointer_from_launch": True
        }))
        for value in (0, 1, "true", None):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.hover_pointer_from_launch({
                        "hover_pointer_from_launch": value
                    })

    def test_hover_pointer_from_launch_needs_a_point_and_no_trajectory(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "matrix.json"
            sample = {
                "id": "1",
                "hover_pointer_normalized": [0.5, -0.25],
                "hover_pointer_from_launch": True,
            }
            path.write_text(
                json.dumps({
                    "schema_version": 1, "name": "fixture",
                    "samples": [dict(sample)],
                }),
                encoding="utf-8",
            )
            self.assertEqual(
                benchmark.load_matrix(path)["samples"][0]["id"],
                "1",
            )
            without_point = dict(sample)
            del without_point["hover_pointer_normalized"]
            path.write_text(
                json.dumps({
                    "schema_version": 1, "name": "fixture",
                    "samples": [without_point],
                }),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                benchmark.load_matrix(path)
            with_trajectory = dict(sample)
            with_trajectory["pointer_trajectory_normalized"] = [
                [-0.5, 0], [0.5, 0],
            ]
            path.write_text(
                json.dumps({
                    "schema_version": 1, "name": "fixture",
                    "samples": [with_trajectory],
                }),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                benchmark.load_matrix(path)

    def test_cursor_primary_click_accepts_only_boolean(self) -> None:
        self.assertFalse(benchmark.cursor_primary_click({}))
        self.assertTrue(benchmark.cursor_primary_click({
            "cursor_primary_click": True
        }))
        for value in (0, 1, "true", None, []):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.cursor_primary_click({
                        "cursor_primary_click": value
                    })

    def test_cursor_primary_click_subframe_accepts_only_boolean(self) -> None:
        self.assertFalse(benchmark.cursor_primary_click_subframe({}))
        self.assertTrue(benchmark.cursor_primary_click_subframe({
            "cursor_primary_click_subframe": True
        }))
        for value in (0, 1, "true", None, []):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.cursor_primary_click_subframe({
                        "cursor_primary_click_subframe": value
                    })

    def test_cursor_drag_to_normalized_accepts_only_finite_pairs(self) -> None:
        self.assertEqual(
            benchmark.cursor_drag_to_normalized({
                "cursor_drag_to_normalized": [0.25, -0.5]
            }),
            (0.25, -0.5),
        )
        self.assertIsNone(benchmark.cursor_drag_to_normalized({}))
        for value in ([0], [0, 2], [float("nan"), 0], "0,0", [True, 0]):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.cursor_drag_to_normalized({
                        "cursor_drag_to_normalized": value
                    })

    def test_pointer_trajectory_accepts_only_bounded_distinct_points(self) -> None:
        self.assertEqual(
            benchmark.pointer_trajectory_normalized({
                "pointer_trajectory_normalized": [
                    [-0.75, 0.5],
                    [0, 0],
                    [0.75, -0.5],
                ]
            }),
            [(-0.75, 0.5), (0.0, 0.0), (0.75, -0.5)],
        )
        self.assertIsNone(benchmark.pointer_trajectory_normalized({}))
        for value in (
            [[0, 0]],
            [[0, 0]] * 9,
            [[0, 0], [0, 0]],
            [[0, 0], [2, 0]],
            [[0, 0], [float("nan"), 0]],
            [[0, 0], [True, 0]],
            "0,0",
        ):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.pointer_trajectory_normalized({
                        "pointer_trajectory_normalized": value
                    })

    def test_pointer_trajectory_minimum_change_is_a_bounded_finite_ratio(self) -> None:
        self.assertIsNone(benchmark.pointer_trajectory_minimum_changed_ratio({}))
        self.assertEqual(
            benchmark.pointer_trajectory_minimum_changed_ratio({
                "minimum_pointer_trajectory_changed_ratio": 0.05
            }),
            0.05,
        )
        for value in (True, "0.1", -0.01, 1.01, float("nan"), float("inf")):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    benchmark.pointer_trajectory_minimum_changed_ratio({
                        "minimum_pointer_trajectory_changed_ratio": value
                    })

    def test_pointer_trajectory_motion_compares_ready_and_each_successive_point(self) -> None:
        ready = Path("ready.png")
        snapshots = [Path("point-00.png"), Path("point-01.png"), Path("point-02.png")]
        with mock.patch.object(
            pointer_evidence,
            "png_motion_metrics",
            side_effect=lambda before, after: (before.name, after.name),
        ):
            self.assertEqual(
                benchmark.pointer_trajectory_motion_metrics(ready, snapshots),
                [
                    ("ready.png", "point-00.png"),
                    ("point-00.png", "point-01.png"),
                    ("point-01.png", "point-02.png"),
                ],
            )
        self.assertIsNone(benchmark.pointer_trajectory_motion_metrics(ready, []))

    def test_pointer_trajectory_excludes_parallel_pointer_interactions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "matrix.json"
            base = {
                "schema_version": 1,
                "name": "fixture",
                "samples": [{
                    "id": "1",
                    "pointer_trajectory_normalized": [[-0.5, 0], [0.5, 0]],
                }],
            }
            path.write_text(json.dumps(base), encoding="utf-8")
            self.assertEqual(
                benchmark.load_matrix(path)["samples"][0]["id"],
                "1",
            )
            base["samples"][0]["hover_pointer_normalized"] = [0, 0]
            path.write_text(json.dumps(base), encoding="utf-8")
            with self.assertRaisesRegex(
                ValueError,
                "cannot be combined with hover_pointer_normalized",
            ):
                benchmark.load_matrix(path)

    def test_pointer_trajectory_minimum_change_requires_trajectory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(json.dumps({
                "schema_version": 1,
                "name": "fixture",
                "samples": [{
                    "id": "1",
                    "minimum_pointer_trajectory_changed_ratio": 0.05,
                }],
            }), encoding="utf-8")
            with self.assertRaisesRegex(
                ValueError,
                "requires pointer_trajectory_normalized",
            ):
                benchmark.load_matrix(path)

    def test_cursor_drag_requires_hover_and_owns_primary_edges(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "matrix.json"
            path.write_text(json.dumps({
                "schema_version": 1,
                "name": "fixture",
                "samples": [{
                    "id": "1",
                    "cursor_drag_to_normalized": [0.1, 0.2],
                }],
            }), encoding="utf-8")
            with self.assertRaisesRegex(
                ValueError,
                "cursor_drag_to_normalized requires hover_pointer_normalized",
            ):
                benchmark.load_matrix(path)

    def test_spring_return_preserves_window_gate_and_requires_explicit_source_owner(self):
        sample = {"cursor_drag_response": "spring-return", "minimum_hover_changed_ratio": 0.005}
        motion = {"before_to_drag": {"changed_ratio": .8},
                  "before_to_spring_after": {"changed_ratio": .9}}
        check = lambda: benchmark.cursor_interaction_output_failures(sample, motion, (.2, .2))
        self.assertTrue(check())
        sample["cursor_drag_return_space"] = "puppet-source"
        self.assertTrue(check())
        sample["puppet_interaction_layer_ids"] = [42]
        self.assertEqual(check(), [])
        motion["before_to_drag"]["changed_ratio"] = 0
        self.assertTrue(check())
        motion["before_to_drag"]["changed_ratio"] = .8
        motion["before_to_spring_after"] = None
        self.assertTrue(check())
        sample["cursor_drag_return_space"] = "invalid"
        self.assertTrue(check())


if __name__ == "__main__":
    unittest.main()

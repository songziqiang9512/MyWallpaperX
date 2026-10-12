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


class SceneWallpaperPreviewTests(unittest.TestCase):
    def test_project_preview_path_stays_inside_isolated_sample(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-path-") as directory:
            root = Path(directory)
            preview = root / "preview.png"
            visual._write_rgb_png(preview, 1, 1, [bytes((8, 16, 32))])
            (root / "project.json").write_text(
                json.dumps({"preview": "preview.png"}),
                encoding="utf-8",
            )
            self.assertEqual(visual.project_preview_path(root), (preview.resolve(), None))

            (root / "project.json").write_text(
                json.dumps({"preview": "../outside.png"}),
                encoding="utf-8",
            )
            resolved, error = visual.project_preview_path(root)
            self.assertIsNone(resolved)
            self.assertIn("escapes", error)

    def test_directional_visual_metrics_center_crop_capture(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-metrics-") as directory:
            root = Path(directory)
            preview = root / "preview.png"
            capture = root / "capture.png"
            blue = bytes((24, 72, 180))
            red = bytes((220, 24, 24))
            visual._write_rgb_png(preview, 2, 2, [blue * 2, blue * 2])
            visual._write_rgb_png(
                capture,
                4,
                2,
                [red + blue * 2 + red, red + blue * 2 + red],
            )

            metrics = visual.directional_visual_metrics(preview, capture)

            self.assertEqual(
                metrics["capture_center_crop"],
                {"x": 1, "y": 0, "width": 2, "height": 2},
            )
            self.assertEqual(metrics["spatial_color_similarity"], 1.0)
            self.assertEqual(metrics["spatial_luminance_similarity"], 1.0)
            self.assertEqual(metrics["preview_mean_rgb"], metrics["capture_mean_rgb"])

    def test_preview_visual_evidence_is_advisory_and_writes_montage(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-evidence-") as directory:
            root = Path(directory)
            sample = root / "sample"
            result = root / "result"
            sample.mkdir()
            result.mkdir()
            preview = sample / "preview.png"
            capture = result / "scene-after-window.png"
            pixels = [bytes((32, 64, 96)) * 2, bytes((96, 64, 32)) * 2]
            visual._write_rgb_png(preview, 2, 2, pixels)
            visual._write_rgb_png(capture, 2, 2, pixels)
            (sample / "project.json").write_text(
                json.dumps({"preview": "preview.png"}),
                encoding="utf-8",
            )

            evidence = visual.collect_preview_visual_evidence(sample, capture, result)

            self.assertEqual(evidence["status"], "available")
            self.assertTrue(evidence["advisory"])
            self.assertFalse(evidence["gating"])
            self.assertFalse(evidence["cross_sample_ranking"])
            self.assertIsNone(evidence["absolute_threshold"])
            self.assertEqual(evidence["metrics"]["spatial_color_similarity"], 1.0)
            self.assertTrue(Path(evidence["reference_png"]).is_file())
            self.assertTrue(Path(evidence["comparison_montage"]).is_file())
            self.assertTrue(
                benchmark.png_has_non_black_pixel(Path(evidence["comparison_montage"]))
            )

    def test_missing_preview_visual_evidence_never_becomes_a_gate(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-scene-preview-missing-") as directory:
            root = Path(directory)
            sample = root / "sample"
            result = root / "result"
            sample.mkdir()
            result.mkdir()
            capture = result / "scene-after-window.png"
            visual._write_rgb_png(capture, 1, 1, [bytes((12, 34, 56))])
            (sample / "project.json").write_text("{}", encoding="utf-8")

            evidence = visual.collect_preview_visual_evidence(sample, capture, result)

            self.assertEqual(evidence["status"], "unavailable")
            self.assertTrue(evidence["advisory"])
            self.assertFalse(evidence["gating"])
            self.assertIn("not declared", evidence["reason"])

    def test_preview_visual_summary_reports_coverage_without_threshold(self) -> None:
        results = [
            {
                "evidence": {
                    "preview_visual": {
                        "status": "available",
                        "metrics": {"spatial_color_similarity": 0.8},
                    }
                }
            },
            {"evidence": {"preview_visual": {"status": "unavailable"}}},
        ]

        self.assertEqual(
            visual.summarize_preview_visual_evidence(results),
            {
                "advisory": True,
                "gating": False,
                "comparison_scope": "same-sample-change-only",
                "cross_sample_ranking": False,
                "absolute_threshold": None,
                "available_count": 1,
                "unavailable_count": 1,
            },
        )


if __name__ == "__main__":
    unittest.main()

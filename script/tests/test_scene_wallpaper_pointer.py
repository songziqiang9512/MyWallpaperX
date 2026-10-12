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


class SceneWallpaperPointerTests(unittest.TestCase):
    def test_cursor_drag_output_changes_then_preserves_settled_position(self) -> None:
        motion = {
            "before_to_hover": {"changed_ratio": 0.08},
            "hover_to_after": {"changed_ratio": 0.0},
        }
        sample = {
            "minimum_hover_changed_ratio": 0.05,
            "maximum_drag_settle_changed_ratio": 0.001,
        }
        self.assertEqual(
            benchmark.cursor_interaction_output_failures(
                sample, motion, (0.6, 0.4)
            ),
            [],
        )
        self.assertIn(
            "drag interaction output evidence below minimum",
            benchmark.cursor_interaction_output_failures(
                sample,
                {**motion, "before_to_hover": {"changed_ratio": 0.01}},
                (0.6, 0.4),
            ),
        )
        self.assertIn(
            "drag interaction output did not preserve settled position",
            benchmark.cursor_interaction_output_failures(
                sample,
                {**motion, "hover_to_after": {"changed_ratio": 0.01}},
                (0.6, 0.4),
            ),
        )

    def test_cursor_ripple_persistence_accepts_expansion_and_decay_after_exit(
        self,
    ) -> None:
        def row(
            *, active: int, bounds: str, maximum: int, inside: bool,
            movement: float,
        ) -> str:
            return (
                "MWX DEBUG SCENE: phase=cursor-ripple-state layer=68 effect=0 "
                "descriptor=68%23effect%230 status=completed width=256 height=256 "
                f"output=ObjectIdentifier(0x1) activePixels={active} "
                f"bounds={bounds} max={maximum} sum={active * maximum} "
                "current=0.500000,0.500000 previous=0.400000,0.500000 "
                f"inside={'true' if inside else 'false'} previousInside=true "
                f"movement={movement:.6f} mask=false frameTime=0.016667"
            )

        log_text = "\n".join([
            row(active=600, bounds="90,120,125,136", maximum=190,
                inside=True, movement=0.04),
            row(active=900, bounds="86,116,129,140", maximum=184,
                inside=True, movement=0),
            row(active=1300, bounds="82,112,133,144", maximum=176,
                inside=False, movement=0),
            row(active=1900, bounds="76,106,139,150", maximum=160,
                inside=False, movement=0),
            row(active=2600, bounds="70,100,145,156", maximum=142,
                inside=False, movement=0),
        ])
        metrics = benchmark.cursor_ripple_persistence_metrics(log_text)
        self.assertTrue(metrics["accepted"])
        self.assertEqual(metrics["record_count"], 5)
        self.assertEqual(metrics["selected"]["post_exit_nonzero_frames"], 3)
        self.assertTrue(metrics["selected"]["expanded_width"])
        self.assertTrue(metrics["selected"]["expanded_height"])
        self.assertTrue(metrics["selected"]["peak_decayed"])
        self.assertEqual(
            benchmark.cursor_ripple_persistence_failures(metrics, True),
            [],
        )

    def test_cursor_ripple_persistence_rejects_missing_movement_injection(
        self,
    ) -> None:
        log_text = (
            "MWX DEBUG SCENE: phase=cursor-ripple-state layer=68 effect=0 "
            "descriptor=68%23effect%230 status=completed width=256 height=256 "
            "output=ObjectIdentifier(0x1) activePixels=12 bounds=1,1,3,4 "
            "max=20 sum=100 current=0.5,0.5 previous=0.5,0.5 "
            "inside=true previousInside=true movement=0.000000 mask=false"
        )
        metrics = benchmark.cursor_ripple_persistence_metrics(log_text)
        self.assertFalse(metrics["accepted"])
        self.assertEqual(
            benchmark.cursor_ripple_persistence_failures(metrics, True),
            ["cursor ripple movement injection evidence missing"],
        )

    def test_cursor_ripple_persistence_rejects_immediate_disappearance(self) -> None:
        injection = (
            "MWX DEBUG SCENE: phase=cursor-ripple-state layer=68 effect=0 "
            "descriptor=68%23effect%230 status=completed width=256 height=256 "
            "output=ObjectIdentifier(0x1) activePixels=600 bounds=90,120,125,136 "
            "max=190 sum=114000 current=0.5,0.5 previous=0.4,0.5 "
            "inside=true previousInside=true movement=0.040000 mask=false"
        )
        vanished = (
            "MWX DEBUG SCENE: phase=cursor-ripple-state layer=68 effect=0 "
            "descriptor=68%23effect%230 status=completed width=256 height=256 "
            "output=ObjectIdentifier(0x1) activePixels=0 bounds=256,256,-1,-1 "
            "max=0 sum=0 current=0.5,0.5 previous=0.5,0.5 "
            "inside=false previousInside=true movement=0.000000 mask=false"
        )
        metrics = benchmark.cursor_ripple_persistence_metrics(
            "\n".join([injection, vanished, vanished, vanished])
        )
        failures = benchmark.cursor_ripple_persistence_failures(metrics, True)
        self.assertIn(
            "cursor ripple disappeared before three post-exit GPU frames",
            failures,
        )
        self.assertIn(
            "cursor ripple extent did not expand after pointer exit",
            failures,
        )

    def test_cursor_ripple_visible_output_must_persist_expand_and_decay(self) -> None:
        def row(
            *, changed: int, bounds: str, maximum: int, inside: bool,
            movement: float,
        ) -> str:
            return (
                "MWX DEBUG SCENE: phase=cursor-ripple-visible layer=68 effect=0 "
                "descriptor=68%23effect%230 status=completed width=1168 height=1168 "
                f"changedPixels={changed} bounds={bounds} max={maximum} "
                f"sum={changed * maximum} current=0.500000,0.500000 "
                "previous=0.400000,0.500000 "
                f"inside={'true' if inside else 'false'} previousInside=true "
                f"movement={movement:.6f}"
            )

        log_text = "\n".join([
            row(changed=800, bounds="420,500,560,540", maximum=190,
                inside=True, movement=0.04),
            row(changed=1200, bounds="400,480,580,560", maximum=174,
                inside=False, movement=0),
            row(changed=1900, bounds="370,450,610,590", maximum=158,
                inside=False, movement=0),
            row(changed=2600, bounds="330,410,650,630", maximum=140,
                inside=False, movement=0),
            row(changed=1000, bounds="300,380,680,660", maximum=80,
                inside=False, movement=0),
        ])
        metrics = benchmark.cursor_ripple_visible_metrics(log_text)
        self.assertTrue(metrics["accepted"])
        self.assertEqual(metrics["selected"]["post_exit_nonzero_frames"], 4)
        self.assertTrue(metrics["selected"]["visible_sum_decayed"])
        self.assertEqual(benchmark.cursor_ripple_visible_failures(metrics, True), [])

        missing = benchmark.cursor_ripple_visible_metrics("")
        self.assertEqual(
            benchmark.cursor_ripple_visible_failures(missing, True),
            ["cursor ripple visible output evidence missing"],
        )


if __name__ == "__main__":
    unittest.main()

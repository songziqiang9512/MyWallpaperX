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


class SceneWallpaperUtilityTests(unittest.TestCase):
    def test_utility_runtime_fixture_preserves_distinct_dispositions(self) -> None:
        preview_log = """Scene preview texture load report
utilityLayerCount: 3
utilityCapturePlannedCount: 1
utilityDependencyEdgeCount: 0
utilityNamedConsumerCount: 0
utilityNamedTargetPlannedCount: 0
utilityNamedBindingPlannedCount: 0
utilityNamedTargetGapCount: 0
utility layer 187: capture kind=project
utility layer 96: unsupportedEffects kind=composition
utility layer 763: skippedHidden kind=composition
"""
        metrics = benchmark.utility_runtime_metrics(preview_log)
        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["candidates"], 3)
        self.assertEqual(metrics["capture_planned"], 1)
        self.assertEqual(metrics["named_consumers"], 0)
        self.assertEqual(metrics["named_target_planned"], 0)
        self.assertEqual(metrics["named_binding_planned"], 0)
        self.assertEqual(
            benchmark.utility_runtime_failures({
                "expected_utility_candidates": 3,
                "expected_utility_capture_planned": 1,
                "expected_utility_dependency_edges": 0,
                "expected_utility_named_consumers": 0,
                "expected_utility_named_target_planned": 0,
                "expected_utility_named_binding_planned": 0,
                "expected_utility_named_target_gaps": 0,
                "required_utility_dispositions": {
                    "187": "capture",
                    "96": "unsupportedEffects",
                    "763": "skippedHidden",
                },
            }, metrics),
            [],
        )
        self.assertEqual(
            benchmark.utility_runtime_failures({
                "expected_utility_capture_planned": 2,
                "required_utility_dispositions": {"96": "capture"},
            }, metrics),
            [
                "utility capture_planned mismatch",
                "utility layer 96 disposition should be capture",
            ],
        )

    def test_utility_capture_execution_preserves_failure_after_success(self) -> None:
        metrics = benchmark.utility_capture_execution_metrics(
            "phase=utility-capture layer=530 status=failed\n"
            "phase=utility-capture layer=530 status=succeeded\n"
            "phase=utility-capture layer=410 status=failed\n"
        )
        self.assertEqual(metrics["succeeded_layer_ids"], [530])
        self.assertEqual(metrics["failed_layer_ids"], [410, 530])
        assert_utility_capture_respects_dormant_graph_members(
            self, benchmark=benchmark,
            graph_execution_observation=graph_execution_observation,
        )

    def test_named_target_runtime_pins_completed_consumers(self) -> None:
        named_metrics = benchmark.named_target_capture_execution_metrics(
            "phase=named-target-capture layer=125 status=failed\n"
            "phase=named-target-capture layer=125 status=succeeded\n"
            "phase=named-target-capture layer=84 status=failed\n"
        )
        self.assertEqual(named_metrics["succeeded_layer_ids"], [125])
        self.assertEqual(named_metrics["failed_layer_ids"], [84, 125])

        binding_metrics = benchmark.named_target_binding_execution_metrics(
            "phase=named-target-binding layer=70 status=failed\n"
            "phase=named-target-binding layer=70 status=succeeded\n"
            "phase=named-target-binding layer=182 status=failed\n"
        )
        self.assertEqual(binding_metrics["succeeded_layer_ids"], [70])
        self.assertEqual(binding_metrics["failed_layer_ids"], [70, 182])
        self.assertEqual(
            benchmark.named_target_binding_failures(
                {"required_named_target_binding_succeeded_layer_ids": [70, 182]},
                2,
                binding_metrics,
            ),
            [
                "named target binding execution below planned count",
                "named target consumer 182 binding should succeed",
            ],
        )
        expected_passthrough = {
            benchmark.EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY: [{
                "layer_id": 182,
                "effect_index": 0,
                "descriptor_id": "182#effect#223",
                "reason": "external-primary-provider-source-unavailable",
            }]
        }
        self.assertEqual(
            benchmark.named_target_binding_failures(
                expected_passthrough,
                2,
                binding_metrics,
            ),
            [],
        )
        self.assertEqual(
            benchmark.named_target_binding_failures(
                expected_passthrough,
                3,
                binding_metrics,
            ),
            ["named target binding execution below planned count"],
        )
        self.assertEqual(
            benchmark.named_target_binding_failures(
                {
                    benchmark.EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY: [{
                        "layer_id": 245,
                        "effect_index": 0,
                        "descriptor_id": "245#effect#246",
                        "reason":
                            "external-primary-provider-source-unavailable",
                    }]
                },
                2,
                binding_metrics,
            ),
            ["named target binding unavailable set mismatch"],
        )
        # Conditional (script-owned visibility) bindings are excused by
        # member: planned consumers {70, 182} minus conditional {70} minus
        # unavailable {182} leaves nothing required; dropping the conditional
        # excuse (or the unavailable expectation) makes the remaining members
        # binding. The count fallback still applies without membership data.
        membership_utility = {
            "named_binding_conditional_layer_ids": [70],
            "named_binding_consumer_layer_ids": [70, 182],
        }
        self.assertEqual(
            benchmark.named_target_binding_failures(
                expected_passthrough,
                2,
                binding_metrics,
                utility_metrics=membership_utility,
            ),
            [],
        )
        self.assertEqual(
            benchmark.named_target_binding_failures(
                {},
                3,
                binding_metrics,
                conditional_count=2,
            ),
            [],
        )
        self.assertEqual(
            benchmark.named_target_binding_failures(
                {},
                3,
                binding_metrics,
                conditional_count=1,
            ),
            ["named target binding execution below planned count"],
        )

        missing = benchmark.particle_runtime_metrics("loaded: 20 / 24\n")
        self.assertEqual(
            benchmark.particle_runtime_failures({
                "expected_particle_candidates": 0,
                "minimum_particle_initial_live": 0,
                "expected_particle_refract_loaded": 0,
            }, missing),
            [
                "particle load evidence missing",
                "particle initial live evidence missing",
                "particle refract evidence missing",
            ],
        )

    def test_visible_graph_output_publication_execution_is_typed(self) -> None:
        assert_visible_publication_execution_metrics(
            self,
            benchmark=benchmark,
        )

    def test_named_graph_output_publication_has_one_terminal_owner(self) -> None:
        assert_named_graph_output_publication_has_one_terminal_owner(
            self,
            benchmark=benchmark,
            graph_execution_observation=graph_execution_observation,
            resolved_graph_exact_evidence=resolved_graph_exact_evidence,
        )


if __name__ == "__main__":
    unittest.main()

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


class SceneWallpaperGraphVisualFailureTests(unittest.TestCase):
    def test_resolved_graph_visual_failure_passthrough_is_terminal_not_program(
        self,
    ) -> None:
        reason = "material-finalizer-system-provider-purpose-mismatch"
        terminal_line = graph_execution_observation(
            frame=13,
            transaction="tx-visual-failure",
            trigger="next-frame+compositor-consume+gpu-completed",
            effect=0,
            descriptor_id="68%23effect%230",
            authored=1,
            material=0,
            copy=0,
            swap=0,
            compose=0,
            rejected=1,
            consumed=True,
            program=f"visual-failure-passthrough:{reason}",
        )
        terminal = benchmark.resolved_material_graph_observation_metrics(
            terminal_line
        )

        self.assertEqual(terminal["validation_failures"], [])
        self.assertEqual(terminal["terminal_success_count"], 1)
        self.assertEqual(terminal["visual_failure_passthrough_count"], 1)
        self.assertEqual(terminal["program_terminal_success_count"], 0)
        self.assertEqual(terminal["program_successful_transaction_count"], 0)
        self.assertEqual(
            terminal["visual_failure_passthroughs"],
            [{
                "layer_id": 68,
                "effect_index": 0,
                "descriptor_id": "68#effect#0",
                "reason": reason,
            }],
        )
        self.assertTrue(terminal["terminal_compositor_consume_observed"])

        invalid_lines = (
            terminal_line.replace(
                "authoredNodes=1 materialNodes=0",
                "authoredNodes=2 materialNodes=1",
            ),
            terminal_line.replace(
                f"program=visual-failure-passthrough:{reason}",
                "program=ordinary-program",
            ),
            terminal_line.replace(
                "effect=0 descriptor=68%23effect%230 ",
                "",
            ),
            terminal_line.replace(
                f"visual-failure-passthrough:{reason}",
                "visual-failure-passthrough:",
            ),
        )
        for invalid_line in invalid_lines:
            invalid = benchmark.resolved_material_graph_observation_metrics(
                invalid_line
            )
            self.assertEqual(invalid["terminal_success_count"], 0)
            self.assertIn(
                "resolved material graph observation rejected nodes are nonzero",
                invalid["validation_failures"],
            )

    def test_resolved_graph_effect_local_visual_failure_joins_exact_gate(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted "
            "dependency=none dependencyReferences=0",
        ])
        disposition, effect_execution, expectation = (
            resolved_graph_effect_local_failure_evidence()
        )
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            resolved_graph_visual_failure_log(),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        sample = {
            "expected_resolved_material_graph_succeeded_layer_ids": [68],
            benchmark.EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY: [expectation],
        }

        self.assertTrue(metrics["execution_succeeded"])
        self.assertEqual(metrics["succeeded_layer_ids"], [68])
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(
            metrics["exact_backend"]["effect_local_passthroughs"],
            [expectation],
        )
        self.assertEqual(
            metrics["graph_observations"][
                "program_successful_transaction_count"
            ],
            0,
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample=sample,
            ),
            [],
        )

        self.assertIn(
            "resolved material graph unexpected effect-local passthrough",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": [68]
                },
            ),
        )
        self.assertIn(
            "resolved material graph effect-local passthrough evidence mismatch",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": [68],
                    benchmark.EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY: [{
                        **expectation,
                        "reason": "material-finalizer-system-provider-unavailable",
                    }],
                },
            ),
        )

        conflicting = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            resolved_graph_visual_failure_log(
                local_fallback_reason=(
                    "frame-target-plan-unsupported-target-descriptor"
                ),
            ),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertIn(
            "resolved material graph fallback scopes conflict",
            benchmark.resolved_material_graph_execution_failures(
                conflicting,
                require_evidence=True,
                sample=sample,
            ),
        )

    def test_resolved_graph_effect_local_failure_keeps_mixed_program_gate(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted "
            "dependency=none dependencyReferences=0",
        ])
        disposition, effect_execution, expectation = (
            resolved_graph_effect_local_failure_evidence(
                include_successful_program=True,
                fallback_effect_index=1,
            )
        )
        sample = {
            "expected_resolved_material_graph_succeeded_layer_ids": [68],
            benchmark.EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY: [expectation],
        }
        complete = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            resolved_graph_visual_failure_log(
                fallback_effect_index=1,
                include_program=True,
            ),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )

        self.assertTrue(complete["execution_succeeded"])
        self.assertEqual(
            complete["exact_backend"]["program_required_layer_ids"],
            [68],
        )
        self.assertEqual(
            complete["exact_backend"]["mixed_program_required_subjects"],
            [(68, 0, "68#effect#0")],
        )
        self.assertEqual(
            complete["graph_observations"][
                "program_successful_transaction_count"
            ],
            2,
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                complete,
                require_evidence=True,
                sample=sample,
            ),
            [],
        )

        missing_program_next_frame = (
            benchmark.resolved_material_graph_execution_metrics(
                preview_text,
                resolved_graph_visual_failure_log(
                    fallback_effect_index=1,
                    include_program=True,
                    include_program_next_frame=False,
                ),
                effect_execution=effect_execution,
                static_disposition=disposition,
            )
        )
        self.assertFalse(missing_program_next_frame["execution_succeeded"])
        self.assertIn(
            "resolved material graph Program transaction count below two",
            benchmark.resolved_material_graph_execution_failures(
                missing_program_next_frame,
                require_evidence=True,
                sample=sample,
            ),
        )

        missing_fallback_next_frame = (
            benchmark.resolved_material_graph_execution_metrics(
                preview_text,
                resolved_graph_visual_failure_log(
                    fallback_effect_index=1,
                    include_program=True,
                    include_visual_next_frame=False,
                ),
                effect_execution=effect_execution,
                static_disposition=disposition,
            )
        )
        self.assertFalse(missing_fallback_next_frame["execution_succeeded"])
        self.assertIn(
            "resolved material graph effect-local passthrough exact join failed",
            missing_fallback_next_frame["validation_failures"],
        )

        wrong_program_subject = (
            benchmark.resolved_material_graph_execution_metrics(
                preview_text,
                resolved_graph_visual_failure_log(
                    fallback_effect_index=1,
                    include_program=True,
                ).replace(
                    "effect=0 descriptor=68%23effect%230 ",
                    "effect=2 descriptor=68%23effect%232 ",
                ),
                effect_execution=effect_execution,
                static_disposition=disposition,
            )
        )
        self.assertFalse(wrong_program_subject["execution_succeeded"])
        self.assertIn(
            "resolved material graph mixed Program exact subject join failed",
            wrong_program_subject["validation_failures"],
        )

        unjoined = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            resolved_graph_visual_failure_log(
                reason="material-finalizer-system-provider-unavailable",
                fallback_effect_index=1,
                include_program=True,
            ),
            effect_execution=effect_execution,
            static_disposition=disposition,
        )
        self.assertFalse(unjoined["execution_succeeded"])
        self.assertIn(
            "resolved material graph effect-local passthrough exact join failed",
            unjoined["validation_failures"],
        )


if __name__ == "__main__":
    unittest.main()

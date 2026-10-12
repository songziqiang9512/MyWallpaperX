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


class SceneWallpaperGraphTerminalsTests(unittest.TestCase):
    def test_resolved_material_graph_execution_gate_accepts_conserved_evidence(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=2 accepted=1 "
            "rejected=1 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted "
            "dependency=none dependencyReferences=0\n"
            "resolved material scene background: "
            "schema=scene-background-provider-v1 layer=68 effect=0 "
            "node=0 slot=1 bindings=3 mode=same-frame-main-target\n"
        )
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=0 failures=0 deferred=1 pending=1 "
            "gpuEncoded=0 localFallbacks=0",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1 localFallbacks=0",
            graph_execution_observation(
                frame=10,
                transaction="tx-10",
                trigger="first-frame+first-success+gpu-completed",
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1512x982/rgbaBackbuffer:2",
            ),
            graph_execution_observation(
                frame=11,
                transaction="tx-11",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1512x982/rgbaBackbuffer:2",
            ),
        ])

        disposition, exact_execution = resolved_graph_exact_evidence([68])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertTrue(metrics["has_evidence"])
        self.assertTrue(metrics["execution_succeeded"])
        self.assertEqual(metrics["validation_failures"], [])

        self.assertEqual(metrics["capability"], {
            "has_evidence": True,
            "schema_version": "layer-graph-capability-v1",
            "observation_count": 1,
            "candidate_count": 2,
            "accepted_count": 1,
            "rejected_count": 1,
            "variant_limit": 8,
            "accepted_layer_ids": [68],
            "accepted_layer_observation_count": 1,
            "duplicate_accepted_layer_ids": [],
            "malformed_route_observation_count": 0,
        })
        self.assertEqual(metrics["scene_background"], {
            "has_evidence": True,
            "schema_version": "scene-background-provider-v1",
            "layer_ids": [68],
            "duplicate_layer_ids": [],
            "unaccepted_layer_ids": [],
            "malformed_observation_count": 0,
            "observations": [{
                "layer_id": 68,
                "effect_index": 0,
                "node_index": 0,
                "slot": 1,
                "binding_count": 3,
            }],
        })
        self.assertEqual(metrics["executor"]["claimed_count"], 2)
        self.assertEqual(metrics["executor"]["encoded_count"], 1)
        self.assertEqual(metrics["executor"]["gpu_encoded_count"], 1)
        self.assertEqual(
            metrics["graph_observations"]["successful_transactions"],
            ["tx-10", "tx-11"],
        )
        self.assertEqual(
            metrics["graph_observations"]["target_descriptor_counts"],
            ["1512x982/rgbaBackbuffer:2"],
        )
        first_terminal = metrics["graph_observations"][
            "terminal_success_observations"
        ][0]
        self.assertEqual(first_terminal["layer_id"], 68)
        self.assertEqual(first_terminal["final_output"], "output-tx-10")
        self.assertEqual(first_terminal["final_physical"], "physical-tx-10")
        self.assertEqual(
            first_terminal["final_publication"],
            "publication-tx-10",
        )
        self.assertEqual(first_terminal["publication_generation"], 10)
        self.assertTrue(
            metrics["graph_observations"]["next_frame_observed"]
        )
        self.assertEqual(
            metrics["graph_observations"]["next_frame_layer_ids"],
            [68],
        )
        self.assertTrue(
            metrics["graph_observations"][
                "terminal_compositor_consume_observed"
            ]
        )
        self.assertEqual(metrics["layer_routes"], {
            "has_evidence": True,
            "schema_version": "layer-graph-route-v1",
            "accepted_layer_ids": [68],
            "observed_layer_ids": [68],
            "compositor_consumed_layer_ids": [68],
            "named_published_layer_ids": [],
            "visible_graph_output_published_layer_ids": [],
            "named_graph_output_published_layer_ids": [],
            "named_compositor_overlap_layer_ids": [],
            "next_frame_layer_ids": [68],
            "missing_layer_ids": [],
            "missing_gpu_completed_layer_ids": [],
            "missing_compositor_consumed_layer_ids": [],
            "missing_next_frame_layer_ids": [],
            "missing_exact_backend_layer_ids": [],
            "unexpected_layer_ids": [],
            "unexpected_gpu_completed_layer_ids": [],
            "unexpected_compositor_consumed_layer_ids": [],
            "unexpected_next_frame_layer_ids": [],
            "unexpected_exact_backend_layer_ids": [],
        })
        self.assertEqual(metrics["succeeded_layer_ids"], [68])
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": [68],
                    "expected_resolved_material_graph_target_descriptor_counts": [
                        "1512x982/rgbaBackbuffer:2"
                    ],
                },
            ),
            [],
        )
        self.assertIn(
            "resolved material graph succeeded layer IDs mismatch",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": []
                },
            ),
        )

    def test_resolved_material_graph_gate_accepts_named_provider_terminal(
        self,
    ) -> None:
        assert_named_provider_terminal(
            self,
            benchmark=benchmark,
            graph_execution_observation=graph_execution_observation,
            resolved_graph_exact_evidence=resolved_graph_exact_evidence,
        )

    def test_resolved_material_graph_gate_accepts_visible_graph_output_provider(
        self,
    ) -> None:
        assert_visible_provider_requires_compositor_consumption(
            self,
            benchmark=benchmark,
            graph_execution_observation=graph_execution_observation,
            resolved_graph_exact_evidence=resolved_graph_exact_evidence,
        )

    def test_resolved_material_graph_execution_gate_requires_terminal_evidence(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted\n"
        )
        audit = (
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1"
        )
        incomplete = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([
                audit,
                graph_execution_observation(
                    frame=10,
                    transaction="tx-10",
                    trigger="first-frame+gpu-completed",
                ),
                graph_execution_observation(
                    frame=10,
                    transaction="tx-10",
                    trigger="gpu-completed",
                ),
            ]),
        )
        incomplete_failures = (
            benchmark.resolved_material_graph_execution_failures(
                incomplete,
                require_evidence=True,
            )
        )
        self.assertIn(
            "resolved material graph successful transaction count below two",
            incomplete_failures,
        )
        self.assertIn(
            "resolved material graph accepted layer next-frame evidence missing",
            incomplete_failures,
        )
        self.assertIn(
            "resolved material graph accepted layer compositor consumption missing",
            incomplete_failures,
        )

        invalid_terminal = benchmark.resolved_material_graph_observation_metrics(
            graph_execution_observation(
                frame=12,
                transaction="tx-invalid",
                trigger="next-frame+gpu-completed",
                authored=3,
                material=1,
                copy=1,
                compose=2,
                rejected=1,
                consumed=True,
                publish=False,
            )
        )
        for failure in (
            "resolved material graph observation rejected nodes are nonzero",
            "resolved material graph observation node conservation failed",
            "resolved material graph observation compose count invalid",
            "resolved material graph observation final publication missing",
            "resolved material graph observation publication generation invalid",
        ):
            self.assertIn(failure, invalid_terminal["validation_failures"])
        self.assertEqual(invalid_terminal["successful_transaction_count"], 0)

        activation_passthrough = (
            benchmark.resolved_material_graph_observation_metrics(
                graph_execution_observation(
                    frame=13,
                    transaction="tx-activation",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    authored=1,
                    material=0,
                    copy=0,
                    swap=0,
                    compose=0,
                    rejected=1,
                    consumed=True,
                    program=(
                        "activation-passthrough:"
                        "effect-activation-visibility-disabled"
                    ),
                )
            )
        )
        self.assertEqual(activation_passthrough["validation_failures"], [])
        self.assertEqual(
            activation_passthrough["activation_passthrough_count"],
            1,
        )
        self.assertEqual(
            activation_passthrough["activation_passthrough_reason_codes"],
            ["effect-activation-visibility-disabled"],
        )
        self.assertEqual(
            activation_passthrough["program_terminal_success_count"],
            0,
        )
        self.assertTrue(
            activation_passthrough["terminal_success_observations"][0][
                "activation_passthrough"
            ]
        )

        disposition, exact_execution = resolved_graph_exact_evidence([68])
        activation_only = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([
                "resolved material runtime audit: "
                "schema=scene-graph-executor-v1 claimed=2 encoded=2 "
                "failures=0 deferred=0 pending=0 gpuEncoded=2",
                graph_execution_observation(
                    frame=13,
                    transaction="tx-activation-13",
                    trigger=(
                        "first-frame+compositor-consume+gpu-completed"
                    ),
                    authored=1,
                    material=0,
                    copy=0,
                    swap=0,
                    compose=0,
                    rejected=1,
                    consumed=True,
                    program=(
                        "activation-passthrough:"
                        "effect-activation-scalar-below-minimum"
                    ),
                ),
                graph_execution_observation(
                    frame=14,
                    transaction="tx-activation-14",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    authored=1,
                    material=0,
                    copy=0,
                    swap=0,
                    compose=0,
                    rejected=1,
                    consumed=True,
                    program=(
                        "activation-passthrough:"
                        "effect-activation-scalar-below-minimum"
                    ),
                ),
            ]),
            effect_execution=exact_execution,
            static_disposition=disposition,
        )
        self.assertFalse(activation_only["execution_succeeded"])
        self.assertEqual(activation_only["succeeded_layer_ids"], [])
        self.assertIn(
            "resolved material graph Program transaction count below two",
            benchmark.resolved_material_graph_execution_failures(
                activation_only,
                require_evidence=True,
            ),
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                activation_only,
                sample={
                    "required_activation_passthrough_reason_codes": [
                        "effect-activation-scalar-below-minimum"
                    ],
                    "minimum_activation_passthrough_count": 2,
                },
            ),
            [],
        )

        malformed_layer = benchmark.resolved_material_graph_observation_metrics(
            graph_execution_observation(
                frame=12,
                transaction="tx-bad-layer",
                trigger="next-frame+gpu-completed",
                consumed=True,
            ).replace("layer=68", "layer=bad")
        )
        self.assertEqual(malformed_layer["terminal_success_count"], 0)
        self.assertIn(
            "resolved material graph observation evidence malformed",
            malformed_layer["validation_failures"],
        )

        bad_axis = benchmark.resolved_material_graph_observation_metrics(
            "\n".join([
                graph_execution_observation(
                    frame=10,
                    transaction="tx-10",
                    trigger="first-frame+gpu-completed",
                ),
                graph_execution_observation(
                    frame=11,
                    transaction="tx-11",
                    trigger="next-frame+gpu-completed",
                    consumed=True,
                ),
                "MWX DEBUG SCENE: schema=1 axis=graph-execution "
                "diagnostic=transaction-signature-conflict",
                graph_execution_observation(
                    frame=12,
                    transaction="tx-failed",
                    trigger="first-failure",
                    outcome="failed",
                    gpu_completion="-",
                ),
                graph_execution_observation(
                    frame=13,
                    transaction="tx-gpu-failed",
                    trigger="gpu-failed",
                    outcome="failed",
                    gpu_completion="failed",
                ),
            ])
        )
        self.assertEqual(bad_axis["diagnostic_count"], 1)
        self.assertEqual(bad_axis["failed_outcome_count"], 2)
        self.assertEqual(bad_axis["gpu_failed_count"], 1)
        for failure in (
            "resolved material graph observation diagnostic reported",
            "resolved material graph observation failed outcome reported",
            "resolved material graph observation GPU failure reported",
        ):
            self.assertIn(failure, bad_axis["validation_failures"])

    def test_resolved_material_graph_zero_contract_is_explicit(self) -> None:
        metrics = benchmark.resolved_material_graph_execution_metrics(
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
            "gpuEncoded=0",
        )

        self.assertTrue(metrics["has_evidence"])
        self.assertTrue(metrics["zero_contract_succeeded"])
        self.assertTrue(metrics["contract_succeeded"])
        self.assertFalse(metrics["execution_succeeded"])
        self.assertEqual(metrics["succeeded_layer_ids"], [])
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": []
                },
            ),
            [],
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample={
                    "expected_resolved_material_graph_succeeded_layer_ids": []
                },
            ),
            [],
        )

    def test_resolved_material_graph_zero_contract_rejects_unauthorized_activity(
        self,
    ) -> None:
        disposition, exact_execution = resolved_graph_exact_evidence([68])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8",
            "\n".join([
                "resolved material runtime audit: schema=scene-graph-executor-v1 "
                "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
                "gpuEncoded=0",
                graph_execution_observation(
                    frame=10,
                    layer=68,
                    transaction="tx-unauthorized",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                ),
            ]),
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertFalse(metrics["zero_contract_succeeded"])
        self.assertEqual(
            metrics["exact_backend"]["unexpected_layer_ids"],
            [68],
        )
        failures = benchmark.resolved_material_graph_execution_failures(metrics)
        self.assertIn(
            "resolved material graph zero contract observed graph execution",
            failures,
        )
        self.assertIn(
            "resolved material graph non-accepted layer exact backend observed",
            failures,
        )


if __name__ == "__main__":
    unittest.main()

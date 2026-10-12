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


class SceneWallpaperGraphRoutesTests(unittest.TestCase):
    def test_resolved_material_graph_execution_gate_accepts_dependency_routes(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=4 accepted=4 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted "
            "dependency=none dependencyReferences=0",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=70 status=accepted "
            "dependency=graph-internal dependencyReferences=1",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=72 status=accepted "
            "dependency=external-primary dependencyReferences=1",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=74 status=accepted "
            "dependency=external-aggregate dependencyReferences=3",
        ])

        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "",
        )

        self.assertEqual(
            metrics["capability"]["accepted_layer_ids"],
            [68, 70, 72, 74],
        )
        self.assertEqual(
            metrics["capability"]["malformed_route_observation_count"],
            0,
        )
        self.assertNotIn(
            "resolved material graph accepted layer evidence malformed",
            metrics["validation_failures"],
        )

        malformed_dependencies = [
            "dependency=none dependencyReferences=1",
            "dependency=external-primary dependencyReferences=0",
            "dependency=external-aggregate dependencyReferences=0",
            "dependency=external-unknown dependencyReferences=1",
        ]
        for malformed_dependency in malformed_dependencies:
            with self.subTest(malformed_dependency=malformed_dependency):
                malformed = benchmark.resolved_material_graph_execution_metrics(
                    "\n".join([
                        "resolved material execution capabilities: "
                        "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
                        "rejected=0 variantLimit=8",
                        "resolved material execution capability: "
                        "schema=layer-graph-route-v1 layer=72 status=accepted "
                        + malformed_dependency,
                    ]),
                    "",
                )
                self.assertEqual(
                    malformed["capability"][
                        "malformed_route_observation_count"
                    ],
                    1,
                )
                self.assertIn(
                    "resolved material graph accepted layer evidence malformed",
                    malformed["validation_failures"],
                )

        malformed_background = benchmark.resolved_material_graph_execution_metrics(
            preview_text
            + "\nresolved material scene background: "
            + "schema=scene-background-provider-v1 layer=70 mode=unknown",
            "",
        )
        self.assertIn(
            "resolved material scene background evidence malformed",
            malformed_background["validation_failures"],
        )

        unaccepted_background = benchmark.resolved_material_graph_execution_metrics(
            preview_text
            + "\nresolved material scene background: "
            + "schema=scene-background-provider-v1 layer=99 effect=0 "
            + "node=0 slot=1 mode=same-frame-main-target",
            "",
        )
        self.assertIn(
            "resolved material scene background layer not accepted",
            unaccepted_background["validation_failures"],
        )

    def test_resolved_material_graph_execution_gate_rejects_false_success(
        self,
    ) -> None:
        no_admission = benchmark.resolved_material_graph_execution_metrics(
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=0 "
            "rejected=1 variantLimit=8\n",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=0 "
            "gpuEncoded=1\n",
        )
        self.assertFalse(no_admission["execution_succeeded"])
        no_admission_failures = (
            benchmark.resolved_material_graph_execution_failures(
                no_admission,
                require_evidence=True,
            )
        )
        self.assertIn(
            "resolved material graph zero contract executor counters nonzero",
            no_admission_failures,
        )
        self.assertIn(
            "resolved material graph zero contract executor counters nonzero",
            benchmark.resolved_material_graph_execution_failures(no_admission),
        )
        self.assertIn(
            "resolved material graph execution has no admitted capability",
            no_admission_failures,
        )

        executor_failure = benchmark.resolved_material_graph_execution_metrics(
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=1 deferred=0 pending=0 "
            "gpuEncoded=1\n",
        )
        self.assertFalse(executor_failure["execution_succeeded"])
        self.assertIn(
            "resolved material graph executor reported failures",
            benchmark.resolved_material_graph_execution_failures(
                executor_failure,
                require_evidence=True,
            ),
        )

        broken_conservation = (
            benchmark.resolved_material_graph_execution_metrics(
                "resolved material execution capabilities: "
                "schema=layer-graph-capability-v1 candidates=2 accepted=1 "
                "rejected=0 variantLimit=8\n",
                "resolved material runtime audit: "
                "schema=scene-graph-executor-v1 claimed=1 encoded=2 "
                "failures=0 deferred=0 pending=0 gpuEncoded=1\n",
            )
        )
        self.assertIn(
            "resolved material graph capability count conservation failed",
            broken_conservation["validation_failures"],
        )
        self.assertIn(
            "resolved material graph executor claim conservation failed",
            broken_conservation["validation_failures"],
        )
        self.assertIn(
            "resolved material graph executor GPU encode conservation failed",
            broken_conservation["validation_failures"],
        )

        missing = benchmark.resolved_material_graph_execution_metrics("", "")
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(
                missing,
                require_evidence=True,
            ),
            ["resolved material graph capability evidence missing"],
        )
        self.assertEqual(
            benchmark.resolved_material_graph_execution_failures(missing),
            [],
        )

        orphan_executor = benchmark.resolved_material_graph_execution_metrics(
            "",
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
            "gpuEncoded=0",
        )
        self.assertIn(
            "resolved material graph activity has no capability evidence",
            benchmark.resolved_material_graph_execution_failures(orphan_executor),
        )

    def test_resolved_material_graph_execution_gate_conserves_layer_routes(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=3 accepted=2 "
            "rejected=1 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
            "gpuEncoded=2",
            graph_execution_observation(
                frame=10,
                layer=68,
                transaction="tx-68",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                layer=76,
                transaction="tx-76",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
        ])

        disposition, exact_execution = resolved_graph_exact_evidence([68, 76])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertTrue(metrics["execution_succeeded"])
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(
            metrics["graph_observations"][
                "successful_gpu_completed_layer_ids"
            ],
            [68, 76],
        )
        self.assertEqual(metrics["layer_routes"]["accepted_layer_ids"], [68, 76])
        self.assertEqual(metrics["layer_routes"]["observed_layer_ids"], [68, 76])
        self.assertEqual(
            metrics["layer_routes"]["next_frame_layer_ids"],
            [68, 76],
        )
        self.assertEqual(metrics["layer_routes"]["missing_layer_ids"], [])

    def test_resolved_material_graph_execution_gate_rejects_bad_layer_routes(
        self,
    ) -> None:
        metrics = benchmark.resolved_material_graph_execution_metrics(
            "\n".join([
                "resolved material execution capabilities: "
                "schema=layer-graph-capability-v1 candidates=2 accepted=2 "
                "rejected=0 variantLimit=8",
                "resolved material execution capability: "
                "schema=layer-graph-route-v1 layer=68 status=accepted",
                "resolved material execution capability: "
                "schema=layer-graph-route-v1 layer=68 status=accepted",
                "resolved material execution capability: "
                "schema=layer-graph-route-v1 layer=bad status=accepted",
            ]),
            "",
        )

        self.assertFalse(metrics["layer_routes"]["has_evidence"])
        self.assertEqual(metrics["capability"]["accepted_layer_ids"], [68])
        self.assertEqual(
            metrics["capability"]["duplicate_accepted_layer_ids"],
            [68],
        )
        self.assertEqual(
            metrics["capability"]["malformed_route_observation_count"],
            1,
        )
        for failure in (
            "resolved material graph accepted layer evidence malformed",
            "resolved material graph accepted layer evidence duplicated",
            "resolved material graph accepted layer count conservation failed",
        ):
            self.assertIn(failure, metrics["validation_failures"])
            self.assertIn(
                failure,
                benchmark.resolved_material_graph_execution_failures(metrics),
            )

    def test_resolved_material_graph_execution_gate_rejects_per_layer_gaps(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=2 accepted=2 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
            "gpuEncoded=2",
            graph_execution_observation(
                frame=10,
                layer=68,
                transaction="tx-68",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                layer=76,
                transaction="tx-76",
                trigger="next-frame+first-success+gpu-completed",
            ),
        ])

        disposition, exact_execution = resolved_graph_exact_evidence([68, 76])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertFalse(metrics["execution_succeeded"])
        self.assertEqual(metrics["layer_routes"]["observed_layer_ids"], [68, 76])
        self.assertEqual(metrics["layer_routes"]["missing_layer_ids"], [76])
        self.assertEqual(
            metrics["layer_routes"][
                "missing_compositor_consumed_layer_ids"
            ],
            [76],
        )
        self.assertIn(
            "resolved material graph accepted layer compositor consumption missing",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
            ),
        )

        missing_gpu_metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([
                "resolved material runtime audit: schema=scene-graph-executor-v1 "
                "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
                "gpuEncoded=2",
                graph_execution_observation(
                    frame=10,
                    layer=68,
                    transaction="tx-68-a",
                    trigger="first-frame+first-success+compositor-consume+gpu-completed",
                    consumed=True,
                ),
                graph_execution_observation(
                    frame=11,
                    layer=68,
                    transaction="tx-68-b",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                ),
            ]),
            effect_execution=exact_execution,
            static_disposition=disposition,
        )
        self.assertEqual(
            missing_gpu_metrics["layer_routes"][
                "missing_gpu_completed_layer_ids"
            ],
            [76],
        )
        self.assertEqual(
            missing_gpu_metrics["layer_routes"]["missing_layer_ids"],
            [76],
        )
        self.assertIn(
            "resolved material graph accepted layer GPU completion missing",
            missing_gpu_metrics["validation_failures"],
        )

    def test_resolved_material_graph_accepts_typed_dormant_dynamic_layer(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=30 status=accepted",
        ])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([
                "MWX dynamic layer visibility: "
                "schema=dynamic-layer-visibility-v1 frame=1 generation=1 "
                "layer=30 source=userProperty value=false effective=false",
                "resolved material runtime audit: schema=scene-graph-executor-v1 "
                "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
                "gpuEncoded=0",
            ]),
        )

        self.assertTrue(metrics["dormant_contract_succeeded"])
        self.assertTrue(metrics["contract_succeeded"])
        self.assertEqual(
            metrics["dynamic_visibility"]["dormant_accepted_layer_ids"],
            [30],
        )
        self.assertEqual(
            metrics["dynamic_visibility"]["execution_expected_layer_ids"],
            [],
        )
        self.assertEqual(metrics["layer_routes"]["missing_layer_ids"], [])
        self.assertEqual(metrics["validation_failures"], [])

        malformed = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            "\n".join([
                "MWX dynamic layer visibility: "
                "schema=dynamic-layer-visibility-v1 frame=1 generation=1 "
                "layer=30 source=unknown value=false effective=false",
                "resolved material runtime audit: schema=scene-graph-executor-v1 "
                "claimed=0 encoded=0 failures=0 deferred=0 pending=0 "
                "gpuEncoded=0",
            ]),
        )
        self.assertFalse(malformed["contract_succeeded"])
        self.assertIn(
            "resolved material graph dynamic visibility evidence malformed",
            malformed["validation_failures"],
        )

    def test_resolved_material_graph_next_frame_is_conserved_per_layer(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=2 accepted=2 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=76 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
            "gpuEncoded=2",
            graph_execution_observation(
                frame=10,
                layer=68,
                transaction="tx-68",
                trigger="first-frame+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                layer=76,
                transaction="tx-76",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
            ),
        ])
        disposition, exact_execution = resolved_graph_exact_evidence([68, 76])

        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertTrue(metrics["graph_observations"]["next_frame_observed"])
        self.assertEqual(
            metrics["graph_observations"]["next_frame_layer_ids"],
            [76],
        )
        self.assertEqual(
            metrics["layer_routes"]["missing_next_frame_layer_ids"],
            [68],
        )
        self.assertEqual(metrics["succeeded_layer_ids"], [76])
        self.assertFalse(metrics["execution_succeeded"])

    def test_resolved_material_graph_exact_backend_must_own_every_subject(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
        ])
        graph_log = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1",
            graph_execution_observation(
                frame=10,
                transaction="tx-10",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                transaction="tx-11",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
            ),
        ])
        cases = (
            (
                {68: "non-unified-backend"},
                {},
                set(),
                "resolved material graph accepted layer exact backend mismatch",
            ),
            (
                {},
                {68: "failed"},
                set(),
                "resolved material graph accepted layer exact execution failed",
            ),
            (
                {},
                {},
                {68},
                "resolved material graph accepted layer exact backend evidence missing",
            ),
        )
        for backends, outcomes, omitted, expected_failure in cases:
            with self.subTest(expected_failure=expected_failure):
                disposition, exact_execution = resolved_graph_exact_evidence(
                    [68],
                    backends=backends,
                    outcomes=outcomes,
                    omitted_layer_ids=omitted,
                )
                metrics = benchmark.resolved_material_graph_execution_metrics(
                    preview_text,
                    graph_log,
                    effect_execution=exact_execution,
                    static_disposition=disposition,
                )
                self.assertEqual(metrics["succeeded_layer_ids"], [])
                self.assertIn(expected_failure, metrics["validation_failures"])
                self.assertIn(
                    "resolved material graph succeeded layer IDs mismatch",
                    benchmark.resolved_material_graph_execution_failures(
                        metrics,
                        sample={
                            "expected_resolved_material_graph_succeeded_layer_ids": [68]
                        },
                    ),
                )

    def test_resolved_material_graph_execution_gate_rejects_unaccepted_layers(
        self,
    ) -> None:
        preview_text = "\n".join([
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8",
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=68 status=accepted",
        ])
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=2 encoded=2 failures=0 deferred=0 pending=2 "
            "gpuEncoded=2",
            graph_execution_observation(
                frame=10,
                layer=68,
                transaction="tx-68",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
            graph_execution_observation(
                frame=11,
                layer=76,
                transaction="tx-76",
                trigger="next-frame+first-success+compositor-consume+gpu-completed",
                consumed=True,
            ),
        ])

        disposition, exact_execution = resolved_graph_exact_evidence([68])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )

        self.assertFalse(metrics["execution_succeeded"])
        self.assertEqual(metrics["layer_routes"]["missing_layer_ids"], [])
        self.assertEqual(
            metrics["layer_routes"]["unexpected_layer_ids"],
            [76],
        )
        self.assertEqual(
            metrics["layer_routes"]["unexpected_gpu_completed_layer_ids"],
            [76],
        )
        self.assertEqual(
            metrics["layer_routes"][
                "unexpected_compositor_consumed_layer_ids"
            ],
            [76],
        )
        failures = benchmark.resolved_material_graph_execution_failures(
            metrics,
            require_evidence=True,
        )
        self.assertIn(
            "resolved material graph non-accepted layer GPU completion observed",
            failures,
        )
        self.assertIn(
            "resolved material graph non-accepted layer compositor consumption observed",
            failures,
        )


if __name__ == "__main__":
    unittest.main()

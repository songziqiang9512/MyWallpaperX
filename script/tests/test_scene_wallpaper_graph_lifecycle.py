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


class SceneWallpaperGraphLifecycleTests(unittest.TestCase):
    def test_resolved_material_graph_extent_lifecycle_accepts_aba_profiles(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=533 status=accepted "
            "dependency=none dependencyReferences=0\n"
        )
        audit = (
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1 localFallbacks=0"
        )
        disposition, exact_execution = resolved_graph_exact_evidence([533])
        cases = (
            {
                "name": "scaled-target-descriptors",
                "observations": [
                    graph_execution_observation(
                        frame=1,
                        layer=533,
                        transaction="scale-a-initial",
                        trigger="first-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="a" * 64,
                        target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                        history="seeded",
                        reset="initial",
                    ),
                    graph_execution_observation(
                        frame=2,
                        layer=533,
                        transaction="scale-a-cow",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="a" * 64,
                        target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                        history="reused",
                        reset="history-copy-on-write",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=3,
                        layer=533,
                        transaction="scale-b-reprepare",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="b" * 64,
                        target_descriptor_counts="481x271/rgbaBackbuffer:2",
                        input_width=962,
                        input_height=542,
                        history="seeded",
                        reset="allocation-reprepare",
                        history_content_discarded=True,
                    ),
                    graph_execution_observation(
                        frame=4,
                        layer=533,
                        transaction="scale-b-cow",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="b" * 64,
                        target_descriptor_counts="481x271/rgbaBackbuffer:2",
                        input_width=962,
                        input_height=542,
                        history="reused",
                        reset="history-copy-on-write",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=5,
                        layer=533,
                        transaction="scale-a-restored",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="a" * 64,
                        target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                        history="seeded",
                        reset="allocation-reprepare",
                        history_content_discarded=True,
                    ),
                ],
                "anchors": [
                    {
                        "input_width": 2048,
                        "input_height": 1152,
                        "target_descriptor_counts":
                            "1024x576/rgbaBackbuffer:2",
                        "history": "seeded",
                        "reset": "initial",
                        "history_rehydrate_copy_count": 0,
                        "history_content_discarded": False,
                    },
                    {
                        "input_width": 962,
                        "input_height": 542,
                        "target_descriptor_counts":
                            "481x271/rgbaBackbuffer:2",
                        "history": "seeded",
                        "reset": "allocation-reprepare",
                        "history_rehydrate_copy_count": 0,
                        "history_content_discarded": True,
                    },
                    {
                        "input_width": 2048,
                        "input_height": 1152,
                        "target_descriptor_counts":
                            "1024x576/rgbaBackbuffer:2",
                        "history": "seeded",
                        "reset": "allocation-reprepare",
                        "history_rehydrate_copy_count": 0,
                        "history_content_discarded": True,
                    },
                ],
            },
            {
                "name": "absolute-target-descriptors",
                "observations": [
                    graph_execution_observation(
                        frame=1,
                        layer=533,
                        transaction="absolute-a-initial",
                        trigger="first-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        history="seeded",
                        reset="initial",
                    ),
                    graph_execution_observation(
                        frame=2,
                        layer=533,
                        transaction="absolute-a-cow",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        history="reused",
                        reset="history-copy-on-write",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=3,
                        layer=533,
                        transaction="absolute-b-reprepare",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        input_width=962,
                        input_height=542,
                        history="reused",
                        reset="allocation-reprepare",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=4,
                        layer=533,
                        transaction="absolute-b-cow",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        input_width=962,
                        input_height=542,
                        history="reused",
                        reset="history-copy-on-write",
                        history_rehydrate_copy_count=2,
                    ),
                    graph_execution_observation(
                        frame=5,
                        layer=533,
                        transaction="absolute-a-restored",
                        trigger="next-frame+compositor-consume+gpu-completed",
                        consumed=True,
                        target_descriptors_sha256="c" * 64,
                        target_descriptor_counts="640x360/rgbaBackbuffer:2",
                        history="reused",
                        reset="allocation-reprepare",
                        history_rehydrate_copy_count=2,
                    ),
                ],
                "anchors": [
                    {
                        "input_width": 2048,
                        "input_height": 1152,
                        "target_descriptor_counts":
                            "640x360/rgbaBackbuffer:2",
                        "history": "seeded",
                        "reset": "initial",
                        "history_rehydrate_copy_count": 0,
                        "history_content_discarded": False,
                    },
                    {
                        "input_width": 962,
                        "input_height": 542,
                        "target_descriptor_counts":
                            "640x360/rgbaBackbuffer:2",
                        "history": "reused",
                        "reset": "allocation-reprepare",
                        "history_rehydrate_copy_count": 2,
                        "history_content_discarded": False,
                    },
                    {
                        "input_width": 2048,
                        "input_height": 1152,
                        "target_descriptor_counts":
                            "640x360/rgbaBackbuffer:2",
                        "history": "reused",
                        "reset": "allocation-reprepare",
                        "history_rehydrate_copy_count": 2,
                        "history_content_discarded": False,
                    },
                ],
            },
        )

        for case in cases:
            with self.subTest(profile=case["name"]):
                metrics = benchmark.resolved_material_graph_execution_metrics(
                    preview_text,
                    "\n".join([audit, *case["observations"]]),
                    effect_execution=exact_execution,
                    static_disposition=disposition,
                )
                sample = {
                    "expected_resolved_material_graph_succeeded_layer_ids": [
                        533
                    ],
                    "expected_resolved_material_graph_extent_lifecycle": {
                        "layer_id": 533,
                        "anchors": case["anchors"],
                        "require_history_copy_on_write": True,
                    },
                }

                self.assertEqual(
                    benchmark.resolved_material_graph_execution_failures(
                        metrics,
                        require_evidence=True,
                        sample=sample,
                    ),
                    [],
                )
                transitions = metrics["graph_observations"][
                    "lifecycle_transitions"
                ]
                self.assertEqual(
                    [entry["allocation_generation"] for entry in transitions],
                    [1, 3, 5],
                )
                self.assertEqual(
                    [entry["mapping_generation"] for entry in transitions],
                    [1, 3, 5],
                )
                self.assertEqual(
                    [entry["mapping_before_sha256"] for entry in transitions],
                    ["a" * 64] * 3,
                )
                self.assertEqual(
                    [entry["mapping_after_sha256"] for entry in transitions],
                    ["b" * 64] * 3,
                )
                self.assertEqual(
                    metrics["graph_observations"][
                        "history_copy_on_write_count"
                    ],
                    2,
                )

    def test_graph_lifecycle_is_scoped_to_runtime_instance(self) -> None:
        observations = []
        for runtime in ("runtime-a", "runtime-b"):
            observations.extend([
                graph_execution_observation(
                    frame=1,
                    layer=533,
                    transaction="r4:1:1:0",
                    trigger="first-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="a" * 64,
                    target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                    history="seeded",
                    reset="initial",
                    runtime_instance_identity=runtime,
                ),
                graph_execution_observation(
                    frame=2,
                    layer=533,
                    transaction="r4:1:2:0",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="a" * 64,
                    target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                    history="reused",
                    reset="history-copy-on-write",
                    history_rehydrate_copy_count=2,
                    runtime_instance_identity=runtime,
                ),
            ])

        metrics = benchmark.resolved_material_graph_observation_metrics(
            "\n".join(observations)
        )

        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(metrics["runtime_instance_identities"], [
            "runtime-a", "runtime-b",
        ])
        self.assertEqual(metrics["runtime_instance_identity_count"], 2)
        self.assertEqual(metrics["successful_transaction_count"], 4)
        self.assertEqual(metrics["history_copy_on_write_count"], 2)

    def test_graph_lifecycle_is_scoped_to_exact_effect_identity(self) -> None:
        observations = [
            graph_execution_observation(
                frame=1,
                layer=17,
                effect=0,
                descriptor_id="17%23effect%230",
                transaction="r4:1:1:0",
                trigger="first-frame+gpu-completed",
                allocation_generation=1,
                mapping_generation=1,
                runtime_instance_identity="runtime-a",
            ),
            graph_execution_observation(
                frame=1,
                layer=17,
                effect=1,
                descriptor_id="17%23effect%231",
                transaction="r4:1:1:1",
                trigger="first-frame+compositor-consume+gpu-completed",
                consumed=True,
                allocation_generation=1,
                mapping_generation=1,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="512x288/rgba8888:2",
                history="seeded",
                reset="initial",
                runtime_instance_identity="runtime-a",
            ),
            graph_execution_observation(
                frame=2,
                layer=17,
                effect=0,
                descriptor_id="17%23effect%230",
                transaction="r4:1:2:0",
                trigger="next-frame+gpu-completed",
                allocation_generation=2,
                mapping_generation=1,
                reset="initial",
                runtime_instance_identity="runtime-a",
            ),
            graph_execution_observation(
                frame=2,
                layer=17,
                effect=1,
                descriptor_id="17%23effect%231",
                transaction="r4:1:2:1",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
                allocation_generation=2,
                mapping_generation=2,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="512x288/rgba8888:2",
                history="reused",
                reset="history-copy-on-write",
                history_rehydrate_copy_count=1,
                runtime_instance_identity="runtime-a",
            ),
        ]

        metrics = benchmark.resolved_material_graph_observation_metrics(
            "\n".join(observations)
        )

        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(metrics["history_copy_on_write_count"], 1)
        self.assertEqual(
            {
                (entry["effect_index"], entry["descriptor_id"])
                for entry in metrics["terminal_success_observations"]
            },
            {(0, "17#effect#0"), (1, "17#effect#1")},
        )

    def test_graph_lifecycle_remains_strict_within_runtime_instance(self) -> None:
        observations = [
            graph_execution_observation(
                frame=1,
                layer=533,
                transaction="initial",
                trigger="first-frame+compositor-consume+gpu-completed",
                consumed=True,
                allocation_generation=2,
                mapping_generation=2,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                history="seeded",
                reset="initial",
                runtime_instance_identity="runtime-a",
            ),
            graph_execution_observation(
                frame=2,
                layer=533,
                transaction="regressed",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
                allocation_generation=1,
                mapping_generation=1,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                history="reused",
                reset="history-copy-on-write",
                history_rehydrate_copy_count=2,
                runtime_instance_identity="runtime-a",
            ),
        ]

        metrics = benchmark.resolved_material_graph_observation_metrics(
            "\n".join(observations)
        )

        self.assertIn(
            "resolved material graph allocation identity transition invalid",
            metrics["validation_failures"],
        )

    def test_graph_lifecycle_tracks_shared_working_pair_separately(self) -> None:
        initial = graph_execution_observation(
            frame=1,
            layer=743,
            transaction="initial-shared-history",
            trigger="first-frame+compositor-consume+gpu-completed",
            consumed=True,
            allocation_generation=40,
            mapping_generation=1,
            full_frame_pair_storage="shared",
            full_frame_pair_generation=7,
            final_physical_identity="shared-pair-7-primary",
            target_descriptors_sha256="a" * 64,
            target_descriptor_counts="1024x576/rgbaBackbuffer:2",
            history="seeded",
            reset="initial",
        )
        valid_reuse = graph_execution_observation(
            frame=2,
            layer=743,
            transaction="shared-history-cow",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
            allocation_generation=41,
            mapping_generation=2,
            full_frame_pair_storage="shared",
            full_frame_pair_generation=7,
            final_physical_identity="shared-pair-7-primary",
            target_descriptors_sha256="a" * 64,
            target_descriptor_counts="1024x576/rgbaBackbuffer:2",
            history="reused",
            reset="history-copy-on-write",
            history_rehydrate_copy_count=2,
        )
        valid = benchmark.resolved_material_graph_observation_metrics(
            "\n".join([initial, valid_reuse])
        )
        self.assertEqual(valid["validation_failures"], [])

        newer_sized_pair = graph_execution_observation(
            frame=3,
            layer=743,
            transaction="newer-sized-pair",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
            allocation_generation=42,
            mapping_generation=3,
            full_frame_pair_storage="shared",
            full_frame_pair_generation=12,
            final_physical_identity="shared-pair-12-primary",
            input_width=1024,
            input_height=577,
            target_descriptors_sha256="b" * 64,
            target_descriptor_counts="1024x577/rgbaBackbuffer:2",
            history="seeded",
            reset="allocation-reprepare",
        )
        cached_older_sized_pair = graph_execution_observation(
            frame=4,
            layer=743,
            transaction="cached-older-sized-pair",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
            allocation_generation=43,
            mapping_generation=4,
            full_frame_pair_storage="shared",
            full_frame_pair_generation=7,
            final_physical_identity="shared-pair-7-primary",
            input_width=1024,
            input_height=576,
            target_descriptors_sha256="a" * 64,
            target_descriptor_counts="1024x576/rgbaBackbuffer:2",
            history="seeded",
            reset="allocation-reprepare",
        )
        cached_pair_return = benchmark.resolved_material_graph_observation_metrics(
            "\n".join([
                initial,
                valid_reuse,
                newer_sized_pair,
                cached_older_sized_pair,
            ])
        )
        self.assertEqual(cached_pair_return["validation_failures"], [])

        invalid_rebind = graph_execution_observation(
            frame=2,
            layer=743,
            transaction="forged-shared-history-cow",
            trigger="next-frame+compositor-consume+gpu-completed",
            consumed=True,
            allocation_generation=41,
            mapping_generation=2,
            full_frame_pair_storage="shared",
            full_frame_pair_generation=7,
            final_physical_identity="forged-pair-primary",
            target_descriptors_sha256="a" * 64,
            target_descriptor_counts="1024x576/rgbaBackbuffer:2",
            history="reused",
            reset="history-copy-on-write",
            history_rehydrate_copy_count=2,
        )
        invalid = benchmark.resolved_material_graph_observation_metrics(
            "\n".join([initial, invalid_rebind])
        )
        self.assertIn(
            "resolved material graph allocation identity transition invalid",
            invalid["validation_failures"],
        )

    def test_resolved_material_graph_lifecycle_rejects_mislabeled_transitions(
        self,
    ) -> None:
        initial = graph_execution_observation(
            frame=1,
            layer=533,
            transaction="initial",
            trigger="first-frame+compositor-consume+gpu-completed",
            consumed=True,
            target_descriptors_sha256="a" * 64,
            target_descriptor_counts="1024x576/rgbaBackbuffer:2",
            history="seeded",
            reset="initial",
        )
        cases = (
            (
                "unknown-reset",
                graph_execution_observation(
                    frame=2,
                    layer=533,
                    transaction="unknown-reset",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="a" * 64,
                    target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                    history="reused",
                    reset="unknown-lifecycle",
                    history_rehydrate_copy_count=2,
                ),
                "resolved material graph reset reason invalid",
            ),
            (
                "copy-on-write-changed-descriptor",
                graph_execution_observation(
                    frame=2,
                    layer=533,
                    transaction="mislabeled-cow",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="b" * 64,
                    target_descriptor_counts="481x271/rgbaBackbuffer:2",
                    input_width=962,
                    input_height=542,
                    history="reused",
                    reset="history-copy-on-write",
                    history_rehydrate_copy_count=2,
                ),
                (
                    "resolved material graph history copy-on-write "
                    "transition invalid"
                ),
            ),
            (
                "reprepare-stable-descriptor",
                graph_execution_observation(
                    frame=2,
                    layer=533,
                    transaction="mislabeled-reprepare",
                    trigger="next-frame+compositor-consume+gpu-completed",
                    consumed=True,
                    target_descriptors_sha256="a" * 64,
                    target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                    history="reused",
                    reset="allocation-reprepare",
                    history_rehydrate_copy_count=2,
                ),
                (
                    "resolved material graph allocation reprepare "
                    "transition invalid"
                ),
            ),
        )

        for name, observation, expected_failure in cases:
            with self.subTest(case=name):
                metrics = benchmark.resolved_material_graph_observation_metrics(
                    "\n".join([initial, observation])
                )
                self.assertIn(
                    expected_failure,
                    metrics["validation_failures"],
                )

    def test_resolved_material_graph_extent_lifecycle_expectation_is_exact(
        self,
    ) -> None:
        preview_text = (
            "resolved material execution capabilities: "
            "schema=layer-graph-capability-v1 candidates=1 accepted=1 "
            "rejected=0 variantLimit=8\n"
            "resolved material execution capability: "
            "schema=layer-graph-route-v1 layer=533 status=accepted\n"
        )
        log_text = "\n".join([
            "resolved material runtime audit: schema=scene-graph-executor-v1 "
            "claimed=1 encoded=1 failures=0 deferred=0 pending=1 "
            "gpuEncoded=1 localFallbacks=0",
            graph_execution_observation(
                frame=1,
                layer=533,
                transaction="a",
                trigger="first-frame+compositor-consume+gpu-completed",
                consumed=True,
                target_descriptors_sha256="a" * 64,
                target_descriptor_counts="1024x576/rgbaBackbuffer:2",
                history="seeded",
                reset="initial",
            ),
            graph_execution_observation(
                frame=2,
                layer=533,
                transaction="b",
                trigger="next-frame+compositor-consume+gpu-completed",
                consumed=True,
                target_descriptors_sha256="b" * 64,
                target_descriptor_counts="481x271/rgbaBackbuffer:2",
                input_width=962,
                input_height=542,
                history="seeded",
                reset="allocation-reprepare",
                history_content_discarded=True,
            ),
        ])
        disposition, exact_execution = resolved_graph_exact_evidence([533])
        metrics = benchmark.resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=exact_execution,
            static_disposition=disposition,
        )
        base_sample = {
            "expected_resolved_material_graph_succeeded_layer_ids": [533],
        }

        malformed = dict(base_sample)
        malformed["expected_resolved_material_graph_extent_lifecycle"] = {
            "layer_id": 533,
            "anchors": [],
            "require_history_copy_on_write": False,
        }
        self.assertIn(
            "resolved material graph extent lifecycle expectation invalid",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample=malformed,
            ),
        )

        wrong_anchor = dict(base_sample)
        wrong_anchor["expected_resolved_material_graph_extent_lifecycle"] = {
            "layer_id": 533,
            "anchors": [
                {
                    "input_width": 2048,
                    "input_height": 1152,
                    "target_descriptor_counts":
                        "1024x576/rgbaBackbuffer:2",
                    "history": "seeded",
                    "reset": "initial",
                    "history_rehydrate_copy_count": 0,
                    "history_content_discarded": False,
                },
                {
                    "input_width": 963,
                    "input_height": 542,
                    "target_descriptor_counts":
                        "481x271/rgbaBackbuffer:2",
                    "history": "seeded",
                    "reset": "allocation-reprepare",
                    "history_rehydrate_copy_count": 0,
                    "history_content_discarded": True,
                },
            ],
            "require_history_copy_on_write": False,
        }
        self.assertIn(
            "resolved material graph extent lifecycle evidence mismatch",
            benchmark.resolved_material_graph_execution_failures(
                metrics,
                require_evidence=True,
                sample=wrong_anchor,
            ),
        )


if __name__ == "__main__":
    unittest.main()

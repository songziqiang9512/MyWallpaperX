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


class SceneWallpaperEffectExecutionTests(unittest.TestCase):
    def test_effect_local_visual_failure_expectation_is_exact(self) -> None:
        _, execution, expectation = (
            resolved_graph_effect_local_failure_evidence()
        )
        sample = {
            benchmark.EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY: [expectation],
        }

        self.assertEqual(execution["validation_failures"], [])
        self.assertEqual(
            benchmark.effect_execution_failures(
                execution,
                sample=sample,
            ),
            [],
        )
        self.assertIn(
            "effect execution CPU invocation failed",
            benchmark.effect_execution_failures(execution),
        )

        wrong_reason = {
            **expectation,
            "reason": "material-finalizer-system-provider-unavailable",
        }
        self.assertIn(
            "effect execution effect-local passthrough expectation mismatch",
            benchmark.effect_execution_failures(
                execution,
                sample={
                    benchmark.EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY: [
                        wrong_reason
                    ],
                },
            ),
        )

        _, wrong_descriptor_execution, _ = (
            resolved_graph_effect_local_failure_evidence(
                event_descriptor_id="68%23effect%239",
            )
        )
        self.assertIn(
            "effect execution effect-local passthrough expectation mismatch",
            benchmark.effect_execution_failures(
                wrong_descriptor_execution,
                sample=sample,
            ),
        )
        self.assertIn(
            "effect execution exact identity missing from disposition",
            wrong_descriptor_execution["validation_failures"],
        )

        _, wrong_backend_execution, _ = (
            resolved_graph_effect_local_failure_evidence(
                backend="fixture-backend",
            )
        )
        self.assertIn(
            "effect execution effect-local passthrough expectation mismatch",
            benchmark.effect_execution_failures(
                wrong_backend_execution,
                sample=sample,
            ),
        )

        _, extra_failure_execution, _ = (
            resolved_graph_effect_local_failure_evidence(
                include_extra_failed_program=True,
            )
        )
        extra_failure_failures = benchmark.effect_execution_failures(
            extra_failure_execution,
            sample=sample,
        )
        self.assertNotIn(
            "effect execution effect-local passthrough expectation mismatch",
            extra_failure_failures,
        )
        self.assertIn(
            "effect execution CPU invocation failed",
            extra_failure_failures,
        )

    def test_effect_recovery_requires_explicit_exact_ordered_expectation(
        self,
    ) -> None:
        _, execution, expectation = resolved_graph_effect_recovery_evidence()
        sample = {benchmark.EFFECT_RECOVERY_EXPECTATION_KEY: [expectation]}

        self.assertEqual(execution["validation_failures"], [])
        self.assertEqual(len(execution["exact_outcome_transition_effects"]), 1)
        self.assertEqual(
            benchmark.effect_execution_failures(execution, sample=sample),
            [],
        )
        default_failures = benchmark.effect_execution_failures(execution)
        self.assertIn(
            "effect execution exact identity both succeeded and failed",
            default_failures,
        )
        self.assertIn("effect execution CPU invocation failed", default_failures)
        _, repeated_pending, _ = resolved_graph_effect_recovery_evidence(
            failure_frames=(10, 11, 12),
        )
        failed_invocation = next(
            value for value in repeated_pending["cpu_invocations"]
            if value["outcome"] == "failed"
        )
        self.assertEqual(failed_invocation["frame_ids"], [10, 11, 12])
        self.assertEqual(
            benchmark.effect_execution_failures(
                repeated_pending,
                sample=sample,
            ),
            [],
        )
        _, fallback_after_success, _ = resolved_graph_effect_recovery_evidence(
            failure_frames=(10, 21),
        )
        self.assertIn(
            "effect execution recovery evidence mismatch",
            benchmark.effect_execution_failures(
                fallback_after_success,
                sample=sample,
            ),
        )
        static_passthrough_failures = benchmark.effect_execution_failures(
            execution,
            sample={
                benchmark.EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY: [expectation]
            },
        )
        self.assertIn(
            "effect execution exact identity both succeeded and failed",
            static_passthrough_failures,
        )
        self.assertIn(
            "effect execution effect-local passthrough expectation mismatch",
            static_passthrough_failures,
        )

        for kwargs in (
            {"failure_frame": 21, "success_frame": 20},
            {"reason": "material-finalizer-system-provider-purpose-mismatch"},
            {"failure_backend": "fixture-backend"},
            {"failure_descriptor_id": "68%23effect%239"},
        ):
            _, invalid_execution, _ = resolved_graph_effect_recovery_evidence(
                **kwargs
            )
            self.assertIn(
                "effect execution recovery evidence mismatch",
                benchmark.effect_execution_failures(
                    invalid_execution,
                    sample=sample,
                ),
            )

        self.assertIn(
            "effect execution recovery expectation invalid",
            benchmark.effect_execution_failures(
                execution,
                sample={benchmark.EFFECT_RECOVERY_EXPECTATION_KEY: []},
            ),
        )

    def test_startup_inactive_passthrough_has_no_exact_cpu_demand(self) -> None:
        preview = "\n".join([
            "authoredEffectGraphStageCount: 1",
            "effectStageDescriptorCount: 1",
            "effectStageParsedCount: 1",
            "effectStageActivityCounts: author-disabled=0,property-inactive=1,layer-hidden=0,active=0",
            "effectStageAdmissionCounts: inactive=0,admitted-dedicated=0,admitted-fallback=0,admitted-generic=0,admitted-passthrough=1,not-admitted=0",
            "effectStageCoverageCounts: inactive=0,complete=1,rejected-missing-graph=0,rejected-ambiguous-graph=0,rejected-graph-mismatch=0,rejected-capability=0",
            "effectStageDescriptorIdentityConserved: true",
            "effectStageActivityConserved: true",
            "effectStageInactiveAdmissionConserved: true",
            "effectStageActiveAdmissionConserved: true",
            "effectStageExecutionIdentityConserved: true",
            "effectStageAdmission: layer=2 effect=0 descriptor=2%23effect%230 activity=property-inactive admission=admitted-passthrough coverage=complete backend=initially-inactive-passthrough profile=inactive-passthrough reason=- path=effects/inactive/effect.json",
            "effectStageRuntimeDispositionSchema: 1",
            "effectStageRuntimeRouteScope: unified-effect-graph",
            "effectStageRuntimeDispositionCount: 1",
            "effectStageRuntimeDispositionKindCounts: inactive=0,dedicated=0,fallback=0,passthrough=1,program=0,unsupported=0,unattributed=0",
            "effectStageRuntimeDispositionAttributionCounts: exact-key=1,none=0",
            "effectStageRuntimeDispositionRoleCounts: owner=0,member=1,none=0",
            "effectStaticRouteGroupCount: 1",
            "effectStaticRouteGroupKindCounts: inactive=0,direct=0,resolved=1",
            "effectStageRuntimeDescriptorIdentityConserved: true",
            "effectStageRuntimeGroupIdentityConserved: true",
            "effectStageRuntimeAdmissionIdentityConserved: true",
            "effectStageRuntimeResolvedMaterialOwnershipConserved: true",
            "effectStaticRouteGroup: layer=2 scope=unified-effect-graph kind=resolved effects=1 owners=0 reason=-",
            "effectStageRuntimeDisposition: layer=2 effect=0 descriptor=2%23effect%230 kind=passthrough attribution=exact-key family=initially-inactive-passthrough group=2 role=member reason=initially-inactive-property-stage-passthrough path=effects/inactive/effect.json",
        ])

        admission = benchmark.effect_stage_admission_metrics(preview)
        self.assertEqual(admission["validation_failures"], [])
        self.assertEqual(
            admission["admission_counts"]["admitted-passthrough"],
            1,
        )
        self.assertEqual(admission["admission_counts"]["admitted-fallback"], 0)

        disposition = benchmark.effect_runtime_disposition_metrics(
            preview,
            admission,
        )
        self.assertEqual(disposition["validation_failures"], [])
        self.assertEqual(disposition["kind_counts"]["passthrough"], 1)
        self.assertEqual(disposition["kind_counts"]["fallback"], 0)
        demand = benchmark.effect_execution_static_demand(disposition)
        self.assertTrue(demand.static_is_valid)
        self.assertEqual(demand.eligible_exact_effect_count, 0)
        self.assertNotIn("passthrough", benchmark.EFFECT_EXECUTION_EXACT_KINDS)

        execution = benchmark.effect_execution_metrics("", disposition)
        self.assertFalse(execution["has_evidence"])
        self.assertEqual(
            benchmark.effect_execution_failures(
                execution,
                require_evidence=True,
                static_disposition=disposition,
            ),
            [],
        )

    def test_effect_execution_decodes_tokens_before_static_family_join(self) -> None:
        disposition = json.loads(json.dumps(
            benchmark.effect_runtime_disposition_metrics(
                effect_runtime_disposition_preview()
            )
        ))
        record = next(
            item for item in disposition["records"]
            if item["layer_id"] == 2 and item["effect_index"] == 0
        )
        record["descriptor_id"] = "same descriptor"
        record["family"] = "Tint Space"
        event = effect_cpu_event(
            frame=20,
            origin="image",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="same%20descriptor",
            family="Tint%20Space",
            backend="strict%20generic",
        )
        metrics = benchmark.effect_execution_metrics(
            effect_execution_log(20, [event], []),
            disposition,
        )
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(metrics["cpu_invocations"][0]["family"], "Tint Space")
        self.assertEqual(
            metrics["cpu_invocations"][0]["backend"], "strict generic"
        )
        self.assertEqual(
            metrics["succeeded_exact_effects"][0]["descriptor_id"],
            "same descriptor",
        )

    def test_effect_execution_failure_is_sticky_across_completed_frame(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        success = effect_cpu_event(
            frame=12,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="fixture-dedicated",
            backend="fixture-dedicated",
        )
        failure = effect_cpu_event(
            frame=12,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="fixture-dedicated",
            backend="fixture-dedicated",
            outcome="failed",
            reason="encoder-refused",
        )
        later_success = effect_cpu_event(
            frame=13,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="fixture-dedicated",
            backend="fixture-dedicated",
        )
        metrics = benchmark.effect_execution_metrics(
            "\n".join([
                effect_execution_log(12, [failure], [], status="completed"),
                effect_execution_log(
                    13, [later_success], [], status="completed"
                ),
            ]),
            disposition,
        )
        self.assertEqual(metrics["completed_frame_ids"], [12, 13])
        self.assertEqual(len(metrics["succeeded_exact_effects"]), 1)
        self.assertEqual(len(metrics["failed_exact_effects"]), 1)
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(len(metrics["exact_outcome_transition_effects"]), 1)
        failures = benchmark.effect_execution_failures(metrics)
        self.assertIn(
            "effect execution exact identity both succeeded and failed",
            failures,
        )
        self.assertIn("effect execution CPU invocation failed", failures)
        self.assertNotIn(
            "effect execution frame command buffer failed",
            failures,
        )

        completed_only = benchmark.effect_execution_metrics(
            effect_execution_log(
                14,
                [],
                [],
                count_overrides={"attempted": 1, "returned": 1},
                cohort_override=hashlib.sha256(
                    str(success["canonical"]).encode("utf-8")
                ).hexdigest(),
            ),
            disposition,
        )
        self.assertEqual(completed_only["succeeded_exact_effects"], [])
        self.assertEqual(completed_only["validation_failures"], [])

    def test_effect_execution_deduplicates_events_before_frame_contract(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        event = effect_cpu_event(
            frame=14,
            origin="resolved-material-graph",
            subject="effect",
            layer=2,
            effect=1,
            descriptor="2%23effect%231",
            family="resolved-material",
            backend="resolved-material-graph",
        )
        route = effect_route_event(
            frame=14,
            origin="resolved-material-graph",
            layer=2,
            operation="graph-stage",
        )
        repeated_event = effect_cpu_event(
            frame=15,
            origin="resolved-material-graph",
            subject="effect",
            layer=2,
            effect=1,
            descriptor="2%23effect%231",
            family="resolved-material",
            backend="resolved-material-graph",
        )
        repeated_route = effect_route_event(
            frame=15,
            origin="resolved-material-graph",
            layer=2,
            operation="graph-stage",
        )
        metrics = benchmark.effect_execution_metrics(
            "\n".join([
                effect_execution_log(14, [event, event], [route, route]),
                effect_execution_log(15, [repeated_event], [repeated_route]),
            ]),
            disposition,
        )
        self.assertEqual(metrics["cpu_invocation_count"], 1)
        self.assertEqual(metrics["route_operation_count"], 1)
        self.assertEqual(metrics["frame_observation_count"], 2)
        self.assertEqual(metrics["frames"][0]["attempted_effects"], 1)
        self.assertEqual(metrics["frames"][0]["route_operations"], 1)
        self.assertEqual(metrics["validation_failures"], [])

    def test_effect_execution_validates_frame_summary_relations_and_format(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        event = effect_cpu_event(
            frame=15,
            origin="strict-chain",
            subject="effect",
            layer=2,
            effect=0,
            descriptor="2%23effect%230",
            family="fixture-dedicated",
            backend="fixture-dedicated",
        )
        bad_returned = benchmark.effect_execution_metrics(
            effect_execution_log(
                15,
                [event],
                [],
                count_overrides={"attempted": 0},
            ),
            disposition,
        )
        self.assertIn(
            "effect execution frame returned outputs exceed attempted effects",
            bad_returned["validation_failures"],
        )
        bad_failed = benchmark.effect_execution_metrics(
            effect_execution_log(
                15,
                [event],
                [],
                count_overrides={"attempted": 0, "returned": 0, "failed": 1},
            ),
            disposition,
        )
        self.assertIn(
            "effect execution frame failed invocations exceed attempted effects",
            bad_failed["validation_failures"],
        )
        opaque_valid_hash = benchmark.effect_execution_metrics(
            effect_execution_log(15, [event], [], cohort_override="0" * 64),
            disposition,
        )
        self.assertNotIn(
            "effect execution frame summary malformed",
            opaque_valid_hash["validation_failures"],
        )
        malformed_hash_log = effect_execution_log(15, [event], []).replace(
            "cohortSHA256=", "cohortSHA256=x"
        )
        malformed_hash = benchmark.effect_execution_metrics(
            malformed_hash_log,
            disposition,
        )
        self.assertIn(
            "effect execution frame summary malformed",
            malformed_hash["validation_failures"],
        )

        first_summary = effect_execution_log(15, [event], [])
        conflicting_summary = effect_execution_log(
            15,
            [],
            [],
            cohort_override="1" * 64,
        ).splitlines()[-1]
        duplicate_status = benchmark.effect_execution_metrics(
            f"{first_summary}\n{conflicting_summary}",
            disposition,
        )
        self.assertIn(
            "effect execution frame status identity duplicated",
            duplicate_status["validation_failures"],
        )

    def test_effect_execution_route_and_shared_buffer_failures_gate(self) -> None:
        disposition = benchmark.effect_runtime_disposition_metrics(
            effect_runtime_disposition_preview()
        )
        route = effect_route_event(
            frame=16,
            origin="graph-executor",
            layer=2,
            operation="typed-stage",
            outcome="failed",
            reason="encoder-refused",
        )
        metrics = benchmark.effect_execution_metrics(
            "\n".join([
                effect_execution_log(16, [], [route], status="failed"),
                effect_execution_log(16, [], [route], status="completed"),
            ]),
            disposition,
        )
        self.assertEqual(metrics["completed_frame_ids"], [16])
        self.assertEqual(metrics["failed_frame_ids"], [16])
        self.assertNotIn(
            "effect execution frame status identity duplicated",
            metrics["validation_failures"],
        )
        failures = benchmark.effect_execution_failures(metrics)
        self.assertIn("effect execution route operation failed", failures)
        self.assertIn(
            "effect execution frame command buffer failed",
            failures,
        )

    def test_effect_execution_degraded_encoded_route_is_non_pass(self) -> None:
        ordinary_route = effect_route_event(
            frame=17,
            origin="graph-executor",
            layer=2,
            operation="typed-stage",
        )
        ordinary_metrics = benchmark.effect_execution_metrics(
            effect_execution_log(17, [], [ordinary_route])
        )
        self.assertEqual(len(ordinary_metrics["encoded_route_operations"]), 1)
        self.assertEqual(ordinary_metrics["degraded_route_operations"], [])
        self.assertEqual(ordinary_metrics["failed_route_operations"], [])
        self.assertEqual(
            benchmark.effect_execution_failures(ordinary_metrics),
            [],
        )

        degraded_route = effect_route_event(
            frame=18,
            origin="graph-executor",
            layer=2,
            operation="degraded-layer-source-passthrough",
        )
        degraded_metrics = benchmark.effect_execution_metrics(
            effect_execution_log(18, [], [degraded_route])
        )
        self.assertEqual(len(degraded_metrics["encoded_route_operations"]), 1)
        self.assertEqual(
            degraded_metrics["degraded_route_operations"],
            degraded_metrics["encoded_route_operations"],
        )
        self.assertEqual(degraded_metrics["failed_route_operations"], [])
        self.assertEqual(
            benchmark.effect_execution_failures(degraded_metrics),
            ["effect execution degraded layer source passthrough"],
        )

        malformed_metrics = benchmark.effect_execution_metrics(
            "schema=1 axis=effect-route-operation frame=19 "
            "origin=graph-executor layer=2 operation=typed-stage "
            "outcome=encoded"
        )
        self.assertIn(
            "effect execution route operation malformed",
            malformed_metrics["validation_failures"],
        )

    def test_effect_execution_expected_local_fallback_is_bounded(self) -> None:
        route = effect_route_event(
            frame=20,
            origin="image",
            layer=17,
            operation="unclaimed-effect-product-authority",
            outcome="failed",
            reason="unclaimed-visible-effects",
        )
        metrics = benchmark.effect_execution_metrics(
            effect_execution_log(20, [], [route])
        )
        expected = [{
            "origin": "image",
            "layer_id": 17,
            "operation": "unclaimed-effect-product-authority",
            "outcome": "failed",
            "reason": "unclaimed-visible-effects",
        }]
        self.assertEqual(
            benchmark.effect_execution_failures(
                metrics,
                sample={
                    "expected_effect_execution_local_fallbacks": expected,
                },
            ),
            [],
        )
        self.assertIn(
            "effect execution local fallback expectation mismatch",
            benchmark.effect_execution_failures(
                metrics,
                sample={
                    "expected_effect_execution_local_fallbacks": [],
                },
            ),
        )

    def test_effect_execution_matrix_contract_is_optional_and_stable_only(self) -> None:
        missing_metrics = benchmark.effect_execution_metrics("")
        self.assertEqual(
            benchmark.effect_execution_failures(
                missing_metrics,
                sample={"expected_effect_execution_schema": 1},
            ),
            ["effect execution evidence missing"],
        )
        self.assertEqual(
            benchmark.effect_execution_failures(
                missing_metrics,
                sample={
                    "expected_effect_execution_canonical_sha256": "0" * 64,
                    "expected_effect_execution_completed_frame_ids": [1],
                    "expected_effect_execution_cpu_invocation_count": 3,
                },
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()

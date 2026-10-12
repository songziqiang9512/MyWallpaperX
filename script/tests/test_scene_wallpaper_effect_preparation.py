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


class SceneWallpaperEffectPreparationTests(unittest.TestCase):
    def test_effect_stage_admission_metrics_are_structured_and_conserved(self) -> None:
        coverage = (
            "inactive=1,complete=1,rejected-missing-graph=0,"
            "rejected-ambiguous-graph=0,rejected-graph-mismatch=0,"
            "rejected-capability=1"
        )
        preview = "\n".join([
            "authoredEffectGraphStageCount: 1",
            "effectStageDescriptorCount: 3",
            "effectStageParsedCount: 3",
            "effectStageActivityCounts: author-disabled=1,property-inactive=0,layer-hidden=0,active=2",
            "effectStageAdmissionCounts: inactive=1,admitted-dedicated=1,admitted-fallback=0,admitted-generic=0,admitted-passthrough=0,not-admitted=1",
            f"effectStageCoverageCounts: {coverage}",
            "effectStageDescriptorIdentityConserved: true",
            "effectStageActivityConserved: true",
            "effectStageInactiveAdmissionConserved: true",
            "effectStageActiveAdmissionConserved: true",
            "effectStageExecutionIdentityConserved: true",
            "effectStageAdmission: layer=1 effect=0 descriptor=1%23effect%230 activity=author-disabled admission=inactive coverage=inactive backend=- profile=- reason=- path=effects/disabled/effect.json",
            "effectStageAdmission: layer=1 effect=1 descriptor=1%23effect%231 activity=active admission=admitted-dedicated coverage=complete backend=fixture-dedicated profile=- reason=- path=effects/fixture-dedicated/effect.json",
            "effectStageAdmission: layer=1 effect=2 descriptor=1%23effect%232 activity=active admission=not-admitted coverage=rejected-capability backend=- profile=- reason=unified-capability-unavailable path=effects/unknown/effect.json",
        ])
        metrics = benchmark.effect_stage_admission_metrics(preview)
        self.assertTrue(metrics["has_evidence"])
        self.assertEqual(metrics["schema_version"], 1)
        self.assertEqual(metrics["descriptor_count"], 3)
        self.assertEqual(metrics["parsed_count"], 3)
        self.assertEqual(metrics["activity_counts"]["active"], 2)
        self.assertEqual(metrics["admission_counts"]["admitted-dedicated"], 1)
        self.assertEqual(metrics["records"][0]["descriptor_id"], "1#effect#0")
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(len(metrics["canonical_sha256"]), 64)
        self.assertEqual(
            benchmark.effect_stage_admission_failures(
                {},
                metrics,
            ),
            [],
        )

        duplicate = preview.replace(
            "effect=2 descriptor=1%23effect%232",
            "effect=1 descriptor=1%23effect%231",
        )
        duplicate_metrics = benchmark.effect_stage_admission_metrics(duplicate)
        self.assertIn(
            "effect stage admission identity duplicated",
            duplicate_metrics["validation_failures"],
        )

        invalid_combination = preview.replace(
            "admission=not-admitted coverage=rejected-capability backend=- profile=- reason=unified-capability-unavailable",
            "admission=not-admitted coverage=complete backend=fixture-dedicated profile=- reason=unified-capability-unavailable",
        )
        invalid_combination_metrics = (
            benchmark.effect_stage_admission_metrics(invalid_combination)
        )
        self.assertIn(
            "effect stage non-admitted state combination invalid",
            invalid_combination_metrics["validation_failures"],
        )

        generic_preview = preview.replace(
            "admitted-dedicated=1,admitted-fallback=0,admitted-generic=0,admitted-passthrough=0",
            "admitted-dedicated=1,admitted-fallback=0,admitted-generic=1,admitted-passthrough=0",
        ).replace(
            "not-admitted=1",
            "not-admitted=0",
        ).replace(
            "complete=1",
            "complete=2",
        ).replace(
            "rejected-capability=1",
            "rejected-capability=0",
        ).replace(
            "admission=not-admitted coverage=rejected-capability backend=- profile=- reason=unified-capability-unavailable",
            "admission=admitted-generic coverage=complete backend=resolved-material profile=program reason=-",
        )
        generic_metrics = benchmark.effect_stage_admission_metrics(
            generic_preview
        )
        self.assertEqual(generic_metrics["validation_failures"], [])

        unified_leaf_metrics = benchmark.effect_stage_admission_metrics(
            generic_preview.replace(
                "admitted-dedicated=1,admitted-fallback=0,admitted-generic=1,admitted-passthrough=0",
                "admitted-dedicated=2,admitted-fallback=0,admitted-generic=1,admitted-passthrough=0",
            ).replace(
                "effectStageDescriptorCount: 3",
                "effectStageDescriptorCount: 4",
            ).replace(
                "effectStageParsedCount: 3",
                "effectStageParsedCount: 4",
            ).replace(
                "author-disabled=1,property-inactive=0,layer-hidden=0,active=2",
                "author-disabled=1,property-inactive=0,layer-hidden=0,active=3",
            ).replace(
                "inactive=1,complete=2",
                "inactive=1,complete=3",
            ) + "\n"
            "effectStageAdmission: layer=2 effect=0 "
            "descriptor=2%23effect%230 activity=active "
            "admission=admitted-dedicated coverage=complete backend=shake "
            "profile=- reason=- path=effects/shake/effect.json"
        )
        self.assertEqual(unified_leaf_metrics["validation_failures"], [])

        property_inactive_metrics = benchmark.effect_stage_admission_metrics(
            generic_preview.replace(
                "property-inactive=0,layer-hidden=0,active=2",
                "property-inactive=1,layer-hidden=0,active=1",
            ).replace(
                "effect=2 descriptor=1%23effect%232 activity=active",
                "effect=2 descriptor=1%23effect%232 activity=property-inactive",
            )
        )
        self.assertEqual(property_inactive_metrics["validation_failures"], [])

        for invalid_owner in (
            "backend=authored-shader profile=program",
            "backend=resolved-material profile=generic-fragment",
        ):
            invalid_generic_metrics = benchmark.effect_stage_admission_metrics(
                generic_preview.replace(
                    "backend=resolved-material profile=program",
                    invalid_owner,
                )
            )
            self.assertIn(
                "effect stage generic owner invalid",
                invalid_generic_metrics["validation_failures"],
            )

        structural_rejection = preview.replace(
            "coverage=rejected-capability backend=- profile=- reason=unified-capability-unavailable",
            "coverage=rejected-graph-mismatch backend=- profile=- reason=stage-graph-mismatch",
        ).replace(
            "rejected-graph-mismatch=0,rejected-capability=1",
            "rejected-graph-mismatch=1,rejected-capability=0",
        )
        structural_metrics = benchmark.effect_stage_admission_metrics(
            structural_rejection
        )
        self.assertIn(
            "effect stage admission structural rejection: rejected-graph-mismatch",
            structural_metrics["validation_failures"],
        )

    def test_effect_local_fallback_admission_and_disposition_are_conserved(
        self,
    ) -> None:
        preview = effect_runtime_disposition_preview().replace(
            "effectStageDescriptorCount: 2",
            "effectStageDescriptorCount: 3",
        ).replace(
            "effectStageParsedCount: 2",
            "effectStageParsedCount: 3",
        ).replace(
            "author-disabled=0,property-inactive=0,layer-hidden=0,active=2",
            "author-disabled=0,property-inactive=0,layer-hidden=0,active=3",
        ).replace(
            "admitted-dedicated=1,admitted-fallback=0,admitted-generic=1,admitted-passthrough=0",
            "admitted-dedicated=1,admitted-fallback=1,admitted-generic=1,admitted-passthrough=0",
        ).replace(
            "inactive=0,complete=2",
            "inactive=0,complete=3",
        ).replace(
            "effectStageRuntimeDispositionCount: 2",
            "effectStageRuntimeDispositionCount: 3",
        ).replace(
            "inactive=0,dedicated=1,fallback=0,passthrough=0,program=1",
            "inactive=0,dedicated=1,fallback=1,passthrough=0,program=1",
        ).replace(
            "exact-key=2,none=0",
            "exact-key=3,none=0",
        ).replace(
            "owner=2,member=0,none=0",
            "owner=3,member=0,none=0",
        ).replace(
            "kind=resolved effects=2 owners=2",
            "kind=resolved effects=3 owners=3",
        ) + "\n" + "\n".join([
            "effectStageAdmission: layer=2 effect=2 "
            "descriptor=2%23effect%232 activity=active "
            "admission=admitted-fallback coverage=complete "
            "backend=visual-failure-passthrough "
            "profile=effect-local-passthrough reason=- "
            "path=effects/broken/effect.json",
            "effectStageRuntimeDisposition: layer=2 effect=2 "
            "descriptor=2%23effect%232 kind=fallback "
            "attribution=exact-key family=visual-failure-passthrough "
            "group=2 role=owner reason=effect-local-visual-failure "
            "path=effects/broken/effect.json",
        ])

        admission = benchmark.effect_stage_admission_metrics(preview)
        self.assertEqual(admission["validation_failures"], [])
        self.assertEqual(admission["admission_counts"]["admitted-fallback"], 1)
        disposition = benchmark.effect_runtime_disposition_metrics(
            preview,
            admission,
        )
        self.assertEqual(disposition["validation_failures"], [])
        self.assertEqual(disposition["kind_counts"]["fallback"], 1)
        failed_fallback = effect_cpu_event(
            frame=22,
            origin="resolved-material-graph",
            subject="effect",
            layer=2,
            effect=2,
            descriptor="2%23effect%232",
            family="visual-failure-passthrough",
            backend="resolved-material-graph",
            outcome="failed",
            reason=(
                "effect-local-passthrough-"
                "material-variant-envelope-frontend"
            ),
        )
        execution = benchmark.effect_execution_metrics(
            effect_execution_log(22, [failed_fallback], []),
            disposition,
        )
        self.assertEqual(execution["validation_failures"], [])
        self.assertIn(
            "effect execution CPU invocation failed",
            benchmark.effect_execution_failures(execution),
        )

        invalid_admission = benchmark.effect_stage_admission_metrics(
            preview.replace(
                "backend=visual-failure-passthrough "
                "profile=effect-local-passthrough",
                "backend=resolved-material profile=program",
                1,
            )
        )
        self.assertIn(
            "effect stage fallback owner invalid",
            invalid_admission["validation_failures"],
        )

    def test_effect_stage_admission_evidence_is_optional_unless_requested(self) -> None:
        metrics = benchmark.effect_stage_admission_metrics("")
        self.assertFalse(metrics["has_evidence"])
        self.assertIsNone(metrics["schema_version"])
        self.assertEqual(
            benchmark.effect_stage_admission_failures({}, metrics),
            [],
        )
        self.assertEqual(
            benchmark.effect_stage_admission_failures(
                {"expected_effect_stage_descriptor_count": 1},
                metrics,
            ),
            [],
        )
        self.assertEqual(
            benchmark.effect_stage_admission_failures(
                {},
                metrics,
                require_evidence=True,
            ),
            ["effect stage admission evidence missing"],
        )

    def test_effect_stage_compile_metrics_are_bounded_conserved_and_hashed(self) -> None:
        empty_preview = "\n".join([
            "effectStageCompileFailureCount: 0",
            "effectStageCompileFailureCodes: ",
            "effectStageCompilerProbeOutcomeCounts: ",
            "effectStageCompilerFailureCodes: ",
        ])
        empty = benchmark.authored_effect_stage_compile_metrics(empty_preview)
        self.assertTrue(empty["has_evidence"])
        self.assertEqual(empty["schema_version"], 1)
        self.assertEqual(empty["stage_failure_count"], 0)
        self.assertEqual(empty["stage_failure_code_counts"], {})
        self.assertEqual(
            empty["compiler_probe_outcome_counts"],
            {"not-applicable": 0, "rejected": 0},
        )
        self.assertEqual(empty["compiler_failure_code_counts"], {})
        self.assertEqual(empty["validation_failures"], [])
        self.assertEqual(len(empty["canonical_sha256"]), 64)

        preview = "\n".join([
            "effectStageCompileFailureCount: 2",
            "effectStageCompileFailureCodes: "
            "no-backend-accepted=1,stage-program-invariant=1",
            "effectStageCompilerProbeOutcomeCounts: "
            "not-applicable=33,rejected=2",
            "effectStageCompilerFailureCodes: "
            "authored-shader/material/material-texture-slot-unsupported=1,"
            "water-flow/compatibility/dedicated-profile-rejected=1",
        ])
        metrics = benchmark.authored_effect_stage_compile_metrics(preview)
        self.assertEqual(metrics["validation_failures"], [])
        self.assertEqual(metrics["stage_failure_count"], 2)
        self.assertEqual(
            metrics["compiler_probe_outcome_counts"],
            {"not-applicable": 33, "rejected": 2},
        )
        self.assertEqual(
            metrics["compiler_failure_code_counts"][
                "water-flow/compatibility/dedicated-profile-rejected"
            ],
            1,
        )
        reordered = preview.replace(
            "no-backend-accepted=1,stage-program-invariant=1",
            "stage-program-invariant=1,no-backend-accepted=1",
        ).replace(
            "not-applicable=33,rejected=2",
            "rejected=2,not-applicable=33",
        )
        self.assertEqual(
            benchmark.authored_effect_stage_compile_metrics(reordered)[
                "canonical_sha256"
            ],
            metrics["canonical_sha256"],
        )

    def test_effect_stage_compile_metrics_reject_partial_or_invalid_summaries(self) -> None:
        self.assertFalse(
            benchmark.authored_effect_stage_compile_metrics("")["has_evidence"]
        )
        partial = benchmark.authored_effect_stage_compile_metrics(
            "effectStageCompileFailureCount: 1\n"
        )
        self.assertIn(
            "effect stage compile summary missing, duplicated, or malformed",
            partial["validation_failures"],
        )

        duplicate = "\n".join([
            "effectStageCompileFailureCount: 1",
            "effectStageCompileFailureCount: 1",
            "effectStageCompileFailureCodes: no-backend-accepted=1",
            "effectStageCompilerProbeOutcomeCounts: rejected=1",
            "effectStageCompilerFailureCodes: "
            "water-flow/compatibility/dedicated-profile-rejected=1",
        ])
        self.assertIn(
            "effect stage compile summary missing, duplicated, or malformed",
            benchmark.authored_effect_stage_compile_metrics(duplicate)[
                "validation_failures"
            ],
        )

        invalid = "\n".join([
            "effectStageCompileFailureCount: 1",
            "effectStageCompileFailureCodes: no-backend-accepted=2",
            "effectStageCompilerProbeOutcomeCounts: "
            "not-applicable=35,rejected=2",
            "effectStageCompilerFailureCodes: "
            "water-flow/compatibility/dedicated-profile-rejected=1",
        ])
        failures = benchmark.authored_effect_stage_compile_metrics(invalid)[
            "validation_failures"
        ]
        self.assertIn("effect stage compile failure count mismatch", failures)
        self.assertIn("effect stage compiler rejection count mismatch", failures)
        self.assertIn("effect stage compiler probe count exceeds bound", failures)

        malformed = "\n".join([
            "effectStageCompileFailureCount: 1",
            "effectStageCompileFailureCodes: unknown-code=1",
            "effectStageCompilerProbeOutcomeCounts: rejected=1",
            "effectStageCompilerFailureCodes: "
            "water-flow/compatibility=1",
        ])
        malformed_failures = benchmark.authored_effect_stage_compile_metrics(
            malformed
        )["validation_failures"]
        self.assertIn(
            "effect stage compile failure code counts malformed",
            malformed_failures,
        )
        self.assertIn(
            "effect stage compile compiler failure code counts malformed",
            malformed_failures,
        )


if __name__ == "__main__":
    unittest.main()

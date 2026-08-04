import copy
import hashlib
import json
import sys
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_ROOT = REPOSITORY_ROOT / "script"
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

import generate_scene_full_matrix as matrix_generator
from scene_matrix_contract import (
    AUTHORED_EFFECT_RUNTIME_EXPECTATIONS,
    EFFECT_EXECUTION_AGGREGATE_KINDS,
    EFFECT_EXECUTION_EXACT_KINDS,
    EFFECT_EXECUTION_EXPECTATIONS,
    EFFECT_EXECUTION_ROUTE_GROUP_KINDS,
    EFFECT_RUNTIME_DISPOSITION_EXPECTATIONS,
    EFFECT_STAGE_ADMISSION_EXPECTATIONS,
    RESOLVED_MATERIAL_GRAPH_BACKEND,
    RESOLVED_MATERIAL_GRAPH_EXPECTATIONS,
    effect_execution_static_demand,
)


def synthetic_result(sample_id: str = "fixture") -> dict[str, object]:
    evidence = defaultdict(int)
    evidence.update({
        metric: 0 for metric in matrix_generator.RUNTIME_EVIDENCE_METRICS
    })
    evidence.update({
        "shader_contract_aggregate_sha256": "a" * 64,
        "effect_graph_sha256": "b" * 64,
        "stock_opacity_single_effect_candidate_layer_ids": [],
    })
    runtime = defaultdict(int)
    runtime["runtime_evidence"] = evidence
    return {
        "id": sample_id,
        "title": "Fixture",
        "package_file": "scene.pkg",
        "hashes": {
            "project_sha256": "c" * 64,
            "package_sha256": "d" * 64,
        },
        "passed": True,
        "runtime": runtime,
    }


def resolved_material_graph_runtime(
    accepted_layer_ids: list[int],
) -> dict[str, object]:
    positive = bool(accepted_layer_ids)
    count = len(accepted_layer_ids)
    return {
        "has_evidence": True,
        "execution_succeeded": positive,
        "zero_contract_succeeded": not positive,
        "contract_succeeded": True,
        "succeeded_layer_ids": list(accepted_layer_ids),
        "capability": {
            "has_evidence": True,
            "accepted_count": count,
            "accepted_layer_ids": list(accepted_layer_ids),
        },
        "executor": {
            "has_evidence": True,
            "claimed_count": count,
            "encoded_count": count,
            "failure_count": 0,
            "deferred_count": 0,
            "pending_max": count,
            "gpu_encoded_count": count,
        },
        "graph_observations": {
            "observation_count": count * 2,
            "successful_gpu_completed_layer_ids": list(accepted_layer_ids),
            "compositor_consumed_layer_ids": list(accepted_layer_ids),
            "next_frame_layer_ids": list(accepted_layer_ids),
        },
        "exact_backend": {
            "backend": RESOLVED_MATERIAL_GRAPH_BACKEND,
            "complete_layer_ids": list(accepted_layer_ids),
            "unexpected_layer_ids": [],
        },
        "layer_routes": {"legacy_conflict_layer_ids": []},
        "validation_failures": [],
    }


def stage_admission_evidence() -> dict[str, object]:
    records = [{
        "layer_id": 1,
        "effect_index": 0,
        "descriptor_id": "1#effect#0",
        "definition_path": "effects/opacity/effect.json",
        "activity": "active",
        "strict_admission": "admitted-dedicated",
        "coverage": "complete",
        "backend": "opacity",
        "profile": None,
        "reason": None,
    }]
    canonical_sha256 = hashlib.sha256(json.dumps(
        records,
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return {
        "has_evidence": True,
        "schema_version": 1,
        "descriptor_count": 1,
        "parsed_count": 1,
        "activity_counts": {
            "author-disabled": 0,
            "layer-hidden": 0,
            "active": 1,
        },
        "strict_admission_counts": {
            "inactive": 0,
            "admitted-dedicated": 1,
            "admitted-generic": 0,
            "not-admitted": 0,
        },
        "coverage_counts": {
            "inactive": 0,
            "complete": 1,
            "terminal-inline-prefix": 0,
            "terminal-inline-suffix": 0,
            "isolated-accepted": 0,
            "isolated-omitted": 0,
            "prefix-accepted": 0,
            "prefix-omitted": 0,
            "rejected-missing-graph": 0,
            "rejected-ambiguous-graph": 0,
            "rejected-chain": 0,
            "rejected-graph-mismatch": 0,
            "rejected-invariant": 0,
        },
        "conservation": {
            "DescriptorIdentity": True,
            "Activity": True,
            "InactiveAdmission": True,
            "ActiveAdmission": True,
            "StrictIdentity": True,
        },
        "records": records,
        "canonical_sha256": canonical_sha256,
        "validation_failures": [],
    }


def runtime_disposition_evidence() -> dict[str, object]:
    records = [{
        "layer_id": 1,
        "effect_index": 0,
        "descriptor_id": "1#effect#0",
        "definition_path": "effects/opacity/effect.json",
        "kind": "strict-dedicated",
        "attribution": "exact-key",
        "family": "opacity",
        "group_id": 1,
        "role": "owner",
        "reason": None,
    }]
    groups = [{
        "layer_id": 1,
        "kind": "authored",
        "effect_count": 1,
        "owner_count": 1,
        "aggregate_contributor_count": 0,
        "reason": None,
    }]
    canonical_sha256 = hashlib.sha256(json.dumps(
        {"groups": groups, "records": records},
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return {
        "has_evidence": True,
        "schema_version": 1,
        "record_count": 1,
        "group_count": 1,
        "kind_counts": {
            "inactive": 0,
            "strict-dedicated": 1,
            "strict-generic": 0,
            "strict-inline-suffix": 0,
            "omitted-by-strict-chain": 0,
            "legacy-exact-inline": 0,
            "legacy-exact-offscreen": 0,
            "legacy-structural-member": 0,
            "legacy-coalesced-inline": 0,
            "legacy-coalesced-offscreen": 0,
            "legacy-shadowed": 0,
            "route-only-member": 0,
            "composite-refused": 0,
            "unsupported": 0,
            "unattributed": 0,
        },
        "attribution_counts": {
            "exact-key": 1,
            "layer-aggregate": 0,
            "none": 0,
        },
        "role_counts": {
            "owner": 1,
            "aggregate-contributor": 0,
            "member": 0,
            "none": 0,
        },
        "group_kind_counts": {
            "inactive": 0,
            "direct": 0,
            "authored": 1,
            "legacy-offscreen": 0,
            "offscreen-passthrough": 0,
            "composite-refused": 0,
        },
        "records": records,
        "groups": groups,
        "canonical_sha256": canonical_sha256,
        "validation_failures": [],
    }


def empty_runtime_disposition_evidence() -> dict[str, object]:
    evidence = runtime_disposition_evidence()
    evidence.update({
        "record_count": 0,
        "group_count": 0,
        "records": [],
        "groups": [],
    })
    for field in (
        "kind_counts",
        "attribution_counts",
        "role_counts",
        "group_kind_counts",
    ):
        evidence[field] = {
            key: 0 for key in evidence[field]
        }
    evidence["canonical_sha256"] = hashlib.sha256(json.dumps(
        {"groups": [], "records": []},
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return evidence


def aggregate_runtime_disposition_evidence() -> dict[str, object]:
    evidence = runtime_disposition_evidence()
    record = evidence["records"][0]
    record.update({
        "kind": "legacy-coalesced-inline",
        "attribution": "layer-aggregate",
        "family": "chromatic-aberration",
        "role": "aggregate-contributor",
    })
    evidence["groups"][0]["kind"] = "direct"
    evidence["groups"][0]["aggregate_contributor_count"] = 1
    evidence["kind_counts"]["strict-dedicated"] = 0
    evidence["kind_counts"]["legacy-coalesced-inline"] = 1
    evidence["attribution_counts"]["exact-key"] = 0
    evidence["attribution_counts"]["layer-aggregate"] = 1
    evidence["role_counts"]["owner"] = 0
    evidence["role_counts"]["aggregate-contributor"] = 1
    evidence["group_kind_counts"]["authored"] = 0
    evidence["group_kind_counts"]["direct"] = 1
    evidence["canonical_sha256"] = hashlib.sha256(json.dumps(
        {
            "groups": evidence["groups"],
            "records": evidence["records"],
        },
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return evidence


def route_demand_runtime_disposition_evidence(
    group_kind: str = "offscreen-passthrough",
) -> dict[str, object]:
    evidence = empty_runtime_disposition_evidence()
    is_route_only = group_kind == "offscreen-passthrough"
    record_kind = "route-only-member" if is_route_only else "unsupported"
    record = {
        "layer_id": 1,
        "effect_index": 0,
        "descriptor_id": "1#effect#0",
        "definition_path": "effects/route/effect.json",
        "kind": record_kind,
        "attribution": "exact-key" if is_route_only else "none",
        "family": "declared-multipass" if is_route_only else "unknown",
        "group_id": 1,
        "role": "member",
        "reason": "capture-or-neutral-copy-only" if is_route_only else None,
    }
    group = {
        "layer_id": 1,
        "kind": group_kind,
        "effect_count": 1,
        "owner_count": 0,
        "aggregate_contributor_count": 0,
        "reason": None,
    }
    evidence.update({
        "record_count": 1,
        "group_count": 1,
        "records": [record],
        "groups": [group],
    })
    evidence["kind_counts"][record_kind] = 1
    evidence["attribution_counts"][record["attribution"]] = 1
    evidence["role_counts"]["member"] = 1
    evidence["group_kind_counts"][group_kind] = 1
    evidence["canonical_sha256"] = hashlib.sha256(json.dumps(
        {"groups": [group], "records": [record]},
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return evidence


def inactive_runtime_disposition_evidence() -> dict[str, object]:
    evidence = empty_runtime_disposition_evidence()
    record = {
        "layer_id": 1,
        "effect_index": 0,
        "descriptor_id": "1#effect#0",
        "definition_path": "effects/disabled/effect.json",
        "kind": "inactive",
        "attribution": "none",
        "family": None,
        "group_id": None,
        "role": "none",
        "reason": "author-disabled",
    }
    group = {
        "layer_id": 1,
        "kind": "inactive",
        "effect_count": 0,
        "owner_count": 0,
        "aggregate_contributor_count": 0,
        "reason": "no-active-effect",
    }
    evidence.update({
        "record_count": 1,
        "group_count": 1,
        "records": [record],
        "groups": [group],
    })
    evidence["kind_counts"]["inactive"] = 1
    evidence["attribution_counts"]["none"] = 1
    evidence["role_counts"]["none"] = 1
    evidence["group_kind_counts"]["inactive"] = 1
    evidence["canonical_sha256"] = hashlib.sha256(json.dumps(
        {"groups": [group], "records": [record]},
        ensure_ascii=True,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return evidence


def effect_execution_evidence(
    *,
    eligible_exact: int = 1,
    observed_exact: int = 1,
    eligible_aggregate: int = 0,
    observed_aggregate: int = 0,
    route_count: int = 0,
) -> dict[str, object]:
    cpu_count = observed_exact + observed_aggregate
    has_transitions = cpu_count > 0 or route_count > 0
    return {
        "has_evidence": True,
        "schema_version": 1,
        "axis_evidence": {
            "cpu_invocation": cpu_count > 0,
            "route_operation": route_count > 0,
            "frame_command_buffer": has_transitions,
        },
        "cpu_invocation_count": cpu_count,
        "route_operation_count": route_count,
        "cpu_invocations": [
            {"outcome": "encoded-output"} for _ in range(cpu_count)
        ],
        "route_operations": [
            {"outcome": "encoded"} for _ in range(route_count)
        ],
        "succeeded_exact_effects": [{} for _ in range(observed_exact)],
        "succeeded_aggregates": [{} for _ in range(observed_aggregate)],
        "encoded_route_operations": [{} for _ in range(route_count)],
        "failed_exact_effects": [],
        "failed_aggregates": [],
        "failed_route_operations": [],
        "completed_frame_ids": [17] if has_transitions else [],
        "failed_frame_ids": [],
        "eligible_exact_effect_count": eligible_exact,
        "observed_eligible_exact_effect_count": observed_exact,
        "eligible_exact_gap_count": eligible_exact - observed_exact,
        "eligible_aggregate_subject_count": eligible_aggregate,
        "observed_eligible_aggregate_subject_count": observed_aggregate,
        "eligible_aggregate_gap_count": (
            eligible_aggregate - observed_aggregate
        ),
        "canonical_sha256": "frame-dependent-and-not-registered",
        "validation_failures": [],
    }


def benchmark_report(
    old_matrix: dict[str, object],
    matrix_path: Path,
    results: list[dict[str, object]],
) -> dict[str, object]:
    passed_count = sum(result.get("passed") is True for result in results)
    return {
        "schema_version": 2,
        "matrix": old_matrix["name"],
        "matrix_path": str(matrix_path.resolve()),
        "matrix_sha256": matrix_generator.sha256(matrix_path),
        "summary": {
            "passed": passed_count == len(results),
            "sample_count": len(results),
            "passed_count": passed_count,
        },
        "samples": results,
    }


class SceneMatrixContractTests(unittest.TestCase):
    def test_authored_effect_registry_has_unique_keys_and_metrics(self) -> None:
        matrix_keys = [
            expectation.matrix_key
            for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        ]
        benchmark_metrics = [
            expectation.benchmark_metric
            for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        ]
        self.assertEqual(len(matrix_keys), len(set(matrix_keys)))
        self.assertEqual(len(benchmark_metrics), len(set(benchmark_metrics)))

    def test_effect_stage_registry_has_unique_keys_and_paths(self) -> None:
        matrix_keys = [
            expectation.matrix_key
            for expectation in EFFECT_STAGE_ADMISSION_EXPECTATIONS
        ]
        report_paths = [
            expectation.report_path
            for expectation in EFFECT_STAGE_ADMISSION_EXPECTATIONS
        ]
        self.assertEqual(len(matrix_keys), len(set(matrix_keys)))
        self.assertEqual(len(report_paths), len(set(report_paths)))
        self.assertTrue(all(path[:2] == (
            "runtime", "authored_effect_stage_admission"
        ) for path in report_paths))

    def test_effect_runtime_disposition_registry_has_unique_keys_and_paths(
        self,
    ) -> None:
        matrix_keys = [
            expectation.matrix_key
            for expectation in EFFECT_RUNTIME_DISPOSITION_EXPECTATIONS
        ]
        report_paths = [
            expectation.report_path
            for expectation in EFFECT_RUNTIME_DISPOSITION_EXPECTATIONS
        ]
        self.assertEqual(len(matrix_keys), len(set(matrix_keys)))
        self.assertEqual(len(report_paths), len(set(report_paths)))
        self.assertTrue(all(path[:2] == (
            "runtime", "effect_runtime_disposition"
        ) for path in report_paths))
        self.assertEqual(matrix_keys, [
            "expected_effect_runtime_disposition_schema",
            "expected_effect_runtime_disposition_record_count",
            "expected_effect_runtime_disposition_group_count",
            "expected_effect_runtime_disposition_kind_counts",
            "expected_effect_runtime_disposition_attribution_counts",
            "expected_effect_runtime_disposition_role_counts",
            "expected_effect_runtime_disposition_group_kind_counts",
            "expected_effect_runtime_disposition_sha256",
        ])

    def test_effect_execution_registry_is_minimal_and_frame_independent(
        self,
    ) -> None:
        matrix_keys = [
            expectation.matrix_key
            for expectation in EFFECT_EXECUTION_EXPECTATIONS
        ]
        report_paths = [
            expectation.report_path
            for expectation in EFFECT_EXECUTION_EXPECTATIONS
        ]
        self.assertEqual(len(matrix_keys), len(set(matrix_keys)))
        self.assertEqual(len(report_paths), len(set(report_paths)))
        self.assertTrue(all(path[:2] == (
            "runtime", "effect_execution"
        ) for path in report_paths))
        self.assertEqual(matrix_keys, [
            "expected_effect_execution_schema",
            "expected_effect_execution_eligible_exact_effect_count",
            "expected_effect_execution_observed_eligible_exact_effect_count",
            "expected_effect_execution_eligible_exact_gap_count",
            "expected_effect_execution_eligible_aggregate_subject_count",
            (
                "expected_effect_execution_"
                "observed_eligible_aggregate_subject_count"
            ),
            "expected_effect_execution_eligible_aggregate_gap_count",
        ])
        joined = " ".join(matrix_keys)
        for excluded in (
            "cpu_invocation_count",
            "route_operation_count",
            "frame",
            "canonical_sha256",
        ):
            self.assertNotIn(excluded, joined)

    def test_resolved_material_graph_registry_tracks_only_succeeded_layers(
        self,
    ) -> None:
        self.assertEqual(len(RESOLVED_MATERIAL_GRAPH_EXPECTATIONS), 1)
        expectation = RESOLVED_MATERIAL_GRAPH_EXPECTATIONS[0]
        self.assertEqual(
            expectation.matrix_key,
            "expected_resolved_material_graph_succeeded_layer_ids",
        )
        self.assertEqual(expectation.report_path, (
            "runtime",
            "resolved_material_graph_execution",
            "succeeded_layer_ids",
        ))
        self.assertEqual(expectation.comparison, "sorted_list")

    def test_resolved_material_graph_matrix_accepts_positive_and_zero_contracts(
        self,
    ) -> None:
        expectation_key = RESOLVED_MATERIAL_GRAPH_EXPECTATIONS[0].matrix_key
        for accepted_layer_ids in ([20], []):
            with self.subTest(accepted_layer_ids=accepted_layer_ids):
                result = synthetic_result()
                result["runtime"]["resolved_material_graph_execution"] = (
                    resolved_material_graph_runtime(accepted_layer_ids)
                )
                self.assertEqual(
                    matrix_generator.resolved_material_graph_execution_values(
                        result,
                        {expectation_key: accepted_layer_ids},
                    ),
                    {expectation_key: accepted_layer_ids},
                )
                refreshed = matrix_generator.matrix_sample(
                    result,
                    {
                        "id": "fixture",
                        "project_sha256": "c" * 64,
                        "package_sha256": "d" * 64,
                        expectation_key: [],
                    },
                )
                self.assertEqual(refreshed[expectation_key], accepted_layer_ids)

    def test_resolved_material_graph_matrix_rejects_false_success_and_zero_activity(
        self,
    ) -> None:
        positive = synthetic_result()
        positive_execution = resolved_material_graph_runtime([20])
        positive_execution["graph_observations"]["next_frame_layer_ids"] = []
        positive["runtime"]["resolved_material_graph_execution"] = positive_execution
        with self.assertRaisesRegex(ValueError, "success intersection invalid"):
            matrix_generator.resolved_material_graph_execution_values(positive)

        zero = synthetic_result()
        zero_execution = resolved_material_graph_runtime([])
        zero_execution["executor"]["claimed_count"] = 1
        zero["runtime"]["resolved_material_graph_execution"] = zero_execution
        with self.assertRaisesRegex(ValueError, "zero contract invalid"):
            matrix_generator.resolved_material_graph_execution_values(zero)

    def test_effect_execution_static_demand_is_shared_and_fail_closed(
        self,
    ) -> None:
        empty = effect_execution_static_demand(
            empty_runtime_disposition_evidence()
        )
        self.assertTrue(empty.static_is_valid)
        self.assertFalse(empty.has_demand)
        self.assertFalse(empty.requires_evidence)

        inactive = empty_runtime_disposition_evidence()
        inactive["groups"] = [{"layer_id": 1, "kind": "inactive"}]
        inactive["group_count"] = 1
        inactive_demand = effect_execution_static_demand(inactive)
        self.assertTrue(inactive_demand.static_is_valid)
        self.assertFalse(inactive_demand.has_demand)

        exact = effect_execution_static_demand(runtime_disposition_evidence())
        self.assertEqual(exact.eligible_exact_effect_count, 1)
        self.assertEqual(exact.eligible_aggregate_subject_count, 0)
        self.assertEqual(exact.route_group_count, 1)
        self.assertTrue(exact.requires_evidence)

        aggregate = effect_execution_static_demand(
            aggregate_runtime_disposition_evidence()
        )
        self.assertEqual(aggregate.eligible_exact_effect_count, 0)
        self.assertEqual(aggregate.eligible_aggregate_subject_count, 1)
        self.assertEqual(aggregate.route_group_count, 1)

        self.assertEqual(EFFECT_EXECUTION_EXACT_KINDS, frozenset({
            "strict-dedicated",
            "strict-generic",
            "strict-inline-suffix",
            "legacy-exact-inline",
            "legacy-exact-offscreen",
        }))
        self.assertEqual(EFFECT_EXECUTION_AGGREGATE_KINDS, frozenset({
            "legacy-coalesced-inline",
            "legacy-coalesced-offscreen",
        }))
        for kind in EFFECT_EXECUTION_ROUTE_GROUP_KINDS:
            disposition = empty_runtime_disposition_evidence()
            disposition["groups"] = [{"layer_id": 1, "kind": kind}]
            disposition["group_count"] = 1
            with self.subTest(route_group_kind=kind):
                self.assertTrue(
                    effect_execution_static_demand(disposition).has_demand
                )

        self.assertTrue(
            effect_execution_static_demand(None).requires_evidence
        )
        invalid = empty_runtime_disposition_evidence()
        invalid["validation_failures"] = ["broken"]
        self.assertTrue(
            effect_execution_static_demand(invalid).requires_evidence
        )

    def test_tracked_matrices_have_no_unclassified_sample_keys(self) -> None:
        nested_expectation_keys = {
            expectation.matrix_key
            for expectations in (
                EFFECT_STAGE_ADMISSION_EXPECTATIONS,
                EFFECT_RUNTIME_DISPOSITION_EXPECTATIONS,
                EFFECT_EXECUTION_EXPECTATIONS,
                RESOLVED_MATERIAL_GRAPH_EXPECTATIONS,
            )
            for expectation in expectations
        }
        for relative_path in (
            "script/scene_wallpaper_sample_matrix.json",
            "script/scene_wallpaper_full_sample_matrix.json",
        ):
            matrix = json.loads((REPOSITORY_ROOT / relative_path).read_text())
            for old_sample in matrix["samples"]:
                with self.subTest(matrix=relative_path, sample=old_sample["id"]):
                    old_without_nested = {
                        key: value for key, value in old_sample.items()
                        if key not in nested_expectation_keys
                    }
                    refreshed = matrix_generator.matrix_sample(
                        synthetic_result(old_sample["id"]),
                        old_without_nested,
                    )
                    self.assertEqual(
                        set(old_sample) - {"package_file"} - nested_expectation_keys,
                        set(old_sample).intersection(refreshed),
                    )

    def test_unknown_matrix_key_fails_closed(self) -> None:
        with self.assertRaisesRegex(
            ValueError,
            "unclassified matrix keys: expected_new_runtime_contract",
        ):
            matrix_generator.matrix_sample(
                synthetic_result(),
                {"expected_new_runtime_contract": 1},
            )

    def test_optional_runtime_contract_is_refreshed_when_already_tracked(
        self,
    ) -> None:
        result = synthetic_result()
        runtime = result["runtime"]
        runtime["particle_refract_loaded"] = 3
        runtime["particle_skipped_transparent"] = 2
        runtime["text_script_binding_count"] = 1
        runtime["text_script_binding_layer_ids"] = [42]
        runtime["time_of_day_effect_script_binding_count"] = 1
        runtime["time_of_day_effect_script_bindings"] = [{
            "layer_id": 42,
            "effect_index": 0,
            "pass_index": 0,
            "constant": "multiply",
        }]
        sample = matrix_generator.matrix_sample(
            result,
            {
                "expected_particle_refract_loaded": 0,
                "expected_particle_skipped_transparent": 0,
                "expected_text_script_binding_count": 0,
                "required_text_script_binding_layer_ids": [],
                "expected_time_of_day_effect_script_binding_count": 0,
                "required_time_of_day_effect_script_bindings": [],
            },
        )
        self.assertEqual(sample["expected_particle_refract_loaded"], 3)
        self.assertEqual(sample["expected_particle_skipped_transparent"], 2)
        self.assertEqual(sample["expected_text_script_binding_count"], 1)
        self.assertEqual(
            sample["required_text_script_binding_layer_ids"],
            [42],
        )
        self.assertEqual(
            sample["expected_time_of_day_effect_script_binding_count"], 1
        )
        self.assertEqual(
            sample["required_time_of_day_effect_script_bindings"],
            runtime["time_of_day_effect_script_bindings"],
        )

    def test_puppet_animation_contract_is_refreshed_when_tracked(self) -> None:
        result = synthetic_result()
        runtime = result["runtime"]
        runtime["puppet_animation_layer_ids"] = [21, 44]
        runtime["puppet_disjoint_additive_layer_ids"] = [21]
        runtime["puppet_animation_clip_count"] = 3
        sample = matrix_generator.matrix_sample(
            result,
            {
                "expected_puppet_animation_layer_ids": [],
                "expected_puppet_disjoint_additive_layer_ids": [],
                "expected_puppet_animation_clip_count": 0,
            },
        )
        self.assertEqual(sample["expected_puppet_animation_layer_ids"], [21, 44])
        self.assertEqual(sample["expected_puppet_disjoint_additive_layer_ids"], [21])
        self.assertEqual(sample["expected_puppet_animation_clip_count"], 3)

    def test_stage_scoped_refresh_changes_only_registered_family(self) -> None:
        result = synthetic_result()
        result["passed"] = False
        result["runtime"]["authored_effect_stage_admission"] = (
            stage_admission_evidence()
        )
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [{
                "id": "fixture",
                "title": "Fixture",
                "capabilities": ["particle_layers"],
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
                "expected_particle_candidates": 1,
                "expected_particle_skipped_transparent": 1,
            }],
        }
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = {
                "schema_version": 2,
                "matrix": old_matrix["name"],
                "matrix_path": str(matrix_path.resolve()),
                "matrix_sha256": matrix_generator.sha256(matrix_path),
                "summary": {
                    "passed": False,
                    "sample_count": 1,
                    "passed_count": 0,
                },
                "samples": [result],
            }
            refreshed = matrix_generator.scoped_effect_stage_admission_matrix(
                report,
                old_matrix,
                matrix_path,
            )

        expected_values = matrix_generator.effect_stage_admission_values(result)
        self.assertEqual(
            {
                key: refreshed["samples"][0][key]
                for key in expected_values
            },
            expected_values,
        )
        stripped = copy.deepcopy(refreshed)
        for key in expected_values:
            stripped["samples"][0].pop(key)
        self.assertEqual(stripped, old_matrix)

    def test_r0_effect_ledgers_scope_updates_both_families_only(self) -> None:
        result = synthetic_result()
        result["passed"] = False
        result["runtime"]["authored_effect_stage_admission"] = (
            stage_admission_evidence()
        )
        result["runtime"]["effect_runtime_disposition"] = (
            runtime_disposition_evidence()
        )
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [{
                "id": "fixture",
                "title": "Fixture",
                "capabilities": ["particle_layers"],
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
                "expected_particle_candidates": 1,
                "required_utility_dispositions": ["capture"],
                **{
                    expectation.matrix_key: (
                        1 if expectation.metric_key == "schema_version" else 0
                    )
                    for expectation in EFFECT_EXECUTION_EXPECTATIONS
                },
            }],
        }
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = {
                "schema_version": 2,
                "matrix": old_matrix["name"],
                "matrix_path": str(matrix_path.resolve()),
                "matrix_sha256": matrix_generator.sha256(matrix_path),
                "summary": {
                    "passed": False,
                    "sample_count": 1,
                    "passed_count": 0,
                },
                "samples": [result],
            }
            refreshed = matrix_generator.scoped_r0_effect_ledgers_matrix(
                report,
                old_matrix,
                matrix_path,
            )

        expected_values = matrix_generator.effect_stage_admission_values(result)
        expected_values.update(
            matrix_generator.effect_runtime_disposition_values(result)
        )
        self.assertEqual(
            {
                key: refreshed["samples"][0][key]
                for key in expected_values
            },
            expected_values,
        )
        stripped = copy.deepcopy(refreshed)
        for key in expected_values:
            stripped["samples"][0].pop(key)
        self.assertEqual(stripped, old_matrix)

    def test_r0_effect_chain_scope_updates_three_families_only(self) -> None:
        result = synthetic_result()
        result["passed"] = False
        result["runtime"]["authored_effect_stage_admission"] = (
            stage_admission_evidence()
        )
        result["runtime"]["effect_runtime_disposition"] = (
            runtime_disposition_evidence()
        )
        result["runtime"]["effect_execution"] = effect_execution_evidence()
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [{
                "id": "fixture",
                "title": "Fixture",
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
                "expected_particle_candidates": 9,
                "required_utility_dispositions": ["capture"],
            }],
        }
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = benchmark_report(old_matrix, matrix_path, [result])
            refreshed = matrix_generator.scoped_r0_effect_chain_matrix(
                report,
                old_matrix,
                matrix_path,
            )

        expected_values = matrix_generator.effect_stage_admission_values(result)
        expected_values.update(
            matrix_generator.effect_runtime_disposition_values(result)
        )
        expected_values.update(
            matrix_generator.effect_execution_values(result, old_matrix["samples"][0])
        )
        self.assertEqual(
            {
                key: refreshed["samples"][0][key]
                for key in expected_values
            },
            expected_values,
        )
        self.assertNotIn(
            "expected_effect_execution_canonical_sha256",
            refreshed["samples"][0],
        )
        stripped = copy.deepcopy(refreshed)
        for key in expected_values:
            stripped["samples"][0].pop(key)
        self.assertEqual(stripped, old_matrix)

    def test_effect_execution_zero_eligible_is_optional_until_tracked(self) -> None:
        result = synthetic_result()
        result["runtime"]["authored_effect_stage_admission"] = (
            stage_admission_evidence()
        )
        result["runtime"]["effect_runtime_disposition"] = (
            empty_runtime_disposition_evidence()
        )
        self.assertIsNone(matrix_generator.effect_execution_values(result))

        inactive_result = synthetic_result()
        inactive_result["runtime"]["effect_runtime_disposition"] = (
            inactive_runtime_disposition_evidence()
        )
        self.assertIsNone(
            matrix_generator.effect_execution_values(inactive_result)
        )

        old_sample = {
            expectation.matrix_key: 0
            for expectation in EFFECT_EXECUTION_EXPECTATIONS
        }
        old_sample["expected_effect_execution_schema"] = 1
        self.assertIsNone(
            matrix_generator.effect_execution_values(result, old_sample)
        )

        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [{
                "id": "fixture",
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
                **old_sample,
            }],
        }
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = benchmark_report(old_matrix, matrix_path, [result])
            refreshed = matrix_generator.scoped_r0_effect_chain_matrix(
                report,
                old_matrix,
                matrix_path,
            )
        execution_keys = {
            expectation.matrix_key
            for expectation in EFFECT_EXECUTION_EXPECTATIONS
        }
        self.assertFalse(
            execution_keys.intersection(refreshed["samples"][0])
        )
        default_refreshed = matrix_generator.matrix_sample(
            result,
            old_matrix["samples"][0],
        )
        self.assertFalse(execution_keys.intersection(default_refreshed))

    def test_effect_execution_route_demand_requires_and_registers_evidence(
        self,
    ) -> None:
        for group_kind in (
            "direct",
            "authored",
            "legacy-offscreen",
            "offscreen-passthrough",
            "composite-refused",
        ):
            with self.subTest(group_kind=group_kind):
                result = synthetic_result()
                result["runtime"]["effect_runtime_disposition"] = (
                    route_demand_runtime_disposition_evidence(group_kind)
                )
                with self.assertRaisesRegex(
                    ValueError,
                    "effect execution evidence missing",
                ):
                    matrix_generator.effect_execution_values(result)

                result["runtime"]["effect_execution"] = (
                    effect_execution_evidence(
                        eligible_exact=0,
                        observed_exact=0,
                        route_count=1,
                    )
                )
                values = matrix_generator.effect_execution_values(result)
                self.assertEqual(
                    values["expected_effect_execution_schema"],
                    1,
                )
                self.assertTrue(all(
                    value == 0
                    for key, value in values.items()
                    if key != "expected_effect_execution_schema"
                ))

    def test_effect_execution_partial_matrix_family_fails_closed(self) -> None:
        result = synthetic_result()
        result["runtime"]["effect_runtime_disposition"] = (
            runtime_disposition_evidence()
        )
        result["runtime"]["effect_execution"] = effect_execution_evidence()
        with self.assertRaisesRegex(ValueError, "matrix contract incomplete"):
            matrix_generator.effect_execution_values(
                result,
                {"expected_effect_execution_schema": 1},
            )

    def test_r0_effect_chain_scope_is_atomic_on_dynamic_failure(self) -> None:
        results = []
        old_samples = []
        for sample_id in ("a", "b"):
            result = synthetic_result(sample_id)
            result["runtime"]["authored_effect_stage_admission"] = (
                stage_admission_evidence()
            )
            result["runtime"]["effect_runtime_disposition"] = (
                runtime_disposition_evidence()
            )
            result["runtime"]["effect_execution"] = effect_execution_evidence()
            results.append(result)
            old_samples.append({
                "id": sample_id,
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
            })
        results[1]["runtime"]["effect_execution"]["failed_frame_ids"] = [19]
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": old_samples,
        }
        original = copy.deepcopy(old_matrix)
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = benchmark_report(old_matrix, matrix_path, results)
            with self.assertRaisesRegex(ValueError, "failure observed"):
                matrix_generator.scoped_r0_effect_chain_matrix(
                    report,
                    old_matrix,
                    matrix_path,
                )
        self.assertEqual(old_matrix, original)

    def test_r0_effect_chain_scope_rejects_targeted_subset(self) -> None:
        result = synthetic_result("a")
        result["runtime"]["authored_effect_stage_admission"] = (
            stage_admission_evidence()
        )
        result["runtime"]["effect_runtime_disposition"] = (
            runtime_disposition_evidence()
        )
        result["runtime"]["effect_execution"] = effect_execution_evidence()
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [
                {
                    "id": sample_id,
                    "project_sha256": "c" * 64,
                    "package_sha256": "d" * 64,
                }
                for sample_id in ("a", "b")
            ],
        }
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = benchmark_report(old_matrix, matrix_path, [result])
            with self.assertRaisesRegex(ValueError, "sample IDs differ"):
                matrix_generator.scoped_r0_effect_chain_matrix(
                    report,
                    old_matrix,
                    matrix_path,
                )

    def test_r0_effect_chain_scope_rejects_package_identity_drift(self) -> None:
        result = synthetic_result()
        result["runtime"]["authored_effect_stage_admission"] = (
            stage_admission_evidence()
        )
        result["runtime"]["effect_runtime_disposition"] = (
            runtime_disposition_evidence()
        )
        result["runtime"]["effect_execution"] = effect_execution_evidence()
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [{
                "id": "fixture",
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
                "package_file": "alternate.pkg",
            }],
        }
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = benchmark_report(old_matrix, matrix_path, [result])
            with self.assertRaisesRegex(ValueError, "package file mismatch"):
                matrix_generator.scoped_r0_effect_chain_matrix(
                    report,
                    old_matrix,
                    matrix_path,
                )

    def test_stage_scope_remains_independent_from_runtime_disposition(
        self,
    ) -> None:
        result = synthetic_result()
        result["runtime"]["authored_effect_stage_admission"] = (
            stage_admission_evidence()
        )
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [{
                "id": "fixture",
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
                "expected_effect_runtime_disposition_schema": 99,
            }],
        }
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = {
                "schema_version": 2,
                "matrix": old_matrix["name"],
                "matrix_path": str(matrix_path.resolve()),
                "matrix_sha256": matrix_generator.sha256(matrix_path),
                "summary": {
                    "passed": True,
                    "sample_count": 1,
                    "passed_count": 1,
                },
                "samples": [result],
            }
            refreshed = matrix_generator.scoped_effect_stage_admission_matrix(
                report,
                old_matrix,
                matrix_path,
            )

        self.assertEqual(
            refreshed["samples"][0][
                "expected_effect_runtime_disposition_schema"
            ],
            99,
        )

    def test_r0_effect_ledgers_scope_requires_both_nested_evidence(self) -> None:
        result = synthetic_result()
        result["runtime"]["authored_effect_stage_admission"] = (
            stage_admission_evidence()
        )
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [{
                "id": "fixture",
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
            }],
        }
        original = copy.deepcopy(old_matrix)
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = {
                "schema_version": 2,
                "matrix": old_matrix["name"],
                "matrix_path": str(matrix_path.resolve()),
                "matrix_sha256": matrix_generator.sha256(matrix_path),
                "summary": {
                    "passed": True,
                    "sample_count": 1,
                    "passed_count": 1,
                },
                "samples": [result],
            }
            with self.assertRaisesRegex(
                ValueError,
                "effect runtime disposition evidence missing",
            ):
                matrix_generator.scoped_r0_effect_ledgers_matrix(
                    report,
                    old_matrix,
                    matrix_path,
                )
        self.assertEqual(old_matrix, original)

    def test_old_matrix_without_effect_ledgers_remains_compatible(self) -> None:
        sample = matrix_generator.matrix_sample(
            synthetic_result(),
            {
                "id": "fixture",
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
            },
        )
        registered_keys = {
            expectation.matrix_key
            for expectation in (
                *EFFECT_STAGE_ADMISSION_EXPECTATIONS,
                *EFFECT_RUNTIME_DISPOSITION_EXPECTATIONS,
                *EFFECT_EXECUTION_EXPECTATIONS,
                *RESOLVED_MATERIAL_GRAPH_EXPECTATIONS,
            )
        }
        self.assertFalse(registered_keys.intersection(sample))

    def test_default_refresh_rejects_failed_report(self) -> None:
        result = synthetic_result()
        result["passed"] = False
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [{
                "id": "fixture",
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
            }],
        }
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            report = {
                "schema_version": 2,
                "matrix": old_matrix["name"],
                "matrix_path": str(matrix_path.resolve()),
                "matrix_sha256": matrix_generator.sha256(matrix_path),
                "summary": {
                    "passed": False,
                    "sample_count": 1,
                    "passed_count": 0,
                },
                "samples": [result],
            }
            with self.assertRaisesRegex(
                ValueError,
                "requires a passing benchmark report",
            ):
                matrix_generator.validate_report_identity(
                    report,
                    old_matrix,
                    matrix_path,
                    require_passed=True,
                )

    def test_scoped_refresh_rejects_identity_drift(self) -> None:
        result = synthetic_result()
        result["runtime"]["authored_effect_stage_admission"] = (
            stage_admission_evidence()
        )
        old_matrix = {
            "schema_version": 1,
            "name": "fixture-matrix",
            "samples": [{
                "id": "fixture",
                "project_sha256": "c" * 64,
                "package_sha256": "d" * 64,
            }],
        }
        with tempfile.TemporaryDirectory() as temporary:
            matrix_path = Path(temporary) / "matrix.json"
            matrix_path.write_text(json.dumps(old_matrix))
            base_report = {
                "schema_version": 2,
                "matrix": old_matrix["name"],
                "matrix_path": str(matrix_path.resolve()),
                "matrix_sha256": matrix_generator.sha256(matrix_path),
                "summary": {
                    "passed": True,
                    "sample_count": 1,
                    "passed_count": 1,
                },
                "samples": [result],
            }
            cases = {
                "matrix sha256 mismatch": {"matrix_sha256": "0" * 64},
                "sample IDs differ": {"samples": []},
            }
            for message, changes in cases.items():
                with self.subTest(message=message):
                    report = copy.deepcopy(base_report)
                    report.update(changes)
                    if not report["samples"]:
                        report["summary"] = {
                            "passed": True,
                            "sample_count": 0,
                            "passed_count": 0,
                        }
                    with self.assertRaisesRegex(ValueError, message):
                        matrix_generator.scoped_effect_stage_admission_matrix(
                            report,
                            old_matrix,
                            matrix_path,
                        )

            hash_drift = copy.deepcopy(base_report)
            hash_drift["samples"][0]["hashes"]["project_sha256"] = "e" * 64
            with self.assertRaisesRegex(ValueError, "source hashes mismatch"):
                matrix_generator.scoped_effect_stage_admission_matrix(
                    hash_drift,
                    old_matrix,
                    matrix_path,
                )

    def test_stage_scoped_refresh_rejects_invalid_nested_evidence(self) -> None:
        result = synthetic_result()
        evidence = stage_admission_evidence()
        evidence["schema_version"] = None
        result["runtime"]["authored_effect_stage_admission"] = evidence
        with self.assertRaisesRegex(ValueError, "schema mismatch"):
            matrix_generator.effect_stage_admission_values(result)

    def test_runtime_disposition_rejects_invalid_nested_evidence(self) -> None:
        cases = {
            "schema mismatch": lambda evidence: evidence.update({
                "schema_version": None,
            }),
            "kind_counts invalid": lambda evidence: evidence[
                "kind_counts"
            ].update({"strict-dedicated": 2}),
            "sha256 invalid": lambda evidence: evidence.update({
                "canonical_sha256": "0" * 64,
            }),
        }
        for message, mutate in cases.items():
            with self.subTest(message=message):
                result = synthetic_result()
                evidence = runtime_disposition_evidence()
                mutate(evidence)
                result["runtime"]["effect_runtime_disposition"] = evidence
                with self.assertRaisesRegex(ValueError, message):
                    matrix_generator.effect_runtime_disposition_values(result)

    def test_effect_execution_rejects_invalid_nested_evidence(self) -> None:
        cases = {
            "schema mismatch": lambda evidence: evidence.update({
                "schema_version": None,
            }),
            "validation failed": lambda evidence: evidence[
                "validation_failures"
            ].append("bad join"),
            "static eligibility mismatch": lambda evidence: evidence.update({
                "eligible_exact_effect_count": 2,
                "eligible_exact_gap_count": 1,
            }),
            "exact conservation invalid": lambda evidence: evidence.update({
                "eligible_exact_gap_count": 1,
            }),
            "transition summary invalid": lambda evidence: evidence.update({
                "cpu_invocations": [],
            }),
            "completed frame missing": lambda evidence: evidence.update({
                "completed_frame_ids": [],
                "axis_evidence": {
                    "cpu_invocation": True,
                    "route_operation": False,
                    "frame_command_buffer": False,
                },
            }),
        }
        for message, mutate in cases.items():
            with self.subTest(message=message):
                result = synthetic_result()
                result["runtime"]["effect_runtime_disposition"] = (
                    runtime_disposition_evidence()
                )
                evidence = effect_execution_evidence()
                mutate(evidence)
                result["runtime"]["effect_execution"] = evidence
                with self.assertRaisesRegex(ValueError, message):
                    matrix_generator.effect_execution_values(result)

    def test_effect_execution_rejects_each_sticky_failure_axis(self) -> None:
        for field in (
            "failed_exact_effects",
            "failed_aggregates",
            "failed_route_operations",
            "failed_frame_ids",
        ):
            with self.subTest(field=field):
                result = synthetic_result()
                result["runtime"]["effect_runtime_disposition"] = (
                    runtime_disposition_evidence()
                )
                evidence = effect_execution_evidence()
                evidence[field] = [23] if field == "failed_frame_ids" else [{}]
                result["runtime"]["effect_execution"] = evidence
                with self.assertRaisesRegex(ValueError, "failure observed"):
                    matrix_generator.effect_execution_values(result)

        result = synthetic_result()
        result["runtime"]["effect_runtime_disposition"] = (
            runtime_disposition_evidence()
        )
        evidence = effect_execution_evidence()
        evidence["cpu_invocations"][0]["outcome"] = "failed"
        result["runtime"]["effect_execution"] = evidence
        with self.assertRaisesRegex(ValueError, "failure observed"):
            matrix_generator.effect_execution_values(result)

    def test_effect_execution_enforces_aggregate_conservation(self) -> None:
        result = synthetic_result()
        result["runtime"]["effect_runtime_disposition"] = (
            aggregate_runtime_disposition_evidence()
        )
        evidence = effect_execution_evidence(
            eligible_exact=0,
            observed_exact=0,
            eligible_aggregate=1,
            observed_aggregate=1,
        )
        evidence["eligible_aggregate_gap_count"] = 1
        result["runtime"]["effect_execution"] = evidence
        with self.assertRaisesRegex(ValueError, "aggregate conservation invalid"):
            matrix_generator.effect_execution_values(result)

    def test_effect_execution_matrix_values_ignore_frame_and_canonical_hash(
        self,
    ) -> None:
        first = synthetic_result()
        first["runtime"]["effect_runtime_disposition"] = (
            runtime_disposition_evidence()
        )
        first["runtime"]["effect_execution"] = effect_execution_evidence()
        second = copy.deepcopy(first)
        second["runtime"]["effect_execution"]["completed_frame_ids"] = [991]
        second["runtime"]["effect_execution"]["canonical_sha256"] = "other"
        self.assertEqual(
            matrix_generator.effect_execution_values(first),
            matrix_generator.effect_execution_values(second),
        )


if __name__ == "__main__":
    unittest.main()

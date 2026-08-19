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
from scene_matrix_suite import load_scene_matrix
from scene_matrix_contract import (
    AUTHORED_EFFECT_RUNTIME_EXPECTATIONS,
    EFFECT_EXECUTION_EXACT_KINDS,
    EFFECT_EXECUTION_EXPECTATIONS,
    RESOLVED_MATERIAL_GRAPH_BACKEND,
    RESOLVED_MATERIAL_GRAPH_EXPECTATIONS,
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
        "failures": [],
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
        "layer_routes": {},
        "validation_failures": [],
    }


def runtime_disposition_evidence() -> dict[str, object]:
    records = [{
        "layer_id": 1,
        "effect_index": 0,
        "descriptor_id": "1#effect#0",
        "definition_path": "effects/blur/effect.json",
        "kind": "dedicated",
        "attribution": "exact-key",
        "family": "standard-blur",
        "group_id": 1,
        "role": "owner",
        "reason": None,
    }]
    groups = [{
        "layer_id": 1,
        "kind": "resolved",
        "effect_count": 1,
        "owner_count": 1,
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
            "dedicated": 1,
            "program": 0,
            "unsupported": 0,
            "unattributed": 0,
        },
        "attribution_counts": {"exact-key": 1, "none": 0},
        "role_counts": {"owner": 1, "member": 0, "none": 0},
        "group_kind_counts": {"inactive": 0, "direct": 0, "resolved": 1},
        "records": records,
        "groups": groups,
        "canonical_sha256": canonical_sha256,
        "validation_failures": [],
    }

def effect_execution_evidence(
    *,
    observed_exact: int = 1,
    route_count: int = 0,
) -> dict[str, object]:
    has_transitions = observed_exact > 0 or route_count > 0
    return {
        "has_evidence": True,
        "schema_version": 1,
        "axis_evidence": {
            "cpu_invocation": observed_exact > 0,
            "route_operation": route_count > 0,
            "frame_command_buffer": has_transitions,
        },
        "cpu_invocation_count": observed_exact,
        "route_operation_count": route_count,
        "cpu_invocations": [
            {"outcome": "encoded-output"} for _ in range(observed_exact)
        ],
        "route_operations": [
            {"outcome": "encoded"} for _ in range(route_count)
        ],
        "succeeded_exact_effects": [{} for _ in range(observed_exact)],
        "encoded_route_operations": [{} for _ in range(route_count)],
        "failed_exact_effects": [],
        "failed_route_operations": [],
        "completed_frame_ids": [17] if has_transitions else [],
        "failed_frame_ids": [],
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
        self.assertEqual(matrix_keys, ["expected_effect_execution_schema"])
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


    def test_tracked_matrices_have_no_unclassified_sample_keys(self) -> None:
        nested_expectation_keys = {
            expectation.matrix_key
            for expectations in (
                EFFECT_EXECUTION_EXPECTATIONS,
                RESOLVED_MATERIAL_GRAPH_EXPECTATIONS,
            )
            for expectation in expectations
        }
        for relative_path in (
            "script/scene_wallpaper_sample_matrix.json",
            "script/scene_wallpaper_full_sample_matrix.json",
        ):
            matrix = load_scene_matrix(REPOSITORY_ROOT / relative_path)
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

    def test_media_property_inputs_are_preserved_together_verbatim(self) -> None:
        inputs = {
            "media_title": "春日歌",
            "media_artist": "Fixture Artist 🎵",
        }
        refreshed = matrix_generator.matrix_sample(
            synthetic_result(),
            inputs,
        )
        self.assertEqual(
            {key: refreshed[key] for key in inputs},
            inputs,
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

    def test_effect_execution_rejects_invalid_nested_evidence(self) -> None:
        cases = {
            "schema mismatch": lambda evidence: evidence.update({
                "schema_version": None,
            }),
            "validation failed": lambda evidence: evidence[
                "validation_failures"
            ].append("bad join"),
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

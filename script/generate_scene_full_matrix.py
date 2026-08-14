#!/usr/bin/env python3

import argparse
import copy
import hashlib
import json
from pathlib import Path

from scene_matrix_contract import (
    AUTHORED_EFFECT_RUNTIME_EXPECTATIONS,
    EFFECT_EXECUTION_EXPECTATIONS,
    RESOLVED_MATERIAL_GRAPH_BACKEND,
    RESOLVED_MATERIAL_GRAPH_EXPECTATIONS,
    effect_execution_static_demand,
    optional_group_is_active,
)
from scene_matrix_suite import compact_suite_payload, load_scene_matrix


RUNTIME_EVIDENCE_METRICS = [
    "schema_version",
    "shader_contract_count",
    "shader_contract_authored_count",
    "shader_contract_builtin_count",
    "shader_contract_stage_count",
    "shader_contract_diagnostic_count",
    "effect_texture_slot_count",
    "effect_texture_slot_hole_count",
    "effect_combo_entry_count",
    "material_texture_slot_count",
    "material_texture_slot_hole_count",
    "material_combo_entry_count",
    "effect_definition_count",
    "effect_definition_pass_count",
    "effect_definition_material_pass_count",
    "effect_definition_fbo_count",
    "effect_definition_copy_command_count",
    "effect_definition_swap_command_count",
    "effect_definition_diagnostic_count",
    "effect_graph_layer_count",
    "effect_graph_effect_count",
    "effect_graph_node_count",
    "effect_graph_material_node_count",
    "effect_graph_copy_node_count",
    "effect_graph_swap_node_count",
    "effect_graph_render_target_count",
    "effect_graph_blocker_count",
    "effect_graph_unblocked_layer_count",
    "visible_layer_count",
    "root_layer_count",
    "child_edge_count",
    "parent_layer_count",
    "max_hierarchy_depth",
    "effective_visible_layer_count",
    "solid_layer_count",
    "authored_solid_color_layer_count",
    "effective_visible_solid_layer_count",
    "built_in_reference_count",
    "missing_resource_count",
    "composition_layer_count",
    "project_layer_count",
    "fullscreen_layer_count",
    "dependency_edge_count",
]

PRESERVED_KEYS = [
    "hover_pointer_normalized",
    "requires_motion",
    "minimum_changed_ratio",
    "maximum_changed_ratio",
    "minimum_hover_changed_ratio",
    "maximum_flat_border_ratio",
    "property_overrides",
    "live_property_overrides",
    "media_title",
    "media_artist",
    "minimum_authored_opacity_runtime_count",
    "minimum_authored_parallax_layer_count",
    "minimum_live_changed_ratio",
    "minimum_particle_initial_live",
    "required_effect_files",
    "required_effectively_hidden_layer_ids",
    "required_effectively_visible_layer_ids",
    "required_effectively_visible_solid_layer_ids",
    "required_solid_layer_ids",
    "required_utility_dispositions",
]

OPTIONAL_RUNTIME_EXPECTATION_GROUPS = {
    "particle_refract": {
        "expected_particle_refract_loaded": "particle_refract_loaded",
    },
    "particle_transparency": {
        "expected_particle_skipped_transparent":
            "particle_skipped_transparent",
    },
    "text_script_binding": {
        "expected_text_script_binding_count": "text_script_binding_count",
        "required_text_script_binding_layer_ids":
            "text_script_binding_layer_ids",
    },
    "time_of_day_effect_script_binding": {
        "expected_time_of_day_effect_script_binding_count":
            "time_of_day_effect_script_binding_count",
        "required_time_of_day_effect_script_bindings":
            "time_of_day_effect_script_bindings",
    },
}

PUPPET_ANIMATION_EXPECTATIONS = {
    "expected_puppet_animation_layer_ids": "puppet_animation_layer_ids",
    "expected_puppet_disjoint_additive_layer_ids":
        "puppet_disjoint_additive_layer_ids",
    "expected_puppet_animation_clip_count": "puppet_animation_clip_count",
}

UTILITY_OWNER_AUTHORITY_EXPECTATIONS = (
    (
        "expected_utility_capture_planned",
        "utility_capture_planned",
        "required_utility_capture_succeeded_layer_ids",
        "utility_capture_succeeded_layer_ids",
        "utility_capture_failed_layer_ids",
        "utility capture",
    ),
    (
        "expected_utility_named_target_planned",
        "utility_named_target_planned",
        "required_named_target_capture_succeeded_layer_ids",
        "named_target_capture_succeeded_layer_ids",
        "named_target_capture_failed_layer_ids",
        "named target capture",
    ),
    (
        "expected_utility_named_binding_planned",
        "utility_named_binding_planned",
        "required_named_target_binding_succeeded_layer_ids",
        "named_target_binding_succeeded_layer_ids",
        "named_target_binding_failed_layer_ids",
        "named target binding",
    ),
)

UTILITY_OWNER_AUTHORITY_SCALAR_EXPECTATIONS = (
    ("expected_utility_named_consumers", "utility_named_consumers"),
    ("expected_utility_named_target_gaps", "utility_named_target_gaps"),
)

R4_OWNER_AUTHORITY_FATAL_REPORT_FAILURES = frozenset({
    "utility layer runtime evidence missing",
    "utility capture execution below planned count",
    "named target capture execution below planned count",
    "named target binding execution below planned count",
})

R4_OWNER_AUTHORITY_PRESERVED_EXPECTATION_KEYS = frozenset({
    "expected_authored_effect_graph_color_key_count",
})

R4_OWNER_AUTHORITY_EXPECTATION_KEYS = frozenset({
    *(
        expectation.matrix_key
        for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        if expectation.matrix_key
        not in R4_OWNER_AUTHORITY_PRESERVED_EXPECTATION_KEYS
    ),
    *(expectation.matrix_key for expectation in EFFECT_EXECUTION_EXPECTATIONS),
    *(expectation.matrix_key for expectation in RESOLVED_MATERIAL_GRAPH_EXPECTATIONS),
    *(
        matrix_key
        for expectation in UTILITY_OWNER_AUTHORITY_EXPECTATIONS
        for matrix_key in (expectation[0], expectation[2])
    ),
    *(matrix_key for matrix_key, _ in UTILITY_OWNER_AUTHORITY_SCALAR_EXPECTATIONS),
})


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _samples_by_id(samples, *, source: str):
    result = {}
    for sample in samples:
        sample_id = str(sample.get("id"))
        if sample_id in result:
            raise ValueError(f"{source} contains duplicate sample id {sample_id}")
        result[sample_id] = sample
    return result


def validate_report_identity(
    report: dict,
    old_matrix: dict,
    old_matrix_path: Path,
    *,
    require_passed: bool,
) -> tuple[dict, dict]:
    if report.get("schema_version") != 2:
        raise ValueError("benchmark report schema must be 2")
    if old_matrix.get("schema_version") != 1:
        raise ValueError("tracked matrix schema must be 1")
    if report.get("matrix") != old_matrix.get("name"):
        raise ValueError("benchmark report matrix name mismatch")
    report_matrix_path = report.get("matrix_path")
    if not isinstance(report_matrix_path, str) or (
        Path(report_matrix_path).expanduser().resolve() != old_matrix_path.resolve()
    ):
        raise ValueError("benchmark report matrix path mismatch")
    if report.get("matrix_sha256") != sha256(old_matrix_path):
        raise ValueError("benchmark report matrix sha256 mismatch")

    report_samples = report.get("samples")
    matrix_samples = old_matrix.get("samples")
    if not isinstance(report_samples, list) or not isinstance(matrix_samples, list):
        raise ValueError("benchmark report or matrix samples are malformed")
    report_by_id = _samples_by_id(report_samples, source="benchmark report")
    old_by_id = _samples_by_id(matrix_samples, source="tracked matrix")
    if set(report_by_id) != set(old_by_id):
        raise ValueError("benchmark report sample IDs differ from tracked matrix")

    for sample_id, result in report_by_id.items():
        old = old_by_id[sample_id]
        hashes = result.get("hashes")
        if not isinstance(hashes, dict) or (
            hashes.get("project_sha256") != old.get("project_sha256")
            or hashes.get("package_sha256") != old.get("package_sha256")
        ):
            raise ValueError(f"sample {sample_id} source hashes mismatch")
        if result.get("package_file", "scene.pkg") != old.get(
            "package_file", "scene.pkg"
        ):
            raise ValueError(f"sample {sample_id} package file mismatch")

    summary = report.get("summary")
    if not isinstance(summary, dict):
        raise ValueError("benchmark report summary is malformed")
    passed_count = sum(result.get("passed") is True for result in report_samples)
    all_passed = passed_count == len(report_samples)
    # A compact suite is portable only beside its tracked base. External
    # review outputs stay expanded instead of writing a broken relative link.
    if (
        summary.get("sample_count") != len(report_samples)
        or summary.get("passed_count") != passed_count
        or summary.get("passed") is not all_passed
    ):
        raise ValueError("benchmark report summary is inconsistent")
    if require_passed and not all_passed:
        raise ValueError("full matrix refresh requires a passing benchmark report")
    return report_by_id, old_by_id


def _nonnegative_integer(value: object, *, sample_id: object, label: str) -> int:
    if type(value) is not int or value < 0:
        raise ValueError(f"sample {sample_id} {label} is invalid")
    return value


def _sorted_layer_ids(
    value: object,
    *,
    sample_id: object,
    label: str,
) -> list[int]:
    if not (
        isinstance(value, list)
        and all(type(layer_id) is int and layer_id >= 0 for layer_id in value)
        and value == sorted(set(value))
    ):
        raise ValueError(f"sample {sample_id} {label} is invalid")
    return value


def _string_list(value: object, *, sample_id: object, label: str) -> list[str]:
    if not (
        isinstance(value, list)
        and all(isinstance(item, str) for item in value)
    ):
        raise ValueError(f"sample {sample_id} {label} is invalid")
    return value


def _validate_r4_owner_authority_report_failures(result: dict) -> None:
    sample_id = result.get("id")
    failures = result.get("failures")
    if not (
        isinstance(failures, list)
        and all(isinstance(failure, str) for failure in failures)
    ):
        raise ValueError(
            f"sample {sample_id} benchmark failure telemetry is malformed"
        )
    fatal_failures = [
        failure
        for failure in failures
        if failure in R4_OWNER_AUTHORITY_FATAL_REPORT_FAILURES
        or (
            failure.startswith("authored effect graph layer ")
            and failure.endswith(" failed")
        )
    ]
    if fatal_failures:
        raise ValueError(
            f"sample {sample_id} owner authority telemetry failed: "
            f"{fatal_failures[0]}"
        )


def authored_effect_graph_runtime_values(
    result: dict,
    old_sample: dict,
    excluded_expectation_keys: frozenset[str] = frozenset(),
) -> dict:
    sample_id = result.get("id")
    runtime = result.get("runtime")
    if not isinstance(runtime, dict):
        raise ValueError(
            f"sample {sample_id} authored effect graph runtime evidence missing"
        )

    values = {}

    optional_groups = {
        expectation.optional_group
        for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        if expectation.optional_group
        and optional_group_is_active(
            expectation.optional_group,
            runtime,
            old_sample,
        )
    }
    for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS:
        if expectation.matrix_key in excluded_expectation_keys:
            continue
        if expectation.matrix_key not in old_sample:
            continue
        value = runtime.get(expectation.report_metric)
        if expectation.comparison == "integer":
            value = _nonnegative_integer(
                value,
                sample_id=sample_id,
                label=expectation.report_metric,
            )
        elif expectation.comparison == "sorted_list":
            value = _sorted_layer_ids(
                value,
                sample_id=sample_id,
                label=expectation.report_metric,
            )
        else:
            value = _string_list(
                value,
                sample_id=sample_id,
                label=expectation.report_metric,
            )
        if (
            expectation.optional_group
            and expectation.optional_group not in optional_groups
        ):
            continue
        values[expectation.matrix_key] = value
    return values


def owner_authority_plan_execution_values(result: dict) -> dict:
    sample_id = result.get("id")
    runtime = result.get("runtime")
    if not isinstance(runtime, dict):
        raise ValueError(
            f"sample {sample_id} owner authority runtime evidence missing"
        )

    values = {}
    for matrix_key, runtime_key in UTILITY_OWNER_AUTHORITY_SCALAR_EXPECTATIONS:
        values[matrix_key] = _nonnegative_integer(
            runtime.get(runtime_key),
            sample_id=sample_id,
            label=runtime_key,
        )
    for (
        plan_matrix_key,
        plan_runtime_key,
        success_matrix_key,
        success_runtime_key,
        failure_runtime_key,
        label,
    ) in UTILITY_OWNER_AUTHORITY_EXPECTATIONS:
        planned = _nonnegative_integer(
            runtime.get(plan_runtime_key),
            sample_id=sample_id,
            label=plan_runtime_key,
        )
        succeeded_layer_ids = _sorted_layer_ids(
            runtime.get(success_runtime_key),
            sample_id=sample_id,
            label=success_runtime_key,
        )
        failed_layer_ids = _sorted_layer_ids(
            runtime.get(failure_runtime_key),
            sample_id=sample_id,
            label=failure_runtime_key,
        )
        if failed_layer_ids:
            raise ValueError(f"sample {sample_id} {label} execution failed")
        if len(succeeded_layer_ids) < planned:
            raise ValueError(
                f"sample {sample_id} {label} execution below planned count"
            )
        values[plan_matrix_key] = planned
        values[success_matrix_key] = succeeded_layer_ids
    return values


def effect_execution_values(
    result: dict,
    old_sample: dict | None = None,
) -> dict | None:
    expectation_keys = {
        expectation.matrix_key for expectation in EFFECT_EXECUTION_EXPECTATIONS
    }
    present_expectations = expectation_keys.intersection(old_sample or {})
    if present_expectations and present_expectations != expectation_keys:
        raise ValueError(
            f"sample {result.get('id')} effect execution matrix contract incomplete"
        )

    runtime = result.get("runtime")
    disposition = runtime.get("effect_runtime_disposition") if isinstance(
        runtime, dict
    ) else None
    execution = runtime.get("effect_execution") if isinstance(runtime, dict) else None
    if not (
        isinstance(disposition, dict)
        and disposition.get("has_evidence") is True
    ):
        if not present_expectations and not (
            isinstance(execution, dict)
            and execution.get("has_evidence") is True
        ):
            return None
        raise ValueError(
            f"sample {result.get('id')} effect runtime disposition evidence missing"
        )
    records = disposition.get("records")
    if not isinstance(records, list):
        raise ValueError(
            f"sample {result.get('id')} effect runtime disposition records invalid"
        )

    demand = effect_execution_static_demand(disposition)
    if not demand.static_is_valid:
        raise ValueError(
            f"sample {result.get('id')} effect runtime disposition evidence invalid"
        )
    has_evidence = bool(
        isinstance(execution, dict)
        and execution.get("has_evidence") is True
    )
    evidence_is_required = demand.has_demand
    if not has_evidence:
        if evidence_is_required:
            raise ValueError(
                f"sample {result.get('id')} effect execution evidence missing"
            )
        return None
    if not demand.has_demand:
        raise ValueError(
            f"sample {result.get('id')} effect execution has no static demand"
        )

    if execution.get("schema_version") != 1:
        raise ValueError(
            f"sample {result.get('id')} effect execution schema mismatch"
        )
    if execution.get("validation_failures") != []:
        raise ValueError(
            f"sample {result.get('id')} effect execution validation failed"
        )

    integer_fields = ("cpu_invocation_count", "route_operation_count")
    if any(
        not isinstance(execution.get(field), int)
        or isinstance(execution.get(field), bool)
        or execution[field] < 0
        for field in integer_fields
    ):
        raise ValueError(
            f"sample {result.get('id')} effect execution counts are invalid"
        )

    failure_fields = (
        "failed_exact_effects",
        "failed_route_operations",
        "failed_frame_ids",
    )
    for field in failure_fields:
        if not isinstance(execution.get(field), list):
            raise ValueError(
                f"sample {result.get('id')} effect execution {field} invalid"
            )
        if execution[field]:
            raise ValueError(
                f"sample {result.get('id')} effect execution failure observed"
            )

    cpu_invocations = execution.get("cpu_invocations")
    route_operations = execution.get("route_operations")
    succeeded_exact_effects = execution.get("succeeded_exact_effects")
    encoded_route_operations = execution.get("encoded_route_operations")
    completed_frame_ids = execution.get("completed_frame_ids")
    if (
        not isinstance(cpu_invocations, list)
        or len(cpu_invocations) != execution["cpu_invocation_count"]
        or any(not isinstance(invocation, dict) for invocation in cpu_invocations)
        or not isinstance(route_operations, list)
        or len(route_operations) != execution["route_operation_count"]
        or any(not isinstance(operation, dict) for operation in route_operations)
        or not isinstance(succeeded_exact_effects, list)
        or any(not isinstance(effect, dict) for effect in succeeded_exact_effects)
        or not isinstance(encoded_route_operations, list)
        or any(
            not isinstance(operation, dict)
            for operation in encoded_route_operations
        )
        or len(encoded_route_operations) != execution["route_operation_count"]
        or not isinstance(completed_frame_ids, list)
        or any(
            not isinstance(frame_id, int) or isinstance(frame_id, bool)
            for frame_id in completed_frame_ids
        )
        or len(completed_frame_ids) != len(set(completed_frame_ids))
    ):
        raise ValueError(
            f"sample {result.get('id')} effect execution transition summary invalid"
        )
    if any(
        invocation.get("outcome") != "encoded-output"
        for invocation in cpu_invocations
    ) or any(
        operation.get("outcome") != "encoded"
        for operation in route_operations
    ):
        raise ValueError(
            f"sample {result.get('id')} effect execution failure observed"
        )

    axis_evidence = execution.get("axis_evidence")
    expected_axis_evidence = {
        "cpu_invocation": execution["cpu_invocation_count"] > 0,
        "route_operation": execution["route_operation_count"] > 0,
        "frame_command_buffer": bool(completed_frame_ids),
    }
    if axis_evidence != expected_axis_evidence:
        raise ValueError(
            f"sample {result.get('id')} effect execution axis summary invalid"
        )
    if (
        execution["cpu_invocation_count"] > 0
        or execution["route_operation_count"] > 0
    ) and not completed_frame_ids:
        raise ValueError(
            f"sample {result.get('id')} effect execution completed frame missing"
        )

    return {
        expectation.matrix_key: execution[expectation.metric_key]
        for expectation in EFFECT_EXECUTION_EXPECTATIONS
    }


def resolved_material_graph_execution_values(
    result: dict,
    old_sample: dict | None = None,
    *,
    require_evidence: bool = False,
) -> dict | None:
    expectation = RESOLVED_MATERIAL_GRAPH_EXPECTATIONS[0]
    runtime = result.get("runtime")
    execution = (
        runtime.get("resolved_material_graph_execution")
        if isinstance(runtime, dict)
        else None
    )
    capability = execution.get("capability") if isinstance(execution, dict) else None
    expects_evidence = (
        require_evidence or expectation.matrix_key in (old_sample or {})
    )
    has_capability_evidence = bool(
        isinstance(capability, dict)
        and capability.get("has_evidence") is True
    )
    if require_evidence and not (
        isinstance(execution, dict)
        and execution.get("has_evidence") is True
    ):
        raise ValueError(
            f"sample {result.get('id')} resolved material graph evidence missing"
        )
    if not has_capability_evidence and not expects_evidence:
        return None
    if not isinstance(execution, dict) or not has_capability_evidence:
        raise ValueError(
            f"sample {result.get('id')} resolved material graph evidence missing"
        )
    if execution.get("validation_failures") != []:
        raise ValueError(
            f"sample {result.get('id')} resolved material graph validation failed"
        )

    def layer_ids(value: object) -> list[int] | None:
        if not (
            isinstance(value, list)
            and all(
                isinstance(layer_id, int) and not isinstance(layer_id, bool)
                and layer_id >= 0
                for layer_id in value
            )
            and value == sorted(set(value))
        ):
            return None
        return value

    accepted_count = capability.get("accepted_count")
    accepted_layer_ids = layer_ids(capability.get("accepted_layer_ids"))
    succeeded_layer_ids = layer_ids(execution.get("succeeded_layer_ids"))
    executor = execution.get("executor")
    observations = execution.get("graph_observations")
    exact_backend = execution.get("exact_backend")
    if (
        not isinstance(accepted_count, int)
        or isinstance(accepted_count, bool)
        or accepted_count < 0
        or accepted_layer_ids is None
        or len(accepted_layer_ids) != accepted_count
        or succeeded_layer_ids is None
        or not isinstance(executor, dict)
        or executor.get("has_evidence") is not True
        or not isinstance(observations, dict)
        or not isinstance(exact_backend, dict)
        or exact_backend.get("backend") != RESOLVED_MATERIAL_GRAPH_BACKEND
    ):
        raise ValueError(
            f"sample {result.get('id')} resolved material graph summary invalid"
        )

    gpu_layer_ids = layer_ids(observations.get("successful_gpu_completed_layer_ids"))
    compositor_layer_ids = layer_ids(observations.get("compositor_consumed_layer_ids"))
    next_frame_layer_ids = layer_ids(observations.get("next_frame_layer_ids"))
    exact_layer_ids = layer_ids(exact_backend.get("complete_layer_ids"))
    if any(value is None for value in (
        gpu_layer_ids,
        compositor_layer_ids,
        next_frame_layer_ids,
        exact_layer_ids,
    )):
        raise ValueError(
            f"sample {result.get('id')} resolved material graph layer evidence invalid"
        )
    computed_succeeded = sorted(
        set(accepted_layer_ids)
        .intersection(gpu_layer_ids)
        .intersection(compositor_layer_ids)
        .intersection(next_frame_layer_ids)
        .intersection(exact_layer_ids)
    )
    if computed_succeeded != succeeded_layer_ids:
        raise ValueError(
            f"sample {result.get('id')} resolved material graph success intersection invalid"
        )

    if accepted_count == 0:
        zero_fields = (
            "claimed_count", "encoded_count", "failure_count",
            "deferred_count", "pending_max", "gpu_encoded_count",
        )
        if (
            execution.get("zero_contract_succeeded") is not True
            or execution.get("contract_succeeded") is not True
            or succeeded_layer_ids
            or any(executor.get(field) != 0 for field in zero_fields)
            or observations.get("observation_count") != 0
            or exact_backend.get("unexpected_layer_ids") != []
        ):
            raise ValueError(
                f"sample {result.get('id')} resolved material graph zero contract invalid"
            )
    elif (
        execution.get("execution_succeeded") is not True
        or execution.get("contract_succeeded") is not True
        or succeeded_layer_ids != accepted_layer_ids
    ):
        raise ValueError(
            f"sample {result.get('id')} resolved material graph positive contract invalid"
        )

    return {expectation.matrix_key: succeeded_layer_ids}


def scoped_r4_owner_authority_matrix(
    report: dict,
    old_matrix: dict,
    old_matrix_path: Path,
) -> dict:
    report_by_id, old_by_id = validate_report_identity(
        report,
        old_matrix,
        old_matrix_path,
        require_passed=False,
    )
    updates_by_id = {}
    for sample_id, result in report_by_id.items():
        old_sample = old_by_id[sample_id]
        _validate_r4_owner_authority_report_failures(result)
        values = authored_effect_graph_runtime_values(
            result,
            old_sample,
            excluded_expectation_keys=
                R4_OWNER_AUTHORITY_PRESERVED_EXPECTATION_KEYS,
        )
        execution_values = effect_execution_values(result, old_sample)
        if execution_values is not None:
            values.update(execution_values)
        values.update(owner_authority_plan_execution_values(result))
        graph_values = resolved_material_graph_execution_values(
            result,
            old_sample,
            require_evidence=True,
        )
        if graph_values is None:
            raise ValueError(
                f"sample {sample_id} resolved material graph evidence missing"
            )
        values.update(graph_values)
        if not set(values).issubset(R4_OWNER_AUTHORITY_EXPECTATION_KEYS):
            raise ValueError(
                f"sample {sample_id} R4 owner authority whitelist escaped"
            )
        updates_by_id[sample_id] = values

    matrix = copy.deepcopy(old_matrix)
    execution_expectation_keys = {
        expectation.matrix_key for expectation in EFFECT_EXECUTION_EXPECTATIONS
    }
    for sample in matrix["samples"]:
        for key in execution_expectation_keys:
            sample.pop(key, None)
        sample.update(updates_by_id[str(sample["id"])])
    return matrix


def capabilities(runtime):
    values = []
    for key, label in (
        ("image_layers", "image_layers"),
        ("text_candidates", "text_layers"),
        ("solid_candidates", "solid_layers"),
        ("particle_candidates", "particle_layers"),
        ("utility_candidates", "utility_layers"),
    ):
        if runtime.get(key, 0):
            values.append(label)
    if runtime["runtime_evidence"].get("dependency_edge_count", 0):
        values.append("dependency_graph")
    return values


def matrix_sample(result, old):
    runtime = result["runtime"]
    runtime_evidence = runtime["runtime_evidence"]
    sample_capabilities = [
        capability
        for capability in (old.get("capabilities") or capabilities(runtime))
        if capability != "scene_script_audio_bars"
    ]
    sample = {
        "id": result["id"],
        "title": result.get("title"),
        "capabilities": sample_capabilities,
        "project_sha256": result["hashes"]["project_sha256"],
        "package_sha256": result["hashes"]["package_sha256"],
    }
    if result.get("package_file") != "scene.pkg":
        sample["package_file"] = result["package_file"]

    for metric in RUNTIME_EVIDENCE_METRICS:
        expectation = "expected_runtime_evidence_schema" if metric == "schema_version" else f"expected_{metric}"
        sample[expectation] = runtime_evidence[metric]
    sample["expected_shader_contract_aggregate_sha256"] = runtime_evidence[
        "shader_contract_aggregate_sha256"
    ]
    sample["expected_effect_graph_sha256"] = runtime_evidence["effect_graph_sha256"]
    sample["expected_stock_opacity_single_effect_candidate_layer_ids"] = runtime_evidence[
        "stock_opacity_single_effect_candidate_layer_ids"
    ]

    sample.update({
        "minimum_loaded_ratio": runtime["loaded_ratio"],
        "minimum_text_loaded": runtime["loaded_textures_text"],
        "expected_text_candidates": runtime["text_candidates"],
        "required_text_loaded_layer_ids": runtime["text_loaded_layer_ids"],
        "expected_solid_candidates": runtime["solid_candidates"],
        "required_solid_loaded_layer_ids": runtime["solid_loaded_layer_ids"],
        "expected_particle_candidates": runtime["particle_candidates"],
        "minimum_particle_loaded": runtime["loaded_particle_layers"],
        "expected_particle_authored": runtime["particle_authored"],
        "expected_particle_visible": runtime["particle_visible"],
        "expected_particle_skipped_hidden": runtime["particle_skipped_hidden"],
        "required_particle_loaded_layer_ids": runtime["particle_loaded_layer_ids"],
        "expected_camera_parallax": runtime["camera_parallax"],
        "expected_utility_candidates": runtime["utility_candidates"],
        "expected_utility_capture_planned": runtime["utility_capture_planned"],
        "expected_utility_dependency_edges": runtime["utility_dependency_edges"],
        "expected_utility_named_consumers": runtime["utility_named_consumers"],
        "expected_utility_named_target_planned": runtime["utility_named_target_planned"],
        "expected_utility_named_binding_planned": runtime["utility_named_binding_planned"],
        "expected_utility_named_target_gaps": runtime["utility_named_target_gaps"],
        "required_utility_capture_succeeded_layer_ids": runtime["utility_capture_succeeded_layer_ids"],
        "required_named_target_capture_succeeded_layer_ids": runtime["named_target_capture_succeeded_layer_ids"],
        "required_named_target_binding_succeeded_layer_ids": runtime["named_target_binding_succeeded_layer_ids"],
    })

    optional_effect_groups = {
        expectation.optional_group
        for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        if expectation.optional_group
        and optional_group_is_active(expectation.optional_group, runtime, old)
    }
    for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS:
        if (
            expectation.optional_group
            and expectation.optional_group not in optional_effect_groups
        ):
            continue
        sample[expectation.matrix_key] = runtime[expectation.report_metric]

    for expectations in OPTIONAL_RUNTIME_EXPECTATION_GROUPS.values():
        is_active = any(
            matrix_key in old or bool(runtime.get(runtime_key))
            for matrix_key, runtime_key in expectations.items()
        )
        if is_active:
            for matrix_key, runtime_key in expectations.items():
                sample[matrix_key] = runtime[runtime_key]

    has_puppet_animation_contract = bool(
        runtime.get("puppet_animation_layer_ids")
    ) or any(key in old for key in PUPPET_ANIMATION_EXPECTATIONS)
    if has_puppet_animation_contract:
        for expectation, metric in PUPPET_ANIMATION_EXPECTATIONS.items():
            sample[expectation] = runtime[metric]

    execution_values = effect_execution_values(result, old)
    if execution_values is not None:
        sample.update(execution_values)

    graph_execution_values = resolved_material_graph_execution_values(result, old)
    if graph_execution_values is not None:
        sample.update(graph_execution_values)

    for key in PRESERVED_KEYS:
        if key in old:
            sample[key] = old[key]

    optional_execution_keys = {
        expectation.matrix_key for expectation in EFFECT_EXECUTION_EXPECTATIONS
    }
    optional_execution_keys.update(
        expectation.matrix_key
        for expectation in RESOLVED_MATERIAL_GRAPH_EXPECTATIONS
    )
    unhandled_keys = sorted(
        set(old) - set(sample) - {"package_file"} - optional_execution_keys
    )
    if unhandled_keys:
        joined = ", ".join(unhandled_keys)
        raise ValueError(
            f"sample {result['id']} has unclassified matrix keys: {joined}"
        )
    return sample


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Refresh a tracked Scene matrix from a benchmark report."
    )
    parser.add_argument("report", type=Path)
    parser.add_argument("old_matrix", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument(
        "--scope",
        choices=(
            "all",
            "r4-owner-authority",
        ),
        default="all",
        help=(
            "refresh every public contract or the R4 owner-authority families"
        ),
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    report_path = args.report.expanduser().resolve()
    old_matrix_path = args.old_matrix.expanduser().resolve()
    output_path = args.output.expanduser().resolve()
    report = json.loads(report_path.read_text())
    old_matrix_payload = json.loads(old_matrix_path.read_text())
    old_matrix = load_scene_matrix(old_matrix_path)
    if args.scope == "r4-owner-authority":
        matrix = scoped_r4_owner_authority_matrix(
            report,
            old_matrix,
            old_matrix_path,
        )
    else:
        report_by_id, old_by_id = validate_report_identity(
            report,
            old_matrix,
            old_matrix_path,
            require_passed=True,
        )
        matrix = {
            "schema_version": 1,
            "name": old_matrix["name"],
            "samples": [
                matrix_sample(report_by_id[sample_id], old_by_id[sample_id])
                for sample_id in sorted(old_by_id)
            ],
        }
    output_payload = matrix
    if (
        old_matrix_payload.get("schema_version") == 2
        and output_path.parent == old_matrix_path.parent
    ):
        raw_base = old_matrix_payload.get("base_matrix")
        if not isinstance(raw_base, str):
            raise ValueError("Scene matrix suite has no base_matrix")
        output_payload = compact_suite_payload(
            old_matrix_path.parent / raw_base,
            matrix,
            suite_path=output_path,
        )
    output_path.write_text(
        json.dumps(output_payload, ensure_ascii=False, indent=2) + "\n"
    )


if __name__ == "__main__":
    main()

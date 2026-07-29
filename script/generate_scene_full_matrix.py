#!/usr/bin/env python3

import argparse
import json
from pathlib import Path

from scene_matrix_contract import (
    AUTHORED_EFFECT_RUNTIME_EXPECTATIONS,
    optional_group_is_active,
)


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
    "maximum_legacy_waterwaves_runtime_count",
    "minimum_authored_opacity_runtime_count",
    "minimum_authored_parallax_layer_count",
    "minimum_legacy_waterwaves_runtime_count",
    "minimum_live_changed_ratio",
    "minimum_particle_initial_live",
    "required_authored_effect_graph_succeeded_layer_ids",
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
}

SCENE_SCRIPT_AUDIO_BARS_EXPECTATIONS = {
    "expected_scene_script_audio_bars_plan_count": "scene_script_audio_bars_plan_count",
    "expected_scene_script_audio_bars_diagnostic_count": "scene_script_audio_bars_diagnostic_count",
    "expected_scene_script_audio_bars_has_audio_consumer": "scene_script_audio_bars_has_audio_consumer",
    "expected_scene_script_audio_bars_total_bar_count": "scene_script_audio_bars_total_bar_count",
    "expected_scene_script_audio_bars_plan_layer_ids": "scene_script_audio_bars_plan_layer_ids",
    "expected_scene_script_audio_bars_plans": "scene_script_audio_bars_plans",
    "expected_scene_script_audio_bars_succeeded_layer_ids": "scene_script_audio_bars_succeeded_layer_ids",
    "required_scene_script_audio_bars_succeeded_layer_ids": "scene_script_audio_bars_succeeded_layer_ids",
}


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
    if runtime.get("authored_effect_graph_stage_count", 0):
        values.append("authored_effect_runtime")
    if runtime.get("route_only_effect_count", 0):
        values.append("route_only_effects")
    if runtime.get("scene_script_audio_bars_plan_count", 0):
        values.append("scene_script_audio_bars")
    return values


def matrix_sample(result, old):
    runtime = result["runtime"]
    runtime_evidence = runtime["runtime_evidence"]
    sample_capabilities = list(old.get("capabilities") or capabilities(runtime))
    if (
        runtime.get("scene_script_audio_bars_plan_count", 0)
        and "scene_script_audio_bars" not in sample_capabilities
    ):
        sample_capabilities.append("scene_script_audio_bars")
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
        "expected_image_blend_planned": runtime["image_blend_planned"],
        "required_image_blend_succeeded_layer_ids": runtime["image_blend_succeeded_layer_ids"],
        "expected_authored_effect_graph_succeeded_layer_ids": runtime["authored_effect_graph_succeeded_layer_ids"],
        "expected_authored_effect_graph_legacy_blur_blocked_layer_ids": runtime["authored_effect_graph_legacy_blur_blocked_layer_ids"],
        "expected_authored_effect_graph_chain_count": runtime["authored_effect_graph_chain_count"],
        "expected_authored_effect_graph_stage_count": runtime["authored_effect_graph_stage_count"],
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

    has_scene_script_audio_bars_contract = bool(
        runtime.get("scene_script_audio_bars_plan_count")
    ) or any(key in old for key in SCENE_SCRIPT_AUDIO_BARS_EXPECTATIONS)
    if has_scene_script_audio_bars_contract:
        for expectation, metric in SCENE_SCRIPT_AUDIO_BARS_EXPECTATIONS.items():
            sample[expectation] = runtime[metric]

    for key in PRESERVED_KEYS:
        if key in old:
            sample[key] = old[key]

    unhandled_keys = sorted(set(old) - set(sample) - {"package_file"})
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
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    report_path = args.report.expanduser().resolve()
    old_matrix_path = args.old_matrix.expanduser().resolve()
    output_path = args.output.expanduser().resolve()
    report = json.loads(report_path.read_text())
    old_matrix = json.loads(old_matrix_path.read_text())
    old_by_id = {sample["id"]: sample for sample in old_matrix["samples"]}
    matrix = {
        "schema_version": 1,
        "name": old_matrix["name"],
        "samples": [
            matrix_sample(result, old_by_id.get(result["id"], {}))
            for result in sorted(report["samples"], key=lambda value: value["id"])
        ],
    }
    output_path.write_text(json.dumps(matrix, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()

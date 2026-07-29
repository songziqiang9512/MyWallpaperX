#!/usr/bin/env python3

import argparse
import json
from pathlib import Path


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
]


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
    return values


def matrix_sample(result, old):
    runtime = result["runtime"]
    runtime_evidence = runtime["runtime_evidence"]
    sample = {
        "id": result["id"],
        "title": result.get("title"),
        "capabilities": old.get("capabilities") or capabilities(runtime),
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
        "expected_authored_effect_graph_local_contrast_count": runtime["authored_effect_graph_local_contrast_count"],
        "expected_authored_effect_graph_opacity_count": runtime["authored_effect_graph_opacity_count"],
        "expected_authored_effect_graph_opacity_layer_ids": runtime["authored_effect_graph_opacity_layer_ids"],
        "expected_authored_effect_graph_color_key_count": runtime["authored_effect_graph_color_key_count"],
        "expected_authored_effect_graph_workshop_shadow_count": runtime["authored_effect_graph_workshop_shadow_count"],
        "expected_authored_effect_graph_spin_count": runtime["authored_effect_graph_spin_count"],
        "expected_authored_effect_graph_procedural_noise_count": runtime["authored_effect_graph_procedural_noise_count"],
        "expected_authored_effect_graph_film_grain_count": runtime["authored_effect_graph_film_grain_count"],
        "expected_authored_effect_graph_light_shafts_count": runtime["authored_effect_graph_light_shafts_count"],
        "expected_authored_effect_graph_shake_count": runtime["authored_effect_graph_shake_count"],
        "expected_authored_effect_graph_water_flow_count": runtime["authored_effect_graph_water_flow_count"],
        "expected_authored_effect_graph_water_waves_count": runtime["authored_effect_graph_water_waves_count"],
        "expected_authored_effect_graph_foliage_sway_count": runtime["authored_effect_graph_foliage_sway_count"],
        "expected_authored_effect_graph_water_ripple_count": runtime["authored_effect_graph_water_ripple_count"],
        "expected_authored_effect_graph_iris_inline_suffix_count": runtime["authored_effect_graph_iris_inline_suffix_count"],
        "expected_authored_effect_graph_blend_count": runtime["authored_effect_graph_blend_count"],
        "expected_authored_effect_graph_tint_count": runtime["authored_effect_graph_tint_count"],
        "expected_authored_effect_graph_pulse_count": runtime["authored_effect_graph_pulse_count"],
        "expected_authored_effect_graph_godrays_count": runtime["authored_effect_graph_godrays_count"],
        "expected_authored_effect_graph_transform_count": runtime["authored_effect_graph_transform_count"],
        "expected_authored_effect_graph_transform_static_fallback_count": runtime["authored_effect_graph_transform_static_fallback_count"],
        "expected_authored_effect_graph_transform_static_fallback_diagnostics": runtime["authored_effect_graph_transform_static_fallback_diagnostics"],
        "expected_authored_effect_graph_authored_shader_count": runtime["authored_effect_graph_authored_shader_count"],
        "expected_authored_effect_graph_chain_count": runtime["authored_effect_graph_chain_count"],
        "expected_authored_effect_graph_stage_count": runtime["authored_effect_graph_stage_count"],
        "expected_route_only_effect_count": runtime["route_only_effect_count"],
    })

    for key in PRESERVED_KEYS:
        if key in old:
            sample[key] = old[key]
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

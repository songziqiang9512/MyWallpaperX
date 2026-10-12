"""Validate one collected Scene sample result against its expectations."""

from __future__ import annotations

import math
import re
from pathlib import Path
from scene_wallpaper_authored_effects import authored_effect_graph_failures
from scene_wallpaper_effect_execution import effect_execution_failures
from scene_wallpaper_effect_preparation import effect_stage_admission_failures
from scene_wallpaper_graph_acceptance import resolved_material_graph_execution_failures
from scene_wallpaper_layer_runtime import (
    particle_runtime_failures, puppet_animation_runtime_failures, solid_runtime_failures,
    startup_runtime_failures,
)
from scene_wallpaper_performance import performance_failures
from scene_wallpaper_pointer_evidence import (
    cursor_interaction_output_failures, cursor_ripple_persistence_failures,
    cursor_ripple_visible_failures, pointer_trajectory_minimum_changed_ratio,
)
from scene_wallpaper_property_updates import (
    live_property_output_failures, live_property_update_failures,
)
from scene_wallpaper_utility_capture import named_target_binding_failures, utility_runtime_failures
from typing import Any


def sample_result_failures(
    sample: dict[str, Any],
    result: dict[str, Any],
    *,
    authored_opacity_runtime_count: int,
    camera_match: re.Match[str] | None,
    camera_shake_match: re.Match[str] | None,
    execution_observations_enabled: bool,
    live_property_overrides: Any,
    log_text: str,
    media_thumbnail_store: dict[str, Any],
    named_graph_output_publication_execution: dict[str, Any],
    named_target_binding_execution: dict[str, Any],
    named_target_capture_execution: dict[str, Any],
    particle_runtime: dict[str, Any],
    puppet_animation_runtime: dict[str, Any],
    ready_match: re.Match[str] | None,
    require_cursor_ripple_persistence: bool,
    require_effect_execution: bool,
    require_effect_stage_admission: bool,
    require_graph_execution: bool,
    result_dir: Path,
    runtime_evidence_match: re.Match[str] | None,
    solid_runtime: dict[str, Any],
    stopped_match: re.Match[str] | None,
    utility_capture_execution: dict[str, Any],
    utility_runtime: dict[str, Any],
    visible_graph_output_publication_execution: dict[str, Any],
) -> list[str]:
    """Validate collected evidence without parsing or executing another run."""
    runtime = result["runtime"]
    evidence = result["evidence"]
    failures: list[str] = []
    if result['timed_out']:
        failures.append("process timeout")
    if result['exit_code'] != 0:
        failures.append(f"process exit {result['exit_code']}")
    if ready_match is None:
        failures.append("missing ready event")
    elif int(ready_match.group("surfaces")) < 1:
        failures.append("no Scene surface")
    else:
        failures.extend(startup_runtime_failures(sample, runtime['startup_ready_ms']))
    failures.extend(performance_failures(runtime['performance']))
    failures.extend(runtime['audio_scaled_value']["failures"])
    if runtime_evidence_match is None:
        failures.append("missing runtime evidence path")
    elif Path(evidence['runtime_evidence']).resolve() != (
        result_dir / "scene-runtime-evidence.json"
    ).resolve():
        failures.append("Scene runtime evidence path is outside Debug evidence directory")
    if evidence['sample_root_residue']:
        failures.append(
            "Scene sample root contains derived files: " + ", ".join(evidence['sample_root_residue'])
        )
    if stopped_match is None or int(stopped_match.group("after")) != 0:
        failures.append("Scene surfaces not released")
    failures.extend(live_property_update_failures(
        live_property_overrides,
        runtime['live_property_update'],
    ))
    failures.extend(runtime['deferred_property_transition']["validation_failures"])
    failures.extend(cursor_ripple_persistence_failures(
        runtime['cursor_ripple_persistence'],
        require_evidence=require_cursor_ripple_persistence,
    ))
    failures.extend(cursor_ripple_visible_failures(
        runtime['cursor_ripple_visible'],
        require_evidence=require_cursor_ripple_persistence,
    ))
    if "phase=snapshot-failed" in log_text:
        failures.append("window snapshot failed")
    if runtime['hover_pointer_normalized'] is not None:
        if log_text.count("phase=pointer-state state=outside") != 2:
            failures.append("pointer outside transition evidence mismatch")
        if runtime['hover_pointer_stationary_entry']:
            if "phase=pointer-state state=move" in log_text:
                failures.append("stationary pointer unexpectedly injected movement")
        elif "phase=pointer-state state=move" not in log_text:
            failures.append("pointer movement transition evidence missing")
        if "phase=pointer-state state=hold" not in log_text:
            failures.append("pointer stationary transition evidence missing")
        if runtime['cursor_primary_click'] or runtime['cursor_drag_to_normalized'] is not None:
            if log_text.count("phase=pointer-state state=press") != 1:
                failures.append("primary pointer press evidence mismatch")
            if log_text.count("phase=pointer-state state=release") != 1:
                failures.append("primary pointer release evidence mismatch")
        if runtime['cursor_drag_to_normalized'] is not None:
            if log_text.count("phase=pointer-state state=drag") != 1:
                failures.append("primary pointer drag evidence mismatch")
    if camera_match is None or camera_match.group("projection") != "cover":
        failures.append("camera projection evidence missing")
    expected_parallax = sample.get("expected_camera_parallax")
    if expected_parallax is not None:
        actual_parallax = camera_match and camera_match.group("parallax") == "true"
        if actual_parallax != bool(expected_parallax):
            failures.append("camera parallax state mismatch")
    expected_shake_status = sample.get("expected_camera_shake_status")
    if expected_shake_status is not None:
        actual_status = (
            camera_shake_match.group("status") if camera_shake_match else None
        )
        if actual_status != str(expected_shake_status):
            failures.append("camera shake status mismatch")
    expected_shake_enabled = sample.get("expected_camera_shake_enabled")
    if expected_shake_enabled is not None:
        actual_enabled = (
            camera_shake_match.group("enabled") == "true"
            if camera_shake_match
            and camera_shake_match.group("enabled") != "invalid"
            else None
        )
        if actual_enabled != bool(expected_shake_enabled):
            failures.append("camera shake enabled state mismatch")
    for field in ("amplitude", "roughness", "speed"):
        expected_value = sample.get(f"expected_camera_shake_{field}")
        if expected_value is None:
            continue
        actual_text = camera_shake_match.group(field) if camera_shake_match else None
        actual_value = (
            float(actual_text)
            if actual_text is not None and actual_text != "invalid"
            else None
        )
        if actual_value is None or not math.isclose(
            actual_value, float(expected_value), rel_tol=0, abs_tol=1e-6
        ):
            failures.append(f"camera shake {field} mismatch")
    minimum_parallax_layers = int(sample.get("minimum_authored_parallax_layer_count", 0))
    if runtime['runtime_evidence']["authored_parallax_layer_count"] < minimum_parallax_layers:
        failures.append("authored parallax layer count below minimum")
    if (runtime['loaded_textures'] / runtime['texture_candidates'] if runtime['texture_candidates'] else 0.0) < float(sample.get("minimum_loaded_ratio", 0)):
        failures.append(f"loaded ratio {(runtime['loaded_textures'] / runtime['texture_candidates'] if runtime['texture_candidates'] else 0.0):.3f} below minimum")
    if runtime['loaded_textures_text'] < int(sample.get("minimum_text_loaded", 0)):
        failures.append("text texture count below minimum")
    if "expected_text_candidates" in sample and runtime['text_candidates'] != int(sample["expected_text_candidates"]):
        failures.append("text candidate count mismatch")
    for layer_id in sample.get("required_text_loaded_layer_ids", []):
        if layer_id not in runtime['text_loaded_layer_ids']:
            failures.append(f"text layer {layer_id} should be loaded")
    failures.extend(solid_runtime_failures(sample, solid_runtime))
    failures.extend(
        puppet_animation_runtime_failures(sample, puppet_animation_runtime)
    )
    failures.extend(utility_runtime_failures(
        sample, utility_runtime, capture_execution=utility_capture_execution,
        graph_execution=runtime['resolved_material_graph_execution'],
        execution_observations_enabled=execution_observations_enabled,
    ))
    failures.extend(authored_effect_graph_failures(
        sample,
        workshop_shadow_count=runtime['authored_effect_graph_workshop_shadow_count'],
        procedural_noise_count=runtime['authored_effect_graph_procedural_noise_count'],
        film_grain_count=runtime['authored_effect_graph_film_grain_count'],
        light_shafts_count=runtime['authored_effect_graph_light_shafts_count'],
        shake_count=runtime['authored_effect_graph_shake_count'],
        water_flow_count=runtime['authored_effect_graph_water_flow_count'],
        water_waves_count=runtime['authored_effect_graph_water_waves_count'],
        water_caustics_count=runtime['authored_effect_graph_water_caustics_count'],
        foliage_sway_count=runtime['authored_effect_graph_foliage_sway_count'],
        water_ripple_count=runtime['authored_effect_graph_water_ripple_count'],
        iris_inline_suffix_count=runtime['authored_effect_graph_iris_inline_suffix_count'],
        cursor_ripple_count=runtime['authored_effect_graph_cursor_ripple_count'],
        cursor_ripple_isolated_count=runtime['authored_effect_graph_cursor_ripple_isolated_count'],
        cursor_ripple_omitted_effects=runtime['authored_effect_graph_cursor_ripple_omitted_effects'],
        clipping_mask_count=runtime['authored_effect_graph_clipping_mask_count'],
        blend_count=runtime['authored_effect_graph_blend_count'],
        tint_count=runtime['authored_effect_graph_tint_count'],
        pulse_count=runtime['authored_effect_graph_pulse_count'],
        godrays_count=runtime['authored_effect_graph_godrays_count'],
        transform_count=runtime['authored_effect_graph_transform_count'],
        transform_static_fallback_count=runtime['authored_effect_graph_transform_static_fallback_count'],
        transform_static_fallback_diagnostics=(
            runtime['authored_effect_graph_transform_static_fallback_diagnostics']
        ),
        authored_shader_count=runtime['authored_effect_graph_authored_shader_count'],
        scroll_count=runtime['authored_effect_graph_scroll_count'],
        opacity_count=runtime['authored_effect_graph_opacity_count'],
        color_key_count=runtime['authored_effect_graph_color_key_count'],
        workshop_audio_bars_count=runtime['authored_effect_graph_workshop_audio_bars_count'],
        fisheye_zero_distortion_count=(
            runtime['authored_effect_graph_fisheye_zero_distortion_count']
        ),
        opacity_layer_ids=runtime['authored_effect_graph_opacity_layer_ids'],
    ))
    failures.extend(effect_stage_admission_failures(
        sample,
        runtime['effect_stage_admission'],
        require_evidence=require_effect_stage_admission,
    ))
    failures.extend(runtime['authored_effect_stage_compile']["validation_failures"])
    failures.extend(runtime['effect_runtime_disposition']["validation_failures"])
    failures.extend(effect_execution_failures(
        runtime['effect_execution'],
        require_evidence=require_effect_execution,
        sample=sample,
        static_disposition=runtime['effect_runtime_disposition'],
    ))
    failures.extend(resolved_material_graph_execution_failures(
        runtime['resolved_material_graph_execution'],
        require_evidence=require_graph_execution,
        sample=sample,
    ))
    succeeded_named_target_ids = set(
        runtime['named_target_capture_succeeded_layer_ids']
    ).union(
        runtime['visible_graph_output_publication_succeeded_layer_ids'],
        runtime['named_graph_output_publication_succeeded_layer_ids'],
    )
    for label, execution in (
        ("named target capture", named_target_capture_execution),
        ("visible graph output publication", visible_graph_output_publication_execution),
        ("named graph output publication", named_graph_output_publication_execution),
    ):
        if not execution_observations_enabled and execution["failed_layer_ids"]:
            failures.append(f"{label} execution reported failures")
    if (
        execution_observations_enabled
        and len(succeeded_named_target_ids) < runtime['utility_named_target_planned']
    ):
        failures.append("named target capture execution below planned count")
    for layer_id in sample.get("required_named_target_capture_succeeded_layer_ids", []):
        if layer_id not in succeeded_named_target_ids:
            failures.append(f"named target layer {layer_id} capture should succeed")
    for layer_id in sample.get(
        "required_visible_graph_output_publication_succeeded_layer_ids", []
    ):
        if layer_id not in runtime['visible_graph_output_publication_succeeded_layer_ids']:
            failures.append(
                f"visible graph output provider {layer_id} publication should succeed"
            )
    for layer_id in sample.get(
        "required_named_graph_output_publication_succeeded_layer_ids", []
    ):
        if layer_id not in runtime['named_graph_output_publication_succeeded_layer_ids']:
            failures.append(
                f"named graph output provider {layer_id} publication should succeed"
            )
    failures.extend(named_target_binding_failures(
        sample,
        runtime['utility_named_binding_planned'],
        named_target_binding_execution,
        conditional_count=runtime['utility_named_binding_conditional'],
        utility_metrics=utility_runtime,
        execution_observations_enabled=execution_observations_enabled,
    ))
    failures.extend(particle_runtime_failures(sample, particle_runtime))
    if runtime['gaussian_blur_runtime_count'] < int(sample.get("minimum_gaussian_blur_runtime_count", 0)):
        failures.append("gaussian blur runtime count below minimum")
    if runtime['precise_blur_runtime_count'] < int(sample.get("minimum_precise_blur_runtime_count", 0)):
        failures.append("precise gaussian blur runtime count below minimum")
    if authored_opacity_runtime_count < int(
        sample.get("minimum_authored_opacity_runtime_count", 0)
    ):
        failures.append("authored opacity runtime count below minimum")
    if runtime['skipped_unsupported_composite_count'] < int(sample.get("minimum_skipped_composite_count", 0)):
        failures.append("unsupported composite fallback count below minimum")
    maximum_skipped_composite_count = sample.get("maximum_skipped_composite_count")
    if maximum_skipped_composite_count is not None:
        if runtime['skipped_unsupported_composite_count'] > int(maximum_skipped_composite_count):
            failures.append("unsupported composite fallback count above maximum")
    if runtime['perspective_opacity_runtime_count'] < int(sample.get("minimum_perspective_opacity_runtime_count", 0)):
        failures.append("perspective opacity runtime count below minimum")
    if runtime['water_ripple_normal_runtime_count'] < int(sample.get("minimum_water_ripple_normal_runtime_count", 0)):
        failures.append("normal-map water ripple runtime count below minimum")
    if runtime['water_ripple_normal_load_count'] < int(sample.get("minimum_water_ripple_normal_load_count", 0)):
        failures.append("normal-map water ripple texture load count below minimum")
    if runtime['legacy_water_ripple_runtime_count'] < int(sample.get("minimum_legacy_water_ripple_runtime_count", 0)):
        failures.append("legacy water ripple runtime count below minimum")
    maximum_legacy_water_ripple_count = sample.get("maximum_legacy_water_ripple_runtime_count")
    if maximum_legacy_water_ripple_count is not None:
        if runtime['legacy_water_ripple_runtime_count'] > int(maximum_legacy_water_ripple_count):
            failures.append("legacy water ripple runtime count above maximum")
    if runtime['sprite_animation_count'] < int(sample.get("minimum_sprite_animation_count", 0)):
        failures.append("sprite animation runtime count below minimum")
    if runtime['color_blend_mode_9_count'] < int(sample.get("minimum_color_blend_mode_9_count", 0)):
        failures.append("layer color blend mode 9 count below minimum")
    if runtime['runtime_evidence']["schema_version"] is None:
        failures.append("Scene runtime evidence missing or invalid")
    runtime_evidence_expectations = {
        "expected_runtime_evidence_schema": "schema_version",
        "expected_shader_contract_count": "shader_contract_count",
        "expected_shader_contract_authored_count": "shader_contract_authored_count",
        "expected_shader_contract_builtin_count": "shader_contract_builtin_count",
        "expected_shader_contract_stage_count": "shader_contract_stage_count",
        "expected_shader_contract_diagnostic_count": "shader_contract_diagnostic_count",
        "expected_effect_texture_slot_count": "effect_texture_slot_count",
        "expected_effect_texture_slot_hole_count": "effect_texture_slot_hole_count",
        "expected_effect_combo_entry_count": "effect_combo_entry_count",
        "expected_material_texture_slot_count": "material_texture_slot_count",
        "expected_material_texture_slot_hole_count": "material_texture_slot_hole_count",
        "expected_material_combo_entry_count": "material_combo_entry_count",
        "expected_effect_definition_count": "effect_definition_count",
        "expected_effect_definition_pass_count": "effect_definition_pass_count",
        "expected_effect_definition_material_pass_count": "effect_definition_material_pass_count",
        "expected_effect_definition_fbo_count": "effect_definition_fbo_count",
        "expected_effect_definition_copy_command_count": "effect_definition_copy_command_count",
        "expected_effect_definition_swap_command_count": "effect_definition_swap_command_count",
        "expected_effect_definition_diagnostic_count": "effect_definition_diagnostic_count",
        "expected_effect_graph_layer_count": "effect_graph_layer_count",
        "expected_effect_graph_effect_count": "effect_graph_effect_count",
        "expected_effect_graph_node_count": "effect_graph_node_count",
        "expected_effect_graph_material_node_count": "effect_graph_material_node_count",
        "expected_effect_graph_copy_node_count": "effect_graph_copy_node_count",
        "expected_effect_graph_swap_node_count": "effect_graph_swap_node_count",
        "expected_effect_graph_render_target_count": "effect_graph_render_target_count",
        "expected_effect_graph_blocker_count": "effect_graph_blocker_count",
        "expected_effect_graph_unblocked_layer_count": "effect_graph_unblocked_layer_count",
        "expected_visible_layer_count": "visible_layer_count",
        "expected_root_layer_count": "root_layer_count",
        "expected_child_edge_count": "child_edge_count",
        "expected_parent_layer_count": "parent_layer_count",
        "expected_max_hierarchy_depth": "max_hierarchy_depth",
        "expected_effective_visible_layer_count": "effective_visible_layer_count",
        "expected_solid_layer_count": "solid_layer_count",
        "expected_authored_solid_color_layer_count": "authored_solid_color_layer_count",
        "expected_effective_visible_solid_layer_count": "effective_visible_solid_layer_count",
        "expected_built_in_reference_count": "built_in_reference_count",
        "expected_missing_resource_count": "missing_resource_count",
        "expected_composition_layer_count": "composition_layer_count",
        "expected_project_layer_count": "project_layer_count",
        "expected_fullscreen_layer_count": "fullscreen_layer_count",
        "expected_dependency_edge_count": "dependency_edge_count",
    }
    for expectation, metric in runtime_evidence_expectations.items():
        if expectation in sample and runtime['runtime_evidence'][metric] != int(sample[expectation]):
            failures.append(f"Scene runtime evidence {metric} mismatch")
    expected_effect_graph_sha256 = sample.get("expected_effect_graph_sha256")
    if expected_effect_graph_sha256 is not None:
        if runtime['runtime_evidence']["effect_graph_sha256"] != expected_effect_graph_sha256:
            failures.append("Scene runtime evidence effect graph sha256 mismatch")
    expected_opacity_candidates = sample.get(
        "expected_stock_opacity_single_effect_candidate_layer_ids"
    )
    if expected_opacity_candidates is not None:
        if (
            runtime['runtime_evidence']["stock_opacity_single_effect_candidate_layer_ids"]
            != sorted(expected_opacity_candidates)
        ):
            failures.append("Scene runtime evidence stock Opacity candidate IDs mismatch")
    expected_shader_contract_aggregate_sha256 = sample.get(
        "expected_shader_contract_aggregate_sha256"
    )
    if expected_shader_contract_aggregate_sha256 is not None:
        if (
            runtime['runtime_evidence']["shader_contract_aggregate_sha256"]
            != expected_shader_contract_aggregate_sha256
        ):
            failures.append("Scene runtime evidence shader contract aggregate sha256 mismatch")
    expected_text_value = sample.get("expected_text_value")
    if expected_text_value is not None and expected_text_value not in runtime['runtime_evidence']["text_values"]:
        failures.append("Scene runtime evidence text property mismatch")
    expected_text_script_binding_count = sample.get("expected_text_script_binding_count")
    if expected_text_script_binding_count is not None:
        if runtime['text_script_binding_count'] != int(expected_text_script_binding_count):
            failures.append("text script binding count mismatch")
    required_text_script_binding_layer_ids = sorted(
        int(layer_id)
        for layer_id in sample.get("required_text_script_binding_layer_ids", [])
    )
    if required_text_script_binding_layer_ids:
        if runtime['text_script_binding_layer_ids'] != required_text_script_binding_layer_ids:
            failures.append("text script binding layer IDs mismatch")
    expected_scene_script_scalar_binding_count = sample.get(
        "expected_scene_script_scalar_binding_count"
    )
    if expected_scene_script_scalar_binding_count is not None:
        if runtime['scene_script_scalar_binding_count'] != int(
            expected_scene_script_scalar_binding_count
        ):
            failures.append("SceneScript scalar binding count mismatch")
    required_scene_script_scalar_bindings = sample.get(
        "required_scene_script_scalar_bindings", []
    )
    if required_scene_script_scalar_bindings:
        if runtime['scene_script_scalar_bindings'] != required_scene_script_scalar_bindings:
            failures.append("SceneScript scalar bindings mismatch")
    expected_media_thumbnail_count = sample.get(
        "expected_media_thumbnail_current_binding_count"
    )
    if expected_media_thumbnail_count is not None:
        if runtime['media_thumbnail_current_binding_count'] != int(
            expected_media_thumbnail_count
        ):
            failures.append("media thumbnail current binding count mismatch")
    required_media_thumbnail_layer_ids = sorted(
        int(layer_id)
        for layer_id in sample.get(
            "required_media_thumbnail_current_binding_layer_ids",
            [],
        )
    )
    if required_media_thumbnail_layer_ids:
        if (
            runtime['media_thumbnail_current_binding_layer_ids']
            != required_media_thumbnail_layer_ids
        ):
            failures.append("media thumbnail current binding layer IDs mismatch")
    expected_previous_media_thumbnail_count = sample.get(
        "expected_media_thumbnail_previous_binding_count"
    )
    if expected_previous_media_thumbnail_count is not None:
        if runtime['media_thumbnail_previous_binding_count'] != int(
            expected_previous_media_thumbnail_count
        ):
            failures.append("media thumbnail previous binding count mismatch")
    required_previous_media_thumbnail_layer_ids = sorted(
        int(layer_id)
        for layer_id in sample.get(
            "required_media_thumbnail_previous_binding_layer_ids",
            [],
        )
    )
    if required_previous_media_thumbnail_layer_ids:
        if (
            runtime['media_thumbnail_previous_binding_layer_ids']
            != required_previous_media_thumbnail_layer_ids
        ):
            failures.append("media thumbnail previous binding layer IDs mismatch")
    expected_media_store_values = (
        (
            "required_media_thumbnail_pending_last_ready",
            "pending_last_ready",
        ),
        (
            "required_media_thumbnail_ready_states",
            "ready_states",
        ),
    )
    for expectation, metric in expected_media_store_values:
        if expectation in sample:
            if media_thumbnail_store[metric] != sample[expectation]:
                failures.append(f"media thumbnail store {metric} mismatch")
    if "expected_media_thumbnail_clear_count" in sample:
        if runtime['media_thumbnail_clear_count'] != int(
            sample["expected_media_thumbnail_clear_count"]
        ):
            failures.append("media thumbnail clear count mismatch")
    visible_layer_ids = set(runtime['runtime_evidence']["visible_layer_ids"])
    for layer_id in sample.get("required_visible_layer_ids", []):
        if layer_id not in visible_layer_ids:
            failures.append(f"Scene property layer {layer_id} should be visible")
    for layer_id in sample.get("required_hidden_layer_ids", []):
        if layer_id in visible_layer_ids:
            failures.append(f"Scene property layer {layer_id} should be hidden")
    effective_visible_layer_ids = set(runtime['runtime_evidence']["effective_visible_layer_ids"])
    for layer_id in sample.get("required_effectively_visible_layer_ids", []):
        if layer_id not in effective_visible_layer_ids:
            failures.append(f"Scene layer {layer_id} should be effectively visible")
    for layer_id in sample.get("required_effectively_hidden_layer_ids", []):
        if layer_id in effective_visible_layer_ids:
            failures.append(f"Scene layer {layer_id} should be effectively hidden")
    solid_layer_ids = set(runtime['runtime_evidence']["solid_layer_ids"])
    for layer_id in sample.get("required_solid_layer_ids", []):
        if layer_id not in solid_layer_ids:
            failures.append(f"Scene solid layer {layer_id} is missing")
    effective_visible_solid_layer_ids = set(
        runtime['runtime_evidence']["effective_visible_solid_layer_ids"]
    )
    for layer_id in sample.get("required_effectively_visible_solid_layer_ids", []):
        if layer_id not in effective_visible_solid_layer_ids:
            failures.append(f"Scene solid layer {layer_id} should be effectively visible")
    effect_files = set(runtime['runtime_evidence']["effect_files"])
    for effect_file in sample.get("required_effect_files", []):
        if effect_file not in effect_files:
            failures.append(f"Scene effect file missing: {effect_file}")
    if runtime['bloom_runtime_count'] < int(sample.get("minimum_bloom_runtime_count", 0)):
        failures.append("bloom runtime count below minimum")
    if not evidence['ready_non_black'] or not evidence['after_non_black']:
        failures.append("non-black window evidence missing")
    if runtime['hover_pointer_normalized'] is not None:
        if not evidence['hover_non_black']:
            failures.append("hover window evidence missing")
        if evidence['puppet_interaction'] is not None:
            failures.extend(evidence['puppet_interaction']["failures"])
        failures.extend(cursor_interaction_output_failures(
            sample, evidence['hover_motion'], runtime['cursor_drag_to_normalized']
        ))
    if runtime['pointer_trajectory_normalized'] is not None:
        if not all(evidence['pointer_trajectory_non_black']):
            failures.append("pointer trajectory window evidence missing")
        minimum_trajectory_change = pointer_trajectory_minimum_changed_ratio(sample)
        if minimum_trajectory_change is not None and (
            evidence['pointer_trajectory_motion'] is None
            or any(
                metric is None
                or metric["changed_ratio"] < float(minimum_trajectory_change)
                for metric in evidence['pointer_trajectory_motion']
            )
        ):
            failures.append("pointer trajectory output evidence below minimum")
    if sample.get("requires_motion"):
        minimum_changed_ratio = float(sample.get("minimum_changed_ratio", 0))
        if evidence['motion'] is None or evidence['motion']["changed_ratio"] < minimum_changed_ratio:
            failures.append("animated output evidence below minimum")
    failures.extend(live_property_output_failures(sample, evidence['motion']))
    maximum_changed_ratio = sample.get("maximum_changed_ratio")
    if maximum_changed_ratio is not None:
        if evidence['motion'] is None or evidence['motion']["changed_ratio"] > float(maximum_changed_ratio):
            failures.append("static output evidence above maximum")
    maximum_flat_border_ratio = sample.get("maximum_flat_border_ratio")
    if maximum_flat_border_ratio is not None:
        ratios = [value for value in evidence['flat_border_ratio'].values() if value is not None]
        expected_ratio_count = 3 if runtime['hover_pointer_normalized'] is not None else 2
        if (
            len(ratios) != expected_ratio_count
            or max(ratios) > float(maximum_flat_border_ratio)
        ):
            failures.append("flat border evidence above maximum")

    return failures

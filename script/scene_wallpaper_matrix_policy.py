"""Select Scene matrix inputs and reject incompatible observation promises."""

from __future__ import annotations


from pathlib import Path
from scene_matrix_contract import (
    EFFECT_EXECUTION_EXPECTATIONS, RESOLVED_MATERIAL_GRAPH_EXPECTATIONS,
)
from scene_matrix_suite import load_scene_matrix
from scene_wallpaper_pointer_evidence import (
    cursor_drag_to_normalized, cursor_primary_click, cursor_primary_click_subframe,
    hover_pointer_from_launch, hover_pointer_normalized, hover_pointer_stationary_entry,
    pointer_trajectory_minimum_changed_ratio, pointer_trajectory_normalized,
)
from typing import Any


def validate_execution_observation_policy(
    *,
    execution_observations_enabled: bool,
    require_effect_execution: bool = False,
    require_graph_execution: bool = False,
    sample: dict[str, Any] | None = None,
) -> None:
    if execution_observations_enabled:
        return
    conflicts = []
    if require_effect_execution:
        conflicts.append("--require-effect-execution")
    if require_graph_execution:
        conflicts.append("--require-graph-execution")
    execution_expectations = {
        expectation.matrix_key
        for expectation in (
            *EFFECT_EXECUTION_EXPECTATIONS,
            *RESOLVED_MATERIAL_GRAPH_EXPECTATIONS,
        )
    }.union({
        "expected_effect_execution_local_fallbacks",
        "expected_resolved_material_graph_local_fallback_layer_ids",
        "expected_resolved_material_graph_local_fallbacks",
        "expected_resolved_material_graph_effect_local_passthroughs",
        "expected_resolved_material_graph_target_descriptor_counts",
        "expected_resolved_material_graph_extent_lifecycle",
        "expected_effect_recoveries",
        "required_activation_passthrough_reason_codes",
        "minimum_activation_passthrough_count",
        "required_utility_capture_succeeded_layer_ids",
        "required_named_target_capture_succeeded_layer_ids",
        "required_visible_graph_output_publication_succeeded_layer_ids",
        "required_named_graph_output_publication_succeeded_layer_ids",
        "required_named_target_binding_succeeded_layer_ids",
    })
    conflicts.extend(sorted(execution_expectations.intersection(sample or {})))
    if conflicts:
        sample_label = (
            f" for sample {sample['id']}" if sample and "id" in sample else ""
        )
        raise ValueError(
            "--no-execution-observations conflicts with execution requirements"
            + sample_label + ": " + ", ".join(conflicts)
        )

def load_matrix(path: Path) -> dict[str, Any]:
    payload = load_scene_matrix(path)
    for sample in payload["samples"]:
        if not isinstance(sample, dict):
            raise ValueError(f"invalid Scene matrix sample: {path}")
        hover_pointer = hover_pointer_normalized(sample)
        stationary_entry = hover_pointer_stationary_entry(sample)
        from_launch_hover = hover_pointer_from_launch(sample)
        primary_click = cursor_primary_click(sample)
        subframe_click = cursor_primary_click_subframe(sample)
        drag_pointer = cursor_drag_to_normalized(sample)
        pointer_trajectory = pointer_trajectory_normalized(sample)
        minimum_trajectory_change = pointer_trajectory_minimum_changed_ratio(sample)
        if minimum_trajectory_change is not None and pointer_trajectory is None:
            raise ValueError(
                "minimum_pointer_trajectory_changed_ratio requires "
                "pointer_trajectory_normalized"
            )
        if from_launch_hover and hover_pointer is None:
            raise ValueError(
                "hover_pointer_from_launch requires hover_pointer_normalized"
            )
        if stationary_entry and hover_pointer is None:
            raise ValueError(
                "hover_pointer_stationary_entry requires hover_pointer_normalized"
            )
        if primary_click and hover_pointer is None:
            raise ValueError(
                "cursor_primary_click requires hover_pointer_normalized"
            )
        if subframe_click and not primary_click:
            raise ValueError(
                "cursor_primary_click_subframe requires cursor_primary_click"
            )
        if drag_pointer is not None and hover_pointer is None:
            raise ValueError(
                "cursor_drag_to_normalized requires hover_pointer_normalized"
            )
        if drag_pointer is not None and primary_click:
            raise ValueError(
                "cursor_drag_to_normalized cannot be combined with cursor_primary_click"
            )
        if pointer_trajectory is not None:
            if hover_pointer is not None:
                raise ValueError(
                    "pointer_trajectory_normalized cannot be combined with hover_pointer_normalized"
                )
            if stationary_entry or primary_click or drag_pointer is not None:
                raise ValueError(
                    "pointer_trajectory_normalized cannot be combined with other pointer interactions"
                )
    return payload

def select_matrix_samples(
    matrix: dict[str, Any],
    sample_ids: list[str] | None,
) -> dict[str, Any]:
    if not sample_ids:
        return matrix
    requested = set(sample_ids)
    available = {str(sample["id"]) for sample in matrix["samples"]}
    missing = sorted(requested - available)
    if missing:
        raise ValueError(
            "Scene matrix does not contain requested sample IDs: " + ", ".join(missing)
        )
    return {
        **matrix,
        "samples": [
            sample for sample in matrix["samples"] if str(sample["id"]) in requested
        ],
    }

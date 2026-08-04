"""Shared contracts for Scene benchmark expectations.

The benchmark validates these keys and the matrix refresher rebuilds them from
the same runtime metrics. Keeping the mapping here prevents a new validator
from silently disappearing the next time a tracked matrix is refreshed.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class RuntimeExpectation:
    matrix_key: str
    benchmark_metric: str
    failure_message: str
    comparison: str = "integer"
    optional_group: str | None = None

    @property
    def report_metric(self) -> str:
        return self.matrix_key.removeprefix("expected_")


@dataclass(frozen=True)
class NestedRuntimeExpectation:
    matrix_key: str
    report_path: tuple[str, ...]
    failure_message: str
    comparison: str = "exact"

    @property
    def metric_key(self) -> str:
        return self.report_path[-1]


EFFECT_EXECUTION_EXACT_KINDS = frozenset({
    "strict-dedicated",
    "strict-generic",
    "strict-inline-suffix",
    "legacy-exact-inline",
    "legacy-exact-offscreen",
})
EFFECT_EXECUTION_AGGREGATE_KINDS = frozenset({
    "legacy-coalesced-inline",
    "legacy-coalesced-offscreen",
})
EFFECT_EXECUTION_ROUTE_GROUP_KINDS = frozenset({
    "direct",
    "authored",
    "legacy-offscreen",
    "offscreen-passthrough",
    "composite-refused",
})
RESOLVED_MATERIAL_GRAPH_BACKEND = "resolved-material-graph"


@dataclass(frozen=True)
class EffectExecutionStaticDemand:
    static_is_valid: bool
    eligible_exact_effect_count: int = 0
    eligible_aggregate_subject_count: int = 0
    route_group_count: int = 0

    @property
    def has_demand(self) -> bool:
        return bool(
            self.eligible_exact_effect_count
            or self.eligible_aggregate_subject_count
            or self.route_group_count
        )

    @property
    def requires_evidence(self) -> bool:
        return not self.static_is_valid or self.has_demand


def effect_execution_static_demand(
    disposition: dict[str, object] | None,
) -> EffectExecutionStaticDemand:
    if not (
        isinstance(disposition, dict)
        and disposition.get("has_evidence") is True
        and disposition.get("schema_version") == 1
        and disposition.get("validation_failures") == []
    ):
        return EffectExecutionStaticDemand(static_is_valid=False)

    records = disposition.get("records")
    groups = disposition.get("groups")
    if not (
        isinstance(records, list)
        and all(isinstance(record, dict) for record in records)
        and isinstance(groups, list)
        and all(isinstance(group, dict) for group in groups)
    ):
        return EffectExecutionStaticDemand(static_is_valid=False)

    group_kinds = {group.get("kind") for group in groups}
    if not group_kinds.issubset(
        EFFECT_EXECUTION_ROUTE_GROUP_KINDS | {"inactive"}
    ):
        return EffectExecutionStaticDemand(static_is_valid=False)

    aggregate_subjects = {
        (record.get("layer_id"), record.get("family"))
        for record in records
        if record.get("kind") in EFFECT_EXECUTION_AGGREGATE_KINDS
    }
    return EffectExecutionStaticDemand(
        static_is_valid=True,
        eligible_exact_effect_count=sum(
            record.get("kind") in EFFECT_EXECUTION_EXACT_KINDS
            for record in records
        ),
        eligible_aggregate_subject_count=len(aggregate_subjects),
        route_group_count=sum(
            group.get("kind") in EFFECT_EXECUTION_ROUTE_GROUP_KINDS
            for group in groups
        ),
    )


EFFECT_STAGE_ADMISSION_EXPECTATIONS = (
    NestedRuntimeExpectation(
        "expected_effect_stage_admission_schema",
        ("runtime", "authored_effect_stage_admission", "schema_version"),
        "effect stage admission schema mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_stage_descriptor_count",
        ("runtime", "authored_effect_stage_admission", "descriptor_count"),
        "effect stage admission descriptor count mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_stage_parsed_count",
        ("runtime", "authored_effect_stage_admission", "parsed_count"),
        "effect stage admission parsed count mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_stage_activity_counts",
        ("runtime", "authored_effect_stage_admission", "activity_counts"),
        "effect stage admission activity counts mismatch",
    ),
    NestedRuntimeExpectation(
        "expected_effect_stage_strict_admission_counts",
        (
            "runtime",
            "authored_effect_stage_admission",
            "strict_admission_counts",
        ),
        "effect stage admission strict counts mismatch",
    ),
    NestedRuntimeExpectation(
        "expected_effect_stage_coverage_counts",
        ("runtime", "authored_effect_stage_admission", "coverage_counts"),
        "effect stage admission coverage counts mismatch",
    ),
    NestedRuntimeExpectation(
        "expected_effect_stage_admission_sha256",
        ("runtime", "authored_effect_stage_admission", "canonical_sha256"),
        "effect stage admission sha256 mismatch",
    ),
)


EFFECT_RUNTIME_DISPOSITION_EXPECTATIONS = (
    NestedRuntimeExpectation(
        "expected_effect_runtime_disposition_schema",
        ("runtime", "effect_runtime_disposition", "schema_version"),
        "effect runtime disposition schema mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_runtime_disposition_record_count",
        ("runtime", "effect_runtime_disposition", "record_count"),
        "effect runtime disposition record count mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_runtime_disposition_group_count",
        ("runtime", "effect_runtime_disposition", "group_count"),
        "effect runtime disposition group count mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_runtime_disposition_kind_counts",
        ("runtime", "effect_runtime_disposition", "kind_counts"),
        "effect runtime disposition kind counts mismatch",
    ),
    NestedRuntimeExpectation(
        "expected_effect_runtime_disposition_attribution_counts",
        ("runtime", "effect_runtime_disposition", "attribution_counts"),
        "effect runtime disposition attribution counts mismatch",
    ),
    NestedRuntimeExpectation(
        "expected_effect_runtime_disposition_role_counts",
        ("runtime", "effect_runtime_disposition", "role_counts"),
        "effect runtime disposition role counts mismatch",
    ),
    NestedRuntimeExpectation(
        "expected_effect_runtime_disposition_group_kind_counts",
        ("runtime", "effect_runtime_disposition", "group_kind_counts"),
        "effect runtime disposition group kind counts mismatch",
    ),
    NestedRuntimeExpectation(
        "expected_effect_runtime_disposition_sha256",
        ("runtime", "effect_runtime_disposition", "canonical_sha256"),
        "effect runtime disposition sha256 mismatch",
    ),
)


EFFECT_EXECUTION_EXPECTATIONS = (
    NestedRuntimeExpectation(
        "expected_effect_execution_schema",
        ("runtime", "effect_execution", "schema_version"),
        "effect execution schema mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_execution_eligible_exact_effect_count",
        ("runtime", "effect_execution", "eligible_exact_effect_count"),
        "effect execution eligible exact count mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_execution_observed_eligible_exact_effect_count",
        (
            "runtime",
            "effect_execution",
            "observed_eligible_exact_effect_count",
        ),
        "effect execution observed exact count mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_execution_eligible_exact_gap_count",
        ("runtime", "effect_execution", "eligible_exact_gap_count"),
        "effect execution exact gap count mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_execution_eligible_aggregate_subject_count",
        (
            "runtime",
            "effect_execution",
            "eligible_aggregate_subject_count",
        ),
        "effect execution eligible aggregate count mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_execution_observed_eligible_aggregate_subject_count",
        (
            "runtime",
            "effect_execution",
            "observed_eligible_aggregate_subject_count",
        ),
        "effect execution observed aggregate count mismatch",
        comparison="integer",
    ),
    NestedRuntimeExpectation(
        "expected_effect_execution_eligible_aggregate_gap_count",
        (
            "runtime",
            "effect_execution",
            "eligible_aggregate_gap_count",
        ),
        "effect execution aggregate gap count mismatch",
        comparison="integer",
    ),
)


RESOLVED_MATERIAL_GRAPH_EXPECTATIONS = (
    NestedRuntimeExpectation(
        "expected_resolved_material_graph_succeeded_layer_ids",
        (
            "runtime",
            "resolved_material_graph_execution",
            "succeeded_layer_ids",
        ),
        "resolved material graph succeeded layer IDs mismatch",
        comparison="sorted_list",
    ),
)


AUTHORED_EFFECT_RUNTIME_EXPECTATIONS = (
    RuntimeExpectation(
        "expected_authored_effect_graph_local_contrast_count",
        "local_contrast_count",
        "authored effect graph Local Contrast count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_opacity_count",
        "opacity_count",
        "authored effect graph Opacity count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_color_key_count",
        "color_key_count",
        "authored effect graph Color Key count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_workshop_audio_bars_count",
        "workshop_audio_bars_count",
        "authored effect graph Workshop Audio Bars count mismatch",
        optional_group="workshop_audio_bars",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_fisheye_zero_distortion_count",
        "fisheye_zero_distortion_count",
        "authored effect graph Fisheye Zero Distortion count mismatch",
        optional_group="fisheye_zero_distortion",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_opacity_layer_ids",
        "opacity_layer_ids",
        "authored effect graph Opacity layer IDs mismatch",
        comparison="sorted_list",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_workshop_shadow_count",
        "workshop_shadow_count",
        "authored effect graph Workshop Shadow count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_spin_count",
        "spin_count",
        "authored effect graph Spin count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_procedural_noise_count",
        "procedural_noise_count",
        "authored effect graph Procedural Noise count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_film_grain_count",
        "film_grain_count",
        "authored effect graph Film Grain count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_light_shafts_count",
        "light_shafts_count",
        "authored effect graph Light Shafts count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_shake_count",
        "shake_count",
        "authored effect graph Shake count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_water_flow_count",
        "water_flow_count",
        "authored effect graph Water Flow count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_water_waves_count",
        "water_waves_count",
        "authored effect graph Water Waves count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_water_caustics_count",
        "water_caustics_count",
        "authored effect graph Water Caustics count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_foliage_sway_count",
        "foliage_sway_count",
        "authored effect graph Foliage Sway count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_water_ripple_count",
        "water_ripple_count",
        "authored effect graph Water Ripple count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_depth_parallax_count",
        "depth_parallax_count",
        "authored effect graph Depth Parallax count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_iris_inline_suffix_count",
        "iris_inline_suffix_count",
        "authored effect graph Iris inline suffix count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_cursor_ripple_count",
        "cursor_ripple_count",
        "authored effect graph Cursor Ripple count mismatch",
        optional_group="cursor_ripple",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_cursor_ripple_isolated_count",
        "cursor_ripple_isolated_count",
        "authored effect graph isolated Cursor Ripple count mismatch",
        optional_group="cursor_ripple",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_cursor_ripple_omitted_effects",
        "cursor_ripple_omitted_effects",
        "authored effect graph Cursor Ripple omissions mismatch",
        comparison="exact",
        optional_group="cursor_ripple",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_shine_count",
        "shine_count",
        "authored effect graph Shine count mismatch",
        optional_group="shine",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_shine_isolated_count",
        "shine_isolated_count",
        "authored effect graph isolated Shine count mismatch",
        optional_group="shine",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_shine_omitted_effects",
        "shine_omitted_effects",
        "authored effect graph Shine omissions mismatch",
        comparison="exact",
        optional_group="shine",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_clipping_mask_count",
        "clipping_mask_count",
        "authored effect graph Clipping Mask count mismatch",
        optional_group="clipping_mask",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_blend_count",
        "blend_count",
        "authored effect graph Blend count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_tint_count",
        "tint_count",
        "authored effect graph Tint count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_color_grading_count",
        "color_grading_count",
        "authored effect graph Color Grading count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_pulse_count",
        "pulse_count",
        "authored effect graph Pulse count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_godrays_count",
        "godrays_count",
        "authored effect graph Godrays count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_transform_count",
        "transform_count",
        "authored effect graph Transform count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_transform_static_fallback_count",
        "transform_static_fallback_count",
        "authored effect graph Transform static fallback count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_transform_static_fallback_diagnostics",
        "transform_static_fallback_diagnostics",
        "authored effect graph Transform static fallback diagnostics mismatch",
        comparison="exact",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_authored_shader_count",
        "authored_shader_count",
        "authored effect graph authored shader count mismatch",
    ),
    RuntimeExpectation(
        "expected_authored_effect_graph_scroll_count",
        "scroll_count",
        "authored effect graph Scroll count mismatch",
    ),
    RuntimeExpectation(
        "expected_route_only_effect_count",
        "route_only_effect_count",
        "offscreen route-only effect count mismatch",
    ),
)


def optional_group_is_active(
    group: str,
    runtime: dict[str, object],
    old_sample: dict[str, object],
) -> bool:
    members = [
        expectation
        for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
        if expectation.optional_group == group
    ]
    return any(
        expectation.matrix_key in old_sample
        or bool(runtime.get(expectation.report_metric))
        for expectation in members
    )

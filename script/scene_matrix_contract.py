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

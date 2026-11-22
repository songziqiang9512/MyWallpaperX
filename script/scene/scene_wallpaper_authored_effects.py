"""Parse authored effect diagnostics and validate exact family counts."""

from __future__ import annotations

import re
from scene_matrix_contract import AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
from typing import Any


AUTHORED_EFFECT_GRAPH_OPACITY_COUNT_RE = re.compile(
    r"^authoredEffectGraphOpacityCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_COLOR_KEY_COUNT_RE = re.compile(
    r"^authoredEffectGraphColorKeyCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_WORKSHOP_SHIFT_HUE_COUNT_RE = re.compile(
    r"^authoredEffectGraphWorkshopShiftHueCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_WORKSHOP_AUDIO_BARS_COUNT_RE = re.compile(
    r"^authoredEffectGraphWorkshopAudioBarsCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_FISHEYE_ZERO_DISTORTION_COUNT_RE = re.compile(
    r"^authoredEffectGraphFisheyeZeroDistortionCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_WORKSHOP_GRADIENT_COUNT_RE = re.compile(
    r"^authoredEffectGraphWorkshopGradientCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_WORKSHOP_AUDIO_HUE_SHIFT_COUNT_RE = re.compile(
    r"^authoredEffectGraphWorkshopAudioHueShiftCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_OPACITY_LAYER_RE = re.compile(
    r"^(?:(?:image|text|solid) )?layer (?P<id>\d+)\b[^\n]*?"
    r"(?:effect runtime foliagesway-uv; )?"
    r"effect runtime opacity-authored;",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_WORKSHOP_SHADOW_COUNT_RE = re.compile(
    r"^authoredEffectGraphWorkshopShadowCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_PROCEDURAL_NOISE_COUNT_RE = re.compile(
    r"^authoredEffectGraphProceduralNoiseCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_FILM_GRAIN_COUNT_RE = re.compile(
    r"^authoredEffectGraphFilmGrainCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_LIGHT_SHAFTS_COUNT_RE = re.compile(
    r"^authoredEffectGraphLightShaftsCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_SHAKE_COUNT_RE = re.compile(
    r"^authoredEffectGraphShakeCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_WATER_FLOW_COUNT_RE = re.compile(
    r"^authoredEffectGraphWaterFlowCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_WATER_WAVES_COUNT_RE = re.compile(
    r"^authoredEffectGraphWaterWavesCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_WATER_CAUSTICS_COUNT_RE = re.compile(
    r"^authoredEffectGraphWaterCausticsCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_FOLIAGE_SWAY_COUNT_RE = re.compile(
    r"^authoredEffectGraphFoliageSwayCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_WATER_RIPPLE_COUNT_RE = re.compile(
    r"^authoredEffectGraphWaterRippleCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_IRIS_INLINE_SUFFIX_COUNT_RE = re.compile(
    r"^authoredEffectGraphIrisInlineSuffixCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_CURSOR_RIPPLE_COUNT_RE = re.compile(
    r"^authoredEffectGraphCursorRippleCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_CURSOR_RIPPLE_ISOLATED_COUNT_RE = re.compile(
    r"^authoredEffectGraphCursorRippleIsolatedCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_CURSOR_RIPPLE_OMITTED_EFFECTS_RE = re.compile(
    r"^authoredEffectGraphCursorRippleOmittedEffects: ?(?P<effects>.*)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_CLIPPING_MASK_COUNT_RE = re.compile(
    r"^authoredEffectGraphClippingMaskCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_BLEND_COUNT_RE = re.compile(
    r"^authoredEffectGraphBlendCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_TINT_COUNT_RE = re.compile(
    r"^authoredEffectGraphTintCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_PULSE_COUNT_RE = re.compile(
    r"^authoredEffectGraphPulseCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_GODRAYS_COUNT_RE = re.compile(
    r"^authoredEffectGraphGodraysCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_TRANSFORM_COUNT_RE = re.compile(
    r"^authoredEffectGraphTransformCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_TRANSFORM_STATIC_FALLBACK_COUNT_RE = re.compile(
    r"^authoredEffectGraphTransformStaticFallbackCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_TRANSFORM_STATIC_FALLBACK_DIAGNOSTICS_RE = re.compile(
    r"^authoredEffectGraphTransformStaticFallbackDiagnostics: ?(?P<diagnostics>.*)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_AUTHORED_SHADER_COUNT_RE = re.compile(
    r"^authoredEffectGraphAuthoredShaderCount: (?P<count>\d+)$",
    re.MULTILINE,
)

AUTHORED_EFFECT_GRAPH_SCROLL_COUNT_RE = re.compile(
    r"^authoredEffectGraphScrollCount: (?P<count>\d+)$",
    re.MULTILINE,
)

def authored_effect_graph_opacity_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_OPACITY_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_color_key_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_COLOR_KEY_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_workshop_shift_hue_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WORKSHOP_SHIFT_HUE_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_workshop_audio_bars_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WORKSHOP_AUDIO_BARS_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_fisheye_zero_distortion_count(
    preview_text: str,
) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_FISHEYE_ZERO_DISTORTION_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_workshop_gradient_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WORKSHOP_GRADIENT_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_workshop_audio_hue_shift_count(
    preview_text: str,
) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WORKSHOP_AUDIO_HUE_SHIFT_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_opacity_layer_ids(preview_text: str) -> list[int]:
    return sorted({
        int(match.group("id"))
        for match in AUTHORED_EFFECT_GRAPH_OPACITY_LAYER_RE.finditer(preview_text)
    })

def authored_effect_graph_workshop_shadow_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WORKSHOP_SHADOW_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_procedural_noise_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_PROCEDURAL_NOISE_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_film_grain_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_FILM_GRAIN_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_light_shafts_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_LIGHT_SHAFTS_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_shake_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_SHAKE_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_water_flow_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WATER_FLOW_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_water_waves_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WATER_WAVES_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_water_caustics_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WATER_CAUSTICS_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_foliage_sway_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_FOLIAGE_SWAY_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_water_ripple_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WATER_RIPPLE_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_iris_inline_suffix_count(
    preview_text: str,
) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_IRIS_INLINE_SUFFIX_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_cursor_ripple_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_CURSOR_RIPPLE_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_cursor_ripple_isolated_count(
    preview_text: str,
) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_CURSOR_RIPPLE_ISOLATED_COUNT_RE.search(
        preview_text
    )
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_cursor_ripple_omitted_effects(
    preview_text: str,
) -> list[str] | None:
    match = AUTHORED_EFFECT_GRAPH_CURSOR_RIPPLE_OMITTED_EFFECTS_RE.search(
        preview_text
    )
    if match is None:
        return None
    effects = match.group("effects").strip()
    return effects.split(";") if effects else []

def authored_effect_graph_clipping_mask_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_CLIPPING_MASK_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_blend_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_BLEND_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_tint_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_TINT_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_pulse_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_PULSE_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_godrays_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_GODRAYS_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_transform_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_TRANSFORM_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_transform_static_fallback_count(
    preview_text: str,
) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_TRANSFORM_STATIC_FALLBACK_COUNT_RE.search(
        preview_text
    )
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_transform_static_fallback_diagnostics(
    preview_text: str,
) -> list[str] | None:
    match = AUTHORED_EFFECT_GRAPH_TRANSFORM_STATIC_FALLBACK_DIAGNOSTICS_RE.search(
        preview_text
    )
    if match is None:
        return None
    diagnostics = match.group("diagnostics").strip()
    return diagnostics.split(";") if diagnostics else []

def authored_effect_graph_authored_shader_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_AUTHORED_SHADER_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_scroll_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_SCROLL_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None

def authored_effect_graph_failures(
    sample: dict[str, Any],
    workshop_shadow_count: int | None = None,
    procedural_noise_count: int | None = None,
    film_grain_count: int | None = None,
    light_shafts_count: int | None = None,
    shake_count: int | None = None,
    water_flow_count: int | None = None,
    water_waves_count: int | None = None,
    water_caustics_count: int | None = None,
    foliage_sway_count: int | None = None,
    water_ripple_count: int | None = None,
    iris_inline_suffix_count: int | None = None,
    cursor_ripple_count: int | None = None,
    cursor_ripple_isolated_count: int | None = None,
    cursor_ripple_omitted_effects: list[str] | None = None,
    clipping_mask_count: int | None = None,
    blend_count: int | None = None,
    tint_count: int | None = None,
    pulse_count: int | None = None,
    godrays_count: int | None = None,
    transform_count: int | None = None,
    transform_static_fallback_count: int | None = None,
    transform_static_fallback_diagnostics: list[str] | None = None,
    authored_shader_count: int | None = None,
    scroll_count: int | None = None,
    opacity_count: int | None = None,
    color_key_count: int | None = None,
    workshop_audio_bars_count: int | None = None,
    fisheye_zero_distortion_count: int | None = None,
    opacity_layer_ids: list[int] | None = None,
) -> list[str]:
    failures: list[str] = []
    runtime_values = {
        "opacity_count": opacity_count,
        "color_key_count": color_key_count,
        "workshop_audio_bars_count": workshop_audio_bars_count,
        "fisheye_zero_distortion_count": fisheye_zero_distortion_count,
        "opacity_layer_ids": opacity_layer_ids,
        "workshop_shadow_count": workshop_shadow_count,
        "procedural_noise_count": procedural_noise_count,
        "film_grain_count": film_grain_count,
        "light_shafts_count": light_shafts_count,
        "shake_count": shake_count,
        "water_flow_count": water_flow_count,
        "water_waves_count": water_waves_count,
        "water_caustics_count": water_caustics_count,
        "foliage_sway_count": foliage_sway_count,
        "water_ripple_count": water_ripple_count,
        "iris_inline_suffix_count": iris_inline_suffix_count,
        "cursor_ripple_count": cursor_ripple_count,
        "cursor_ripple_isolated_count": cursor_ripple_isolated_count,
        "cursor_ripple_omitted_effects": cursor_ripple_omitted_effects,
        "clipping_mask_count": clipping_mask_count,
        "blend_count": blend_count,
        "tint_count": tint_count,
        "pulse_count": pulse_count,
        "godrays_count": godrays_count,
        "transform_count": transform_count,
        "transform_static_fallback_count": transform_static_fallback_count,
        "transform_static_fallback_diagnostics":
            transform_static_fallback_diagnostics,
        "authored_shader_count": authored_shader_count,
        "scroll_count": scroll_count,
    }
    for expectation in AUTHORED_EFFECT_RUNTIME_EXPECTATIONS:
        expected = sample.get(expectation.matrix_key)
        if expected is None:
            continue
        actual = runtime_values[expectation.benchmark_metric]
        if expectation.comparison == "integer":
            matches = actual == int(expected)
        elif expectation.comparison == "sorted_list":
            matches = (actual or []) == sorted(expected)
        else:
            matches = actual == expected
        if not matches:
            failures.append(expectation.failure_message)
    return failures

#!/usr/bin/env python3
"""Run isolated, signed-app Scene wallpaper evidence checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from scene_matrix_contract import AUTHORED_EFFECT_RUNTIME_EXPECTATIONS
from web_benchmark_capture import (
    AppIdentityError,
    discard_staged_app,
    png_flat_border_ratio,
    png_has_non_black_pixel,
    png_motion_metrics,
    require_fresh_output_dir,
    stage_signed_app,
    verify_staged_app,
)
from scene_preview_visual_evidence import (
    collect_preview_visual_evidence,
    summarize_preview_visual_evidence,
)


FLOAT_PATTERN = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
READY_RE = re.compile(
    r"phase=ready .* layers=(?P<layers>\d+) imageLayers=(?P<images>\d+) "
    r"effects=(?P<effects>\d+) surfaces=(?P<surfaces>\d+) "
    rf"(?:startupElapsedMS=(?P<startup_elapsed_ms>{FLOAT_PATTERN}) )?"
)
RUNTIME_EVIDENCE_RE = re.compile(
    r"phase=ready .* runtimeEvidence=(?P<path>.+)$",
    re.MULTILINE,
)
STOPPED_RE = re.compile(r"phase=stopped surfacesBefore=(?P<before>\d+) surfacesAfter=(?P<after>\d+)")
PERFORMANCE_LINE_RE = re.compile(r"phase=performance (?P<fields>[^\r\n]+)")
LIVE_PROPERTY_UPDATE_RE = re.compile(
    r"phase=live-property-update accepted=(?P<accepted>true|false) "
    r"surfacesBefore=(?P<before>\d+) surfacesAfter=(?P<after>\d+) "
    r"windowsBefore=(?P<windows_before>[\d,]*) windowsAfter=(?P<windows_after>[\d,]*) "
    r"keys=(?P<keys>[^\n]*)"
)
LOADED_RE = re.compile(r"^loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)
TEXT_LOADED_RE = re.compile(r"^text loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)
TEXT_LAYER_OK_RE = re.compile(r'^text layer (?P<id>\d+) .*: OK ', re.MULTILINE)
TEXT_SCRIPT_BINDING_COUNT_RE = re.compile(
    r"^textScriptBindingCount: (?P<count>\d+)$",
    re.MULTILINE,
)
TEXT_SCRIPT_DIAGNOSTIC_COUNT_RE = re.compile(
    r"^textScriptDiagnosticCount: (?P<count>\d+)$",
    re.MULTILINE,
)
TEXT_SCRIPT_BINDING_RE = re.compile(
    r"^textScript layer (?P<id>\d+) content: profile=(?P<profile>\S+) "
    r"value@fixture=(?P<value>.+)$",
    re.MULTILINE,
)
TIME_OF_DAY_EFFECT_SCRIPT_BINDING_COUNT_RE = re.compile(
    r"^timeOfDayEffectScriptBindingCount: (?P<count>\d+)$",
    re.MULTILINE,
)
TIME_OF_DAY_EFFECT_SCRIPT_DEBUG_WALL_DATE_RE = re.compile(
    r"^timeOfDayEffectScriptDebugWallDate: (?P<value>\S+)$",
    re.MULTILINE,
)
TIME_OF_DAY_EFFECT_SCRIPT_BINDING_RE = re.compile(
    r"^time-of-day effect script: layer=(?P<layer>\d+) "
    r"effect=(?P<effect>\d+) pass=(?P<pass>\d+) constant=(?P<constant>\S+)$",
    re.MULTILINE,
)
MEDIA_THUMBNAIL_CURRENT_BINDING_COUNT_RE = re.compile(
    r"^mediaThumbnailCurrentBindingCount: (?P<count>\d+)$",
    re.MULTILINE,
)
MEDIA_THUMBNAIL_CURRENT_BINDING_LAYER_IDS_RE = re.compile(
    r"^mediaThumbnailCurrentBindingLayerIDs: (?P<ids>[\d,]*)$",
    re.MULTILINE,
)
MEDIA_THUMBNAIL_PREVIOUS_TRANSITION_COUNT_RE = re.compile(
    r"^mediaThumbnailPreviousTransitionCount: (?P<count>\d+)$",
    re.MULTILINE,
)
MEDIA_THUMBNAIL_PREVIOUS_TRANSITION_LAYER_IDS_RE = re.compile(
    r"^mediaThumbnailPreviousTransitionLayerIDs: (?P<ids>[\d,]*)$",
    re.MULTILINE,
)
MEDIA_THUMBNAIL_TRANSITION_EXECUTION_RE = re.compile(
    r"media thumbnail transition: layer=(?P<id>\d+) "
    r"generation=(?P<generation>\d+) phase=(?P<phase>started|midpoint|completed)"
)
MEDIA_THUMBNAIL_PENDING_RE = re.compile(
    r"media thumbnail store: phase=pending-last-ready "
    r"requestedGeneration=(?P<requested>\d+) "
    r"readyGeneration=(?P<ready>\d+) hasCurrent=(?P<current>true|false)"
)
MEDIA_THUMBNAIL_READY_RE = re.compile(
    r"media thumbnail store: phase=ready generation=(?P<generation>\d+) "
    r"hasCurrent=(?P<current>true|false) hasPrevious=(?P<previous>true|false)"
)
MEDIA_THUMBNAIL_CLEAR_RE = re.compile(r"phase=media-thumbnail-cleared")
SCENE_SCRIPT_AUDIO_BARS_PLAN_COUNT_RE = re.compile(
    r"^sceneScriptAudioBarsPlanCount: (?P<count>\d+)$",
    re.MULTILINE,
)
SCENE_SCRIPT_AUDIO_BARS_DIAGNOSTIC_COUNT_RE = re.compile(
    r"^sceneScriptAudioBarsDiagnosticCount: (?P<count>\d+)$",
    re.MULTILINE,
)
SCENE_SCRIPT_AUDIO_BARS_HAS_AUDIO_CONSUMER_RE = re.compile(
    r"^sceneScriptAudioBarsHasAudioConsumer: (?P<value>true|false)$",
    re.MULTILINE | re.IGNORECASE,
)
SCENE_SCRIPT_AUDIO_BARS_PLAN_RE = re.compile(
    r"^sceneScript audio bars: layer=(?P<id>\d+) "
    r"host=(?P<host>\S+) "
    r"sourceSHA256=(?P<source_sha256>[0-9a-fA-F]{64}) "
    r"(?:count|instances)=(?P<bar_count>\d+) "
    r"resolution=(?P<audio_resolution>\d+) "
    r"channel=(?P<channel>\S+) "
    r"model=(?P<model_path>\S+) "
    r"material=(?P<material_path>\S+) "
    r"texture=(?P<texture_path>\S+) "
    rf"width=(?P<width_multiplier>{FLOAT_PATTERN}) "
    rf"height=(?P<height_multiplier>{FLOAT_PATTERN}) "
    rf"depth=(?P<depth_multiplier>{FLOAT_PATTERN}) "
    rf"xStep=(?P<x_step>{FLOAT_PATTERN}) "
    rf"yStep=(?P<y_step>{FLOAT_PATTERN}) "
    rf"angle=(?P<angle_degrees>{FLOAT_PATTERN}) "
    r"alignment=(?P<alignment>\S+) "
    r"firstStep=(?P<first_step>\S+)$",
    re.MULTILINE,
)
PARTICLE_LOADED_RE = re.compile(
    r"^particle loaded: (?P<loaded>\d+) / (?P<total>\d+)$",
    re.MULTILINE,
)
PARTICLE_REFRACT_LOADED_RE = re.compile(
    r"^particle refract loaded: (?P<count>\d+)$",
    re.MULTILINE,
)
PARTICLE_INITIAL_LIVE_RE = re.compile(
    r"^particle initial live: (?P<live>\d+)$",
    re.MULTILINE,
)
PARTICLE_AUTHORED_RE = re.compile(r"^particle authored: (?P<count>\d+)$", re.MULTILINE)
PARTICLE_VISIBLE_RE = re.compile(r"^particle visible: (?P<count>\d+)$", re.MULTILINE)
PARTICLE_SKIPPED_HIDDEN_RE = re.compile(
    r"^particle skipped hidden: (?P<count>\d+)$",
    re.MULTILINE,
)
PARTICLE_SKIPPED_TRANSPARENT_RE = re.compile(
    r"^particle skipped transparent: (?P<count>\d+)$",
    re.MULTILINE,
)
PARTICLE_LAYER_OK_RE = re.compile(r'^particle layer (?P<id>\d+) .*: OK ', re.MULTILINE)
SOLID_LAYER_COUNT_RE = re.compile(r"^solidLayerCount: (?P<count>\d+)$", re.MULTILINE)
SOLID_LAYER_OK_RE = re.compile(
    r'^layer (?P<id>\d+) .*: OK procedural solid(?:\s|$)',
    re.MULTILINE,
)
PUPPET_ANIMATION_OK_RE = re.compile(
    r'^layer (?P<id>\d+) .*?: .*puppet animation OK .*? '
    r'mode=(?P<mode>[a-z-]+) ids=(?P<ids>[\d,]+) clips=(?P<clips>\d+)(?:\s|$)',
    re.MULTILINE,
)
UTILITY_LAYER_COUNT_RE = re.compile(r"^utilityLayerCount: (?P<count>\d+)$", re.MULTILINE)
UTILITY_CAPTURE_COUNT_RE = re.compile(
    r"^utilityCapturePlannedCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_DEPENDENCY_COUNT_RE = re.compile(
    r"^utilityDependencyEdgeCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_NAMED_TARGET_PLANNED_RE = re.compile(
    r"^utilityNamedTargetPlannedCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_NAMED_CONSUMER_COUNT_RE = re.compile(
    r"^utilityNamedConsumerCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_NAMED_BINDING_PLANNED_RE = re.compile(
    r"^utilityNamedBindingPlannedCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_NAMED_TARGET_GAP_RE = re.compile(
    r"^utilityNamedTargetGapCount: (?P<count>\d+)$", re.MULTILINE
)
UTILITY_LAYER_RE = re.compile(
    r"^utility layer (?P<id>\d+): (?P<disposition>\w+) kind=(?P<kind>\w+)",
    re.MULTILINE,
)
UTILITY_CAPTURE_EXECUTION_RE = re.compile(
    r"phase=utility-capture layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
SCENE_SCRIPT_AUDIO_BARS_EXECUTION_RE = re.compile(
    r"phase=scene-script-audio-bars layer=(?P<id>\d+) "
    r"status=(?P<status>succeeded|failed)"
)
AUTHORED_EFFECT_GRAPH_EXECUTION_RE = re.compile(
    r"phase=authored-effect-graph layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
AUTHORED_EFFECT_GRAPH_LEGACY_BLUR_BLOCKED_RE = re.compile(
    r"^authoredEffectGraphLegacyBlurBlockedLayerIDs: ?(?P<ids>[\d,]*)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_LOCAL_CONTRAST_COUNT_RE = re.compile(
    r"^authoredEffectGraphLocalContrastCount: (?P<count>\d+)$",
    re.MULTILINE,
)
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
AUTHORED_EFFECT_GRAPH_SPIN_COUNT_RE = re.compile(
    r"^authoredEffectGraphSpinCount: (?P<count>\d+)$",
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
AUTHORED_EFFECT_GRAPH_FOLIAGE_SWAY_COUNT_RE = re.compile(
    r"^authoredEffectGraphFoliageSwayCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_WATER_RIPPLE_COUNT_RE = re.compile(
    r"^authoredEffectGraphWaterRippleCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_DEPTH_PARALLAX_COUNT_RE = re.compile(
    r"^authoredEffectGraphDepthParallaxCount: (?P<count>\d+)$",
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
AUTHORED_EFFECT_GRAPH_SHINE_COUNT_RE = re.compile(
    r"^authoredEffectGraphShineCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_SHINE_ISOLATED_COUNT_RE = re.compile(
    r"^authoredEffectGraphShineIsolatedCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_SHINE_OMITTED_EFFECTS_RE = re.compile(
    r"^authoredEffectGraphShineOmittedEffects: ?(?P<effects>.*)$",
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
AUTHORED_EFFECT_GRAPH_COLOR_GRADING_COUNT_RE = re.compile(
    r"^authoredEffectGraphColorGradingCount: (?P<count>\d+)$",
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
AUTHORED_EFFECT_GRAPH_CHAIN_COUNT_RE = re.compile(
    r"^authoredEffectGraphChainCount: (?P<count>\d+)$",
    re.MULTILINE,
)
AUTHORED_EFFECT_GRAPH_STAGE_COUNT_RE = re.compile(
    r"^authoredEffectGraphStageCount: (?P<count>\d+)$",
    re.MULTILINE,
)
NAMED_TARGET_CAPTURE_EXECUTION_RE = re.compile(
    r"phase=named-target-capture layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
NAMED_TARGET_BINDING_EXECUTION_RE = re.compile(
    r"phase=named-target-binding layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
IMAGE_BLEND_PLANNED_RE = re.compile(
    r"^imageBlendPlannedCount: (?P<count>\d+)$", re.MULTILINE
)
IMAGE_BLEND_EXECUTION_RE = re.compile(
    r"phase=image-blend layer=(?P<id>\d+) status=(?P<status>succeeded|failed)"
)
CAMERA_RE = re.compile(
    r"^camera: projection=(?P<projection>\S+) parallax=(?P<parallax>true|false) "
    rf"amount=(?P<amount>{FLOAT_PATTERN}) (?:delay=(?P<delay>{FLOAT_PATTERN}) )?"
    rf"mouseInfluence=(?P<influence>{FLOAT_PATTERN})$",
    re.MULTILINE,
)
SAMPLE_ROOT_DERIVED_FILES = (
    ".mywallpaperx-scene-interpretation.json",
    ".mywallpaperx-scene-preview-log.txt",
)
PERFORMANCE_INT_FIELDS = {
    "callbacks": "driver_callbacks",
    "submitted": "submitted_frames",
    "completed": "completed_frames",
    "failed": "failed_frames",
    "callbackOver16": "callback_over_16_67_ms",
    "callbackOver33": "callback_over_33_33_ms",
    "discontinuities": "discontinuity_count",
    "drawableMissed": "drawable_missed",
    "cpuOver16": "cpu_over_16_67_ms",
    "cpuOver33": "cpu_over_33_33_ms",
    "gpuSamples": "gpu_samples",
    "gpuOver16": "gpu_over_16_67_ms",
    "gpuOver33": "gpu_over_33_33_ms",
}
PERFORMANCE_FLOAT_FIELDS = {
    "elapsed": "measurement_elapsed_seconds",
    "submittedFPS": "submitted_fps_total",
    "completedFPS": "completed_fps_total",
    "callbackP50MS": "callback_p50_ms",
    "callbackP95MS": "callback_p95_ms",
    "callbackMaxMS": "callback_max_ms",
    "droppedMS": "dropped_frame_time_ms",
    "maxRawFrameMS": "maximum_raw_frame_time_ms",
    "drawableWaitP95MS": "drawable_wait_p95_ms",
    "drawableWaitMaxMS": "drawable_wait_max_ms",
    "preEncodeP95MS": "pre_encode_p95_ms",
    "preEncodeMaxMS": "pre_encode_max_ms",
    "mainFrameP95MS": "main_frame_p95_ms",
    "mainFrameMaxMS": "main_frame_max_ms",
    "cpuP50MS": "cpu_frame_p50_ms",
    "cpuP95MS": "cpu_frame_p95_ms",
    "cpuMaxMS": "cpu_frame_max_ms",
    "gpuP50MS": "gpu_frame_p50_ms",
    "gpuP95MS": "gpu_frame_p95_ms",
    "gpuMaxMS": "gpu_frame_max_ms",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def performance_metrics(log_text: str, surface_count: int | None) -> dict[str, Any]:
    matches = list(PERFORMANCE_LINE_RE.finditer(log_text))
    if len(matches) != 1:
        return {
            "available": False,
            "error": f"expected one performance event, found {len(matches)}",
        }

    raw_fields: dict[str, str] = {}
    for token in matches[0].group("fields").split():
        if token.count("=") != 1:
            return {"available": False, "error": f"invalid performance token: {token}"}
        key, value = token.split("=", 1)
        if not key or not value:
            return {"available": False, "error": f"invalid performance token: {token}"}
        if key in raw_fields:
            return {"available": False, "error": f"duplicate performance field: {key}"}
        raw_fields[key] = value

    required = set(PERFORMANCE_INT_FIELDS) | set(PERFORMANCE_FLOAT_FIELDS)
    missing = sorted(required - raw_fields.keys())
    if missing:
        return {
            "available": False,
            "error": "missing performance fields: " + ", ".join(missing),
        }

    metrics: dict[str, Any] = {"available": True, "target_fps": 60.0}
    try:
        for source, destination in PERFORMANCE_INT_FIELDS.items():
            value = int(raw_fields[source])
            if value < 0:
                raise ValueError(f"negative performance field: {source}")
            metrics[destination] = value
        for source, destination in PERFORMANCE_FLOAT_FIELDS.items():
            value = float(raw_fields[source])
            if not math.isfinite(value) or value < 0:
                raise ValueError(f"invalid performance field: {source}")
            metrics[destination] = value
    except ValueError as error:
        return {"available": False, "error": str(error)}

    elapsed = metrics["measurement_elapsed_seconds"]
    if elapsed <= 0:
        return {"available": False, "error": "performance elapsed must be positive"}
    if surface_count is None or surface_count <= 0:
        return {"available": False, "error": "performance surface count must be positive"}

    metrics["driver_fps"] = metrics["driver_callbacks"] / elapsed
    metrics["submitted_fps_per_surface"] = metrics["submitted_fps_total"] / surface_count
    metrics["completed_fps_per_surface"] = metrics["completed_fps_total"] / surface_count
    return metrics


def performance_failures(metrics: dict[str, Any]) -> list[str]:
    if metrics.get("available") is True:
        return []
    return [f"performance evidence unavailable: {metrics.get('error', 'unknown error')}"]


def summarize_performance(results: list[dict[str, Any]]) -> dict[str, Any]:
    available = [
        (str(result["id"]), result.get("runtime", {}).get("performance"))
        for result in results
        if result.get("runtime", {}).get("performance", {}).get("available") is True
    ]
    unavailable = len(results) - len(available)
    if not available:
        return {
            "available_count": 0,
            "unavailable_count": unavailable,
            "lowest_driver_fps": None,
            "slowest_startup_ready_ms": None,
        }
    lowest_id, lowest = min(available, key=lambda item: item[1]["driver_fps"])
    startup_values = [
        (str(result["id"]), result.get("runtime", {}).get("startup_ready_ms"))
        for result in results
        if isinstance(result.get("runtime", {}).get("startup_ready_ms"), (int, float))
    ]
    slowest = max(startup_values, key=lambda item: item[1]) if startup_values else None
    return {
        "available_count": len(available),
        "unavailable_count": unavailable,
        "lowest_driver_fps": {"id": lowest_id, "fps": lowest["driver_fps"]},
        "slowest_startup_ready_ms": (
            {"id": slowest[0], "milliseconds": slowest[1]} if slowest else None
        ),
    }


def load_matrix(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1 or not isinstance(payload.get("samples"), list):
        raise ValueError(f"invalid Scene matrix: {path}")
    for sample in payload["samples"]:
        if not isinstance(sample, dict):
            raise ValueError(f"invalid Scene matrix sample: {path}")
        hover_pointer_normalized(sample)
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


def hover_pointer_normalized(
    sample: dict[str, Any],
) -> tuple[float, float] | None:
    raw = sample.get("hover_pointer_normalized")
    if raw is None:
        return None
    if (
        not isinstance(raw, list)
        or len(raw) != 2
        or any(type(value) not in (int, float) for value in raw)
    ):
        raise ValueError("hover_pointer_normalized must contain two numbers")
    x, y = (float(raw[0]), float(raw[1]))
    if not math.isfinite(x) or not math.isfinite(y) or not (-1 <= x <= 1 and -1 <= y <= 1):
        raise ValueError("hover_pointer_normalized must stay within [-1, 1]")
    return (x, y)


def scene_package_path(source: Path) -> Path | None:
    project_path = source / "project.json"
    if not project_path.is_file():
        return None
    try:
        project = json.loads(project_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        project = {}
    raw_entry = project.get("file")
    entry = raw_entry.strip().replace("\\", "/") if isinstance(raw_entry, str) else ""
    entry_name = Path(entry).name if entry else "scene.json"
    derived_name = str(Path(entry_name).with_suffix(".pkg"))
    package_names = (
        [derived_name]
        if derived_name == "scene.pkg"
        else [derived_name, "scene.pkg"]
    )
    return next((source / name for name in package_names if (source / name).is_file()), None)


def copy_sample(source: Path, destination: Path) -> None:
    if not (source / "project.json").is_file() or scene_package_path(source) is None:
        raise FileNotFoundError(f"Scene sample is incomplete: {source}")
    shutil.copytree(source, destination)


def pass_metadata_metrics(passes: list[Any]) -> tuple[int, int, int]:
    slot_count = 0
    slot_holes = 0
    combo_count = 0
    for item in passes:
        if not isinstance(item, dict):
            raise ValueError("Scene runtime evidence pass is not an object")
        slots = item.get("textureSlots")
        combos = item.get("combos")
        if not isinstance(slots, list) or any(slot is not None and not isinstance(slot, str) for slot in slots):
            raise ValueError("Scene runtime evidence textureSlots has an invalid shape")
        if not isinstance(combos, dict) or any(type(value) is not int for value in combos.values()):
            raise ValueError("Scene runtime evidence combos has an invalid shape")
        slot_count += len(slots)
        slot_holes += sum(slot is None for slot in slots)
        combo_count += len(combos)
    return slot_count, slot_holes, combo_count


def shader_contract_metrics(contracts: Any) -> dict[str, Any]:
    if not isinstance(contracts, list):
        raise ValueError("Scene runtime evidence shaderContracts has an invalid shape")

    authored_count = 0
    builtin_count = 0
    stage_count = 0
    diagnostic_count = 0
    aggregate_entries: list[list[str]] = []
    identities: set[str] = set()
    for contract in contracts:
        if not isinstance(contract, dict):
            raise ValueError("Scene runtime evidence shader contract is not an object")
        identity = contract.get("identity")
        source_kind = contract.get("sourceKind")
        stages = contract.get("stages")
        diagnostics = contract.get("diagnostics")
        canonical_sha256 = contract.get("canonicalSHA256")
        if not isinstance(identity, str) or not identity:
            raise ValueError("Scene runtime evidence shader contract identity has an invalid shape")
        if identity in identities:
            raise ValueError("Scene runtime evidence shader contract identity is duplicated")
        identities.add(identity)
        if source_kind not in {"authoredSource", "hostBuiltin"}:
            raise ValueError("Scene runtime evidence shader contract sourceKind has an invalid shape")
        if not isinstance(stages, list):
            raise ValueError("Scene runtime evidence shader contract stages has an invalid shape")
        if not isinstance(diagnostics, list):
            raise ValueError("Scene runtime evidence shader contract diagnostics has an invalid shape")
        if not isinstance(canonical_sha256, str) or re.fullmatch(
            r"[0-9a-f]{64}", canonical_sha256
        ) is None:
            raise ValueError(
                "Scene runtime evidence shader contract canonicalSHA256 has an invalid shape"
            )

        stage_kinds: set[str] = set()
        for stage in stages:
            if not isinstance(stage, dict):
                raise ValueError("Scene runtime evidence shader contract stage is not an object")
            kind = stage.get("kind")
            relative_path = stage.get("relativePath")
            source = stage.get("source")
            raw_sha256 = stage.get("rawSHA256")
            if kind not in {"vertex", "fragment"} or kind in stage_kinds:
                raise ValueError("Scene runtime evidence shader contract stage kind is invalid")
            stage_kinds.add(kind)
            if relative_path != f"shaders/{identity}.{'vert' if kind == 'vertex' else 'frag'}":
                raise ValueError("Scene runtime evidence shader contract stage path is invalid")
            if not isinstance(source, str) or not isinstance(raw_sha256, str):
                raise ValueError("Scene runtime evidence shader contract stage source is invalid")
            if raw_sha256 != hashlib.sha256(source.encode("utf-8")).hexdigest():
                raise ValueError("Scene runtime evidence shader contract stage rawSHA256 mismatch")

            for field in ("includes", "annotations", "declarations"):
                if not isinstance(stage.get(field), list):
                    raise ValueError(
                        f"Scene runtime evidence shader contract stage {field} is invalid"
                    )
            for include in stage["includes"]:
                if not isinstance(include, dict) or not isinstance(include.get("relativePath"), str):
                    raise ValueError("Scene runtime evidence shader contract include is invalid")
                if not isinstance(include.get("raw"), str) or type(include.get("line")) is not int:
                    raise ValueError("Scene runtime evidence shader contract include is invalid")
            for annotation in stage["annotations"]:
                marker = annotation.get("marker") if isinstance(annotation, dict) else None
                if not isinstance(annotation, dict) or "value" not in annotation:
                    raise ValueError("Scene runtime evidence shader contract annotation is invalid")
                if marker is not None and not isinstance(marker, str):
                    raise ValueError("Scene runtime evidence shader contract annotation is invalid")
                if not isinstance(annotation.get("raw"), str) or type(annotation.get("line")) is not int:
                    raise ValueError("Scene runtime evidence shader contract annotation is invalid")
            for declaration in stage["declarations"]:
                if not isinstance(declaration, dict) or declaration.get("kind") not in {
                    "uniform", "attribute", "varying"
                }:
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")
                if not all(isinstance(declaration.get(field), str) for field in ("type", "name", "raw")):
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")
                if type(declaration.get("line")) is not int:
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")
                if declaration.get("arraySuffix") is not None and not isinstance(
                    declaration.get("arraySuffix"), str
                ):
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")
                if declaration.get("arraySize") is not None and type(
                    declaration.get("arraySize")
                ) is not int:
                    raise ValueError("Scene runtime evidence shader contract declaration is invalid")

        diagnostic_codes = {
            "duplicateIdentity", "invalidReference", "pathEscape", "symlinkEscape",
            "missingVertexStage", "missingFragmentStage", "unreadableSource", "invalidUTF8",
            "malformedAnnotation",
        }
        for diagnostic in diagnostics:
            if not isinstance(diagnostic, dict) or diagnostic.get("code") not in diagnostic_codes:
                raise ValueError("Scene runtime evidence shader contract diagnostic is invalid")
            if not isinstance(diagnostic.get("message"), str):
                raise ValueError("Scene runtime evidence shader contract diagnostic is invalid")
            if diagnostic.get("relativePath") is not None and not isinstance(
                diagnostic.get("relativePath"), str
            ):
                raise ValueError("Scene runtime evidence shader contract diagnostic is invalid")
            if diagnostic.get("line") is not None and type(diagnostic.get("line")) is not int:
                raise ValueError("Scene runtime evidence shader contract diagnostic is invalid")
        if source_kind == "hostBuiltin" and (stages or diagnostics):
            raise ValueError("Scene runtime evidence host builtin shader contract is invalid")

        authored_count += source_kind == "authoredSource"
        builtin_count += source_kind == "hostBuiltin"
        stage_count += len(stages)
        diagnostic_count += len(diagnostics)
        aggregate_entries.append([identity, canonical_sha256])

    # UTF-8 JSON over sorted [identity, canonicalSHA256] pairs is the stable wire encoding.
    aggregate_sha256 = hashlib.sha256(json.dumps(
        sorted(aggregate_entries),
        ensure_ascii=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    return {
        "shader_contract_count": len(contracts),
        "shader_contract_authored_count": authored_count,
        "shader_contract_builtin_count": builtin_count,
        "shader_contract_stage_count": stage_count,
        "shader_contract_diagnostic_count": diagnostic_count,
        "shader_contract_aggregate_sha256": aggregate_sha256,
    }


def layer_graph_metrics(layers: list[dict[str, Any]]) -> dict[str, Any]:
    layers_by_id = {layer["id"]: layer for layer in layers if type(layer.get("id")) is int}

    def is_effectively_visible(layer: dict[str, Any]) -> bool:
        current: dict[str, Any] | None = layer
        visited: set[int] = set()
        while current is not None:
            layer_id = current.get("id")
            if current.get("visible") is False or layer_id in visited:
                return False
            if type(layer_id) is int:
                visited.add(layer_id)
            parent_id = current.get("parentID")
            current = layers_by_id.get(parent_id) if type(parent_id) is int else None
        return True

    def hierarchy_depth(layer: dict[str, Any]) -> int:
        depth = 0
        current = layer
        visited: set[int] = set()
        while type(current.get("parentID")) is int:
            layer_id = current.get("id")
            if layer_id in visited:
                break
            if type(layer_id) is int:
                visited.add(layer_id)
            parent = layers_by_id.get(current["parentID"])
            if parent is None:
                break
            depth += 1
            current = parent
        return depth

    effective_visible_ids = [
        layer["id"]
        for layer in layers
        if type(layer.get("id")) is int and is_effectively_visible(layer)
    ]
    parent_ids = {
        layer["parentID"]
        for layer in layers
        if type(layer.get("parentID")) is int
    }
    return {
        "root_layer_count": sum(layer.get("parentID") is None for layer in layers),
        "child_edge_count": sum(type(layer.get("parentID")) is int for layer in layers),
        "parent_layer_count": len(parent_ids),
        "max_hierarchy_depth": max((hierarchy_depth(layer) for layer in layers), default=0),
        "effective_visible_layer_count": len(effective_visible_ids),
        "effective_visible_layer_ids": effective_visible_ids,
    }


def runtime_evidence_metrics(path: Path) -> dict[str, Any]:
    try:
        evidence = json.loads(path.read_text(encoding="utf-8"))
        payload = evidence["runtimeInput"]
        shader_contracts = shader_contract_metrics(payload["shaderContracts"])
        descriptor = payload["renderDescriptor"]
        layers = descriptor.get("layers", [])
        effect_passes = [
            item
            for layer in descriptor.get("layers", [])
            for effect in layer.get("effects", [])
            for item in effect.get("passes", [])
        ]
        material_passes = descriptor.get("materialPasses", [])
        effect_definitions = descriptor.get("effectDefinitions", [])
        definition_passes = [
            item
            for definition in effect_definitions
            for item in definition.get("passes", [])
        ]
        definition_framebuffers = [
            item
            for definition in effect_definitions
            for item in definition.get("framebuffers", [])
        ]
        definition_diagnostics = descriptor.get("effectDefinitionDiagnostics", [])
        effect_graphs = payload.get("authoredEffectRenderPlans", [])
        effect_graph_nodes = [
            node
            for graph_plan in effect_graphs
            for node in graph_plan.get("nodes", [])
        ]
        effect_graph_blockers = [
            blocker
            for graph_plan in effect_graphs
            for blocker in graph_plan.get("blockers", [])
        ]
        effect_graph_blocker_reasons: dict[str, int] = {}
        for blocker in effect_graph_blockers:
            reason = blocker.get("reason")
            if isinstance(reason, str):
                effect_graph_blocker_reasons[reason] = (
                    effect_graph_blocker_reasons.get(reason, 0) + 1
                )
        effect_graph_sha256 = hashlib.sha256(json.dumps(
            effect_graphs,
            ensure_ascii=True,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")).hexdigest()
        graph = layer_graph_metrics(layers)
        solid_layers = [layer for layer in layers if layer.get("contentKind") == "solid"]
        utility_layers = [
            layer
            for layer in layers
            if layer.get("contentKind") in {"composition", "project", "fullscreen"}
        ]
        dependency_edges = [
            (layer.get("id"), dependency_id)
            for layer in layers
            for dependency_id in layer.get("dependencyLayerIDs", [])
            if type(layer.get("id")) is int and type(dependency_id) is int
        ]
        solid_layer_ids = [
            layer["id"] for layer in solid_layers if type(layer.get("id")) is int
        ]
        effective_visible_ids = set(graph["effective_visible_layer_ids"])
        stock_opacity_single_effect_candidate_layer_ids = sorted({
            graph_plan["layerID"]
            for graph_plan in effect_graphs
            if type(graph_plan.get("layerID")) is int
            and graph_plan["layerID"] in effective_visible_ids
            and len(graph_plan.get("effects", [])) == 1
            and str(graph_plan["effects"][0].get("definitionPath", ""))
                .replace("\\", "/").lower() == "effects/opacity/effect.json"
        })
        effective_visible_solid_layer_ids = [
            layer_id for layer_id in solid_layer_ids if layer_id in effective_visible_ids
        ]
        authored_solid_color_layer_ids = [
            layer["id"]
            for layer in solid_layers
            if type(layer.get("id")) is int and isinstance(layer.get("colorRGB"), list)
        ]
        parallax_layers = [
            layer
            for layer in layers
            if isinstance(layer.get("parallaxDepthXY"), list)
            and any(abs(float(value)) > 1e-8 for value in layer["parallaxDepthXY"])
        ]
        effect_slot_count, effect_slot_holes, effect_combo_count = pass_metadata_metrics(effect_passes)
        material_slot_count, material_slot_holes, material_combo_count = pass_metadata_metrics(material_passes)
        return {
            "schema_version": int(evidence["schemaVersion"]),
            **shader_contracts,
            "effect_texture_slot_count": effect_slot_count,
            "effect_texture_slot_hole_count": effect_slot_holes,
            "effect_combo_entry_count": effect_combo_count,
            "material_texture_slot_count": material_slot_count,
            "material_texture_slot_hole_count": material_slot_holes,
            "material_combo_entry_count": material_combo_count,
            "effect_definition_count": len(effect_definitions),
            "effect_definition_pass_count": len(definition_passes),
            "effect_definition_material_pass_count": sum(
                isinstance(item.get("materialPath"), str) for item in definition_passes
            ),
            "effect_definition_fbo_count": len(definition_framebuffers),
            "effect_definition_copy_command_count": sum(
                item.get("command") == "copy" for item in definition_passes
            ),
            "effect_definition_swap_command_count": sum(
                item.get("command") == "swap" for item in definition_passes
            ),
            "effect_definition_diagnostic_count": len(definition_diagnostics),
            "effect_graph_layer_count": len(effect_graphs),
            "effect_graph_effect_count": sum(
                len(graph_plan.get("effects", [])) for graph_plan in effect_graphs
            ),
            "effect_graph_node_count": len(effect_graph_nodes),
            "effect_graph_material_node_count": sum(
                node.get("kind") == "material" for node in effect_graph_nodes
            ),
            "effect_graph_copy_node_count": sum(
                node.get("kind") == "copy" for node in effect_graph_nodes
            ),
            "effect_graph_swap_node_count": sum(
                node.get("kind") == "swap" for node in effect_graph_nodes
            ),
            "effect_graph_render_target_count": sum(
                len(graph_plan.get("renderTargets", [])) for graph_plan in effect_graphs
            ),
            "effect_graph_blocker_count": len(effect_graph_blockers),
            "effect_graph_blocker_reasons": effect_graph_blocker_reasons,
            "effect_graph_unblocked_layer_count": sum(
                not graph_plan.get("blockers", []) for graph_plan in effect_graphs
            ),
            "effect_graph_sha256": effect_graph_sha256,
            "stock_opacity_single_effect_candidate_layer_ids":
                stock_opacity_single_effect_candidate_layer_ids,
            "visible_layer_count": sum(layer.get("visible") is not False for layer in layers),
            "visible_layer_ids": [layer.get("id") for layer in layers if layer.get("visible") is not False],
            **graph,
            "solid_layer_count": len(solid_layers),
            "solid_layer_ids": solid_layer_ids,
            "authored_solid_color_layer_count": len(authored_solid_color_layer_ids),
            "authored_solid_color_layer_ids": authored_solid_color_layer_ids,
            "effective_visible_solid_layer_count": len(effective_visible_solid_layer_ids),
            "effective_visible_solid_layer_ids": effective_visible_solid_layer_ids,
            "composition_layer_count": sum(
                layer.get("contentKind") == "composition" for layer in utility_layers
            ),
            "project_layer_count": sum(
                layer.get("contentKind") == "project" for layer in utility_layers
            ),
            "fullscreen_layer_count": sum(
                layer.get("contentKind") == "fullscreen" for layer in utility_layers
            ),
            "utility_layer_ids": [layer["id"] for layer in utility_layers],
            "dependency_edge_count": len(dependency_edges),
            "dependency_consumer_layer_ids": sorted({edge[0] for edge in dependency_edges}),
            "dependency_source_layer_ids": sorted({edge[1] for edge in dependency_edges}),
            "authored_parallax_layer_count": len(parallax_layers),
            "authored_parallax_layer_ids": [layer.get("id") for layer in parallax_layers],
            "parallax_propagation_block_count": sum(
                layer.get("disablesParallaxPropagation") is True for layer in layers
            ),
            "text_values": [layer.get("text") for layer in layers if isinstance(layer.get("text"), str)],
            "effect_files": sorted({
                effect.get("file")
                for layer in layers
                for effect in layer.get("effects", [])
                if isinstance(effect.get("file"), str)
            }),
            "built_in_reference_count": int(descriptor.get("builtInReferenceCount", 0)),
            "missing_resource_count": len(descriptor.get("missingResources", [])),
            "error": None,
        }
    except (AttributeError, KeyError, TypeError, ValueError, json.JSONDecodeError, OSError) as error:
        return {
            "schema_version": None,
            "shader_contract_count": 0,
            "shader_contract_authored_count": 0,
            "shader_contract_builtin_count": 0,
            "shader_contract_stage_count": 0,
            "shader_contract_diagnostic_count": 0,
            "shader_contract_aggregate_sha256": None,
            "effect_texture_slot_count": 0,
            "effect_texture_slot_hole_count": 0,
            "effect_combo_entry_count": 0,
            "material_texture_slot_count": 0,
            "material_texture_slot_hole_count": 0,
            "material_combo_entry_count": 0,
            "effect_definition_count": 0,
            "effect_definition_pass_count": 0,
            "effect_definition_material_pass_count": 0,
            "effect_definition_fbo_count": 0,
            "effect_definition_copy_command_count": 0,
            "effect_definition_swap_command_count": 0,
            "effect_definition_diagnostic_count": 0,
            "effect_graph_layer_count": 0,
            "effect_graph_effect_count": 0,
            "effect_graph_node_count": 0,
            "effect_graph_material_node_count": 0,
            "effect_graph_copy_node_count": 0,
            "effect_graph_swap_node_count": 0,
            "effect_graph_render_target_count": 0,
            "effect_graph_blocker_count": 0,
            "effect_graph_blocker_reasons": {},
            "effect_graph_unblocked_layer_count": 0,
            "effect_graph_sha256": None,
            "stock_opacity_single_effect_candidate_layer_ids": [],
            "visible_layer_count": 0,
            "visible_layer_ids": [],
            "root_layer_count": 0,
            "child_edge_count": 0,
            "parent_layer_count": 0,
            "max_hierarchy_depth": 0,
            "effective_visible_layer_count": 0,
            "effective_visible_layer_ids": [],
            "solid_layer_count": 0,
            "solid_layer_ids": [],
            "authored_solid_color_layer_count": 0,
            "authored_solid_color_layer_ids": [],
            "effective_visible_solid_layer_count": 0,
            "effective_visible_solid_layer_ids": [],
            "composition_layer_count": 0,
            "project_layer_count": 0,
            "fullscreen_layer_count": 0,
            "utility_layer_ids": [],
            "dependency_edge_count": 0,
            "dependency_consumer_layer_ids": [],
            "dependency_source_layer_ids": [],
            "authored_parallax_layer_count": 0,
            "authored_parallax_layer_ids": [],
            "parallax_propagation_block_count": 0,
            "text_values": [],
            "effect_files": [],
            "built_in_reference_count": 0,
            "missing_resource_count": 0,
            "error": str(error),
        }


def particle_runtime_metrics(preview_text: str) -> dict[str, Any]:
    loaded_match = PARTICLE_LOADED_RE.search(preview_text)
    refract_loaded_match = PARTICLE_REFRACT_LOADED_RE.search(preview_text)
    initial_live_match = PARTICLE_INITIAL_LIVE_RE.search(preview_text)
    authored_match = PARTICLE_AUTHORED_RE.search(preview_text)
    visible_match = PARTICLE_VISIBLE_RE.search(preview_text)
    skipped_hidden_match = PARTICLE_SKIPPED_HIDDEN_RE.search(preview_text)
    skipped_transparent_match = PARTICLE_SKIPPED_TRANSPARENT_RE.search(preview_text)
    loaded = int(loaded_match.group("loaded")) if loaded_match else 0
    candidates = int(loaded_match.group("total")) if loaded_match else 0
    return {
        "has_load_evidence": loaded_match is not None,
        "has_initial_live_evidence": initial_live_match is not None,
        "has_visibility_evidence": all(
            match is not None
            for match in (authored_match, visible_match, skipped_hidden_match)
        ),
        "loaded": loaded,
        "candidates": candidates,
        "loaded_ratio": loaded / candidates if candidates else 0.0,
        "has_refract_evidence": refract_loaded_match is not None,
        "refract_loaded": int(refract_loaded_match.group("count"))
        if refract_loaded_match else 0,
        "initial_live": int(initial_live_match.group("live")) if initial_live_match else 0,
        "authored": int(authored_match.group("count")) if authored_match else 0,
        "visible": int(visible_match.group("count")) if visible_match else 0,
        "skipped_hidden": int(skipped_hidden_match.group("count")) if skipped_hidden_match else 0,
        "has_transparent_evidence": skipped_transparent_match is not None,
        "skipped_transparent": int(skipped_transparent_match.group("count"))
        if skipped_transparent_match else 0,
        "loaded_layer_ids": [int(match.group("id")) for match in PARTICLE_LAYER_OK_RE.finditer(preview_text)],
    }


def solid_runtime_metrics(preview_text: str) -> dict[str, Any]:
    count_match = SOLID_LAYER_COUNT_RE.search(preview_text)
    loaded_layer_ids = [
        int(match.group("id")) for match in SOLID_LAYER_OK_RE.finditer(preview_text)
    ]
    candidates = int(count_match.group("count")) if count_match else 0
    return {
        "has_count_evidence": count_match is not None,
        "loaded": len(loaded_layer_ids),
        "candidates": candidates,
        "loaded_ratio": len(loaded_layer_ids) / candidates if candidates else 0.0,
        "loaded_layer_ids": loaded_layer_ids,
    }


def puppet_animation_runtime_metrics(preview_text: str) -> dict[str, Any]:
    entries = [
        {
            "layer_id": int(match.group("id")),
            "mode": match.group("mode"),
            "animation_ids": [
                int(animation_id)
                for animation_id in match.group("ids").split(",")
            ],
            "clip_count": int(match.group("clips")),
        }
        for match in PUPPET_ANIMATION_OK_RE.finditer(preview_text)
    ]
    entries.sort(key=lambda entry: entry["layer_id"])
    return {
        "layer_ids": [entry["layer_id"] for entry in entries],
        "disjoint_additive_layer_ids": [
            entry["layer_id"]
            for entry in entries
            if entry["mode"] == "disjoint-additive"
        ],
        "clip_count": sum(entry["clip_count"] for entry in entries),
        "entries": entries,
    }


def puppet_animation_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    failures: list[str] = []
    expected_layer_ids = sample.get("expected_puppet_animation_layer_ids")
    if expected_layer_ids is not None:
        if metrics["layer_ids"] != sorted(int(value) for value in expected_layer_ids):
            failures.append("puppet animation layer IDs mismatch")
    expected_additive_layer_ids = sample.get(
        "expected_puppet_disjoint_additive_layer_ids"
    )
    if expected_additive_layer_ids is not None:
        if metrics["disjoint_additive_layer_ids"] != sorted(
            int(value) for value in expected_additive_layer_ids
        ):
            failures.append("puppet disjoint-additive layer IDs mismatch")
    expected_clip_count = sample.get("expected_puppet_animation_clip_count")
    if expected_clip_count is not None:
        if metrics["clip_count"] != int(expected_clip_count):
            failures.append("puppet animation clip count mismatch")
    return failures


def text_script_runtime_metrics(preview_text: str) -> dict[str, Any]:
    binding_match = TEXT_SCRIPT_BINDING_COUNT_RE.search(preview_text)
    diagnostic_match = TEXT_SCRIPT_DIAGNOSTIC_COUNT_RE.search(preview_text)
    bindings = [
        {
            "layer_id": int(match.group("id")),
            "profile": match.group("profile"),
            "fixture_value": match.group("value"),
        }
        for match in TEXT_SCRIPT_BINDING_RE.finditer(preview_text)
    ]
    return {
        "binding_count": int(binding_match.group("count")) if binding_match else None,
        "diagnostic_count": (
            int(diagnostic_match.group("count")) if diagnostic_match else None
        ),
        "binding_layer_ids": sorted(binding["layer_id"] for binding in bindings),
        "bindings": bindings,
    }


def time_of_day_effect_script_runtime_metrics(preview_text: str) -> dict[str, Any]:
    count_match = TIME_OF_DAY_EFFECT_SCRIPT_BINDING_COUNT_RE.search(preview_text)
    wall_date_match = TIME_OF_DAY_EFFECT_SCRIPT_DEBUG_WALL_DATE_RE.search(preview_text)
    bindings = [
        {
            "layer_id": int(match.group("layer")),
            "effect_index": int(match.group("effect")),
            "pass_index": int(match.group("pass")),
            "constant": match.group("constant"),
        }
        for match in TIME_OF_DAY_EFFECT_SCRIPT_BINDING_RE.finditer(preview_text)
    ]
    return {
        "binding_count": int(count_match.group("count")) if count_match else None,
        "debug_wall_date": wall_date_match.group("value") if wall_date_match else None,
        "bindings": bindings,
    }


def media_thumbnail_runtime_metrics(preview_text: str) -> dict[str, Any]:
    count_match = MEDIA_THUMBNAIL_CURRENT_BINDING_COUNT_RE.search(preview_text)
    layer_ids_match = MEDIA_THUMBNAIL_CURRENT_BINDING_LAYER_IDS_RE.search(preview_text)
    transition_count_match = MEDIA_THUMBNAIL_PREVIOUS_TRANSITION_COUNT_RE.search(
        preview_text
    )
    transition_layer_ids_match = (
        MEDIA_THUMBNAIL_PREVIOUS_TRANSITION_LAYER_IDS_RE.search(preview_text)
    )
    layer_ids = []
    if layer_ids_match:
        layer_ids = [
            int(value)
            for value in layer_ids_match.group("ids").split(",")
            if value
        ]
    return {
        "current_binding_count": (
            int(count_match.group("count")) if count_match else None
        ),
        "current_binding_layer_ids": layer_ids,
        "previous_transition_count": (
            int(transition_count_match.group("count"))
            if transition_count_match else None
        ),
        "previous_transition_layer_ids": [
            int(value)
            for value in transition_layer_ids_match.group("ids").split(",")
            if value
        ] if transition_layer_ids_match else [],
    }


def media_thumbnail_transition_execution_metrics(log_text: str) -> dict[str, Any]:
    phases: dict[str, set[int]] = {
        "started": set(),
        "midpoint": set(),
        "completed": set(),
    }
    generations: set[int] = set()
    for match in MEDIA_THUMBNAIL_TRANSITION_EXECUTION_RE.finditer(log_text):
        phases[match.group("phase")].add(int(match.group("id")))
        generations.add(int(match.group("generation")))
    return {
        "generation_ids": sorted(generations),
        "started_layer_ids": sorted(phases["started"]),
        "midpoint_layer_ids": sorted(phases["midpoint"]),
        "completed_layer_ids": sorted(phases["completed"]),
    }


def media_thumbnail_store_metrics(log_text: str) -> dict[str, Any]:
    return {
        "pending_last_ready": [
            {
                "requested_generation": int(match.group("requested")),
                "ready_generation": int(match.group("ready")),
                "has_current": match.group("current") == "true",
            }
            for match in MEDIA_THUMBNAIL_PENDING_RE.finditer(log_text)
        ],
        "ready_states": [
            {
                "generation": int(match.group("generation")),
                "has_current": match.group("current") == "true",
                "has_previous": match.group("previous") == "true",
            }
            for match in MEDIA_THUMBNAIL_READY_RE.finditer(log_text)
        ],
        "clear_count": len(MEDIA_THUMBNAIL_CLEAR_RE.findall(log_text)),
    }


def scene_script_audio_bars_runtime_metrics(preview_text: str) -> dict[str, Any]:
    plan_count_match = SCENE_SCRIPT_AUDIO_BARS_PLAN_COUNT_RE.search(preview_text)
    diagnostic_count_match = (
        SCENE_SCRIPT_AUDIO_BARS_DIAGNOSTIC_COUNT_RE.search(preview_text)
    )
    has_audio_consumer_match = (
        SCENE_SCRIPT_AUDIO_BARS_HAS_AUDIO_CONSUMER_RE.search(preview_text)
    )
    plans = [
        {
            "layer_id": int(match.group("id")),
            "host": match.group("host"),
            "source_sha256": match.group("source_sha256").lower(),
            "bar_count": int(match.group("bar_count")),
            "audio_resolution": int(match.group("audio_resolution")),
            "channel": match.group("channel"),
            "model_path": match.group("model_path"),
            "material_path": match.group("material_path"),
            "texture_path": match.group("texture_path"),
            "width_multiplier": float(match.group("width_multiplier")),
            "height_multiplier": float(match.group("height_multiplier")),
            "depth_multiplier": float(match.group("depth_multiplier")),
            "x_step": float(match.group("x_step")),
            "y_step": float(match.group("y_step")),
            "angle_degrees": float(match.group("angle_degrees")),
            "alignment": match.group("alignment"),
            "first_step": match.group("first_step"),
        }
        for match in SCENE_SCRIPT_AUDIO_BARS_PLAN_RE.finditer(preview_text)
    ]
    return {
        "plan_count": (
            int(plan_count_match.group("count")) if plan_count_match else None
        ),
        "diagnostic_count": (
            int(diagnostic_count_match.group("count"))
            if diagnostic_count_match
            else None
        ),
        "has_audio_consumer": (
            has_audio_consumer_match.group("value").lower() == "true"
            if has_audio_consumer_match
            else None
        ),
        "plan_layer_ids": sorted(plan["layer_id"] for plan in plans),
        "total_bar_count": sum(plan["bar_count"] for plan in plans),
        "plans": plans,
    }


SCENE_SCRIPT_AUDIO_BARS_PLAN_FIELDS = (
    "layer_id",
    "host",
    "source_sha256",
    "bar_count",
    "audio_resolution",
    "channel",
    "model_path",
    "material_path",
    "texture_path",
    "width_multiplier",
    "height_multiplier",
    "depth_multiplier",
    "x_step",
    "y_step",
    "angle_degrees",
    "alignment",
    "first_step",
)
SCENE_SCRIPT_AUDIO_BARS_PLAN_INTEGER_FIELDS = {
    "layer_id",
    "bar_count",
    "audio_resolution",
}
SCENE_SCRIPT_AUDIO_BARS_PLAN_FLOAT_FIELDS = {
    "width_multiplier",
    "height_multiplier",
    "depth_multiplier",
    "x_step",
    "y_step",
    "angle_degrees",
}


def scene_script_audio_bars_plan_matches(
    actual: dict[str, Any],
    expected: dict[str, Any],
) -> bool:
    if any(field not in expected for field in SCENE_SCRIPT_AUDIO_BARS_PLAN_FIELDS):
        return False
    try:
        for field in SCENE_SCRIPT_AUDIO_BARS_PLAN_FIELDS:
            if field in SCENE_SCRIPT_AUDIO_BARS_PLAN_FLOAT_FIELDS:
                if not math.isclose(
                    float(actual[field]),
                    float(expected[field]),
                    rel_tol=1e-6,
                    abs_tol=1e-4,
                ):
                    return False
            elif field in SCENE_SCRIPT_AUDIO_BARS_PLAN_INTEGER_FIELDS:
                if int(actual[field]) != int(expected[field]):
                    return False
            elif field == "source_sha256":
                if str(actual[field]).lower() != str(expected[field]).lower():
                    return False
            elif str(actual[field]) != str(expected[field]):
                return False
    except (KeyError, TypeError, ValueError):
        return False
    return True


def scene_script_audio_bars_execution_metrics(log_text: str) -> dict[str, Any]:
    matches = list(SCENE_SCRIPT_AUDIO_BARS_EXECUTION_RE.finditer(log_text))
    succeeded: set[int] = set()
    failed: set[int] = set()
    for match in matches:
        layer_id = int(match.group("id"))
        if match.group("status") == "succeeded":
            succeeded.add(layer_id)
        else:
            failed.add(layer_id)
    return {
        "has_evidence": bool(matches),
        "succeeded_layer_ids": sorted(succeeded),
        "failed_layer_ids": sorted(failed),
    }


def scene_script_audio_bars_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
    execution: dict[str, Any] | None = None,
) -> list[str]:
    expectation_keys = {
        "expected_scene_script_audio_bars_plan_count",
        "expected_scene_script_audio_bars_diagnostic_count",
        "expected_scene_script_audio_bars_has_audio_consumer",
        "expected_scene_script_audio_bars_total_bar_count",
        "expected_scene_script_audio_bars_plan_layer_ids",
        "expected_scene_script_audio_bars_plans",
        "expected_scene_script_audio_bars_succeeded_layer_ids",
        "required_scene_script_audio_bars_succeeded_layer_ids",
    }
    if not any(key in sample for key in expectation_keys):
        return []

    failures: list[str] = []
    if any(
        metrics[key] is None
        for key in ("plan_count", "diagnostic_count", "has_audio_consumer")
    ):
        failures.append("SceneScript audio bars runtime evidence missing")
    elif metrics["plan_count"] != len(metrics["plans"]):
        failures.append("SceneScript audio bars plan detail count mismatch")
    expected_plan_count = sample.get(
        "expected_scene_script_audio_bars_plan_count"
    )
    if (
        expected_plan_count is not None
        and metrics["plan_count"] != int(expected_plan_count)
    ):
        failures.append("SceneScript audio bars plan count mismatch")
    expected_diagnostic_count = sample.get(
        "expected_scene_script_audio_bars_diagnostic_count"
    )
    if (
        expected_diagnostic_count is not None
        and metrics["diagnostic_count"] != int(expected_diagnostic_count)
    ):
        failures.append("SceneScript audio bars diagnostic count mismatch")
    expected_has_audio_consumer = sample.get(
        "expected_scene_script_audio_bars_has_audio_consumer"
    )
    if (
        expected_has_audio_consumer is not None
        and metrics["has_audio_consumer"] is not bool(expected_has_audio_consumer)
    ):
        failures.append("SceneScript audio bars audio consumer state mismatch")
    expected_total_bar_count = sample.get(
        "expected_scene_script_audio_bars_total_bar_count"
    )
    if (
        expected_total_bar_count is not None
        and metrics["total_bar_count"] != int(expected_total_bar_count)
    ):
        failures.append("SceneScript audio bars total bar count mismatch")
    expected_layer_ids = sample.get(
        "expected_scene_script_audio_bars_plan_layer_ids"
    )
    if expected_layer_ids is not None:
        if metrics["plan_layer_ids"] != sorted(int(value) for value in expected_layer_ids):
            failures.append("SceneScript audio bars plan layer IDs mismatch")

    expected_plans = sample.get("expected_scene_script_audio_bars_plans")
    expected_plan_layer_ids: list[int] = []
    if expected_plans is not None:
        if not isinstance(expected_plans, list):
            failures.append("SceneScript audio bars expected plan tuple invalid")
        else:
            try:
                actual_sorted = sorted(
                    metrics["plans"],
                    key=lambda plan: (
                        int(plan["layer_id"]),
                        str(plan["source_sha256"]),
                    ),
                )
                expected_sorted = sorted(
                    expected_plans,
                    key=lambda plan: (
                        int(plan["layer_id"]),
                        str(plan["source_sha256"]),
                    ),
                )
                expected_plan_layer_ids = sorted({
                    int(plan["layer_id"]) for plan in expected_plans
                })
            except (KeyError, TypeError, ValueError):
                failures.append("SceneScript audio bars expected plan tuple invalid")
            else:
                if (
                    len(actual_sorted) != len(expected_sorted)
                    or any(
                        not scene_script_audio_bars_plan_matches(actual, expected)
                        for actual, expected in zip(actual_sorted, expected_sorted)
                    )
                ):
                    failures.append("SceneScript audio bars plan tuple mismatch")

    expected_succeeded = sample.get(
        "expected_scene_script_audio_bars_succeeded_layer_ids"
    )
    required_succeeded = sorted(
        int(layer_id)
        for layer_id in sample.get(
            "required_scene_script_audio_bars_succeeded_layer_ids",
            [],
        )
    )
    requires_execution = (
        expected_plans is not None
        or expected_succeeded is not None
        or bool(required_succeeded)
    )
    if requires_execution:
        execution = execution or {
            "has_evidence": False,
            "succeeded_layer_ids": [],
            "failed_layer_ids": [],
        }
        succeeded = set(execution["succeeded_layer_ids"])
        if not execution["has_evidence"]:
            failures.append("SceneScript audio bars execution evidence missing")
        failures.extend(
            f"SceneScript audio bars layer {layer_id} failed"
            for layer_id in execution["failed_layer_ids"]
        )
        if expected_succeeded is not None:
            if succeeded != {int(layer_id) for layer_id in expected_succeeded}:
                failures.append(
                    "SceneScript audio bars succeeded layer IDs mismatch"
                )
        for layer_id in required_succeeded:
            if layer_id not in succeeded:
                failures.append(
                    f"SceneScript audio bars layer {layer_id} should succeed"
                )
        for layer_id in expected_plan_layer_ids:
            if layer_id not in succeeded:
                failures.append(
                    f"SceneScript audio bars planned layer {layer_id} should succeed"
                )
    return failures


def utility_runtime_metrics(preview_text: str) -> dict[str, Any]:
    count_match = UTILITY_LAYER_COUNT_RE.search(preview_text)
    capture_match = UTILITY_CAPTURE_COUNT_RE.search(preview_text)
    dependency_match = UTILITY_DEPENDENCY_COUNT_RE.search(preview_text)
    named_consumer_match = UTILITY_NAMED_CONSUMER_COUNT_RE.search(preview_text)
    named_target_match = UTILITY_NAMED_TARGET_PLANNED_RE.search(preview_text)
    named_binding_match = UTILITY_NAMED_BINDING_PLANNED_RE.search(preview_text)
    named_gap_match = UTILITY_NAMED_TARGET_GAP_RE.search(preview_text)
    layers = [
        {
            "id": int(match.group("id")),
            "disposition": match.group("disposition"),
            "kind": match.group("kind"),
        }
        for match in UTILITY_LAYER_RE.finditer(preview_text)
    ]
    return {
        "has_evidence": all(
            match is not None
            for match in (
                count_match,
                capture_match,
                dependency_match,
                named_consumer_match,
                named_target_match,
                named_binding_match,
                named_gap_match,
            )
        ),
        "candidates": int(count_match.group("count")) if count_match else 0,
        "capture_planned": int(capture_match.group("count")) if capture_match else 0,
        "dependency_edges": int(dependency_match.group("count")) if dependency_match else 0,
        "named_consumers": int(named_consumer_match.group("count")) if named_consumer_match else 0,
        "named_target_planned": int(named_target_match.group("count")) if named_target_match else 0,
        "named_binding_planned": int(named_binding_match.group("count")) if named_binding_match else 0,
        "named_target_gaps": int(named_gap_match.group("count")) if named_gap_match else 0,
        "layers": layers,
    }


def utility_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    expected_metrics = {
        "expected_utility_candidates": "candidates",
        "expected_utility_capture_planned": "capture_planned",
        "expected_utility_dependency_edges": "dependency_edges",
        "expected_utility_named_consumers": "named_consumers",
        "expected_utility_named_target_planned": "named_target_planned",
        "expected_utility_named_binding_planned": "named_binding_planned",
        "expected_utility_named_target_gaps": "named_target_gaps",
    }
    requires_evidence = any(key in sample for key in expected_metrics) or bool(
        sample.get("required_utility_dispositions")
    )
    if requires_evidence and not metrics["has_evidence"]:
        return ["utility layer runtime evidence missing"]

    failures: list[str] = []
    for expectation, metric in expected_metrics.items():
        if expectation in sample and metrics[metric] != int(sample[expectation]):
            failures.append(f"utility {metric} mismatch")
    actual_dispositions = {
        str(layer["id"]): layer["disposition"] for layer in metrics["layers"]
    }
    for layer_id, disposition in sample.get("required_utility_dispositions", {}).items():
        if actual_dispositions.get(str(layer_id)) != disposition:
            failures.append(
                f"utility layer {layer_id} disposition should be {disposition}"
            )
    return failures


def utility_capture_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, UTILITY_CAPTURE_EXECUTION_RE)


def authored_effect_graph_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, AUTHORED_EFFECT_GRAPH_EXECUTION_RE)


def authored_effect_graph_legacy_blur_blocked_layer_ids(preview_text: str) -> list[int]:
    match = AUTHORED_EFFECT_GRAPH_LEGACY_BLUR_BLOCKED_RE.search(preview_text)
    if match is None or not match.group("ids"):
        return []
    return sorted({int(value) for value in match.group("ids").split(",")})


def authored_effect_graph_local_contrast_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_LOCAL_CONTRAST_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None


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


def authored_effect_graph_spin_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_SPIN_COUNT_RE.search(preview_text)
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


def authored_effect_graph_foliage_sway_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_FOLIAGE_SWAY_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None


def authored_effect_graph_water_ripple_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_WATER_RIPPLE_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None


def authored_effect_graph_depth_parallax_count(
    preview_text: str,
) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_DEPTH_PARALLAX_COUNT_RE.search(preview_text)
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


def authored_effect_graph_shine_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_SHINE_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None


def authored_effect_graph_shine_isolated_count(
    preview_text: str,
) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_SHINE_ISOLATED_COUNT_RE.search(preview_text)
    return int(match.group("count")) if match is not None else None


def authored_effect_graph_shine_omitted_effects(
    preview_text: str,
) -> list[str] | None:
    match = AUTHORED_EFFECT_GRAPH_SHINE_OMITTED_EFFECTS_RE.search(preview_text)
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


def authored_effect_graph_color_grading_count(preview_text: str) -> int | None:
    match = AUTHORED_EFFECT_GRAPH_COLOR_GRADING_COUNT_RE.search(preview_text)
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


def authored_effect_graph_chain_metrics(preview_text: str) -> dict[str, int | None]:
    chain_match = AUTHORED_EFFECT_GRAPH_CHAIN_COUNT_RE.search(preview_text)
    stage_match = AUTHORED_EFFECT_GRAPH_STAGE_COUNT_RE.search(preview_text)
    return {
        "chain_count": int(chain_match.group("count")) if chain_match else None,
        "stage_count": int(stage_match.group("count")) if stage_match else None,
    }


def named_target_capture_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, NAMED_TARGET_CAPTURE_EXECUTION_RE)


def named_target_binding_execution_metrics(log_text: str) -> dict[str, Any]:
    return capture_execution_metrics(log_text, NAMED_TARGET_BINDING_EXECUTION_RE)


def image_blend_runtime_metrics(
    preview_text: str,
    log_text: str,
) -> dict[str, Any]:
    planned_match = IMAGE_BLEND_PLANNED_RE.search(preview_text)
    execution = capture_execution_metrics(log_text, IMAGE_BLEND_EXECUTION_RE)
    return {
        "has_evidence": planned_match is not None,
        "planned": int(planned_match.group("count")) if planned_match else 0,
        **execution,
    }


def image_blend_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    requires_evidence = "expected_image_blend_planned" in sample or bool(
        sample.get("required_image_blend_succeeded_layer_ids")
    )
    if requires_evidence and not metrics["has_evidence"]:
        return ["image blend runtime evidence missing"]
    failures: list[str] = []
    if "expected_image_blend_planned" in sample:
        if metrics["planned"] != int(sample["expected_image_blend_planned"]):
            failures.append("image blend planned count mismatch")
    succeeded = set(metrics["succeeded_layer_ids"])
    if len(succeeded) < metrics["planned"]:
        failures.append("image blend execution below planned count")
    for layer_id in sample.get("required_image_blend_succeeded_layer_ids", []):
        if layer_id not in succeeded:
            failures.append(f"image blend consumer {layer_id} should succeed")
    return failures


def capture_execution_metrics(
    log_text: str,
    pattern: re.Pattern[str],
) -> dict[str, Any]:
    succeeded: set[int] = set()
    failed: set[int] = set()
    for match in pattern.finditer(log_text):
        layer_id = int(match.group("id"))
        if match.group("status") == "succeeded":
            succeeded.add(layer_id)
            failed.discard(layer_id)
        elif layer_id not in succeeded:
            failed.add(layer_id)
    return {
        "succeeded_layer_ids": sorted(succeeded),
        "failed_layer_ids": sorted(failed),
    }


def authored_effect_graph_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
    legacy_blur_blocked_layer_ids: list[int],
    local_contrast_count: int | None,
    chain_metrics: dict[str, int | None] | None = None,
    workshop_shadow_count: int | None = None,
    spin_count: int | None = None,
    procedural_noise_count: int | None = None,
    film_grain_count: int | None = None,
    light_shafts_count: int | None = None,
    shake_count: int | None = None,
    water_flow_count: int | None = None,
    water_waves_count: int | None = None,
    foliage_sway_count: int | None = None,
    water_ripple_count: int | None = None,
    depth_parallax_count: int | None = None,
    iris_inline_suffix_count: int | None = None,
    cursor_ripple_count: int | None = None,
    cursor_ripple_isolated_count: int | None = None,
    cursor_ripple_omitted_effects: list[str] | None = None,
    shine_count: int | None = None,
    shine_isolated_count: int | None = None,
    shine_omitted_effects: list[str] | None = None,
    clipping_mask_count: int | None = None,
    blend_count: int | None = None,
    tint_count: int | None = None,
    color_grading_count: int | None = None,
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
    route_only_effect_count: int | None = None,
    opacity_layer_ids: list[int] | None = None,
) -> list[str]:
    failures = [
        f"authored effect graph layer {layer_id} failed"
        for layer_id in metrics["failed_layer_ids"]
    ]
    succeeded = set(metrics["succeeded_layer_ids"])
    expected = sample.get("expected_authored_effect_graph_succeeded_layer_ids")
    if expected is not None and succeeded != set(expected):
        failures.append("authored effect graph succeeded layer IDs mismatch")
    for layer_id in sample.get("required_authored_effect_graph_succeeded_layer_ids", []):
        if layer_id not in succeeded:
            failures.append(f"authored effect graph layer {layer_id} should succeed")
    expected_blocked = sample.get(
        "expected_authored_effect_graph_legacy_blur_blocked_layer_ids"
    )
    if expected_blocked is not None:
        if set(legacy_blur_blocked_layer_ids) != set(expected_blocked):
            failures.append("authored effect graph legacy blur blocked layer IDs mismatch")
    runtime_values = {
        "local_contrast_count": local_contrast_count,
        "opacity_count": opacity_count,
        "color_key_count": color_key_count,
        "workshop_audio_bars_count": workshop_audio_bars_count,
        "fisheye_zero_distortion_count": fisheye_zero_distortion_count,
        "opacity_layer_ids": opacity_layer_ids,
        "workshop_shadow_count": workshop_shadow_count,
        "spin_count": spin_count,
        "procedural_noise_count": procedural_noise_count,
        "film_grain_count": film_grain_count,
        "light_shafts_count": light_shafts_count,
        "shake_count": shake_count,
        "water_flow_count": water_flow_count,
        "water_waves_count": water_waves_count,
        "foliage_sway_count": foliage_sway_count,
        "water_ripple_count": water_ripple_count,
        "depth_parallax_count": depth_parallax_count,
        "iris_inline_suffix_count": iris_inline_suffix_count,
        "cursor_ripple_count": cursor_ripple_count,
        "cursor_ripple_isolated_count": cursor_ripple_isolated_count,
        "cursor_ripple_omitted_effects": cursor_ripple_omitted_effects,
        "shine_count": shine_count,
        "shine_isolated_count": shine_isolated_count,
        "shine_omitted_effects": shine_omitted_effects,
        "clipping_mask_count": clipping_mask_count,
        "blend_count": blend_count,
        "tint_count": tint_count,
        "color_grading_count": color_grading_count,
        "pulse_count": pulse_count,
        "godrays_count": godrays_count,
        "transform_count": transform_count,
        "transform_static_fallback_count": transform_static_fallback_count,
        "transform_static_fallback_diagnostics":
            transform_static_fallback_diagnostics,
        "authored_shader_count": authored_shader_count,
        "scroll_count": scroll_count,
        "route_only_effect_count": route_only_effect_count,
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
    chain_metrics = chain_metrics or {"chain_count": None, "stage_count": None}
    for sample_key, metric_key, label in (
        ("expected_authored_effect_graph_chain_count", "chain_count", "chain count"),
        ("expected_authored_effect_graph_stage_count", "stage_count", "stage count"),
    ):
        if sample_key in sample and chain_metrics[metric_key] != int(sample[sample_key]):
            failures.append(f"authored effect graph {label} mismatch")
    return failures


def named_target_binding_failures(
    sample: dict[str, Any],
    planned_count: int,
    metrics: dict[str, Any],
) -> list[str]:
    succeeded = set(metrics["succeeded_layer_ids"])
    failures: list[str] = []
    if len(succeeded) < planned_count:
        failures.append("named target binding execution below planned count")
    for layer_id in sample.get("required_named_target_binding_succeeded_layer_ids", []):
        if layer_id not in succeeded:
            failures.append(f"named target consumer {layer_id} binding should succeed")
    return failures


def solid_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    failures: list[str] = []
    requires_count_evidence = (
        "expected_solid_candidates" in sample
        or bool(sample.get("required_solid_loaded_layer_ids"))
    )
    if requires_count_evidence and not metrics["has_count_evidence"]:
        failures.append("solid layer count evidence missing")
    elif "expected_solid_candidates" in sample:
        if metrics["candidates"] != int(sample["expected_solid_candidates"]):
            failures.append("solid layer candidate count mismatch")

    loaded_layer_ids = set(metrics["loaded_layer_ids"])
    for layer_id in sample.get("required_solid_loaded_layer_ids", []):
        if layer_id not in loaded_layer_ids:
            failures.append(f"solid layer {layer_id} should be loaded")
    return failures


def particle_runtime_failures(
    sample: dict[str, Any],
    metrics: dict[str, Any],
) -> list[str]:
    failures: list[str] = []
    requires_load_evidence = (
        "minimum_particle_loaded" in sample
        or "expected_particle_candidates" in sample
        or bool(sample.get("required_particle_loaded_layer_ids"))
    )
    if requires_load_evidence and not metrics["has_load_evidence"]:
        failures.append("particle load evidence missing")
    else:
        if metrics["loaded"] < int(sample.get("minimum_particle_loaded", 0)):
            failures.append("particle loaded count below minimum")
        expected_candidates = sample.get("expected_particle_candidates")
        if expected_candidates is not None and metrics["candidates"] != int(expected_candidates):
            failures.append("particle candidate count mismatch")

    if "minimum_particle_initial_live" in sample:
        if not metrics["has_initial_live_evidence"]:
            failures.append("particle initial live evidence missing")
        elif metrics["initial_live"] < int(sample["minimum_particle_initial_live"]):
            failures.append("particle initial live count below minimum")
    visibility_expectations = {
        "expected_particle_authored": "authored",
        "expected_particle_visible": "visible",
        "expected_particle_skipped_hidden": "skipped_hidden",
    }
    if any(key in sample for key in visibility_expectations) and not metrics["has_visibility_evidence"]:
        failures.append("particle visibility evidence missing")
    else:
        for expectation, metric in visibility_expectations.items():
            if expectation in sample and metrics[metric] != int(sample[expectation]):
                failures.append(f"particle {metric} count mismatch")
    if "expected_particle_skipped_transparent" in sample:
        if not metrics["has_transparent_evidence"]:
            failures.append("particle transparent visibility evidence missing")
        elif metrics["skipped_transparent"] != int(
            sample["expected_particle_skipped_transparent"]
        ):
            failures.append("particle skipped transparent count mismatch")
    loaded_layer_ids = set(metrics["loaded_layer_ids"])
    for layer_id in sample.get("required_particle_loaded_layer_ids", []):
        if layer_id not in loaded_layer_ids:
            failures.append(f"particle layer {layer_id} should be loaded")
    if "expected_particle_refract_loaded" in sample:
        if not metrics["has_refract_evidence"]:
            failures.append("particle refract evidence missing")
        elif metrics["refract_loaded"] != int(sample["expected_particle_refract_loaded"]):
            failures.append("particle refract loaded count mismatch")
    return failures


def append_property_arguments(
    command: list[str],
    property_overrides: Any,
    live_property_overrides: Any,
) -> None:
    arguments = [
        (property_overrides, "--mwx-debug-scene-properties-json"),
        (live_property_overrides, "--mwx-debug-scene-live-properties-json"),
    ]
    for values, flag in arguments:
        if isinstance(values, dict) and values:
            command.extend([
                flag,
                json.dumps(values, ensure_ascii=False, separators=(",", ":")),
            ])


def append_media_thumbnail_argument(
    command: list[str],
    media_thumbnail_path: Any,
    runtime_sample: Path,
    failures: list[str],
) -> None:
    if media_thumbnail_path is None:
        return
    media_thumbnail = Path(str(media_thumbnail_path))
    if (
        media_thumbnail.is_absolute()
        or ".." in media_thumbnail.parts
        or media_thumbnail.suffix.lower() not in {".png", ".jpg", ".jpeg"}
        or not (runtime_sample / media_thumbnail).is_file()
    ):
        failures.append("invalid isolated media thumbnail path")
        return
    command.extend([
        "--mwx-debug-scene-media-thumbnail",
        str(media_thumbnail),
    ])


def append_media_thumbnail_sequence_argument(
    command: list[str],
    sequence: Any,
    runtime_sample: Path,
    failures: list[str],
) -> None:
    if sequence is None:
        return
    if not isinstance(sequence, list) or not 1 <= len(sequence) <= 8:
        failures.append("invalid isolated media thumbnail sequence")
        return
    normalized: list[dict[str, Any]] = []
    for entry in sequence:
        if not isinstance(entry, dict):
            failures.append("invalid isolated media thumbnail sequence")
            return
        keys = set(entry)
        if keys not in ({"path", "delay"}, {"clear", "delay"}):
            failures.append("invalid isolated media thumbnail sequence")
            return
        delay = entry["delay"]
        if (
            isinstance(delay, bool)
            or not isinstance(delay, (int, float))
            or not math.isfinite(delay)
            or not 0.1 <= delay <= 60
        ):
            failures.append("invalid isolated media thumbnail sequence")
            return
        if "clear" in entry:
            if entry["clear"] is not True:
                failures.append("invalid isolated media thumbnail sequence")
                return
            normalized.append({"clear": True, "delay": float(delay)})
            continue
        path = Path(str(entry["path"]))
        if (
            path.is_absolute()
            or ".." in path.parts
            or path.suffix.lower() not in {".png", ".jpg", ".jpeg"}
            or not (runtime_sample / path).is_file()
        ):
            failures.append("invalid isolated media thumbnail sequence")
            return
        normalized.append({"path": str(path), "delay": float(delay)})
    command.extend([
        "--mwx-debug-scene-media-thumbnail-sequence-json",
        json.dumps(normalized, ensure_ascii=False, separators=(",", ":")),
    ])


def live_property_update_metrics(log_text: str) -> dict[str, Any] | None:
    match = LIVE_PROPERTY_UPDATE_RE.search(log_text)
    if match is None:
        return None

    def window_numbers(raw: str) -> list[int]:
        return [int(value) for value in raw.split(",") if value]

    return {
        "accepted": match.group("accepted") == "true",
        "surfaces_before": int(match.group("before")),
        "surfaces_after": int(match.group("after")),
        "windows_before": window_numbers(match.group("windows_before")),
        "windows_after": window_numbers(match.group("windows_after")),
        "keys": [value for value in match.group("keys").split(",") if value],
    }


def live_property_update_failures(
    requested: Any,
    metrics: dict[str, Any] | None,
) -> list[str]:
    if not isinstance(requested, dict) or not requested:
        return []
    if metrics is None:
        return ["live property update evidence missing"]

    failures: list[str] = []
    if not metrics["accepted"]:
        failures.append("live property update rejected")
    if metrics["surfaces_before"] != metrics["surfaces_after"]:
        failures.append("live property update changed Scene surface count")
    if metrics["windows_before"] != metrics["windows_after"]:
        failures.append("live property update replaced Scene windows")
    if metrics["keys"] != sorted(requested):
        failures.append("live property update key evidence mismatch")
    return failures


def live_property_output_failures(
    sample: dict[str, Any],
    motion: dict[str, Any] | None,
) -> list[str]:
    minimum = sample.get("minimum_live_changed_ratio")
    if minimum is None:
        return []
    if motion is None or motion["changed_ratio"] < float(minimum):
        return ["live property output evidence below minimum"]
    return []


def run_sample(
    runtime_binary: Path,
    sample_root: Path,
    sample: dict[str, Any],
    output_dir: Path,
    runtime_root: Path,
    duration: float,
    after_snapshot_delay: float | None,
    audio_spectrum_fixture: bool = False,
) -> dict[str, Any]:
    sample_id = str(sample["id"])
    source = sample_root / "Scene" / sample_id
    result_dir = output_dir / "results" / sample_id
    runtime_sample = runtime_root / "runtime-samples" / sample_id
    runtime_home = runtime_root / "runtime-homes" / sample_id
    result_dir.mkdir(parents=True)
    runtime_home.mkdir(parents=True)
    copy_sample(source, runtime_sample)
    for file_name in SAMPLE_ROOT_DERIVED_FILES:
        (runtime_sample / file_name).unlink(missing_ok=True)
    package_path = scene_package_path(source)
    if package_path is None:
        raise FileNotFoundError(f"Scene sample package is missing: {source}")

    hashes = {
        "project_sha256": sha256(source / "project.json"),
        "package_sha256": sha256(package_path),
    }
    failures: list[str] = []
    for key, actual in hashes.items():
        expected = sample.get(key)
        if expected and expected != actual:
            failures.append(f"{key} mismatch")

    app_log = result_dir / "app.log"
    command = [
        str(runtime_binary),
        "--mwx-debug-scene-root",
        str(runtime_sample),
        "--mwx-debug-scene-evidence-dir",
        str(result_dir),
        "--mwx-debug-scene-duration",
        str(duration),
    ]
    if after_snapshot_delay is not None:
        command.extend([
            "--mwx-debug-scene-after-snapshot-delay",
            str(after_snapshot_delay),
        ])
    if audio_spectrum_fixture or sample.get("audio_spectrum_fixture") is True:
        command.append("--mwx-debug-scene-audio-spectrum-fixture")
    property_overrides = sample.get("property_overrides")
    live_property_overrides = sample.get("live_property_overrides")
    append_property_arguments(command, property_overrides, live_property_overrides)
    append_media_thumbnail_argument(
        command,
        sample.get("media_thumbnail_path"),
        runtime_sample,
        failures,
    )
    append_media_thumbnail_sequence_argument(
        command,
        sample.get("media_thumbnail_sequence"),
        runtime_sample,
        failures,
    )
    hover_pointer = hover_pointer_normalized(sample)
    if hover_pointer is not None:
        command.extend([
            "--mwx-debug-scene-hover-pointer-json",
            json.dumps(
                {"x": hover_pointer[0], "y": hover_pointer[1]},
                separators=(",", ":"),
            ),
        ])
    environment = os.environ.copy()
    environment["HOME"] = str(runtime_home)
    environment["CFFIXED_USER_HOME"] = str(runtime_home)
    timed_out = False
    with app_log.open("w", encoding="utf-8") as log_handle:
        process = subprocess.Popen(
            command,
            cwd=output_dir,
            env=environment,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            exit_code = process.wait(timeout=duration + 20)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.terminate()
            try:
                exit_code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                exit_code = process.wait(timeout=5)

    log_text = app_log.read_text(encoding="utf-8", errors="replace")
    preview_log = result_dir / "scene-preview.log"
    preview_text = preview_log.read_text(encoding="utf-8", errors="replace") if preview_log.is_file() else ""
    ready_match = READY_RE.search(log_text)
    runtime_evidence_match = RUNTIME_EVIDENCE_RE.search(log_text)
    stopped_match = STOPPED_RE.search(log_text)
    surface_count = int(ready_match.group("surfaces")) if ready_match else None
    startup_ready_ms = (
        float(ready_match.group("startup_elapsed_ms"))
        if ready_match and ready_match.group("startup_elapsed_ms") is not None
        else None
    )
    performance = performance_metrics(log_text, surface_count)
    live_property_update = live_property_update_metrics(log_text)
    loaded_match = LOADED_RE.search(preview_text)
    loaded = int(loaded_match.group("loaded")) if loaded_match else 0
    total = int(loaded_match.group("total")) if loaded_match else 0
    loaded_ratio = loaded / total if total else 0.0
    text_loaded_match = TEXT_LOADED_RE.search(preview_text)
    text_loaded = int(text_loaded_match.group("loaded")) if text_loaded_match else 0
    text_total = int(text_loaded_match.group("total")) if text_loaded_match else 0
    text_loaded_layer_ids = [int(match.group("id")) for match in TEXT_LAYER_OK_RE.finditer(preview_text)]
    text_script_runtime = text_script_runtime_metrics(preview_text)
    time_of_day_effect_script_runtime = time_of_day_effect_script_runtime_metrics(
        preview_text
    )
    media_thumbnail_runtime = media_thumbnail_runtime_metrics(preview_text)
    media_thumbnail_transition_execution = (
        media_thumbnail_transition_execution_metrics(log_text)
    )
    media_thumbnail_store = media_thumbnail_store_metrics(log_text)
    scene_script_audio_bars_runtime = scene_script_audio_bars_runtime_metrics(
        preview_text
    )
    scene_script_audio_bars_execution = (
        scene_script_audio_bars_execution_metrics(log_text)
    )
    solid_runtime = solid_runtime_metrics(preview_text)
    puppet_animation_runtime = puppet_animation_runtime_metrics(preview_text)
    utility_runtime = utility_runtime_metrics(preview_text)
    utility_capture_execution = utility_capture_execution_metrics(log_text)
    authored_effect_graph_execution = authored_effect_graph_execution_metrics(log_text)
    authored_effect_graph_legacy_blur_blocked = (
        authored_effect_graph_legacy_blur_blocked_layer_ids(preview_text)
    )
    authored_effect_graph_local_contrast = authored_effect_graph_local_contrast_count(
        preview_text
    )
    authored_effect_graph_opacity = authored_effect_graph_opacity_count(preview_text)
    authored_effect_graph_color_key = authored_effect_graph_color_key_count(preview_text)
    authored_effect_graph_workshop_shift_hue = (
        authored_effect_graph_workshop_shift_hue_count(preview_text)
    )
    authored_effect_graph_workshop_audio_bars = (
        authored_effect_graph_workshop_audio_bars_count(preview_text)
    )
    authored_effect_graph_fisheye_zero_distortion = (
        authored_effect_graph_fisheye_zero_distortion_count(preview_text)
    )
    authored_effect_graph_workshop_gradient = (
        authored_effect_graph_workshop_gradient_count(preview_text)
    )
    authored_effect_graph_workshop_audio_hue_shift = (
        authored_effect_graph_workshop_audio_hue_shift_count(preview_text)
    )
    authored_effect_graph_opacity_layers = authored_effect_graph_opacity_layer_ids(
        preview_text
    )
    authored_effect_graph_workshop_shadow = authored_effect_graph_workshop_shadow_count(
        preview_text
    )
    authored_effect_graph_spin = authored_effect_graph_spin_count(preview_text)
    authored_effect_graph_procedural_noise = (
        authored_effect_graph_procedural_noise_count(preview_text)
    )
    authored_effect_graph_film_grain = authored_effect_graph_film_grain_count(preview_text)
    authored_effect_graph_light_shafts = authored_effect_graph_light_shafts_count(
        preview_text
    )
    authored_effect_graph_shake = authored_effect_graph_shake_count(preview_text)
    authored_effect_graph_water_flow = authored_effect_graph_water_flow_count(preview_text)
    authored_effect_graph_water_waves = authored_effect_graph_water_waves_count(preview_text)
    authored_effect_graph_foliage_sway = authored_effect_graph_foliage_sway_count(
        preview_text
    )
    authored_effect_graph_water_ripple = authored_effect_graph_water_ripple_count(
        preview_text
    )
    authored_effect_graph_depth_parallax = (
        authored_effect_graph_depth_parallax_count(preview_text)
    )
    authored_effect_graph_iris_inline_suffix = (
        authored_effect_graph_iris_inline_suffix_count(preview_text)
    )
    authored_effect_graph_cursor_ripple = authored_effect_graph_cursor_ripple_count(
        preview_text
    )
    authored_effect_graph_cursor_ripple_isolated = (
        authored_effect_graph_cursor_ripple_isolated_count(preview_text)
    )
    authored_effect_graph_cursor_ripple_omitted = (
        authored_effect_graph_cursor_ripple_omitted_effects(preview_text)
    )
    authored_effect_graph_shine = authored_effect_graph_shine_count(preview_text)
    authored_effect_graph_shine_isolated = (
        authored_effect_graph_shine_isolated_count(preview_text)
    )
    authored_effect_graph_shine_omitted = authored_effect_graph_shine_omitted_effects(
        preview_text
    )
    authored_effect_graph_clipping_mask = authored_effect_graph_clipping_mask_count(
        preview_text
    )
    authored_effect_graph_blend = authored_effect_graph_blend_count(preview_text)
    authored_effect_graph_tint = authored_effect_graph_tint_count(preview_text)
    authored_effect_graph_color_grading = authored_effect_graph_color_grading_count(
        preview_text
    )
    authored_effect_graph_pulse = authored_effect_graph_pulse_count(preview_text)
    authored_effect_graph_godrays = authored_effect_graph_godrays_count(preview_text)
    authored_effect_graph_transform = authored_effect_graph_transform_count(preview_text)
    authored_effect_graph_transform_static_fallback = (
        authored_effect_graph_transform_static_fallback_count(preview_text)
    )
    authored_effect_graph_transform_fallback_diagnostics = (
        authored_effect_graph_transform_static_fallback_diagnostics(preview_text)
    )
    authored_effect_graph_authored_shader = authored_effect_graph_authored_shader_count(
        preview_text
    )
    authored_effect_graph_scroll = authored_effect_graph_scroll_count(preview_text)
    authored_effect_graph_chain = authored_effect_graph_chain_metrics(preview_text)
    route_only_effect_count = preview_text.count("offscreen route-only")
    named_target_capture_execution = named_target_capture_execution_metrics(log_text)
    named_target_binding_execution = named_target_binding_execution_metrics(log_text)
    image_blend_runtime = image_blend_runtime_metrics(preview_text, log_text)
    particle_runtime = particle_runtime_metrics(preview_text)
    camera_match = CAMERA_RE.search(preview_text)
    initial_reason = "before" if hover_pointer is not None else "ready"
    ready_snapshot = result_dir / f"scene-{initial_reason}-window.png"
    hover_snapshot = result_dir / "scene-hover-window.png"
    after_snapshot = result_dir / "scene-after-window.png"
    ready_non_black = png_has_non_black_pixel(ready_snapshot)
    hover_non_black = (
        png_has_non_black_pixel(hover_snapshot)
        if hover_pointer is not None
        else None
    )
    after_non_black = png_has_non_black_pixel(after_snapshot)
    flat_border_ratio = {
        "ready": png_flat_border_ratio(ready_snapshot),
        "after": png_flat_border_ratio(after_snapshot),
    }
    if hover_pointer is not None:
        flat_border_ratio["hover"] = png_flat_border_ratio(hover_snapshot)
    motion = png_motion_metrics(ready_snapshot, after_snapshot)
    hover_motion = (
        {
            "before_to_hover": png_motion_metrics(ready_snapshot, hover_snapshot),
            "hover_to_after": png_motion_metrics(hover_snapshot, after_snapshot),
        }
        if hover_pointer is not None
        else None
    )
    preview_visual = collect_preview_visual_evidence(
        runtime_sample,
        after_snapshot,
        result_dir,
    )
    runtime_evidence_path = (
        Path(runtime_evidence_match.group("path").strip())
        if runtime_evidence_match is not None
        else Path("-")
    )
    runtime_evidence = runtime_evidence_metrics(runtime_evidence_path)
    sample_root_residue = [
        file_name
        for file_name in SAMPLE_ROOT_DERIVED_FILES
        if (runtime_sample / file_name).exists()
    ]

    if timed_out:
        failures.append("process timeout")
    if exit_code != 0:
        failures.append(f"process exit {exit_code}")
    if ready_match is None:
        failures.append("missing ready event")
    elif int(ready_match.group("surfaces")) < 1:
        failures.append("no Scene surface")
    elif startup_ready_ms is None:
        failures.append("missing startup ready elapsed evidence")
    elif not math.isfinite(startup_ready_ms) or startup_ready_ms < 0:
        failures.append("invalid startup ready elapsed evidence")
    failures.extend(performance_failures(performance))
    if runtime_evidence_match is None:
        failures.append("missing runtime evidence path")
    elif runtime_evidence_path.resolve() != (
        result_dir / "scene-runtime-evidence.json"
    ).resolve():
        failures.append("Scene runtime evidence path is outside Debug evidence directory")
    if sample_root_residue:
        failures.append(
            "Scene sample root contains derived files: " + ", ".join(sample_root_residue)
        )
    if stopped_match is None or int(stopped_match.group("after")) != 0:
        failures.append("Scene surfaces not released")
    failures.extend(live_property_update_failures(
        live_property_overrides,
        live_property_update,
    ))
    if "phase=snapshot-failed" in log_text:
        failures.append("window snapshot failed")
    if hover_pointer is not None:
        if log_text.count("phase=pointer-state state=outside") != 2:
            failures.append("pointer outside transition evidence mismatch")
        if "phase=pointer-state state=hover" not in log_text:
            failures.append("pointer hover transition evidence missing")
    if camera_match is None or camera_match.group("projection") != "cover":
        failures.append("camera projection evidence missing")
    expected_parallax = sample.get("expected_camera_parallax")
    if expected_parallax is not None:
        actual_parallax = camera_match and camera_match.group("parallax") == "true"
        if actual_parallax != bool(expected_parallax):
            failures.append("camera parallax state mismatch")
    minimum_parallax_layers = int(sample.get("minimum_authored_parallax_layer_count", 0))
    if runtime_evidence["authored_parallax_layer_count"] < minimum_parallax_layers:
        failures.append("authored parallax layer count below minimum")
    if loaded_ratio < float(sample.get("minimum_loaded_ratio", 0)):
        failures.append(f"loaded ratio {loaded_ratio:.3f} below minimum")
    if text_loaded < int(sample.get("minimum_text_loaded", 0)):
        failures.append("text texture count below minimum")
    if "expected_text_candidates" in sample and text_total != int(sample["expected_text_candidates"]):
        failures.append("text candidate count mismatch")
    for layer_id in sample.get("required_text_loaded_layer_ids", []):
        if layer_id not in text_loaded_layer_ids:
            failures.append(f"text layer {layer_id} should be loaded")
    failures.extend(solid_runtime_failures(sample, solid_runtime))
    failures.extend(
        puppet_animation_runtime_failures(sample, puppet_animation_runtime)
    )
    failures.extend(utility_runtime_failures(sample, utility_runtime))
    failures.extend(authored_effect_graph_failures(
        sample,
        authored_effect_graph_execution,
        authored_effect_graph_legacy_blur_blocked,
        authored_effect_graph_local_contrast,
        authored_effect_graph_chain,
        workshop_shadow_count=authored_effect_graph_workshop_shadow,
        spin_count=authored_effect_graph_spin,
        procedural_noise_count=authored_effect_graph_procedural_noise,
        film_grain_count=authored_effect_graph_film_grain,
        light_shafts_count=authored_effect_graph_light_shafts,
        shake_count=authored_effect_graph_shake,
        water_flow_count=authored_effect_graph_water_flow,
        water_waves_count=authored_effect_graph_water_waves,
        foliage_sway_count=authored_effect_graph_foliage_sway,
        water_ripple_count=authored_effect_graph_water_ripple,
        depth_parallax_count=authored_effect_graph_depth_parallax,
        iris_inline_suffix_count=authored_effect_graph_iris_inline_suffix,
        cursor_ripple_count=authored_effect_graph_cursor_ripple,
        cursor_ripple_isolated_count=authored_effect_graph_cursor_ripple_isolated,
        cursor_ripple_omitted_effects=authored_effect_graph_cursor_ripple_omitted,
        shine_count=authored_effect_graph_shine,
        shine_isolated_count=authored_effect_graph_shine_isolated,
        shine_omitted_effects=authored_effect_graph_shine_omitted,
        clipping_mask_count=authored_effect_graph_clipping_mask,
        blend_count=authored_effect_graph_blend,
        tint_count=authored_effect_graph_tint,
        color_grading_count=authored_effect_graph_color_grading,
        pulse_count=authored_effect_graph_pulse,
        godrays_count=authored_effect_graph_godrays,
        transform_count=authored_effect_graph_transform,
        transform_static_fallback_count=authored_effect_graph_transform_static_fallback,
        transform_static_fallback_diagnostics=(
            authored_effect_graph_transform_fallback_diagnostics
        ),
        authored_shader_count=authored_effect_graph_authored_shader,
        scroll_count=authored_effect_graph_scroll,
        opacity_count=authored_effect_graph_opacity,
        color_key_count=authored_effect_graph_color_key,
        workshop_audio_bars_count=authored_effect_graph_workshop_audio_bars,
        fisheye_zero_distortion_count=(
            authored_effect_graph_fisheye_zero_distortion
        ),
        route_only_effect_count=route_only_effect_count,
        opacity_layer_ids=authored_effect_graph_opacity_layers,
    ))
    succeeded_capture_ids = set(utility_capture_execution["succeeded_layer_ids"])
    if len(succeeded_capture_ids) < utility_runtime["capture_planned"]:
        failures.append("utility capture execution below planned count")
    for layer_id in sample.get("required_utility_capture_succeeded_layer_ids", []):
        if layer_id not in succeeded_capture_ids:
            failures.append(f"utility layer {layer_id} capture should succeed")
    succeeded_named_target_ids = set(named_target_capture_execution["succeeded_layer_ids"])
    if len(succeeded_named_target_ids) < utility_runtime["named_target_planned"]:
        failures.append("named target capture execution below planned count")
    for layer_id in sample.get("required_named_target_capture_succeeded_layer_ids", []):
        if layer_id not in succeeded_named_target_ids:
            failures.append(f"named target layer {layer_id} capture should succeed")
    failures.extend(named_target_binding_failures(
        sample,
        utility_runtime["named_binding_planned"],
        named_target_binding_execution,
    ))
    failures.extend(image_blend_runtime_failures(sample, image_blend_runtime))
    failures.extend(particle_runtime_failures(sample, particle_runtime))
    blur_runtime_count = preview_text.count("effect runtime gaussian-blur;")
    if blur_runtime_count < int(sample.get("minimum_gaussian_blur_runtime_count", 0)):
        failures.append("gaussian blur runtime count below minimum")
    precise_blur_runtime_count = preview_text.count("effect runtime gaussian-blur-precise;")
    if precise_blur_runtime_count < int(sample.get("minimum_precise_blur_runtime_count", 0)):
        failures.append("precise gaussian blur runtime count below minimum")
    authored_opacity_runtime_count = preview_text.count("effect runtime opacity-authored;")
    if authored_opacity_runtime_count < int(
        sample.get("minimum_authored_opacity_runtime_count", 0)
    ):
        failures.append("authored opacity runtime count below minimum")
    skipped_composite_count = preview_text.count("unsupported composite skipped;")
    if skipped_composite_count < int(sample.get("minimum_skipped_composite_count", 0)):
        failures.append("unsupported composite fallback count below minimum")
    maximum_skipped_composite_count = sample.get("maximum_skipped_composite_count")
    if maximum_skipped_composite_count is not None:
        if skipped_composite_count > int(maximum_skipped_composite_count):
            failures.append("unsupported composite fallback count above maximum")
    perspective_opacity_count = preview_text.count("effect runtime perspective-opacity;")
    if perspective_opacity_count < int(sample.get("minimum_perspective_opacity_runtime_count", 0)):
        failures.append("perspective opacity runtime count below minimum")
    water_ripple_normal_count = preview_text.count("effect runtime waterripple-normal;")
    if water_ripple_normal_count < int(sample.get("minimum_water_ripple_normal_runtime_count", 0)):
        failures.append("normal-map water ripple runtime count below minimum")
    water_ripple_normal_load_count = preview_text.count("waterripple normal OK")
    if water_ripple_normal_load_count < int(sample.get("minimum_water_ripple_normal_load_count", 0)):
        failures.append("normal-map water ripple texture load count below minimum")
    legacy_water_ripple_count = preview_text.count("effect runtime waterripple-legacy;")
    if legacy_water_ripple_count < int(sample.get("minimum_legacy_water_ripple_runtime_count", 0)):
        failures.append("legacy water ripple runtime count below minimum")
    maximum_legacy_water_ripple_count = sample.get("maximum_legacy_water_ripple_runtime_count")
    if maximum_legacy_water_ripple_count is not None:
        if legacy_water_ripple_count > int(maximum_legacy_water_ripple_count):
            failures.append("legacy water ripple runtime count above maximum")
    legacy_waterwaves_count = preview_text.count("effect runtime waterwaves-legacy;")
    if legacy_waterwaves_count < int(sample.get("minimum_legacy_waterwaves_runtime_count", 0)):
        failures.append("legacy waterwaves runtime count below minimum")
    maximum_legacy_waterwaves_count = sample.get("maximum_legacy_waterwaves_runtime_count")
    if maximum_legacy_waterwaves_count is not None:
        if legacy_waterwaves_count > int(maximum_legacy_waterwaves_count):
            failures.append("legacy waterwaves runtime count above maximum")
    sprite_animation_count = preview_text.count("; sprite animation frames=")
    if sprite_animation_count < int(sample.get("minimum_sprite_animation_count", 0)):
        failures.append("sprite animation runtime count below minimum")
    color_blend_mode_9_count = preview_text.count("layer color blend mode=9")
    if color_blend_mode_9_count < int(sample.get("minimum_color_blend_mode_9_count", 0)):
        failures.append("layer color blend mode 9 count below minimum")
    if runtime_evidence["schema_version"] is None:
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
        if expectation in sample and runtime_evidence[metric] != int(sample[expectation]):
            failures.append(f"Scene runtime evidence {metric} mismatch")
    expected_effect_graph_sha256 = sample.get("expected_effect_graph_sha256")
    if expected_effect_graph_sha256 is not None:
        if runtime_evidence["effect_graph_sha256"] != expected_effect_graph_sha256:
            failures.append("Scene runtime evidence effect graph sha256 mismatch")
    expected_opacity_candidates = sample.get(
        "expected_stock_opacity_single_effect_candidate_layer_ids"
    )
    if expected_opacity_candidates is not None:
        if (
            runtime_evidence["stock_opacity_single_effect_candidate_layer_ids"]
            != sorted(expected_opacity_candidates)
        ):
            failures.append("Scene runtime evidence stock Opacity candidate IDs mismatch")
    expected_shader_contract_aggregate_sha256 = sample.get(
        "expected_shader_contract_aggregate_sha256"
    )
    if expected_shader_contract_aggregate_sha256 is not None:
        if (
            runtime_evidence["shader_contract_aggregate_sha256"]
            != expected_shader_contract_aggregate_sha256
        ):
            failures.append("Scene runtime evidence shader contract aggregate sha256 mismatch")
    expected_text_value = sample.get("expected_text_value")
    if expected_text_value is not None and expected_text_value not in runtime_evidence["text_values"]:
        failures.append("Scene runtime evidence text property mismatch")
    expected_text_script_binding_count = sample.get("expected_text_script_binding_count")
    if expected_text_script_binding_count is not None:
        if text_script_runtime["binding_count"] != int(expected_text_script_binding_count):
            failures.append("text script binding count mismatch")
    required_text_script_binding_layer_ids = sorted(
        int(layer_id)
        for layer_id in sample.get("required_text_script_binding_layer_ids", [])
    )
    if required_text_script_binding_layer_ids:
        if text_script_runtime["binding_layer_ids"] != required_text_script_binding_layer_ids:
            failures.append("text script binding layer IDs mismatch")
    expected_time_of_day_binding_count = sample.get(
        "expected_time_of_day_effect_script_binding_count"
    )
    if expected_time_of_day_binding_count is not None:
        if time_of_day_effect_script_runtime["binding_count"] != int(
            expected_time_of_day_binding_count
        ):
            failures.append("time-of-day effect script binding count mismatch")
    required_time_of_day_bindings = sample.get(
        "required_time_of_day_effect_script_bindings", []
    )
    if required_time_of_day_bindings:
        if time_of_day_effect_script_runtime["bindings"] != required_time_of_day_bindings:
            failures.append("time-of-day effect script bindings mismatch")
    expected_media_thumbnail_count = sample.get(
        "expected_media_thumbnail_current_binding_count"
    )
    if expected_media_thumbnail_count is not None:
        if media_thumbnail_runtime["current_binding_count"] != int(
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
            media_thumbnail_runtime["current_binding_layer_ids"]
            != required_media_thumbnail_layer_ids
        ):
            failures.append("media thumbnail current binding layer IDs mismatch")
    expected_media_transition_count = sample.get(
        "expected_media_thumbnail_previous_transition_count"
    )
    if expected_media_transition_count is not None:
        if media_thumbnail_runtime["previous_transition_count"] != int(
            expected_media_transition_count
        ):
            failures.append("media thumbnail previous transition count mismatch")
    required_media_transition_layer_ids = sorted(
        int(layer_id)
        for layer_id in sample.get(
            "required_media_thumbnail_previous_transition_layer_ids", []
        )
    )
    if required_media_transition_layer_ids:
        if (
            media_thumbnail_runtime["previous_transition_layer_ids"]
            != required_media_transition_layer_ids
        ):
            failures.append("media thumbnail previous transition layer IDs mismatch")
    for expectation, metric in (
        (
            "required_media_thumbnail_transition_started_layer_ids",
            "started_layer_ids",
        ),
        (
            "required_media_thumbnail_transition_midpoint_layer_ids",
            "midpoint_layer_ids",
        ),
        (
            "required_media_thumbnail_transition_completed_layer_ids",
            "completed_layer_ids",
        ),
    ):
        required_layer_ids = sorted(int(value) for value in sample.get(expectation, []))
        if required_layer_ids:
            if media_thumbnail_transition_execution[metric] != required_layer_ids:
                failures.append(f"media thumbnail transition {metric} mismatch")
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
        if media_thumbnail_store["clear_count"] != int(
            sample["expected_media_thumbnail_clear_count"]
        ):
            failures.append("media thumbnail clear count mismatch")
    failures.extend(
        scene_script_audio_bars_runtime_failures(
            sample,
            scene_script_audio_bars_runtime,
            scene_script_audio_bars_execution,
        )
    )
    visible_layer_ids = set(runtime_evidence["visible_layer_ids"])
    for layer_id in sample.get("required_visible_layer_ids", []):
        if layer_id not in visible_layer_ids:
            failures.append(f"Scene property layer {layer_id} should be visible")
    for layer_id in sample.get("required_hidden_layer_ids", []):
        if layer_id in visible_layer_ids:
            failures.append(f"Scene property layer {layer_id} should be hidden")
    effective_visible_layer_ids = set(runtime_evidence["effective_visible_layer_ids"])
    for layer_id in sample.get("required_effectively_visible_layer_ids", []):
        if layer_id not in effective_visible_layer_ids:
            failures.append(f"Scene layer {layer_id} should be effectively visible")
    for layer_id in sample.get("required_effectively_hidden_layer_ids", []):
        if layer_id in effective_visible_layer_ids:
            failures.append(f"Scene layer {layer_id} should be effectively hidden")
    solid_layer_ids = set(runtime_evidence["solid_layer_ids"])
    for layer_id in sample.get("required_solid_layer_ids", []):
        if layer_id not in solid_layer_ids:
            failures.append(f"Scene solid layer {layer_id} is missing")
    effective_visible_solid_layer_ids = set(
        runtime_evidence["effective_visible_solid_layer_ids"]
    )
    for layer_id in sample.get("required_effectively_visible_solid_layer_ids", []):
        if layer_id not in effective_visible_solid_layer_ids:
            failures.append(f"Scene solid layer {layer_id} should be effectively visible")
    effect_files = set(runtime_evidence["effect_files"])
    for effect_file in sample.get("required_effect_files", []):
        if effect_file not in effect_files:
            failures.append(f"Scene effect file missing: {effect_file}")
    bloom_runtime_count = preview_text.count("effect runtime bloom")
    if bloom_runtime_count < int(sample.get("minimum_bloom_runtime_count", 0)):
        failures.append("bloom runtime count below minimum")
    if not ready_non_black or not after_non_black:
        failures.append("non-black window evidence missing")
    if hover_pointer is not None:
        if not hover_non_black:
            failures.append("hover window evidence missing")
        minimum_hover_ratio = float(sample.get("minimum_hover_changed_ratio", 0))
        hover_ratios = [
            metrics["changed_ratio"]
            for metrics in (hover_motion or {}).values()
            if metrics is not None
        ]
        if len(hover_ratios) != 2 or min(hover_ratios) <= minimum_hover_ratio:
            failures.append("hover interaction output evidence below minimum")
    if sample.get("requires_motion"):
        minimum_changed_ratio = float(sample.get("minimum_changed_ratio", 0))
        if motion is None or motion["changed_ratio"] < minimum_changed_ratio:
            failures.append("animated output evidence below minimum")
    failures.extend(live_property_output_failures(sample, motion))
    maximum_changed_ratio = sample.get("maximum_changed_ratio")
    if maximum_changed_ratio is not None:
        if motion is None or motion["changed_ratio"] > float(maximum_changed_ratio):
            failures.append("static output evidence above maximum")
    maximum_flat_border_ratio = sample.get("maximum_flat_border_ratio")
    if maximum_flat_border_ratio is not None:
        ratios = [value for value in flat_border_ratio.values() if value is not None]
        expected_ratio_count = 3 if hover_pointer is not None else 2
        if (
            len(ratios) != expected_ratio_count
            or max(ratios) > float(maximum_flat_border_ratio)
        ):
            failures.append("flat border evidence above maximum")

    return {
        "id": sample_id,
        "title": sample.get("title"),
        "capabilities": sample.get("capabilities", []),
        "audio_spectrum_fixture": audio_spectrum_fixture
            or sample.get("audio_spectrum_fixture") is True,
        "property_overrides": property_overrides if isinstance(property_overrides, dict) else {},
        "live_property_overrides": (
            live_property_overrides if isinstance(live_property_overrides, dict) else {}
        ),
        "passed": not failures,
        "failures": failures,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "hashes": hashes,
        "package_file": package_path.name,
        "runtime_sample": str(runtime_sample),
        "runtime_home": str(runtime_home),
        "runtime_retained": True,
        "evidence": {
            "app_log": str(app_log),
            "preview_log": str(preview_log),
            "runtime_evidence": str(runtime_evidence_path),
            "sample_root_residue": sample_root_residue,
            "ready_snapshot": str(ready_snapshot),
            "hover_snapshot": str(hover_snapshot) if hover_pointer is not None else None,
            "after_snapshot": str(after_snapshot),
            "ready_non_black": ready_non_black,
            "hover_non_black": hover_non_black,
            "after_non_black": after_non_black,
            "flat_border_ratio": flat_border_ratio,
            "motion": motion,
            "hover_motion": hover_motion,
            "preview_visual": preview_visual,
        },
        "runtime": {
            "layers": int(ready_match.group("layers")) if ready_match else None,
            "image_layers": int(ready_match.group("images")) if ready_match else None,
            "effects": int(ready_match.group("effects")) if ready_match else None,
            "surfaces": int(ready_match.group("surfaces")) if ready_match else None,
            "startup_ready_ms": startup_ready_ms,
            "performance": performance,
            "hover_pointer_normalized": (
                list(hover_pointer) if hover_pointer is not None else None
            ),
            "live_property_update": live_property_update,
            "loaded_textures": loaded,
            "texture_candidates": total,
            "loaded_ratio": round(loaded_ratio, 4),
            "loaded_textures_text": text_loaded,
            "text_candidates": text_total,
            "text_loaded_layer_ids": text_loaded_layer_ids,
            "text_script_binding_count": text_script_runtime["binding_count"],
            "text_script_diagnostic_count": text_script_runtime["diagnostic_count"],
            "text_script_binding_layer_ids": text_script_runtime["binding_layer_ids"],
            "text_script_bindings": text_script_runtime["bindings"],
            "time_of_day_effect_script_binding_count": (
                time_of_day_effect_script_runtime["binding_count"]
            ),
            "time_of_day_effect_script_debug_wall_date": (
                time_of_day_effect_script_runtime["debug_wall_date"]
            ),
            "time_of_day_effect_script_bindings": (
                time_of_day_effect_script_runtime["bindings"]
            ),
            "media_thumbnail_current_binding_count": (
                media_thumbnail_runtime["current_binding_count"]
            ),
            "media_thumbnail_current_binding_layer_ids": (
                media_thumbnail_runtime["current_binding_layer_ids"]
            ),
            "media_thumbnail_previous_transition_count": (
                media_thumbnail_runtime["previous_transition_count"]
            ),
            "media_thumbnail_previous_transition_layer_ids": (
                media_thumbnail_runtime["previous_transition_layer_ids"]
            ),
            "media_thumbnail_transition_generation_ids": (
                media_thumbnail_transition_execution["generation_ids"]
            ),
            "media_thumbnail_transition_started_layer_ids": (
                media_thumbnail_transition_execution["started_layer_ids"]
            ),
            "media_thumbnail_transition_midpoint_layer_ids": (
                media_thumbnail_transition_execution["midpoint_layer_ids"]
            ),
            "media_thumbnail_transition_completed_layer_ids": (
                media_thumbnail_transition_execution["completed_layer_ids"]
            ),
            "media_thumbnail_pending_last_ready": (
                media_thumbnail_store["pending_last_ready"]
            ),
            "media_thumbnail_ready_states": media_thumbnail_store["ready_states"],
            "media_thumbnail_clear_count": media_thumbnail_store["clear_count"],
            "scene_script_audio_bars_plan_count": (
                scene_script_audio_bars_runtime["plan_count"]
            ),
            "scene_script_audio_bars_diagnostic_count": (
                scene_script_audio_bars_runtime["diagnostic_count"]
            ),
            "scene_script_audio_bars_has_audio_consumer": (
                scene_script_audio_bars_runtime["has_audio_consumer"]
            ),
            "scene_script_audio_bars_total_bar_count": (
                scene_script_audio_bars_runtime["total_bar_count"]
            ),
            "scene_script_audio_bars_plan_layer_ids": (
                scene_script_audio_bars_runtime["plan_layer_ids"]
            ),
            "scene_script_audio_bars_plans": (
                scene_script_audio_bars_runtime["plans"]
            ),
            "scene_script_audio_bars_succeeded_layer_ids": (
                scene_script_audio_bars_execution["succeeded_layer_ids"]
            ),
            "scene_script_audio_bars_failed_layer_ids": (
                scene_script_audio_bars_execution["failed_layer_ids"]
            ),
            "loaded_solid_layers": solid_runtime["loaded"],
            "solid_candidates": solid_runtime["candidates"],
            "solid_loaded_ratio": round(solid_runtime["loaded_ratio"], 4),
            "solid_loaded_layer_ids": solid_runtime["loaded_layer_ids"],
            "puppet_animation_layer_ids": puppet_animation_runtime["layer_ids"],
            "puppet_disjoint_additive_layer_ids": (
                puppet_animation_runtime["disjoint_additive_layer_ids"]
            ),
            "puppet_animation_clip_count": puppet_animation_runtime["clip_count"],
            "puppet_animation_entries": puppet_animation_runtime["entries"],
            "utility_candidates": utility_runtime["candidates"],
            "utility_capture_planned": utility_runtime["capture_planned"],
            "utility_dependency_edges": utility_runtime["dependency_edges"],
            "utility_named_consumers": utility_runtime["named_consumers"],
            "utility_named_target_planned": utility_runtime["named_target_planned"],
            "utility_named_binding_planned": utility_runtime["named_binding_planned"],
            "utility_named_target_gaps": utility_runtime["named_target_gaps"],
            "utility_layers": utility_runtime["layers"],
            "utility_capture_succeeded_layer_ids": utility_capture_execution["succeeded_layer_ids"],
            "utility_capture_failed_layer_ids": utility_capture_execution["failed_layer_ids"],
            "authored_effect_graph_succeeded_layer_ids": authored_effect_graph_execution["succeeded_layer_ids"],
            "authored_effect_graph_failed_layer_ids": authored_effect_graph_execution["failed_layer_ids"],
            "authored_effect_graph_legacy_blur_blocked_layer_ids": authored_effect_graph_legacy_blur_blocked,
            "authored_effect_graph_local_contrast_count": authored_effect_graph_local_contrast,
            "authored_effect_graph_opacity_count": authored_effect_graph_opacity,
            "authored_effect_graph_color_key_count": authored_effect_graph_color_key,
            "authored_effect_graph_workshop_shift_hue_count": authored_effect_graph_workshop_shift_hue,
            "authored_effect_graph_workshop_audio_bars_count": authored_effect_graph_workshop_audio_bars,
            "authored_effect_graph_fisheye_zero_distortion_count": authored_effect_graph_fisheye_zero_distortion,
            "authored_effect_graph_workshop_gradient_count": authored_effect_graph_workshop_gradient,
            "authored_effect_graph_workshop_audio_hue_shift_count": authored_effect_graph_workshop_audio_hue_shift,
            "authored_effect_graph_opacity_layer_ids": authored_effect_graph_opacity_layers,
            "authored_effect_graph_workshop_shadow_count": authored_effect_graph_workshop_shadow,
            "authored_effect_graph_spin_count": authored_effect_graph_spin,
            "authored_effect_graph_procedural_noise_count": authored_effect_graph_procedural_noise,
            "authored_effect_graph_film_grain_count": authored_effect_graph_film_grain,
            "authored_effect_graph_light_shafts_count": authored_effect_graph_light_shafts,
            "authored_effect_graph_shake_count": authored_effect_graph_shake,
            "authored_effect_graph_water_flow_count": authored_effect_graph_water_flow,
            "authored_effect_graph_water_waves_count": authored_effect_graph_water_waves,
            "authored_effect_graph_foliage_sway_count": authored_effect_graph_foliage_sway,
            "authored_effect_graph_water_ripple_count": authored_effect_graph_water_ripple,
            "authored_effect_graph_depth_parallax_count": authored_effect_graph_depth_parallax,
            "authored_effect_graph_iris_inline_suffix_count": authored_effect_graph_iris_inline_suffix,
            "authored_effect_graph_cursor_ripple_count": authored_effect_graph_cursor_ripple,
            "authored_effect_graph_cursor_ripple_isolated_count": authored_effect_graph_cursor_ripple_isolated,
            "authored_effect_graph_cursor_ripple_omitted_effects": authored_effect_graph_cursor_ripple_omitted,
            "authored_effect_graph_shine_count": authored_effect_graph_shine,
            "authored_effect_graph_shine_isolated_count": authored_effect_graph_shine_isolated,
            "authored_effect_graph_shine_omitted_effects": authored_effect_graph_shine_omitted,
            "authored_effect_graph_clipping_mask_count": authored_effect_graph_clipping_mask,
            "authored_effect_graph_blend_count": authored_effect_graph_blend,
            "authored_effect_graph_tint_count": authored_effect_graph_tint,
            "authored_effect_graph_color_grading_count": authored_effect_graph_color_grading,
            "authored_effect_graph_pulse_count": authored_effect_graph_pulse,
            "authored_effect_graph_godrays_count": authored_effect_graph_godrays,
            "authored_effect_graph_transform_count": authored_effect_graph_transform,
            "authored_effect_graph_transform_static_fallback_count": authored_effect_graph_transform_static_fallback,
            "authored_effect_graph_transform_static_fallback_diagnostics": authored_effect_graph_transform_fallback_diagnostics,
            "authored_effect_graph_authored_shader_count": authored_effect_graph_authored_shader,
            "authored_effect_graph_scroll_count": authored_effect_graph_scroll,
            "authored_effect_graph_chain_count": authored_effect_graph_chain["chain_count"],
            "authored_effect_graph_stage_count": authored_effect_graph_chain["stage_count"],
            "named_target_capture_succeeded_layer_ids": named_target_capture_execution["succeeded_layer_ids"],
            "named_target_capture_failed_layer_ids": named_target_capture_execution["failed_layer_ids"],
            "named_target_binding_succeeded_layer_ids": named_target_binding_execution["succeeded_layer_ids"],
            "named_target_binding_failed_layer_ids": named_target_binding_execution["failed_layer_ids"],
            "image_blend_planned": image_blend_runtime["planned"],
            "image_blend_succeeded_layer_ids": image_blend_runtime["succeeded_layer_ids"],
            "image_blend_failed_layer_ids": image_blend_runtime["failed_layer_ids"],
            "loaded_particle_layers": particle_runtime["loaded"],
            "particle_candidates": particle_runtime["candidates"],
            "particle_loaded_ratio": round(particle_runtime["loaded_ratio"], 4),
            "particle_refract_loaded": particle_runtime["refract_loaded"],
            "particle_initial_live": particle_runtime["initial_live"],
            "particle_authored": particle_runtime["authored"],
            "particle_visible": particle_runtime["visible"],
            "particle_skipped_hidden": particle_runtime["skipped_hidden"],
            "particle_skipped_transparent": particle_runtime["skipped_transparent"],
            "particle_loaded_layer_ids": particle_runtime["loaded_layer_ids"],
            "camera_projection": camera_match.group("projection") if camera_match else None,
            "camera_parallax": camera_match.group("parallax") == "true" if camera_match else None,
            "camera_parallax_amount": float(camera_match.group("amount")) if camera_match else None,
            "camera_parallax_delay": (
                float(camera_match.group("delay"))
                if camera_match and camera_match.group("delay") is not None
                else None
            ),
            "camera_parallax_mouse_influence": float(camera_match.group("influence")) if camera_match else None,
            "offscreen_route_count": preview_text.count("offscreen skeleton"),
            "gaussian_blur_runtime_count": blur_runtime_count,
            "precise_blur_runtime_count": precise_blur_runtime_count,
            "skipped_unsupported_composite_count": skipped_composite_count,
            "perspective_opacity_runtime_count": perspective_opacity_count,
            "water_ripple_normal_runtime_count": water_ripple_normal_count,
            "water_ripple_normal_load_count": water_ripple_normal_load_count,
            "legacy_water_ripple_runtime_count": legacy_water_ripple_count,
            "legacy_waterwaves_runtime_count": legacy_waterwaves_count,
            "sprite_animation_count": sprite_animation_count,
            "color_blend_mode_9_count": color_blend_mode_9_count,
            "bloom_runtime_count": bloom_runtime_count,
            "route_only_effect_count": route_only_effect_count,
            "runtime_evidence": runtime_evidence,
        },
    }


def apply_runtime_retention(
    runtime_root: Path,
    app_identity: dict[str, Any],
    results: list[dict[str, Any]],
    keep_runtime: bool,
) -> None:
    if keep_runtime:
        return

    failed_results = [result for result in results if not result["passed"]]
    for result in results:
        if not result["passed"]:
            continue
        for key in ("runtime_sample", "runtime_home"):
            path = Path(result[key])
            try:
                path.resolve().relative_to(runtime_root.resolve())
            except ValueError as error:
                raise RuntimeError(f"Scene runtime cleanup path escapes runtime root: {path}") from error
            if path.exists():
                shutil.rmtree(path)
            result[key] = None
        result["runtime_retained"] = False

    if failed_results:
        for directory_name in ("runtime-samples", "runtime-homes"):
            directory = runtime_root / directory_name
            if directory.is_dir() and not any(directory.iterdir()):
                directory.rmdir()
        return

    discard_staged_app(app_identity)
    if runtime_root.is_dir():
        shutil.rmtree(runtime_root)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="signed MyWallpaperX executable")
    parser.add_argument("--sample-root", required=True, type=Path, help="isolated root containing Scene/<id>")
    parser.add_argument(
        "--matrix",
        type=Path,
        default=Path(__file__).with_name("scene_wallpaper_sample_matrix.json"),
    )
    parser.add_argument(
        "--sample-id",
        action="append",
        help="run only this ID from the selected matrix; may be repeated",
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--duration", type=float, default=7)
    parser.add_argument(
        "--keep-runtime",
        action="store_true",
        help="retain staged app, isolated samples, and temporary HOME after a passing run",
    )
    parser.add_argument(
        "--after-snapshot-delay",
        type=float,
        help="seconds after launch to capture the non-hover after frame",
    )
    parser.add_argument(
        "--audio-spectrum-fixture",
        action="store_true",
        help="publish a varying asymmetric 16-band fixture through the shared Scene inbox",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    duration = max(args.duration, 7)
    if args.after_snapshot_delay is not None and (
        not math.isfinite(args.after_snapshot_delay)
        or args.after_snapshot_delay <= 1
        or args.after_snapshot_delay >= duration
    ):
        print(
            "Scene benchmark precondition failed: after snapshot delay must be "
            "finite, greater than 1, and less than duration",
            file=sys.stderr,
        )
        return 2
    matrix_path = args.matrix.expanduser().resolve()
    try:
        matrix = select_matrix_samples(load_matrix(matrix_path), args.sample_id)
    except ValueError as error:
        print(f"Scene benchmark precondition failed: {error}", file=sys.stderr)
        return 2
    output_dir = require_fresh_output_dir(args.output_dir.expanduser().resolve())
    runtime_root = output_dir / "runtime"
    runtime_root.mkdir()
    try:
        runtime_binary, app_identity = stage_signed_app(args.app, runtime_root)
    except AppIdentityError as error:
        shutil.rmtree(runtime_root, ignore_errors=True)
        print(f"Scene benchmark precondition failed: {error}", file=sys.stderr)
        return 2

    results = [
        run_sample(
            runtime_binary=runtime_binary,
            sample_root=args.sample_root.expanduser().resolve(),
            sample=sample,
            output_dir=output_dir,
            runtime_root=runtime_root,
            duration=duration,
            after_snapshot_delay=args.after_snapshot_delay,
            audio_spectrum_fixture=args.audio_spectrum_fixture,
        )
        for sample in matrix["samples"]
    ]
    try:
        verify_staged_app(app_identity)
    except AppIdentityError as error:
        for result in results:
            result["failures"].append(f"staged app identity failure: {error}")
            result["passed"] = False

    passed = all(result["passed"] for result in results)
    apply_runtime_retention(
        runtime_root=runtime_root,
        app_identity=app_identity,
        results=results,
        keep_runtime=args.keep_runtime,
    )
    report = {
        "schema_version": 2,
        "matrix": matrix["name"],
        "matrix_path": str(matrix_path),
        "matrix_sha256": sha256(matrix_path),
        "command": sys.argv,
        "app_identity": app_identity,
        "sample_root": str(args.sample_root.expanduser().resolve()),
        "summary": {
            "passed": passed,
            "sample_count": len(results),
            "passed_count": sum(result["passed"] for result in results),
            "preview_visual": summarize_preview_visual_evidence(results),
            "performance": summarize_performance(results),
        },
        "samples": results,
    }
    report_path = output_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Scene benchmark {'PASS' if passed else 'FAIL'}: {report_path}")
    for result in results:
        print(
            f"{result['id']}: {'PASS' if result['passed'] else 'FAIL'} "
            f"loaded={result['runtime']['loaded_ratio']:.3f} failures={result['failures']}"
        )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

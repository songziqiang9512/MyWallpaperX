#!/usr/bin/env python3
"""Run isolated, signed-app Scene wallpaper evidence checks."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import math
import os
import re
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from scene_matrix_contract import (
    AUTHORED_EFFECT_RUNTIME_EXPECTATIONS, EFFECT_EXECUTION_EXACT_KINDS,
    EFFECT_EXECUTION_EXPECTATIONS, RESOLVED_MATERIAL_GRAPH_BACKEND,
    RESOLVED_MATERIAL_GRAPH_EXPECTATIONS, effect_execution_static_demand,
)
from scene_matrix_suite import load_scene_matrix
from scene_preview_visual_evidence import (
    collect_preview_visual_evidence, summarize_preview_visual_evidence,
)
from scene_product_entry_audio_baseline import (
    PRODUCT_ENTRY_AUDIO_MODE, classify_product_entry_result, load_audio_declaration_matrix,
    parse_product_entry_property_overrides, product_entry_command,
    summarize_product_entry_results,
)
from scene_puppet_interaction_evidence import collect_puppet_interaction_evidence
from scene_wallpaper_authored_effects import (
    AUTHORED_EFFECT_GRAPH_AUTHORED_SHADER_COUNT_RE, AUTHORED_EFFECT_GRAPH_BLEND_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_CLIPPING_MASK_COUNT_RE, AUTHORED_EFFECT_GRAPH_COLOR_KEY_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_CURSOR_RIPPLE_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_CURSOR_RIPPLE_ISOLATED_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_CURSOR_RIPPLE_OMITTED_EFFECTS_RE,
    AUTHORED_EFFECT_GRAPH_FILM_GRAIN_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_FISHEYE_ZERO_DISTORTION_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_FOLIAGE_SWAY_COUNT_RE, AUTHORED_EFFECT_GRAPH_GODRAYS_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_IRIS_INLINE_SUFFIX_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_LIGHT_SHAFTS_COUNT_RE, AUTHORED_EFFECT_GRAPH_OPACITY_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_OPACITY_LAYER_RE, AUTHORED_EFFECT_GRAPH_PROCEDURAL_NOISE_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_PULSE_COUNT_RE, AUTHORED_EFFECT_GRAPH_SCROLL_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_SHAKE_COUNT_RE, AUTHORED_EFFECT_GRAPH_TINT_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_TRANSFORM_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_TRANSFORM_STATIC_FALLBACK_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_TRANSFORM_STATIC_FALLBACK_DIAGNOSTICS_RE,
    AUTHORED_EFFECT_GRAPH_WATER_CAUSTICS_COUNT_RE, AUTHORED_EFFECT_GRAPH_WATER_FLOW_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_WATER_RIPPLE_COUNT_RE, AUTHORED_EFFECT_GRAPH_WATER_WAVES_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_WORKSHOP_AUDIO_BARS_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_WORKSHOP_AUDIO_HUE_SHIFT_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_WORKSHOP_GRADIENT_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_WORKSHOP_SHADOW_COUNT_RE,
    AUTHORED_EFFECT_GRAPH_WORKSHOP_SHIFT_HUE_COUNT_RE,
    authored_effect_graph_authored_shader_count, authored_effect_graph_blend_count,
    authored_effect_graph_clipping_mask_count, authored_effect_graph_color_key_count,
    authored_effect_graph_cursor_ripple_count,
    authored_effect_graph_cursor_ripple_isolated_count,
    authored_effect_graph_cursor_ripple_omitted_effects, authored_effect_graph_failures,
    authored_effect_graph_film_grain_count,
    authored_effect_graph_fisheye_zero_distortion_count,
    authored_effect_graph_foliage_sway_count, authored_effect_graph_godrays_count,
    authored_effect_graph_iris_inline_suffix_count, authored_effect_graph_light_shafts_count,
    authored_effect_graph_opacity_count, authored_effect_graph_opacity_layer_ids,
    authored_effect_graph_procedural_noise_count, authored_effect_graph_pulse_count,
    authored_effect_graph_scroll_count, authored_effect_graph_shake_count,
    authored_effect_graph_tint_count, authored_effect_graph_transform_count,
    authored_effect_graph_transform_static_fallback_count,
    authored_effect_graph_transform_static_fallback_diagnostics,
    authored_effect_graph_water_caustics_count, authored_effect_graph_water_flow_count,
    authored_effect_graph_water_ripple_count, authored_effect_graph_water_waves_count,
    authored_effect_graph_workshop_audio_bars_count,
    authored_effect_graph_workshop_audio_hue_shift_count,
    authored_effect_graph_workshop_gradient_count, authored_effect_graph_workshop_shadow_count,
    authored_effect_graph_workshop_shift_hue_count,
)
from scene_wallpaper_effect_disposition import (
    EFFECT_RUNTIME_DISPOSITION_ATTRIBUTION_COUNTS_RE,
    EFFECT_RUNTIME_DISPOSITION_CONSERVATION_RE, EFFECT_RUNTIME_DISPOSITION_COUNT_RE,
    EFFECT_RUNTIME_DISPOSITION_KIND_COUNTS_RE, EFFECT_RUNTIME_DISPOSITION_RE,
    EFFECT_RUNTIME_DISPOSITION_ROLE_COUNTS_RE, EFFECT_RUNTIME_DISPOSITION_SCHEMA_RE,
    EFFECT_RUNTIME_EVIDENCE_PREFIX_RE, EFFECT_RUNTIME_ROUTE_GROUP_COUNT_RE,
    EFFECT_RUNTIME_ROUTE_GROUP_KIND_COUNTS_RE, EFFECT_RUNTIME_ROUTE_GROUP_RE,
    EFFECT_RUNTIME_ROUTE_SCOPE_RE, effect_runtime_disposition_metrics,
)
from scene_wallpaper_effect_execution import (
    EFFECT_CPU_INVOCATION_RE, EFFECT_ROUTE_OPERATION_RE, SCENE_FRAME_COMMAND_BUFFER_RE,
    _effect_execution_identity_list, _effect_execution_payload,
    _effect_execution_static_catalog, _empty_effect_execution_metrics,
    effect_execution_failures, effect_execution_metrics,
)
from scene_wallpaper_effect_expectations import (
    ACTIVATION_PASSTHROUGH_PROGRAM_IDENTITIES, ACTIVATION_PASSTHROUGH_PROGRAM_REASONS,
    EFFECT_LOCAL_PASSTHROUGH_CPU_PREFIX, EFFECT_LOCAL_PASSTHROUGH_EXPECTATION_KEY,
    EFFECT_RECOVERY_EXPECTATION_KEY, TYPED_EFFECT_ACTIVATION_DECISION_RE,
    authored_deactivated_activation_identities, effect_local_passthrough_cpu_keys,
    effect_local_passthrough_expectation, effect_local_passthrough_graph_keys,
    effect_recovery_cpu_evidence, effect_recovery_expectation, graph_effect_subject_keys,
)
from scene_wallpaper_effect_preparation import (
    EFFECT_STAGE_ACTIVITY_COUNTS_RE, EFFECT_STAGE_ADMISSION_COUNTS_RE,
    EFFECT_STAGE_ADMISSION_RE, EFFECT_STAGE_COMPILER_FAILURE_CODES_RE,
    EFFECT_STAGE_COMPILER_PROBE_OUTCOMES_RE, EFFECT_STAGE_COMPILE_FAILURE_CODES_RE,
    EFFECT_STAGE_COMPILE_FAILURE_COUNT_RE, EFFECT_STAGE_CONSERVATION_RE,
    EFFECT_STAGE_COVERAGE_COUNTS_RE, EFFECT_STAGE_DESCRIPTOR_COUNT_RE,
    EFFECT_STAGE_PARSED_COUNT_RE, _stage_compile_count_map, _stage_count_map,
    authored_effect_stage_compile_metrics, effect_stage_admission_failures,
    effect_stage_admission_metrics,
)
from scene_wallpaper_graph_acceptance import resolved_material_graph_execution_failures
from scene_wallpaper_graph_execution import (
    DYNAMIC_LAYER_VISIBILITY_RE, RESOLVED_MATERIAL_GRAPH_EXECUTOR_RE,
    RESOLVED_MATERIAL_GRAPH_LOCAL_FALLBACK_RE, RESOLVED_MATERIAL_LAYER_CAPABILITY_RE,
    RESOLVED_MATERIAL_LAYER_ROUTE_V1_RE, RESOLVED_MATERIAL_LAYER_ROUTE_V2_RE,
    RESOLVED_MATERIAL_SCENE_BACKGROUND_RE, resolved_material_graph_execution_metrics,
)
from scene_wallpaper_graph_output_metrics import (
    named_graph_output_publication_execution_metrics,
    resolved_material_graph_observation_metrics, resolved_material_graph_output_metrics,
    visible_graph_output_publication_execution_metrics,
)
from scene_wallpaper_graph_subjects import (
    resolved_material_graph_exact_backend_metrics, resolved_material_graph_passthrough_metrics,
)
from scene_wallpaper_layer_runtime import (
    AUDIO_SCALED_VALUE_PROGRAM_RE, PARTICLE_AUTHORED_RE, PARTICLE_COMMITTED_NONEMPTY_RE,
    PARTICLE_CURRENT_NONEMPTY_RE, PARTICLE_DIAGNOSTIC_RE, PARTICLE_INITIAL_LIVE_RE,
    PARTICLE_LAYER_OK_RE, PARTICLE_LAYER_UNAVAILABLE_RE, PARTICLE_LOADED_RE,
    PARTICLE_REFRACT_LOADED_RE, PARTICLE_SKIPPED_HIDDEN_RE, PARTICLE_SKIPPED_TRANSPARENT_RE,
    PARTICLE_STICKY_LOADED_RE, PARTICLE_VISIBLE_RE, PUPPET_ANIMATION_OK_RE,
    SOLID_LAYER_COUNT_RE, SOLID_LAYER_OK_RE, audio_scaled_value_evidence_metrics,
    particle_runtime_failures, particle_runtime_metrics, puppet_animation_runtime_failures,
    puppet_animation_runtime_metrics, solid_runtime_failures, solid_runtime_metrics,
    startup_runtime_failures,
)
from scene_wallpaper_matrix_policy import (
    load_matrix, select_matrix_samples, validate_execution_observation_policy,
)
from scene_wallpaper_media_event import (
    append_media_properties_arguments, append_media_thumbnail_argument,
    append_media_timeline_arguments, media_color_transition_metrics,
    media_event_expectation_failures, media_owner_output_metrics,
    media_properties_owner_callback_metrics, media_properties_owner_expectation_failures,
    media_timeline_callback_metrics, media_timeline_expectation_failures,
    scene_script_vector_media_startup_metrics,
)
from scene_wallpaper_media_properties import (
    media_properties_callback_metrics, media_properties_expectation_failures,
)
from scene_wallpaper_performance import (
    FLOAT_PATTERN, PERFORMANCE_FLOAT_FIELDS, PERFORMANCE_FRAME_STAGES_LINE_RE,
    PERFORMANCE_GPU_CENSUS_FIELDS, PERFORMANCE_GPU_LINE_RE,
    PERFORMANCE_GPU_OFFSCREEN_CATEGORIES, PERFORMANCE_INT_FIELDS, PERFORMANCE_LINE_RE,
    PERFORMANCE_RESOURCES_LINE_RE, PERFORMANCE_RESOURCE_CPU_UNAVAILABLE_STATUSES,
    PERFORMANCE_RESOURCE_FLOAT_FIELDS, PERFORMANCE_RESOURCE_INT_FIELDS,
    PERFORMANCE_RESOURCE_STRING_FIELDS, PERFORMANCE_STAGES_LINE_RE, PERFORMANCE_STAGE_RE,
    _performance_stage_metrics, performance_failures, performance_frame_stage_metrics,
    performance_gpu_census_metrics, performance_metrics, performance_resource_metrics,
    performance_stage_metrics, summarize_performance,
)
from scene_wallpaper_pointer_evidence import (
    CURSOR_RIPPLE_STATE_RE, CURSOR_RIPPLE_VISIBLE_RE, _cursor_ripple_propagation_metrics,
    cursor_drag_to_normalized, cursor_interaction_output_failures, cursor_primary_click,
    cursor_primary_click_subframe, cursor_ripple_persistence_failures,
    cursor_ripple_persistence_metrics, cursor_ripple_visible_failures,
    cursor_ripple_visible_metrics, hover_pointer_from_launch, hover_pointer_normalized,
    hover_pointer_stationary_entry, pointer_trajectory_minimum_changed_ratio,
    pointer_trajectory_motion_metrics, pointer_trajectory_normalized,
)
from scene_wallpaper_property_updates import (
    DEFERRED_BASE_IMAGE_RE, DEFERRED_PROPERTY_TRANSITION_RE, LIVE_PROPERTY_UPDATE_RE,
    append_dynamic_values_fault_argument, append_media_thumbnail_sequence_argument,
    append_performance_profile_argument, append_performance_warmup_argument,
    append_property_arguments, append_resize_sequence_argument,
    append_texture_override_argument, deferred_property_transition_metrics,
    live_property_output_failures, live_property_update_failures, live_property_update_metrics,
)
from scene_wallpaper_runtime_metadata import (
    layer_graph_metrics, pass_metadata_metrics, runtime_evidence_metrics,
    shader_contract_metrics,
)
from scene_wallpaper_sample_lifecycle import (
    SAMPLE_ROOT_DERIVED_FILES, apply_runtime_retention, copy_sample,
    rebuildable_artifact_removal_metrics, remove_runtime_tree, run_product_entry_audio_sample,
    scene_package_path, sha256,
)
from scene_wallpaper_sample_run import (
    CAMERA_RE, CAMERA_SHAKE_RE, LOADED_RE, READY_RE, RUNTIME_EVIDENCE_RE, STOPPED_RE,
    TEXT_LAYER_OK_RE, TEXT_LOADED_RE, run_sample,
)
from scene_wallpaper_typed_publications import (
    MEDIA_THUMBNAIL_CLEAR_RE, MEDIA_THUMBNAIL_CURRENT_BINDING_COUNT_RE,
    MEDIA_THUMBNAIL_CURRENT_BINDING_LAYER_IDS_RE, MEDIA_THUMBNAIL_PENDING_RE,
    MEDIA_THUMBNAIL_PREVIOUS_BINDING_COUNT_RE, MEDIA_THUMBNAIL_PREVIOUS_BINDING_LAYER_IDS_RE,
    MEDIA_THUMBNAIL_READY_RE, SCENE_SCRIPT_AUDIO_SCALAR_PUBLICATION_RE,
    SCENE_SCRIPT_AUDIO_VECTOR_PUBLICATION_RE, SCENE_SCRIPT_EFFECT_VECTOR_COMPLETION_RE,
    SCENE_SCRIPT_OBJECT_SCALAR_COMPLETION_RE, SCENE_SCRIPT_SCALAR_BINDING_COUNT_RE,
    SCENE_SCRIPT_SCALAR_COMPLETION_RE, SCENE_SCRIPT_VEC3_COMPLETION_RE,
    TEXT_SCRIPT_BINDING_COUNT_RE, TEXT_SCRIPT_BINDING_RE, TEXT_SCRIPT_COMPLETION_RE,
    TEXT_SCRIPT_DIAGNOSTIC_COUNT_RE, TYPED_USER_PROPERTY_BOOL_ACTIVATION_PUBLICATION_RE,
    TYPED_USER_PROPERTY_SCALAR_SPLAT_UNIFORM_PUBLICATION_RE,
    TYPED_USER_PROPERTY_SCALAR_UNIFORM_PUBLICATION_RE, media_thumbnail_runtime_metrics,
    media_thumbnail_store_metrics, scene_script_scalar_runtime_metrics,
    text_script_runtime_metrics, typed_user_property_bool_activation_publications,
    typed_user_property_scalar_splat_uniform_publications,
    typed_user_property_scalar_uniform_publications,
)
from scene_wallpaper_utility_capture import (
    NAMED_TARGET_BINDING_EXECUTION_RE, NAMED_TARGET_CAPTURE_EXECUTION_RE,
    UTILITY_CAPTURE_COUNT_RE, UTILITY_CAPTURE_EXECUTION_RE, UTILITY_DEPENDENCY_COUNT_RE,
    UTILITY_LAYER_COUNT_RE, UTILITY_LAYER_RE, UTILITY_NAMED_BINDING_CONDITIONAL_IDS_RE,
    UTILITY_NAMED_BINDING_CONDITIONAL_RE, UTILITY_NAMED_BINDING_CONSUMER_IDS_RE,
    UTILITY_NAMED_BINDING_PLANNED_RE, UTILITY_NAMED_CONSUMER_COUNT_RE,
    UTILITY_NAMED_TARGET_GAP_RE, UTILITY_NAMED_TARGET_PLANNED_RE, capture_execution_metrics,
    named_target_binding_execution_metrics, named_target_binding_failures,
    named_target_capture_execution_metrics, utility_capture_execution_metrics,
    utility_runtime_failures, utility_runtime_metrics,
)
from typing import Any, Callable
from urllib.parse import unquote
from web_benchmark_capture import (
    AppIdentityError, discard_staged_app, png_flat_border_ratio, png_has_non_black_pixel,
    png_motion_metrics, require_fresh_output_dir, stage_signed_app, verify_staged_app,
)


def positive_uint64(raw: str) -> int:
    try:
        value = int(raw, 10)
    except ValueError as error:
        raise argparse.ArgumentTypeError("expected a positive UInt64") from error
    if value <= 0 or value > (1 << 64) - 1:
        raise argparse.ArgumentTypeError("expected a positive UInt64")
    return value

def bounded_duration(raw: str, minimum: float = 7) -> float:
    try:
        value = float(raw)
    except ValueError as error:
        raise argparse.ArgumentTypeError("expected a finite duration") from error
    if not math.isfinite(value) or value > 3_600:
        raise argparse.ArgumentTypeError(
            "expected a finite duration no greater than 3600 seconds"
        )
    return max(value, minimum)

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
        "--product-entry-audio-baseline",
        action="store_true",
        help=(
            "run the census audio relationship set through the isolated "
            "SteamWorkshopService product entry and stop at S3 publication"
        ),
    )
    parser.add_argument(
        "--audio-declaration-snapshot",
        type=Path,
        default=(Path(__file__).resolve().parents[1]
                 / ".artifacts/scene-evidence/census/scene_capability_census_snapshot.json"),
        help="local census cache that owns the audio relationship IDs; generate explicitly when absent",
    )
    parser.add_argument(
        "--product-entry-properties-json",
        help=(
            "typed string/number/bool startup overrides for one explicitly "
            "selected product-entry audio sample"
        ),
    )
    parser.add_argument(
        "--sample-id",
        action="append",
        help="run only this ID from the selected matrix; may be repeated",
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument(
        "--no-execution-observations",
        action="store_true",
        help=(
            "performance-only run: keep stage and resource telemetry but skip "
            "the execution observation instrument, so CPU figures describe "
            "product work; observation-derived evidence becomes unavailable"
        ),
    )
    parser.add_argument("--log-only", action="store_true",
                        help="collect runtime logs without PNG or visual qualification")
    parser.add_argument("--jobs", type=int, default=1,
                        help="bounded sample concurrency; multiple jobs require --log-only")
    parser.add_argument("--duration", type=lambda raw: bounded_duration(raw, 0))
    parser.add_argument(
        "--performance-fps",
        type=int,
        choices=(30, 60),
        default=60,
        help="explicit playback performance profile used by the Debug evidence runner",
    )
    parser.add_argument(
        "--performance-warmup",
        type=float,
        help=(
            "explicit seconds after ready before performance measurement; "
            "AS1 steady-state runs require 30"
        ),
    )
    parser.add_argument(
        "--keep-runtime",
        action="store_true",
        help=(
            "debug only: retain the staged app, isolated samples, and temporary "
            "HOME regardless of the run outcome"
        ),
    )
    parser.add_argument(
        "--after-snapshot-delay",
        type=float,
        help="seconds after launch to capture the non-hover after frame",
    )
    parser.add_argument(
        "--periodic-snapshot-interval",
        type=float,
        help="capture a continuous Scene series at this interval in seconds",
    )
    parser.add_argument(
        "--resize-sequence",
        help=(
            "DEBUG evidence-window resize events as delay:scale pairs, "
            "for example 1.5:0.6,3.5:1.0"
        ),
    )
    parser.add_argument(
        "--drop-dynamic-values-frame",
        type=positive_uint64,
        help=(
            "drop the complete dynamic snapshot at this frame in the isolated "
            "Debug evidence runner"
        ),
    )
    parser.add_argument(
        "--audio-spectrum-fixture",
        action="store_true",
        help="publish deterministic PCM through the product capture service, Scene analyzer and shared inbox",
    )
    parser.add_argument(
        "--audio-spectrum-silence-fixture",
        action="store_true",
        help="give the debug producer exclusive ownership and hold the Scene inbox at zero",
    )
    parser.add_argument(
        "--require-effect-stage-admission",
        action="store_true",
        help="fail selected samples when the structured effect-stage ledger is absent",
    )
    parser.add_argument(
        "--require-effect-execution",
        action="store_true",
        help=(
            "fail selected samples when the structured effect CPU, route, and "
            "shared frame execution evidence is absent"
        ),
    )
    parser.add_argument(
        "--require-graph-execution",
        action="store_true",
        help=(
            "fail selected samples unless an admitted R4 material graph is "
            "claimed and encoded on the GPU without executor failures"
        ),
    )
    parser.add_argument(
        "--require-cursor-ripple-persistence",
        action="store_true",
        help=(
            "fail selected samples unless a moving pointer injects a GPU ripple "
            "that expands and decays for at least three frames after exit"
        ),
    )
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be a positive integer")
    args.duration = max(args.duration if args.duration is not None else (4 if args.log_only else 7),
                        3 if args.log_only else 7)
    if args.jobs != 1 and not args.log_only:
        parser.error("parallel samples require --log-only; visual/performance runs stay serial")
    if args.log_only and (args.no_execution_observations or args.product_entry_audio_baseline):
        parser.error("log-only requires direct-host execution observations")
    if args.log_only and (args.periodic_snapshot_interval is not None
                          or args.require_cursor_ripple_persistence):
        parser.error("log-only cannot promise periodic images or visible cursor output")
    try:
        validate_execution_observation_policy(
            execution_observations_enabled=not args.no_execution_observations,
            require_effect_execution=args.require_effect_execution,
            require_graph_execution=args.require_graph_execution,
        )
    except ValueError as error:
        parser.error(str(error))
    return args

def main() -> int:
    args = parse_args()
    try:
        product_entry_property_overrides = (
            parse_product_entry_property_overrides(
                args.product_entry_properties_json
            )
        )
    except ValueError as error:
        print(f"Scene benchmark precondition failed: {error}", file=sys.stderr)
        return 2
    if args.product_entry_properties_json is not None and (
        not args.product_entry_audio_baseline
        or len(args.sample_id or []) != 1
    ):
        print(
            "Scene benchmark precondition failed: product-entry properties "
            "require product-entry audio mode and exactly one --sample-id",
            file=sys.stderr,
        )
        return 2
    product_entry_incompatible_options = any((
        args.no_execution_observations,
        args.performance_fps != 60,
        args.performance_warmup is not None,
        args.after_snapshot_delay is not None,
        args.periodic_snapshot_interval is not None,
        args.resize_sequence is not None,
        args.drop_dynamic_values_frame is not None,
        args.audio_spectrum_fixture,
        args.audio_spectrum_silence_fixture,
        args.require_effect_stage_admission,
        args.require_effect_execution,
        args.require_graph_execution,
        args.require_cursor_ripple_persistence,
    ))
    if args.product_entry_audio_baseline and product_entry_incompatible_options:
        print(
            "Scene benchmark precondition failed: product-entry audio baseline "
            "cannot use direct-host visual, fixture, performance, or execution "
            "options",
            file=sys.stderr,
        )
        return 2
    if args.audio_spectrum_fixture and args.audio_spectrum_silence_fixture:
        print(
            "Scene benchmark precondition failed: audio spectrum PCM and silence "
            "fixtures are mutually exclusive",
            file=sys.stderr,
        )
        return 2
    duration = args.duration
    if args.performance_warmup is not None and (
        not math.isfinite(args.performance_warmup)
        or args.performance_warmup < 0
        or args.performance_warmup > duration - 2.5
    ):
        print(
            "Scene benchmark precondition failed: performance warmup must be "
            "finite, nonnegative, and leave at least one measurement second",
            file=sys.stderr,
        )
        return 2
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
    if args.periodic_snapshot_interval is not None and (
        not math.isfinite(args.periodic_snapshot_interval)
        or args.periodic_snapshot_interval < 0.08
        or args.periodic_snapshot_interval > 10
    ):
        print(
            "Scene benchmark precondition failed: periodic snapshot interval must "
            "be finite and between 0.08 and 10 seconds",
            file=sys.stderr,
        )
        return 2
    matrix_path = (
        args.audio_declaration_snapshot.expanduser().resolve()
        if args.product_entry_audio_baseline
        else args.matrix.expanduser().resolve()
    )
    if args.product_entry_audio_baseline and not matrix_path.is_file():
        print(
            f"Scene benchmark precondition failed: census cache is missing: {matrix_path}; "
            "pass --audio-declaration-snapshot <existing-cache> or explicitly run "
            "python3.12 script/scene_capability_census.py generate with the matching "
            "--samples-root and --snapshot first",
            file=sys.stderr,
        )
        return 2
    try:
        unfiltered_matrix = (
            load_audio_declaration_matrix(matrix_path)
            if args.product_entry_audio_baseline
            else load_matrix(matrix_path)
        )
        matrix = select_matrix_samples(unfiltered_matrix, args.sample_id)
        for sample in matrix["samples"]:
            validate_execution_observation_policy(
                execution_observations_enabled=not args.no_execution_observations,
                require_effect_execution=args.require_effect_execution,
                require_graph_execution=args.require_graph_execution,
                sample=sample,
            )
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Scene benchmark precondition failed: {error}", file=sys.stderr)
        return 2
    output_dir = require_fresh_output_dir(args.output_dir.expanduser().resolve())
    runtime_root = output_dir / "runtime"
    runtime_root.mkdir()
    try:
        runtime_binary, app_identity = stage_signed_app(args.app, runtime_root)
    except AppIdentityError as error:
        try:
            remove_runtime_tree(runtime_root)
        except OSError as cleanup_error:
            print(
                f"Scene benchmark failed-stage cleanup failed: {cleanup_error}",
                file=sys.stderr,
            )
        print(f"Scene benchmark precondition failed: {error}", file=sys.stderr)
        return 2

    try:
        if args.product_entry_audio_baseline:
            results = []
            for index, sample in enumerate(matrix["samples"], start=1):
                sample_id = str(sample["id"])
                print(
                    f"Scene product-entry audio baseline "
                    f"[{index}/{len(matrix['samples'])}]: {sample_id}",
                    flush=True,
                )
                result = run_product_entry_audio_sample(
                    runtime_binary=runtime_binary,
                    sample_root=args.sample_root.expanduser().resolve(),
                    sample=sample,
                    output_dir=output_dir,
                    runtime_root=runtime_root,
                    duration=duration,
                    property_overrides=product_entry_property_overrides,
                )
                apply_runtime_retention(runtime_root, app_identity, [result], args.keep_runtime,
                                        finalize_stage=False)
                results.append(result)
                print(
                    f"{sample_id}: {result['baseline']['status']}",
                    flush=True,
                )
        else:
            def run_selected(sample: dict[str, Any]) -> dict[str, Any]:
                result = run_sample(
                    runtime_binary=runtime_binary,
                    sample_root=args.sample_root.expanduser().resolve(),
                    sample=sample, output_dir=output_dir, runtime_root=runtime_root,
                    duration=duration, performance_fps=args.performance_fps,
                    after_snapshot_delay=args.after_snapshot_delay,
                    performance_warmup=args.performance_warmup,
                    periodic_snapshot_interval=args.periodic_snapshot_interval,
                    resize_sequence=args.resize_sequence,
                    drop_dynamic_values_frame=args.drop_dynamic_values_frame,
                    audio_spectrum_fixture=args.audio_spectrum_fixture,
                    audio_spectrum_silence_fixture=args.audio_spectrum_silence_fixture,
                    require_effect_stage_admission=args.require_effect_stage_admission,
                    require_effect_execution=args.require_effect_execution,
                    require_graph_execution=args.require_graph_execution,
                    no_execution_observations=args.no_execution_observations,
                    require_cursor_ripple_persistence=args.require_cursor_ripple_persistence,
                    log_only=args.log_only,
                )
                apply_runtime_retention(runtime_root, app_identity, [result], args.keep_runtime,
                                        finalize_stage=False)
                return result

            if args.jobs == 1:
                results = [run_selected(sample) for sample in matrix["samples"]]
            else:
                # The executor joins running workers before the outer cleanup
                # can remove their shared, read-only staged App.
                with ThreadPoolExecutor(max_workers=args.jobs) as pool:
                    futures = {}
                    try:
                        for index, sample in enumerate(matrix["samples"]):
                            futures[pool.submit(run_selected, sample)] = index
                        results = [None] * len(futures)
                        for future in as_completed(futures):
                            results[futures[future]] = future.result()
                    except BaseException:
                        for future in futures:
                            future.cancel()
                        raise

    except (Exception, KeyboardInterrupt):
        if not args.keep_runtime:
            try:
                remove_runtime_tree(runtime_root)
            except OSError as cleanup_error:
                print(
                    f"Scene benchmark interrupted-runtime cleanup failed: {cleanup_error}",
                    file=sys.stderr,
                )
        raise
    try:
        verify_staged_app(app_identity)
    except AppIdentityError as error:
        for result in results:
            failure = f"staged app identity failure: {error}"
            result["failures"].append(failure)
            result["passed"] = False
            if args.product_entry_audio_baseline:
                result["baseline"]["failures"].append(failure)
                result["baseline"]["passed"] = False
                result["baseline"]["status"] = "staged-app-identity-failure"

    summary = (
        summarize_product_entry_results(results)
        if args.product_entry_audio_baseline
        else {
            "passed": all(result["passed"] for result in results),
            "sample_count": len(results),
            "passed_count": sum(result["passed"] for result in results),
            "preview_visual": ({"status": "not-requested"} if args.log_only
                               else summarize_preview_visual_evidence(results)),
            "performance": ({"status": "diagnostic-only", "comparison_eligible": False}
                            if args.log_only else summarize_performance(results)),
        }
    )
    passed = bool(summary["passed"])
    apply_runtime_retention(
        runtime_root=runtime_root,
        app_identity=app_identity,
        results=results,
        keep_runtime=args.keep_runtime,
    )
    report = {
        "schema_version": 2,
        "mode": (
            PRODUCT_ENTRY_AUDIO_MODE
            if args.product_entry_audio_baseline
            else "direct-host-scene-log-audit" if args.log_only else "direct-host-scene-benchmark"
        ),
        "matrix": matrix["name"],
        "matrix_path": str(matrix_path),
        "matrix_sha256": sha256(matrix_path),
        "matrix_source": matrix.get("source"),
        "command": sys.argv,
        "app_identity": app_identity,
        "sample_root": str(args.sample_root.expanduser().resolve()),
        "summary": summary,
        "samples": results,
    }
    if args.log_only:
        report.update(jobs=args.jobs, claim_boundary="runtime-diagnostics-only-not-visual-or-performance")
    if args.product_entry_audio_baseline:
        report["product_entry_property_overrides"] = (
            product_entry_property_overrides
        )
    report_path = output_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Scene benchmark {'PASS' if passed else 'FAIL'}: {report_path}")
    if not args.product_entry_audio_baseline:
        for result in results:
            print(
                f"{result['id']}: {'PASS' if result['passed'] else 'FAIL'} "
                f"loaded={result['runtime'].get('loaded_ratio', 0):.3f} "
                f"failures={result['failures']}"
            )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

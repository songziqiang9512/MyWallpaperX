"""Execute one isolated Scene run and collect its existing result schema."""

from __future__ import annotations

import json
import math
import os
import re
import subprocess
from pathlib import Path
from scene_preview_visual_evidence import collect_sample_visual_evidence
from scene_wallpaper_authored_effects import (
    authored_effect_graph_authored_shader_count, authored_effect_graph_blend_count,
    authored_effect_graph_clipping_mask_count, authored_effect_graph_color_key_count,
    authored_effect_graph_cursor_ripple_count,
    authored_effect_graph_cursor_ripple_isolated_count,
    authored_effect_graph_cursor_ripple_omitted_effects,
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
from scene_wallpaper_effect_disposition import effect_runtime_disposition_metrics
from scene_wallpaper_effect_execution import effect_execution_metrics
from scene_wallpaper_effect_preparation import (
    authored_effect_stage_compile_metrics, effect_stage_admission_metrics,
)
from scene_wallpaper_graph_execution import resolved_material_graph_execution_metrics
from scene_wallpaper_graph_output_metrics import (
    named_graph_output_publication_execution_metrics,
    visible_graph_output_publication_execution_metrics,
)
from scene_wallpaper_layer_runtime import (
    audio_scaled_value_evidence_metrics, particle_runtime_metrics,
    puppet_animation_runtime_metrics, solid_runtime_metrics,
)
from scene_wallpaper_matrix_policy import validate_execution_observation_policy
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
from scene_wallpaper_performance import FLOAT_PATTERN, performance_metrics
from scene_wallpaper_pointer_evidence import (
    cursor_drag_to_normalized, cursor_primary_click, cursor_primary_click_subframe,
    cursor_ripple_persistence_metrics, cursor_ripple_visible_metrics,
    hover_pointer_from_launch, hover_pointer_normalized, hover_pointer_stationary_entry,
    pointer_trajectory_normalized,
)
from scene_wallpaper_property_updates import (
    append_dynamic_values_fault_argument, append_media_thumbnail_sequence_argument,
    append_performance_profile_argument, append_performance_warmup_argument,
    append_property_arguments, append_resize_sequence_argument,
    append_texture_override_argument, deferred_property_transition_metrics,
    live_property_update_metrics,
)
from scene_wallpaper_runtime_metadata import runtime_evidence_metrics
from scene_wallpaper_sample_acceptance import sample_result_failures
from scene_wallpaper_sample_lifecycle import (
    SAMPLE_ROOT_DERIVED_FILES, copy_sample, scene_package_path, sha256,
)
from scene_sample_snapshot import tree_manifest
from scene_wallpaper_typed_publications import (
    media_thumbnail_runtime_metrics, media_thumbnail_store_metrics,
    scene_script_scalar_runtime_metrics, text_script_runtime_metrics,
    typed_user_property_bool_activation_publications,
    typed_user_property_scalar_splat_uniform_publications,
    typed_user_property_scalar_uniform_publications,
)
from scene_wallpaper_utility_capture import (
    named_target_binding_execution_metrics, named_target_capture_execution_metrics,
    utility_capture_execution_metrics, utility_runtime_metrics,
)
from typing import Any


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

LOADED_RE = re.compile(r"^loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)

TEXT_LOADED_RE = re.compile(r"^text loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)

TEXT_LAYER_OK_RE = re.compile(r'^text layer (?P<id>\d+) .*: OK ', re.MULTILINE)

CAMERA_RE = re.compile(
    r"^camera: projection=(?P<projection>\S+) parallax=(?P<parallax>true|false) "
    rf"amount=(?P<amount>{FLOAT_PATTERN}) (?:delay=(?P<delay>{FLOAT_PATTERN}) )?"
    rf"mouseInfluence=(?P<influence>{FLOAT_PATTERN})$",
    re.MULTILINE,
)

CAMERA_SHAKE_RE = re.compile(
    r"^camera shake: status=(?P<status>disabled|executable|invalid) "
    r"enabled=(?P<enabled>true|false|invalid) "
    rf"amplitude=(?P<amplitude>(?:{FLOAT_PATTERN}|invalid)) "
    rf"roughness=(?P<roughness>(?:{FLOAT_PATTERN}|invalid)) "
    rf"speed=(?P<speed>(?:{FLOAT_PATTERN}|invalid))$",
    re.MULTILINE,
)

def run_sample(
    runtime_binary: Path,
    sample_root: Path,
    sample: dict[str, Any],
    output_dir: Path,
    runtime_root: Path,
    duration: float,
    performance_fps: int,
    after_snapshot_delay: float | None,
    performance_warmup: float | None = None,
    periodic_snapshot_interval: float | None = None,
    resize_sequence: str | None = None,
    drop_dynamic_values_frame: int | None = None,
    audio_spectrum_fixture: bool = False,
    audio_spectrum_silence_fixture: bool = False,
    require_effect_stage_admission: bool = False,
    require_effect_execution: bool = False,
    require_graph_execution: bool = False,
    require_cursor_ripple_persistence: bool = False,
    no_execution_observations: bool = False,
    startup_timeout_allowance: float = 60,
    log_only: bool = False,
) -> dict[str, Any]:
    # Playback duration starts after preparation; cold shader/resource work
    # needs its own bounded allowance in the supervising process.
    if not math.isfinite(startup_timeout_allowance) or startup_timeout_allowance <= 0:
        raise ValueError("startup_timeout_allowance must be finite and positive")
    if log_only and no_execution_observations:
        raise ValueError("log-only runs require execution observations")
    execution_observations_enabled = not no_execution_observations
    validate_execution_observation_policy(
        execution_observations_enabled=execution_observations_enabled,
        require_effect_execution=require_effect_execution,
        require_graph_execution=require_graph_execution,
        sample=sample,
    )
    sample_id = str(sample["id"])
    source = sample_root / "Scene" / sample_id
    result_dir = output_dir / "results" / sample_id
    runtime_sample = runtime_root / "runtime-samples" / sample_id
    runtime_home = runtime_root / "runtime-homes" / sample_id
    result_dir.mkdir(parents=True)
    if not (source / "project.json").is_file():
        return {
            "id": sample_id, "title": sample.get("title"), "passed": False,
            "input_status": "source-invalid", "failures": ["Scene sample project.json is missing"],
            "exit_code": None, "timed_out": False, "hashes": {},
            "runtime_sample": None, "runtime_home": None, "runtime_retained": False,
            "evidence": {"visual_status": "not-requested"}, "runtime": {},
        }
    runtime_home.mkdir(parents=True)
    runtime_tmp = runtime_home / "tmp"
    runtime_tmp.mkdir(mode=0o700)
    copy_sample(source, runtime_sample)
    package_path = scene_package_path(source)

    hashes = {
        "project_sha256": sha256(source / "project.json"),
        "package_sha256": sha256(package_path) if package_path is not None else None,
    }
    if package_path is None:
        hashes["tree_sha256"] = tree_manifest(source)[0]
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
    if log_only:
        command.append("--mwx-debug-scene-log-only")
    append_performance_profile_argument(command, performance_fps)
    append_performance_warmup_argument(command, performance_warmup)
    if no_execution_observations:
        # Performance-only run: the staged app still emits the per-call and
        # per-frame stage telemetry and the 1 Hz resource samples, but skips the
        # execution observation instrument, so the CPU figures describe product
        # work. Observation-derived evidence fields are then absent by design.
        command.append("--mwx-debug-scene-no-execution-observations")
    if after_snapshot_delay is not None:
        command.extend([
            "--mwx-debug-scene-after-snapshot-delay",
            str(after_snapshot_delay),
        ])
    if periodic_snapshot_interval is not None:
        command.extend([
            "--mwx-debug-scene-periodic-snapshot-interval",
            str(periodic_snapshot_interval),
        ])
    append_resize_sequence_argument(command, resize_sequence)
    append_dynamic_values_fault_argument(command, drop_dynamic_values_frame)
    sample_audio_fixture = sample.get("audio_spectrum_fixture") is True
    sample_silence_fixture = sample.get("audio_spectrum_silence_fixture") is True
    if (audio_spectrum_fixture or sample_audio_fixture) and (
        audio_spectrum_silence_fixture or sample_silence_fixture
    ):
        failures.append("audio spectrum PCM and silence fixtures are mutually exclusive")
    elif audio_spectrum_fixture or sample_audio_fixture:
        command.append("--mwx-debug-scene-audio-spectrum-fixture")
    elif audio_spectrum_silence_fixture or sample_silence_fixture:
        command.append("--mwx-debug-scene-audio-silence-fixture")
    property_overrides = sample.get("property_overrides")
    live_property_overrides = sample.get("live_property_overrides")
    append_property_arguments(command, property_overrides, live_property_overrides)
    texture_overrides = sample.get("texture_overrides")
    append_texture_override_argument(
        command, texture_overrides, runtime_sample, failures
    )
    append_media_properties_arguments(
        command,
        sample.get("media_title"),
        sample.get("media_artist"),
        failures,
        sub_title=sample.get("media_sub_title"),
        album_title=sample.get("media_album_title"),
        album_artist=sample.get("media_album_artist"),
        genres=sample.get("media_genres"),
        content_type=sample.get("media_content_type"),
    )
    append_media_timeline_arguments(
        command,
        sample.get("media_timeline_position"),
        sample.get("media_timeline_duration"),
        failures,
    )
    append_media_thumbnail_argument(
        command,
        sample.get("media_thumbnail_path"),
        runtime_sample,
        failures,
        primary_color=sample.get("media_thumbnail_primary_color"),
        secondary_color=sample.get("media_thumbnail_secondary_color"),
        tertiary_color=sample.get("media_thumbnail_tertiary_color"),
        text_color=sample.get("media_thumbnail_text_color"),
        high_contrast_color=sample.get("media_thumbnail_high_contrast_color"),
        playback_state=sample.get("media_playback_state"),
    )
    append_media_thumbnail_sequence_argument(
        command,
        sample.get("media_thumbnail_sequence"),
        runtime_sample,
        failures,
    )
    pointer_trajectory = pointer_trajectory_normalized(sample)
    hover_pointer = hover_pointer_normalized(sample)
    if pointer_trajectory is not None:
        hover_pointer = pointer_trajectory[0]
    hover_pointer_stationary = hover_pointer_stationary_entry(sample)
    from_launch_hover = hover_pointer_from_launch(sample)
    if from_launch_hover and hover_pointer is None:
        raise ValueError("hover_pointer_from_launch requires hover_pointer_normalized")
    primary_click = cursor_primary_click(sample)
    subframe_click = cursor_primary_click_subframe(sample)
    drag_pointer = cursor_drag_to_normalized(sample)
    if sample.get("cursor_drag_response") in {"spring-return", "no-capture"} and (
        drag_pointer is None or hover_pointer is None
    ):
        raise ValueError("Puppet interaction needs an explicit press and drag position")
    if hover_pointer is not None:
        command.extend([
            "--mwx-debug-scene-hover-pointer-json",
            json.dumps(
                {"x": hover_pointer[0], "y": hover_pointer[1]},
                separators=(",", ":"),
            ),
        ])
        if hover_pointer_stationary:
            command.append("--mwx-debug-scene-hover-pointer-stationary-entry")
        if from_launch_hover:
            command.append("--mwx-debug-scene-hover-pointer-from-launch")
        if primary_click:
            command.append("--mwx-debug-scene-primary-click")
            if subframe_click:
                command.append("--mwx-debug-scene-primary-click-subframe")
        if drag_pointer is not None:
            command.extend([
                "--mwx-debug-scene-cursor-drag-to-json",
                json.dumps(
                    {"x": drag_pointer[0], "y": drag_pointer[1]},
                    separators=(",", ":"),
                ),
            ])
        if pointer_trajectory is not None:
            command.extend([
                "--mwx-debug-scene-pointer-trajectory-json",
                json.dumps(pointer_trajectory, separators=(",", ":")),
            ])
    environment = os.environ.copy()
    environment["HOME"] = str(runtime_home)
    environment["CFFIXED_USER_HOME"] = str(runtime_home)
    environment["TMPDIR"] = str(runtime_tmp) + "/"
    if "cursor_start_second" in sample:
        second = float(sample["cursor_start_second"])
        if not math.isfinite(second) or not 0 <= second < 60:
            raise ValueError("cursor_start_second must be in [0, 60)")
        environment["MYWALLPAPERX_SCENE_DEBUG_POINTER_SECOND"] = str(second)
    if sample.get("cursor_drag_response") in {"spring-return", "no-capture"}:
        layers = sample.get("puppet_interaction_layer_ids", [])
        if not layers or any(type(layer) is not int for layer in layers):
            raise ValueError("Puppet interaction requires explicit integer layer IDs")
        environment["MYWALLPAPERX_SCENE_DEBUG_PUPPET_BONE_EVIDENCE"] = ",".join(map(str, layers))
    if require_cursor_ripple_persistence:
        environment["MYWALLPAPERX_SCENE_DEBUG_CURSOR_RIPPLE_EVIDENCE"] = "1"
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
            exit_code = process.wait(timeout=duration + startup_timeout_allowance)
        except BaseException as error:
            timed_out = isinstance(error, subprocess.TimeoutExpired)
            process.terminate()
            try:
                exit_code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                exit_code = process.wait(timeout=5)
            if not timed_out:
                raise

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
    deferred_property_transition = deferred_property_transition_metrics(
        log_text
    )
    cursor_ripple_persistence = cursor_ripple_persistence_metrics(log_text)
    cursor_ripple_visible = cursor_ripple_visible_metrics(log_text)
    loaded_match = LOADED_RE.search(preview_text)
    loaded = int(loaded_match.group("loaded")) if loaded_match else 0
    total = int(loaded_match.group("total")) if loaded_match else 0
    loaded_ratio = loaded / total if total else 0.0
    text_loaded_match = TEXT_LOADED_RE.search(preview_text)
    text_loaded = int(text_loaded_match.group("loaded")) if text_loaded_match else 0
    text_total = int(text_loaded_match.group("total")) if text_loaded_match else 0
    text_loaded_layer_ids = [int(match.group("id")) for match in TEXT_LAYER_OK_RE.finditer(preview_text)]
    text_script_runtime = text_script_runtime_metrics(preview_text, log_text)
    scene_script_scalar_runtime = scene_script_scalar_runtime_metrics(
        preview_text,
        log_text,
    )
    media_color_completions = media_color_transition_metrics(log_text)
    scene_script_vector_media_startup = (
        scene_script_vector_media_startup_metrics(preview_text)
    )
    media_owner_outputs = media_owner_output_metrics(
        scene_script_scalar_runtime["effect_vector_completions"]
            + scene_script_scalar_runtime["vec3_completions"],
        scene_script_vector_media_startup,
    )
    failures.extend(
        media_event_expectation_failures(
            sample,
            media_color_completions,
            scene_script_vector_media_startup,
            media_owner_outputs,
        )
    )
    media_properties_callbacks = media_properties_callback_metrics(log_text)
    failures.extend(media_properties_expectation_failures(
        sample, media_properties_callbacks
    ))
    media_timeline_callbacks = media_timeline_callback_metrics(log_text)
    failures.extend(media_timeline_expectation_failures(
        sample, media_timeline_callbacks
    ))
    media_properties_owner_callbacks = media_properties_owner_callback_metrics(
        log_text
    )
    failures.extend(media_properties_owner_expectation_failures(
        sample, media_properties_owner_callbacks
    ))
    user_property_scalar_uniform_publications = (
        typed_user_property_scalar_uniform_publications(log_text)
    )
    user_property_scalar_splat_uniform_publications = (
        typed_user_property_scalar_splat_uniform_publications(log_text)
    )
    user_property_bool_activation_publications = (
        typed_user_property_bool_activation_publications(log_text)
    )
    media_thumbnail_runtime = media_thumbnail_runtime_metrics(preview_text)
    media_thumbnail_store = media_thumbnail_store_metrics(log_text)
    solid_runtime = solid_runtime_metrics(preview_text)
    puppet_animation_runtime = puppet_animation_runtime_metrics(preview_text)
    utility_runtime = utility_runtime_metrics(preview_text)
    utility_capture_execution = utility_capture_execution_metrics(log_text)
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
    authored_effect_graph_water_caustics = authored_effect_graph_water_caustics_count(
        preview_text
    )
    authored_effect_graph_foliage_sway = authored_effect_graph_foliage_sway_count(
        preview_text
    )
    authored_effect_graph_water_ripple = authored_effect_graph_water_ripple_count(
        preview_text
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
    authored_effect_graph_clipping_mask = authored_effect_graph_clipping_mask_count(
        preview_text
    )
    authored_effect_graph_blend = authored_effect_graph_blend_count(preview_text)
    authored_effect_graph_tint = authored_effect_graph_tint_count(preview_text)
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
    effect_stage_admission = effect_stage_admission_metrics(
        preview_text
    )
    authored_effect_stage_compile = authored_effect_stage_compile_metrics(
        preview_text
    )
    effect_runtime_disposition = effect_runtime_disposition_metrics(
        preview_text,
        effect_stage_admission,
    )
    effect_execution = effect_execution_metrics(
        log_text,
        effect_runtime_disposition,
    )
    visible_graph_output_publication_execution = (
        visible_graph_output_publication_execution_metrics(log_text)
    )
    named_graph_output_publication_execution = (
        named_graph_output_publication_execution_metrics(log_text)
    )
    resolved_material_graph_execution = (
        resolved_material_graph_execution_metrics(
            preview_text,
            log_text,
            effect_execution=effect_execution,
            static_disposition=effect_runtime_disposition,
            visible_graph_output_publication=(
                visible_graph_output_publication_execution
            ),
            named_graph_output_publication=(
                named_graph_output_publication_execution
            ),
            execution_observations_enabled=execution_observations_enabled,
        )
    )
    named_target_capture_execution = named_target_capture_execution_metrics(log_text)
    named_target_binding_execution = named_target_binding_execution_metrics(log_text)
    particle_runtime = particle_runtime_metrics(preview_text)
    audio_scaled_value_evidence_path = (
        result_dir / "scene-audio-scaled-value-evidence.json"
    )
    audio_scaled_value = audio_scaled_value_evidence_metrics(
        preview_text,
        audio_scaled_value_evidence_path,
    )
    camera_match = CAMERA_RE.search(preview_text)
    camera_shake_match = CAMERA_SHAKE_RE.search(preview_text)
    visual = {"visual_status": "not-requested"} if log_only else collect_sample_visual_evidence(
        runtime_sample, result_dir, sample=sample, hover_pointer=hover_pointer,
        pointer_trajectory=pointer_trajectory, log_text=log_text,
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

    # Counts belong to the collected report; acceptance consumes these values.
    blur_runtime_count = preview_text.count("effect runtime gaussian-blur;")
    precise_blur_runtime_count = preview_text.count("effect runtime gaussian-blur-precise;")
    authored_opacity_runtime_count = preview_text.count("effect runtime opacity-authored;")
    skipped_composite_count = preview_text.count("unsupported composite skipped;")
    perspective_opacity_count = preview_text.count("effect runtime perspective-opacity;")
    water_ripple_normal_count = preview_text.count("effect runtime waterripple-normal;")
    water_ripple_normal_load_count = preview_text.count("waterripple normal OK")
    legacy_water_ripple_count = preview_text.count("effect runtime waterripple-legacy;")
    sprite_animation_count = preview_text.count("; sprite animation frames=")
    color_blend_mode_9_count = preview_text.count("layer color blend mode=9")
    bloom_runtime_count = preview_text.count("effect runtime bloom")
    result = {
        "id": sample_id,
        "title": sample.get("title"),
        "capabilities": sample.get("capabilities", []),
        "audio_spectrum_fixture": audio_spectrum_fixture
            or sample.get("audio_spectrum_fixture") is True,
        "audio_spectrum_silence_fixture": audio_spectrum_silence_fixture
            or sample.get("audio_spectrum_silence_fixture") is True,
        "drop_dynamic_values_frame": drop_dynamic_values_frame,
        "property_overrides": property_overrides if isinstance(property_overrides, dict) else {},
        "live_property_overrides": (
            live_property_overrides if isinstance(live_property_overrides, dict) else {}
        ),
        "texture_overrides": (
            texture_overrides if isinstance(texture_overrides, dict) else {}
        ),
        "passed": not failures,
        "failures": failures,
        "particle_unavailable_layer_ids": particle_runtime["unavailable_layer_ids"],
        "particle_diagnostics": particle_runtime["particle_diagnostics"],
        "exit_code": exit_code,
        "timed_out": timed_out,
        "hashes": hashes,
        "package_file": package_path.name if package_path is not None else None,
        "runtime_sample": str(runtime_sample),
        "runtime_home": str(runtime_home),
        "runtime_retained": True,
        "evidence": {
            "app_log": str(app_log),
            "preview_log": str(preview_log),
            "runtime_evidence": str(runtime_evidence_path),
            "audio_scaled_value_evidence": (
                str(audio_scaled_value_evidence_path)
                if audio_scaled_value["has_evidence"] else None
            ),
            "sample_root_residue": sample_root_residue,
            **visual,
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
            "hover_pointer_stationary_entry": hover_pointer_stationary,
            "hover_pointer_from_launch": from_launch_hover,
            "cursor_primary_click": primary_click,
            "cursor_primary_click_subframe": subframe_click,
            "cursor_drag_to_normalized": (
                list(drag_pointer) if drag_pointer is not None else None
            ),
            "pointer_trajectory_normalized": (
                [list(point) for point in pointer_trajectory]
                if pointer_trajectory is not None else None
            ),
            "cursor_ripple_persistence": cursor_ripple_persistence,
            "cursor_ripple_visible": cursor_ripple_visible,
            "live_property_update": live_property_update,
            "deferred_property_transition": deferred_property_transition,
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
            "scene_script_scalar_binding_count": (
                scene_script_scalar_runtime["binding_count"]
            ),
            "scene_script_scalar_target_count": (
                scene_script_scalar_runtime["target_count"]
            ),
            "scene_script_scalar_route": scene_script_scalar_runtime["route"],
            "scene_script_scalar_fallback": scene_script_scalar_runtime["fallback"],
            "scene_script_scalar_bindings": (
                scene_script_scalar_runtime["bindings"]
            ),
            "scene_script_scalar_completions": (
                scene_script_scalar_runtime["completions"]
            ),
            "scene_script_object_scalar_completions": (
                scene_script_scalar_runtime["object_scalar_completions"]
            ),
            "scene_script_audio_scalar_publications": (
                scene_script_scalar_runtime["audio_scalar_publications"]
            ),
            "typed_user_property_scalar_uniform_publications": (
                user_property_scalar_uniform_publications
            ),
            "typed_user_property_scalar_splat_uniform_publications": (
                user_property_scalar_splat_uniform_publications
            ),
            "typed_user_property_bool_activation_publications": (
                user_property_bool_activation_publications
            ),
            "scene_script_vec3_binding_count": (
                scene_script_scalar_runtime["vector_binding_count"]
            ),
            "scene_script_vector_binding_count": (
                scene_script_scalar_runtime["vector_binding_count"]
            ),
            "scene_script_vec3_completions": (
                scene_script_scalar_runtime["vec3_completions"]
            ),
            "scene_script_effect_vector_completions": (
                scene_script_scalar_runtime["effect_vector_completions"]
            ),
            "scene_script_audio_vector_publications": (
                scene_script_scalar_runtime["audio_vector_publications"]
            ),
            "media_color_completions": media_color_completions,
            "media_owner_outputs": media_owner_outputs,
            "media_properties_callbacks": media_properties_callbacks,
            "media_timeline_callbacks": media_timeline_callbacks,
            "media_properties_owner_callbacks": media_properties_owner_callbacks,
            "scene_script_vector_media_startup": (
                scene_script_vector_media_startup
            ),
            "media_thumbnail_current_binding_count": (
                media_thumbnail_runtime["current_binding_count"]
            ),
            "media_thumbnail_current_binding_layer_ids": (
                media_thumbnail_runtime["current_binding_layer_ids"]
            ),
            "media_thumbnail_previous_binding_count": (
                media_thumbnail_runtime["previous_binding_count"]
            ),
            "media_thumbnail_previous_binding_layer_ids": (
                media_thumbnail_runtime["previous_binding_layer_ids"]
            ),
            "media_thumbnail_pending_last_ready": (
                media_thumbnail_store["pending_last_ready"]
            ),
            "media_thumbnail_ready_states": media_thumbnail_store["ready_states"],
            "media_thumbnail_clear_count": media_thumbnail_store["clear_count"],
            "loaded_solid_layers": solid_runtime["loaded"],
            "solid_candidates": solid_runtime["candidates"],
            "solid_loaded_ratio": round(solid_runtime["loaded_ratio"], 4),
            "solid_loaded_layer_ids": solid_runtime["loaded_layer_ids"],
            "puppet_animation_layer_ids": puppet_animation_runtime["layer_ids"],
            "puppet_layered_layer_ids": (
                puppet_animation_runtime["layered_layer_ids"]
            ),
            "puppet_animation_clip_count": puppet_animation_runtime["clip_count"],
            "puppet_animation_entries": puppet_animation_runtime["entries"],
            "utility_candidates": utility_runtime["candidates"],
            "utility_capture_planned": utility_runtime["capture_planned"],
            "utility_dependency_edges": utility_runtime["dependency_edges"],
            "utility_named_consumers": utility_runtime["named_consumers"],
            "utility_named_target_planned": utility_runtime["named_target_planned"],
            "utility_named_binding_planned": utility_runtime["named_binding_planned"],
            "utility_named_binding_conditional": utility_runtime[
                "named_binding_conditional"
            ],
            "utility_named_binding_conditional_layer_ids": utility_runtime[
                "named_binding_conditional_layer_ids"
            ],
            "utility_named_binding_consumer_layer_ids": utility_runtime[
                "named_binding_consumer_layer_ids"
            ],
            "utility_named_target_gaps": utility_runtime["named_target_gaps"],
            "utility_layers": utility_runtime["layers"],
            "utility_capture_succeeded_layer_ids": utility_capture_execution["succeeded_layer_ids"],
            "utility_capture_failed_layer_ids": utility_capture_execution["failed_layer_ids"],
            "authored_effect_graph_opacity_count": authored_effect_graph_opacity,
            "authored_effect_graph_color_key_count": authored_effect_graph_color_key,
            "authored_effect_graph_workshop_shift_hue_count": authored_effect_graph_workshop_shift_hue,
            "authored_effect_graph_workshop_audio_bars_count": authored_effect_graph_workshop_audio_bars,
            "authored_effect_graph_fisheye_zero_distortion_count": authored_effect_graph_fisheye_zero_distortion,
            "authored_effect_graph_workshop_gradient_count": authored_effect_graph_workshop_gradient,
            "authored_effect_graph_workshop_audio_hue_shift_count": authored_effect_graph_workshop_audio_hue_shift,
            "authored_effect_graph_opacity_layer_ids": authored_effect_graph_opacity_layers,
            "authored_effect_graph_workshop_shadow_count": authored_effect_graph_workshop_shadow,
            "authored_effect_graph_procedural_noise_count": authored_effect_graph_procedural_noise,
            "authored_effect_graph_film_grain_count": authored_effect_graph_film_grain,
            "authored_effect_graph_light_shafts_count": authored_effect_graph_light_shafts,
            "authored_effect_graph_shake_count": authored_effect_graph_shake,
            "authored_effect_graph_water_flow_count": authored_effect_graph_water_flow,
            "authored_effect_graph_water_waves_count": authored_effect_graph_water_waves,
            "authored_effect_graph_water_caustics_count": authored_effect_graph_water_caustics,
            "authored_effect_graph_foliage_sway_count": authored_effect_graph_foliage_sway,
            "authored_effect_graph_water_ripple_count": authored_effect_graph_water_ripple,
            "authored_effect_graph_iris_inline_suffix_count": authored_effect_graph_iris_inline_suffix,
            "authored_effect_graph_cursor_ripple_count": authored_effect_graph_cursor_ripple,
            "authored_effect_graph_cursor_ripple_isolated_count": authored_effect_graph_cursor_ripple_isolated,
            "authored_effect_graph_cursor_ripple_omitted_effects": authored_effect_graph_cursor_ripple_omitted,
            "authored_effect_graph_clipping_mask_count": authored_effect_graph_clipping_mask,
            "authored_effect_graph_blend_count": authored_effect_graph_blend,
            "authored_effect_graph_tint_count": authored_effect_graph_tint,
            "authored_effect_graph_pulse_count": authored_effect_graph_pulse,
            "authored_effect_graph_godrays_count": authored_effect_graph_godrays,
            "authored_effect_graph_transform_count": authored_effect_graph_transform,
            "authored_effect_graph_transform_static_fallback_count": authored_effect_graph_transform_static_fallback,
            "authored_effect_graph_transform_static_fallback_diagnostics": authored_effect_graph_transform_fallback_diagnostics,
            "authored_effect_graph_authored_shader_count": authored_effect_graph_authored_shader,
            "authored_effect_graph_scroll_count": authored_effect_graph_scroll,
            "effect_stage_admission": effect_stage_admission,
            "authored_effect_stage_compile": authored_effect_stage_compile,
            "effect_runtime_disposition": effect_runtime_disposition,
            "effect_execution": effect_execution,
            "resolved_material_graph_execution": (
                resolved_material_graph_execution
            ),
            "named_target_capture_succeeded_layer_ids": (
                named_target_capture_execution["succeeded_layer_ids"]
            ),
            "named_target_capture_failed_layer_ids": (
                named_target_capture_execution["failed_layer_ids"]
            ),
            "visible_graph_output_publication_succeeded_layer_ids": (
                visible_graph_output_publication_execution[
                    "succeeded_layer_ids"
                ]
            ),
            "visible_graph_output_publication_failed_layer_ids": (
                visible_graph_output_publication_execution["failed_layer_ids"]
            ),
            "named_graph_output_publication_succeeded_layer_ids": (
                named_graph_output_publication_execution[
                    "succeeded_layer_ids"
                ]
            ),
            "named_graph_output_publication_failed_layer_ids": (
                named_graph_output_publication_execution["failed_layer_ids"]
            ),
            "named_target_binding_succeeded_layer_ids": (
                named_target_binding_execution["succeeded_layer_ids"]
            ),
            "named_target_binding_failed_layer_ids": (
                named_target_binding_execution["failed_layer_ids"]
            ),
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
            "particle_sticky_loaded": particle_runtime["sticky_loaded"],
            "particle_sticky_total": particle_runtime["sticky_total"],
            "particle_current_nonempty_layer_ids": particle_runtime["current_nonempty_layer_ids"],
            "particle_committed_nonempty_layer_ids": particle_runtime["committed_nonempty_layer_ids"],
            "particle_unavailable_layer_ids": particle_runtime["unavailable_layer_ids"],
            "particle_diagnostics": particle_runtime["particle_diagnostics"],
            "audio_scaled_value": audio_scaled_value,
            "camera_projection": camera_match.group("projection") if camera_match else None,
            "camera_parallax": camera_match.group("parallax") == "true" if camera_match else None,
            "camera_parallax_amount": float(camera_match.group("amount")) if camera_match else None,
            "camera_parallax_delay": (
                float(camera_match.group("delay"))
                if camera_match and camera_match.group("delay") is not None
                else None
            ),
            "camera_parallax_mouse_influence": float(camera_match.group("influence")) if camera_match else None,
            "camera_shake_status": (
                camera_shake_match.group("status") if camera_shake_match else None
            ),
            "camera_shake_enabled": (
                camera_shake_match.group("enabled") == "true"
                if camera_shake_match
                and camera_shake_match.group("enabled") != "invalid"
                else None
            ),
            "camera_shake_amplitude": (
                float(camera_shake_match.group("amplitude"))
                if camera_shake_match
                and camera_shake_match.group("amplitude") != "invalid"
                else None
            ),
            "camera_shake_roughness": (
                float(camera_shake_match.group("roughness"))
                if camera_shake_match
                and camera_shake_match.group("roughness") != "invalid"
                else None
            ),
            "camera_shake_speed": (
                float(camera_shake_match.group("speed"))
                if camera_shake_match
                and camera_shake_match.group("speed") != "invalid"
                else None
            ),
            "offscreen_route_count": preview_text.count("offscreen skeleton"),
            "gaussian_blur_runtime_count": blur_runtime_count,
            "precise_blur_runtime_count": precise_blur_runtime_count,
            "skipped_unsupported_composite_count": skipped_composite_count,
            "perspective_opacity_runtime_count": perspective_opacity_count,
            "water_ripple_normal_runtime_count": water_ripple_normal_count,
            "water_ripple_normal_load_count": water_ripple_normal_load_count,
            "legacy_water_ripple_runtime_count": legacy_water_ripple_count,
            "sprite_animation_count": sprite_animation_count,
            "color_blend_mode_9_count": color_blend_mode_9_count,
            "bloom_runtime_count": bloom_runtime_count,
            "runtime_evidence": runtime_evidence,
        },
    }
    failures.extend(sample_result_failures(
        sample, result,
        authored_opacity_runtime_count=authored_opacity_runtime_count,
        camera_match=camera_match,
        camera_shake_match=camera_shake_match,
        execution_observations_enabled=execution_observations_enabled,
        live_property_overrides=live_property_overrides,
        log_text=log_text,
        media_thumbnail_store=media_thumbnail_store,
        named_graph_output_publication_execution=named_graph_output_publication_execution,
        named_target_binding_execution=named_target_binding_execution,
        named_target_capture_execution=named_target_capture_execution,
        particle_runtime=particle_runtime,
        puppet_animation_runtime=puppet_animation_runtime,
        ready_match=ready_match,
        require_cursor_ripple_persistence=require_cursor_ripple_persistence,
        require_effect_execution=require_effect_execution,
        require_effect_stage_admission=require_effect_stage_admission,
        require_graph_execution=require_graph_execution,
        result_dir=result_dir,
        runtime_evidence_match=runtime_evidence_match,
        solid_runtime=solid_runtime,
        stopped_match=stopped_match,
        utility_capture_execution=utility_capture_execution,
        utility_runtime=utility_runtime,
        visible_graph_output_publication_execution=visible_graph_output_publication_execution,
        log_only=log_only,
    ))
    result["passed"] = not failures
    if startup_timeout_allowance != 60:
        result["startup_timeout_allowance"] = startup_timeout_allowance
    return result

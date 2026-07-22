#!/usr/bin/env python3
"""Run isolated, signed-app Scene wallpaper evidence checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from web_benchmark_capture import (
    AppIdentityError,
    png_flat_border_ratio,
    png_has_non_black_pixel,
    png_motion_metrics,
    require_fresh_output_dir,
    stage_signed_app,
    verify_staged_app,
)


READY_RE = re.compile(
    r"phase=ready .* layers=(?P<layers>\d+) imageLayers=(?P<images>\d+) "
    r"effects=(?P<effects>\d+) surfaces=(?P<surfaces>\d+)"
)
INTERPRETATION_RE = re.compile(
    r"phase=ready .* interpretation=(?P<path>.+)$",
    re.MULTILINE,
)
STOPPED_RE = re.compile(r"phase=stopped surfacesBefore=(?P<before>\d+) surfacesAfter=(?P<after>\d+)")
LOADED_RE = re.compile(r"^loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)
TEXT_LOADED_RE = re.compile(r"^text loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)
FLOAT_PATTERN = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
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


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_matrix(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1 or not isinstance(payload.get("samples"), list):
        raise ValueError(f"invalid Scene matrix: {path}")
    return payload


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
            raise ValueError("Scene interpretation pass is not an object")
        slots = item.get("textureSlots")
        combos = item.get("combos")
        if not isinstance(slots, list) or any(slot is not None and not isinstance(slot, str) for slot in slots):
            raise ValueError("Scene interpretation textureSlots has an invalid shape")
        if not isinstance(combos, dict) or any(type(value) is not int for value in combos.values()):
            raise ValueError("Scene interpretation combos has an invalid shape")
        slot_count += len(slots)
        slot_holes += sum(slot is None for slot in slots)
        combo_count += len(combos)
    return slot_count, slot_holes, combo_count


def interpretation_metrics(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        descriptor = payload["renderDescriptor"]
        layers = descriptor.get("layers", [])
        effect_passes = [
            item
            for layer in descriptor.get("layers", [])
            for effect in layer.get("effects", [])
            for item in effect.get("passes", [])
        ]
        material_passes = descriptor.get("materialPasses", [])
        parallax_layers = [
            layer
            for layer in layers
            if isinstance(layer.get("parallaxDepthXY"), list)
            and any(abs(float(value)) > 1e-8 for value in layer["parallaxDepthXY"])
        ]
        effect_slot_count, effect_slot_holes, effect_combo_count = pass_metadata_metrics(effect_passes)
        material_slot_count, material_slot_holes, material_combo_count = pass_metadata_metrics(material_passes)
        return {
            "format_version": int(payload["formatVersion"]),
            "effect_texture_slot_count": effect_slot_count,
            "effect_texture_slot_hole_count": effect_slot_holes,
            "effect_combo_entry_count": effect_combo_count,
            "material_texture_slot_count": material_slot_count,
            "material_texture_slot_hole_count": material_slot_holes,
            "material_combo_entry_count": material_combo_count,
            "visible_layer_count": sum(layer.get("visible") is not False for layer in layers),
            "visible_layer_ids": [layer.get("id") for layer in layers if layer.get("visible") is not False],
            "authored_parallax_layer_count": len(parallax_layers),
            "authored_parallax_layer_ids": [layer.get("id") for layer in parallax_layers],
            "parallax_propagation_block_count": sum(
                layer.get("disablesParallaxPropagation") is True for layer in layers
            ),
            "text_values": [layer.get("text") for layer in layers if isinstance(layer.get("text"), str)],
            "error": None,
        }
    except (AttributeError, KeyError, TypeError, ValueError, json.JSONDecodeError, OSError) as error:
        return {
            "format_version": None,
            "effect_texture_slot_count": 0,
            "effect_texture_slot_hole_count": 0,
            "effect_combo_entry_count": 0,
            "material_texture_slot_count": 0,
            "material_texture_slot_hole_count": 0,
            "material_combo_entry_count": 0,
            "visible_layer_count": 0,
            "visible_layer_ids": [],
            "authored_parallax_layer_count": 0,
            "authored_parallax_layer_ids": [],
            "parallax_propagation_block_count": 0,
            "text_values": [],
            "error": str(error),
        }


def run_sample(
    runtime_binary: Path,
    sample_root: Path,
    sample: dict[str, Any],
    output_dir: Path,
    duration: float,
) -> dict[str, Any]:
    sample_id = str(sample["id"])
    source = sample_root / "Scene" / sample_id
    result_dir = output_dir / "results" / sample_id
    runtime_sample = output_dir / "runtime-samples" / sample_id
    runtime_home = output_dir / "runtime-homes" / sample_id
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
    property_overrides = sample.get("property_overrides")
    if isinstance(property_overrides, dict) and property_overrides:
        command.extend([
            "--mwx-debug-scene-properties-json",
            json.dumps(property_overrides, ensure_ascii=False, separators=(",", ":")),
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
    interpretation_match = INTERPRETATION_RE.search(log_text)
    stopped_match = STOPPED_RE.search(log_text)
    loaded_match = LOADED_RE.search(preview_text)
    loaded = int(loaded_match.group("loaded")) if loaded_match else 0
    total = int(loaded_match.group("total")) if loaded_match else 0
    loaded_ratio = loaded / total if total else 0.0
    text_loaded_match = TEXT_LOADED_RE.search(preview_text)
    text_loaded = int(text_loaded_match.group("loaded")) if text_loaded_match else 0
    text_total = int(text_loaded_match.group("total")) if text_loaded_match else 0
    camera_match = CAMERA_RE.search(preview_text)
    ready_snapshot = result_dir / "scene-ready-window.png"
    after_snapshot = result_dir / "scene-after-window.png"
    ready_non_black = png_has_non_black_pixel(ready_snapshot)
    after_non_black = png_has_non_black_pixel(after_snapshot)
    flat_border_ratio = {
        "ready": png_flat_border_ratio(ready_snapshot),
        "after": png_flat_border_ratio(after_snapshot),
    }
    motion = png_motion_metrics(ready_snapshot, after_snapshot)
    interpretation_path = (
        Path(interpretation_match.group("path").strip())
        if interpretation_match is not None
        else Path("-")
    )
    interpretation = interpretation_metrics(interpretation_path)
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
    if interpretation_match is None:
        failures.append("missing cache interpretation path")
    else:
        interpretation_cache_root = (
            runtime_home / "Library/Caches/MyWallpaperX/SteamWorkshopScene"
        ).resolve()
        try:
            interpretation_path.resolve().relative_to(interpretation_cache_root)
        except ValueError:
            failures.append("Scene interpretation path is outside package cache")
    if sample_root_residue:
        failures.append(
            "Scene sample root contains derived files: " + ", ".join(sample_root_residue)
        )
    if stopped_match is None or int(stopped_match.group("after")) != 0:
        failures.append("Scene surfaces not released")
    if "phase=snapshot-failed" in log_text:
        failures.append("window snapshot failed")
    if camera_match is None or camera_match.group("projection") != "cover":
        failures.append("camera projection evidence missing")
    expected_parallax = sample.get("expected_camera_parallax")
    if expected_parallax is not None:
        actual_parallax = camera_match and camera_match.group("parallax") == "true"
        if actual_parallax != bool(expected_parallax):
            failures.append("camera parallax state mismatch")
    minimum_parallax_layers = int(sample.get("minimum_authored_parallax_layer_count", 0))
    if interpretation["authored_parallax_layer_count"] < minimum_parallax_layers:
        failures.append("authored parallax layer count below minimum")
    if loaded_ratio < float(sample.get("minimum_loaded_ratio", 0)):
        failures.append(f"loaded ratio {loaded_ratio:.3f} below minimum")
    if text_loaded < int(sample.get("minimum_text_loaded", 0)):
        failures.append("text texture count below minimum")
    blur_runtime_count = preview_text.count("effect runtime gaussian-blur;")
    if blur_runtime_count < int(sample.get("minimum_gaussian_blur_runtime_count", 0)):
        failures.append("gaussian blur runtime count below minimum")
    precise_blur_runtime_count = preview_text.count("effect runtime gaussian-blur-precise;")
    if precise_blur_runtime_count < int(sample.get("minimum_precise_blur_runtime_count", 0)):
        failures.append("precise gaussian blur runtime count below minimum")
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
    if interpretation["format_version"] is None:
        failures.append("Scene interpretation evidence missing or invalid")
    interpretation_expectations = {
        "expected_interpretation_format": "format_version",
        "expected_effect_texture_slot_count": "effect_texture_slot_count",
        "expected_effect_texture_slot_hole_count": "effect_texture_slot_hole_count",
        "expected_effect_combo_entry_count": "effect_combo_entry_count",
        "expected_material_texture_slot_count": "material_texture_slot_count",
        "expected_material_texture_slot_hole_count": "material_texture_slot_hole_count",
        "expected_material_combo_entry_count": "material_combo_entry_count",
        "expected_visible_layer_count": "visible_layer_count",
    }
    for expectation, metric in interpretation_expectations.items():
        if expectation in sample and interpretation[metric] != int(sample[expectation]):
            failures.append(f"Scene interpretation {metric} mismatch")
    expected_text_value = sample.get("expected_text_value")
    if expected_text_value is not None and expected_text_value not in interpretation["text_values"]:
        failures.append("Scene interpretation text property mismatch")
    visible_layer_ids = set(interpretation["visible_layer_ids"])
    for layer_id in sample.get("required_visible_layer_ids", []):
        if layer_id not in visible_layer_ids:
            failures.append(f"Scene property layer {layer_id} should be visible")
    for layer_id in sample.get("required_hidden_layer_ids", []):
        if layer_id in visible_layer_ids:
            failures.append(f"Scene property layer {layer_id} should be hidden")
    bloom_runtime_count = preview_text.count("effect runtime bloom")
    if bloom_runtime_count < int(sample.get("minimum_bloom_runtime_count", 0)):
        failures.append("bloom runtime count below minimum")
    if not ready_non_black or not after_non_black:
        failures.append("non-black window evidence missing")
    if sample.get("requires_motion"):
        minimum_changed_ratio = float(sample.get("minimum_changed_ratio", 0))
        if motion is None or motion["changed_ratio"] < minimum_changed_ratio:
            failures.append("animated output evidence below minimum")
    maximum_changed_ratio = sample.get("maximum_changed_ratio")
    if maximum_changed_ratio is not None:
        if motion is None or motion["changed_ratio"] > float(maximum_changed_ratio):
            failures.append("static output evidence above maximum")
    maximum_flat_border_ratio = sample.get("maximum_flat_border_ratio")
    if maximum_flat_border_ratio is not None:
        ratios = [value for value in flat_border_ratio.values() if value is not None]
        if len(ratios) != 2 or max(ratios) > float(maximum_flat_border_ratio):
            failures.append("flat border evidence above maximum")

    return {
        "id": sample_id,
        "title": sample.get("title"),
        "capabilities": sample.get("capabilities", []),
        "property_overrides": property_overrides if isinstance(property_overrides, dict) else {},
        "passed": not failures,
        "failures": failures,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "hashes": hashes,
        "package_file": package_path.name,
        "runtime_sample": str(runtime_sample),
        "runtime_home": str(runtime_home),
        "evidence": {
            "app_log": str(app_log),
            "preview_log": str(preview_log),
            "interpretation": str(interpretation_path),
            "sample_root_residue": sample_root_residue,
            "ready_snapshot": str(ready_snapshot),
            "after_snapshot": str(after_snapshot),
            "ready_non_black": ready_non_black,
            "after_non_black": after_non_black,
            "flat_border_ratio": flat_border_ratio,
            "motion": motion,
        },
        "runtime": {
            "layers": int(ready_match.group("layers")) if ready_match else None,
            "image_layers": int(ready_match.group("images")) if ready_match else None,
            "effects": int(ready_match.group("effects")) if ready_match else None,
            "surfaces": int(ready_match.group("surfaces")) if ready_match else None,
            "loaded_textures": loaded,
            "texture_candidates": total,
            "loaded_ratio": round(loaded_ratio, 4),
            "loaded_textures_text": text_loaded,
            "text_candidates": text_total,
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
            "route_only_effect_count": preview_text.count("offscreen route-only"),
            "interpretation": interpretation,
        },
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="signed MyWallpaperX executable")
    parser.add_argument("--sample-root", required=True, type=Path, help="isolated root containing Scene/<id>")
    parser.add_argument(
        "--matrix",
        type=Path,
        default=Path(__file__).with_name("scene_wallpaper_sample_matrix.json"),
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--duration", type=float, default=7)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output_dir = require_fresh_output_dir(args.output_dir.expanduser().resolve())
    matrix = load_matrix(args.matrix.expanduser().resolve())
    try:
        runtime_binary, app_identity = stage_signed_app(args.app, output_dir)
    except AppIdentityError as error:
        print(f"Scene benchmark precondition failed: {error}", file=sys.stderr)
        return 2

    results = [
        run_sample(
            runtime_binary=runtime_binary,
            sample_root=args.sample_root.expanduser().resolve(),
            sample=sample,
            output_dir=output_dir,
            duration=max(args.duration, 5),
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
    report = {
        "schema_version": 1,
        "matrix": matrix["name"],
        "command": sys.argv,
        "app_identity": app_identity,
        "sample_root": str(args.sample_root.expanduser().resolve()),
        "summary": {
            "passed": passed,
            "sample_count": len(results),
            "passed_count": sum(result["passed"] for result in results),
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

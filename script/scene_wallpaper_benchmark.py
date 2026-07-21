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
STOPPED_RE = re.compile(r"phase=stopped surfacesBefore=(?P<before>\d+) surfacesAfter=(?P<after>\d+)")
LOADED_RE = re.compile(r"^loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)
TEXT_LOADED_RE = re.compile(r"^text loaded: (?P<loaded>\d+) / (?P<total>\d+)$", re.MULTILINE)


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


def copy_sample(source: Path, destination: Path) -> None:
    if not (source / "project.json").is_file() or not (source / "scene.pkg").is_file():
        raise FileNotFoundError(f"Scene sample is incomplete: {source}")
    shutil.copytree(source, destination)


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

    hashes = {
        "project_sha256": sha256(source / "project.json"),
        "package_sha256": sha256(source / "scene.pkg"),
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
    stopped_match = STOPPED_RE.search(log_text)
    loaded_match = LOADED_RE.search(preview_text)
    loaded = int(loaded_match.group("loaded")) if loaded_match else 0
    total = int(loaded_match.group("total")) if loaded_match else 0
    loaded_ratio = loaded / total if total else 0.0
    text_loaded_match = TEXT_LOADED_RE.search(preview_text)
    text_loaded = int(text_loaded_match.group("loaded")) if text_loaded_match else 0
    text_total = int(text_loaded_match.group("total")) if text_loaded_match else 0
    ready_snapshot = result_dir / "scene-ready-window.png"
    after_snapshot = result_dir / "scene-after-window.png"
    ready_non_black = png_has_non_black_pixel(ready_snapshot)
    after_non_black = png_has_non_black_pixel(after_snapshot)
    motion = png_motion_metrics(ready_snapshot, after_snapshot)

    if timed_out:
        failures.append("process timeout")
    if exit_code != 0:
        failures.append(f"process exit {exit_code}")
    if ready_match is None:
        failures.append("missing ready event")
    elif int(ready_match.group("surfaces")) < 1:
        failures.append("no Scene surface")
    if stopped_match is None or int(stopped_match.group("after")) != 0:
        failures.append("Scene surfaces not released")
    if "phase=snapshot-failed" in log_text:
        failures.append("window snapshot failed")
    if loaded_ratio < float(sample.get("minimum_loaded_ratio", 0)):
        failures.append(f"loaded ratio {loaded_ratio:.3f} below minimum")
    if text_loaded < int(sample.get("minimum_text_loaded", 0)):
        failures.append("text texture count below minimum")
    blur_runtime_count = preview_text.count("effect runtime gaussian-blur")
    if blur_runtime_count < int(sample.get("minimum_gaussian_blur_runtime_count", 0)):
        failures.append("gaussian blur runtime count below minimum")
    bloom_runtime_count = preview_text.count("effect runtime bloom")
    if bloom_runtime_count < int(sample.get("minimum_bloom_runtime_count", 0)):
        failures.append("bloom runtime count below minimum")
    if not ready_non_black or not after_non_black:
        failures.append("non-black window evidence missing")
    if sample.get("requires_motion"):
        minimum_changed_ratio = float(sample.get("minimum_changed_ratio", 0))
        if motion is None or motion["changed_ratio"] < minimum_changed_ratio:
            failures.append("animated output evidence below minimum")

    return {
        "id": sample_id,
        "title": sample.get("title"),
        "capabilities": sample.get("capabilities", []),
        "passed": not failures,
        "failures": failures,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "hashes": hashes,
        "runtime_sample": str(runtime_sample),
        "runtime_home": str(runtime_home),
        "evidence": {
            "app_log": str(app_log),
            "preview_log": str(preview_log),
            "ready_snapshot": str(ready_snapshot),
            "after_snapshot": str(after_snapshot),
            "ready_non_black": ready_non_black,
            "after_non_black": after_non_black,
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
            "offscreen_route_count": preview_text.count("offscreen skeleton"),
            "gaussian_blur_runtime_count": blur_runtime_count,
            "bloom_runtime_count": bloom_runtime_count,
            "route_only_effect_count": preview_text.count("offscreen route-only"),
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

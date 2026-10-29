"""Own isolated sample/package material, product-entry run and cleanup."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import subprocess
from pathlib import Path
from scene_product_entry_audio_baseline import classify_product_entry_result, product_entry_command
from scene_sample_snapshot import DERIVED_NAMES, tree_manifest
from typing import Any, Callable
from web_benchmark_capture import discard_staged_app


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
    if not (source / "project.json").is_file():
        raise FileNotFoundError(f"Scene sample is incomplete: {source}")
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns(*DERIVED_NAMES))

def rebuildable_artifact_removal_metrics(path: Path) -> tuple[int, int]:
    if path.is_symlink() or not path.is_dir():
        return 1, path.lstat().st_size
    count = 0
    size_bytes = 0
    with os.scandir(path) as entries:
        for entry in entries:
            child = Path(entry.path)
            if entry.is_dir(follow_symlinks=False):
                child_count, child_bytes = rebuildable_artifact_removal_metrics(
                    child
                )
                count += child_count
                size_bytes += child_bytes
            else:
                count += 1
                size_bytes += entry.stat(follow_symlinks=False).st_size
    return count, size_bytes

def run_product_entry_audio_sample(
    runtime_binary: Path,
    sample_root: Path,
    sample: dict[str, Any],
    output_dir: Path,
    runtime_root: Path,
    duration: float,
    property_overrides: dict[str, str | float | bool],
) -> dict[str, Any]:
    sample_id = str(sample["id"])
    source = sample_root / "Scene" / sample_id
    result_dir = output_dir / "results" / sample_id
    runtime_sample = runtime_root / "runtime-samples" / sample_id
    runtime_home = runtime_root / "runtime-homes" / sample_id
    runtime_workshop = runtime_root / "runtime-workshops" / sample_id
    result_dir.mkdir(parents=True)
    runtime_home.mkdir(parents=True)
    runtime_workshop.mkdir(parents=True)

    package_path = scene_package_path(source) if source.is_dir() else None
    preflight_failures: list[str] = []
    if not (source / "project.json").is_file():
        preflight_failures.append("Scene sample project.json is missing")
    if preflight_failures:
        return {
            "id": sample_id,
            "passed": False,
            "baseline": {
                "status": "source-invalid",
                "passed": False,
                "failures": preflight_failures,
                "evidence_ceiling": "S0-no-executable-result",
            },
            "failures": preflight_failures,
            "command": None,
            "exit_code": None,
            "timed_out": False,
            "hashes": {},
            "evidence": {},
            "daemon_client_result": None,
            "property_overrides": property_overrides,
            "runtime_sample": str(runtime_sample),
            "runtime_home": str(runtime_home),
            "runtime_workshop": str(runtime_workshop),
            "runtime_retained": True,
        }

    copy_sample(source, runtime_sample)
    hashes = {
        "project_sha256": sha256(source / "project.json"),
        "package_sha256": sha256(package_path) if package_path is not None else None,
    }
    if package_path is None:
        hashes["tree_sha256"] = tree_manifest(source)[0]
    command = product_entry_command(
        runtime_binary=runtime_binary,
        runtime_sample=runtime_sample,
        result_dir=result_dir,
        runtime_workshop=runtime_workshop,
        sample_id=sample_id,
        duration=duration,
        property_overrides=property_overrides,
    )
    environment = os.environ.copy()
    environment["HOME"] = str(runtime_home)
    environment["CFFIXED_USER_HOME"] = str(runtime_home)
    app_log = result_dir / "app.log"
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
            exit_code = process.wait(timeout=duration + 60)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.terminate()
            try:
                exit_code = process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                exit_code = process.wait(timeout=5)

    daemon_result_path = result_dir / "scene-daemon-client-result.json"
    daemon_result: Any = None
    if daemon_result_path.is_file():
        try:
            daemon_result = json.loads(
                daemon_result_path.read_text(encoding="utf-8")
            )
        except (OSError, json.JSONDecodeError):
            daemon_result = None
    baseline = classify_product_entry_result(
        sample_id,
        daemon_result,
        exit_code=exit_code,
        timed_out=timed_out,
        expected_property_overrides=property_overrides,
    )
    removed_artifact_count = 0
    removed_artifact_bytes = 0
    retained_names = {"app.log", "scene-daemon-client-result.json"}
    for artifact in result_dir.iterdir():
        if artifact.name in retained_names:
            continue
        artifact_count, artifact_bytes = rebuildable_artifact_removal_metrics(
            artifact
        )
        removed_artifact_count += artifact_count
        removed_artifact_bytes += artifact_bytes
        if artifact.is_dir() and not artifact.is_symlink():
            shutil.rmtree(artifact)
        else:
            artifact.unlink()
    evidence = {
        "app_log_path": str(app_log),
        "app_log_sha256": sha256(app_log),
        "daemon_client_result_path": (
            str(daemon_result_path) if daemon_result_path.is_file() else None
        ),
        "daemon_client_result_sha256": (
            sha256(daemon_result_path) if daemon_result_path.is_file() else None
        ),
        "removed_rebuildable_artifact_count": removed_artifact_count,
        "removed_rebuildable_artifact_bytes": removed_artifact_bytes,
    }
    return {
        "id": sample_id,
        "passed": baseline["passed"],
        "baseline": baseline,
        "failures": baseline["failures"],
        "command": command,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "hashes": hashes,
        "evidence": evidence,
        "daemon_client_result": daemon_result,
        "property_overrides": property_overrides,
        "runtime_sample": str(runtime_sample),
        "runtime_home": str(runtime_home),
        "runtime_workshop": str(runtime_workshop),
        "runtime_retained": True,
    }

def remove_runtime_tree(runtime_root: Path) -> None:
    if not runtime_root.exists():
        return

    def retry_read_only_removal(
        function: Callable[[str], object],
        raw_path: str,
        error: BaseException,
    ) -> None:
        if not isinstance(error, PermissionError):
            raise error
        path = Path(raw_path)
        parent = path.parent
        if parent.exists() and not parent.is_symlink():
            parent.chmod(parent.stat().st_mode | stat.S_IWUSR | stat.S_IXUSR)
        if path.exists() and not path.is_symlink():
            mode = stat.S_IWUSR | (stat.S_IXUSR if path.is_dir() else 0)
            path.chmod(path.stat().st_mode | mode)
        function(raw_path)

    shutil.rmtree(runtime_root, onexc=retry_read_only_removal)

def apply_runtime_retention(
    runtime_root: Path,
    app_identity: dict[str, Any],
    results: list[dict[str, Any]],
    keep_runtime: bool,
    *,
    finalize_stage: bool = True,
) -> None:
    if keep_runtime:
        return

    for result in results:
        for key in ("runtime_sample", "runtime_home", "runtime_workshop"):
            if not result.get(key):
                continue
            path = Path(result[key])
            try:
                path.resolve().relative_to(runtime_root.resolve())
            except ValueError as error:
                raise RuntimeError(f"Scene runtime cleanup path escapes runtime root: {path}") from error
            if path.exists():
                remove_runtime_tree(path)
            result[key] = None
        result["runtime_retained"] = False

    if finalize_stage:
        discard_staged_app(app_identity)
        remove_runtime_tree(runtime_root)

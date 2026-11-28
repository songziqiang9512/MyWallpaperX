#!/usr/bin/env python3
"""Bounded glslang -> SPIR-V -> SPIRV-Cross MSL compiler harness.

The default report remains observe-only. With explicit ``--artifact-output``
the tool also emits an exact-source-keyed, development-gated Program artifact
after combined MSL and Metal frontend preflight. The App independently validates
that artifact and only attempts it under an explicit ``prefer-generic`` route;
this tool does not enable a default or release product route.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import platform
import resource
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from scene_shader_compiler_artifact import (
    ArtifactFailure,
    build_program_artifact,
    request_cache_key,
)
from scene_shader_compiler_request_contract import (
    ALLOWED_STAGES,
    RequestContractFailure,
    validated_request_stages,
)
from scene_shader_compiler_normalization import (
    HarnessFailure,
    normalize_request,
    normalize_wallpaper_engine_pair,
)
from scene_shader_compiler_cli import parse_args


SCRIPT_ROOT = Path(__file__).resolve().parent
DEFAULT_MANIFEST = SCRIPT_ROOT / "data" / "scene_shader_compiler_dependencies.json"
STAGE_SUFFIX = {"vertex": "vert", "fragment": "frag"}


@dataclass(frozen=True)
class Limits:
    maximum_stage_source_bytes: int
    maximum_diagnostic_bytes: int
    maximum_artifact_bytes: int
    maximum_resident_bytes: int
    timeout_seconds: float


@dataclass(frozen=True)
class Tool:
    name: str
    path: Path
    sha256: str
    version: str


@dataclass(frozen=True)
class CommandResult:
    argv: list[str]
    duration_milliseconds: float
    stdout: str
    stderr: str


def canonical_json(payload: Any) -> bytes:
    return (json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ) + "\n").encode("utf-8")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_json(path: Path, phase: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise HarnessFailure(phase, "invalid-json", [str(error)]) from error
    if not isinstance(payload, dict):
        raise HarnessFailure(phase, "invalid-shape")
    return payload


def parse_limits(manifest: dict[str, Any]) -> Limits:
    raw = manifest.get("limits")
    if not isinstance(raw, dict):
        raise HarnessFailure("manifest", "limits-missing")
    try:
        values = Limits(
            maximum_stage_source_bytes=int(raw["maximumStageSourceBytes"]),
            maximum_diagnostic_bytes=int(raw["maximumDiagnosticBytes"]),
            maximum_artifact_bytes=int(raw["maximumArtifactBytes"]),
            maximum_resident_bytes=int(raw["maximumResidentBytes"]),
            timeout_seconds=int(raw["timeoutMilliseconds"]) / 1000.0,
        )
    except (KeyError, TypeError, ValueError) as error:
        raise HarnessFailure("manifest", "limits-invalid", [str(error)]) from error
    if not (
        1024 <= values.maximum_stage_source_bytes <= 4 * 1024 * 1024
        and 1024 <= values.maximum_diagnostic_bytes <= 1024 * 1024
        and 1024 <= values.maximum_artifact_bytes <= 64 * 1024 * 1024
        and 64 * 1024 * 1024 <= values.maximum_resident_bytes <= 2 * 1024 * 1024 * 1024
        and 0.1 <= values.timeout_seconds <= 30.0
    ):
        raise HarnessFailure("manifest", "limits-out-of-range")
    return values


def validate_request(payload: dict[str, Any], limits: Limits) -> list[dict[str, str]]:
    try:
        return validated_request_stages(
            payload, limits.maximum_stage_source_bytes
        )
    except RequestContractFailure as error:
        raise HarnessFailure(
            "request", error.code, error.details
        ) from error


def _child_limits(limits: Limits) -> None:
    def set_limit(kind: int, soft: int, hard: int) -> None:
        _, current_hard = resource.getrlimit(kind)
        bounded_hard = hard if current_hard == resource.RLIM_INFINITY else min(hard, current_hard)
        resource.setrlimit(kind, (min(soft, bounded_hard), bounded_hard))

    set_limit(
        resource.RLIMIT_CPU,
        max(1, math.ceil(limits.timeout_seconds)),
        max(2, math.ceil(limits.timeout_seconds) + 1),
    )
    set_limit(
        resource.RLIMIT_FSIZE,
        limits.maximum_artifact_bytes,
        limits.maximum_artifact_bytes,
    )
    set_limit(resource.RLIMIT_NOFILE, 64, 64)
    # Darwin exposes RLIMIT_AS but rejects lowering it from preexec_fn on
    # supported hosts. Keep the manifest value as an integration/worker gate;
    # timeout, source, diagnostics, file-size, CPU and descriptor limits remain
    # enforced by this observe-only harness.
    if sys.platform != "darwin" and hasattr(resource, "RLIMIT_AS"):
        set_limit(
            resource.RLIMIT_AS,
            limits.maximum_resident_bytes,
            limits.maximum_resident_bytes,
        )


def run_command(
    argv: list[str],
    limits: Limits,
    phase: str,
    expected_exit: int = 0,
    working_directory: Path | None = None,
) -> CommandResult:
    started = time.monotonic()
    try:
        process = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=False,
            start_new_session=True,
            preexec_fn=lambda: _child_limits(limits),
            env={"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"},
            cwd=working_directory,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise HarnessFailure(phase, "spawn-failed", [str(error)]) from error
    try:
        stdout_raw, stderr_raw = process.communicate(timeout=limits.timeout_seconds)
    except subprocess.TimeoutExpired as error:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise HarnessFailure(phase, "timeout") from error
    duration = (time.monotonic() - started) * 1000.0
    if len(stdout_raw) > limits.maximum_diagnostic_bytes or len(stderr_raw) > limits.maximum_diagnostic_bytes:
        raise HarnessFailure(phase, "diagnostic-too-large")
    stdout = stdout_raw.decode("utf-8", "replace")
    stderr = stderr_raw.decode("utf-8", "replace")
    if process.returncode != expected_exit:
        details = [f"exit={process.returncode}"]
        if stdout.strip():
            details.append(f"stdout={stdout.strip()}")
        if stderr.strip():
            details.append(f"stderr={stderr.strip()}")
        raise HarnessFailure(phase, "tool-rejected", details)
    return CommandResult(argv, round(duration, 3), stdout, stderr)


def resolve_tool(
    name: str,
    raw_path: str,
    expected_hashes: set[str],
    version_contains: str,
    version_exit_code: int,
    limits: Limits,
) -> Tool:
    path = Path(raw_path).expanduser().resolve()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise HarnessFailure("tool", "unavailable", [name, str(path)])
    artifact_hash = sha256(path)
    if artifact_hash not in expected_hashes:
        raise HarnessFailure("tool", "hash-mismatch", [name, artifact_hash])
    probe = run_command(
        [str(path), "--version"],
        limits,
        f"{name}-version",
        expected_exit=version_exit_code,
    )
    version = (probe.stdout + probe.stderr).strip()
    if version_contains not in version:
        raise HarnessFailure("tool", "version-mismatch", [name, version[:512]])
    return Tool(name, path, artifact_hash, version)


def validate_artifact(path: Path, limits: Limits, phase: str) -> dict[str, Any]:
    try:
        size = path.stat().st_size
    except OSError as error:
        raise HarnessFailure(phase, "artifact-missing", [str(error)]) from error
    if size <= 0 or size > limits.maximum_artifact_bytes:
        raise HarnessFailure(phase, "artifact-size", [str(size)])
    return {"bytes": size, "sha256": sha256(path)}


def compile_request(
    request: dict[str, Any],
    stages: list[dict[str, str]],
    glslang: Tool,
    spirv_cross: Tool,
    metal_path: Path,
    limits: Limits,
    normalization: dict[str, Any],
    artifact_requested: bool,
) -> tuple[dict[str, Any], dict[str, Any] | None]:
    with tempfile.TemporaryDirectory(prefix="mwx-shader-compiler-") as directory:
        root = Path(directory)
        sources: dict[str, Path] = {}
        for stage in stages:
            path = root / f"author.{STAGE_SUFFIX[stage['stage']]}"
            path.write_text(stage["source"], encoding="utf-8")
            sources[stage["stage"]] = path

        link = run_command([
            str(glslang.path),
            "-V",
            "--auto-map-bindings",
            "--auto-map-locations",
            "-l",
            str(sources["vertex"]),
            str(sources["fragment"]),
        ], limits, "stage-link", working_directory=root)

        compiled: list[dict[str, Any]] = []
        for stage in stages:
            name = stage["stage"]
            spirv = root / f"{name}.spv"
            msl = root / f"{name}.metal"
            reflection = root / f"{name}.reflection.json"
            air = root / f"{name}.air"
            frontend = run_command([
                str(glslang.path),
                "-V",
                "--auto-map-bindings",
                "--auto-map-locations",
                "-S",
                STAGE_SUFFIX[name],
                "-e",
                stage["entryPoint"],
                "-o",
                str(spirv),
                str(sources[name]),
            ], limits, f"{name}-glslang", working_directory=root)
            spirv_info = validate_artifact(spirv, limits, f"{name}-spirv")
            cross_msl = run_command([
                str(spirv_cross.path),
                str(spirv),
                "--msl",
                "--msl-version",
                "20000",
                "--msl-decoration-binding",
                "--rename-entry-point",
                stage["entryPoint"],
                "mwxGenericVertex" if name == "vertex" else "mwxGenericFragment",
                STAGE_SUFFIX[name],
                "--output",
                str(msl),
            ], limits, f"{name}-msl", working_directory=root)
            msl_info = validate_artifact(msl, limits, f"{name}-msl")
            cross_reflect = run_command([
                str(spirv_cross.path),
                str(spirv),
                "--reflect",
                "--output",
                str(reflection),
            ], limits, f"{name}-reflection", working_directory=root)
            reflection_info = validate_artifact(
                reflection, limits, f"{name}-reflection"
            )
            reflection_payload = read_json(reflection, f"{name}-reflection")
            metal = run_command([
                str(metal_path),
                "-x",
                "metal",
                "-std=macos-metal2.4",
                "-c",
                str(msl),
                "-o",
                str(air),
            ], limits, f"{name}-metal", working_directory=root)
            air_info = validate_artifact(air, limits, f"{name}-air")
            compiled.append({
                "stage": name,
                "entryPoint": stage["entryPoint"],
                "sourceBytes": len(stage["source"].encode("utf-8")),
                "sourceSHA256": hashlib.sha256(
                    stage["source"].encode("utf-8")
                ).hexdigest(),
                "spirv": spirv_info,
                "msl": msl_info,
                "reflectionArtifact": reflection_info,
                "air": air_info,
                "reflection": reflection_payload,
                "durationsMilliseconds": {
                    "glslang": frontend.duration_milliseconds,
                    "spirvCrossMSL": cross_msl.duration_milliseconds,
                    "spirvCrossReflection": cross_reflect.duration_milliseconds,
                    "metal": metal.duration_milliseconds,
                },
            })
        report = {
            "schemaVersion": 1,
            "kind": "scene-shader-compiler-harness",
            "status": "passed",
            "requestID": request["requestID"],
            "routeState": "observe-only",
            "productExecutionAuthorized": False,
            "toolchain": {
                "architecture": platform.machine(),
                "glslang": {
                    "path": str(glslang.path),
                    "sha256": glslang.sha256,
                    "version": glslang.version,
                },
                "spirvCross": {
                    "path": str(spirv_cross.path),
                    "sha256": spirv_cross.sha256,
                    "version": spirv_cross.version,
                },
                "metal": {"path": str(metal_path), "sha256": sha256(metal_path)},
            },
            "stageLinkMilliseconds": link.duration_milliseconds,
            "normalization": normalization,
            "limits": {
                "sourceBytes": "enforced",
                "diagnosticBytes": "enforced",
                "artifactBytes": "enforced",
                "wallTimeout": "enforced-process-group-kill",
                "cpuSeconds": "enforced-rlimit",
                "openFiles": "enforced-rlimit",
                "residentBytes": (
                    "best-effort-not-enforced-on-darwin"
                    if sys.platform == "darwin" else "enforced-rlimit"
                ),
            },
            "stages": compiled,
            "evidenceBoundary": (
                "Compiler, reflection, MSL emission, and Metal frontend preflight only; "
                "no Program, GPU encode, publication, compositor, next-frame, or parity claim."
            ),
        }
        artifact: dict[str, Any] | None = None
        if artifact_requested:
            try:
                artifact = build_program_artifact(
                    request_key=request_cache_key(request),
                    backend_id="glslang-spirv-cross-msl-v2",
                    compiled_stages=compiled,
                    stage_sources={stage["stage"]: stage["source"] for stage in stages},
                    msl_sources={
                        stage["stage"]: (root / f"{stage['stage']}.metal").read_text(
                            encoding="utf-8"
                        )
                        for stage in stages
                    },
                    maximum_artifact_bytes=limits.maximum_artifact_bytes,
                    output_semantics=request["outputSemantics"],
                    expected_color_transfer=request.get("expectedColorTransfer"),
                    premultiplied_color_input_slots=request.get(
                        "premultipliedColorInputSlots"
                    ),
                    color_boundary=request.get("colorBoundary"),
                    source_raster_projection_fragment_reads=normalization.get("fragmentReadsRasterPosition"),
                )
            except ArtifactFailure as error:
                raise HarnessFailure("artifact", str(error)) from error
            combined_msl = root / "program.metal"
            combined_air = root / "program.air"
            combined_msl.write_text(artifact["program"]["metalSource"], encoding="utf-8")
            artifact_metal = run_command([
                str(metal_path),
                "-x",
                "metal",
                "-std=macos-metal2.4",
                "-c",
                str(combined_msl),
                "-o",
                str(combined_air),
            ], limits, "artifact-metal", working_directory=root)
            artifact["program"]["metalPreflight"] = {
                **validate_artifact(combined_air, limits, "artifact-air"),
                "durationMilliseconds": artifact_metal.duration_milliseconds,
            }
        return report, artifact


def recorded_hashes(manifest: dict[str, Any], key: str) -> set[str]:
    artifacts = manifest.get("verifiedDevelopmentArtifacts")
    if not isinstance(artifacts, list):
        raise HarnessFailure("manifest", "artifacts-missing")
    hashes = {
        item.get(key)
        for item in artifacts
        if isinstance(item, dict) and isinstance(item.get(key), str)
    }
    if not hashes:
        raise HarnessFailure("manifest", "artifact-hash-missing", [key])
    return hashes


def main() -> int:
    args = parse_args(__doc__, DEFAULT_MANIFEST)
    try:
        manifest = read_json(args.dependency_manifest, "manifest")
        if manifest.get("schemaVersion") != 1:
            raise HarnessFailure("manifest", "schema-version")
        if (
            manifest.get("routeState") != "observe-only"
            or manifest.get("productExecutionAuthorized") is not False
        ):
            raise HarnessFailure("manifest", "route-authority")
        limits = parse_limits(manifest)
        request = read_json(args.request, "request")
        stages = validate_request(request, limits)
        stages, normalization = normalize_request(request, stages)
        tools = manifest.get("tools")
        if not isinstance(tools, dict):
            raise HarnessFailure("manifest", "tools-missing")
        glslang_manifest = tools.get("glslang")
        cross_manifest = tools.get("spirvCross")
        if not isinstance(glslang_manifest, dict) or not isinstance(cross_manifest, dict):
            raise HarnessFailure("manifest", "tool-shape")
        glslang = resolve_tool(
            "glslang",
            args.glslang,
            recorded_hashes(manifest, "glslangSHA256"),
            str(glslang_manifest.get("versionProbeContains", "")),
            int(glslang_manifest.get("versionProbeExitCode", -1)),
            limits,
        )
        spirv_cross = resolve_tool(
            "spirv-cross",
            args.spirv_cross,
            recorded_hashes(manifest, "spirvCrossSHA256"),
            str(cross_manifest.get("versionProbeContains", "")),
            int(cross_manifest.get("versionProbeExitCode", -1)),
            limits,
        )
        metal = Path(args.metal).expanduser().resolve()
        if not metal.is_file() or not os.access(metal, os.X_OK):
            raise HarnessFailure("tool", "unavailable", ["metal", str(metal)])
        report, artifact = compile_request(
            request, stages, glslang, spirv_cross, metal, limits, normalization,
            artifact_requested=args.artifact_output is not None,
        )
        if args.artifact_output is not None:
            if artifact is None:
                raise HarnessFailure("artifact", "program-contract-unproven")
            artifact_output = canonical_json(artifact)
            if len(artifact_output) > limits.maximum_artifact_bytes:
                raise HarnessFailure("artifact", "artifact-size")
            args.artifact_output.parent.mkdir(parents=True, exist_ok=True)
            args.artifact_output.write_bytes(artifact_output)
        output = canonical_json(report)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(output)
        return 0
    except HarnessFailure as failure:
        print(json.dumps({
            "schemaVersion": 1,
            "kind": "scene-shader-compiler-harness",
            "status": "failed",
            "failure": {
                "phase": failure.phase,
                "code": failure.code,
                "details": failure.details,
            },
        }, ensure_ascii=False, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

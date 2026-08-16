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
from itertools import accumulate
import json
import math
import os
import platform
import re
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
from scene_shader_compiler_cli import parse_args


SCRIPT_ROOT = Path(__file__).resolve().parent
DEFAULT_MANIFEST = SCRIPT_ROOT / "scene_shader_compiler_dependencies.json"
ALLOWED_STAGES = ("vertex", "fragment")
STAGE_SUFFIX = {"vertex": "vert", "fragment": "frag"}
ALLOWED_DIALECTS = ("glsl-450", "wallpaper-engine-glsl-like-v0")
VALUE_TYPES = {
    "bool", "int", "uint", "float",
    "ivec2", "ivec3", "ivec4",
    "uvec2", "uvec3", "uvec4",
    "vec2", "vec3", "vec4",
    "mat2", "mat3", "mat4",
}
DECLARATION = re.compile(
    r"^\s*(?P<storage>uniform|attribute|varying)\s+"
    r"(?P<type>[A-Za-z_][A-Za-z0-9_]*)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"(?P<array>\s*\[\s*(?P<count>[0-9]+)\s*\])?\s*;"
    r"(?P<comment>\s*(?://.*)?)$"
)
SCALAR_TEXTURE_ASSIGNMENT = re.compile(
    r"(?P<prefix>\bfloat\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*)"
    r"(?P<sample>texSample2D\([^;]+\))(?P<suffix>\s*;)"
)


class HarnessFailure(RuntimeError):
    def __init__(self, phase: str, code: str, details: list[str] | None = None) -> None:
        super().__init__(f"{phase}:{code}")
        self.phase = phase
        self.code = code
        self.details = details or []


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
    if payload.get("schemaVersion") != 1:
        raise HarnessFailure("request", "schema-version")
    request_id = payload.get("requestID")
    if not isinstance(request_id, str) or not request_id or len(request_id) > 128:
        raise HarnessFailure("request", "request-id")
    raw_stages = payload.get("stages")
    if not isinstance(raw_stages, list) or len(raw_stages) != 2:
        raise HarnessFailure("request", "stage-count")
    stages: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw in raw_stages:
        if not isinstance(raw, dict):
            raise HarnessFailure("request", "stage-shape")
        stage = raw.get("stage")
        entry_point = raw.get("entryPoint")
        source = raw.get("source")
        if stage not in ALLOWED_STAGES or stage in seen:
            raise HarnessFailure("request", "stage-identity")
        if entry_point != "main":
            raise HarnessFailure("request", "entry-point")
        if not isinstance(source, str) or not source:
            raise HarnessFailure("request", "source")
        encoded = source.encode("utf-8")
        if len(encoded) > limits.maximum_stage_source_bytes:
            raise HarnessFailure("request", "source-too-large", [str(stage)])
        if "\x00" in source:
            raise HarnessFailure("request", "source-nul", [str(stage)])
        seen.add(stage)
        stages.append({"stage": stage, "entryPoint": entry_point, "source": source})
    if seen != set(ALLOWED_STAGES):
        raise HarnessFailure("request", "stage-pair")
    return sorted(stages, key=lambda value: ALLOWED_STAGES.index(value["stage"]))


def validated_defines(payload: dict[str, Any]) -> dict[str, int]:
    raw = payload.get("defines", {})
    if not isinstance(raw, dict) or len(raw) > 128:
        raise HarnessFailure("request", "defines-shape")
    result: dict[str, int] = {}
    for name, value in raw.items():
        if not isinstance(name, str) or re.fullmatch(r"[A-Z_][A-Z0-9_]*", name) is None:
            raise HarnessFailure("request", "define-name", [str(name)])
        if isinstance(value, bool):
            result[name] = int(value)
        elif isinstance(value, int) and -(2 ** 31) <= value < 2 ** 31:
            result[name] = value
        else:
            raise HarnessFailure("request", "define-value", [name])
    return result


def _used_varying_components(body: str, name: str, width: int) -> set[str]:
    ordered = "xyzw"[:width]
    aliases = dict(zip("rgba", "xyzw"))
    used: set[str] = set()
    for match in re.finditer(
        rf"\b{re.escape(name)}\b(?P<swizzle>\.[xyzwrgba]{{1,4}})?",
        body,
    ):
        swizzle = match.group("swizzle")
        if swizzle is None:
            return set(ordered)
        used.update(aliases.get(component, component) for component in swizzle[1:])
    return used


def _prune_unused_varying_component_assignments(
    vertex_body: str,
    fragment_body: str,
    varying_shapes: dict[str, tuple[str, int | None]],
) -> tuple[str, int]:
    pruned = 0
    for name, (value_type, count) in varying_shapes.items():
        width_match = re.fullmatch(r"vec([2-4])", value_type)
        if count is not None or width_match is None:
            continue
        used = _used_varying_components(
            fragment_body, name, int(width_match.group(1))
        )
        aliases = dict(zip("rgba", "xyzw"))
        assignment = re.compile(
            rf"^[ \t]*{re.escape(name)}\.(?P<swizzle>[xyzwrgba]{{1,4}})"
            rf"\s*=\s*(?P<expression>[^;]*);[ \t]*$",
            re.MULTILINE,
        )

        def replacement(match: re.Match[str]) -> str:
            nonlocal pruned
            assigned = {
                aliases.get(component, component)
                for component in match.group("swizzle")
            }
            expression = match.group("expression")
            calls = re.findall(r"\b([A-Za-z_]\w*)\s*\(", expression)
            if assigned & used or any(
                call not in {"float", "int", "uint", "vec2", "vec3", "vec4"}
                for call in calls
            ):
                return match.group(0)
            if "++" in expression or "--" in expression:
                return match.group(0)
            if not re.fullmatch(r"[A-Za-z0-9_.,()\s+\-*/]+", expression):
                return match.group(0)
            pruned += 1
            return ""

        vertex_body = assignment.sub(replacement, vertex_body)
    return vertex_body, pruned


def normalize_wallpaper_engine_pair(
    stages: list[dict[str, str]],
    defines: dict[str, int],
) -> tuple[list[dict[str, str]], dict[str, Any]]:
    parsed: dict[str, dict[str, Any]] = {}
    uniform_shapes: dict[str, tuple[str, int | None]] = {}
    sampler_slots: dict[str, int] = {}
    varying_shapes: dict[str, tuple[str, int | None]] = {}
    attribute_shapes: dict[str, tuple[str, int | None]] = {}
    stage_varyings: dict[str, set[str]] = {stage: set() for stage in ALLOWED_STAGES}
    scalar_texture_rewrites = 0
    boolean_combo_rewrites = 0
    reserved_identifier_rewrites = 0

    for stage in stages:
        stage_name = stage["stage"]
        kept: list[str] = []
        declarations: list[tuple[str, str, str, int | None]] = []
        seen_declarations: set[tuple[str, str]] = set()
        for line in stage["source"].replace("\r\n", "\n").replace("\r", "\n").split("\n"):
            if line.lstrip().startswith("#version"):
                continue
            match = DECLARATION.fullmatch(line)
            if match is None:
                if re.match(r"^\s*(uniform|attribute|varying)\b", line):
                    raise HarnessFailure(
                        "normalization", "declaration-unsupported", [stage_name, line.strip()]
                    )
                kept.append(line)
                continue
            storage = match.group("storage")
            value_type = match.group("type")
            name = match.group("name")
            count = int(match.group("count")) if match.group("count") else None
            if count is not None and not (1 <= count <= 128):
                raise HarnessFailure("normalization", "array-count", [stage_name, name])
            declaration_identity = (storage, name)
            if declaration_identity in seen_declarations:
                raise HarnessFailure(
                    "normalization", "declaration-duplicate", [stage_name, storage, name]
                )
            seen_declarations.add(declaration_identity)
            declarations.append((storage, value_type, name, count))
            if storage == "uniform":
                if value_type.startswith("sampler"):
                    slot_match = re.fullmatch(r"g_Texture([0-7])", name)
                    if value_type != "sampler2D" or slot_match is None or count is not None:
                        raise HarnessFailure(
                            "normalization", "sampler-unsupported", [stage_name, name, value_type]
                        )
                    slot = int(slot_match.group(1))
                    existing_slot = sampler_slots.setdefault(name, slot)
                    if existing_slot != slot:
                        raise HarnessFailure("normalization", "sampler-conflict", [name])
                else:
                    if value_type not in VALUE_TYPES:
                        raise HarnessFailure(
                            "normalization", "uniform-type", [stage_name, name, value_type]
                        )
                    shape = (value_type, count)
                    existing = uniform_shapes.setdefault(name, shape)
                    if existing != shape:
                        raise HarnessFailure("normalization", "uniform-conflict", [name])
            elif storage == "attribute":
                if stage_name != "vertex" or value_type not in VALUE_TYPES or count is not None:
                    raise HarnessFailure("normalization", "attribute-unsupported", [stage_name, name])
                shape = (value_type, count)
                existing = attribute_shapes.setdefault(name, shape)
                if existing != shape:
                    raise HarnessFailure("normalization", "attribute-conflict", [name])
            elif storage == "varying":
                if value_type not in VALUE_TYPES or (count is not None and count > 16):
                    raise HarnessFailure("normalization", "varying-type", [stage_name, name])
                shape = (value_type, count)
                existing = varying_shapes.setdefault(name, shape)
                if existing != shape:
                    raise HarnessFailure("normalization", "varying-conflict", [name])
                stage_varyings[stage_name].add(name)
        body = "\n".join(kept)
        body, replacements = re.subn(r"\bsample\b", "mwx_sample", body)
        reserved_identifier_rewrites += replacements
        if stage_name == "fragment":
            body = re.sub(r"\bgl_FragColor\b", "mwxFragColor", body)
            body, replacements = SCALAR_TEXTURE_ASSIGNMENT.subn(
                r"\g<prefix>\g<sample>.r\g<suffix>", body
            )
            scalar_texture_rewrites += replacements
        for define_name in defines:
            body, replacements = re.subn(
                rf"\b{re.escape(define_name)}\s*\?",
                f"({define_name} != 0) ?",
                body,
            )
            boolean_combo_rewrites += replacements
        parsed[stage_name] = {"body": body, "declarations": declarations}

    expected_attributes = {
        "a_Position": ("vec3", None),
        "a_TexCoord": ("vec2", None),
    }
    if attribute_shapes != expected_attributes:
        raise HarnessFailure(
            "normalization", "vertex-attributes-unsupported",
            sorted(attribute_shapes),
        )
    missing_vertex_outputs = stage_varyings["fragment"] - stage_varyings["vertex"]
    if missing_vertex_outputs:
        raise HarnessFailure(
            "normalization", "varying-link",
            sorted(missing_vertex_outputs),
        )

    if "mwxRenderSize" in uniform_shapes:
        raise HarnessFailure("normalization", "reserved-uniform", ["mwxRenderSize"])
    uses_target_pixel_position = re.search(
        r"\bg_ModelViewProjectionMatrix\b", parsed["vertex"]["body"]
    ) is not None
    position_expression = (
        "(mwxPosition - vec2(0.5)) * mwxRenderSize"
        if uses_target_pixel_position
        else "mwxPosition * 2.0 - vec2(1.0)"
    )
    vertex_body, main_replacements = re.subn(
        r"\bvoid\s+main\s*\(\s*\)\s*\{",
        f"""void main() {{
    const vec2 mwxCoordinates[4] = vec2[4](
        vec2(0.0, 1.0), vec2(1.0, 1.0),
        vec2(0.0, 0.0), vec2(1.0, 0.0));
    vec2 a_TexCoord = mwxCoordinates[gl_VertexIndex];
    vec2 mwxPosition = vec2(a_TexCoord.x, 1.0 - a_TexCoord.y);
    vec3 a_Position = vec3({position_expression}, 0.0);""",
        parsed["vertex"]["body"],
        count=1,
    )
    if main_replacements != 1:
        raise HarnessFailure("normalization", "vertex-main")
    vertex_body, varying_component_prunes = (
        _prune_unused_varying_component_assignments(
            vertex_body,
            parsed["fragment"]["body"],
            varying_shapes,
        )
    )
    parsed["vertex"]["body"] = vertex_body

    attribute_order = sorted(
        attribute_shapes,
        key=lambda name: ({"a_Position": 0, "a_TexCoord": 1}.get(name, 2), name),
    )
    varying_order = sorted(varying_shapes)
    varying_spans = [varying_shapes[name][1] or 1 for name in varying_order]
    varying_locations = dict(zip(varying_order, [0, *accumulate(varying_spans)]))
    active_uniform_names = {
        name
        for name in uniform_shapes
        if any(
            re.search(rf"\b{re.escape(name)}\b", parsed[stage]["body"])
            for stage in ALLOWED_STAGES
        )
    }
    uniform_lines = [
        f"    {value_type} {name}{f'[{count}]' if count is not None else ''};"
        for name, (value_type, count) in sorted(uniform_shapes.items())
        if name in active_uniform_names
    ]
    uniform_lines.append("    vec2 mwxRenderSize;")
    define_lines = [f"#define {name} {value}" for name, value in sorted(defines.items())]
    compatibility_lines = [
        "#define mul(x, y) ((y) * (x))",
        "#define texSample2D texture",
        *[f"#define CAST{count}(x) vec{count}(x)" for count in range(2, 5)],
        "#define frac fract",
        "#define saturate(x) clamp((x), 0.0, 1.0)",
        "#define atan2 atan",
    ]

    normalized: list[dict[str, str]] = []
    for stage in stages:
        stage_name = stage["stage"]
        interface: list[str] = []
        active_sampler_lines = [
            f"layout(set = 0, binding = {slot}) uniform sampler2D {name};"
            for name, slot in sorted(sampler_slots.items(), key=lambda item: item[1])
            if re.search(rf"\b{re.escape(name)}\b", parsed[stage_name]["body"])
        ]
        for name in varying_order:
            if name not in stage_varyings[stage_name]:
                continue
            value_type, count = varying_shapes[name]
            suffix = f"[{count}]" if count is not None else ""
            direction = "out" if stage_name == "vertex" else "in"
            interface.append(
                f"layout(location = {varying_locations[name]}) "
                f"{direction} {value_type} {name}{suffix};"
            )
        if stage_name == "fragment":
            interface.append("layout(location = 0) out vec4 mwxFragColor;")
        uniform_block = (
            "layout(std140, set = 0, binding = 8) uniform MWXUniforms {\n"
            + "\n".join(uniform_lines)
            + "\n};\n"
        )
        source = "\n".join([
            "#version 450",
            *define_lines,
            *compatibility_lines,
            uniform_block.rstrip(),
            *active_sampler_lines,
            *interface,
            parsed[stage_name]["body"],
        ]).strip() + "\n"
        normalized.append({
            "stage": stage_name,
            "entryPoint": stage["entryPoint"],
            "source": source,
        })
    return normalized, {
        "dialect": "wallpaper-engine-glsl-like-v0",
        "uniformCount": len(uniform_shapes),
        "activeUniformCount": len(active_uniform_names),
        "inactiveUniformsPruned": len(uniform_shapes) - len(active_uniform_names),
        "unusedVaryingComponentAssignmentsPruned": varying_component_prunes,
        "samplerSlots": sorted(sampler_slots.values()),
        "attributeCount": len(attribute_shapes),
        "varyingCount": len(varying_shapes),
        "defineCount": len(defines),
        "scalarTextureChannelRewrites": scalar_texture_rewrites,
        "booleanComboTernaryRewrites": boolean_combo_rewrites,
        "reservedIdentifierRewrites": reserved_identifier_rewrites,
        "vertexPositionInput": (
            "target-pixels" if uses_target_pixel_position else "clip-space"
        ),
    }


def normalize_request(
    payload: dict[str, Any],
    stages: list[dict[str, str]],
) -> tuple[list[dict[str, str]], dict[str, Any]]:
    dialect = payload.get("sourceDialect", "glsl-450")
    if dialect not in ALLOWED_DIALECTS:
        raise HarnessFailure("request", "source-dialect", [str(dialect)])
    defines = validated_defines(payload)
    if dialect == "glsl-450":
        if defines:
            raise HarnessFailure("request", "defines-with-standard-glsl")
        return stages, {"dialect": dialect, "transformed": False}
    normalized, summary = normalize_wallpaper_engine_pair(stages, defines)
    summary["transformed"] = True
    return normalized, summary


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
                    backend_id="glslang-spirv-cross-msl-v1",
                    compiled_stages=compiled,
                    stage_sources={stage["stage"]: stage["source"] for stage in stages},
                    msl_sources={
                        stage["stage"]: (root / f"{stage['stage']}.metal").read_text(
                            encoding="utf-8"
                        )
                        for stage in stages
                    },
                    maximum_artifact_bytes=limits.maximum_artifact_bytes,
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

#!/usr/bin/env python3
"""Build a bounded Program artifact from validated compiler-stage outputs."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any


class ArtifactFailure(RuntimeError):
    pass


TYPE_NAMES = {
    "int": "int",
    "uint": "uint",
    "float": "float",
    "ivec2": "int2",
    "ivec3": "int3",
    "ivec4": "int4",
    "uvec2": "uint2",
    "uvec3": "uint3",
    "uvec4": "uint4",
    "vec2": "float2",
    "vec3": "float3",
    "vec4": "float4",
    "mat2": "float2x2",
    "mat3": "float3x3",
    "mat4": "float4x4",
}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def request_cache_key(request: dict[str, Any]) -> str:
    raw_stages = request.get("stages")
    if not isinstance(raw_stages, list):
        raise ArtifactFailure("request-stages")
    sources: dict[str, str] = {}
    for stage in raw_stages:
        if not isinstance(stage, dict):
            raise ArtifactFailure("request-stage")
        name, source = stage.get("stage"), stage.get("source")
        if name not in ("vertex", "fragment") or not isinstance(source, str):
            raise ArtifactFailure("request-stage")
        sources[name] = source
    if set(sources) != {"vertex", "fragment"}:
        raise ArtifactFailure("request-pair")
    digest = hashlib.sha256()
    for value in (
        "mwx-generic-shader-request-v1",
        str(request.get("sourceDialect", "glsl-450")),
        sources["vertex"],
        sources["fragment"],
        json.dumps(request.get("defines", {}), sort_keys=True, separators=(",", ":")),
    ):
        encoded = value.encode("utf-8")
        digest.update(len(encoded).to_bytes(8, "big"))
        digest.update(encoded)
    return digest.hexdigest()


def _uniform_layout(reflection: dict[str, Any]) -> tuple[list[dict[str, Any]], int]:
    ubos = reflection.get("ubos")
    types = reflection.get("types")
    if not isinstance(ubos, list) or len(ubos) != 1 or not isinstance(types, dict):
        raise ArtifactFailure("uniform-block")
    ubo = ubos[0]
    if not isinstance(ubo, dict) or ubo.get("set") != 0 or ubo.get("binding") != 8:
        raise ArtifactFailure("uniform-binding")
    raw_type = types.get(ubo.get("type"))
    if not isinstance(raw_type, dict) or not isinstance(raw_type.get("members"), list):
        raise ArtifactFailure("uniform-type")
    fields: list[dict[str, Any]] = []
    for member in raw_type["members"]:
        if not isinstance(member, dict):
            raise ArtifactFailure("uniform-member")
        name, value_type, offset = member.get("name"), member.get("type"), member.get("offset")
        if (
            not isinstance(name, str)
            or value_type not in TYPE_NAMES
            or not isinstance(offset, int)
            or member.get("array") is not None
        ):
            raise ArtifactFailure("uniform-member")
        fields.append({
            "name": name,
            "authoredName": name,
            "type": TYPE_NAMES[value_type],
            "offset": offset,
        })
    block_size = ubo.get("block_size")
    if not isinstance(block_size, int) or block_size < 0 or block_size > 4096:
        raise ArtifactFailure("uniform-size")
    byte_size = (block_size + 15) // 16 * 16
    return fields, byte_size


def _sample_end(source: str, start: int) -> int | None:
    depth = 0
    for index in range(start, len(source)):
        character = source[index]
        if character == "(":
            depth += 1
        elif character == ")":
            depth -= 1
            if depth == 0:
                return index + 1
    return None


def _channel_use(source: str, name: str) -> str:
    starts = [match.start() for match in re.finditer(rf"\b{re.escape(name)}\.sample\s*\(", source)]
    if not starts:
        raise ArtifactFailure("texture-unused")
    for start in starts:
        opening = source.find("(", start)
        end = _sample_end(source, opening)
        if end is None or re.match(r"\s*\.x\b", source[end:]) is None:
            return "unproven"
    return "redOnly"


def _texture_bindings(compiled_stages: list[dict[str, Any]], msl: str) -> list[dict[str, Any]]:
    bindings: dict[int, str] = {}
    for stage in compiled_stages:
        reflection = stage.get("reflection")
        if not isinstance(reflection, dict):
            raise ArtifactFailure("reflection")
        for texture in reflection.get("textures", []):
            if not isinstance(texture, dict):
                raise ArtifactFailure("texture")
            name, slot = texture.get("name"), texture.get("binding")
            if (
                not isinstance(name, str)
                or not isinstance(slot, int)
                or name != f"g_Texture{slot}"
                or not 0 <= slot < 8
            ):
                raise ArtifactFailure("texture")
            if slot in bindings and bindings[slot] != name:
                raise ArtifactFailure("texture-conflict")
            bindings[slot] = name
    return [
        {"name": name, "slot": slot, "channelUse": _channel_use(msl, name)}
        for slot, name in sorted(bindings.items())
    ]


def _passthrough_color_transfer(fragment_msl: str) -> dict[str, Any]:
    assignments = re.findall(r"^\s*out\.mwxFragColor\s*=.*;$", fragment_msl, re.MULTILINE)
    if len(assignments) != 1:
        raise ArtifactFailure("color-assignment")
    match = re.fullmatch(
        r"\s*out\.mwxFragColor\s*=\s*g_Texture([0-7])\.sample\([^;]+\);",
        assignments[0],
    )
    if match is None:
        raise ArtifactFailure("color-transfer")
    return {"kind": "passthrough", "slot": int(match.group(1))}


def build_program_artifact(
    *,
    request_key: str,
    backend_id: str,
    compiled_stages: list[dict[str, Any]],
    stage_sources: dict[str, str],
    msl_sources: dict[str, str],
    maximum_artifact_bytes: int,
) -> dict[str, Any]:
    if set(stage_sources) != {"vertex", "fragment"} or set(msl_sources) != set(stage_sources):
        raise ArtifactFailure("stage-pair")
    if any(re.search(r"\b(for|while|do)\b", source) for source in stage_sources.values()):
        raise ArtifactFailure("loop-unbounded")
    stages = {stage.get("stage"): stage for stage in compiled_stages}
    if set(stages) != {"vertex", "fragment"}:
        raise ArtifactFailure("compiled-pair")
    vertex_layout = _uniform_layout(stages["vertex"]["reflection"])
    fragment_layout = _uniform_layout(stages["fragment"]["reflection"])
    if vertex_layout != fragment_layout:
        raise ArtifactFailure("uniform-stage-mismatch")
    vertex_msl = msl_sources["vertex"].replace("MWXUniforms", "MWXVertexUniforms")
    fragment_msl = msl_sources["fragment"].replace(
        "MWXUniforms", "MWXFragmentUniforms"
    )
    if vertex_msl == msl_sources["vertex"] or fragment_msl == msl_sources["fragment"]:
        raise ArtifactFailure("uniform-struct-name")
    metal_source = vertex_msl.rstrip() + "\n\n" + fragment_msl.lstrip()
    if len(metal_source.encode("utf-8")) > maximum_artifact_bytes:
        raise ArtifactFailure("metal-size")
    return {
        "schemaVersion": 1,
        "kind": "scene-generic-shader-program-artifact",
        "backendID": backend_id,
        "requestKey": request_key,
        "routeState": "prefer-generic",
        "program": {
            "metalSource": metal_source,
            "metalSourceSHA256": sha256_bytes(metal_source.encode("utf-8")),
            "vertexFunctionName": "mwxGenericVertex",
            "fragmentFunctionName": "mwxGenericFragment",
            "uniformBufferIndex": 8,
            "uniformLayout": {"fields": vertex_layout[0], "byteSize": vertex_layout[1]},
            "textureBindings": _texture_bindings(compiled_stages, metal_source),
            "staticLoopWork": 0,
            "colorTransfer": _passthrough_color_transfer(msl_sources["fragment"]),
        },
    }

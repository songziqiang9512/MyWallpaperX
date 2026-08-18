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

TYPE_ALIGNMENT = {
    "int": 4, "uint": 4, "float": 4,
    "int2": 8, "uint2": 8, "float2": 8, "float2x2": 8,
    "int3": 16, "int4": 16, "uint3": 16, "uint4": 16,
    "float3": 16, "float4": 16, "float3x3": 16, "float4x4": 16,
}

TYPE_BYTE_SIZE = {
    "int": 4, "uint": 4, "float": 4,
    "int2": 8, "uint2": 8, "float2": 8,
    "int3": 16, "int4": 16, "uint3": 16, "uint4": 16,
    "float3": 16, "float4": 16,
    "float2x2": 16, "float3x3": 48, "float4x4": 64,
}

SPV_UNSAFE_ARRAY = re.compile(
    r"template<typename T, size_t Num>\s+struct spvUnsafeArray\s*\{.*?\n\};",
    re.DOTALL,
)


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
        "mwx-generic-shader-request-v3",
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


def _aligned_uniform_layout(fields: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], int]:
    aligned: list[dict[str, Any]] = []
    offset = 0
    for field in fields:
        value_type = field["type"]
        alignment = TYPE_ALIGNMENT[value_type]
        offset = (offset + alignment - 1) // alignment * alignment
        aligned.append({**field, "offset": offset})
        offset += TYPE_BYTE_SIZE[value_type]
    return aligned, (offset + 15) // 16 * 16


def _active_uniform_fields(
    fields: list[dict[str, Any]],
    msl: str,
) -> list[dict[str, Any]]:
    pattern = re.compile(r"struct\s+MWXUniforms\s*\{(?P<body>.*?)\};", re.DOTALL)
    matches = list(pattern.finditer(msl))
    if len(matches) != 1:
        raise ArtifactFailure("uniform-struct")
    match = matches[0]
    executable = msl[:match.start()] + msl[match.end():]
    executable = re.sub(r"/\*.*?\*/|//[^\n]*", " ", executable, flags=re.DOTALL)
    return [
        field for field in fields
        if field["authoredName"] == "mwxRenderSize"
        or re.search(
            rf"\.\s*{re.escape(field['authoredName'])}\b", executable
        ) is not None
    ]


def _stage_local_uniform_layout(
    vertex_fields: list[dict[str, Any]],
    fragment_fields: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], int, dict[str, str], dict[str, str]]:
    shared_internal = "mwxRenderSize"
    vertex_names = {field["authoredName"] for field in vertex_fields}
    fragment_names = {field["authoredName"] for field in fragment_fields}
    duplicated = (vertex_names & fragment_names) - {shared_internal}
    combined: list[dict[str, Any]] = []
    mappings: dict[str, dict[str, str]] = {"vertex": {}, "fragment": {}}
    internal: dict[str, Any] | None = None
    for stage, fields, prefix in (
        ("vertex", vertex_fields, "mwxV_"),
        ("fragment", fragment_fields, "mwxF_"),
    ):
        for field in fields:
            authored = field["authoredName"]
            if authored == shared_internal:
                if internal is not None and internal["type"] != field["type"]:
                    raise ArtifactFailure("uniform-stage-mismatch")
                internal = {**field, "name": shared_internal}
                mappings[stage][authored] = shared_internal
                continue
            name = prefix + authored if authored in duplicated else authored
            combined.append({**field, "name": name, "stage": stage})
            mappings[stage][authored] = name
    if internal is not None:
        combined.append(internal)
    fields, byte_size = _aligned_uniform_layout(combined)
    return fields, byte_size, mappings["vertex"], mappings["fragment"]


def _normalize_uniform_struct(
    msl: str,
    fields: list[dict[str, Any]],
    names: dict[str, str],
) -> str:
    pattern = re.compile(r"struct\s+MWXUniforms\s*\{(?P<body>.*?)\};", re.DOTALL)
    matches = list(pattern.finditer(msl))
    if len(matches) != 1:
        raise ArtifactFailure("uniform-struct")
    match = matches[0]
    body = "\n" + "\n".join(
        f"    {field['type']} {field['name']};" for field in fields
    ) + "\n"
    result = msl[:match.start("body")] + body + msl[match.end("body"):]
    for authored, field_name in names.items():
        if authored != field_name:
            result = re.sub(
                rf"\.{re.escape(authored)}\b", f".{field_name}", result
            )
    return result


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


def _premultiplied_accumulator(
    fragment_msl: str, assignment: str
) -> dict[str, Any] | None:
    output = re.fullmatch(
        r"\s*out\.mwxFragColor\s*=\s*(?P<name>[A-Za-z_]\w*)\s*;",
        assignment,
    )
    if output is None:
        return None
    color = output.group("name")
    helper = re.search(
        r"float3\s+(?P<function>[A-Za-z_]\w*)\s*\(\s*int\s+\w+\s*,\s*"
        r"thread\s+const\s+float3&\s*(?P<a>[A-Za-z_]\w*)\s*,\s*"
        r"thread\s+const\s+float3&\s*(?P<b>[A-Za-z_]\w*)\s*,\s*"
        r"thread\s+const\s+float&\s*(?P<coverage>[A-Za-z_]\w*)\s*\)\s*"
        r"\{\s*return\s+(?P=a)\s*\+\s*\(\s*(?P=b)\s*\*\s*"
        r"(?P=coverage)\s*\)\s*;\s*\}",
        fragment_msl,
        re.DOTALL,
    )
    if helper is None:
        return None
    function = re.escape(helper.group("function"))
    name = re.escape(color)
    flow = re.search(
        rf"float4\s+{name}\s*=\s*float4\(\s*0(?:\.0+)?\s*\)\s*;.*?"
        rf"float3\s+(?P<input>[A-Za-z_]\w*)\s*=\s*{name}\.xyz\s*;\s*"
        rf"float3\s+(?P<source>[A-Za-z_]\w*)\s*=\s*[^;]+;\s*"
        rf"float\s+(?P<factor>[A-Za-z_]\w*)\s*=\s*"
        rf"(?P<coverage>[A-Za-z_]\w*)\s*;\s*"
        rf"float3\s+(?P<result>[A-Za-z_]\w*)\s*=\s*{function}\(\s*31\s*,\s*"
        rf"(?P=input)\s*,\s*(?P=source)\s*,\s*(?P=factor)\s*\)\s*;\s*"
        rf"{name}\.x\s*=\s*(?P=result)\.x\s*;\s*"
        rf"{name}\.y\s*=\s*(?P=result)\.y\s*;\s*"
        rf"{name}\.z\s*=\s*(?P=result)\.z\s*;\s*"
        rf"{name}\.w\s*=\s*fast::max\(\s*{name}\.w\s*,\s*"
        rf"(?P=coverage)\s*\)\s*;.*?"
        rf"out\.mwxFragColor\s*=\s*{name}\s*;",
        fragment_msl,
        re.DOTALL,
    )
    if flow is None:
        return None
    writes = re.findall(
        rf"^\s*{name}\.(?P<member>[xyzw])\s*=", fragment_msl, re.MULTILINE
    )
    if writes != ["x", "y", "z", "w"]:
        return None
    return {"kind": "premultiplied"}


def _premultiplied_alpha_attenuation(
    fragment_msl: str,
) -> tuple[str, dict[str, Any]] | None:
    assignments = re.findall(
        r"^[ \t]*out\.mwxFragColor\s*=.*;$", fragment_msl, re.MULTILINE
    )
    if len(assignments) != 1:
        return None
    output = re.fullmatch(
        r"[ \t]*out\.mwxFragColor\s*=\s*(?P<name>[A-Za-z_]\w*)\s*;",
        assignments[0],
    )
    if output is None:
        return None
    name = output.group("name")
    escaped = re.escape(name)
    declaration = re.findall(
        rf"^[ \t]*float4\s+{escaped}\s*=\s*"
        rf"g_Texture(?P<slot>[0-7])\.sample\([^;]+\)\s*;$",
        fragment_msl,
        re.MULTILINE,
    )
    attenuation = list(re.finditer(
        rf"^(?P<indent>[ \t]*){escaped}\.w\s*\*=\s*"
        rf"(?P<factor>[^;]+)\s*;$",
        fragment_msl,
        re.MULTILINE,
    ))
    if len(declaration) != 1 or len(attenuation) != 1:
        return None
    if len(re.findall(rf"\b{escaped}\b", fragment_msl)) != 3:
        return None
    factor = attenuation[0].group("factor")
    if re.search(rf"\b{escaped}\b", factor):
        return None
    writes = re.findall(
        rf"^\s*{escaped}(?:\.(?P<member>[xyzwrgba]{{1,4}}))?\s*(?:[+\-*/]?=)",
        fragment_msl,
        re.MULTILINE,
    )
    if writes != ["w"]:
        return None
    replacement = f"{attenuation[0].group('indent')}{name} *= {factor};"
    transformed = (
        fragment_msl[:attenuation[0].start()]
        + replacement
        + fragment_msl[attenuation[0].end():]
    )
    return transformed, {"kind": "straight-alpha", "slot": int(declaration[0])}


def _passthrough_color_transfer(fragment_msl: str) -> dict[str, Any]:
    assignments = re.findall(r"^\s*out\.mwxFragColor\s*=.*;$", fragment_msl, re.MULTILINE)
    if len(assignments) != 1:
        raise ArtifactFailure("color-assignment")
    match = re.fullmatch(
        r"\s*out\.mwxFragColor\s*=\s*g_Texture([0-7])\.sample\([^;]+\);",
        assignments[0],
    )
    if match is None:
        interpolated = _interpolated_color_transfer(fragment_msl, assignments[0])
        if interpolated is not None:
            return interpolated
        premultiplied = _premultiplied_accumulator(fragment_msl, assignments[0])
        if premultiplied is not None:
            return premultiplied
        opaque = re.fullmatch(
            r"\s*out\.mwxFragColor\s*=\s*float4\(.+,\s*1(?:\.0+)?\s*\);",
            assignments[0],
        )
        if opaque is not None:
            return {"kind": "opaque"}
        raise ArtifactFailure("color-transfer")
    return {"kind": "passthrough", "slot": int(match.group(1))}


def _interpolated_color_transfer(
    fragment_msl: str, assignment: str
) -> dict[str, Any] | None:
    output = re.fullmatch(
        r"\s*out\.mwxFragColor\s*=\s*mix\(\s*"
        r"(?P<first>[A-Za-z_]\w*)\s*,\s*"
        r"(?P<second>[A-Za-z_]\w*)\s*,\s*"
        r"(?P<weight>[A-Za-z_]\w*|[-+]?(?:\d+(?:\.\d*)?|\.\d+))\s*\)\s*;",
        assignment,
    )
    if output is None:
        return None

    slots: list[int] = []
    for group in ("first", "second"):
        name = output.group(group)
        declaration = re.findall(
            rf"^[ \t]*float4\s+{re.escape(name)}\s*=\s*"
            rf"g_Texture(?P<slot>[0-7])\.sample\([^;]+\)\s*;$",
            fragment_msl,
            re.MULTILINE,
        )
        if len(declaration) != 1 or len(re.findall(rf"\b{re.escape(name)}\b", fragment_msl)) != 2:
            return None
        slots.append(int(declaration[0]))

    weight = output.group("weight")
    if re.fullmatch(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)", weight) is None:
        scalar_declarations = re.findall(
            rf"^[ \t]*float\s+{re.escape(weight)}\s*=\s*[^;]+;$",
            fragment_msl,
            re.MULTILINE,
        )
        if len(scalar_declarations) != 1:
            return None

    slots = sorted(set(slots))
    if len(slots) < 2:
        return None
    return {"kind": "interpolated-color", "slots": slots}


def _without_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", " ", source, flags=re.DOTALL)
    return re.sub(r"//[^\n]*", " ", source)


def _static_loop_work(stage_sources: dict[str, str]) -> int:
    total = 0
    loop = re.compile(
        r"\bfor\s*\(\s*int\s+(?P<name>[A-Za-z_]\w*)\s*=\s*0\s*;\s*"
        r"(?P=name)\s*<\s*(?P<limit>\d+)\s*;\s*"
        r"(?:(?:\+\+\s*(?P=name))|(?:(?P=name)\s*\+\+))\s*\)"
    )
    for source in stage_sources.values():
        body = _without_comments(source)
        for match in loop.finditer(body):
            limit = int(match.group("limit"))
            if not 1 <= limit <= 64:
                raise ArtifactFailure("loop-bound")
            total += limit
        remainder = loop.sub("", body)
        if re.search(r"\b(for|while|do)\b", remainder):
            raise ArtifactFailure("loop-unbounded")
    if total > 256:
        raise ArtifactFailure("loop-budget")
    return total


def _deduplicate_stage_helpers(vertex_msl: str, fragment_msl: str) -> tuple[str, str]:
    vertex_helper = SPV_UNSAFE_ARRAY.search(vertex_msl)
    fragment_helper = SPV_UNSAFE_ARRAY.search(fragment_msl)
    if vertex_helper is None or fragment_helper is None:
        return vertex_msl, fragment_msl
    if vertex_helper.group(0) != fragment_helper.group(0):
        raise ArtifactFailure("stage-helper-conflict")
    fragment_msl = (
        fragment_msl[:fragment_helper.start()]
        + fragment_msl[fragment_helper.end():]
    )
    return vertex_msl, fragment_msl


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
    static_loop_work = _static_loop_work(stage_sources)
    stages = {stage.get("stage"): stage for stage in compiled_stages}
    if set(stages) != {"vertex", "fragment"}:
        raise ArtifactFailure("compiled-pair")
    vertex_layout = _uniform_layout(stages["vertex"]["reflection"])
    fragment_layout = _uniform_layout(stages["fragment"]["reflection"])
    uniform_layout = _stage_local_uniform_layout(
        _active_uniform_fields(vertex_layout[0], msl_sources["vertex"]),
        _active_uniform_fields(fragment_layout[0], msl_sources["fragment"]),
    )
    fragment_color_preparation = _premultiplied_alpha_attenuation(
        msl_sources["fragment"]
    )
    prepared_fragment_msl = (
        fragment_color_preparation[0]
        if fragment_color_preparation is not None
        else msl_sources["fragment"]
    )
    color_transfer = (
        fragment_color_preparation[1]
        if fragment_color_preparation is not None
        else _passthrough_color_transfer(msl_sources["fragment"])
    )
    vertex_msl = _normalize_uniform_struct(
        msl_sources["vertex"], uniform_layout[0], uniform_layout[2]
    ).replace(
        "MWXUniforms", "MWXVertexUniforms"
    )
    fragment_msl = _normalize_uniform_struct(
        prepared_fragment_msl, uniform_layout[0], uniform_layout[3]
    ).replace(
        "MWXUniforms", "MWXFragmentUniforms"
    )
    if vertex_msl == msl_sources["vertex"] or fragment_msl == msl_sources["fragment"]:
        raise ArtifactFailure("uniform-struct-name")
    vertex_msl, fragment_msl = _deduplicate_stage_helpers(vertex_msl, fragment_msl)
    metal_source = vertex_msl.rstrip() + "\n\n" + fragment_msl.lstrip()
    if len(metal_source.encode("utf-8")) > maximum_artifact_bytes:
        raise ArtifactFailure("metal-size")
    return {
        "schemaVersion": 3,
        "kind": "scene-generic-shader-program-artifact",
        "backendID": backend_id,
        "requestKey": request_key,
        "program": {
            "metalSource": metal_source,
            "metalSourceSHA256": sha256_bytes(metal_source.encode("utf-8")),
            "vertexFunctionName": "mwxGenericVertex",
            "fragmentFunctionName": "mwxGenericFragment",
            "uniformBufferIndex": 8,
            "uniformLayout": {
                "fields": uniform_layout[0], "byteSize": uniform_layout[1]
            },
            "textureBindings": _texture_bindings(compiled_stages, metal_source),
            "staticLoopWork": static_loop_work,
            "fragmentOutputChannelUse": "unproven",
            "colorTransfer": color_transfer,
        },
    }

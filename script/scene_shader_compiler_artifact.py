#!/usr/bin/env python3
"""Build a bounded Program artifact from validated compiler-stage outputs."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

from scene_shader_compiler_msl_function_contract import (
    call_arguments as _call_arguments,
    function_body as _function_body,
    safe_carrier_parameter as _safe_carrier_parameter,
    safe_initial_carrier_flow as _safe_initial_carrier_flow,
    sample_end as _sample_end,
)
from scene_shader_compiler_loop_budget import static_loop_work as _static_loop_work
from scene_shader_compiler_passthrough_contract import aliased_texture_passthrough
from scene_shader_compiler_color_transfer_contract import (
    IndependentSignalContractFailure,
    expected_color_transfer_key,
    independent_signal_static_loop_work,
    parse_expected_transfer,
    prepare_independent_signal_contract,
)


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
TEXTURE_TRANSFORM_FIELD = re.compile(r"mwxTexture(?P<slot>[0-7])Transform(?P<part>[01])")


def expected_independent_color_transfer(value: Any) -> dict[str, Any] | None:
    try:
        return parse_expected_transfer(value)
    except IndependentSignalContractFailure as error:
        raise ArtifactFailure(error.code) from error


def expected_color_transfer_for_output(
    output_semantics: Any, value: Any
) -> dict[str, Any] | None:
    if output_semantics not in ("color", "red-green-unorm"):
        raise ArtifactFailure("output-semantics")
    if output_semantics == "red-green-unorm" and value is not None:
        raise ArtifactFailure("expected-color-transfer")
    return None if output_semantics != "color" else (
        expected_independent_color_transfer(value)
    )


def request_cache_key(request: dict[str, Any]) -> str:
    if request.get("schemaVersion") != 4:
        raise ArtifactFailure("request-schema")
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
    output_semantics = request.get("outputSemantics")
    expected = expected_color_transfer_for_output(
        output_semantics, request.get("expectedColorTransfer")
    )
    expected_key = expected_color_transfer_key(expected)
    digest = hashlib.sha256()
    for value in (
        "mwx-generic-shader-request-v9",
        str(request.get("sourceDialect", "glsl-450")),
        output_semantics,
        sources["vertex"],
        sources["fragment"],
        expected_key,
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
        dimensions = member.get("array")
        array_count = dimensions[0] if (
            isinstance(dimensions, list) and len(dimensions) == 1
            and isinstance(dimensions[0], int)
        ) else None
        audio_array = (
            value_type == "float"
            and array_count in (16, 32, 64)
            and name in (
                f"g_AudioSpectrum{array_count}Left",
                f"g_AudioSpectrum{array_count}Right",
            )
        )
        if (
            not isinstance(name, str)
            or value_type not in TYPE_NAMES
            or not isinstance(offset, int)
            or (dimensions is not None and not audio_array)
        ):
            raise ArtifactFailure("uniform-member")
        field = {
            "name": name,
            "authoredName": name,
            "type": TYPE_NAMES[value_type],
            "offset": offset,
        }
        if array_count is not None:
            field["arrayCount"] = array_count
        fields.append(field)
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
        offset += TYPE_BYTE_SIZE[value_type] * field.get("arrayCount", 1)
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
    def is_shared_internal(name: str) -> bool:
        return name == "mwxRenderSize" or TEXTURE_TRANSFORM_FIELD.fullmatch(name) is not None

    vertex_names = {field["authoredName"] for field in vertex_fields}
    fragment_names = {field["authoredName"] for field in fragment_fields}
    duplicated = {
        name for name in vertex_names & fragment_names
        if not is_shared_internal(name)
    }
    combined: list[dict[str, Any]] = []
    mappings: dict[str, dict[str, str]] = {"vertex": {}, "fragment": {}}
    shared: dict[str, dict[str, Any]] = {}
    for stage, fields, prefix in (
        ("vertex", vertex_fields, "mwxV_"),
        ("fragment", fragment_fields, "mwxF_"),
    ):
        for field in fields:
            authored = field["authoredName"]
            if is_shared_internal(authored):
                previous = shared.get(authored)
                shape = (field["type"], field.get("arrayCount"))
                if previous is not None and shape != (
                    previous["type"], previous.get("arrayCount")
                ):
                    raise ArtifactFailure("uniform-stage-mismatch")
                shared[authored] = {**field, "name": authored}
                mappings[stage][authored] = authored
                continue
            name = prefix + authored if authored in duplicated else authored
            combined.append({**field, "name": name, "stage": stage})
            mappings[stage][authored] = name
    combined.extend(shared[name] for name in sorted(shared))
    fields, byte_size = _aligned_uniform_layout(combined)
    return fields, byte_size, mappings["vertex"], mappings["fragment"]


def _validate_texture_transform_layout(
    fields: list[dict[str, Any]],
    texture_bindings: list[dict[str, Any]],
) -> None:
    expected = {
        (binding["slot"], part)
        for binding in texture_bindings
        for part in (0, 1)
    }
    observed: set[tuple[int, int]] = set()
    for field in fields:
        match = TEXTURE_TRANSFORM_FIELD.fullmatch(field["authoredName"])
        if match is None:
            continue
        key = (int(match.group("slot")), int(match.group("part")))
        if (
            key in observed
            or field["name"] != field["authoredName"]
            or field["type"] != "float4"
            or "arrayCount" in field
            or "stage" in field
        ):
            raise ArtifactFailure("texture-transform-layout")
        observed.add(key)
    if observed != expected:
        raise ArtifactFailure("texture-transform-layout")


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
        f"    {field['type']} {field['name']}"
        f"{'[' + str(field['arrayCount']) + ']' if 'arrayCount' in field else ''};"
        for field in fields
    ) + "\n"
    result = msl[:match.start("body")] + body + msl[match.end("body"):]
    for authored, field_name in names.items():
        if authored != field_name:
            result = re.sub(
                rf"\.{re.escape(authored)}\b", f".{field_name}", result
            )
    return result


def _channel_use(source: str, name: str) -> str:
    starts = [match.start() for match in re.finditer(rf"\b{re.escape(name)}\.sample\s*\(", source)]
    if not starts:
        raise ArtifactFailure("texture-unused")
    component_mask = 0
    observes_whole_vector = False
    for start in starts:
        opening = source.find("(", start)
        end = _sample_end(source, opening)
        if end is None:
            return "unproven"
        suffix = source[end:]
        if re.match(r"\s*\.x\b", suffix) is not None:
            component_mask |= 1
        elif re.match(r"\s*\.y\b", suffix) is not None:
            component_mask |= 2
        elif re.match(r"\s*\.xy\b", suffix) is not None:
            component_mask |= 3
        elif re.match(r"\s*\.", suffix) is not None:
            return "unproven"
        else:
            observes_whole_vector = True
    if observes_whole_vector:
        return "wholeVector"
    return {
        1: "redOnly",
        2: "greenOnly",
        3: "redGreenOnly",
    }.get(component_mask, "unproven")


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
        aliased = aliased_texture_passthrough(fragment_msl, assignments[0])
        if aliased is not None:
            return aliased
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


def _independent_signal_color_transfer(
    fragment_msl: str,
    expected: dict[str, Any],
    texture_bindings: list[dict[str, Any]],
) -> dict[str, Any]:
    source = _without_comments(fragment_msl)
    # This substring is only a conservative conflict check, not the proof.
    if "premultiply" in source.lower():
        raise ArtifactFailure("independent-color-boundary")
    slot = expected["slot"]
    if not any(
        binding.get("name") == f"g_Texture{slot}"
        and binding.get("slot") == slot
        for binding in texture_bindings
    ):
        raise ArtifactFailure("independent-color-binding")

    samples: list[tuple[int, int, str | None]] = []
    for match in re.finditer(r"\bg_Texture(?P<slot>[0-7])\s*\.\s*sample\s*\(", source):
        opening = source.find("(", match.start())
        end = _sample_end(source, opening)
        if end is None:
            raise ArtifactFailure("independent-color-sample")
        projection_match = re.match(r"\s*\.\s*(?P<value>[A-Za-z_]\w*)", source[end:])
        projection = projection_match.group("value") if projection_match else None
        samples.append((match.start(), int(match.group("slot")), projection))
    whole = [sample for sample in samples if sample[2] is None]
    if len(whole) != 1 or whole[0][1] != slot:
        raise ArtifactFailure("independent-color-sample")
    if len([sample for sample in samples if sample[1] == slot]) != 1:
        raise ArtifactFailure("independent-color-sample")
    if any(
        sample[2] not in ("x", "xy")
        for sample in samples if sample != whole[0]
    ):
        raise ArtifactFailure("independent-color-sample")

    body = _function_body(source, "mwxGenericFragment")
    if body is None:
        raise ArtifactFailure("independent-output-carrier")
    entry_returns = re.findall(
        r"\bfragment\s+(?P<type>[A-Za-z_]\w*)\s+mwxGenericFragment\s*\(",
        source,
    )
    output_structs = re.findall(
        rf"\bstruct\s+{re.escape(entry_returns[0])}\s*\{{(?P<body>.*?)\}}\s*;",
        source,
        re.DOTALL,
    ) if len(entry_returns) == 1 else []
    if len(output_structs) != 1 or len(re.findall(
        r"\bfloat4\s+mwxFragColor\s*\[\[\s*color\(0\)\s*\]\]\s*;",
        output_structs[0],
    )) != 1:
        raise ArtifactFailure("independent-output-carrier")
    if len(re.findall(r"\breturn\b", body)) != 1 or re.search(
        r"\breturn\s+out\s*;", body
    ) is None:
        raise ArtifactFailure("independent-output-return")
    write_pattern = re.compile(
        r"\bout\.(?P<field>[A-Za-z_]\w*)"
        r"(?P<component>\s*\.\s*[xyzwrgba]{1,4})?\s*"
        r"(?P<operator>\+=|-=|\*=|/=|=(?!=))"
    )
    writes = list(write_pattern.finditer(body))
    if not 2 <= len(writes) <= 9:
        raise ArtifactFailure("independent-output-carrier")
    out_declarations = list(re.finditer(
        rf"\b{re.escape(entry_returns[0])}\s+out(?:\s*=\s*\{{\s*\}})?\s*;",
        body,
    ))
    if len(out_declarations) != 1 or out_declarations[0].start() >= writes[0].start():
        raise ArtifactFailure("independent-output-carrier")
    if len(list(write_pattern.finditer(source))) != len(writes):
        raise ArtifactFailure("independent-output-drift")
    if any(
        write.group("field") != "mwxFragColor"
        or write.group("component") is not None
        or write.group("operator") != "="
        for write in writes
    ):
        raise ArtifactFailure("independent-output-drift")

    assignments: list[str] = []
    assignment_ends: list[int] = []
    for write in writes:
        semicolon = body.find(";", write.end())
        if semicolon < 0:
            raise ArtifactFailure("independent-output-carrier")
        assignments.append(body[write.end():semicolon].strip())
        assignment_ends.append(semicolon + 1)
    whole_declarations = list(re.finditer(
        rf"\bfloat4\s+(?P<name>[A-Za-z_]\w*)\s*=\s*"
        rf"g_Texture{slot}\s*\.\s*sample\s*\([^;]+\)\s*;",
        body,
    ))
    if len(whole_declarations) != 1 or (
        whole_declarations[0].start() >= writes[0].start()
    ):
        raise ArtifactFailure("independent-output-carrier")
    carrier = whole_declarations[0].group("name")
    initial = assignments[0]
    if not _safe_initial_carrier_flow(
        source, body[:writes[0].start()], carrier, initial
    ):
        raise ArtifactFailure("independent-output-carrier")
    for update_index, expression in enumerate(assignments[1:], start=1):
        arguments = _call_arguments(expression)
        callee = re.match(r"(?P<name>[A-Za-z_]\w*)\s*\(", expression)
        if arguments is None or callee is None:
            raise ArtifactFailure("independent-output-carrier")
        direct = [
            index for index, argument in enumerate(arguments)
            if argument == "out.mwxFragColor"
        ]
        staged: list[tuple[int, str]] = []
        for index, argument in enumerate(arguments):
            if re.fullmatch(r"[A-Za-z_]\w*", argument) is None:
                continue
            declarations = list(re.finditer(
                rf"\bfloat4\s+{re.escape(argument)}\s*=\s*"
                r"out\.mwxFragColor\s*;", body
            ))
            if len(declarations) == 1 and (
                assignment_ends[update_index - 1] <= declarations[0].start()
                < writes[update_index].start()
            ) and len(re.findall(rf"\b{re.escape(argument)}\b", body)) == 2:
                staged.append((index, argument))
        if len(direct) + len(staged) != 1:
            raise ArtifactFailure("independent-output-carrier")
        carrier_index = direct[0] if direct else staged[0][0]
        if not _safe_carrier_parameter(
            source, callee.group("name"), arguments, carrier_index,
            require_const_reference=bool(staged),
        ):
            raise ArtifactFailure("independent-output-helper")
    if len(re.findall(r"\bout\.mwxFragColor\b", body)) != 2 * len(writes) - 1:
        raise ArtifactFailure("independent-output-drift")
    if len(re.findall(r"\bout\b", body)) != 2 * len(writes) + 1:
        raise ArtifactFailure("independent-output-drift")
    return {"kind": expected["kind"], "slot": slot}


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
    output_semantics: str = "color",
    expected_color_transfer: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if set(stage_sources) != {"vertex", "fragment"} or set(msl_sources) != set(stage_sources):
        raise ArtifactFailure("stage-pair")
    expected = expected_color_transfer_for_output(
        output_semantics, expected_color_transfer
    )
    stages = {stage.get("stage"): stage for stage in compiled_stages}
    if set(stages) != {"vertex", "fragment"}:
        raise ArtifactFailure("compiled-pair")
    vertex_layout = _uniform_layout(stages["vertex"]["reflection"])
    fragment_layout = _uniform_layout(stages["fragment"]["reflection"])
    uniform_layout = _stage_local_uniform_layout(
        _active_uniform_fields(vertex_layout[0], msl_sources["vertex"]),
        _active_uniform_fields(fragment_layout[0], msl_sources["fragment"]),
    )
    prepared_fragment_msl = msl_sources["fragment"]
    if output_semantics == "red-green-unorm":
        color_transfer = {"kind": "red-green-unorm-data"}
    elif expected is not None:
        color_transfer = None
    else:
        fragment_color_preparation = _premultiplied_alpha_attenuation(
            msl_sources["fragment"]
        )
        if fragment_color_preparation is not None:
            prepared_fragment_msl, color_transfer = fragment_color_preparation
        else:
            color_transfer = _passthrough_color_transfer(msl_sources["fragment"])
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
    texture_bindings = _texture_bindings(compiled_stages, metal_source)
    _validate_texture_transform_layout(uniform_layout[0], texture_bindings)
    accumulator_work = None
    if expected is not None:
        try:
            fragment_msl, color_transfer = prepare_independent_signal_contract(
                fragment_msl, expected, texture_bindings,
                preserving_fallback=_independent_signal_color_transfer,
            )
            accumulator_work = independent_signal_static_loop_work(
                fragment_msl, expected, maximum_loop_work=256,
            )
        except IndependentSignalContractFailure as error:
            raise ArtifactFailure(error.code) from error
    if color_transfer is None:
        raise ArtifactFailure("color-transfer")
    metal_source = vertex_msl.rstrip() + "\n\n" + fragment_msl.lstrip()
    if len(metal_source.encode("utf-8")) > maximum_artifact_bytes:
        raise ArtifactFailure("metal-size")
    if accumulator_work is None:
        static_loop_work = _static_loop_work(stage_sources, ArtifactFailure)
    else:
        static_loop_work = accumulator_work + _static_loop_work(
            {"vertex": stage_sources["vertex"]}, ArtifactFailure
        )
        if static_loop_work > 256:
            raise ArtifactFailure("loop-budget")
    return {
        "schemaVersion": 6,
        "kind": "scene-generic-shader-program-artifact",
        "backendID": backend_id,
        "requestKey": request_key,
        "outputSemantics": output_semantics,
        "program": {
            "metalSource": metal_source,
            "metalSourceSHA256": hashlib.sha256(metal_source.encode("utf-8")).hexdigest(),
            "vertexFunctionName": "mwxGenericVertex",
            "fragmentFunctionName": "mwxGenericFragment",
            "uniformBufferIndex": 8,
            "uniformLayout": {
                "fields": uniform_layout[0], "byteSize": uniform_layout[1]
            },
            "textureBindings": texture_bindings,
            "staticLoopWork": static_loop_work,
            "fragmentOutputChannelUse": "unproven",
            "colorTransfer": color_transfer,
        },
    }

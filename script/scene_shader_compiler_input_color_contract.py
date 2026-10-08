"""Typed input-color contract shared by shader request and worker validation."""

from __future__ import annotations

import re
from typing import Any

from scene_shader_compiler_msl_function_contract import sample_end


class InputColorContractFailure(ValueError):
    pass


def premultiplied_color_input_slots(value: Any) -> list[int]:
    if not isinstance(value, list):
        raise InputColorContractFailure("premultiplied-color-input-slots")
    if any(isinstance(slot, bool) or not isinstance(slot, int) for slot in value):
        raise InputColorContractFailure("premultiplied-color-input-slots")
    if value != sorted(value) or len(value) != len(set(value)):
        raise InputColorContractFailure("premultiplied-color-input-slots")
    if any(slot < 0 or slot > 7 for slot in value):
        raise InputColorContractFailure("premultiplied-color-input-slots")
    return value


def cache_key(slots: list[int]) -> str:
    return ",".join(str(slot) for slot in slots)


def ordinary_color_boundary(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    required = {"colorInputSlots", "outputRepresentation"}
    if not isinstance(value, dict) or not required <= set(value) or set(value) - required - {"signalPassthroughSlot"}:
        raise InputColorContractFailure("ordinary-color-boundary")
    slots = premultiplied_color_input_slots(value["colorInputSlots"])
    representation = value["outputRepresentation"]
    if representation not in {"opaque", "straight-alpha", "premultiplied-alpha", "independent-alpha-signal"}:
        raise InputColorContractFailure("ordinary-color-boundary")
    signal_slot = value.get("signalPassthroughSlot")
    if signal_slot is not None and (
        isinstance(signal_slot, bool) or not isinstance(signal_slot, int)
        or signal_slot not in slots or representation == "independent-alpha-signal"
    ):
        raise InputColorContractFailure("ordinary-color-boundary")
    result = {"colorInputSlots": slots, "outputRepresentation": representation}
    if signal_slot is not None:
        result["signalPassthroughSlot"] = signal_slot
    return result


def ordinary_boundary_cache_key(value: dict[str, Any] | None) -> str:
    if value is None:
        return "-"
    signal_slot = value.get("signalPassthroughSlot")
    return f"ordinary-color-v2:{cache_key(value['colorInputSlots'])}:{value['outputRepresentation']}:{signal_slot if signal_slot is not None else '-'}"


def _ordinary_stored_color_expression(value: str, boundary: dict[str, Any]) -> str:
    helper = {"straight-alpha": "mwxStraightColorOutput", "premultiplied-alpha": "mwxPremultiply"}.get(
        boundary["outputRepresentation"])
    return f"{helper}({value})" if helper else value


def lower_ordinary_color_boundary(
    source: str, boundary: dict[str, Any], *, stage: str = "fragment", include_helpers: bool = True
) -> str:
    """Adapt original compiler MSL using each function's proven uniform context."""
    if any(name in source for name in (
        "mwxStraightColorInput", "mwxStraightColorOutput", "mwxPassthroughColorOutput", "mwxUnpremultiply",
        "mwxGenericUnpremultiply", "mwxGenericPremultiply",
    )):
        raise InputColorContractFailure("ordinary-color-helper-conflict")
    namespaces = list(re.finditer(r"\busing\s+namespace\s+metal\s*;", source))
    if len(namespaces) != 1:
        raise InputColorContractFailure("ordinary-color-namespace")
    source = ordinary_uniform_contexts(source, boundary)
    scopes: list[tuple[int, int, str, str | None]] = []
    signature = re.compile(
        r"^[ \t]*(?:(?:fragment|vertex|inline|static)\s+|__attribute__\s*\(\(\s*always_inline\s*\)\)\s*)*[A-Za-z_]\w*"
        r"(?:<[^{};\n]+>)?\s+([A-Za-z_]\w*)\s*\(([^{};]*)\)\s*\{", re.MULTILINE
    )
    for match in signature.finditer(source):
        arguments = re.findall(r"\bconstant\s+MWXUniforms\s*&\s*([A-Za-z_]\w*)\b", match[2])
        if len(arguments) > 1:
            raise InputColorContractFailure("ordinary-color-uniform-context")
        depth, close = 1, match.end()
        while close < len(source) and depth:
            depth += (source[close] == "{") - (source[close] == "}")
            close += 1
        if depth:
            raise InputColorContractFailure("ordinary-color-function")
        scopes.append((match.end(), close - 1, match[1], arguments[0] if arguments else None))
    edits: list[tuple[int, int, str]] = []
    returns = list(re.finditer(r"^([ \t]*)return\s+out\s*;[ \t]*$", source, re.MULTILINE))
    if stage == "fragment" and not returns:
        raise InputColorContractFailure("ordinary-color-output")
    for result in returns if stage == "fragment" else []:
        scope = next((scope for scope in scopes if scope[0] <= result.start()
                      and result.end() <= scope[1] and scope[2] == "mwxGenericFragment"), None)
        if scope is None:
            raise InputColorContractFailure("ordinary-color-output")
        signal_slot = boundary.get("signalPassthroughSlot")
        if signal_slot is not None or boundary["outputRepresentation"] in {"straight-alpha", "premultiplied-alpha"}:
            expression = _ordinary_stored_color_expression("out.mwxFragColor", boundary)
            if signal_slot is not None:
                if scope[3] is None:
                    raise InputColorContractFailure("ordinary-color-uniform-context")
                expression = f"mwxPassthroughColorOutput(out.mwxFragColor, {scope[3]}.mwxPremultipliedColorInputMask, {signal_slot}u)"
            indent = result[1]
            edits.append((result.start(), result.end(),
                f"{indent}out.mwxFragColor = {expression};\n{indent}return out;"))
    for sample in re.finditer(r"\bg_Texture([0-7])\s*\.\s*sample\s*\(", source):
        slot = int(sample[1])
        if slot not in boundary["colorInputSlots"]:
            continue
        end = sample_end(source, source.find("(", sample.start(), sample.end()))
        scope = next((scope for scope in scopes
                      if scope[0] <= sample.start() and end is not None and end <= scope[1]), None)
        if end is None or scope is None or scope[3] is None:
            raise InputColorContractFailure("ordinary-color-uniform-context")
        edits.append((sample.start(), end,
            f"mwxStraightColorInput({source[sample.start():end]}, {scope[3]}.mwxPremultipliedColorInputMask, {slot}u)"))
    transformed = source
    for start, end, replacement in sorted(edits, reverse=True):
        transformed = transformed[:start] + replacement + transformed[end:]
    if not include_helpers:
        return transformed
    helper = ""
    if boundary["colorInputSlots"]:
        helper += unpremultiply_helper("mwxUnpremultiply") + """
inline float4 mwxStraightColorInput(float4 color, uint mask, uint slot) {
    return (mask & (1u << slot)) != 0u ? mwxUnpremultiply(color) : color;
}
"""
    if boundary["outputRepresentation"] == "premultiplied-alpha":
        helper += premultiply_helper("mwxPremultiply")
    helper += """
inline float4 mwxStraightColorOutput(float4 color) {
    return float4(color.xyz, clamp(color.w, 0.0, 1.0));
}
"""
    if boundary.get("signalPassthroughSlot") is not None:
        helper += "\ninline float4 mwxPassthroughColorOutput(float4 color, uint mask, uint slot) {\n" \
            + f"    return (mask & (1u << (8u + slot))) != 0u ? color : {_ordinary_stored_color_expression('color', boundary)};\n" \
            + "}\n"
    namespace = re.search(r"\busing\s+namespace\s+metal\s*;", transformed)
    assert namespace is not None
    return transformed[:namespace.end()] + helper + transformed[namespace.end():]


def ordinary_uniform_contexts(source: str, boundary: dict[str, Any]) -> str:
    """Restore the omitted compiler uniform argument and thread helper callers."""
    signature = re.compile(
        r"^[ \t]*(?:(?:fragment|vertex|inline|static)\s+|__attribute__\s*\(\(\s*always_inline\s*\)\)\s*)*[A-Za-z_]\w*"
        r"(?:<[^{};\n]+>)?\s+([A-Za-z_]\w*)\s*\(([^{};]*)\)\s*\{", re.MULTILINE
    )
    scopes: list[dict[str, Any]] = []
    for match in signature.finditer(source):
        arguments = re.findall(r"\bconstant\s+MWXUniforms\s*&\s*([A-Za-z_]\w*)\b", match[2])
        if len(arguments) > 1:
            raise InputColorContractFailure("ordinary-color-uniform-context")
        depth, close = 1, match.end()
        while close < len(source) and depth:
            depth += (source[close] == "{") - (source[close] == "}")
            close += 1
        if depth:
            raise InputColorContractFailure("ordinary-color-function")
        scopes.append({"name": match[1], "parameters": match.span(2),
                       "start": match.end(), "end": close - 1,
                       "uniforms": arguments[0] if arguments else None,
                       "entry": ("vertex" if match[0].strip().startswith("vertex ") else
                                 "fragment" if match[0].strip().startswith("fragment ") else None)})

    def containing(start: int, end: int) -> int | None:
        return next((index for index, scope in enumerate(scopes)
                     if scope["start"] <= start and end <= scope["end"]), None)

    needed: set[int] = set()
    for sample in re.finditer(r"\bg_Texture([0-7])\s*\.\s*sample\s*\(", source):
        if int(sample[1]) not in boundary["colorInputSlots"]:
            continue
        end = sample_end(source, source.find("(", sample.start(), sample.end()))
        index = containing(sample.start(), end) if end is not None else None
        if index is None:
            raise InputColorContractFailure("ordinary-color-uniform-context")
        needed.add(index)
    if boundary.get("signalPassthroughSlot") is not None:
        needed.update(index for index, scope in enumerate(scopes) if scope["entry"] == "fragment")
    calls: list[tuple[int, int, int, int]] = []
    for target, scope in enumerate(scopes):
        for call in re.finditer(r"\b" + re.escape(scope["name"]) + r"\s*\(", source):
            caller = containing(call.start(), call.end())
            if caller is None:
                continue
            opening = source.rfind("(", call.start(), call.end())
            end = sample_end(source, opening)
            if end is None:
                raise InputColorContractFailure("ordinary-color-uniform-context")
            calls.append((caller, target, opening + 1, end - 1))
    previous: set[int] = set()
    while previous != needed:
        previous = needed.copy()
        needed.update(caller for caller, target, _, _ in calls
                      if target in previous and scopes[target]["uniforms"] is None)
    missing = {index for index in needed if scopes[index]["uniforms"] is None}
    if not missing:
        return source
    injected = "mwxColorUniforms"
    if re.search(r"\b" + injected + r"\b", source) or len({s["name"] for s in scopes}) != len(scopes):
        raise InputColorContractFailure("ordinary-color-uniform-context")
    edits: list[tuple[int, str]] = []
    for index in missing:
        scope = scopes[index]
        start, end = scope["parameters"]
        parameters = source[start:end]
        entry_name = "mwxGenericVertex" if scope["entry"] == "vertex" else "mwxGenericFragment"
        if ((scope["entry"] is not None and (scope["name"] != entry_name or "[[buffer(8)]]" in parameters))
                or (scope["entry"] is None and not any(target == index for _, target, _, _ in calls))):
            raise InputColorContractFailure("ordinary-color-uniform-context")
        attribute = " [[buffer(8)]]" if scope["entry"] is not None else ""
        separator = ", " if parameters.strip() else ""
        edits.append((start, f"constant MWXUniforms& {injected}{attribute}{separator}"))
    for caller, target, start, end in calls:
        if target in missing:
            uniforms = scopes[caller]["uniforms"] or injected
            separator = ", " if source[start:end].strip() else ""
            edits.append((start, f"{uniforms}{separator}"))
    for position, replacement in sorted(edits, reverse=True):
        source = source[:position] + replacement + source[position:]
    return source


def lower_premultiplied_color_inputs(
    source: str,
    slots: list[int],
    texture_bindings: list[dict[str, Any]],
) -> str:
    """Move exact typed color inputs into the authored straight-color domain."""
    if not slots:
        return source
    selected = set(slots)
    if any(
        sum(
            isinstance(binding, dict)
            and binding.get("slot") == slot
            and binding.get("name") == f"g_Texture{slot}"
            for binding in texture_bindings
        ) != 1
        for slot in selected
    ):
        raise InputColorContractFailure("premultiplied-color-input-binding")
    if len(re.findall(
        r"\binline\s+float4\s+mwxGenericUnpremultiply\s*\(", source
    )) != 1:
        raise InputColorContractFailure("premultiplied-color-input-helper")

    samples: list[tuple[int, int, int]] = []
    for match in re.finditer(
        r"\bg_Texture(?P<slot>[0-7])\s*\.\s*sample\s*\(", source
    ):
        slot = int(match.group("slot"))
        if slot not in selected:
            continue
        opening = source.find("(", match.start(), match.end())
        end = sample_end(source, opening)
        if end is None:
            raise InputColorContractFailure("premultiplied-color-input-sample")
        prefix = source[:match.start()]
        if re.search(r"mwxGenericUnpremultiply\s*\(\s*$", prefix):
            raise InputColorContractFailure("premultiplied-color-input-double")
        samples.append((match.start(), end, slot))
    if set(slot for _, _, slot in samples) != selected:
        raise InputColorContractFailure("premultiplied-color-input-sample")

    transformed = source
    for start, end, _ in reversed(samples):
        transformed = (
            transformed[:start]
            + "mwxGenericUnpremultiply("
            + transformed[start:end]
            + ")"
            + transformed[end:]
        )
    return transformed


def unpremultiply_helper(name: str) -> str:
    """Convert represented color without clipping authored HDR RGB."""
    return f"""

inline float4 {name}(float4 color) {{
    const float alpha = clamp(color.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0 ? color.xyz / alpha : float3(0.0);
    return float4(rgb, alpha);
}}
"""


def premultiply_helper(name: str) -> str:
    return f"""

inline float4 {name}(float4 color) {{
    const float alpha = clamp(color.w, 0.0, 1.0);
    return float4(color.xyz * alpha, alpha);
}}
"""

#!/usr/bin/env python3
"""Exact identity-free external contracts for source-proven color transfers."""

from __future__ import annotations

import re
from typing import Any, Callable

from scene_shader_compiler_independent_signal_contract import (
    IndependentSignalContractFailure,
    independent_signal_accumulator_static_loop_work as _accumulator_loop_work,
    parse_expected_transfer as _parse_single_slot_transfer,
    prepare_independent_signal_contract as _prepare_single_slot_transfer,
)
from scene_shader_compiler_msl_function_contract import function_body
from scene_shader_compiler_msl_function_contract import sample_end


COMPOSITING_KIND = "independent-alpha-signal-compositing"
STRAIGHT_ALPHA_PRESERVING_KIND = "straight-alpha-preserving"
_UNPREMULTIPLY = "mwxSignalCompositeUnpremultiply"
_PREMULTIPLY = "mwxSignalCompositePremultiply"
_STRAIGHT_UNPREMULTIPLY = "mwxGenericUnpremultiply"
_STRAIGHT_PREMULTIPLY = "mwxGenericPremultiply"


def parse_expected_transfer(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
    if isinstance(value, dict) and value.get("kind") == STRAIGHT_ALPHA_PRESERVING_KIND:
        slot = value.get("slot")
        if (
            set(value) != {"kind", "slot"}
            or isinstance(slot, bool)
            or not isinstance(slot, int)
            or not 0 <= slot < 8
        ):
            raise IndependentSignalContractFailure("expected-color-transfer")
        return {"kind": STRAIGHT_ALPHA_PRESERVING_KIND, "slot": slot}
    if isinstance(value, dict) and set(value) == {"kind", "slots"}:
        kind, slots = value.get("kind"), value.get("slots")
        if (
            kind != COMPOSITING_KIND
            or not isinstance(slots, list)
            or len(slots) != 2
            or any(isinstance(slot, bool) or not isinstance(slot, int) for slot in slots)
            or any(not 0 <= slot < 8 for slot in slots)
            or slots[0] == slots[1]
        ):
            raise IndependentSignalContractFailure("expected-color-transfer")
        return {"kind": kind, "slots": list(slots)}
    return _parse_single_slot_transfer(value)


def expected_color_transfer_key(expected: dict[str, Any] | None) -> str:
    if expected is None:
        return "-"
    if "slot" in expected:
        key = f"{expected['kind']}:{expected['slot']}"
        if "accumulatorLoopWork" in expected:
            key += f":accumulator:{expected['accumulatorLoopWork']}"
        if expected.get("usesRGBA8UnormAttachmentBoundary") is True:
            key += ":rgba8-unorm"
        return key
    return ":".join([expected["kind"], *(str(slot) for slot in expected["slots"])])


def prepare_independent_signal_contract(
    fragment_msl: str,
    expected_transfer: Any,
    texture_bindings: list[dict[str, Any]],
    *,
    maximum_loop_work: int = 256,
    preserving_fallback: Callable[..., dict[str, Any]] | None = None,
) -> tuple[str, dict[str, Any]]:
    expected = parse_expected_transfer(expected_transfer)
    if expected is None:
        raise IndependentSignalContractFailure("expected-color-transfer")
    if expected["kind"] == STRAIGHT_ALPHA_PRESERVING_KIND:
        return _prepare_straight_alpha_preserving(
            fragment_msl, expected, texture_bindings
        ), expected
    if expected["kind"] != COMPOSITING_KIND:
        return _prepare_single_slot_transfer(
            fragment_msl,
            expected,
            texture_bindings,
            maximum_loop_work=maximum_loop_work,
            preserving_fallback=preserving_fallback,
        )
    return _prepare_compositing(fragment_msl, expected, texture_bindings), expected


def independent_signal_static_loop_work(
    fragment_msl: str,
    expected_transfer: dict[str, Any],
    maximum_loop_work: int,
) -> int | None:
    if expected_transfer["kind"] in (
        COMPOSITING_KIND,
        STRAIGHT_ALPHA_PRESERVING_KIND,
    ):
        return None
    expected_work = expected_transfer.get("accumulatorLoopWork")
    if expected_work is None:
        return None
    actual_work = _accumulator_loop_work(
        fragment_msl,
        expected_slot=expected_transfer["slot"],
        maximum_loop_work=maximum_loop_work,
        uses_rgba8_unorm_attachment_boundary=expected_transfer.get(
            "usesRGBA8UnormAttachmentBoundary", False
        ),
    )
    if actual_work != expected_work:
        raise IndependentSignalContractFailure(
            "independent-accumulator-work-mismatch"
        )
    return actual_work


def _prepare_straight_alpha_preserving(
    source: str,
    expected: dict[str, Any],
    texture_bindings: list[dict[str, Any]],
) -> str:
    if not isinstance(source, str) or not source.strip():
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-source"
        )
    slot = expected["slot"]
    masked = _mask_comments(source)
    if any(
        re.search(rf"\b{re.escape(helper)}\b", masked)
        for helper in (_STRAIGHT_UNPREMULTIPLY, _STRAIGHT_PREMULTIPLY)
    ):
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-helper"
        )
    if len(re.findall(r"\busing\s+namespace\s+metal\s*;", masked)) != 1:
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-namespace"
        )

    texture_slots = [
        int(match.group(1))
        for match in re.finditer(r"\bg_Texture([0-7])\b", masked)
    ]
    if slot not in texture_slots or not _validate_required_bindings(
        set(texture_slots), texture_bindings
    ):
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-binding"
        )

    samples: list[tuple[int, int]] = []
    for match in re.finditer(
        r"\bg_Texture(?P<slot>[0-7])\s*\.\s*sample\s*\(", masked
    ):
        if int(match.group("slot")) != slot:
            continue
        opening = masked.find("(", match.start(), match.end())
        end = sample_end(masked, opening)
        if end is None:
            raise IndependentSignalContractFailure(
                "straight-alpha-preserving-sample"
            )
        samples.append((match.start(), end))
    if not samples or len(re.findall(r"\.\s*sample\s*\(", masked)) != len(
        re.findall(r"\bg_Texture[0-7]\s*\.\s*sample\s*\(", masked)
    ):
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-sample"
        )

    return_type, body_start, body_end = _fragment_body_bounds(masked)
    body = masked[body_start:body_end]
    terminal_returns = list(re.finditer(
        r"(?m)^(?P<indent>[ \t]*)return\s+out\s*;[ \t]*$", body
    ))
    if (
        len(re.findall(r"\breturn\b", body)) != 1
        or len(terminal_returns) != 1
        or body[terminal_returns[0].end():].strip()
    ):
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-return"
        )

    output_reference = re.compile(r"\bout\s*\.\s*mwxFragColor\b")
    assignments = list(re.finditer(
        r"(?m)^[ \t]*out\s*\.\s*mwxFragColor\s*=(?!=)"
        r"(?P<value>[^;\n]+);[ \t]*$",
        body,
    ))
    references = list(output_reference.finditer(body))
    if (
        not assignments
        or len(references) != len(assignments)
        or any(assignment.start() >= terminal_returns[0].start() for assignment in assignments)
        or output_reference.search(masked[:body_start] + masked[body_end:]) is not None
    ):
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-output"
        )
    declarations = re.findall(
        rf"\b{re.escape(return_type)}\s+out(?:\s*=\s*\{{\s*\}})?\s*;",
        body,
    )
    if (
        len(declarations) != 1
        or len(re.findall(r"\bout\b", body)) != len(assignments) + 2
    ):
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-output"
        )

    transformed = source
    for start, end in reversed(samples):
        transformed = (
            transformed[:start]
            + f"{_STRAIGHT_UNPREMULTIPLY}("
            + transformed[start:end]
            + ")"
            + transformed[end:]
        )

    transformed_masked = _mask_comments(transformed)
    _, transformed_body_start, transformed_body_end = _fragment_body_bounds(
        transformed_masked
    )
    transformed_body = transformed_masked[
        transformed_body_start:transformed_body_end
    ]
    transformed_return = re.search(
        r"(?m)^(?P<indent>[ \t]*)return\s+out\s*;[ \t]*$",
        transformed_body,
    )
    if transformed_return is None:
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-return"
        )
    return_start = transformed_body_start + transformed_return.start()
    return_end = transformed_body_start + transformed_return.end()
    indent = transformed_return.group("indent")
    transformed = (
        transformed[:return_start]
        + f"{indent}out.mwxFragColor = "
        + f"{_STRAIGHT_PREMULTIPLY}(out.mwxFragColor);\n"
        + f"{indent}return out;"
        + transformed[return_end:]
    )

    helpers = f"""

inline float4 {_STRAIGHT_UNPREMULTIPLY}(float4 color) {{
    const float alpha = clamp(color.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0
        ? clamp(color.xyz / alpha, float3(0.0), float3(1.0))
        : float3(0.0);
    return float4(rgb, alpha);
}}

inline float4 {_STRAIGHT_PREMULTIPLY}(float4 color) {{
    const float alpha = clamp(color.w, 0.0, 1.0);
    return float4(color.xyz * alpha, alpha);
}}
"""
    return re.sub(
        r"(\busing\s+namespace\s+metal\s*;)",
        lambda match: match.group(1) + helpers,
        transformed,
        count=1,
    )


def _fragment_body_bounds(source: str) -> tuple[str, int, int]:
    headers = list(re.finditer(
        r"\bfragment\s+(?P<return>[A-Za-z_]\w*)\s+"
        r"mwxGenericFragment\s*\(",
        source,
    ))
    if len(headers) != 1:
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-function"
        )
    header = headers[0]
    opening = source.find("(", header.start(), header.end())
    parameters_end = sample_end(source, opening)
    if parameters_end is None:
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-function"
        )
    body_start = source.find("{", parameters_end)
    prototype_end = source.find(";", parameters_end)
    if body_start < 0 or (prototype_end >= 0 and prototype_end < body_start):
        raise IndependentSignalContractFailure(
            "straight-alpha-preserving-function"
        )
    depth = 0
    for index in range(body_start, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return header.group("return"), body_start + 1, index
            if depth < 0:
                break
    raise IndependentSignalContractFailure(
        "straight-alpha-preserving-function"
    )


def _validate_required_bindings(
    slots: set[int], texture_bindings: list[dict[str, Any]]
) -> bool:
    if not isinstance(texture_bindings, list):
        return False
    return all(
        sum(
            isinstance(binding, dict)
            and binding.get("slot") == slot
            and binding.get("name") == f"g_Texture{slot}"
            for binding in texture_bindings
        ) == 1
        for slot in slots
    )


def _prepare_compositing(
    source: str,
    expected: dict[str, Any],
    texture_bindings: list[dict[str, Any]],
) -> str:
    if not isinstance(source, str) or not source.strip():
        raise IndependentSignalContractFailure("independent-compositing-source")
    signal_slot, color_slot = expected["slots"]
    _validate_bindings([signal_slot, color_slot], texture_bindings)
    if source.count(_UNPREMULTIPLY) or source.count(_PREMULTIPLY):
        raise IndependentSignalContractFailure("independent-compositing-helper")
    if len(re.findall(r"\busing\s+namespace\s+metal\s*;", source)) != 1:
        raise IndependentSignalContractFailure("independent-compositing-namespace")

    body = function_body(_mask_comments(source), "mwxGenericFragment")
    original_body = function_body(source, "mwxGenericFragment")
    if body is None or original_body is None or len(body) != len(original_body):
        raise IndependentSignalContractFailure("independent-compositing-function")
    if re.search(
        r"\b(?:if|else|for|while|do|switch|case|discard|break|continue)\b|\?",
        body,
    ):
        raise IndependentSignalContractFailure("independent-compositing-control")

    samples = list(re.finditer(r"\bg_Texture([0-7])\.sample\s*\(", body))
    declaration_pattern = re.compile(
        r"(?m)^([ \t]*float4\s+([A-Za-z_]\w*)\s*=\s*)"
        r"g_Texture([0-7])\.sample\(([^;]+)\)(\s*;[ \t]*)$"
    )
    declarations = list(declaration_pattern.finditer(body))
    if len(samples) != 2 or len(declarations) != 2:
        raise IndependentSignalContractFailure("independent-compositing-samples")
    by_slot: dict[int, re.Match[str]] = {}
    for declaration in declarations:
        slot = int(declaration.group(3))
        if slot in by_slot:
            raise IndependentSignalContractFailure("independent-compositing-samples")
        by_slot[slot] = declaration
    if set(by_slot) != {signal_slot, color_slot}:
        raise IndependentSignalContractFailure("independent-compositing-slots")

    signal_name = by_slot[signal_slot].group(2)
    color = by_slot[color_slot]
    color_name = color.group(2)
    if signal_name == color_name or len(re.findall(
        rf"\b{re.escape(signal_name)}\b", body
    )) < 2:
        raise IndependentSignalContractFailure("independent-compositing-carriers")
    writes = list(re.finditer(
        r"(?m)^[ \t]*out\.mwxFragColor(?:\.([xyzwrgba]{1,4}))?"
        r"\s*(?:[+\-*/]?=).*;[ \t]*$",
        body,
    ))
    outputs = list(re.finditer(
        r"(?m)^[ \t]*out\.mwxFragColor\s*=\s*([A-Za-z_]\w*)\s*;[ \t]*$",
        body,
    ))
    if (
        len(writes) != 1
        or len(outputs) != 1
        or outputs[0].group(1) != color_name
        or len(re.findall(r"\breturn\s+out\s*;", body)) != 1
        or max(color.start(), by_slot[signal_slot].start()) >= outputs[0].start()
    ):
        raise IndependentSignalContractFailure("independent-compositing-output")

    transformed_body = original_body
    output = outputs[0]
    transformed_body = (
        transformed_body[:output.start()]
        + f"out.mwxFragColor = {_PREMULTIPLY}({color_name});"
        + transformed_body[output.end():]
    )
    color = next(
        declaration for declaration in declaration_pattern.finditer(transformed_body)
        if int(declaration.group(3)) == color_slot
    )
    replacement = (
        f"{color.group(1)}{_UNPREMULTIPLY}("
        f"g_Texture{color_slot}.sample({color.group(4)})){color.group(5)}"
    )
    transformed_body = (
        transformed_body[:color.start()] + replacement + transformed_body[color.end():]
    )
    body_start = source.find(original_body)
    if body_start < 0:
        raise IndependentSignalContractFailure("independent-compositing-function")
    transformed = (
        source[:body_start] + transformed_body + source[body_start + len(original_body):]
    )
    helpers = f"""

inline float4 {_UNPREMULTIPLY}(float4 value) {{
    const float alpha = clamp(value.w, 0.0, 1.0);
    const float3 rgb = alpha > 0.0
        ? clamp(value.xyz / alpha, float3(0.0), float3(1.0))
        : float3(0.0);
    return float4(rgb, alpha);
}}

inline float4 {_PREMULTIPLY}(float4 value) {{
    const float alpha = clamp(value.w, 0.0, 1.0);
    return float4(clamp(value.xyz, float3(0.0), float3(1.0)) * alpha, alpha);
}}
"""
    return re.sub(
        r"(\busing\s+namespace\s+metal\s*;)",
        lambda match: match.group(1) + helpers,
        transformed,
        count=1,
    )


def _validate_bindings(
    slots: list[int], texture_bindings: list[dict[str, Any]]
) -> None:
    if not isinstance(texture_bindings, list):
        raise IndependentSignalContractFailure("independent-color-binding")
    for slot in slots:
        matches = [
            binding for binding in texture_bindings
            if isinstance(binding, dict)
            and binding.get("slot") == slot
            and binding.get("name") == f"g_Texture{slot}"
        ]
        if len(matches) != 1:
            raise IndependentSignalContractFailure("independent-color-binding")


def _mask_comments(source: str) -> str:
    def mask(match: re.Match[str]) -> str:
        return "".join("\n" if value == "\n" else " " for value in match.group(0))

    return re.sub(r"/\*.*?\*/|//[^\n]*", mask, source, flags=re.DOTALL)

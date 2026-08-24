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


COMPOSITING_KIND = "independent-alpha-signal-compositing"
_UNPREMULTIPLY = "mwxSignalCompositeUnpremultiply"
_PREMULTIPLY = "mwxSignalCompositePremultiply"


def parse_expected_transfer(value: Any) -> dict[str, Any] | None:
    if value is None:
        return None
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
    if expected_transfer["kind"] == COMPOSITING_KIND:
        return None
    expected_work = expected_transfer.get("accumulatorLoopWork")
    if expected_work is None:
        return None
    actual_work = _accumulator_loop_work(
        fragment_msl,
        expected_slot=expected_transfer["slot"],
        maximum_loop_work=maximum_loop_work,
    )
    if actual_work != expected_work:
        raise IndependentSignalContractFailure(
            "independent-accumulator-work-mismatch"
        )
    return actual_work


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

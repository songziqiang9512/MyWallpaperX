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

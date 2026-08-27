"""Typed input-color contract shared by shader request and worker validation."""

from __future__ import annotations

from typing import Any


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

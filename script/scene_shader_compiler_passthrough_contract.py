#!/usr/bin/env python3
"""Prove unchanged texture-sample aliases used as fragment output."""

from __future__ import annotations

import re


def aliased_texture_passthrough(
    fragment_msl: str, assignment: str
) -> dict[str, int | str] | None:
    output = re.fullmatch(
        r"\s*out\.mwxFragColor\s*=\s*(?P<name>[A-Za-z_]\w*)\s*;",
        assignment,
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
    if len(declaration) != 1:
        return None
    if len(re.findall(rf"\b{escaped}\b", fragment_msl)) != 2:
        return None
    return {"kind": "passthrough", "slot": int(declaration[0])}

#!/usr/bin/env python3
"""Emit the generic compiler's shared texture-coordinate transform surface."""

from __future__ import annotations

import re


def active_sampler_slots(
    samplers: dict[str, int], stage_bodies: list[str]
) -> list[int]:
    return sorted(
        slot
        for name, slot in samplers.items()
        if any(re.search(rf"\b{re.escape(name)}\b", body) for body in stage_bodies)
    )


def texture_transform_uniform_lines(active_slots: list[int]) -> list[str]:
    return [
        f"    vec4 mwxTexture{slot}Transform{component};"
        for slot in active_slots
        for component in (0, 1)
    ]


def shader_compatibility_lines() -> list[str]:
    return [
        "#define mul(x, y) ((y) * (x))",
        "#define CAST2(x) vec2(x)",
        "#define CAST3(x) vec3(x)",
        "#define CAST4(x) vec4(x)",
        "#define CAST3X3(x) mat3(x)",
        "#define frac fract",
        "#define saturate(x) clamp((x), 0.0, 1.0)",
        "#define atan2 atan",
    ]


def texture_sampling_support_lines(active_slots: list[int]) -> list[str]:
    coordinates = [
        f"vec2 mwxTexture{slot}Coordinate(vec2 value) {{ return "
        f"mwxTexture{slot}Transform0.xy + mwxTexture{slot}Transform0.zw * value.x + "
        f"mwxTexture{slot}Transform1.xy * value.y; }}"
        for slot in active_slots
    ]
    routes = [
        f"#define MWX_TEXTURE_UV_g_Texture{slot}(value) mwxTexture{slot}Coordinate(value)"
        for slot in active_slots
    ]
    return [
        *coordinates,
        *routes,
        "#define MWX_TEXTURE_UV_INNER(textureName, value) MWX_TEXTURE_UV_##textureName(value)",
        "#define MWX_TEXTURE_UV(textureName, value) MWX_TEXTURE_UV_INNER(textureName, value)",
        "#define texSample2D(textureValue, value) texture(textureValue, MWX_TEXTURE_UV(textureValue, value))",
        "#define texture2D(textureValue, value) texture(textureValue, MWX_TEXTURE_UV(textureValue, value))",
        "#define texSample2DLod(textureValue, value, lodValue) textureLod(textureValue, MWX_TEXTURE_UV(textureValue, value), lodValue)",
        "#define texture2DLod(textureValue, value, lodValue) textureLod(textureValue, MWX_TEXTURE_UV(textureValue, value), lodValue)",
    ]

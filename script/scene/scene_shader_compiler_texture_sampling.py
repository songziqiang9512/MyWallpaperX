#!/usr/bin/env python3
"""Emit native sampling aliases for the offline generic compiler harness."""

from __future__ import annotations

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


def texture_sampling_support_lines() -> list[str]:
    return [
        "#define texSample2D(textureValue, value) texture(textureValue, value)",
        "#define texture2D(textureValue, value) texture(textureValue, value)",
        "#define texSample2DLod(textureValue, value, lodValue) textureLod(textureValue, value, lodValue)",
        "#define texture2DLod(textureValue, value, lodValue) textureLod(textureValue, value, lodValue)",
    ]

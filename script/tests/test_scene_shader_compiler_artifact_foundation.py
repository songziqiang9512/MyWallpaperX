#!/usr/bin/env python3
"""Focused gates for generic compiler artifact foundation contracts."""

from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_shader_compiler_artifact import ArtifactFailure, build_program_artifact
from scene_shader_compiler_harness import normalize_wallpaper_engine_pair


def artifact_arguments(fragment_msl: str) -> dict:
    reflection = {
        "types": {"_1": {"members": [
            {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
            {"name": "mwxTexture0Transform0", "type": "vec4", "offset": 16},
            {"name": "mwxTexture0Transform1", "type": "vec4", "offset": 32},
        ]}},
        "ubos": [{"type": "_1", "block_size": 48, "set": 0, "binding": 8}],
        "textures": [{"name": "g_Texture0", "binding": 0}],
    }
    uniform_struct = """struct MWXUniforms {
    float2 mwxRenderSize;
    float4 mwxTexture0Transform0;
    float4 mwxTexture0Transform1;
};"""
    return {
        "request_key": "a" * 64,
        "backend_id": "glslang-spirv-cross-msl-v2",
        "compiled_stages": [
            {"stage": stage, "reflection": copy.deepcopy(reflection)}
            for stage in ("vertex", "fragment")
        ],
        "stage_sources": {"vertex": "void main() {}", "fragment": "void main() {}"},
        "msl_sources": {"vertex": uniform_struct, "fragment": fragment_msl},
        "maximum_artifact_bytes": 1_024_000,
    }


class SceneShaderCompilerArtifactFoundationTests(unittest.TestCase):
    direct_fragment = """struct MWXUniforms {
    float2 mwxRenderSize;
    float4 mwxTexture0Transform0;
    float4 mwxTexture0Transform1;
};
fragment void f() {
    float2 uv = uniforms.mwxTexture0Transform0.xy
        + uniforms.mwxTexture0Transform0.zw * 0.5
        + uniforms.mwxTexture0Transform1.xy * 0.5;
    out.mwxFragColor = g_Texture0.sample(s, uv);
}
"""

    def test_normalizer_routes_every_active_sampler_through_transform_abi(self) -> None:
        normalized, _ = normalize_wallpaper_engine_pair([
            {"stage": "vertex", "entryPoint": "main", "source": """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord; }
"""},
            {"stage": "fragment", "entryPoint": "main", "source": """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture3;
varying vec2 v_TexCoord;
void main() {
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord)
        + texture2D(g_Texture3, v_TexCoord);
}
"""},
        ], {})
        sources = {stage["stage"]: stage["source"] for stage in normalized}
        for slot in (0, 3):
            self.assertIn(f"vec4 mwxTexture{slot}Transform0;", sources["fragment"])
            self.assertIn(f"vec4 mwxTexture{slot}Transform1;", sources["fragment"])
            self.assertIn(f"mwxTexture{slot}Coordinate", sources["fragment"])
        self.assertNotIn("#define texSample2D texture", sources["fragment"])

    def test_worker_matrix_cast_uses_linkable_glsl_constructor(self) -> None:
        normalized, _ = normalize_wallpaper_engine_pair([
            {"stage": "vertex", "entryPoint": "main", "source": """
uniform mat4 g_ProjectionInverse;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    mat3 rotation = CAST3X3(g_ProjectionInverse);
    vec2 direction = mul(vec3(1.0, 0.0, 0.0), rotation).xy;
    gl_Position = vec4(a_Position.xy + direction * 0.0, 0.0, 1.0);
    v_TexCoord = a_TexCoord;
}
"""},
            {"stage": "fragment", "entryPoint": "main", "source": """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord); }
"""},
        ], {})
        self.assertIn("#define CAST3X3(x) mat3(x)", normalized[0]["source"])
        self.assertIn(
            "mat3 rotation = CAST3X3(g_ProjectionInverse)", normalized[0]["source"]
        )

    def test_static_float_loop_with_dynamic_early_exit_is_bounded(self) -> None:
        arguments = artifact_arguments(self.direct_fragment)
        arguments["stage_sources"]["fragment"] = """
float boundedSample(float currentDepth) {
    float numLayers = 24;
    float currentLayerDepth = 1.0;
    for (float index = 0.0;
         currentLayerDepth > currentDepth && index < numLayers;
         index++) {
        currentLayerDepth -= 1.0 / numLayers;
    }
    return currentLayerDepth;
}
void main() { boundedSample(0.5); }
"""
        artifact = build_program_artifact(**arguments)
        self.assertEqual(artifact["program"]["staticLoopWork"], 24)

        arguments["stage_sources"]["fragment"] = """
float unseenBoundedSample(float remaining) {
    const float marchLimit = 12.0f;
    for (float probe = 0e0; probe < marchLimit && remaining > 0.0; ++probe) {
        remaining -= 0.25;
    }
    return remaining;
}
void main() { unseenBoundedSample(1.0); }
"""
        artifact = build_program_artifact(**arguments)
        self.assertEqual(artifact["program"]["staticLoopWork"], 12)

    def test_predeclared_static_loop_counter_is_bounded(self) -> None:
        arguments = artifact_arguments(self.direct_fragment)
        arguments["stage_sources"]["vertex"] = """
void main() {
    int sampleIndex;
    for (sampleIndex = 0; sampleIndex < 32; sampleIndex += 1) {
        consume(sampleIndex);
    }
}
"""
        artifact = build_program_artifact(**arguments)
        self.assertEqual(artifact["program"]["staticLoopWork"], 32)

    def test_predeclared_static_loop_counter_rejects_escaping_or_unsafe_state(self) -> None:
        arguments = artifact_arguments(self.direct_fragment)
        fixtures = (
            """void main() { int i; use(i);
for (i = 0; i < 32; i += 1) { consume(i); } }""",
            """void main() { int i;
for (i = 0; i < 32; i += 1) { consume(i); } use(i); }""",
            """void main() { float i;
for (i = 0; i < 32; i += 1) { consume(i); } }""",
            """void main() { int i; int unrelated;
for (i = 0; i < 32; i += 1) { consume(i); } }""",
            """void main() { int i;
for (i = 0; i < 32; i += dynamicStep) { consume(i); } }""",
            """void main() { int i;
for (i = 0; i < 32; i -= 1) { consume(i); } }""",
        )
        for source in fixtures:
            with self.subTest(source=source):
                arguments["stage_sources"]["vertex"] = source
                with self.assertRaisesRegex(ArtifactFailure, "loop-unbounded"):
                    build_program_artifact(**arguments)

    def test_dynamic_early_exit_rejects_unproven_or_mutable_bounds(self) -> None:
        arguments = artifact_arguments(self.direct_fragment)
        fixtures = (
            """uniform float g_Count; void main() { float remaining = 1.0;
for (float i = 0.0; remaining > 0.0 && i < g_Count; i++) { remaining -= 0.1; }}""",
            """void main() { float count = 24.0; float remaining = 1.0;
for (float i = 0.0; remaining > 0.0 || i < count; i++) { remaining -= 0.1; }}""",
            """void main() { float count = 24.0; float remaining = 1.0;
for (float i = 0.0; i < remaining && i < count; i++) { remaining -= 0.1; }}""",
            """void main() { float count = 24.0; float remaining = 1.0;
for (float i = 0.0; remaining > 0.0 && i < count; i++) { i = 0.0; }}""",
            """void main() { float count = 24.0; count = 32.0; float remaining = 1.0;
for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; }}""",
            """void main() { float count = 24.5; float remaining = 1.0;
for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; }}""",
            """float decoy() { float count = 24.0; return count; }
uniform float count; void main() { float remaining = 1.0;
for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; }}""",
            """void main() { for (int outer = 0; outer < 16; outer++) {
for (int inner = 0; inner < 16; inner++) { consume(outer, inner); } }}""",
            """void main() { float count = 24.0; float remaining = 1.0;
for (int outer = 0; outer < 2; outer++) {
for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; } }}""",
            """void reset(inout float value) { value = 0.0; }
void main() { float count = 24.0; float remaining = 1.0;
for (float i = 0.0; remaining > 0.0 && i < count; i++) { reset(i); }}""",
            """void widen(inout float value) { value = 1000000.0; }
void main() { float count = 24.0; widen(count); float remaining = 1.0;
for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; }}""",
            """void inner() { for (int i = 0; i < 64; i++) { consume(i); } }
void main() { for (int outer = 0; outer < 4; outer++) { inner(); } }""",
            """float bounded(float remaining) { float count = 24.0;
for (float i = 0.0; remaining > 0.0 && i < count; i++) { remaining -= 0.1; }
return remaining; }
void main() { bounded(1.0); bounded(0.5); }""",
        )
        for source in fixtures:
            with self.subTest(source=source):
                arguments["stage_sources"]["fragment"] = source
                with self.assertRaisesRegex(ArtifactFailure, "loop-unbounded"):
                    build_program_artifact(**arguments)

    def test_unchanged_texture_alias_is_passthrough(self) -> None:
        alias = self.direct_fragment.replace(
            "out.mwxFragColor = g_Texture0.sample(s, uv);",
            "float4 albedo = g_Texture0.sample(s, uv);\n    out.mwxFragColor = albedo;",
        )
        artifact = build_program_artifact(**artifact_arguments(alias))
        self.assertEqual(
            artifact["program"]["colorTransfer"], {"kind": "passthrough", "slot": 0}
        )

        for mutation in ("albedo *= 0.5;", "consume(albedo);", "albedo.x = 0.0;"):
            changed = alias.replace("out.mwxFragColor = albedo;", f"{mutation}\n    out.mwxFragColor = albedo;")
            with self.subTest(mutation=mutation), self.assertRaisesRegex(
                ArtifactFailure, "color-transfer"
            ):
                build_program_artifact(**artifact_arguments(changed))

    def test_falsey_non_list_input_color_slots_fail_closed(self) -> None:
        arguments = artifact_arguments(self.direct_fragment)
        for value in (False, 0, "", {}):
            with self.subTest(value=value), self.assertRaisesRegex(
                ArtifactFailure,
                "premultiplied-color-input-slots",
            ):
                build_program_artifact(
                    **arguments,
                    premultiplied_color_input_slots=value,
                )


if __name__ == "__main__":
    unittest.main()

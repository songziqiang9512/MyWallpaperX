#!/usr/bin/env python3

"""Source-proven independent-signal compiler request and MSL drift gates."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_shader_compiler_harness as harness_support

from scene_shader_compiler_artifact import ArtifactFailure, request_cache_key


class SceneIndependentSignalCompilerArtifactTests(unittest.TestCase):
    def helper(self) -> harness_support.SceneShaderCompilerHarnessTests:
        return harness_support.SceneShaderCompilerHarnessTests(
            "test_project_fixture_compiles_without_product_authority"
        )

    def independent_tools(
        self, root: Path
    ) -> tuple[Path, Path, Path]:
        helper = self.helper()
        glslang, _, metal = helper.tools(root)
        spirv_cross = helper.write_tool(root, "spirv-cross", """
            import json, pathlib, sys
            if "--version" in sys.argv:
                print("Git commit: fake-cross-v1")
                raise SystemExit(0)
            stage = pathlib.Path(sys.argv[1]).stem
            output = pathlib.Path(sys.argv[sys.argv.index("--output") + 1])
            members = [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
                {"name": "mwxTexture0Transform0", "type": "vec4", "offset": 16},
                {"name": "mwxTexture0Transform1", "type": "vec4", "offset": 32},
                {"name": "mwxTexture1Transform0", "type": "vec4", "offset": 48},
                {"name": "mwxTexture1Transform1", "type": "vec4", "offset": 64},
            ]
            textures = [
                {"name": "g_Texture0", "binding": 0, "set": 0, "type": "sampler2D"},
                {"name": "g_Texture1", "binding": 1, "set": 0, "type": "sampler2D"},
            ]
            uniforms = (
                "struct MWXUniforms { float2 mwxRenderSize; "
                "float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; "
                "float4 mwxTexture1Transform0; float4 mwxTexture1Transform1; };"
            )
            if "--reflect" in sys.argv:
                output.write_text(json.dumps({
                    "types": {"_1": {"name": "MWXUniforms", "members": members}},
                    "ubos": [{"name": "MWXUniforms", "type": "_1", "block_size": 80, "set": 0, "binding": 8}],
                    "textures": textures,
                }), encoding="utf-8")
            elif stage == "vertex":
                output.write_text("\\n".join([
                    "#include <metal_stdlib>", "using namespace metal;", uniforms,
                    "vertex float4 mwxGenericVertex(constant MWXUniforms& uniforms [[buffer(8)]], uint vertexID [[vertex_id]]) { return (uniforms.mwxTexture0Transform0 + uniforms.mwxTexture0Transform1 + uniforms.mwxTexture1Transform0 + uniforms.mwxTexture1Transform1) * 0.0; }",
                ]), encoding="utf-8")
            else:
                output.write_text("\\n".join([
                    "#include <metal_stdlib>", "using namespace metal;", uniforms,
                    "struct Output { float4 mwxFragColor [[color(0)]]; };",
                    "float4 boundedInjection(float4 current, float amount) { return fast::min(current + float4(amount), float4(1.0)); }",
                    "fragment Output mwxGenericFragment(constant MWXUniforms& uniforms [[buffer(8)]], texture2d<float> g_Texture0 [[texture(0)]], texture2d<float> g_Texture1 [[texture(1)]]) {",
                    "    Output out;",
                    "    float2 uv = uniforms.mwxTexture1Transform0.xy + uniforms.mwxTexture1Transform0.zw * 0.5 + uniforms.mwxTexture1Transform1.xy * 0.5;",
                    "    float2 drift = g_Texture0.sample(sampler(), uv).xy;",
                    "    float4 signal = g_Texture1.sample(sampler(), uv);",
                    "    out.mwxFragColor = signal / (1.0 + length(drift));",
                    "    out.mwxFragColor = boundedInjection(out.mwxFragColor, 0.5);",
                    "    return out;", "}",
                ]), encoding="utf-8")
        """)
        return glslang, spirv_cross, metal

    def test_source_proven_request_is_exact_and_tamper_closed(self) -> None:
        helper = self.helper()
        with tempfile.TemporaryDirectory(
            prefix="mwx-compiler-independent-"
        ) as directory:
            root = Path(directory)
            tools = self.independent_tools(root)
            manifest = helper.manifest(root, tools[0], tools[1])
            request = json.loads(
                harness_support.FIXTURE.read_text(encoding="utf-8")
            )
            request["expectedColorTransfer"] = {
                "kind": "independent-alpha-signal-preserving", "slot": 1,
            }
            request_path = root / "request.json"
            request_path.write_text(json.dumps(request), encoding="utf-8")
            output = root / "report.json"
            artifact_output = root / "artifact.json"
            completed = helper.run_harness(
                request_path, output, manifest, tools,
                artifact_output=artifact_output,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            artifact = json.loads(artifact_output.read_text(encoding="utf-8"))
            self.assertEqual(artifact["requestKey"], request_cache_key(request))
            self.assertEqual(artifact["program"]["colorTransfer"], {
                "kind": "independent-alpha-signal-preserving", "slot": 1,
            })
            self.assertNotIn(
                "premultiply", artifact["program"]["metalSource"].lower()
            )

            unresolved = copy.deepcopy(request)
            unresolved.pop("expectedColorTransfer")
            self.assertNotEqual(
                request_cache_key(request), request_cache_key(unresolved)
            )
            request_path.write_text(json.dumps(unresolved), encoding="utf-8")
            artifact_output.unlink()
            completed = helper.run_harness(
                request_path, output, manifest, tools,
                artifact_output=artifact_output,
            )
            self.assertEqual(completed.returncode, 2)
            self.assertFalse(artifact_output.exists())
            failure = json.loads(completed.stderr)
            self.assertEqual(failure["failure"]["phase"], "artifact")
            self.assertEqual(failure["failure"]["code"], "color-assignment")

            wrong_slot = copy.deepcopy(request)
            wrong_slot["expectedColorTransfer"]["slot"] = 7
            request_path.write_text(json.dumps(wrong_slot), encoding="utf-8")
            completed = helper.run_harness(
                request_path, output, manifest, tools,
                artifact_output=artifact_output,
            )
            self.assertEqual(completed.returncode, 2)
            failure = json.loads(completed.stderr)
            self.assertEqual(failure["failure"]["phase"], "artifact")
            self.assertEqual(
                failure["failure"]["code"], "independent-color-binding"
            )

            malformed = copy.deepcopy(request)
            malformed["expectedColorTransfer"]["extra"] = True
            request_path.write_text(json.dumps(malformed), encoding="utf-8")
            completed = helper.run_harness(
                request_path, output, manifest, tools,
                artifact_output=artifact_output,
            )
            self.assertEqual(completed.returncode, 2)
            failure = json.loads(completed.stderr)
            self.assertEqual(failure["failure"]["phase"], "request")
            self.assertEqual(
                failure["failure"]["code"], "expected-color-transfer"
            )

    def test_expected_msl_lowering_drift_fails_closed(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 8, "set": 0, "binding": 8,
            }],
            "textures": [
                {"name": "g_Texture0", "binding": 0},
                {"name": "g_Texture1", "binding": 1},
            ],
        }
        vertex_msl = "struct MWXUniforms { float2 mwxRenderSize; };"
        fragment_msl = """struct MWXUniforms { float2 mwxRenderSize; };
struct Output { float4 mwxFragColor [[color(0)]]; };
float4 boundedInjection(float4 current, float amount) {
    return fast::min(current + float4(amount), float4(1.0));
}
fragment Output mwxGenericFragment(
    constant MWXUniforms& uniforms [[buffer(8)]]
) {
    Output out;
    float2 uv = uniforms.mwxRenderSize;
    float2 drift = g_Texture0.sample(s, uv).xy;
    float4 signal = g_Texture1.sample(s, uv);
    out.mwxFragColor = signal / (1.0 + length(drift));
    out.mwxFragColor = boundedInjection(out.mwxFragColor, 0.5);
    return out;
}
"""
        arguments = harness_support.artifact_arguments(
            reflection, vertex_msl, fragment_msl, "i"
        )
        arguments["expected_color_transfer"] = {
            "kind": "independent-alpha-signal-preserving", "slot": 1,
        }
        artifact = harness_support.build_program_artifact(**arguments)
        self.assertEqual(artifact["program"]["colorTransfer"], {
            "kind": "independent-alpha-signal-preserving", "slot": 1,
        })
        self.assertNotIn(
            "premultiply", artifact["program"]["metalSource"].lower()
        )

        dropped_accumulator = copy.deepcopy(arguments)
        dropped_accumulator["expected_color_transfer"] = {
            "kind": "independent-alpha-signal-preserving",
            "slot": 1,
            "accumulatorLoopWork": 30,
        }
        with self.assertRaises(ArtifactFailure) as dropped:
            harness_support.build_program_artifact(**dropped_accumulator)
        self.assertEqual(
            str(dropped.exception),
            "independent-accumulator-work-mismatch",
        )

        const_reference = copy.deepcopy(arguments)
        const_reference["msl_sources"]["fragment"] = fragment_msl.replace(
            "boundedInjection(float4 current",
            "boundedInjection(thread const float4& current",
        )
        const_artifact = harness_support.build_program_artifact(**const_reference)
        self.assertEqual(
            const_artifact["program"]["colorTransfer"],
            {"kind": "independent-alpha-signal-preserving", "slot": 1},
        )

        scaled = copy.deepcopy(arguments)
        scaled["msl_sources"]["fragment"] = fragment_msl.replace(
            "    out.mwxFragColor = signal / (1.0 + length(drift));",
            "    signal *= step(0.0, drift.x);\n"
            "    out.mwxFragColor = signal / (1.0 + length(drift));",
        )
        scaled_artifact = harness_support.build_program_artifact(**scaled)
        self.assertEqual(
            scaled_artifact["program"]["colorTransfer"],
            {"kind": "independent-alpha-signal-preserving", "slot": 1},
        )

        staged_fragment_msl = fragment_msl.replace(
            "boundedInjection(float4 current",
            "boundedInjection(thread const float4& current",
        ).replace(
            "    out.mwxFragColor = boundedInjection(out.mwxFragColor, 0.5);",
            "    float4 param = out.mwxFragColor;\n"
            "    out.mwxFragColor = boundedInjection(param, 0.5);",
        )
        staged = copy.deepcopy(arguments)
        staged["msl_sources"]["fragment"] = staged_fragment_msl
        staged_artifact = harness_support.build_program_artifact(**staged)
        self.assertEqual(
            staged_artifact["program"]["colorTransfer"],
            {"kind": "independent-alpha-signal-preserving", "slot": 1},
        )

        drifts = {
            "boundary": fragment_msl.replace(
                "struct Output",
                "float4 mwxPremultiply(float4 c) { return c; }\nstruct Output",
            ),
            "second-color": fragment_msl.replace(
                "float4 signal =",
                "float4 hidden = g_Texture0.sample(s, uv);\n    float4 signal =",
            ),
            "component-output": fragment_msl.replace(
                "out.mwxFragColor = boundedInjection",
                "out.mwxFragColor.xy = boundedInjection",
            ),
            "extra-output": fragment_msl.replace(
                "    return out;",
                "    out.mwxFragColor = float4(0.0);\n    return out;",
            ),
            "constant-init": fragment_msl.replace(
                "out.mwxFragColor = signal / (1.0 + length(drift));",
                "out.mwxFragColor = float4(0.0);",
            ),
            "carrier-inout-scalar": fragment_msl
            .replace(
                "struct Output",
                "float dirtyScalar(thread float4& value) { value = float4(0.0); return 0.5; }\nstruct Output",
            )
            .replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    signal *= dirtyScalar(signal);\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "carrier-dirty-scalar": fragment_msl
            .replace(
                "struct Output",
                "float leakedScalar; float dirtyScalar() { leakedScalar = 1.0; return leakedScalar; }\nstruct Output",
            )
            .replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    signal *= dirtyScalar();\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "carrier-mutated-local-scalar": fragment_msl
            .replace(
                "struct Output",
                "float dirtyScalar() { return 1.0; }\nstruct Output",
            )
            .replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    float dirtyFactor = 0.5;\n"
                "    dirtyFactor = dirtyScalar();\n"
                "    signal *= dirtyFactor;\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "dirty-vector-initializer": fragment_msl
            .replace(
                "struct Output",
                "float2 dirtyVector() { return float2(0.5); }\nstruct Output",
            )
            .replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    float2 hiddenVector = dirtyVector();\n"
                "    float4 signal = g_Texture1.sample(s, uv);\n"
                "    signal *= step(0.0, hiddenVector.x);",
            ),
            "vector-reassignment": fragment_msl.replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    drift = float2(0.0);\n"
                "    float4 signal = g_Texture1.sample(s, uv);",
            ),
            "vector-member-assignment": fragment_msl.replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    drift.x = 0.0;\n"
                "    float4 signal = g_Texture1.sample(s, uv);",
            ),
            "vector-index-assignment": fragment_msl.replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    drift[0] = 0.0;\n"
                "    float4 signal = g_Texture1.sample(s, uv);",
            ),
            "vector-parenthesized-control-assignment": fragment_msl.replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    if (true) { (drift).x = 0.0; }\n"
                "    float4 signal = g_Texture1.sample(s, uv);",
            ),
            "vector-inout-escape": fragment_msl
            .replace(
                "struct Output",
                "void mutate(thread float2& value) { value.x = 0.0; }\n"
                "struct Output",
            )
            .replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    mutate(drift);\n"
                "    float4 signal = g_Texture1.sample(s, uv);",
            ),
            "vector-prefix-increment": fragment_msl.replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    ++drift.x;\n"
                "    float4 signal = g_Texture1.sample(s, uv);",
            ),
            "vector-postfix-increment": fragment_msl.replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    drift.x++;\n"
                "    float4 signal = g_Texture1.sample(s, uv);",
            ),
            "rgb-scalar-inout-escape": fragment_msl
            .replace(
                "struct Output",
                "void mutate(thread float& value) { value = 0.0; }\n"
                "struct Output",
            )
            .replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    float energy = step(length(signal.xyz), 0.5) * 0.5;\n"
                "    mutate(energy);\n"
                "    signal *= energy;\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "rgb-scalar-prefix-increment": fragment_msl.replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    float energy = step(length(signal.xyz), 0.5) * 0.5;\n"
                "    ++energy;\n"
                "    signal *= energy;\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "rgb-scalar-postfix-increment": fragment_msl.replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    float energy = step(length(signal.xyz), 0.5) * 0.5;\n"
                "    energy++;\n"
                "    signal *= energy;\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "uniform-instance-local-shadow": fragment_msl.replace(
                "    float2 uv = uniforms.mwxRenderSize;",
                "    float uniforms = 0.5;\n"
                "    float2 uv = uniforms.mwxRenderSize;",
            ),
            "unknown-side-effect-call": fragment_msl
            .replace(
                "struct Output",
                "void dirtyGlobal() {}\nstruct Output",
            )
            .replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    dirtyGlobal();\n"
                "    float4 signal = g_Texture1.sample(s, uv);",
            ),
            "unknown-write": fragment_msl
            .replace("struct Output", "float globalValue;\nstruct Output")
            .replace(
                "    float4 signal = g_Texture1.sample(s, uv);",
                "    globalValue = 0.5;\n"
                "    float4 signal = g_Texture1.sample(s, uv);",
            ),
            "carrier-global-scalar": fragment_msl
            .replace("struct Output", "float leakedScalar;\nstruct Output")
            .replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    signal *= leakedScalar;\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "carrier-resource-scalar": fragment_msl.replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    signal *= g_Texture0.sample(s, uv).x;\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "carrier-recursive-scalar": fragment_msl
            .replace(
                "struct Output",
                "float recursiveScalar(float value) { return recursiveScalar(value); }\nstruct Output",
            )
            .replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    signal *= recursiveScalar(0.5);\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "carrier-shadowed-scalar-builtin": fragment_msl
            .replace(
                "struct Output",
                "float step(float edge, float value) { return value; }\nstruct Output",
            )
            .replace(
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
                "    signal *= step(0.0, drift.x);\n"
                "    out.mwxFragColor = signal / (1.0 + length(drift));",
            ),
            "initial-output-dirty-scalar": fragment_msl
            .replace(
                "struct Output",
                "float leakedScalar; float dirtyScalar() { leakedScalar = 1.0; return leakedScalar; }\nstruct Output",
            )
            .replace(
                "out.mwxFragColor = signal / (1.0 + length(drift));",
                "out.mwxFragColor = signal / dirtyScalar();",
            ),
            "extra-output-read": fragment_msl.replace(
                "    return out;",
                "    float4 alias = out.mwxFragColor;\n    return out;",
            ),
            "struct-reference-alias": fragment_msl.replace(
                "    out.mwxFragColor = boundedInjection",
                "    thread Output& alias = out;\n    alias.mwxFragColor = float4(0.0);\n    out.mwxFragColor = boundedInjection",
            ),
            "whole-output-assignment": fragment_msl.replace(
                "    out.mwxFragColor = boundedInjection",
                "    Output otherOutput;\n    out = otherOutput;\n    out.mwxFragColor = boundedInjection",
            ),
            "nonconst-field-reference-write": fragment_msl.replace(
                "boundedInjection(float4 current, float amount) {",
                "boundedInjection(thread float4& current, float amount) {\n    current.x = 0.0;",
            ),
            "const-reference-alias-write": fragment_msl.replace(
                "boundedInjection(float4 current, float amount) {",
                "boundedInjection(thread const float4& current, float amount) {\n    thread float4& alias = const_cast<thread float4&>(current);\n    alias.x = 0.0;",
            ),
            "const-reference-nested-alias-write": fragment_msl.replace(
                "float4 boundedInjection(float4 current, float amount) {\n    return fast::min(current + float4(amount), float4(1.0));\n}",
                "float4 second(thread const float4& value, float amount) {\n    thread float4& alias = const_cast<thread float4&>(value);\n    alias.x = 0.0;\n    return alias;\n}\nfloat4 boundedInjection(thread const float4& current, float amount) {\n    return second(current, amount);\n}",
            ),
            "const-reference-cycle": fragment_msl.replace(
                "boundedInjection(float4 current, float amount) {\n    return fast::min(current + float4(amount), float4(1.0));",
                "boundedInjection(thread const float4& current, float amount) {\n    return boundedInjection(current, amount);",
            ),
            "staged-value-parameter": staged_fragment_msl.replace(
                "thread const float4& current", "float4 current"
            ),
            "staged-pointer-parameter": staged_fragment_msl.replace(
                "thread const float4& current", "thread const float4* current"
            ),
            "staged-multiple-write": staged_fragment_msl.replace(
                "    out.mwxFragColor = boundedInjection(param, 0.5);",
                "    param.x = 0.0;\n    out.mwxFragColor = boundedInjection(param, 0.5);",
            ),
            "staged-extra-consumer": staged_fragment_msl.replace(
                "    out.mwxFragColor = boundedInjection(param, 0.5);",
                "    float4 hidden = param;\n    out.mwxFragColor = boundedInjection(param, 0.5);",
            ),
            "staged-multihop": staged_fragment_msl.replace(
                "    out.mwxFragColor = boundedInjection(param, 0.5);",
                "    float4 next = param;\n    out.mwxFragColor = boundedInjection(next, 0.5);",
            ),
            "return-drift": fragment_msl.replace(
                "    return out;",
                "    if (false) { return out; }\n    return out;",
            ),
        }
        for name, drift in drifts.items():
            with self.subTest(name=name):
                changed = copy.deepcopy(arguments)
                changed["msl_sources"]["fragment"] = drift
                with self.assertRaises(ArtifactFailure):
                    harness_support.build_program_artifact(**changed)

    def test_bundled_compiler_emits_exact_staged_const_reference_carrier(
        self,
    ) -> None:
        helper = self.helper()
        root_path = harness_support.REPOSITORY_ROOT
        glslang = root_path / "MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"
        spirv_cross = (
            root_path / "MyWallpaperX/Resources/SceneShaderCompilerTools/spirv-cross"
        )
        metal = Path(subprocess.run(
            ["xcrun", "--sdk", "macosx", "--find", "metal"],
            check=True, capture_output=True, text=True,
        ).stdout.strip())
        uniforms = """layout(std140, set = 0, binding = 8) uniform MWXUniforms {
    vec2 mwxRenderSize;
    vec4 mwxTexture0Transform0;
    vec4 mwxTexture0Transform1;
    vec4 mwxTexture1Transform0;
    vec4 mwxTexture1Transform1;
} uniforms;"""
        request = {
            "schemaVersion": 5,
            "requestID": "project-independent-real-backend-v1",
            "outputSemantics": "color",
            "expectedColorTransfer": {
                "kind": "independent-alpha-signal-preserving", "slot": 1,
            },
            "premultipliedColorInputSlots": [],
            "stages": [
                {
                    "stage": "vertex", "entryPoint": "main",
                    "source": f"""#version 450
layout(location = 0) in vec3 a_Position;
layout(location = 1) in vec2 a_TexCoord;
layout(location = 0) out vec2 v_TexCoord;
{uniforms}
void main() {{
    v_TexCoord = a_TexCoord;
    gl_Position = vec4(a_Position.xy / uniforms.mwxRenderSize, a_Position.z, 1.0);
}}
""",
                },
                {
                    "stage": "fragment", "entryPoint": "main",
                    "source": f"""#version 450
layout(location = 0) in vec2 v_TexCoord;
layout(location = 0) out vec4 mwxFragColor;
layout(set = 0, binding = 0) uniform sampler2D g_Texture0;
layout(set = 0, binding = 1) uniform sampler2D g_Texture1;
{uniforms}
vec4 boundedInjection(vec4 current, float amount) {{
    return min(current + vec4(amount), vec4(1.0));
}}
void main() {{
    vec2 uv0 = uniforms.mwxTexture0Transform0.xy
        + uniforms.mwxTexture0Transform0.zw * v_TexCoord
        + uniforms.mwxTexture0Transform1.xy;
    vec2 uv1 = uniforms.mwxTexture1Transform0.xy
        + uniforms.mwxTexture1Transform0.zw * v_TexCoord
        + uniforms.mwxTexture1Transform1.xy;
    vec2 drift = texture(g_Texture0, uv0).xy;
    vec4 signal = texture(g_Texture1, uv1);
    mwxFragColor = signal / (1.0 + length(drift));
    mwxFragColor = boundedInjection(mwxFragColor, 0.5);
}}
""",
                },
            ],
        }
        with tempfile.TemporaryDirectory(
            prefix="mwx-independent-real-backend-"
        ) as directory:
            root = Path(directory)
            request_path = root / "request.json"
            request_path.write_text(json.dumps(request), encoding="utf-8")
            manifest = helper.manifest(
                root, glslang, spirv_cross, timeout_ms=10_000
            )
            manifest_payload = json.loads(manifest.read_text(encoding="utf-8"))
            manifest_payload["tools"]["glslang"]["versionProbeContains"] = (
                "Glslang Version: 11:16.4.0"
            )
            manifest_payload["tools"]["spirvCross"]["versionProbeContains"] = (
                "Git commit: vulkan-sdk-1.4.357.0"
            )
            manifest_payload["tools"]["spirvCross"]["versionProbeExitCode"] = 1
            manifest.write_text(json.dumps(manifest_payload), encoding="utf-8")
            report = root / "report.json"
            artifact_path = root / "artifact.json"
            completed = helper.run_harness(
                request_path, report, manifest,
                (glslang, spirv_cross, metal), artifact_output=artifact_path,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            artifact = json.loads(artifact_path.read_text(encoding="utf-8"))
            self.assertEqual(artifact["program"]["colorTransfer"], {
                "kind": "independent-alpha-signal-preserving", "slot": 1,
            })
            source = artifact["program"]["metalSource"]
            self.assertRegex(
                source,
                r"constant\s+MWXFragmentUniforms&\s+uniforms\s*"
                r"\[\[buffer\(8\)\]\]",
            )
            self.assertRegex(
                source,
                r"float2\s+drift\s*=\s*g_Texture0\.sample\([^;]+\)\.xy\s*;",
            )
            self.assertRegex(
                source,
                r"float4\s+signal\s*=\s*g_Texture1\.sample\([^;]+\)\s*;",
            )
            self.assertRegex(
                source,
                r"out\.mwxFragColor\s*=\s*signal\s*/\s*float4\s*"
                r"\(1\.0\s*\+\s*length\(drift\)\)\s*;",
            )
            self.assertRegex(
                source, r"boundedInjection\(thread const float4& current"
            )
            self.assertRegex(
                source,
                r"float4\s+[A-Za-z_]\w*\s*=\s*out\.mwxFragColor\s*;",
            )


if __name__ == "__main__":
    unittest.main()

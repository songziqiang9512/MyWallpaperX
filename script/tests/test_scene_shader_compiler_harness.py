#!/usr/bin/env python3
"""Tests for the bounded upstream shader compiler and Program artifact harness."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_shader_compiler_artifact import (
    ArtifactFailure,
    build_program_artifact,
    request_cache_key,
)


SCRIPT = REPOSITORY_ROOT / "script/scene_shader_compiler_harness.py"
FIXTURE = REPOSITORY_ROOT / "script/fixtures/scene_shader_compiler/ordinary_one_pass.json"
WE_FIXTURE = REPOSITORY_ROOT / "script/fixtures/scene_shader_compiler/wallpaper_engine_one_pass.json"


class SceneShaderCompilerHarnessTests(unittest.TestCase):
    def write_tool(self, root: Path, name: str, body: str) -> Path:
        path = root / name
        path.write_text("#!/usr/bin/env python3\n" + textwrap.dedent(body), encoding="utf-8")
        path.chmod(0o755)
        return path

    def sha256(self, path: Path) -> str:
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def tools(self, root: Path, slow: bool = False) -> tuple[Path, Path, Path]:
        delay = "import time; time.sleep(4)" if slow else ""
        glslang = self.write_tool(root, "glslang", f"""
            import pathlib, sys
            if "--version" in sys.argv:
                print("Glslang Version: fake-v1")
                raise SystemExit(0)
            {delay}
            if "-l" in sys.argv:
                sources = [pathlib.Path(value) for value in sys.argv if value.endswith((".vert", ".frag"))]
                if any("BROKEN" in path.read_text(encoding="utf-8") for path in sources):
                    print("fixture link rejection", file=sys.stderr)
                    raise SystemExit(7)
                pathlib.Path("vert.spv").write_bytes(b"LINK-SPV")
                pathlib.Path("frag.spv").write_bytes(b"LINK-SPV")
                raise SystemExit(0)
            output = pathlib.Path(sys.argv[sys.argv.index("-o") + 1])
            source = pathlib.Path(sys.argv[-1]).read_text(encoding="utf-8")
            if "BROKEN" in source:
                print("fixture compiler rejection", file=sys.stderr)
                raise SystemExit(7)
            output.write_bytes(b"SPV")
        """)
        spirv_cross = self.write_tool(root, "spirv-cross", """
            import json, pathlib, sys
            if "--version" in sys.argv:
                print("Git commit: fake-cross-v1")
                raise SystemExit(0)
            stage = pathlib.Path(sys.argv[1]).stem
            output = pathlib.Path(sys.argv[sys.argv.index("--output") + 1])
            if "--reflect" in sys.argv:
                textures = [{"name": "g_Texture0", "binding": 0, "set": 0, "type": "sampler2D"}]
                output.write_text(json.dumps({
                    "types": {"_1": {"name": "MWXUniforms", "members": [
                        {"name": "mwxRenderSize", "type": "vec2", "offset": 0}
                    ]}},
                    "ubos": [{"name": "MWXUniforms", "type": "_1", "block_size": 8, "set": 0, "binding": 8}],
                    "textures": textures,
                }), encoding="utf-8")
            elif stage == "vertex":
                output.write_text("\\n".join([
                    "#include <metal_stdlib>",
                    "using namespace metal;",
                    "struct MWXUniforms { float2 mwxRenderSize; };",
                    "vertex float4 mwxGenericVertex(constant MWXUniforms& uniforms [[buffer(8)]], uint vertexID [[vertex_id]]) { return float4(0.0); }",
                ]), encoding="utf-8")
            else:
                output.write_text("\\n".join([
                    "#include <metal_stdlib>",
                    "using namespace metal;",
                    "struct MWXUniforms { float2 mwxRenderSize; };",
                    "struct Output { float4 mwxFragColor [[color(0)]]; };",
                    "fragment Output mwxGenericFragment(constant MWXUniforms& uniforms [[buffer(8)]], texture2d<float> g_Texture0 [[texture(0)]]) {",
                    "    Output out;",
                    "    out.mwxFragColor = g_Texture0.sample(sampler(), float2(0.5));",
                    "    return out;",
                    "}",
                ]), encoding="utf-8")
        """)
        metal = self.write_tool(root, "metal", """
            import pathlib, sys
            output = pathlib.Path(sys.argv[sys.argv.index("-o") + 1])
            output.write_bytes(b"AIR")
        """)
        return glslang, spirv_cross, metal

    def manifest(
        self,
        root: Path,
        glslang: Path,
        spirv_cross: Path,
        timeout_ms: int = 2000,
    ) -> Path:
        path = root / "manifest.json"
        path.write_text(json.dumps({
            "schemaVersion": 1,
            "routeState": "observe-only",
            "productExecutionAuthorized": False,
            "tools": {
                "glslang": {
                    "versionProbeContains": "Glslang Version: fake-v1",
                    "versionProbeExitCode": 0,
                },
                "spirvCross": {
                    "versionProbeContains": "Git commit: fake-cross-v1",
                    "versionProbeExitCode": 0,
                },
            },
            "limits": {
                "maximumStageSourceBytes": 65536,
                "maximumDiagnosticBytes": 16384,
                "maximumArtifactBytes": 1048576,
                "maximumResidentBytes": 536870912,
                "timeoutMilliseconds": timeout_ms,
            },
            "verifiedDevelopmentArtifacts": [{
                "glslangSHA256": self.sha256(glslang),
                "spirvCrossSHA256": self.sha256(spirv_cross),
            }],
        }), encoding="utf-8")
        return path

    def run_harness(
        self,
        request: Path,
        output: Path,
        manifest: Path,
        tools: tuple[Path, Path, Path],
        artifact_output: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        glslang, cross, metal = tools
        command = [
            sys.executable,
            str(SCRIPT),
            "--request", str(request),
            "--output", str(output),
            "--dependency-manifest", str(manifest),
            "--glslang", str(glslang),
            "--spirv-cross", str(cross),
            "--metal", str(metal),
        ]
        if artifact_output is not None:
            command += ["--artifact-output", str(artifact_output)]
        return subprocess.run(command, text=True, capture_output=True, check=False)

    def test_project_fixture_compiles_without_product_authority(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools = self.tools(root)
            manifest = self.manifest(root, tools[0], tools[1])
            output = root / "report.json"
            completed = self.run_harness(FIXTURE, output, manifest, tools)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(report["status"], "passed")
            self.assertEqual(report["routeState"], "observe-only")
            self.assertFalse(report["productExecutionAuthorized"])
            self.assertEqual([stage["stage"] for stage in report["stages"]], [
                "vertex", "fragment"
            ])
            self.assertIn("no Program", report["evidenceBoundary"])
            self.assertFalse((root / "vert.spv").exists())
            self.assertFalse((root / "frag.spv").exists())

    def test_direct_sample_artifact_is_source_keyed_and_preflighted(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools = self.tools(root)
            manifest = self.manifest(root, tools[0], tools[1])
            output = root / "report.json"
            artifact_output = root / "artifact.json"
            completed = self.run_harness(
                FIXTURE, output, manifest, tools, artifact_output=artifact_output
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            artifact = json.loads(artifact_output.read_text(encoding="utf-8"))
            request = json.loads(FIXTURE.read_text(encoding="utf-8"))
            self.assertEqual(artifact["schemaVersion"], 3)
            self.assertEqual(artifact["kind"], "scene-generic-shader-program-artifact")
            self.assertEqual(artifact["requestKey"], request_cache_key(request))
            self.assertNotIn("routeState", artifact)
            self.assertEqual(artifact["program"]["colorTransfer"], {
                "kind": "passthrough", "slot": 0
            })
            self.assertEqual(artifact["program"]["uniformLayout"]["byteSize"], 16)
            self.assertEqual(artifact["program"]["metalPreflight"]["bytes"], 3)
            self.assertEqual(
                artifact["program"]["fragmentOutputChannelUse"], "unproven"
            )
            self.assertIn("MWXVertexUniforms", artifact["program"]["metalSource"])
            self.assertIn("MWXFragmentUniforms", artifact["program"]["metalSource"])

    def test_fixed_loop_and_opaque_output_form_bounded_artifact(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0}
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 8, "set": 0, "binding": 8
            }],
            "textures": [{"name": "g_Texture0", "binding": 0}],
        }
        stages = [
            {"stage": "vertex", "reflection": reflection},
            {"stage": "fragment", "reflection": reflection},
        ]
        helper = """template<typename T, size_t Num>
struct spvUnsafeArray
{
    T elements[Num ? Num : 1];
};
"""
        vertex_msl = helper + "struct MWXUniforms { float2 mwxRenderSize; };"
        fragment_msl = helper + """struct MWXUniforms { float2 mwxRenderSize; };
fragment void f() {
    out.mwxFragColor = float4(lightMap * strength, 1.0);
    g_Texture0.sample(s, uv);
}
"""
        artifact = build_program_artifact(
            request_key="a" * 64,
            backend_id="glslang-spirv-cross-msl-v1",
            compiled_stages=stages,
            stage_sources={
                "vertex": "void main() {}",
                "fragment": "for (int i = 0; i < 4; ++i) { value += i; }",
            },
            msl_sources={"vertex": vertex_msl, "fragment": fragment_msl},
            maximum_artifact_bytes=1_024_000,
        )
        self.assertEqual(artifact["schemaVersion"], 3)
        self.assertEqual(artifact["program"]["staticLoopWork"], 4)
        self.assertEqual(artifact["program"]["colorTransfer"], {"kind": "opaque"})
        self.assertEqual(
            artifact["program"]["fragmentOutputChannelUse"], "unproven"
        )
        self.assertEqual(artifact["program"]["metalSource"].count("struct spvUnsafeArray"), 1)
        with self.assertRaisesRegex(ArtifactFailure, "loop-unbounded"):
            build_program_artifact(
                request_key="b" * 64,
                backend_id="glslang-spirv-cross-msl-v1",
                compiled_stages=stages,
                stage_sources={
                    "vertex": "void main() {}",
                    "fragment": "for (int i = 0; i < limit; ++i) { value += i; }",
                },
                msl_sources={"vertex": vertex_msl, "fragment": fragment_msl},
                maximum_artifact_bytes=1_024_000,
            )

    def test_zero_accumulator_with_shared_coverage_is_premultiplied(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "color", "type": "vec3", "offset": 0},
                {"name": "strength", "type": "float", "offset": 12},
                {"name": "mwxRenderSize", "type": "vec2", "offset": 16},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 24, "set": 0, "binding": 8
            }],
            "textures": [{"name": "g_Texture1", "binding": 1}],
        }
        stages = [
            {"stage": "vertex", "reflection": reflection},
            {"stage": "fragment", "reflection": reflection},
        ]
        vertex_msl = """struct MWXUniforms
{
    packed_float3 color;
    float strength;
    float2 mwxRenderSize;
};"""
        fragment_msl = """struct MWXUniforms
{
    packed_float3 color;
    float strength;
    float2 mwxRenderSize;
};
float3 ApplyBlending(int mode, thread const float3& A, thread const float3& B,
                     thread const float& opacity) {
    return A + (B * opacity);
}
fragment void f() {
    float4 albedo = float4(0.0);
    float coverage = g_Texture1.sample(s, uv).x;
    float3 param = albedo.xyz;
    float3 param_1 = color * intensity;
    float param_2 = coverage;
    float3 result = ApplyBlending(31, param, param_1, param_2);
    albedo.x = result.x;
    albedo.y = result.y;
    albedo.z = result.z;
    albedo.w = fast::max(albedo.w, coverage);
    out.mwxFragColor = albedo;
}
"""
        kwargs = {
            "request_key": "c" * 64,
            "backend_id": "glslang-spirv-cross-msl-v1",
            "compiled_stages": stages,
            "stage_sources": {
                "vertex": "void main() {}", "fragment": "void main() {}"
            },
            "msl_sources": {"vertex": vertex_msl, "fragment": fragment_msl},
            "maximum_artifact_bytes": 1_024_000,
        }
        artifact = build_program_artifact(**kwargs)
        self.assertEqual(
            artifact["program"]["colorTransfer"], {"kind": "premultiplied"}
        )
        self.assertEqual(
            [field["offset"] for field in artifact["program"]["uniformLayout"]["fields"]],
            [0, 16, 24],
        )
        self.assertEqual(artifact["program"]["uniformLayout"]["byteSize"], 32)
        self.assertNotIn("packed_float3", artifact["program"]["metalSource"])
        kwargs["msl_sources"] = {
            "vertex": vertex_msl,
            "fragment": fragment_msl.replace(
                "fast::max(albedo.w, coverage)",
                "fast::max(albedo.w, unrelated)",
            ),
        }
        with self.assertRaisesRegex(ArtifactFailure, "color-transfer"):
            build_program_artifact(**kwargs)

    def test_alpha_only_attenuation_is_rewritten_for_premultiplied_host(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "alpha", "type": "float", "offset": 0},
                {"name": "mwxRenderSize", "type": "vec2", "offset": 8},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 16, "set": 0, "binding": 8
            }],
            "textures": [
                {"name": "g_Texture0", "binding": 0},
                {"name": "g_Texture1", "binding": 1},
            ],
        }
        stages = [
            {"stage": "vertex", "reflection": reflection},
            {"stage": "fragment", "reflection": reflection},
        ]
        vertex_msl = "struct MWXUniforms { float alpha; float2 mwxRenderSize; };"
        fragment_msl = """struct MWXUniforms { float alpha; float2 mwxRenderSize; };
fragment void f() {
    float4 albedo = g_Texture0.sample(sourceSampler, uv);
    float mask = g_Texture1.sample(maskSampler, maskUV).x;
    albedo.w *= (mask * uniforms.alpha);
    out.mwxFragColor = albedo;
}
"""
        kwargs = {
            "request_key": "d" * 64,
            "backend_id": "glslang-spirv-cross-msl-v1",
            "compiled_stages": stages,
            "stage_sources": {
                "vertex": "void main() {}", "fragment": "void main() {}"
            },
            "msl_sources": {"vertex": vertex_msl, "fragment": fragment_msl},
            "maximum_artifact_bytes": 1_024_000,
        }
        artifact = build_program_artifact(**kwargs)
        self.assertEqual(
            artifact["program"]["colorTransfer"], {
                "kind": "straight-alpha", "slot": 0
            }
        )
        source = artifact["program"]["metalSource"]
        self.assertIn("albedo *= (mask * uniforms.alpha);", source)
        self.assertNotIn("albedo.w *=", source)

        kwargs["msl_sources"] = {
            "vertex": vertex_msl,
            "fragment": fragment_msl.replace(
                "albedo.w *= (mask * uniforms.alpha);",
                "albedo.xyz = float3(1.0);\n    albedo.w *= (mask * uniforms.alpha);",
            ),
        }
        with self.assertRaisesRegex(ArtifactFailure, "color-transfer"):
            build_program_artifact(**kwargs)

        kwargs["msl_sources"] = {
            "vertex": vertex_msl,
            "fragment": fragment_msl.replace(
                "albedo.w *= (mask * uniforms.alpha);",
                "mutate(albedo);\n    albedo.w *= (mask * uniforms.alpha);",
            ),
        }
        with self.assertRaisesRegex(ArtifactFailure, "color-transfer"):
            build_program_artifact(**kwargs)

    def test_two_direct_color_samples_require_scalar_unmutated_mix(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "rate", "type": "float", "offset": 0},
                {"name": "mwxRenderSize", "type": "vec2", "offset": 8},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 16, "set": 0, "binding": 8
            }],
            "textures": [
                {"name": "g_Texture0", "binding": 0},
                {"name": "g_Texture1", "binding": 1},
            ],
        }
        stages = [
            {"stage": "vertex", "reflection": reflection},
            {"stage": "fragment", "reflection": reflection},
        ]
        vertex_msl = "struct MWXUniforms { float rate; float2 mwxRenderSize; };"
        fragment_msl = """struct MWXUniforms { float rate; float2 mwxRenderSize; };
fragment void f() {
    float4 current = g_Texture0.sample(sourceSampler, uv);
    float4 history = g_Texture1.sample(historySampler, uv);
    float rate = uniforms.rate;
    out.mwxFragColor = mix(history, current, rate);
}
"""
        kwargs = {
            "request_key": "e" * 64,
            "backend_id": "glslang-spirv-cross-msl-v1",
            "compiled_stages": stages,
            "stage_sources": {
                "vertex": "void main() {}", "fragment": "void main() {}"
            },
            "msl_sources": {"vertex": vertex_msl, "fragment": fragment_msl},
            "maximum_artifact_bytes": 1_024_000,
        }
        artifact = build_program_artifact(**kwargs)
        self.assertEqual(
            artifact["program"]["colorTransfer"], {
                "kind": "interpolated-color", "slots": [0, 1]
            }
        )

        kwargs["msl_sources"] = {
            "vertex": vertex_msl,
            "fragment": fragment_msl.replace("float rate =", "float2 rate ="),
        }
        with self.assertRaisesRegex(ArtifactFailure, "color-transfer"):
            build_program_artifact(**kwargs)

        kwargs["msl_sources"] = {
            "vertex": vertex_msl,
            "fragment": fragment_msl.replace(
                "float4 history =",
                "current *= 0.5;\n    float4 history =",
            ),
        }
        with self.assertRaisesRegex(ArtifactFailure, "color-transfer"):
            build_program_artifact(**kwargs)

    def test_varying_array_reserves_each_interface_location(self) -> None:
        from scene_shader_compiler_harness import normalize_wallpaper_engine_pair

        normalized, _ = normalize_wallpaper_engine_pair([
            {
                "stage": "vertex", "entryPoint": "main",
                "source": """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 samples[4];
varying vec2 base;
void main() { gl_Position = vec4(a_Position, 1.0); }
""",
            },
            {
                "stage": "fragment", "entryPoint": "main",
                "source": """varying vec2 samples[4];
varying vec2 base;
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
void main() { vec4 sample; gl_FragColor = texture(g_Texture0, base); }
""",
            },
        ], {})
        for stage in normalized:
            self.assertIn("location = 0", stage["source"])
            self.assertIn("location = 1", stage["source"])
            self.assertNotIn("location = 2", stage["source"])
            self.assertIn("#define CAST3(x) vec3(x)", stage["source"])
        self.assertIn("vec4 mwx_sample", normalized[1]["source"])
        self.assertIn("uniform sampler2D g_Texture0", normalized[1]["source"])
        self.assertNotIn("uniform sampler2D g_Texture1", normalized[1]["source"])

    def test_vertex_position_input_matches_authored_position_contract(self) -> None:
        from scene_shader_compiler_harness import normalize_wallpaper_engine_pair

        fragment = {
            "stage": "fragment", "entryPoint": "main",
            "source": """varying vec2 v_TexCoord;
uniform sampler2D g_Texture0;
void main() { gl_FragColor = texture(g_Texture0, v_TexCoord); }
""",
        }
        direct, direct_summary = normalize_wallpaper_engine_pair([
            {
                "stage": "vertex", "entryPoint": "main",
                "source": """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord = a_TexCoord;
}
""",
            },
            fragment,
        ], {})
        projected, projected_summary = normalize_wallpaper_engine_pair([
            {
                "stage": "vertex", "entryPoint": "main",
                "source": """uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = mul(
        vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord;
}
""",
            },
            fragment,
        ], {})

        self.assertEqual(direct_summary["vertexPositionInput"], "clip-space")
        self.assertIn(
            "mwxPosition * 2.0 - vec2(1.0)", direct[0]["source"]
        )
        self.assertEqual(
            projected_summary["vertexPositionInput"], "target-pixels"
        )
        self.assertIn(
            "(mwxPosition - vec2(0.5)) * mwxRenderSize",
            projected[0]["source"],
        )

    def test_inactive_optional_varying_components_prune_dead_resolution(self) -> None:
        from scene_shader_compiler_harness import normalize_wallpaper_engine_pair

        normalized, summary = normalize_wallpaper_engine_pair([
            {
                "stage": "vertex", "entryPoint": "main",
                "source": """uniform mat4 g_ModelViewProjectionMatrix;
uniform vec4 g_Texture1Resolution;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord.xy = a_TexCoord;
    v_TexCoord.zw = vec2(
        v_TexCoord.x * g_Texture1Resolution.z / g_Texture1Resolution.x,
        v_TexCoord.y * g_Texture1Resolution.w / g_Texture1Resolution.y);
}
""",
            },
            {
                "stage": "fragment", "entryPoint": "main",
                "source": """uniform sampler2D g_Texture0;
varying vec4 v_TexCoord;
void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord.xy); }
""",
            },
        ], {})
        for stage in normalized:
            self.assertNotIn("g_Texture1Resolution", stage["source"])
        self.assertNotIn("v_TexCoord.zw =", normalized[0]["source"])
        self.assertIn("v_TexCoord.xy =", normalized[0]["source"])
        self.assertEqual(summary["inactiveUniformsPruned"], 1)
        self.assertEqual(summary["unusedVaryingComponentAssignmentsPruned"], 1)

    def test_inactive_varying_call_is_not_pruned_without_purity_proof(self) -> None:
        from scene_shader_compiler_harness import normalize_wallpaper_engine_pair

        normalized, summary = normalize_wallpaper_engine_pair([
            {
                "stage": "vertex", "entryPoint": "main",
                "source": """uniform vec4 g_Texture1Resolution;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_TexCoord;
vec2 authoredWarp(vec2 value) { return value; }
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord.zw = authoredWarp(g_Texture1Resolution.xy);
}
""",
            },
            {
                "stage": "fragment", "entryPoint": "main",
                "source": """varying vec4 v_TexCoord;
void main() { gl_FragColor = vec4(v_TexCoord.xy, 0.0, 1.0); }
""",
            },
        ], {})
        self.assertIn("authoredWarp(g_Texture1Resolution.xy)", normalized[0]["source"])
        self.assertIn("vec4 g_Texture1Resolution;", normalized[0]["source"])
        self.assertEqual(summary["inactiveUniformsPruned"], 0)
        self.assertEqual(summary["unusedVaryingComponentAssignmentsPruned"], 0)

    def test_inactive_varying_increment_is_not_pruned_as_pure_arithmetic(self) -> None:
        from scene_shader_compiler_harness import normalize_wallpaper_engine_pair

        normalized, summary = normalize_wallpaper_engine_pair([
            {
                "stage": "vertex", "entryPoint": "main",
                "source": """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_TexCoord;
void main() {
    float counter = 0.0;
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord.zw = vec2(counter++, 0.0);
}
""",
            },
            {
                "stage": "fragment", "entryPoint": "main",
                "source": """varying vec4 v_TexCoord;
void main() { gl_FragColor = vec4(v_TexCoord.xy, 0.0, 1.0); }
""",
            },
        ], {})
        self.assertIn("vec2(counter++, 0.0)", normalized[0]["source"])
        self.assertEqual(summary["unusedVaryingComponentAssignmentsPruned"], 0)

    def test_compiler_rejection_does_not_publish_report(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools = self.tools(root)
            manifest = self.manifest(root, tools[0], tools[1])
            request = json.loads(FIXTURE.read_text(encoding="utf-8"))
            request["stages"][1]["source"] += "\nBROKEN\n"
            request_path = root / "request.json"
            request_path.write_text(json.dumps(request), encoding="utf-8")
            output = root / "report.json"
            completed = self.run_harness(request_path, output, manifest, tools)
            self.assertEqual(completed.returncode, 2)
            self.assertFalse(output.exists())
            failure = json.loads(completed.stderr)
            self.assertEqual(failure["failure"]["phase"], "stage-link")
            self.assertEqual(failure["failure"]["code"], "tool-rejected")

    def test_wallpaper_engine_dialect_is_normalized_by_public_shape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools = self.tools(root)
            manifest = self.manifest(root, tools[0], tools[1])
            output = root / "report.json"
            completed = self.run_harness(WE_FIXTURE, output, manifest, tools)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))
            normalization = report["normalization"]
            self.assertEqual(normalization["dialect"], "wallpaper-engine-glsl-like-v0")
            self.assertEqual(normalization["uniformCount"], 2)
            self.assertEqual(normalization["samplerSlots"], [0, 1])
            self.assertEqual(normalization["attributeCount"], 2)
            self.assertEqual(normalization["varyingCount"], 1)
            self.assertEqual(normalization["defineCount"], 1)
            self.assertEqual(normalization["scalarTextureChannelRewrites"], 1)
            self.assertEqual(normalization["booleanComboTernaryRewrites"], 1)

    def test_wallpaper_engine_dialect_does_not_synthesize_missing_varying(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools = self.tools(root)
            manifest = self.manifest(root, tools[0], tools[1])
            request = json.loads(WE_FIXTURE.read_text(encoding="utf-8"))
            request["stages"][1]["source"] = request["stages"][1]["source"].replace(
                "varying vec2 v_TexCoord;",
                "varying vec2 v_TexCoord;\nvarying vec2 v_FragmentOnly;",
            )
            request_path = root / "request.json"
            request_path.write_text(json.dumps(request), encoding="utf-8")
            output = root / "report.json"
            completed = self.run_harness(request_path, output, manifest, tools)
            self.assertEqual(completed.returncode, 2)
            self.assertFalse(output.exists())
            failure = json.loads(completed.stderr)
            self.assertEqual(failure["failure"]["phase"], "normalization")
            self.assertEqual(failure["failure"]["code"], "varying-link")
            self.assertEqual(failure["failure"]["details"], ["v_FragmentOnly"])

    def test_hash_mismatch_fails_before_compilation(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools = self.tools(root)
            manifest = self.manifest(root, tools[0], tools[1])
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["verifiedDevelopmentArtifacts"][0]["glslangSHA256"] = "0" * 64
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            output = root / "report.json"
            completed = self.run_harness(FIXTURE, output, manifest, tools)
            self.assertEqual(completed.returncode, 2)
            self.assertFalse(output.exists())
            failure = json.loads(completed.stderr)
            self.assertEqual(failure["failure"]["phase"], "tool")
            self.assertEqual(failure["failure"]["code"], "hash-mismatch")

    def test_timeout_kills_the_compiler_process_group(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools = self.tools(root, slow=True)
            manifest = self.manifest(root, tools[0], tools[1], timeout_ms=2500)
            output = root / "report.json"
            completed = self.run_harness(FIXTURE, output, manifest, tools)
            self.assertEqual(completed.returncode, 2)
            self.assertFalse(output.exists())
            failure = json.loads(completed.stderr)
            self.assertEqual(failure["failure"]["phase"], "stage-link")
            self.assertEqual(failure["failure"]["code"], "timeout")


if __name__ == "__main__":
    unittest.main()

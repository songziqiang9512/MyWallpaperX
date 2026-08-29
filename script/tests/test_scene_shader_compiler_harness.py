#!/usr/bin/env python3
"""Tests for the bounded upstream shader compiler and Program artifact harness."""

from __future__ import annotations

import copy
import hashlib
import json
import re
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
    build_program_artifact as build_product_artifact,
    request_cache_key,
)
from scene_shader_compiler_harness import (
    HarnessFailure,
    normalize_wallpaper_engine_pair,
    parse_limits,
    validate_request,
)
from script.tests.scene_generic_shader_test_support import (
    assert_default_color_artifact,
)


SCRIPT = REPOSITORY_ROOT / "script/scene_shader_compiler_harness.py"
FIXTURE = REPOSITORY_ROOT / "script/fixtures/scene_shader_compiler/ordinary_one_pass.json"
WE_FIXTURE = REPOSITORY_ROOT / "script/fixtures/scene_shader_compiler/wallpaper_engine_one_pass.json"


def artifact_arguments(
    reflection: dict, vertex_msl: str, fragment_msl: str, key: str = "a"
) -> dict:
    return {
        "request_key": key * 64,
        "backend_id": "glslang-spirv-cross-msl-v2",
        "compiled_stages": [
            {"stage": stage, "reflection": copy.deepcopy(reflection)}
            for stage in ("vertex", "fragment")
        ],
        "stage_sources": {"vertex": "void main() {}", "fragment": "void main() {}"},
        "msl_sources": {"vertex": vertex_msl, "fragment": fragment_msl},
        "maximum_artifact_bytes": 1_024_000,
    }


def transform_abi_fixture(arguments: dict) -> dict:
    values = copy.deepcopy(arguments)
    slots = sorted({
        texture["binding"]
        for stage in values["compiled_stages"]
        for texture in stage["reflection"].get("textures", [])
    })
    for stage in values["compiled_stages"]:
        reflection = stage["reflection"]
        uniform = reflection["ubos"][0]
        members = reflection["types"][uniform["type"]]["members"]
        offset = (uniform["block_size"] + 15) // 16 * 16
        for slot in slots:
            for part in (0, 1):
                name = f"mwxTexture{slot}Transform{part}"
                members.append({"name": name, "type": "vec4", "offset": offset})
                offset += 16
        uniform["block_size"] = offset
    for stage, source in values["msl_sources"].items():
        match = re.search(r"struct\s+MWXUniforms\s*\{.*?\};", source, re.DOTALL)
        if match is None:
            raise AssertionError("fixture uniform struct missing")
        probes = " + ".join(
            f"uniforms.mwxTexture{slot}Transform{part}.x"
            for slot in slots for part in (0, 1)
        ) or "0.0"
        helper = (
            f"\nfloat mwx{stage.title()}TransformProbe("
            f"constant MWXUniforms& uniforms) {{ return {probes}; }}\n"
        )
        values["msl_sources"][stage] = source[:match.end()] + helper + source[match.end():]
    return values


def build_program_artifact(**arguments) -> dict:
    return build_product_artifact(**transform_abi_fixture(arguments))


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
                        {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
                        {"name": "mwxTexture0Transform0", "type": "vec4", "offset": 16},
                        {"name": "mwxTexture0Transform1", "type": "vec4", "offset": 32},
                    ]}},
                    "ubos": [{"name": "MWXUniforms", "type": "_1", "block_size": 48, "set": 0, "binding": 8}],
                    "textures": textures,
                }), encoding="utf-8")
            elif stage == "vertex":
                output.write_text("\\n".join([
                    "#include <metal_stdlib>",
                    "using namespace metal;",
                    "struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };",
                    "vertex float4 mwxGenericVertex(constant MWXUniforms& uniforms [[buffer(8)]], uint vertexID [[vertex_id]]) { return (uniforms.mwxTexture0Transform0 + uniforms.mwxTexture0Transform1) * 0.0; }",
                ]), encoding="utf-8")
            else:
                output.write_text("\\n".join([
                    "#include <metal_stdlib>",
                    "using namespace metal;",
                    "struct MWXUniforms { float2 mwxRenderSize; float4 mwxTexture0Transform0; float4 mwxTexture0Transform1; };",
                    "struct Output { float4 mwxFragColor [[color(0)]]; };",
                    "fragment Output mwxGenericFragment(constant MWXUniforms& uniforms [[buffer(8)]], texture2d<float> g_Texture0 [[texture(0)]]) {",
                    "    Output out;",
                    "    float2 uv = uniforms.mwxTexture0Transform0.xy + uniforms.mwxTexture0Transform0.zw * 0.5 + uniforms.mwxTexture0Transform1.xy * 0.5;",
                    "    out.mwxFragColor = g_Texture0.sample(sampler(), uv);",
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

    def harness_setup(
        self, root: Path, *, slow: bool = False, timeout_ms: int = 2000
    ) -> tuple[tuple[Path, Path, Path], Path, Path]:
        tools = self.tools(root, slow=slow)
        manifest = self.manifest(root, tools[0], tools[1], timeout_ms=timeout_ms)
        return tools, manifest, root / "report.json"

    def assert_harness_failure(
        self, completed: subprocess.CompletedProcess[str], output: Path,
        phase: str, code: str, details: list[str] | None = None,
    ) -> None:
        self.assertEqual(completed.returncode, 2)
        self.assertFalse(output.exists())
        failure = json.loads(completed.stderr)["failure"]
        self.assertEqual((failure["phase"], failure["code"]), (phase, code))
        if details is not None:
            self.assertEqual(failure["details"], details)

    def test_project_fixture_compiles_without_product_authority(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools, manifest, output = self.harness_setup(root)
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
            tools, manifest, output = self.harness_setup(root)
            artifact_output = root / "artifact.json"
            completed = self.run_harness(
                FIXTURE, output, manifest, tools, artifact_output=artifact_output
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            artifact = json.loads(artifact_output.read_text(encoding="utf-8"))
            request = json.loads(FIXTURE.read_text(encoding="utf-8"))
            assert_default_color_artifact(self, artifact)
            self.assertEqual(artifact["requestKey"], request_cache_key(request))
            self.assertNotIn("routeState", artifact)
            self.assertEqual(artifact["program"]["colorTransfer"], {
                "kind": "passthrough", "slot": 0
            })
            self.assertEqual(artifact["program"]["uniformLayout"]["byteSize"], 48)
            self.assertEqual(artifact["program"]["metalPreflight"]["bytes"], 3)
            self.assertEqual(
                artifact["program"]["fragmentOutputChannelUse"], "unproven"
            )
            self.assertIn("MWXVertexUniforms", artifact["program"]["metalSource"])
            self.assertIn("MWXFragmentUniforms", artifact["program"]["metalSource"])

            raw_request = {**request, "outputSemantics": "red-green-unorm"}
            self.assertNotEqual(request_cache_key(request), request_cache_key(raw_request))
            limits = parse_limits(json.loads(manifest.read_text(encoding="utf-8")))
            self.assertEqual(len(validate_request(raw_request, limits)), 2)
            for semantic, expected, code in (
                ("red-green-unorm", {"kind": "bad"}, "expected-color-transfer"),
                ("unknown", None, "output-semantics"),
            ):
                invalid = {**raw_request, "outputSemantics": semantic}
                if expected is not None:
                    invalid["expectedColorTransfer"] = expected
                with self.assertRaisesRegex(HarnessFailure, f"request:{code}"):
                    validate_request(invalid, limits)

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
        arguments = artifact_arguments(reflection, vertex_msl, fragment_msl)
        arguments["stage_sources"]["fragment"] = (
            "void main() { for (int i = 0; i < 4; ++i) { value += i; } }"
        )
        artifact = build_program_artifact(**arguments)
        assert_default_color_artifact(self, artifact)
        self.assertEqual(artifact["program"]["staticLoopWork"], 4)
        self.assertEqual(artifact["program"]["colorTransfer"], {"kind": "opaque"})
        self.assertEqual(
            artifact["program"]["fragmentOutputChannelUse"], "unproven"
        )
        self.assertEqual(artifact["program"]["metalSource"].count("struct spvUnsafeArray"), 1)
        with self.assertRaisesRegex(ArtifactFailure, "loop-unbounded"):
            arguments["stage_sources"]["fragment"] = (
                "void main() { for (int i = 0; i < limit; ++i) { value += i; } }"
            )
            build_program_artifact(**arguments)

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
        kwargs = artifact_arguments(reflection, vertex_msl, fragment_msl, "c")
        artifact = build_program_artifact(**kwargs)
        self.assertEqual(
            artifact["program"]["colorTransfer"], {"kind": "premultiplied"}
        )
        self.assertEqual(
            [field["offset"] for field in artifact["program"]["uniformLayout"]["fields"]],
            [0, 16, 32],
        )
        self.assertEqual(
            [field.get("stage") for field in artifact["program"]["uniformLayout"]["fields"]],
            [None, None, None],
        )
        self.assertEqual(artifact["program"]["uniformLayout"]["byteSize"], 48)
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
        vertex_msl = "struct MWXUniforms { float alpha; float2 mwxRenderSize; };"
        fragment_msl = """struct MWXUniforms { float alpha; float2 mwxRenderSize; };
fragment void f() {
    float4 albedo = g_Texture0.sample(sourceSampler, uv);
    float mask = g_Texture1.sample(maskSampler, maskUV).x;
    albedo.w *= (mask * uniforms.alpha);
    out.mwxFragColor = albedo;
}
"""
        kwargs = artifact_arguments(reflection, vertex_msl, fragment_msl, "d")
        artifact = build_program_artifact(**kwargs)
        self.assertEqual(
            artifact["program"]["colorTransfer"], {
                "kind": "straight-alpha", "slot": 0
            }
        )
        source = artifact["program"]["metalSource"]
        self.assertIn("albedo *= (mask * uniforms.alpha);", source)
        self.assertNotIn("albedo.w *=", source)

        raw_kwargs = {**kwargs, "output_semantics": "red-green-unorm"}
        raw = build_program_artifact(**raw_kwargs)
        self.assertEqual(raw["outputSemantics"], "red-green-unorm")
        self.assertEqual(raw["program"]["colorTransfer"], {"kind": "red-green-unorm-data"})
        self.assertIn("albedo.w *=", raw["program"]["metalSource"])
        self.assertNotIn("albedo *=", raw["program"]["metalSource"])

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

    def test_linked_uniform_superset_is_filtered_per_stage(self) -> None:
        reflection = {
            "types": {"_1": {"members": [
                {"name": "g_Direction", "type": "vec2", "offset": 0},
                {"name": "g_Speed", "type": "float", "offset": 8},
                {"name": "mwxRenderSize", "type": "vec2", "offset": 16},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 24, "set": 0, "binding": 8
            }],
            "textures": [{"name": "g_Texture0", "binding": 0}],
        }
        vertex_msl = """struct MWXUniforms {
    float2 g_Direction;
    float g_Speed;
    float2 mwxRenderSize;
};
vertex void v() {
    position.xy += uniforms.g_Direction * uniforms.g_Speed;
    position.xy /= uniforms.mwxRenderSize;
}
"""
        fragment_msl = """struct MWXUniforms {
    float2 g_Direction;
    float g_Speed;
    float2 mwxRenderSize;
};
fragment void f() {
    float ignored = uniforms.g_Speed * uniforms.mwxRenderSize.x;
    out.mwxFragColor = g_Texture0.sample(sourceSampler, uv);
}
"""
        artifact = build_program_artifact(
            **artifact_arguments(reflection, vertex_msl, fragment_msl, "f")
        )
        fields = artifact["program"]["uniformLayout"]["fields"]
        self.assertEqual(
            [(field["name"], field.get("stage")) for field in fields],
            [
                ("g_Direction", "vertex"),
                ("mwxV_g_Speed", "vertex"),
                ("mwxF_g_Speed", "fragment"),
                ("mwxRenderSize", None),
                ("mwxTexture0Transform0", None),
                ("mwxTexture0Transform1", None),
            ],
        )
        source = artifact["program"]["metalSource"]
        self.assertNotIn("mwxF_g_Direction", source)
        self.assertIn("uniforms.mwxV_g_Speed", source)
        self.assertIn("uniforms.mwxF_g_Speed", source)

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
        vertex_msl = "struct MWXUniforms { float rate; float2 mwxRenderSize; };"
        fragment_msl = """struct MWXUniforms { float rate; float2 mwxRenderSize; };
fragment void f() {
    float4 current = g_Texture0.sample(sourceSampler, uv);
    float4 history = g_Texture1.sample(historySampler, uv);
    float rate = uniforms.rate;
    out.mwxFragColor = mix(history, current, rate);
}
"""
        kwargs = artifact_arguments(reflection, vertex_msl, fragment_msl, "e")
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
void main() {
    vec4 sample;
    vec2 arrayValue = samples[0];
    gl_FragColor = texture(g_Texture0, base + arrayValue * 0.0);
}
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

    def test_shared_vector_narrowing_rules_cover_sampler_coordinates_scalars_and_constructors(self) -> None:
        normalized, _ = normalize_wallpaper_engine_pair([
            {
                "stage": "vertex", "entryPoint": "main",
                "source": """uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = vec4(a_TexCoord, 0.0, 1.0);
}
""",
            },
            {
                "stage": "fragment", "entryPoint": "main",
                "source": """uniform sampler2D g_Texture0;
uniform vec2 g_PointerPosition;
varying vec4 v_TexCoord;
void main() {
    vec4 scene = texSample2D(g_Texture0, v_TexCoord);
    float pointer = g_PointerPosition * 0.5;
    float alreadyNarrowed = (g_PointerPosition * 0.5).x;
    float projected = g_PointerPosition.x * 0.25;
    float interpolated = mix(g_PointerPosition.x, g_PointerPosition.y, 0.5);
    float magnitude = length(g_PointerPosition);
    float indexed = g_PointerPosition[0] * 0.25;
    float left = g_PointerPosition.y * 0.05, right = left;
    float numericBool = 1.0;
    numericBool += g_PointerPosition.x < 0.5;
    numericBool *= g_PointerPosition.x > 0.0 && g_PointerPosition.y < 1.0;
    float frequency = g_PointerPosition.x * 64.0;
    uint wrapped = frequency % 64;
    uint integerOnly = 65 % 64;
    float interpolatedIntegerEndpoints = lerp(0, 1, projected);
    float smoothedIntegerEndpoints = smoothstep(0, 1, projected);
    vec3 finalColor = vec4(scene.r, scene.g, scene.b, 1.0);
    gl_FragColor = vec4(
        finalColor + pointer + alreadyNarrowed + projected + interpolated + magnitude + indexed + left + right + numericBool + interpolatedIntegerEndpoints + smoothedIntegerEndpoints + float(wrapped + integerOnly),
        scene.a
    );
}
""",
            },
        ], {})
        fragment = normalized[1]["source"]
        self.assertIn("texSample2D(g_Texture0, v_TexCoord.xy)", fragment)
        self.assertIn("(g_PointerPosition * 0.5).x", fragment)
        self.assertIn(
            "float alreadyNarrowed = (g_PointerPosition * 0.5).x;",
            fragment,
        )
        self.assertNotIn("((g_PointerPosition * 0.5).x).x", fragment)
        self.assertIn("float projected = g_PointerPosition.x * 0.25;", fragment)
        self.assertIn(
            "float interpolated = mix(g_PointerPosition.x, g_PointerPosition.y, 0.5);",
            fragment,
        )
        self.assertIn("float magnitude = length(g_PointerPosition);", fragment)
        self.assertIn("float indexed = g_PointerPosition[0] * 0.25;", fragment)
        self.assertIn(
            "float left = g_PointerPosition.y * 0.05, right = left;",
            fragment,
        )
        self.assertIn(
            "numericBool += float(g_PointerPosition.x < 0.5);",
            fragment,
        )
        self.assertIn(
            "numericBool *= float(g_PointerPosition.x > 0.0 && g_PointerPosition.y < 1.0);",
            fragment,
        )
        self.assertIn(
            "uint wrapped = uint(mod(float(frequency), float(64)));",
            fragment,
        )
        self.assertIn("uint integerOnly = 65 % 64;", fragment)
        self.assertIn(
            "float interpolatedIntegerEndpoints = mix(0.0, 1.0, projected);",
            fragment,
        )
        self.assertIn(
            "float smoothedIntegerEndpoints = smoothstep(0.0, 1.0, projected);",
            fragment,
        )
        self.assertIn("vec3 finalColor = vec4(scene.r, scene.g, scene.b, 1.0).xyz;", fragment)

    def test_inactive_varying_call_is_not_pruned_without_purity_proof(self) -> None:
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
            tools, manifest, output = self.harness_setup(root)
            request = json.loads(FIXTURE.read_text(encoding="utf-8"))
            request["stages"][1]["source"] += "\nBROKEN\n"
            request_path = root / "request.json"
            request_path.write_text(json.dumps(request), encoding="utf-8")
            completed = self.run_harness(request_path, output, manifest, tools)
            self.assert_harness_failure(completed, output, "stage-link", "tool-rejected")

    def test_wallpaper_engine_dialect_is_normalized_by_public_shape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools, manifest, output = self.harness_setup(root)
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
            tools, manifest, output = self.harness_setup(root)
            request = json.loads(WE_FIXTURE.read_text(encoding="utf-8"))
            request["stages"][1]["source"] = request["stages"][1]["source"].replace(
                "varying vec2 v_TexCoord;",
                "varying vec2 v_TexCoord;\nvarying vec2 v_FragmentOnly;",
            ).replace(
                "void main() {",
                "void main() { vec2 liveValue = v_FragmentOnly;",
            )
            request_path = root / "request.json"
            request_path.write_text(json.dumps(request), encoding="utf-8")
            completed = self.run_harness(request_path, output, manifest, tools)
            self.assert_harness_failure(
                completed, output, "normalization", "varying-link", ["v_FragmentOnly"]
            )

    def test_unused_fragment_varying_is_not_part_of_linked_interface(self) -> None:
        normalized, summary = normalize_wallpaper_engine_pair([
            {
                "stage": "vertex", "entryPoint": "main",
                "source": """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_Live;
varying vec2 v_Optional;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_Live = a_TexCoord;
    v_Optional = a_TexCoord;
}
""",
            },
            {
                "stage": "fragment", "entryPoint": "main",
                "source": """varying vec2 v_Live;
varying vec4 v_Optional;
void main() { gl_FragColor = vec4(v_Live, 0.0, 1.0); }
""",
            },
        ], {})
        self.assertEqual(summary["inactiveFragmentVaryingsPruned"], 1)
        self.assertEqual(summary["varyingCount"], 2)
        self.assertNotIn("in vec4 v_Optional", normalized[1]["source"])
        self.assertIn("out vec2 v_Optional", normalized[0]["source"])

    def test_live_fragment_varying_shape_mismatch_remains_rejected(self) -> None:
        stages = [
            {
                "stage": "vertex", "entryPoint": "main",
                "source": """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_Live;
void main() { gl_Position = vec4(a_Position, 1.0); v_Live = a_TexCoord; }
""",
            },
            {
                "stage": "fragment", "entryPoint": "main",
                "source": """varying vec4 v_Live;
void main() { gl_FragColor = v_Live; }
""",
            },
        ]
        with self.assertRaises(HarnessFailure) as failure:
            normalize_wallpaper_engine_pair(stages, {})
        self.assertEqual(failure.exception.phase, "normalization")
        self.assertEqual(failure.exception.code, "varying-conflict")
        self.assertEqual(failure.exception.details, ["v_Live"])

    def test_hash_mismatch_fails_before_compilation(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools, manifest, output = self.harness_setup(root)
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            payload["verifiedDevelopmentArtifacts"][0]["glslangSHA256"] = "0" * 64
            manifest.write_text(json.dumps(payload), encoding="utf-8")
            completed = self.run_harness(FIXTURE, output, manifest, tools)
            self.assert_harness_failure(completed, output, "tool", "hash-mismatch")

    def test_timeout_kills_the_compiler_process_group(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-compiler-test-") as directory:
            root = Path(directory)
            tools, manifest, output = self.harness_setup(
                root, slow=True, timeout_ms=2500
            )
            completed = self.run_harness(FIXTURE, output, manifest, tools)
            self.assert_harness_failure(completed, output, "stage-link", "timeout")


if __name__ == "__main__":
    unittest.main()

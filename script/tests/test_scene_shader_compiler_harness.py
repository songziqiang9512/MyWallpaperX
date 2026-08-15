#!/usr/bin/env python3
"""Tests for the bounded observe-only upstream shader compiler harness."""

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
            self.assertEqual(artifact["kind"], "scene-generic-shader-program-artifact")
            self.assertEqual(len(artifact["requestKey"]), 64)
            self.assertEqual(artifact["routeState"], "prefer-generic")
            self.assertEqual(artifact["program"]["colorTransfer"], {
                "kind": "passthrough", "slot": 0
            })
            self.assertEqual(artifact["program"]["uniformLayout"]["byteSize"], 16)
            self.assertEqual(artifact["program"]["metalPreflight"]["bytes"], 3)
            self.assertIn("MWXVertexUniforms", artifact["program"]["metalSource"])
            self.assertIn("MWXFragmentUniforms", artifact["program"]["metalSource"])

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

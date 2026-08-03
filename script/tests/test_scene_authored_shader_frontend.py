#!/usr/bin/env python3

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPO_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPO_ROOT / "script"))

from scene_real_test_fixtures import sample_cache_root


SWIFT_SOURCES = [
    SCENE_ROOT / "Format/SceneJSONValue.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderSourceGraph.swift",
    SCENE_ROOT / "RenderGraph/SceneShaderContract.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontendModel.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLexer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
]

HARNESS = r"""
import Foundation
import Metal

private struct HarnessOutput: Codable {
    let diagnosticCodes: [String]
    let staticLoopWork: Int?
    let offscreenWidth: Int?
    let offscreenHeight: Int?
    let metalError: String?
}

@main
private struct AuthoredShaderFrontendHarness {
    static func main() throws {
        let vertexSource = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        let fragmentSource = try String(
            contentsOfFile: CommandLine.arguments[2],
            encoding: .utf8
        )
        let output = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertexSource,
            fragmentSource: fragmentSource
        )
        var metalError: String?
        if let program = output.program,
           CommandLine.arguments.dropFirst(3).first != "--skip-metal" {
            do {
                guard let device = MTLCreateSystemDefaultDevice() else {
                    throw NSError(
                        domain: "AuthoredShaderFrontendHarness",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Metal device unavailable"]
                    )
                }
                _ = try device.makeLibrary(source: program.metalSource, options: nil)
            } catch {
                metalError = String(describing: error)
            }
        }
        let encoded = try JSONEncoder().encode(HarnessOutput(
            diagnosticCodes: output.diagnostics.map { $0.code.rawValue },
            staticLoopWork: output.program?.staticLoopWork,
            offscreenWidth: output.program?.offscreenSize(
                viewportSize: CGSize(width: 3840, height: 2160)
            ).map { Int($0.width) },
            offscreenHeight: output.program?.offscreenSize(
                viewportSize: CGSize(width: 3840, height: 2160)
            ).map { Int($0.height) },
            metalError: metalError
        ))
        FileHandle.standardOutput.write(encoded)
    }
}
"""

VERTEX_SOURCE = """
uniform mat4 g_ModelViewProjectionMatrix;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    v_TexCoord = a_TexCoord;
}
"""


class SceneAuthoredShaderFrontendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "AuthoredShaderFrontendHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "authored-shader-frontend-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(build_root / "clang-module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(build_root / "swift-module-cache")
        subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPO_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.build_directory.cleanup()

    def compile(self, vertex_source, fragment_source, *, metal=True):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            vertex = root / "fixture.vert"
            fragment = root / "fixture.frag"
            vertex.write_text(textwrap.dedent(vertex_source), encoding="utf-8")
            fragment.write_text(textwrap.dedent(fragment_source), encoding="utf-8")
            command = [str(self.binary), str(vertex), str(fragment)]
            if not metal:
                command.append("--skip-metal")
            completed = subprocess.run(
                command,
                cwd=REPO_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        return json.loads(completed.stdout)

    def test_unrelated_textured_shader_compiles_to_metal(self):
        output = self.compile(
            VERTEX_SOURCE,
            """
            uniform sampler2D g_Texture0;
            uniform float g_Strength;
            varying vec2 v_TexCoord;
            float scaleValue(float value) { return value * g_Strength; }
            void main() {
                vec4 sampled = texture2D(g_Texture0, v_TexCoord);
                gl_FragColor = vec4(sampled.rgb * scaleValue(0.5), sampled.a);
            }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertIsNone(output.get("metalError"))

    def test_overloaded_functions_do_not_crash_or_look_recursive(self):
        output = self.compile(
            VERTEX_SOURCE,
            """
            varying vec2 v_TexCoord;
            float distanceField(vec3 point, float radius) {
                return length(point) - radius;
            }
            float distanceField(vec3 point, vec3 origin, float radius) {
                return length(point - origin) - radius;
            }
            void main() {
                float value = distanceField(vec3(v_TexCoord, 0.0), vec3(0.0), 0.5);
                gl_FragColor = vec4(value);
            }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertIsNone(output.get("metalError"))

    def test_dynamic_and_unbounded_control_flow_fail_closed(self):
        dynamic = self.compile(
            VERTEX_SOURCE,
            """
            uniform int g_Count;
            varying vec2 v_TexCoord;
            void main() {
                float value = 0.0;
                for (int index = 0; index < g_Count; index++) { value += 1.0; }
                gl_FragColor = vec4(value);
            }
            """,
            metal=False,
        )
        unbounded = self.compile(
            VERTEX_SOURCE,
            """
            varying vec2 v_TexCoord;
            void main() {
                while (v_TexCoord.x > 0.0) { break; }
                gl_FragColor = vec4(1.0);
            }
            """,
            metal=False,
        )
        self.assertEqual(dynamic["diagnosticCodes"], ["dynamicLoop"])
        self.assertEqual(unbounded["diagnosticCodes"], ["unsupportedControlFlow"])

    def test_recursion_and_static_work_over_budget_fail_closed(self):
        recursive = self.compile(
            VERTEX_SOURCE,
            """
            varying vec2 v_TexCoord;
            float cycle(float value) { return cycle(value); }
            void main() { gl_FragColor = vec4(cycle(v_TexCoord.x)); }
            """,
            metal=False,
        )
        loops = "\n".join(
            f"for (int index{i} = 0; index{i} < 256; index{i}++) {{ value += 1.0; }}"
            for i in range(17)
        )
        over_budget = self.compile(
            VERTEX_SOURCE,
            f"""
            varying vec2 v_TexCoord;
            void main() {{
                float value = 0.0;
                {loops}
                gl_FragColor = vec4(value);
            }}
            """,
            metal=False,
        )
        self.assertEqual(recursive["diagnosticCodes"], ["recursiveFunction"])
        self.assertEqual(over_budget["diagnosticCodes"], ["loopBudgetExceeded"])

    def test_loop_cost_expands_calls_inside_static_loops(self):
        output = self.compile(
            VERTEX_SOURCE,
            """
            varying vec2 v_TexCoord;
            float expensive(float value) {
                for (int inner = 0; inner < 256; inner++) { value += 1.0; }
                return value;
            }
            void main() {
                float value = 0.0;
                for (int outer = 0; outer < 32; outer++) { value += expensive(value); }
                gl_FragColor = vec4(value);
            }
            """,
            metal=False,
        )
        self.assertEqual(output["diagnosticCodes"], ["loopBudgetExceeded"])

    def test_offscreen_size_preserves_native_viewport_despite_static_loop_work(self):
        loops = "\n".join(
            f"for (int index{i} = 0; index{i} < 256; index{i}++) {{ value += 1.0; }}"
            for i in range(16)
        )
        output = self.compile(
            VERTEX_SOURCE,
            f"""
            varying vec2 v_TexCoord;
            void main() {{
                float value = 0.0;
                {loops}
                gl_FragColor = vec4(value);
            }}
            """,
            metal=False,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertEqual(output["offscreenWidth"], 3840)
        self.assertEqual(output["offscreenHeight"], 2160)
        self.assertGreater(output["staticLoopWork"], 1)

    def test_stage_link_mismatch_fails_closed(self):
        output = self.compile(
            VERTEX_SOURCE,
            """
            varying vec3 v_TexCoord;
            void main() { gl_FragColor = vec4(v_TexCoord, 1.0); }
            """,
            metal=False,
        )
        self.assertEqual(output["diagnosticCodes"], ["stageLinkMismatch"])

    def test_uniform_upload_budget_fails_closed(self):
        declarations = "\n".join(
            f"uniform vec4 u_Value{index};" for index in range(300)
        )
        output = self.compile(
            VERTEX_SOURCE,
            f"""
            {declarations}
            varying vec2 v_TexCoord;
            void main() {{ gl_FragColor = vec4(v_TexCoord, 0.0, 1.0); }}
            """,
            metal=False,
        )
        self.assertEqual(output["diagnosticCodes"], ["invalidUniformLayout"])

    def test_isolated_314_shader_enters_the_same_frontend(self):
        cache = sample_cache_root("3141421197")
        vertex = cache / "shaders/effects/myfirstshader.vert"
        fragment = cache / "shaders/effects/myfirstshader.frag"
        if not vertex.is_file() or not fragment.is_file():
            self.skipTest("isolated 3141421197 shader fixture is unavailable")
        completed = subprocess.run(
            [str(self.binary), str(vertex), str(fragment)],
            cwd=REPO_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertIsNone(output.get("metalError"))
        self.assertEqual(output["offscreenWidth"], 3840)
        self.assertEqual(output["offscreenHeight"], 2160)
        self.assertGreater(output["staticLoopWork"], 1)


if __name__ == "__main__":
    unittest.main()

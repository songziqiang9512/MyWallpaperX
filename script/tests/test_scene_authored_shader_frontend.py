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
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderBoundedLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderStaticLoopAdmission.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderLoopAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSyntax.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderDeadBindingAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalSource.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVectorConversion.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFunctionSemantics.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderVaryingArrayEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderMetalEmitter+Translation.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderColorTransferAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderSameSlotMixGraphAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderOpaqueInputAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderIndependentAlphaAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderPremultipliedOutputAnalyzer.swift",
    SCENE_ROOT / "RenderGraph/SceneAuthoredShaderFrontend.swift",
]

HARNESS = r"""
import Foundation
import Metal

private struct HarnessOutput: Codable {
    let diagnosticCodes: [String]
    let staticLoopWork: Int?
    let textureSlots: [Int]?
    let uniformNames: [String]?
    let offscreenWidth: Int?
    let offscreenHeight: Int?
    let metalSource: String?
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
            textureSlots: output.program?.textureBindings.map(\.slot),
            uniformNames: output.program?.uniformLayout.fields.map(\.name),
            offscreenWidth: output.program?.offscreenSize(
                viewportSize: CGSize(width: 3840, height: 2160)
            ).map { Int($0.width) },
            offscreenHeight: output.program?.offscreenSize(
                viewportSize: CGSize(width: 3840, height: 2160)
            ).map { Int($0.height) },
            metalSource: output.program?.metalSource,
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

VEC4_COORDINATE_VERTEX_SOURCE = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_Coordinates;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_Coordinates = vec4(a_TexCoord, 0.0, 1.0);
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

    def test_two_texture_rgb_blend_preserves_source_alpha_in_program(self):
        output = self.compile(
            VERTEX_SOURCE,
            """
            uniform sampler2D g_Texture0;
            uniform sampler2D g_Texture1;
            uniform float g_Multiply;
            varying vec2 v_TexCoord;
            vec3 fixtureBlend(
                const int mode,
                in vec3 base,
                in vec3 overlay,
                in float weight
            ) {
                if (mode == 0) {
                    return mix(base, overlay, weight);
                }
                return base;
            }
            void main() {
                vec4 base = texSample2D(g_Texture0, v_TexCoord);
                vec4 overlay = texSample2D(g_Texture1, v_TexCoord);
                float weight = g_Multiply * overlay.a;
                base.rgb = fixtureBlend(0, base.rgb, overlay.rgb, weight);
                gl_FragColor = base;
            }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertEqual(output["textureSlots"], [0, 1])
        self.assertIn("mwxUnpremultiply(mwxTexture0.sample", output["metalSource"])
        self.assertIn("return mwxPremultiply(mwxFragColor);", output["metalSource"])
        self.assertIsNone(output.get("metalError"))

    def test_float_vector_narrowing_matches_cross_backend_authored_forms(self):
        function_argument = self.compile(
            VEC4_COORDINATE_VERTEX_SOURCE,
            """
            varying vec4 v_Coordinates;
            vec2 fixtureCoordinates(vec2 value, float amount) {
                return value * amount;
            }
            void main() {
                vec2 coordinates = fixtureCoordinates(v_Coordinates, 0.5);
                gl_FragColor = vec4(coordinates, 0.0, 1.0);
            }
            """,
        )
        compact_function_source = function_argument["metalSource"].replace(" ", "")
        self.assertEqual(function_argument["diagnosticCodes"], [])
        self.assertIn("(mwxInput.v_Coordinates).xy", compact_function_source)
        self.assertIsNone(function_argument.get("metalError"))

    def test_mat3_inverse_and_inout_parameters_translate_to_metal(self):
        output = self.compile(
            """
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            mat3 squareToQuad(vec2 point0, vec2 point1, vec2 point2, vec2 point3) {
                return mat3(
                    vec3(1.0, 0.0, 0.0),
                    vec3(0.0, 1.0, 0.0),
                    vec3(0.0, 0.0, 1.0)
                );
            }
            void main() {
                mat3 transform = inverse(squareToQuad(
                    vec2(0.0), vec2(1.0, 0.0), vec2(1.0), vec2(0.0, 1.0)
                ));
                v_TexCoord = mul(vec3(a_TexCoord, 1.0), transform).xy;
                gl_Position = vec4(a_Position, 1.0);
            }
            """,
            """
            varying vec2 v_TexCoord;
            void accumulate(const vec3 delta, inout vec3 result) {
                result += delta;
            }
            void main() {
                vec3 result = vec3(v_TexCoord, 0.0);
                accumulate(vec3(0.0, 0.0, 1.0), result);
                gl_FragColor = vec4(result, 1.0);
            }
            """,
        )
        compact_source = output["metalSource"].replace(" ", "")
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertIn("mwxInverseFloat3x3", output["metalSource"])
        self.assertIn("threadfloat3&result", compact_source)
        self.assertIsNone(output.get("metalError"))

        unsupported_inverse = self.compile(
            VERTEX_SOURCE,
            """
            varying vec2 v_TexCoord;
            void main() {
                mat4 value = mat4(1.0);
                gl_FragColor = inverse(value)[0];
            }
            """,
            metal=False,
        )
        malformed_inout = self.compile(
            VERTEX_SOURCE,
            """
            varying vec2 v_TexCoord;
            void mutate(inout vec3 values[2]) { values[0] += vec3(1.0); }
            void main() { gl_FragColor = vec4(v_TexCoord, 0.0, 1.0); }
            """,
            metal=False,
        )
        self.assertEqual(unsupported_inverse["diagnosticCodes"], ["unsupportedDeclaration"])
        self.assertEqual(malformed_inout["diagnosticCodes"], ["unsupportedDeclaration"])

        texture_result = self.compile(
            VERTEX_SOURCE,
            """
            uniform sampler2D g_Texture0;
            varying vec2 v_TexCoord;
            void main() {
                vec3 color = texSample2D(g_Texture0, v_TexCoord);
                gl_FragColor = vec4(color, 1.0);
            }
            """,
        )
        compact_texture_source = texture_result["metalSource"].replace(" ", "")
        self.assertEqual(texture_result["diagnosticCodes"], [])
        self.assertIn("float3color=(mwxTexture0.sample", compact_texture_source)
        self.assertIn(")).xyz;", compact_texture_source)
        self.assertIsNone(texture_result.get("metalError"))

        assignment_result = self.compile(
            """
            uniform mat4 g_ModelViewProjectionMatrix;
            uniform vec2 g_PointerPosition;
            uniform vec2 g_Scale;
            uniform vec2 g_Aspect;
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_Delta;
            void main() {
                gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
                vec4 transformed = vec4(g_PointerPosition, 0.0, 1.0);
                vec2 delta = transformed * g_Scale * g_Aspect * 0.001;
                v_Delta = delta;
            }
            """,
            """
            varying vec2 v_Delta;
            void main() { gl_FragColor = vec4(v_Delta, 0.0, 1.0); }
            """,
        )
        compact_assignment_source = assignment_result["metalSource"].replace(" ", "")
        self.assertEqual(assignment_result["diagnosticCodes"], [])
        self.assertIn("float2delta=(transformed).xy", compact_assignment_source)
        self.assertIn(
            "*mwxUniforms.g_Scale*mwxUniforms.g_Aspect*0.001;",
            compact_assignment_source,
        )
        self.assertIsNone(assignment_result.get("metalError"))

        staged_result = self.compile(
            VERTEX_SOURCE,
            """
            uniform vec3 g_Coordinates;
            varying vec2 v_TexCoord;
            void main() {
                vec4 expanded = vec4(v_TexCoord, 1.0, 1.0);
                vec2 reduced = expanded / g_Coordinates * 0.5;
                gl_FragColor = vec4(reduced, 0.0, 1.0);
            }
            """,
        )
        compact_staged_source = staged_result["metalSource"].replace(" ", "")
        self.assertEqual(staged_result["diagnosticCodes"], [])
        self.assertIn("((expanded).xyz/", compact_staged_source)
        self.assertIn("mwxUniforms.g_Coordinates*0.5).xy;", compact_staged_source)
        self.assertIsNone(staged_result.get("metalError"))

    def test_float_vector_narrowing_does_not_guess_unsupported_conversions(self):
        fixtures = [
            """
            uniform vec2 g_Coordinates;
            vec3 fixtureValue(vec3 value) { return value; }
            void main() {
                vec3 value = fixtureValue(g_Coordinates);
                gl_FragColor = vec4(value, 1.0);
            }
            """,
            """
            uniform vec4 g_Coordinates;
            vec2 ambiguousValue(vec2 value) { return value; }
            vec3 ambiguousValue(vec3 value) { return value; }
            void main() {
                gl_FragColor = vec4(ambiguousValue(g_Coordinates), 1.0);
            }
            """,
            """
            uniform ivec4 g_Integer;
            ivec2 integerValue(ivec2 value) { return value; }
            void main() {
                ivec2 value = integerValue(g_Integer);
                gl_FragColor = vec4(value, 0, 1);
            }
            """,
            """
            uniform sampler2D g_Texture0;
            varying vec2 v_TexCoord;
            void main() {
                vec4 base = texSample2D(g_Texture0, v_TexCoord);
                vec3 color = texSample2D(g_Texture0, v_TexCoord) + base;
                gl_FragColor = vec4(color, 1.0);
            }
            """,
        ]
        for fragment_source in fixtures:
            with self.subTest(fragment_source=fragment_source):
                output = self.compile(VERTEX_SOURCE, fragment_source)
                compact_source = output["metalSource"].replace(" ", "")
                self.assertNotIn("(mwxUniforms.g_Coordinates).xy", compact_source)
                self.assertNotIn("(mwxUniforms.g_Coordinates).xyz", compact_source)
                self.assertNotIn("(mwxUniforms.g_Integer).xy", compact_source)
                self.assertNotIn(")).xyz+", compact_source)
                self.assertIsNotNone(output.get("metalError"))

    def test_explicit_float_vector_swizzle_is_not_narrowed_twice(self):
        output = self.compile(
            VEC4_COORDINATE_VERTEX_SOURCE,
            """
            varying vec4 v_Coordinates;
            vec2 fixtureCoordinates(vec2 value) { return value; }
            void main() {
                vec2 coordinates = fixtureCoordinates(v_Coordinates.xy);
                gl_FragColor = vec4(coordinates, 0.0, 1.0);
            }
            """,
        )
        compact_source = output["metalSource"].replace(" ", "")
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertNotIn("((mwxInput.v_Coordinates).xy).xy", compact_source)
        self.assertIsNone(output.get("metalError"))

    def test_dead_optional_sampler_and_resolution_varying_write_are_projected(self):
        output = self.compile(
            """
            uniform vec4 g_Texture1Resolution;
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec4 v_Coordinates;
            void main() {
                gl_Position = vec4(a_Position, 1.0);
                v_Coordinates.xy = a_TexCoord;
                v_Coordinates.zw = vec2(
                    v_Coordinates.x * g_Texture1Resolution.z / g_Texture1Resolution.x,
                    v_Coordinates.y * g_Texture1Resolution.w / g_Texture1Resolution.y
                );
            }
            """,
            """
            uniform sampler2D g_Texture0;
            uniform sampler2D g_Texture1;
            varying vec4 v_Coordinates;
            void main() {
                gl_FragColor = texSample2D(g_Texture0, v_Coordinates.xy);
            }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertEqual(output["textureSlots"], [0])
        self.assertNotIn("g_Texture1Resolution", output["uniformNames"])
        self.assertNotIn("g_Texture1Resolution", output["metalSource"])
        self.assertIsNone(output.get("metalError"))

    def test_inactive_sampler_resolution_stays_live_when_output_depends_on_it(self):
        fixtures = [
            (
                "gl_Position = vec4(a_Position.xy * g_Texture1Resolution.xy, 0.0, 1.0);",
                "v_Coordinates.xy = a_TexCoord;",
                "v_Coordinates.xy",
            ),
            (
                "gl_Position = vec4(a_Position, 1.0);",
                "v_Coordinates.xy = a_TexCoord * g_Texture1Resolution.xy;",
                "v_Coordinates.xy",
            ),
            (
                "gl_Position = vec4(a_Position, 1.0);",
                "v_Coordinates.zw = normalize(g_Texture1Resolution.xy);",
                "v_Coordinates.xy",
            ),
        ]
        for position, assignment, fragment_coordinates in fixtures:
            with self.subTest(assignment=assignment):
                output = self.compile(
                    f"""
                    uniform vec4 g_Texture1Resolution;
                    attribute vec3 a_Position;
                    attribute vec2 a_TexCoord;
                    varying vec4 v_Coordinates;
                    void main() {{
                        {position}
                        {assignment}
                    }}
                    """,
                    f"""
                    uniform sampler2D g_Texture0;
                    uniform sampler2D g_Texture1;
                    varying vec4 v_Coordinates;
                    void main() {{
                        gl_FragColor = texSample2D(g_Texture0, {fragment_coordinates});
                    }}
                    """,
                )
                self.assertEqual(output["textureSlots"], [0, 1])
                self.assertIn("g_Texture1Resolution", output["uniformNames"])
                self.assertIn("g_Texture1Resolution", output["metalSource"])
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

    def test_function_root_const_int_loop_bound_compiles_to_metal(self):
        output = self.compile(
            VERTEX_SOURCE,
            """
            #define CAST_SAMPLE_COUNT 30
            varying vec2 v_TexCoord;
            void main() {
                const int sampleCount = CAST_SAMPLE_COUNT;
                float value = 0.0;
                for (int index = 0; index < sampleCount; ++index) {
                    value += v_TexCoord.x;
                }
                gl_FragColor = vec4(value);
            }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertEqual(output["staticLoopWork"], 30)
        self.assertIsNone(output.get("metalError"))

    def test_static_float_loop_bound_with_dynamic_early_exit_compiles_to_metal(self):
        output = self.compile(
            VERTEX_SOURCE,
            """
            uniform sampler2D g_Texture0;
            uniform mat4 g_ProjectionInverse;
            varying vec2 v_TexCoord;
            float boundedSample(vec2 coordinates) {
                float numLayers = 24;
                float currentLayerDepth = 1.0;
                float currentDepthMapValue = texSample2D(g_Texture0, coordinates).r;
                for (float index = 0.0;
                     currentLayerDepth > currentDepthMapValue && index < numLayers;
                     index++) {
                    currentLayerDepth -= 1.0 / numLayers;
                }
                mat3 rotation = CAST3X3(g_ProjectionInverse);
                vec3 direction = mul(vec3(1.0, 0.0, 0.0), rotation);
                return currentLayerDepth + direction.x;
            }
            void main() {
                gl_FragColor = vec4(boundedSample(v_TexCoord));
            }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertGreaterEqual(output["staticLoopWork"], 24)
        self.assertIsNone(output.get("metalError"))

    def test_dynamic_early_exit_loop_rejects_unproven_bounds_and_mutation(self):
        fixtures = [
            """
            uniform float g_Count;
            void main() {
                float remaining = 1.0;
                for (float index = 0.0; remaining > 0.0 && index < g_Count; index++) {
                    remaining -= 0.1;
                }
                gl_FragColor = vec4(remaining);
            }
            """,
            """
            void main() {
                float count = 24.0;
                float remaining = 1.0;
                for (float index = 0.0; remaining > 0.0 || index < count; index++) {
                    remaining -= 0.1;
                }
                gl_FragColor = vec4(remaining);
            }
            """,
            """
            void main() {
                float count = 24.0;
                float remaining = 1.0;
                for (float index = 0.0; index < remaining && index < count; index++) {
                    remaining -= 0.1;
                }
                gl_FragColor = vec4(remaining);
            }
            """,
            """
            void main() {
                float count = 24.0;
                float remaining = 1.0;
                for (float index = 0.0; remaining > 0.0 && index < count; index++) {
                    index = 0.0;
                    remaining -= 0.1;
                }
                gl_FragColor = vec4(remaining);
            }
            """,
            """
            void main() {
                float count = 24.0;
                count = 32.0;
                float remaining = 1.0;
                for (float index = 0.0; remaining > 0.0 && index < count; index++) {
                    remaining -= 0.1;
                }
                gl_FragColor = vec4(remaining);
            }
            """,
        ]
        for fragment_source in fixtures:
            with self.subTest(fragment_source=fragment_source):
                output = self.compile(
                    VERTEX_SOURCE,
                    fragment_source,
                    metal=False,
                )
                self.assertEqual(output["diagnosticCodes"], ["dynamicLoop"])

    def test_const_int_loop_bound_rejects_unproven_or_mutable_forms(self):
        fixtures = [
            """
            void main() {
                int sampleCount = 30;
                for (int index = 0; index < sampleCount; ++index) {}
                gl_FragColor = vec4(1.0);
            }
            """,
            """
            void main() {
                const float sampleCount = 30.0;
                for (int index = 0; index < sampleCount; ++index) {}
                gl_FragColor = vec4(1.0);
            }
            """,
            """
            void main() {
                if (true) { const int sampleCount = 30; }
                for (int index = 0; index < sampleCount; ++index) {}
                gl_FragColor = vec4(1.0);
            }
            """,
            """
            void main() {
                const int sampleCount = 30;
                if (true) { const int sampleCount = 20; }
                for (int index = 0; index < sampleCount; ++index) {}
                gl_FragColor = vec4(1.0);
            }
            """,
            """
            void main() {
                const int sampleCount = 30;
                for (int index = 0; index < sampleCount; ++index) {}
                sampleCount = 20;
                gl_FragColor = vec4(1.0);
            }
            """,
            """
            void main() {
                for (int index = 0; index < sampleCount; ++index) {}
                const int sampleCount = 30;
                gl_FragColor = vec4(1.0);
            }
            """,
            """
            void main() {
                const int sampleCount = 300;
                for (int index = 0; index < sampleCount; ++index) {}
                gl_FragColor = vec4(1.0);
            }
            """,
        ]
        for fragment_source in fixtures:
            with self.subTest(fragment_source=fragment_source):
                output = self.compile(
                    VERTEX_SOURCE,
                    fragment_source,
                    metal=False,
                )
                self.assertEqual(output["diagnosticCodes"], ["dynamicLoop"])

    def test_uniform_bounded_parameter_array_loop_compiles_to_metal(self):
        output = self.compile(
            """
            uniform mat4 g_ModelViewProjectionMatrix;
            uniform float g_AudioSpectrum16Left[16];
            uniform float g_AudioSpectrum16Right[16];
            uniform float g_RangeMinimum;
            uniform float g_RangeMaximum;
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying float v_Value;
            float accumulate(float bufferLeft[16], float bufferRight[16]) {
                float value = 0.0;
                for (int index = int(g_RangeMinimum);
                     index <= int(g_RangeMaximum);
                     ++index) {
                    value += bufferLeft[index];
                    value += bufferRight[index];
                }
                return value / (g_RangeMaximum - g_RangeMinimum + 1.0);
            }
            void main() {
                gl_Position = mul(vec4(a_Position, 1.0),
                    g_ModelViewProjectionMatrix);
                v_Value = accumulate(
                    g_AudioSpectrum16Left,
                    g_AudioSpectrum16Right
                );
            }
            """,
            """
            varying float v_Value;
            void main() { gl_FragColor = vec4(v_Value); }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertIsNone(output.get("metalError"))
        self.assertGreaterEqual(output["staticLoopWork"], 16)
        self.assertIn(
            "clamp(mwxUniforms.g_RangeMinimum, 0.0, 15.0)",
            output["metalSource"],
        )
        self.assertIn(
            "clamp(mwxUniforms.g_RangeMaximum, 0.0, 15.0)",
            output["metalSource"],
        )
        self.assertEqual(
            output["metalSource"].count(
                "clamp(mwxUniforms.g_RangeMinimum, 0.0, 15.0)"
            ),
            1,
        )
        self.assertEqual(
            output["metalSource"].count(
                "clamp(mwxUniforms.g_RangeMaximum, 0.0, 15.0)"
            ),
            1,
        )
        self.assertIn(
            "mwxUniforms.g_RangeMaximum - mwxUniforms.g_RangeMinimum",
            output["metalSource"],
        )

    def test_fixed_float_varying_array_compiles_to_metal(self):
        output = self.compile(
            """
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_Samples[3];
            void main() {
                gl_Position = vec4(a_Position, 1.0);
                v_Samples[0] = a_TexCoord;
                v_Samples[1] = a_TexCoord + vec2(0.1);
                v_Samples[2] = a_TexCoord - vec2(0.1);
            }
            """,
            """
            varying vec2 v_Samples[3];
            void main() {
                gl_FragColor = vec4(
                    v_Samples[0] + v_Samples[1] + v_Samples[2],
                    0.0,
                    1.0
                );
            }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertIsNone(output.get("metalError"))

    def test_varying_array_rejects_mismatch_integer_and_excessive_shapes(self):
        fixtures = [
            ("vec2", 3, "vec2", 4),
            ("ivec2", 3, "ivec2", 3),
            ("vec2", 17, "vec2", 17),
        ]
        for vertex_type, vertex_count, fragment_type, fragment_count in fixtures:
            with self.subTest(
                vertex_type=vertex_type,
                vertex_count=vertex_count,
                fragment_type=fragment_type,
                fragment_count=fragment_count,
            ):
                output = self.compile(
                    f"""
                    attribute vec3 a_Position;
                    varying {vertex_type} v_Samples[{vertex_count}];
                    void main() {{
                        gl_Position = vec4(a_Position, 1.0);
                        v_Samples[0] = {vertex_type}(0);
                    }}
                    """,
                    f"""
                    varying {fragment_type} v_Samples[{fragment_count}];
                    void main() {{ gl_FragColor = vec4(v_Samples[0], 0.0, 1.0); }}
                    """,
                    metal=False,
                )
                self.assertIn(
                    output["diagnosticCodes"][0],
                    ["unsupportedType", "stageLinkMismatch"],
                )

        dynamic_index = self.compile(
            """
            attribute vec3 a_Position;
            varying vec2 v_Samples[3];
            void main() {
                gl_Position = vec4(a_Position, 1.0);
                v_Samples[0] = vec2(0.0);
            }
            """,
            """
            uniform int g_Index;
            varying vec2 v_Samples[3];
            void main() { gl_FragColor = vec4(v_Samples[g_Index], 0.0, 1.0); }
            """,
            metal=False,
        )
        self.assertEqual(dynamic_index["diagnosticCodes"], ["unsupportedType"])

    def test_uniform_bounded_parameter_array_loop_rejects_unproven_shapes(self):
        fixtures = [
            """
            uniform float g_Minimum;
            uniform float g_Maximum;
            float accumulate(float values[16]) {
                float value = 0.0;
                for (int index = int(g_Minimum); index <= int(g_Maximum); ++index) {
                    value += values[index] + float(index);
                }
                return value;
            }
            void main() { gl_FragColor = vec4(1.0); }
            """,
            """
            uniform float g_Minimum;
            uniform float g_Maximum;
            float accumulate(float left[16], float right[32]) {
                float value = 0.0;
                for (int index = int(g_Minimum); index <= int(g_Maximum); ++index) {
                    value += left[index] + right[index];
                }
                return value;
            }
            void main() { gl_FragColor = vec4(1.0); }
            """,
            """
            uniform int g_Minimum;
            uniform float g_Maximum;
            float accumulate(float values[16]) {
                float value = 0.0;
                for (int index = int(g_Minimum); index <= int(g_Maximum); ++index) {
                    value += values[index];
                }
                return value;
            }
            void main() { gl_FragColor = vec4(1.0); }
            """,
            """
            uniform float g_Minimum;
            uniform float g_Maximum;
            float accumulate(float values[257]) {
                float value = 0.0;
                for (int index = int(g_Minimum); index <= int(g_Maximum); ++index) {
                    value += values[index];
                }
                return value;
            }
            void main() { gl_FragColor = vec4(1.0); }
            """,
            """
            uniform float g_Minimum;
            uniform float g_Maximum;
            float accumulate(float values[16]) {
                float value = 0.0;
                for (int index = int(g_Minimum); index <= int(g_Maximum); index += 1) {
                    value += values[index];
                }
                return value;
            }
            void main() { gl_FragColor = vec4(1.0); }
            """,
        ]
        for fragment_source in fixtures:
            with self.subTest(fragment_source=fragment_source):
                output = self.compile(
                    VERTEX_SOURCE,
                    fragment_source,
                    metal=False,
                )
                self.assertEqual(output["diagnosticCodes"], ["dynamicLoop"])

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

    def test_unused_fragment_varying_does_not_require_a_vertex_output(self):
        output = self.compile(
            VERTEX_SOURCE,
            """
            varying vec2 v_TexCoord;
            varying vec2 v_Unused;
            void main() { gl_FragColor = vec4(v_TexCoord, 0.0, 1.0); }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertIsNone(output.get("metalError"))

    def test_unused_uniform_does_not_enter_the_runtime_abi(self):
        output = self.compile(
            """
            uniform mat4 g_ModelViewProjectionMatrix;
            uniform vec4 g_Texture1Resolution;
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = mul(vec4(a_Position, 1.0),
                    g_ModelViewProjectionMatrix);
                v_TexCoord = a_TexCoord;
            }
            """,
            """
            varying vec2 v_TexCoord;
            void main() { gl_FragColor = vec4(v_TexCoord, 0.0, 1.0); }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertNotIn("g_Texture1Resolution", output["metalSource"])
        self.assertIsNone(output.get("metalError"))

    def test_uniform_upload_budget_fails_closed(self):
        declarations = "\n".join(
            f"uniform vec4 u_Value{index};" for index in range(300)
        )
        references = " + ".join(f"u_Value{index}" for index in range(300))
        output = self.compile(
            VERTEX_SOURCE,
            f"""
            {declarations}
            varying vec2 v_TexCoord;
            void main() {{ gl_FragColor = {references}; }}
            """,
            metal=False,
        )
        self.assertEqual(output["diagnosticCodes"], ["invalidUniformLayout"])

    def test_audio_spectrum_arrays_are_public_and_other_arrays_fail_closed(self):
        output = self.compile(
            VERTEX_SOURCE,
            """
            uniform float g_AudioSpectrum16Left[16];
            uniform float g_AudioSpectrum16Right[16];
            uniform float g_AudioSpectrum32Left[32];
            uniform float g_AudioSpectrum32Right[32];
            uniform float g_AudioSpectrum64Left[64];
            uniform float g_AudioSpectrum64Right[64];
            varying vec2 v_TexCoord;
            void main() {
                float value = g_AudioSpectrum16Left[0]
                    + g_AudioSpectrum32Right[1]
                    + g_AudioSpectrum64Left[2];
                gl_FragColor = vec4(value + v_TexCoord.x);
            }
            """,
        )
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertIsNone(output.get("metalError"))

        unknown = self.compile(
            VERTEX_SOURCE,
            """
            uniform float g_Unknown[16];
            varying vec2 v_TexCoord;
            void main() { gl_FragColor = vec4(g_Unknown[0]); }
            """,
            metal=False,
        )
        self.assertEqual(unknown["diagnosticCodes"], ["unsupportedType"])

        invalid_count = self.compile(
            VERTEX_SOURCE,
            """
            uniform float g_AudioSpectrum15Left[15];
            varying vec2 v_TexCoord;
            void main() { gl_FragColor = vec4(g_AudioSpectrum15Left[0]); }
            """,
            metal=False,
        )
        self.assertEqual(invalid_count["diagnosticCodes"], ["unsupportedType"])

        invalid_type = self.compile(
            VERTEX_SOURCE,
            """
            uniform vec4 g_AudioSpectrum16Left[16];
            varying vec2 v_TexCoord;
            void main() { gl_FragColor = g_AudioSpectrum16Left[0]; }
            """,
            metal=False,
        )
        self.assertEqual(invalid_type["diagnosticCodes"], ["unsupportedType"])

        conflicting_shape = self.compile(
            """
            uniform mat4 g_ModelViewProjectionMatrix;
            uniform float g_AudioSpectrum16Left;
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = mul(vec4(a_Position, 1.0),
                    g_ModelViewProjectionMatrix);
                v_TexCoord = a_TexCoord;
            }
            """,
            """
            uniform float g_AudioSpectrum16Left[16];
            varying vec2 v_TexCoord;
            void main() { gl_FragColor = vec4(g_AudioSpectrum16Left[0]); }
            """,
            metal=False,
        )
        self.assertEqual(conflicting_shape["diagnosticCodes"], [])
        self.assertIn("mwxV_g_AudioSpectrum16Left", conflicting_shape["uniformNames"])
        self.assertIn("mwxF_g_AudioSpectrum16Left", conflicting_shape["uniformNames"])

    def test_cross_stage_uniform_names_keep_stage_local_bindings(self):
        output = self.compile(
            """
            uniform float g_Speed;
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
                gl_Position = vec4(a_Position.x * g_Speed, a_Position.yz, 1.0);
                v_TexCoord = a_TexCoord;
            }
            """,
            """
            uniform float g_Speed;
            varying vec2 v_TexCoord;
            void main() {
                gl_FragColor = vec4(v_TexCoord, g_Speed, 1.0);
            }
            """,
        )
        compact_source = output["metalSource"].replace(" ", "")
        self.assertEqual(output["diagnosticCodes"], [])
        self.assertIn("mwxV_g_Speed", output["uniformNames"])
        self.assertIn("mwxF_g_Speed", output["uniformNames"])
        self.assertIn("a_Position.x*mwxUniforms.mwxV_g_Speed", compact_source)
        self.assertIn("v_TexCoord,mwxUniforms.mwxF_g_Speed,1.0", compact_source)
        self.assertIsNone(output.get("metalError"))

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

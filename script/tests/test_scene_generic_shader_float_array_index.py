#!/usr/bin/env python3

"""Stage-link gate for authored float-valued fixed-array subscripts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
from scene_swift_source_sets import scene_swift_sources  # noqa: E402


GLSLANG = REPOSITORY_ROOT / "MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"

SWIFT_SOURCES: list[Path] = []
for _set_name in ("authored_shader_frontend_core", "generic_shader_compiler_preparation_implementation"):
    for _source in scene_swift_sources(_set_name):
        if _source not in SWIFT_SOURCES:
            SWIFT_SOURCES.append(_source)
SWIFT_SOURCES.append(
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/Material/SceneResolvedMaterialGenericShaderProgramArtifact.swift"
)

HARNESS = r'''
import Foundation

@main
private struct FloatArrayIndexHarness {
    static func main() throws {
        let arguments = CommandLine.arguments
        let vertex = try String(contentsOfFile: arguments[1], encoding: .utf8)
        let fragment = try String(contentsOfFile: arguments[2], encoding: .utf8)
        let frontend = SceneAuthoredShaderFrontend.compile(
            vertexSource: vertex, fragmentSource: fragment
        )
        var result: [String: Any] = [
            "boundedHasProgram": frontend.program != nil,
            "boundedDiagnostics": frontend.diagnostics.map { $0.code.rawValue },
            "boundedMetal": frontend.program?.metalSource ?? "",
        ]
        switch SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertex,
            fragmentSource: fragment,
            maximumStageSourceBytes: 100_000
        ) {
        case let .success(pair):
            try pair.vertex.write(toFile: arguments[3], atomically: true, encoding: .utf8)
            try pair.fragment.write(toFile: arguments[4], atomically: true, encoding: .utf8)
            result["ok"] = true
            result["vertex"] = pair.vertex
            result["fragment"] = pair.fragment
        case let .failure(failure):
            result["ok"] = false
            result["failure"] = String(describing: failure)
        }
        print(json: result)
    }

    private static func print(json value: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
'''


class SceneGenericShaderFloatArrayIndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(tempfile.mkdtemp(prefix="mwx-float-array-index-"))
        harness = cls.root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = cls.root / "float-array-index"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(cls.root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(cls.root / "swift-cache")
        completed = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                *(str(source) for source in SWIFT_SOURCES), str(harness),
                "-module-cache-path", str(cls.root / "module-cache"),
                "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        import shutil

        shutil.rmtree(cls.root, ignore_errors=True)

    def _normalize(self, fragment: str, vertex: str | None = None) -> tuple[dict, Path]:
        vertex = vertex or """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec2 v_TexCoord;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord = a_TexCoord;
}
"""
        vertex_path = self.root / "input.vert"
        fragment_path = self.root / "input.frag"
        output_vertex = self.root / "output.vert"
        output_fragment = self.root / "output.frag"
        vertex_path.write_text(vertex, encoding="utf-8")
        fragment_path.write_text(fragment, encoding="utf-8")
        completed = subprocess.run(
            [
                str(self.binary), str(vertex_path), str(fragment_path),
                str(output_vertex), str(output_fragment),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(completed.stdout), output_fragment

    def test_float_index_is_cast_only_for_proven_fixed_float_arrays(self) -> None:
        positive, output = self._normalize("""uniform float g_AudioSpectrum32Left[32];
varying vec2 v_TexCoord;
void main() {
    float index = floor(v_TexCoord.x * 3.0);
    float localValues[32] = g_AudioSpectrum32Left;
    float value = localValues[index] + g_AudioSpectrum32Left[index];
    // localValues[index] in a comment must remain untouched.
    gl_FragColor = vec4(value);
}
""")
        self.assertTrue(positive["ok"], positive)
        source = output.read_text(encoding="utf-8")
        self.assertIn("localValues[int(index)]", source)
        self.assertIn("g_AudioSpectrum32Left[int(index)]", source)
        self.assertIn("localValues[index] in a comment", source)
        subprocess.run(
            [
                str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
                str(self.root / "output.vert"), str(output),
            ],
            cwd=self.root,
            check=True,
            capture_output=True,
            text=True,
        )

    def test_integer_and_unknown_indices_are_not_rewritten(self) -> None:
        result, output = self._normalize("""uniform float g_AudioSpectrum32Left[32];
varying vec2 v_TexCoord;
void main() {
    int integerIndex = 1;
    float values[32] = g_AudioSpectrum32Left;
    float known = values[integerIndex];
    float unknown = values[unknownIndex];
    gl_FragColor = vec4(known + unknown);
}
""")
        self.assertTrue(result["ok"], result)
        source = output.read_text(encoding="utf-8")
        self.assertIn("values[integerIndex]", source)
        self.assertIn("values[unknownIndex]", source)
        self.assertNotIn("int(integerIndex)", source)
        self.assertNotIn("int(unknownIndex)", source)

    def test_source_scalar_intrinsic_collision_preserves_author_function(self) -> None:
        result, output = self._normalize("""varying vec2 v_TexCoord;
float mod(float a, float b) { return a + b; }
void main() { gl_FragColor = vec4(mod(v_TexCoord.x, v_TexCoord.y)); }
""")
        self.assertTrue(result["ok"], result)
        source = output.read_text(encoding="utf-8")
        self.assertIn("float mwxAuthored_mod(float a, float b) { return a + b; }", source)
        self.assertIn("mwxAuthored_mod(v_TexCoord.x, v_TexCoord.y)", source)
        subprocess.run([
            str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
            str(self.root / "output.vert"), str(output)
        ], cwd=self.root, check=True, capture_output=True, text=True)
        for call in ["mod(v_TexCoord, v_TexCoord)", "mod(v_TexCoord.x + 1.0, v_TexCoord.y)"]:
            result, output = self._normalize(
                "varying vec2 v_TexCoord;\nfloat mod(float a, float b) { return a + b; }\n"
                "void main() { gl_FragColor = vec4(" + call + "); }\n"
            )
            self.assertTrue(result["ok"], result)
            self.assertNotIn("mwxAuthored_mod", output.read_text(encoding="utf-8"))

    def test_declaration_terminator_whitespace_is_insignificant(self) -> None:
        """A terminator followed only by whitespace is valid authored input.

        A real workshop fragment declared `varying vec2 v_TexCoord; ` (trailing
        space, no annotation); rejecting it as `declarationUnsupported` sent
        that effect to the shared-backend fallback.
        """
        result, output = self._normalize(
            "uniform sampler2D g_Texture0;\n"
            "varying vec2 v_TexCoord; \n"
            "uniform float u_Value;\t\n"
            "void main() { gl_FragColor = texSample2D(g_Texture0, v_TexCoord) * u_Value; }\n"
        )
        self.assertTrue(result["ok"], result)
        # The declaration survives as the linked stage interface entry.
        self.assertIn(
            "layout(location = 0) in vec2 v_TexCoord;",
            output.read_text(encoding="utf-8"),
        )

    def test_declaration_without_terminator_still_fails_closed(self) -> None:
        result, _output = self._normalize(
            "uniform sampler2D g_Texture0;\n"
            "varying vec2 v_TexCoord;\n"
            "uniform float u_Value\n"
            "void main() { gl_FragColor = vec4(u_Value); }\n"
        )
        self.assertFalse(result["ok"], result)
        self.assertEqual(result.get("failure"), "declarationUnsupported")

    def test_dead_uniform_stage_shapes_do_not_revoke_linked_program(self) -> None:
        vertex = """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
uniform vec2 u_Reference;
varying vec2 v_TexCoord;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_TexCoord = a_TexCoord;
}
"""
        fragment = """uniform float u_Reference;
varying vec2 v_TexCoord;
void main() { gl_FragColor = vec4(v_TexCoord, 0.25, 1.0); }
"""
        standard, _ = self._normalize(
            fragment.replace("uniform float u_Reference;\n", ""),
            vertex.replace("uniform vec2 u_Reference;\n", ""),
        )
        result, output = self._normalize(fragment, vertex)
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["vertex"], standard["vertex"])
        self.assertEqual(result["fragment"], standard["fragment"])
        subprocess.run([
            str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
            str(self.root / "output.vert"), str(output),
        ], cwd=self.root, check=True, capture_output=True, text=True)

    def test_fragment_member_declaration_preserves_complete_vec4(self) -> None:
        vertex = """attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_Span;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_Span = vec4(a_TexCoord, 0.1, 0.2);
}
"""
        for expression in (
            "vec4(v_Span.z, v_Span.w, v_Span.x, 1.0)",
            "texSample2D(g_Texture0, v_Span.xy + v_Span.zw)",
        ):
            outputs = []
            for suffix in ("", ".xy"):
                with self.subTest(expression=expression, suffix=suffix):
                    result, output = self._normalize(
                        "uniform sampler2D g_Texture0;\n"
                        f"varying vec4 v_Span{suffix}; // full linked value\n"
                        f"void main() {{ gl_FragColor = {expression}; }}\n",
                        vertex,
                    )
                    self.assertTrue(result["ok"], result)
                    self.assertTrue(result["boundedHasProgram"], result)
                    self.assertEqual(result["boundedDiagnostics"], [])
                    subprocess.run(
                        [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
                         str(self.root / "output.vert"), str(output)],
                        cwd=self.root, check=True, capture_output=True, text=True,
                    )
                    outputs.append((result["vertex"], result["fragment"], result["boundedMetal"]))
            self.assertEqual(outputs[0], outputs[1])

    def test_same_name_shadow_and_member_tokens_keep_shape_conflict_rejected(self) -> None:
        bodies = (
            ("u_Reference", "void main() { vec2 u_Reference = a_TexCoord; gl_Position = vec4(u_Reference, 0.0, 1.0); v_TexCoord = a_TexCoord; }"),
            ("u_Reference", "vec2 pass(vec2 u_Reference) { return u_Reference; }\nvoid main() { gl_Position = vec4(pass(a_TexCoord), 0.0, 1.0); v_TexCoord = a_TexCoord; }"),
            ("x", "void main() { gl_Position = vec4(a_Position.x, a_Position.y, 0.0, 1.0); v_TexCoord = a_TexCoord; }"),
            ("u_Reference", "void main() { v_TexCoord = a_TexCoord; for (int u_Reference = 0; u_Reference < 2; u_Reference++) v_TexCoord += vec2(float(u_Reference)); gl_Position = vec4(a_Position, 1.0); }"),
            ("u_Reference", "void main() { v_TexCoord = a_TexCoord; for (int u_Reference = 0; u_Reference < 2; u_Reference++) if (a_TexCoord.x < 0.5) { v_TexCoord += vec2(float(u_Reference)); } else v_TexCoord -= vec2(float(u_Reference)); gl_Position = vec4(a_Position, 1.0); }"),
        )
        for name, body in bodies:
            with self.subTest(name=name, body=body):
                vertex = ("attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
                          f"uniform vec2 {name};\nvarying vec2 v_TexCoord;\n{body}\n")
                fragment = (f"uniform float {name};\nvarying vec2 v_TexCoord;\n"
                            f"void main() {{ gl_FragColor = vec4({name}); }}\n")
                standard, _ = self._normalize(fragment, vertex.replace(f"uniform vec2 {name};\n", ""))
                self.assertTrue(standard["ok"], standard.get("failure"))
                subprocess.run([
                    str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
                    str(self.root / "output.vert"), str(self.root / "output.frag"),
                ], cwd=self.root, check=True, capture_output=True, text=True)
                result, _ = self._normalize(fragment, vertex)
                self.assertFalse(result["ok"], body)
                self.assertEqual(result.get("failure"), "uniformUnsupported")

    def test_initializer_and_selection_scopes_remain_legal_without_shape_conflict(self) -> None:
        for body in (
            "vec2 u_Reference = vec2(u_Reference);",
            "if (a_TexCoord.x < 0.5) vec2 u_Reference = vec2(0.25);",
        ):
            with self.subTest(body=body):
                vertex = ("attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
                          "uniform vec2 u_Reference;\nvarying vec2 v_TexCoord;\n"
                          "void main() { " + body + " gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord + u_Reference; }\n")
                fragment = ("uniform vec2 u_Reference;\nvarying vec2 v_TexCoord;\n"
                            "void main() { gl_FragColor = vec4(v_TexCoord + u_Reference, 0.0, 1.0); }\n")
                result, output = self._normalize(fragment, vertex)
                self.assertTrue(result["ok"], result.get("failure"))
                subprocess.run([
                    str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
                    str(self.root / "output.vert"), str(output),
                ], cwd=self.root, check=True, capture_output=True, text=True)

    def test_live_uniform_in_vertex_keeps_shape_when_fragment_declaration_is_dead(self) -> None:
        vertex = ("attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
                  "uniform vec2 u_Reference;\nvarying vec2 v_TexCoord;\n"
                  "void main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord + u_Reference; }\n")
        fragment = ("uniform float u_Reference;\nvarying vec2 v_TexCoord;\n"
                    "void main() { gl_FragColor = vec4(v_TexCoord, 0.0, 1.0); }\n")
        standard, _ = self._normalize(fragment.replace("uniform float u_Reference;\n", ""), vertex)
        result, output = self._normalize(fragment, vertex)
        self.assertTrue(result["ok"], result.get("failure"))
        self.assertEqual(result["vertex"], standard["vertex"])
        self.assertEqual(result["fragment"], standard["fragment"])
        subprocess.run([
            str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
            str(self.root / "output.vert"), str(output),
        ], cwd=self.root, check=True, capture_output=True, text=True)

    def test_active_stage_uniform_shape_conflicts_remain_rejected(self) -> None:
        bodies = (
            "void main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord + u_Reference; }",
            "void main() { vec2 value = u_Reference; gl_Position = vec4(a_Position, 1.0); v_TexCoord = value; }",
            "void main() { vec2 u_Reference = vec2(u_Reference); gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord + u_Reference; }",
            "void main() { if (a_TexCoord.x < 0.5) vec2 u_Reference = vec2(0.25); gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord + u_Reference; }",
            "vec2 value() { return u_Reference; }\nvoid main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = value(); }",
            "void main() { { vec2 u_Reference = a_TexCoord; v_TexCoord = u_Reference; } gl_Position = vec4(a_Position, 1.0); v_TexCoord += u_Reference; }",
            "void main() { v_TexCoord = a_TexCoord; for (int u_Reference = 0; u_Reference < 2; u_Reference++) { v_TexCoord += vec2(float(u_Reference)); } gl_Position = vec4(a_Position, 1.0); v_TexCoord += u_Reference; }",
            "void main() { v_TexCoord = a_TexCoord; for (int u_Reference = 0; u_Reference < 2; u_Reference++) v_TexCoord += vec2(float(u_Reference)); gl_Position = vec4(a_Position, 1.0); v_TexCoord += u_Reference; }",
            "void main() { v_TexCoord = a_TexCoord; for (int u_Reference = 0; u_Reference < 2; u_Reference++) for (int inner = 0; inner < 2; inner++) { v_TexCoord += vec2(float(u_Reference)); } gl_Position = vec4(a_Position, 1.0); v_TexCoord += u_Reference; }",
            "void main() { v_TexCoord = a_TexCoord; for (int u_Reference = 0; u_Reference < 2; u_Reference++) if (a_TexCoord.x < 0.5) { v_TexCoord += vec2(float(u_Reference)); } else v_TexCoord -= vec2(float(u_Reference)); gl_Position = vec4(a_Position, 1.0); v_TexCoord += u_Reference; }",
        )
        for body in bodies:
            with self.subTest(body=body):
                result, _ = self._normalize(
                    "uniform float u_Reference;\nvarying vec2 v_TexCoord;\n"
                    "void main() { gl_FragColor = vec4(u_Reference); }\n",
                    "attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
                    f"uniform vec2 u_Reference;\nvarying vec2 v_TexCoord;\n{body}\n",
                )
                self.assertFalse(result["ok"], body)
                self.assertEqual(result.get("failure"), "uniformUnsupported")

    def test_invalid_dead_uniform_shapes_still_fail_closed(self) -> None:
        vertex = ("attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
                  "uniform vec2 u_Reference;\nvarying vec2 v_TexCoord;\n"
                  "void main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord; }\n")
        for declaration, body in (
            ("uniform vec2 u_Reference[2];", "gl_FragColor = vec4(v_TexCoord, 0.0, 1.0);"),
            ("uniform Unknown u_Reference;", "gl_FragColor = vec4(v_TexCoord, 0.0, 1.0);"),
        ):
            with self.subTest(declaration=declaration):
                result, _ = self._normalize(
                    declaration + "\nvarying vec2 v_TexCoord;\nvoid main() { " + body + " }\n",
                    vertex,
                )
                self.assertFalse(result["ok"], result.get("failure"))
                self.assertEqual(result.get("failure"), "uniformUnsupported")
        fragment = ("uniform float u_Reference;\nvarying vec2 v_TexCoord;\n"
                    "void main() { if (v_TexCoord.x < 0.5) discard; gl_FragColor = vec4(u_Reference); }\n")
        standard, _ = self._normalize(fragment, vertex.replace("uniform vec2 u_Reference;\n", ""))
        result, output = self._normalize(fragment, vertex)
        self.assertTrue(result["ok"], result.get("failure"))
        self.assertEqual(result["vertex"], standard["vertex"])
        self.assertEqual(result["fragment"], standard["fragment"])
        subprocess.run([
            str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
            str(self.root / "output.vert"), str(output),
        ], cwd=self.root, check=True, capture_output=True, text=True)

    def test_member_declaration_rejects_unproven_storage_shape_and_suffix(self) -> None:
        declarations = (
            "uniform vec4 u_Value.xy;", "attribute vec4 a_Value.xy;",
            "varying vec2 v_Value.xy;", "varying vec3 v_Value.xy;",
            "varying vec4 v_Value.zw;", "varying vec4 v_Value.rg;",
            "varying vec4 v_Value.xq;", "varying vec4 v_Value.xy.z;",
            "varying vec4 v_Value.xy[2];", "varying vec4 v_Value[2].xy;",
            "varying vec4 v_Value.xy = vec4(1.0);",
            "varying vec4 v_Value.xy",
        )
        for declaration in declarations:
            with self.subTest(declaration=declaration):
                result, _ = self._normalize(
                    declaration + "\nvarying vec2 v_TexCoord;\n"
                    "void main() { gl_FragColor = vec4(v_TexCoord, 0.0, 1.0); }\n"
                )
                self.assertFalse(result["ok"], result)
                self.assertEqual(result.get("failure"), "declarationUnsupported")
                self.assertIn("unsupportedDeclaration", result["boundedDiagnostics"])
        result, _ = self._normalize(
            "varying vec2 v_TexCoord;\nvoid main() { gl_FragColor = vec4(v_TexCoord, 0.0, 1.0); }\n",
            "attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
            "varying vec4 v_Span.xy;\nvarying vec2 v_TexCoord;\n"
            "void main() { gl_Position = vec4(a_Position, 1.0); v_TexCoord = a_TexCoord; }\n",
        )
        self.assertFalse(result["ok"], result)
        self.assertEqual(result.get("failure"), "declarationUnsupported")
        self.assertIn("unsupportedDeclaration", result["boundedDiagnostics"])

    def test_member_declaration_cannot_supply_missing_vertex_components(self) -> None:
        result, _ = self._normalize(
            "uniform sampler2D g_Texture0;\nvarying vec4 v_Span.xy;\n"
            "void main() { gl_FragColor = texSample2D(g_Texture0, v_Span.xy + v_Span.zw); }\n",
            "attribute vec3 a_Position;\nattribute vec2 a_TexCoord;\n"
            "varying vec3 v_Span;\n"
            "void main() { gl_Position = vec4(a_Position, 1.0); v_Span = vec3(a_TexCoord, 0.5); }\n",
        )
        self.assertFalse(result["ok"], result)
        self.assertEqual(result.get("failure"), "varyingUnsupported")
        self.assertFalse(result["boundedHasProgram"], result)
        self.assertNotIn("unsupportedDeclaration", result["boundedDiagnostics"])

    def test_fragment_duplicate_varying_requires_matching_type_and_array_count(self) -> None:
        body = "void main() { gl_FragColor = vec4(v_TexCoord, 0.0, 1.0); }\n"
        result, output = self._normalize(
            "varying vec2 v_TexCoord;\nvarying vec2 v_TexCoord;\n" + body
        )
        self.assertTrue(result["ok"], result)
        subprocess.run(
            [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
             str(self.root / "output.vert"), str(output)],
            cwd=self.root, check=True, capture_output=True, text=True,
        )
        for repeated in ("varying vec3 v_TexCoord;", "varying vec2 v_TexCoord[2];"):
            with self.subTest(repeated=repeated):
                result, _ = self._normalize(
                    "varying vec2 v_TexCoord;\n" + repeated + "\n" + body
                )
                self.assertFalse(result["ok"], result)
                self.assertEqual(result.get("failure"), "declarationDuplicate")

    def test_member_and_function_identifiers_fail_closed(self) -> None:
        result, output = self._normalize("""uniform float g_AudioSpectrum32Left[32];
varying vec2 v_TexCoord;
struct Holder { float values[32]; };
float helper(float value) { return value; }
void main() {
    float index = floor(v_TexCoord.x * 3.0);
    float values[32] = g_AudioSpectrum32Left;
    Holder holder;
    float memberValue = holder.values[index];
    float functionValue = values[helper];
    gl_FragColor = vec4(memberValue + functionValue);
}
""")
        self.assertTrue(result["ok"], result)
        source = output.read_text(encoding="utf-8")
        self.assertIn("holder.values[index]", source)
        self.assertIn("values[helper]", source)
        self.assertNotIn("values[int(helper)]", source)

    def _link(self, fragment: Path) -> subprocess.CompletedProcess:
        return subprocess.run(
            [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
             str(self.root / "output.vert"), str(fragment)],
            cwd=self.root, capture_output=True, text=True,
        )

    def test_numeric_identifier_ternary_uses_proven_scalar_declarations(self) -> None:
        for kind, values, zero in (
            ("float", ("0.0", "1.0", "-0.5"), "0.0"),
            ("int", ("0", "2", "-2"), "0"),
            ("uint", ("0u", "2u"), "0u"),
        ):
            for value in values:
                with self.subTest(kind=kind, value=value):
                    result, output = self._normalize(
                        "varying vec2 v_TexCoord;\nvoid main() {\n"
                        f"    {kind} outside = {value}, inside = {value};\n"
                        "    float first = outside ? 0.25 : 0.75;\n"
                        "    float second = inside ? 0.5 : 1.0;\n"
                        "    gl_FragColor = vec4(first, second, 0.0, 1.0);\n}\n"
                    )
                    self.assertTrue(result["ok"], result)
                    source = output.read_text(encoding="utf-8")
                    self.assertIn(f"(outside != {zero}) ?", source)
                    self.assertIn(f"(inside != {zero}) ?", source)
                    linked = self._link(output)
                    self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_ternary_bool_comparison_and_numeric_literals_keep_selection(self) -> None:
        result, output = self._normalize(
            "varying vec2 v_TexCoord;\nvoid main() {\n"
            "    bool outside = v_TexCoord.x > 0.5;\n"
            "    float value = outside ? 0.25 : 0.75;\n"
            "    float comparison = v_TexCoord.y > 0.0 ? 0.5 : 1.0;\n"
            "    float zero = 0 ? 0.25 : 0.75;\n"
            "    float nonzero = 2 ? 0.5 : 1.0;\n"
            "    gl_FragColor = vec4(value, comparison, zero, nonzero);\n}\n"
        )
        self.assertTrue(result["ok"], result)
        source = output.read_text(encoding="utf-8")
        self.assertIn("outside ?", source)
        self.assertNotIn("outside !=", source)
        self.assertIn("v_TexCoord.y > 0.0 ?", source)
        self.assertIn("false ? 0.25 : 0.75", source)
        self.assertIn("true ? 0.5 : 1.0", source)
        linked = self._link(output)
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_unproven_ternary_identifier_remains_rejected(self) -> None:
        for declarations, body in (
            ("", ""),
            ("", "vec2 outside = vec2(1.0);"),
            ("", "float outside[2];"),
            ("float outside() { return 1.0; }", ""),
            ("float outside = 1.0;", "float outside = 0.0;"),
            ("float outside = 1.0;", "float first = 1.0, outside = 0.0;"),
            ("float outside = 1.0;", "vec2 first = vec2(1.0), outside = vec2(0.0);"),
            ("struct Holder { float outside; };", "float outside = 1.0;"),
        ):
            with self.subTest(declarations=declarations, body=body):
                result, output = self._normalize(
                    "varying vec2 v_TexCoord;\n" + declarations
                    + "\nvoid main() {\n" + body
                    + "\n    gl_FragColor = outside ? vec4(0.25) : vec4(0.75);\n}\n"
                )
                self.assertTrue(result["ok"], result)
                source = output.read_text(encoding="utf-8")
                self.assertIn("outside ?", source)
                self.assertNotIn("outside !=", source)
                linked = self._link(output)
                self.assertNotEqual(linked.returncode, 0, source)

    def test_boolean_arithmetic_preserves_unique_declaration_proof(self) -> None:
        result, output = self._normalize(
            "varying vec2 v_TexCoord;\nvoid main() {\n"
            "    bool ready = v_TexCoord.x > 0.5;\n"
            "    float value = 0.0;\n"
            "    value = ready;\n"
            "    gl_FragColor = vec4(value);\n}\n"
        )
        self.assertTrue(result["ok"], result)
        self.assertIn("value = float(ready);", output.read_text(encoding="utf-8"))
        linked = self._link(output)
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)
        result, output = self._normalize(
            "varying vec2 v_TexCoord;\nbool ready = true;\nvoid main() {\n"
            "    bool first = true, ready = false;\n"
            "    float value = 0.0;\n"
            "    value = ready;\n"
            "    gl_FragColor = vec4(value);\n}\n"
        )
        self.assertTrue(result["ok"], result)
        self.assertIn("value = ready;", output.read_text(encoding="utf-8"))
        linked = self._link(output)
        self.assertNotEqual(linked.returncode, 0, result)

    def test_scalar_builtin_mix_weight_and_return_share_bounded_and_generic_types(self) -> None:
        for loop in ("for (int pass = 0; pass < 2; ++pass)",
                     "for (float pass = 0.0; pass < 2.0; ++pass)"):
            for wide_name in ("accumulated", "renamedValue"):
                with self.subTest(loop=loop, name=wide_name):
                    result, output = self._normalize(
                        "varying vec2 v_TexCoord;\n"
                        "vec3 computeColor(vec2 coord) {\n"
                        f"    vec4 {wide_name} = vec4(0.2, 0.4, 0.6, 0.8);\n"
                        "    vec3 replacement = vec3(0.9, 0.7, 0.5);\n"
                        "    float distanceValue = coord.x - 0.5;\n"
                        f"    {loop} {{\n"
                        f"        {wide_name} = vec4(mix(replacement, {wide_name}, "
                        "step(0.0, distanceValue)), 1.0);\n    }\n"
                        f"    return {wide_name};\n}}\n"
                        "void main() { gl_FragColor = vec4(computeColor(v_TexCoord), 1.0); }\n"
                    )
                    self.assertTrue(result["ok"], result)
                    source = output.read_text(encoding="utf-8")
                    self.assertIn(f"mix(replacement, {wide_name}.xyz, step(", source)
                    self.assertIn(f"return ({wide_name}).xyz;", source)
                    linked = self._link(output)
                    self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)
                    if "int pass" in loop:
                        self.assertTrue(result["boundedHasProgram"], result)
                        metal = self.root / "typed-conversion.metal"
                        metal.write_text(result["boundedMetal"], encoding="utf-8")
                        compiled = subprocess.run(
                            ["xcrun", "--sdk", "macosx", "metal", "-c", str(metal),
                             "-o", str(self.root / "typed-conversion.air")],
                            cwd=self.root, capture_output=True, text=True,
                        )
                        self.assertEqual(compiled.returncode, 0, compiled.stderr)
                    else:
                        self.assertFalse(result["boundedHasProgram"], result)
                        self.assertIn("dynamicLoop", result["boundedDiagnostics"])

    def test_vec3_return_narrows_one_known_vector_constructor_or_authored_call(self) -> None:
        for expression in ("vec4(coord, 0.5, 0.75)", "makeWide(coord)"):
            with self.subTest(expression=expression):
                result, output = self._normalize(
                    "varying vec2 v_TexCoord;\n"
                    "vec4 makeWide(vec2 inputCoord) { return vec4(inputCoord, 0.5, 0.75); }\n"
                    f"vec3 takeRGB(vec2 coord) {{ return {expression}; }}\n"
                    "void main() { gl_FragColor = vec4(takeRGB(v_TexCoord), 1.0); }\n"
                )
                self.assertTrue(result["ok"], result)
                self.assertTrue(result["boundedHasProgram"], result)
                self.assertIn(f"return ({expression}).xyz;", output.read_text(encoding="utf-8"))
                linked = self._link(output)
                self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)
                metal = self.root / "typed-call-return.metal"
                metal.write_text(result["boundedMetal"], encoding="utf-8")
                compiled = subprocess.run(
                    ["xcrun", "--sdk", "macosx", "metal", "-c", str(metal),
                     "-o", str(self.root / "typed-call-return.air")],
                    cwd=self.root, capture_output=True, text=True,
                )
                self.assertEqual(compiled.returncode, 0, compiled.stderr)

    def test_mix_unknown_vector_or_source_overload_weight_stays_rejected(self) -> None:
        for declarations, weight in (
            ("", "unknownWeight"),
            ("vec2 weightPair = vec2(0.5);", "step(vec2(0.0), weightPair)"),
            ("float weightFunction(float x) { return x; }", "weightFunction(0.5)"),
            ("float step(float x, float y) { return x + y; }", "step(0.0, 0.5)"),
        ):
            with self.subTest(weight=weight):
                result, output = self._normalize(
                    "varying vec2 v_TexCoord;\n" + declarations + "\n"
                    "void main() { vec4 wideColor = vec4(0.25); vec3 smallColor = vec3(0.5);\n"
                    f"gl_FragColor = vec4(mix(smallColor, wideColor, {weight}), 1.0); }}\n"
                )
                self.assertTrue(result["ok"], result)
                self.assertIn(f"mix(smallColor, wideColor, {weight})", output.read_text(encoding="utf-8"))
                linked = self._link(output)
                self.assertNotEqual(linked.returncode, 0, weight)

    def test_return_unknown_array_overload_and_shadow_facts_are_not_narrowed(self) -> None:
        cases = (
            ("", "", "missingValue", False),
            ("", "vec4 values[2];", "values", False),
            ("vec4 makeValue(float x) { return vec4(x); }\n"
             "vec3 makeValue(vec2 x) { return vec3(x, 1.0); }", "", "makeValue(0.5)", False),
            ("vec4 makeValue(float sourceValue) { return vec4(sourceValue); }",
             "vec3 makeValue = vec3(0.5);", "makeValue(0.5)", False),
            ("vec4 outputValue = vec4(0.25);", "vec3 outputValue = vec3(0.5);", "outputValue", True),
            ("vec4 outputValue = vec4(0.25);", "vec3 firstValue = vec3(0.5), outputValue = firstValue;", "outputValue", True),
            ("struct Holder { vec3 xyz; };\nvec4 outputValue = vec4(0.25);", "Holder outputValue;", "outputValue", False),
        )
        for declarations, body, expression, links in cases:
            with self.subTest(expression=expression, body=body):
                result, output = self._normalize(
                    "varying vec2 v_TexCoord;\n" + declarations + "\n"
                    f"vec3 returnedRGB() {{ {body} return {expression}; }}\n"
                    "void main() { gl_FragColor = vec4(returnedRGB(), 1.0); }\n"
                )
                self.assertTrue(result["ok"], result)
                self.assertIn(f"return {expression};", output.read_text(encoding="utf-8"))
                linked = self._link(output)
                self.assertEqual(linked.returncode == 0, links, linked.stdout + linked.stderr)

    def test_source_scalar_fract_keeps_body_and_only_return_const_is_removed(self) -> None:
        result, output = self._normalize(
            "varying vec2 v_TexCoord;\nconst float retainedGlobal = 0.25;\n"
            "const float fract(const float inputValue) {\n"
            "    const float retainedLocal = 0.75;\n"
            "    return inputValue * retainedLocal - floor(inputValue) * 0.25;\n}\n"
            "const vec3 returnedColor(const vec3 inputColor) { return inputColor; }\n"
            "void main() {\n"
            "    float selectedValue = 0.0;\n"
            "    for (float repetition = 0.0; repetition < 2.0; repetition++) {\n"
            "        selectedValue = fract(v_TexCoord.x * v_TexCoord.y * (1.0 + v_TexCoord.x));\n"
            "    }\n"
            "    gl_FragColor = vec4(returnedColor(vec3(selectedValue + retainedGlobal)), 1.0);\n"
            "    // const float fract(const float inputValue) is author commentary.\n}\n"
        )
        self.assertTrue(result["ok"], result)
        source = output.read_text(encoding="utf-8")
        self.assertIn("float mwxAuthored_fract(const float inputValue)", source)
        self.assertIn("vec3 returnedColor(const vec3 inputColor)", source)
        self.assertIn("const float retainedGlobal = 0.25;", source)
        self.assertIn("const float retainedLocal = 0.75;", source)
        self.assertIn("return inputValue * retainedLocal - floor(inputValue) * 0.25;", source)
        self.assertIn("mwxAuthored_fract(v_TexCoord.x * v_TexCoord.y * (1.0 + v_TexCoord.x))", source)
        self.assertIn("// const float fract(const float inputValue) is author commentary.", source)
        self.assertFalse(result["boundedHasProgram"], result)
        self.assertIn("dynamicLoop", result["boundedDiagnostics"])
        linked = self._link(output)
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_source_fract_unknown_signature_overload_shadow_or_alias_stays_closed(self) -> None:
        for declarations, argument, local in (
            ("float fract(float scalarValue) { return scalarValue; }", "missingArgument", ""),
            ("float fract(float scalarValue) { return scalarValue; }\n"
             "vec2 fract(vec2 vectorValue) { return vectorValue; }", "v_TexCoord.x", ""),
            ("float fract(vec2 vectorValue) { return vectorValue.x; }", "v_TexCoord", ""),
            ("float fract(float scalarValue) { return scalarValue; }", "v_TexCoord.x", "float fract = 0.5;"),
            ("float fract(float scalarValue) { return scalarValue; }\nfloat mwxAuthored_fract = 0.5;", "v_TexCoord.x", ""),
            ("float fract(float scalarValue) { return scalarValue; }", "v_TexCoord", ""),
        ):
            with self.subTest(declarations=declarations, argument=argument, local=local):
                result, output = self._normalize(
                    "varying vec2 v_TexCoord;\n" + declarations + "\n"
                    f"void main() {{ {local} gl_FragColor = vec4(fract({argument})); }}\n"
                )
                self.assertTrue(result["ok"], result)
                self.assertIn(f"fract({argument})", output.read_text(encoding="utf-8"))
                self.assertNotIn("mwxAuthored_fract(", output.read_text(encoding="utf-8"))
                linked = self._link(output)
                self.assertNotEqual(linked.returncode, 0, linked.stdout + linked.stderr)


if __name__ == "__main__":
    unittest.main()

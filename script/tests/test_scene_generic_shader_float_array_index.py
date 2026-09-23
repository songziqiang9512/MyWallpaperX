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
        switch SceneGenericShaderSourceNormalizer.normalize(
            vertexSource: vertex,
            fragmentSource: fragment,
            maximumStageSourceBytes: 100_000
        ) {
        case let .success(pair):
            try pair.vertex.write(toFile: arguments[3], atomically: true, encoding: .utf8)
            try pair.fragment.write(toFile: arguments[4], atomically: true, encoding: .utf8)
            print(json: ["ok": true, "vertex": pair.vertex, "fragment": pair.fragment])
        case let .failure(failure):
            print(json: ["ok": false, "failure": String(describing: failure)])
        }
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

    def _normalize(self, fragment: str) -> tuple[dict, Path]:
        vertex = """attribute vec3 a_Position;
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


if __name__ == "__main__":
    unittest.main()

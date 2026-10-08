#!/usr/bin/env python3
"""Dead resource projection through the production bounded and generic compilers."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
from scene_swift_source_sets import scene_swift_sources
from script.tests.test_scene_generic_shader_texture_transform_compiler import compiler_bundle

SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SOURCES = list(dict.fromkeys([
    *scene_swift_sources("authored_shader_frontend_core"),
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    SCENE_ROOT / "Compilation/Material/SceneResolvedMaterialGenericShaderRequest.swift",
]))
HARNESS = Path(__file__).with_name("fixtures") / "SceneShaderDeadBindingProjectionHarness.swift"
FRAGMENT = """uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
varying vec4 v_Coordinates;
void main() { gl_FragColor = texSample2D(g_Texture0, v_Coordinates.xy); }
"""
DEAD_CHAIN = """v_Coordinates.xy = a_TexCoord;
float padding = 1.0;
vec2 res0 = g_Texture1Resolution.xy - padding;
float ratio0 = res0.x / res0.y;
float ratio1 = g_Texture1Resolution.x / g_Texture1Resolution.y;
float horizontal = step(ratio0, ratio1);
vec2 ratio = mix(vec2(1., ratio1 / ratio0), vec2(ratio0 / ratio1, 1.),
                 1 == int(1) ? 1. - horizontal : horizontal);
v_Coordinates.zw = v_Coordinates.xy / res0 * ratio + .5;
float S = min(res0.x / g_Texture1Resolution.x, res0.y / g_Texture1Resolution.y);
vec2 excessSize = (res0 - g_Texture1Resolution.xy * S) / res0;
v_Coordinates.zw += excessSize * ratio * .5;
gl_Position = vec4(a_Position, 1.0);"""


def vertex(body: str, helpers: str = "") -> str:
    return """uniform vec4 g_Texture1Resolution;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_Coordinates;
""" + helpers + "\nvoid main() {\n" + body + "\n}\n"


class SceneShaderDeadBindingProjectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-dead-binding-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.bundle = compiler_bundle(cls.root)
        cls.binary = cls.root / "probe"
        cls.evidence = Path(os.environ["MWX_DEAD_BINDING_EVIDENCE"]) if os.environ.get(
            "MWX_DEAD_BINDING_EVIDENCE") else None
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(cls.root / "clang-cache")
        command = ["xcrun", "swiftc", *(str(p) for p in SOURCES), str(HARNESS),
                   "-module-cache-path", str(cls.root / "swift-cache"), "-o", str(cls.binary)]
        completed = subprocess.run(command, cwd=REPOSITORY_ROOT, env=environment,
                                   capture_output=True, text=True, timeout=180)
        if cls.evidence:
            cls.evidence.mkdir(parents=True, exist_ok=True)
            (cls.evidence / "build.json").write_text(json.dumps({
                "command": command, "returncode": completed.returncode,
                "stderr": completed.stderr,
                "sources": {str(p.relative_to(REPOSITORY_ROOT)): hashlib.sha256(
                    p.read_bytes()).hexdigest() for p in [*SOURCES, HARNESS]},
            }, indent=2) + "\n")
        if completed.returncode:
            raise RuntimeError(completed.stderr)

    def compile(self, source: str, fragment: str = FRAGMENT,
                *, metadata: dict | None = None) -> dict:
        request = {"stages": [{"stage": "vertex", "source": source},
                              {"stage": "fragment", "source": fragment}], **(metadata or {})}
        key = hashlib.sha256(json.dumps(request, sort_keys=True).encode()).hexdigest()
        path = self.root / f"{key}.json"
        path.write_text(json.dumps(request))
        completed = subprocess.run([str(self.binary), str(path), str(self.bundle),
                                    str(self.root / "artifacts")], cwd=REPOSITORY_ROOT,
                                   capture_output=True, text=True, timeout=90)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        output = json.loads(completed.stdout)
        if self.evidence:
            (self.evidence / f"{key}.input.json").write_text(json.dumps(request, indent=2))
            (self.evidence / f"{key}.result.json").write_text(json.dumps(output, indent=2))
        return output

    def test_direct_increment_and_decrement_remain_observable(self) -> None:
        for mutation in ("counter++", "++counter", "counter--", "--counter"):
            with self.subTest(mutation=mutation):
                result = self.compile(vertex(f"""float counter = 0.0;
v_Coordinates.xy = a_TexCoord;
v_Coordinates.zw = vec2(g_Texture1Resolution.x * {mutation}, 0.0);
gl_Position = vec4(a_Position + vec3(counter), 1.0);"""))
                self.assertEqual(result.get("boundedSlots"), [0, 1], result)
                self.assertIn("g_Texture1Resolution", result["boundedUniforms"])
                self.assertEqual(result["boundedMetalError"], "")
                self.assertEqual(result.get("genericSlots"), [0, 1], result)
                self.assertEqual(result["genericMetalError"], "")

    def assert_compiled_slots(self, result: dict, slots: list[int]) -> None:
        self.assertEqual(result.get("boundedSlots"), slots, result)
        self.assertEqual(result.get("genericSlots"), slots, result)
        self.assertEqual(result["boundedMetalError"], "")
        self.assertEqual(result["genericMetalError"], "")
        self.assertTrue(result.get("genericPublicationAccepted"), result)

    def test_single_definition_chain_and_compound_dead_writes(self) -> None:
        helpers = "float unrelated() { float S = 3.0; return S; }"
        source = vertex(DEAD_CHAIN, helpers)
        result = self.compile(source)
        self.assert_compiled_slots(result, [0])
        self.assertNotIn("g_Texture1Resolution", result["genericUniforms"])
        self.assertNotIn("g_Texture1Resolution", result["boundedUniforms"])
        self.assertIn(helpers, result["vertex"])
        self.assertIn("gl_Position = vec4(a_Position, 1.0);", result["vertex"])
        self.assertEqual(result["fragment"], FRAGMENT)
        # Reapplying the same canonical owner is stable, with no stale demand.
        repeated = self.compile(result["vertex"], result["fragment"])
        self.assertEqual(repeated["vertex"], result["vertex"])
        self.assertEqual(repeated["genericSlots"], [0])

    def test_pure_direct_builtin_is_projected(self) -> None:
        result = self.compile(vertex("""v_Coordinates.xy = a_TexCoord;
v_Coordinates.zw = normalize(g_Texture1Resolution.xy);
gl_Position = vec4(a_Position, 1.0);"""))
        self.assert_compiled_slots(result, [0])

    def test_numeric_macro_named_as_builtin_is_not_erased(self) -> None:
        source = vertex("""v_Coordinates.xy = a_TexCoord;
v_Coordinates.zw = vec2(min(g_Texture1Resolution.x, 0.0), 0.0);
gl_Position = vec4(a_Position, 1.0);""", "#define min 4")
        result = self.compile(source)
        self.assertEqual(result["vertex"], source)
        self.assertIn("stage-link:rejected", result.get("genericFailure", ""), result)
        projection = self.compile(source, metadata={"projectionOnly": True})
        self.assertEqual(projection["samplerNames"], ["g_Texture0", "g_Texture1"])

    def test_opaque_block_preserves_top_level_projection_and_live_reads(self) -> None:
        for active_read in (False, True):
            with self.subTest(active_read=active_read):
                position = "a_Position + vec3(v_Coordinates.z)" if active_read else "a_Position"
                source = vertex(f"""v_Coordinates.xy = a_TexCoord;
v_Coordinates.zw = normalize(g_Texture1Resolution.xy);
if (a_TexCoord.x > 0.5) {{ gl_Position = vec4({position}, 1.0); }}
else {{ gl_Position = vec4(a_Position, 1.0); }}""")
                result = self.compile(source)
                self.assert_compiled_slots(result, [0, 1] if active_read else [0])

    def test_live_components_position_and_alias_retain_resource(self) -> None:
        fixtures = [
            ("""v_Coordinates.xy = a_TexCoord;
v_Coordinates.zw = g_Texture1Resolution.xy;
gl_Position = vec4(a_Position + vec3(v_Coordinates.z), 1.0);""", FRAGMENT),
            (DEAD_CHAIN, FRAGMENT.replace("v_Coordinates.xy);", "v_Coordinates.zw);")),
            (DEAD_CHAIN.replace("vec4(a_Position, 1.0)",
                                "vec4(a_Position + vec3(ratio0), 1.0)"), FRAGMENT),
            (DEAD_CHAIN.replace("gl_Position =", "vec4 alias = v_Coordinates;\ngl_Position =")
             .replace("vec4(a_Position, 1.0)", "vec4(a_Position + vec3(alias.z), 1.0)"),
             FRAGMENT),
            (DEAD_CHAIN.replace("v_Coordinates.zw +=", "v_Coordinates.xy +="), FRAGMENT),
        ]
        for body, fragment in fixtures:
            with self.subTest(body=body[-100:]):
                self.assert_compiled_slots(self.compile(vertex(body), fragment), [0, 1])

    def test_mutations_and_authored_calls_are_not_discardable(self) -> None:
        for expression in ("(counter = 1)", "(counter += 1)", "(counter &= 1)",
                           "(counter |= 1)", "(counter ^= 1)", "(counter <<= 1)",
                           "(counter >>= 1)"):
            with self.subTest(expression=expression):
                source = vertex(f"""int counter = 2;
v_Coordinates.xy = a_TexCoord;
v_Coordinates.zw = vec2(g_Texture1Resolution.x * float({expression}), 0.);
gl_Position = vec4(a_Position + vec3(float(counter)), 1.0);""")
                result = self.compile(source)
                self.assertEqual(result["vertex"], source)
                self.assertEqual(result.get("genericSlots"), [0, 1], result)
                self.assertEqual(result["genericMetalError"], "")
        for name in ("helper", "min", "mix", "ApplyBlending"):
            with self.subTest(name=name):
                # A distinct signature tests shadowing without invalidating the
                # source through the backend's built-in precision overload rule.
                helper = f"float {name}(float x, int y) {{ return x + float(y); }}"
                source = vertex(f"""v_Coordinates.xy = a_TexCoord;
v_Coordinates.zw = vec2({name}(g_Texture1Resolution.x, 0), 0.);
gl_Position = vec4(a_Position, 1.0);""", helper)
                result = self.compile(source)
                self.assertEqual(result["vertex"], source)
                self.assertEqual(result.get("genericSlots"), [0, 1], result)
                self.assertEqual(result["genericMetalError"], "")

    def test_authored_helper_with_nested_shadow_and_global_mutation_is_retained(self) -> None:
        source = vertex("""v_Coordinates.xy = a_TexCoord;
v_Coordinates.zw = vec2(helper(g_Texture1Resolution.x), 0.);
gl_Position = vec4(a_Position + vec3(v_Coordinates.z), 1.0);""", """
float helper(float x) {
    { float v_Coordinates = 0.; }
    v_Coordinates.z++;
    return x;
}""")
        result = self.compile(source)
        self.assertEqual(result["vertex"], source)
        self.assertEqual(result.get("genericSlots"), [0, 1], result)
        self.assertEqual(result["genericMetalError"], "")

    def test_duplicate_local_and_nested_shadow_retain_resource(self) -> None:
        source = vertex("""v_Coordinates.xy = a_TexCoord;
float factor = g_Texture1Resolution.x;
{ float factor = 1.; v_Coordinates.zw = vec2(factor); }
v_Coordinates.zw = vec2(factor);
gl_Position = vec4(a_Position, 1.0);""")
        result = self.compile(source)
        self.assertEqual(result["vertex"], source)
        self.assertEqual(result.get("genericSlots"), [0, 1], result)
        self.assertEqual(result["genericMetalError"], "")

    def test_illegal_write_swizzles_are_not_erased_before_typechecking(self) -> None:
        for swizzle in ("zz", "zq"):
            with self.subTest(swizzle=swizzle):
                source = vertex(f"""v_Coordinates.xy = a_TexCoord;
v_Coordinates.{swizzle} = g_Texture1Resolution.xy;
gl_Position = vec4(a_Position, 1.0);""")
                result = self.compile(source)
                self.assertEqual(result["vertex"], source)
                self.assertIn("stage-link:rejected", result.get("genericFailure", ""), result)
                self.assertEqual(result.get("boundedSlots"), [0, 1])

    def test_projection_budget_keeps_dependencies_and_no_resolution_skips_work(self) -> None:
        for expression, names in (("g_Texture1Resolution.xy", ["g_Texture0", "g_Texture1"]),
                                  ("vec2(.25)", ["g_Texture0"])):
            with self.subTest(expression=expression):
                body = "v_Coordinates.xy = a_TexCoord;\n" + (
                    f"v_Coordinates.zw = {expression};\n" * 1024
                ) + "gl_Position = vec4(a_Position, 1.0);"
                source = vertex(body)
                result = self.compile(source, metadata={"projectionOnly": True})
                self.assertEqual(result["vertex"], source)
                self.assertEqual(result["samplerNames"], names)

    def test_authored_requests_have_no_dead_resolution_binding(self) -> None:
        directory = os.environ.get("MWX_DEAD_BINDING_AUTHORED_REQUESTS")
        if not directory:
            self.skipTest("Set MWX_DEAD_BINDING_AUTHORED_REQUESTS for retained real requests")
        for key in ("3fb6d6388ed4b45d76e66fc86b2c660255ee96373ade800393adda11eb299b87",
                    "4c1f3ccfe0b54153749cbf1cd24a99293e4b42d8447c98751c2262faec5c5e23"):
            with self.subTest(request=key):
                request = json.loads((Path(directory) / f"{key}.json").read_text())
                stages = {stage["stage"]: stage["source"] for stage in request["stages"]}
                result = self.compile(stages["vertex"], stages["fragment"], metadata={
                    field: request[field] for field in (
                        "outputSemantics", "premultipliedColorInputSlots")})
                self.assertEqual(result.get("genericSlots"), [0, 3], result)
                self.assertNotIn("g_Texture2Resolution", result["genericUniforms"])
                self.assertEqual(result["genericMetalError"], "")
                self.assertEqual(result["fragment"], stages["fragment"])



if __name__ == "__main__":
    unittest.main()

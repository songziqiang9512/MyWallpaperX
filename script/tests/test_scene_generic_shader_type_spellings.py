#!/usr/bin/env python3
"""Typed HLSL vector spellings through the production generic compiler input."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_shader_scalar_vector_builtin_canonicalization import (
    GLSLANG, HARNESS, REPOSITORY_ROOT, SWIFT_SOURCES,
)


class SceneGenericShaderTypeSpellingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not shutil.which("swiftc") or not GLSLANG.is_file():
            raise unittest.SkipTest("Swift and the bundled GLSL compiler are required")
        cls.directory = tempfile.TemporaryDirectory(prefix="mwx-type-spellings-")
        root = Path(cls.directory.name)
        harness = root / "TypeSpellingHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "type-spellings"
        cls.environment = os.environ.copy()
        cls.environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        cls.environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc", "-parse-as-library",
                "-whole-module-optimization", "-Onone",
                *map(str, dict.fromkeys(SWIFT_SOURCES)), str(harness),
                "-module-cache-path", str(root / "module-cache"),
                "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT, env=cls.environment,
            capture_output=True, text=True, timeout=180,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stdout + completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.directory.cleanup()

    def normalize(self, source: str, root: Path) -> dict:
        authored = root / "authored.glsl"
        authored.write_text(source, encoding="utf-8")
        completed = subprocess.run(
            [str(self.binary), "--analyze", str(authored)],
            cwd=root, env=self.environment, capture_output=True,
            text=True, timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertIn("normalizedVertex", payload, payload)
        self.assertIn("normalizedFragment", payload, payload)
        return payload

    def link(self, payload: dict, root: Path) -> subprocess.CompletedProcess:
        vertex, fragment = root / "linked.vert", root / "linked.frag"
        vertex.write_text(payload["normalizedVertex"], encoding="utf-8")
        fragment.write_text(payload["normalizedFragment"], encoding="utf-8")
        return subprocess.run(
            [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
             "-l", str(vertex), str(fragment), "-o", str(root / "linked.spv")],
            cwd=root, capture_output=True, text=True, timeout=30,
        )

    def render(self, payload: dict, root: Path) -> list[float]:
        linked = self.link(payload, root)
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)
        fragment = root / "linked.frag"
        spirv, metal = root / "fragment.spv", root / "fragment.metal"
        for command in (
            [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
             str(fragment), "-o", str(spirv)],
            [str(GLSLANG.with_name("spirv-cross")), str(spirv), "--msl",
             "--rename-entry-point", "main", "comparisonFragment", "frag",
             "--output", str(metal)],
        ):
            completed = subprocess.run(
                command, cwd=root, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        completed = subprocess.run(
            [str(self.binary), "--render", str(metal)],
            cwd=root, env=self.environment, capture_output=True,
            text=True, timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        return json.loads(completed.stdout)

    def assert_pixels(self, pixels: list[float], expected: list[float]) -> None:
        self.assertEqual(len(pixels), 8, pixels)  # Existing harness draws twice.
        for actual, wanted in zip(pixels, expected * 2):
            self.assertAlmostEqual(actual, wanted, delta=1e-6)

    def test_helper_local_alias_and_integer_mod_compile_and_render(self) -> None:
        source = """
float readLane(int bin) {
    float4 packed = vec4(0.125, 0.25, 0.5, 0.75);
    return mod(bin, 4) == 0 ? packed.x :
        (mod(bin, 4) == 1 ? packed.y : (mod(bin, 4) == 2 ? packed.z : packed.w));
}
void main() {
    gl_FragColor = vec4(readLane(0), readLane(5), readLane(6), readLane(7));
}
"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = self.normalize(source, root)
            self.assertIn("vec4 packed", payload["normalizedFragment"])
            self.assertNotIn("float4 packed", payload["normalizedFragment"])
            self.assertIn("mod(bin, 4)", payload["normalizedFragment"])
            self.assert_pixels(self.render(payload, root), [0.125, 0.25, 0.5, 0.75])

    def test_return_parameter_constructor_and_renamed_glsl_equivalent(self) -> None:
        source = """
float3 extend(in float2 coordinates) {
    const float3 expanded = float3((coordinates), 0.75);
    return expanded;
}
float4 paint(float2 coordinates) {
    float3 rgb = extend(coordinates);
    return float4(rgb, 1.0);
}
void main() { gl_FragColor = paint(float2(0.25, 0.5)); }
"""
        variants = (
            source,
            source.replace("extend", "lift").replace("coordinates", "uvPair")
                .replace("expanded", "triplet").replace("paint", "emitColor"),
            source.replace("float2", "vec2").replace("float3", "vec3")
                .replace("float4", "vec4"),
        )
        for source_variant in variants:
            with self.subTest(source=source_variant), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                payload = self.normalize(source_variant, root)
                self.assertNotRegex(payload["normalizedFragment"], r"\bfloat[234]\b")
                self.assert_pixels(self.render(payload, root), [0.25, 0.5, 0.75, 1.0])

    def test_value_member_and_authored_function_names_are_preserved(self) -> None:
        cases = (
            (
                "void main() { float float4 = 0.25; gl_FragColor = vec4(float4); }",
                ("float float4", "vec4(float4)"),
            ),
            (
                "struct Carrier { float float4; };\n"
                "void main() { Carrier item; item.float4 = 0.25; "
                "gl_FragColor = vec4(item.float4); }",
                ("float float4", "item.float4"),
            ),
            (
                "float float4(float value) { return value * 2.0; }\n"
                "void main() { gl_FragColor = vec4(float4(0.25)); }",
                ("float float4(float value)", "float4(0.25)"),
            ),
        )
        for source, preserved in cases:
            with self.subTest(source=source), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                payload = self.normalize(source, root)
                for text in preserved:
                    self.assertIn(text, payload["normalizedFragment"])
                linked = self.link(payload, root)
                self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_macro_origin_comments_and_unknown_alias_do_not_guess_types(self) -> None:
        comment = "/* float4 alias(float2 value); float3(0.0) */"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = self.normalize(
                comment + "\nvoid main() { float4 color = float4(0.5); gl_FragColor = color; }",
                root,
            )
            self.assertIn(comment, payload["normalizedFragment"])
            self.assertIn("vec4 color", payload["normalizedFragment"])
            linked = self.link(payload, root)
            self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

        cases = (
            ("#define CELL float4\nvoid main() { CELL color = vec4(0.5); "
             "gl_FragColor = color; }", "CELL color", False),
            ("#define float4 vec4\nvoid main() { gl_FragColor = float4(0.5); }",
             "float4(0.5)", True),
            ("#define float4 1\nvoid main() { float4 item = vec4(0.5); "
             "gl_FragColor = item; }", "float4 item", False),
            ("void main() { float5 color; gl_FragColor = vec4(0.5); }",
             "float5 color", False),
        )
        for source, preserved, should_link in cases:
            with self.subTest(source=source), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                payload = self.normalize(source, root)
                self.assertIn(preserved, payload["normalizedFragment"])
                linked = self.link(payload, root)
                self.assertEqual(linked.returncode == 0, should_link,
                                 linked.stdout + linked.stderr)

    def test_struct_type_shadow_and_scalar_clamp_keep_authored_values(self) -> None:
        cases = (
            (
                "struct-type-shadow",
                "struct float4 { float z; float w; float x; float y; };\n"
                "void main() { float4 item = float4(0.125, 0.25, 0.5, 0.75); "
                "gl_FragColor = vec4(item.x, item.y, item.z, item.w); }",
                [0.5, 0.75, 0.125, 0.25],
            ),
            (
                "scalar-clamp-is-not-vector-broadcast",
                "void main() { int count = 1; "
                "gl_FragColor = vec4(min(0.75, count)); }",
                [0.75, 0.75, 0.75, 0.75],
            ),
        )
        for name, source, expected in cases:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                payload = self.normalize(source, root)
                if name == "struct-type-shadow":
                    fragment = payload["normalizedFragment"]
                    structure = re.search(r"\bstruct\s+float4\s*\{([^{}]*)\}\s*;",
                                          fragment, re.DOTALL)
                    self.assertIsNotNone(structure, fragment)
                    fields = re.findall(r"\bfloat\s+(\w+)\s*;", structure.group(1))
                    self.assertEqual(fields, ["z", "w", "x", "y"], fragment)
                    constructor = re.search(
                        r"\bfloat4\s+item\s*=\s*float4\s*\(([^()]*)\)\s*;",
                        fragment,
                    )
                    self.assertIsNotNone(constructor, fragment)
                    values = [float(value.strip())
                              for value in constructor.group(1).split(",")]
                    members = dict(zip(fields, values))
                    self.assertEqual([members[field] for field in "xyzw"], expected)
                    linked = self.link(payload, root)
                    self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)
                    # The authored struct still collides with Metal's float4
                    # name. This slice preserves GLSL meaning, not that MSL ABI.
                else:
                    self.assert_pixels(self.render(payload, root), expected)

    def test_explicit_negative_mod_retains_floor_semantics_with_aliases(self) -> None:
        source = """
float4 wrapPair(float2 values) {
    return float4(mod(values.x, 2.0), mod(values.y, -2.0), 0.0, 1.0);
}
void main() { gl_FragColor = wrapPair(float2(-5.75, 5.75)); }
"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = self.normalize(source, root)
            self.assertIn("mod(values.x, 2.0)", payload["normalizedFragment"])
            self.assertIn("mod(values.y, -2.0)", payload["normalizedFragment"])
            self.assert_pixels(self.render(payload, root), [0.25, -0.25, 0.0, 1.0])



if __name__ == "__main__":
    unittest.main()

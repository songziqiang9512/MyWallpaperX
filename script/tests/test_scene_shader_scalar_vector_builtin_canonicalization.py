#!/usr/bin/env python3
"""Shared authored scalar/vector built-in compiler canonicalization gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneAuthoredShaderBackendCanonicalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneAuthoredShaderConstantNumericExpression.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneAuthoredShaderVaryingArrayLivePrefixCanonicalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderBooleanScalarArithmeticNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderTernaryScalarConditionNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderFloatingModuloNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderScalarArithmeticNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderScalarBuiltInLiteralNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderScalarVectorBroadcastNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderInactiveBuiltinOverloadCanonicalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderMutableFragmentVaryingNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderTextureSamplingNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderDirectFunctionVectorArgumentNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderSourceNormalizer.swift",
    REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene/Compilation/ShaderPreparation/SceneGenericShaderSourceNormalizer+Rewrites.swift",
]
GLSLANG = (
    REPOSITORY_ROOT
    / "MyWallpaperX/Resources/SceneShaderCompilerTools/glslang"
)


HARNESS = (REPOSITORY_ROOT / "script/tests/fixtures/SceneScalarVectorBuiltInHarness.swift").read_text(encoding="utf-8")

LOOP_HELPER = """
float sampleCount(float first, float stop) {
    float count = 0.0;
    for (int i = first; i < stop; ++i) { count += 1.0; }
    return count;
}
"""


class SceneShaderScalarVectorBuiltInCanonicalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory()
        build_root = Path(cls.build_directory.name)
        harness = build_root / "ScalarVectorBuiltInHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = build_root / "scalar-vector-built-in-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(
            build_root / "clang-module-cache"
        )
        environment["SWIFT_MODULECACHE_PATH"] = str(
            build_root / "swift-module-cache"
        )
        subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            check=True,
            capture_output=True,
            text=True,
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.build_directory.cleanup()

    def test_canonicalizes_only_source_proven_max_zero_vector_form(self) -> None:
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertEqual(
            {name for name, passed in output["checks"].items() if not passed},
            set(),
        )

    def test_dynamic_loop_keeps_built_in_type_conversions_and_renders(self) -> None:
        source = LOOP_HELPER + """
void main() {
    vec3 albedo = vec3(-0.5, 0.5, 1.5);
    vec3 lowered = max(0, albedo);
    vec3 limited = min(1, lowered);
    vec3 mixed = mix(0.25, limited, 0.5);
    vec3 powered = pow(mixed, 2.0);
    float scale = max(1, abs(0.5));
    gl_FragColor = vec4(powered * scale, sampleCount(0.0, 2.8) / 4.0);
}
"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            authored = root / "source.frag"
            authored.write_text(source, encoding="utf-8")
            output = json.loads(subprocess.check_output(
                [str(self.binary), "--analyze", str(authored)], text=True,
            ))
            self.assertEqual(output["strictDiagnosticCodes"], ["dynamicLoop"])
            self.assertEqual(output["typeDiagnosticCodes"], [])
            self.assertTrue(output["idempotent"])
            for expected in ["max(vec3(0.0), albedo)", "min(vec3(1.0), lowered)",
                             "mix(vec3(0.25), limited, 0.5)", "pow(mixed, vec3(2.0))",
                             "max(1.0, abs(0.5))"]:
                self.assertIn(expected, output["canonicalFragment"])
            vertex, fragment = root / "author.vert", root / "author.frag"
            vertex.write_text(output["normalizedVertex"], encoding="utf-8")
            fragment.write_text(output["normalizedFragment"], encoding="utf-8")
            spirv, metal = root / "result.spv", root / "result.metal"
            for command in (
                [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                 "-l", str(vertex), str(fragment)],
                [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                 str(fragment), "-o", str(spirv)],
                [str(GLSLANG.with_name("spirv-cross")), str(spirv), "--msl",
                 "--rename-entry-point", "main", "comparisonFragment", "frag", "--output", str(metal)],
            ):
                compiled = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=30)
                self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            pixels = json.loads(subprocess.check_output(
                [str(self.binary), "--render", str(metal)], text=True, timeout=30,
            ))
            self.assertEqual(pixels, [0.015625, 0.140625, 0.390625, 0.75] * 2)

    def test_dynamic_loop_does_not_bypass_syntax_or_custom_overload_guards(self) -> None:
        cases = [
            ("vec3 max(int bound, vec3 value) { return value; }", "max(0, color)"),
            ("vec3 min(int bound, vec3 value) { return value; }", "min(1, color)"),
            ("vec3 mix(float first, vec3 second, float weight) { return second; }", "mix(0.25, color, 0.5)"),
            ("vec3 pow(vec3 value, float exponent) { return value; }", "pow(color, 2.0)"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            authored = Path(directory) / "source.frag"
            for helper, call in cases:
                with self.subTest(call=call):
                    source = LOOP_HELPER + helper + "\nvoid main() { vec3 color = vec3(0.5);"
                    source += f" gl_FragColor = vec4({call}, 0.75); }}"
                    authored.write_text(source, encoding="utf-8")
                    output = json.loads(subprocess.check_output(
                        [str(self.binary), "--analyze", str(authored)], text=True,
                    ))
                    self.assertEqual(output["strictDiagnosticCodes"], ["dynamicLoop"])
                    self.assertEqual(output["typeDiagnosticCodes"], [])
                    self.assertEqual(output["canonicalFragment"], source)
            for malformed in [
                "void main() { vec3 color = vec3(0.5); gl_FragColor = vec4(max(0, color));",
                "void main() { vec3 color = vec3(0.5); @; gl_FragColor = vec4(max(0, color)); }",
            ]:
                with self.subTest(malformed=malformed):
                    authored.write_text(malformed, encoding="utf-8")
                    output = json.loads(subprocess.check_output(
                        [str(self.binary), "--analyze", str(authored)], text=True,
                    ))
                    self.assertTrue(output["typeDiagnosticCodes"])
                    self.assertEqual(output["canonicalFragment"], malformed)

    def test_literal_zero_request_links_with_bundled_glslang(self) -> None:
        if not GLSLANG.is_file() or not os.access(GLSLANG, os.X_OK):
            self.skipTest("bundled glslang is unavailable")
        completed = subprocess.run(
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        output = json.loads(completed.stdout)
        self.assertIsNotNone(output["normalizedVertex"])
        self.assertIsNotNone(output["normalizedFragment"])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            vertex = root / "author.vert"
            fragment = root / "author.frag"
            vertex.write_text(output["normalizedVertex"], encoding="utf-8")
            fragment.write_text(output["normalizedFragment"], encoding="utf-8")
            linked = subprocess.run(
                [
                    str(GLSLANG),
                    "-V",
                    "--auto-map-bindings",
                    "--auto-map-locations",
                    "-l",
                    str(vertex),
                    str(fragment),
                ],
                cwd=root,
                capture_output=True,
                text=True,
            )
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_literal_bounds_on_abs_results_link(self) -> None:
        if not GLSLANG.is_file() or not os.access(GLSLANG, os.X_OK):
            self.skipTest("bundled glslang is unavailable")
        statements = [
            "gl_FragColor = vec4(max(1, abs(g_Ratio)), 0.0, 1.0);",
            "gl_FragColor = vec4(min(0.5, abs(-g_Ratio)), 0.0, 1.0);",
            "gl_FragColor = vec4(max(1, abs(g_Ratio.x)));",
            "gl_FragColor = vec4(min(abs(g_Ratio.x), 2));",
            "gl_FragColor = vec4(max(2, abs(abs(g_Ratio))), 0.0, 1.0);",
            "int n = max(1, abs(-2)); gl_FragColor = vec4(float(n));",
        ]
        for statement in statements:
            with self.subTest(statement=statement), tempfile.TemporaryDirectory() as directory:
                output = json.loads(subprocess.check_output(
                    [str(self.binary), statement], text=True,
                ))
                root = Path(directory)
                vertex = root / "author.vert"
                fragment = root / "author.frag"
                vertex.write_text(output["normalizedVertex"], encoding="utf-8")
                fragment.write_text(output["normalizedFragment"], encoding="utf-8")
                linked = subprocess.run(
                    [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                     "-l", str(vertex), str(fragment)],
                    cwd=root, capture_output=True, text=True,
                )
                self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_declared_int_first_builtin_operands_link(self) -> None:
        # The archived stage-link class: max/min(int, vecN) has no Vulkan
        # GLSL overload (int does not convert to the vector), while the
        # reverse order converts implicitly. The authored language
        # broadcasts the scalar, so the normalizer promotes it to the
        # sibling's vector type.
        if not GLSLANG.is_file() or not os.access(GLSLANG, os.X_OK):
            self.skipTest("bundled glslang is unavailable")
        cases = [
            ("int k = 2; gl_FragColor = vec4(max(k, g_Ratio), 0.0, 1.0);",
             "max(vec2(k), g_Ratio)"),
            ("int k = 2; gl_FragColor = vec4(min(k, g_Ratio), 0.0, 1.0);",
             "min(vec2(k), g_Ratio)"),
            # A float scalar first operand broadcasts the same way.
            ("float f = 0.5; gl_FragColor = vec4(max(f, g_Ratio), 0.0, 1.0);",
             "max(vec2(f), g_Ratio)"),
            # An integer scalar against an integer vector keeps its element
            # domain: the constructor is the sibling's ivec type.
            ("int k = 2; ivec2 iv = ivec2(2);"
             " gl_FragColor = vec4(float(max(k, iv).x));",
             "max(ivec2(k), iv)"),
            # A locally declared vector sibling takes the same promotion.
            ("int k = 2; vec2 lv = g_Ratio; gl_FragColor = vec4(max(k, lv), 0.0, 1.0);",
             "max(vec2(k), lv)"),
            # The vector-first order already links; it must stay untouched.
            ("int k = 2; gl_FragColor = vec4(max(g_Ratio, k), 0.0, 1.0);",
             "max(g_Ratio, k)"),
            # Integer-integer max keeps its own overload.
            ("int k = 2; int j = 3; gl_FragColor = vec4(float(max(k, j)));",
             "max(k, j)"),
            # A uint scalar broadcasts into the uvec sibling.
            ("uint u = 2u; uvec2 uv = uvec2(2);"
             " gl_FragColor = vec4(float(max(u, uv).x));",
             "max(uvec2(u), uv)"),
            # A float scalar entering an integer vector would narrow; the
            # shape stays fail-closed with no rewrite and no link claim.
            ("float f = 0.5; ivec2 iv = ivec2(2);"
             " gl_FragColor = vec4(float(max(f, iv).x));",
             "max(f, iv)"),
            # An authored overload owning the built-in name keeps its call
            # sites; a different signature is a legal GLSL overload.
            ("vec2 max(int a, vec2 b) { return b; }"
             " int k = 2; gl_FragColor = vec4(max(k, g_Ratio), 0.0, 1.0);",
             "max(k, g_Ratio)"),
        ]
        for statement, expected in cases:
            with self.subTest(statement=statement), tempfile.TemporaryDirectory() as directory:
                output = json.loads(subprocess.check_output(
                    [str(self.binary), statement], text=True,
                ))
                fragment = output["normalizedFragment"]
                self.assertIn(expected, fragment)
                if expected in ("max(g_Ratio, k)", "max(k, j)"):
                    self.assertNotIn("vec2(k)", fragment)
                if expected in ("max(k, g_Ratio)", "max(f, iv)"):
                    # The authored overload sits inside the harness body, and
                    # the narrowing shape has no legal overload at all; both
                    # assert the guard's text behaviour only.
                    self.assertNotIn("vec2(k)", fragment)
                    continue
                root = Path(directory)
                vertex = root / "author.vert"
                fragment_path = root / "author.frag"
                vertex.write_text(output["normalizedVertex"], encoding="utf-8")
                fragment_path.write_text(fragment, encoding="utf-8")
                linked = subprocess.run(
                    [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                     "-l", str(vertex), str(fragment_path)],
                    cwd=root, capture_output=True, text=True,
                )
                self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_integer_literal_clamp_broadcast_follows_sibling_type(self) -> None:
        # The archived stage-link subclass: the literal broadcast used to
        # hardcode vec3, which breaks narrower and integer-vector siblings.
        # The broadcast now follows the sibling's declared type; integer
        # scalar and unknown siblings stay untouched.
        if not GLSLANG.is_file() or not os.access(GLSLANG, os.X_OK):
            self.skipTest("bundled glslang is unavailable")
        cases = [
            ("int k = 2; ivec2 iv = ivec2(2);"
             " gl_FragColor = vec4(float(max(2, iv).x));",
             "max(ivec2(2), iv)"),
            ("gl_FragColor = vec4(max(2, g_Ratio), 0.0, 1.0);",
             "max(vec2(2.0), g_Ratio)"),
            # Integer scalar against integer scalar keeps its own overload.
            ("int k = 2; int n = max(2, k);"
             " gl_FragColor = vec4(float(n));",
             "max(2, k)"),
            # A float scalar sibling needs only the float spelling.
            ("float v = max(2.0, g_Ratio.x);"
             " gl_FragColor = vec4(v, 0.0, 1.0, 1.0);",
             "max(2.0, g_Ratio.x)"),
        ]
        for statement, expected in cases:
            with self.subTest(statement=statement), tempfile.TemporaryDirectory() as directory:
                output = json.loads(subprocess.check_output(
                    [str(self.binary), statement], text=True,
                ))
                fragment = output["normalizedFragment"]
                self.assertIn(expected, fragment)
                if expected == "max(2, k)":
                    # The harness prelude itself defines vec3 macros; the
                    # untouched assertion is line-scoped to the call.
                    line = next(
                        line for line in fragment.splitlines()
                        if "max(2, k)" in line
                    )
                    self.assertNotIn("vec3(", line)
                    self.assertNotIn("ivec2(2)", line)
                root = Path(directory)
                vertex = root / "author.vert"
                fragment_path = root / "author.frag"
                vertex.write_text(output["normalizedVertex"], encoding="utf-8")
                fragment_path.write_text(fragment, encoding="utf-8")
                linked = subprocess.run(
                    [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                     "-l", str(vertex), str(fragment_path)],
                    cwd=root, capture_output=True, text=True,
                )
                self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_float_to_int_assignments_carry_explicit_truncation(self) -> None:
        # The archived stage-link subclass: an integer target assigned a
        # float-bearing expression relied on the lenient compilers' implicit
        # conversion. The normalizer spells the truncation through int(...)
        # for declarations and plain assignments; comparison operands have
        # separate promotion and pixel-result tests.
        # Compound assignments rebuild as `k = int(k op (rhs))` — the same
        # truncation the official D3D pipeline applies implicitly; the
        # sample-real `*=` form, uint targets, pure-integer RHS and explicit
        # conversions each keep their exact contract below. Qualified member
        # LHS and `%=` remain fail-closed residuals.
        if not GLSLANG.is_file() or not os.access(GLSLANG, os.X_OK):
            self.skipTest("bundled glslang is unavailable")
        cases = [
            # A for-update ends at the enclosing ')', never the first body
            # semicolon. Float atoms in the body cannot type the update.
            ("float value = 0.0; for (int k = 0; k < 4; k += 1) { value += 0.25; }"
             " gl_FragColor = vec4(value);", "k += 1) { value += 0.25; }"),
            ("float value = 0.0; for (int k = 0; k < 4; k = k + 1) { value += 0.25; }"
             " gl_FragColor = vec4(value);", "k = k + 1) { value += 0.25; }"),
            ("float value = 0.0; for (int k = 0; k < 4; k += 1.0) { value += 0.25; }"
             " gl_FragColor = vec4(value);", "k = int(k + (1.0))) { value += 0.25; }"),
            ("float value = 0.0; for (int k = 0; k < 4; k = k + (1.0)) value += 0.25;"
             " gl_FragColor = vec4(value);", "k = int(k + (1.0))) value += 0.25;"),
            ("float value = 0.0; for (int k = 0; k < 4; k += int(1.0)) { value += 0.25; }"
             " gl_FragColor = vec4(value);", "k += int(1.0)) { value += 0.25; }"),
            ("int offsets[2]; offsets[0] = 0; float value = 0.0;"
             " for (int k = 0; k < 2.5; k += offsets[0] + 1.0) { value += 0.25; }"
             " gl_FragColor = vec4(value);",
             "k = int(k + (offsets[0] + 1.0))) { value += 0.25; }"),
            ("int k = g_Ratio.y * 2;"
             " gl_FragColor = vec4(float(k), 0.0, 1.0, 1.0);",
             "int k = int(g_Ratio.y * 2);"),
            ("int k = 0; k = g_Ratio.y;"
             " gl_FragColor = vec4(float(k), 0.0, 1.0, 1.0);",
             "k = int(g_Ratio.y)"),
            ("int k = 0; k = g_Ratio.y * 3.0;"
             " gl_FragColor = vec4(float(k), 0.0, 1.0, 1.0);",
             "k = int(g_Ratio.y * 3.0)"),
            ("int k = g_Ratio.y;"
             " gl_FragColor = vec4(float(k), 0.0, 1.0, 1.0);",
             "int k = int(g_Ratio.y)"),
            # The workshop-real compound form (Simple_Audio_Bars) rebuilds
            # with the accumulated LHS and a parenthesized whole RHS.
            ("int bar = 0; bar *= step(1.0 - g_Ratio.x, g_Ratio.y);"
             " gl_FragColor = vec4(float(bar), 0.0, 1.0, 1.0);",
             "bar = int(bar * (step(1.0 - g_Ratio.x, g_Ratio.y)))"),
            ("int k = 0; k += g_Ratio.y;"
             " gl_FragColor = vec4(float(k), 0.0, 1.0, 1.0);",
             "k = int(k + (g_Ratio.y))"),
            # A uint target takes the same explicit truncation.
            ("uint k = 0u; k -= g_Ratio.y;"
             " gl_FragColor = vec4(float(k), 0.0, 1.0, 1.0);",
             "k = int(k - (g_Ratio.y))"),
            # An already-integer pair keeps its own statement untouched.
            ("int k = 2; int n = k;"
             " gl_FragColor = vec4(float(n), 0.0, 1.0, 1.0);",
             "int n = k"),
            # A pure-integer compound statement stays untouched.
            ("int k = 2; int n = 3; k *= n;"
             " gl_FragColor = vec4(float(k), 0.0, 1.0, 1.0);",
             "k *= n"),
            # A float-declared target is not an int truncation site; the
            # statement keeps its authored form.
            ("float k = 1.0; k *= g_Ratio.y;"
             " gl_FragColor = vec4(k, 0.0, 1.0, 1.0);",
             "k *= g_Ratio.y"),
            # An explicit conversion is already the truncation; it must not
            # be wrapped twice (plain and compound forms).
            ("int k = 0; k = int(g_Ratio.y);"
             " gl_FragColor = vec4(float(k), 0.0, 1.0, 1.0);",
             "k = int(g_Ratio.y)"),
            ("int k = 0; k += int(g_Ratio.y);"
             " gl_FragColor = vec4(float(k), 0.0, 1.0, 1.0);",
             "k += int(g_Ratio.y)"),
        ]
        for statement, expected in cases:
            with self.subTest(statement=statement), tempfile.TemporaryDirectory() as directory:
                output = json.loads(subprocess.check_output(
                    [str(self.binary), statement], text=True,
                ))
                fragment = output["normalizedFragment"]
                self.assertIn(expected, fragment)
                if "int(" in expected:
                    self.assertNotIn("int(int(", fragment)
                root = Path(directory)
                vertex = root / "author.vert"
                fragment_path = root / "author.frag"
                vertex.write_text(output["normalizedVertex"], encoding="utf-8")
                fragment_path.write_text(fragment, encoding="utf-8")
                linked = subprocess.run(
                    [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                     "-l", str(vertex), str(fragment_path)],
                    cwd=root, capture_output=True, text=True,
                )
                self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_compound_assignment_does_not_inherit_another_scope_integer_type(self) -> None:
        statement = (
            "float spare = 0.0, k = 1; k *= 0.5;"
            " gl_FragColor = vec4(k, k, k, float(helper()));"
        )
        output = json.loads(subprocess.check_output([
            str(self.binary), statement,
            "int helper() { int k = 1; return k; }",
        ], text=True))
        self.assertIn("k *= 0.5", output["normalizedFragment"])
        self.assertNotIn("k = int(k", output["normalizedFragment"])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "comparison.frag"
            source.write_text(output["normalizedFragment"], encoding="utf-8")
            spirv = root / "comparison.spv"
            metal = root / "comparison.metal"
            for command in (
                [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                 str(source), "-o", str(spirv)],
                [str(GLSLANG.with_name("spirv-cross")), str(spirv), "--msl",
                 "--rename-entry-point", "main", "comparisonFragment", "frag",
                 "--output", str(metal)],
            ):
                compiled = subprocess.run(command, capture_output=True, text=True, timeout=30)
                self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            pixels = json.loads(subprocess.check_output([
                str(self.binary), "--render", str(metal),
            ], text=True, timeout=30))
            self.assertEqual(pixels, [0.5, 0.5, 0.5, 1.0] * 2)

    def test_comparisons_do_not_narrow_fractional_operands(self) -> None:
        # Comparisons promote unlike assignment conversion: a fractional
        # right operand must not acquire a float-to-int instruction.
        if not GLSLANG.is_file() or not os.access(GLSLANG, os.X_OK):
            self.skipTest("bundled glslang is unavailable")
        cases = [
            # float/float local comparison keeps its authored operands.
            ("float coverage = 0.4; float cutoff = 0.8; int scratch = 0;"
             " if (coverage < cutoff) { scratch = 1; }"
             " gl_FragColor = vec4(float(scratch));",
             None),
            # The reversed operator direction is the same defect class.
            ("float coverage = 0.4; float cutoff = 0.8; int scratch = 0;"
             " if (cutoff > coverage) { scratch = 1; }"
             " gl_FragColor = vec4(float(scratch));",
             None),
            # A swizzle member on the left is not a declared int scalar.
            ("float cutoff = 0.8; int scratch = 0;"
             " if (g_Ratio.x < cutoff) { scratch = 1; }"
             " gl_FragColor = vec4(float(scratch));",
             None),
            # A left identifier containing the right name must not corrupt
            # the left operand (the old whole-expression replace produced
            # the undeclared identifier xint).
            ("float coverage = 0.8; float xcoverage = 0.1; int scratch = 0;"
             " if (xcoverage < coverage) { scratch = 1; }"
             " gl_FragColor = vec4(float(scratch));",
             None),
            # The same name on both sides keeps the authored comparison.
            ("float cutoff = 0.8; int scratch = 0;"
             " if (cutoff < cutoff) { scratch = 1; }"
             " gl_FragColor = vec4(float(scratch));",
             None),
            # A declared float uniform also keeps its fractional value.
            ("float coverage = 0.4; int scratch = 0;"
             " if (coverage < g_Threshold) { scratch = 1; }"
             " gl_FragColor = vec4(float(scratch));",
             "uniform float g_Threshold;"),
            # Integer/float comparisons promote, including uniform bounds.
            ("float cutoff = 0.8; int k = 0; if (k < cutoff) { k = 1; }"
             " gl_FragColor = vec4(float(k));",
             None),
            ("int k = 0; if (k < g_Threshold) { k = 1; }"
             " gl_FragColor = vec4(float(k));",
             "uniform float g_Threshold;"),
        ]
        for statement, extra in cases:
            with self.subTest(statement=statement), tempfile.TemporaryDirectory() as directory:
                command = [str(self.binary), statement]
                if extra is not None:
                    command.append(extra)
                output = json.loads(subprocess.check_output(command, text=True))
                fragment = output["normalizedFragment"]
                root = Path(directory)
                fragment_path = root / "author.frag"
                fragment_path.write_text(fragment, encoding="utf-8")
                compiled = subprocess.run(
                    [str(GLSLANG), "-V", "--auto-map-bindings",
                     "--auto-map-locations", str(fragment_path),
                     "-o", str(root / "result.spv")],
                    cwd=root, capture_output=True, text=True,
                )
                self.assertEqual(
                    compiled.returncode, 0, compiled.stdout + compiled.stderr
                )
                payload = (root / "result.spv").read_bytes()
                words = struct.unpack(f"<{len(payload) // 4}I", payload)
                opcode_counts: dict[int, int] = {}
                offset = 5
                while offset < len(words):
                    count, opcode = (
                        words[offset] >> 16, words[offset] & 0xFFFF
                    )
                    self.assertGreater(count, 0)
                    opcode_counts[opcode] = opcode_counts.get(opcode, 0) + 1
                    offset += count
                self.assertEqual(opcode_counts.get(110, 0), 0)

    def test_fractional_comparisons_and_loop_counts_render_authored_results(self) -> None:
        cross = GLSLANG.with_name("spirv-cross")
        cases = [
            ("int k = 0; float cutoff = 0.8; gl_FragColor = vec4(float(k < cutoff));", 1),
            ("int k = 0; float cutoff = -0.8; gl_FragColor = vec4(float(k > cutoff));", 1),
            ("uint k = 0u; float cutoff = 0.8; gl_FragColor = vec4(float(k < cutoff));", 1),
            ("int k = 0; float cutoff = -0.8; gl_FragColor = vec4(float(k <= cutoff));", 0),
            ("int k = 0; float cutoff = 0.8; gl_FragColor = vec4(float(k >= cutoff));", 0),
            ("int n = 0; float stop = 2.8; for (int k = 0; k < stop; ++k) { ++n; }"
             " gl_FragColor = vec4(float(n));", 3),
            ("int k = 0; float cutoff = 0.8; gl_FragColor = vec4(float(cutoff > k));", 1),
            ("float cutoff = 2.8; int k = cutoff; gl_FragColor = vec4(float(k));", 2),
        ]
        for statement, expected in cases:
            with self.subTest(statement=statement), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                normalized = json.loads(subprocess.check_output([str(self.binary), statement, "--no-inputs"], text=True))
                source = root / "comparison.frag"
                source.write_text(normalized["normalizedFragment"], encoding="utf-8")
                spirv = root / "comparison.spv"
                metal = root / "comparison.metal"
                for command in (
                    [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                     str(source), "-o", str(spirv)],
                    [str(cross), str(spirv), "--msl", "--rename-entry-point", "main",
                     "comparisonFragment", "frag", "--output", str(metal)],
                ):
                    compiled = subprocess.run(command, capture_output=True, text=True, timeout=30)
                    self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
                pixels = json.loads(subprocess.check_output(
                    [str(self.binary), "--render", str(metal)], text=True, timeout=30
                ))
                self.assertEqual(pixels, [float(expected)] * 8)

    def test_hlsl_attribute_annotations_are_stripped_and_link(self) -> None:
        # The archived syntax-error subclass: a bare `[loop]` line survives
        # normalization and glslang rejects it with "unexpected IDENTIFIER,
        # expecting LEFT_BRACKET". The annotation carries loop-execution
        # hints only, so stripping it preserves semantics and restores the
        # link.
        if not GLSLANG.is_file() or not os.access(GLSLANG, os.X_OK):
            self.skipTest("bundled glslang is unavailable")
        statement = (
            "[loop] for (int i = 0; i < 4; i++) {"
            " albedo.r += float(i); }"
        )
        with tempfile.TemporaryDirectory() as directory:
            output = json.loads(subprocess.check_output(
                [str(self.binary), statement], text=True,
            ))
            root = Path(directory)
            vertex = root / "author.vert"
            fragment = root / "author.frag"
            vertex.write_text(output["normalizedVertex"], encoding="utf-8")
            fragment.write_text(output["normalizedFragment"], encoding="utf-8")
            self.assertNotIn("[loop]", output["normalizedFragment"])
            linked = subprocess.run(
                [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                 "-l", str(vertex), str(fragment)],
                cwd=root, capture_output=True, text=True,
            )
            self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_octal_bounds_preserve_compiled_numeric_value(self) -> None:
        for peer in ("abs(g_Ratio)", "abs(g_Ratio.x)"):
            with self.subTest(peer=peer), tempfile.TemporaryDirectory() as directory:
                suffix = ", 0.0, 1.0" if peer == "abs(g_Ratio)" else ""
                statement = f"gl_FragColor = vec4(min(010, {peer}){suffix});"
                output = json.loads(subprocess.check_output(
                    [str(self.binary), statement], text=True,
                ))
                root = Path(directory)
                fragment = root / "author.frag"
                fragment.write_text(output["normalizedFragment"], encoding="utf-8")
                linked = subprocess.run(
                    [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                     str(fragment), "-o", str(root / "result.spv")],
                    cwd=root, capture_output=True, text=True,
                )
                self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)
                payload = (root / "result.spv").read_bytes()
                words = struct.unpack(f"<{len(payload) // 4}I", payload)
                float_types, constants = set(), []
                offset = 5
                while offset < len(words):
                    count, opcode = words[offset] >> 16, words[offset] & 0xffff
                    self.assertGreater(count, 0)
                    operands = words[offset + 1:offset + count]
                    if opcode == 22 and operands[1] == 32:  # OpTypeFloat
                        float_types.add(operands[0])
                    if opcode == 43 and operands[0] in float_types:  # OpConstant
                        constants.append(struct.unpack("<f", struct.pack("<I", operands[2]))[0])
                    offset += count
                self.assertIn(8.0, constants)
                self.assertNotIn(10.0, constants)


if __name__ == "__main__":
    unittest.main()

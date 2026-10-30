#!/usr/bin/env python3
"""Self-authored scalar remainder compiler and float-target behavior gate."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from script.tests.test_scene_shader_scalar_vector_builtin_canonicalization import (
    GLSLANG, HARNESS, REPOSITORY_ROOT, SWIFT_SOURCES,
)

HARNESS = HARNESS.replace(
    "    static func main() throws {",
    """    static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--bounded" {
            let source = try String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8)
            let pair = SceneAuthoredShaderBackendCanonicalizer.canonicalize(vertex: vertex, fragment: source)
            let output = SceneAuthoredShaderFrontend.compile(vertexSource: pair.vertex, fragmentSource: pair.fragment)
            if let program = output.program {
                _ = try MTLCreateSystemDefaultDevice()!.makeLibrary(source: program.metalSource, options: nil)
            }
            FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: [
                "diagnostics": output.diagnostics.map { $0.code.rawValue },
                "metalSource": output.program?.metalSource ?? "",
            ]))
            return
        }
""",
).replace(
    "            encoder.setRenderPipelineState(pipeline)",
    """            encoder.setRenderPipelineState(pipeline)
            var uniforms: [Float] = [6.25, 2.5, 0, 0, 0, 0, 0, 0]
            if let override = CommandLine.arguments.first(where: { $0.hasPrefix("--uniforms=") }) {
                let values = override.dropFirst(11).split(separator: ",").compactMap { Float($0) }
                for index in values.indices { uniforms[index] = values[index] }
            }
            encoder.setFragmentBytes(&uniforms, length: uniforms.count * 4, index: 0)""",
).replace(
    'CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--render"',
    'CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "--render"',
)


class SceneShaderScalarRemainderTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None or not GLSLANG.is_file():
            raise unittest.SkipTest("Swift/Metal shader toolchain is unavailable")
        cls.directory = tempfile.TemporaryDirectory()
        cls.cpu_compilations = []
        root = Path(cls.directory.name)
        harness = root / "ScalarRemainderHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "scalar-remainder-harness"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        subprocess.run([
            swiftc, "-parse-as-library", *(str(path) for path in SWIFT_SOURCES),
            str(harness), "-o", str(cls.binary),
        ], cwd=REPOSITORY_ROOT, env=environment, check=True, capture_output=True, text=True)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.directory.cleanup()

    def normalize(self, statement: str, declarations: str | None = None) -> dict:
        source = (declarations or "") + "\nvoid main() { " + statement + " }"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "self-authored.glsl"
            path.write_text(source, encoding="utf-8")
            return json.loads(subprocess.check_output([
                str(self.binary), "--analyze", str(path),
            ], text=True))

    def render(self, statement: str, declarations: str | None = None,
               *, bounded: bool = False, uniforms: tuple[float, float] | None = None,
               resource_path: str = "self-authored") -> list[float]:
        output = self.normalize(statement, declarations)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fragment = root / (resource_path + ".frag")
            fragment.parent.mkdir(parents=True, exist_ok=True)
            spirv = fragment.with_suffix(".spv")
            metal = fragment.with_suffix(".metal")
            if bounded:
                fragment.write_text((declarations or "") + "\nvoid main() { " + statement + " }", encoding="utf-8")
                compiled = json.loads(subprocess.check_output([
                    str(self.binary), "--bounded", str(fragment),
                ], text=True))
                self.assertEqual(compiled["diagnostics"], [])
                metal.write_text(compiled["metalSource"].replace(
                    "sceneAuthoredFragment", "comparisonFragment"), encoding="utf-8")
            else:
                fragment.write_text(output["normalizedFragment"], encoding="utf-8")
                for command in (
                    [str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations",
                     str(fragment), "-o", str(spirv)],
                    [str(GLSLANG.with_name("spirv-cross")), str(spirv), "--msl",
                     "--rename-entry-point", "main", "comparisonFragment", "frag",
                     "--output", str(metal)],
                ):
                    result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            arguments = [str(self.binary), "--render", str(metal)]
            if uniforms is not None:
                arguments.append("--uniforms=" + ",".join(map(str, uniforms)))
            return json.loads(subprocess.check_output(arguments, text=True, timeout=30))

    def compile_cpu(self, statement: str, declarations: str = "", *, succeeds: bool = True) -> str:
        output = self.normalize(statement, declarations)
        self.assertTrue(output["idempotent"])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            vertex, fragment, spirv = root / "case.vert", root / "case.frag", root / "case.spv"
            vertex.write_text(output["normalizedVertex"])
            fragment.write_text(output["normalizedFragment"])
            compiled = subprocess.run([
                str(GLSLANG), "-V", "--auto-map-bindings", "--auto-map-locations", "-l",
                "-g0", str(vertex), str(fragment), "-o", str(spirv),
            ], capture_output=True, text=True, timeout=30)
            record = {"method": self._testMethodName, "statement": statement,
                      "declarations": declarations, "exitCode": compiled.returncode,
                      "expectedSuccess": succeeds, "diagnostic": compiled.stdout + compiled.stderr,
                      "canonicalFragment": output["canonicalFragment"]}
            self.cpu_compilations.append(record)
            proof = os.environ.get("MWX_SCALAR_REMAINDER_PROOF")
            if proof:
                evidence = Path(proof)
                evidence.mkdir(parents=True, exist_ok=True)
                (evidence / "compiler-cases.json").write_text(json.dumps(self.cpu_compilations, indent=2) + "\n")
            self.assertEqual(compiled.returncode == 0, succeeds, record["diagnostic"])
            if not succeeds:
                return ""
            return subprocess.check_output([
                str(GLSLANG.with_name("spirv-cross")), str(spirv), "--msl",
            ], text=True, timeout=30)

    def test_compound_float_remainder_cpu_link_matches_binary_reference(self) -> None:
        cases = [
            ("float phase = -5.75; float period = 2.0; phase %= period;",
             "float phase = -5.75; float period = 2.0; phase = phase % period;",
             "gl_FragColor = vec4(phase, 0.0, 0.0, 1.0);", ""),
            ("float distance = 14.5; float span = 4.0; float observed = (distance %= span * 2.0 + 1.0);",
             "float distance = 14.5; float span = 4.0; float observed = (distance = distance % (span * 2.0 + 1.0));",
             "gl_FragColor = vec4(distance, observed, 0.0, 1.0);", ""),
            ("float value = 5.75; float observed = 2.0 * (value %= 4) + 1.0;",
             "float value = 5.75; float observed = 2.0 * (value = value % 4) + 1.0;",
             "gl_FragColor = vec4(value, observed, 0.0, 1.0);", ""),
            ("float value = 14.5; float period = 5.0; value %= (period % 3.0) + 0.5;",
             "float value = 14.5; float period = 5.0; value = value % ((period % 3.0) + 0.5);",
             "gl_FragColor = vec4(value, 0.0, 0.0, 1.0);", ""),
            ("float value = 5.75; value %= 2.0, value += 1.0;",
             "float value = 5.75; value = value % 2.0, value += 1.0;",
             "gl_FragColor = vec4(value, 0.0, 0.0, 1.0);", ""),
            ("float wrap(float travel, float period) { return travel %= period + 1.0; }",
             "float wrap(float travel, float period) { return (travel = travel % (period + 1.0)); }",
             "gl_FragColor = vec4(wrap(5.75, 1.0), 0.0, 0.0, 1.0);", "helper"),
            ("float signal = 0.0; for (float x = -radius; x <= radius; ++x) { signal += 1.0; } signal %= 2;",
             "float signal = 0.0; for (float x = -radius; x <= radius; ++x) { signal += 1.0; } signal = signal % 2;",
             "gl_FragColor = vec4(signal, 0.0, 0.0, 1.0);", "uniform float radius;"),
        ]
        for candidate, reference, output, declarations in cases:
            with self.subTest(candidate=candidate):
                if declarations == "helper":
                    actual = self.compile_cpu(output, candidate)
                    expected = self.compile_cpu(output, reference)
                else:
                    actual = self.compile_cpu(candidate + output, declarations)
                    expected = self.compile_cpu(reference + output, declarations)
                self.assertEqual(actual, expected)

    def test_compound_remainder_cpu_keeps_unknown_integer_and_readonly_boundaries(self) -> None:
        for statement in (
            "missing %= 2.0;", "vec2 value = vec2(5.75); value %= 2.0;",
            "float table[2]; int index = 0; table[index++] %= 2.0;",
            "Payload value; value.phase %= 2.0;",
            "float value = 5.75; { vec2 value = vec2(1.0); value %= 2.0; }",
            "float value = 5.75; value %= ++value;",
        ):
            with self.subTest(statement=statement):
                output = self.normalize(statement + "gl_FragColor = vec4(1.0);",
                                        "struct Payload { float phase; };")
                self.assertIn("%=", output["canonicalFragment"])
                self.assertNotIn("mwxScalarRemainder", output["canonicalFragment"])
        integer = "int signedValue = 19; uint unsignedValue = 19u; signedValue %= 6; unsignedValue %= 6u;"
        output = self.normalize(integer + "gl_FragColor = vec4(float(signedValue), float(unsignedValue), 0.0, 1.0);")
        self.assertNotIn("mwxScalarRemainder", output["canonicalFragment"])
        self.compile_cpu(integer + "gl_FragColor = vec4(float(signedValue), float(unsignedValue), 0.0, 1.0);")
        for statement, declarations in (
            ("const float frozen = 5.75; frozen %= 2.0;", ""),
            ("frozen %= 2.0;", "uniform float frozen;"),
            ("int value = 9; value %= 2.0;", ""),
            ("float a = 1.0; float x = 5.75; a + x %= 2;", ""),
            ("float x = 5.75; -x %= 2;", ""),
        ):
            with self.subTest(statement=statement, declarations=declarations):
                self.compile_cpu(statement + "gl_FragColor = vec4(1.0);", declarations, succeeds=False)

    def test_parenthesized_scalar_expression_remainder_renders(self) -> None:
        pixels = self.render(
            "float travel = 5.75; float period = 2.0;"
            " float result = (travel + 0.5) % (period + 0.5);"
            " gl_FragColor = vec4(result, 0.0, 0.0, 1.0);"
        )
        self.assertEqual(pixels, [1.25, 0.0, 0.0, 1.0] * 2)

    def test_scalar_uniform_components_and_renamed_equivalents_render(self) -> None:
        for name, expression, resource_path in (
            ("phaseSpan", "phaseSpan.x % phaseSpan.y", "timing-playground"),
            ("independentRange", "((independentRange.x + 0.0)) % ((independentRange.y * 1.0))",
             "renamed public resources/phase-renamed"),
        ):
            statement = f"gl_FragColor = vec4({expression}, 0.0, 0.0, 1.0);"
            for bounded in (False, True):
                with self.subTest(name=name, bounded=bounded):
                    self.assertEqual(self.render(statement, f"uniform vec2 {name};", bounded=bounded,
                                                 resource_path=resource_path),
                                     [1.25, 0.0, 0.0, 1.0] * 2)

    def test_project_truncating_remainder_signs_and_typed_targets_match(self) -> None:
        # Mixed-sign results assert the existing project's truncating policy;
        # they are not an official-client parity claim.
        statement = (
            "float magnitude = 5.75; float divisor = 2.0;"
            " float a = magnitude % divisor; float b = -magnitude % divisor;"
            " float c = magnitude % -divisor; float d = -magnitude % -divisor;"
            " gl_FragColor = vec4(a, b, c, d);"
        )
        for bounded in (False, True):
            with self.subTest(bounded=bounded):
                self.assertEqual(self.render(statement, bounded=bounded), [1.75, -1.75, 1.75, -1.75] * 2)
                self.assertEqual(self.render(
                    "float frequency = -5.75; int signedValue = frequency % 2;"
                    " uint positiveValue = (-frequency) % 2;"
                    " gl_FragColor = vec4(float(signedValue), float(positiveValue), 0.0, 1.0);",
                    bounded=bounded), [-1.0, 1.0, 0.0, 1.0] * 2)

    def test_precedence_nested_remainders_and_integer_neighbors_render(self) -> None:
        statement = (
            "float dividend = 14.5; float period = 4.0; float scale = 2.0;"
            " float first = dividend % period * scale;"
            " float nested = (dividend % period) % scale;"
            " float inner = dividend % (period % 3.0);"
            " float offset = 10.0 + period * 3.0 % scale;"
            " int integral = (17 + 2) % 6;"
            " gl_FragColor = vec4(first + float(integral), nested, inner, offset);"
        )
        output = self.normalize(statement)
        self.assertIn("(17 + 2) % 6", output["canonicalFragment"])
        self.assertTrue(output["idempotent"])
        for bounded in (False, True):
            with self.subTest(bounded=bounded):
                self.assertEqual(self.render(statement, bounded=bounded), [6.0, 0.5, 0.5, 10.0] * 2)

    def test_function_parameters_control_flow_and_unrelated_scope_render(self) -> None:
        declarations = (
            "int spare(int travel) { return travel; }"
            " float wrap(float travel, float period) { return (travel + 0.5) % period; }"
        )
        statement = (
            "float distance = 5.75; float period = 2.5; float result = 0.0;"
            " for (int step = 0; step < 2; ++step) {"
            " if (step == 1) { result = wrap(distance, period);"
            " result = (result + 5.0) % period; } }"
            " gl_FragColor = vec4(result, 0.0, 0.0, 1.0);"
        )
        for bounded in (False, True):
            with self.subTest(bounded=bounded):
                self.assertEqual(self.render(statement, declarations, bounded=bounded), [1.25, 0.0, 0.0, 1.0] * 2)

    def test_explicit_glsl_mod_keeps_floor_semantics(self) -> None:
        statement = "gl_FragColor = vec4(mod(-5.75, 2.0), mod(5.75, -2.0), 0.0, 1.0);"
        output = self.normalize(statement)
        self.assertIn("mod(-5.75, 2.0)", output["canonicalFragment"])
        self.assertNotIn("mwxScalarRemainder", output["canonicalFragment"])
        self.assertEqual(self.render(statement), [0.25, -0.25, 0.0, 1.0] * 2)

    def test_helper_collisions_and_comments_preserve_authored_bindings(self) -> None:
        declarations = "float mwxScalarRemainder(float a, float b) { return 7.0; }"
        statement = (
            "float left = 5.75; float right = 2.0; /* unknown % vector */"
            " gl_FragColor = vec4(left % right, mwxScalarRemainder(left, right), 0.0, 1.0);"
        )
        output = self.normalize(statement, declarations)
        self.assertTrue(output["idempotent"])
        for bounded in (False, True):
            with self.subTest(bounded=bounded):
                self.assertEqual(self.render(statement, declarations, bounded=bounded), [1.75, 7.0, 0.0, 1.0] * 2)

    def test_unknown_vector_array_shadow_and_side_effects_are_not_rewritten(self) -> None:
        cases = [
            "float result = missing % 2.0;",
            "vec2 direction = vec2(1.0); vec2 result = direction % 2.0;",
            "float value = 5.75; float result = value++ % 2.0;",
            "float value = 5.75; float result = value % ++value;",
            "float value = 5.75; float result = value % value++;",
            "float table[2]; float result = table[0] % 2.0;",
            "float value = 5.75; { vec2 value = vec2(1.0); vec2 result = value % 2.0; }",
            "float value = 5.75; float result = value % 2.0; { int value = 2; }",
            "float result = custom() % 2.0;",
        ]
        for statement in cases:
            with self.subTest(statement=statement):
                output = self.normalize(statement + " gl_FragColor = vec4(1.0);")
                self.assertIn("%", output["canonicalFragment"])
                self.assertNotIn("float mwxScalarRemainder", output["canonicalFragment"])

    def test_numeric_define_source_width_is_not_silently_cut(self) -> None:
        output = self.normalize(
            "float value = 5.75; float result = value % WRAP_PERIOD; gl_FragColor = vec4(result);",
            "#define WRAP_PERIOD 2.0",
        )
        self.assertIn("value % WRAP_PERIOD", output["canonicalFragment"])
        self.assertNotIn("mwxScalarRemainder", output["canonicalFragment"])

    def test_generic_control_flow_does_not_block_type_preparation(self) -> None:
        statements = [
            "float value = 5.75; float result = value % 2.0; if (result < 0.0) discard;",
            "float value = 5.75; float result = 0.0; int index = 0;"
            " while (index < 1) { result = value % 2.0; ++index; }",
            "float value = 5.75; float result = 0.0; int index = 0;"
            " do { result = value % 2.0; ++index; } while (index < 1);",
            "float value = 5.75; float result = 0.0; int selection = 1;"
            " switch (selection) { case 1: result = value % 2.0; break; default: result = 0.0; }",
        ]
        for statement in statements:
            statement += " gl_FragColor = vec4(result, 0.0, 0.0, 1.0);"
            with self.subTest(statement=statement):
                output = self.normalize(statement)
                self.assertIn("unsupportedControlFlow", output["strictDiagnosticCodes"])
                self.assertEqual(self.render(statement), [1.75, 0.0, 0.0, 1.0] * 2)
                self.assertEqual(output["typeDiagnosticCodes"], [])

    def test_large_finite_remainder_matches_bounded_native_builtin(self) -> None:
        pixels = self.render(
            "gl_FragColor = vec4(phaseRange.x % phaseRange.y, fmod(phaseRange.x, phaseRange.y), 0.0, 1.0);",
            "uniform vec2 phaseRange;", bounded=True, uniforms=(33554432.0, 3.0),
        )
        # Preserve the native builtin's result with the product's default Metal
        # compile options; this is not an IEEE exact-remainder claim.
        self.assertEqual(pixels[0], pixels[1])
        self.assertEqual(pixels[4], pixels[5])
        self.assertEqual(pixels[:4], pixels[4:])

    def test_authored_fmod_function_value_and_define_keep_ownership(self) -> None:
        for declaration in (
            "float fmod(float first, float second) { return first; }",
            "uniform float fmod;",
            "#define fmod 4.0",
        ):
            with self.subTest(declaration=declaration):
                output = self.normalize(
                    "float value = 5.75; float result = value % 2.0; gl_FragColor = vec4(result);",
                    declaration,
                )
                self.assertIn("value % 2.0", output["canonicalFragment"])
                self.assertNotIn("mwxScalarRemainder", output["canonicalFragment"])


if __name__ == "__main__":
    unittest.main()

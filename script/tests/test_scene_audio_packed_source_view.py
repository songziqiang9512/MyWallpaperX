#!/usr/bin/env python3
"""Packed audio source reads over the unchanged logical scalar uniform array.

The Metal comparison consumes raw SPIR-V std140 reflection, not the product
HostUniformEncoder layout. Actual media/FFT/upload order needs a separate gate.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

from script.tests import test_scene_generic_shader_type_spellings as SPELLINGS


class SceneAudioPackedSourceViewTests(unittest.TestCase):
    # Reuse the one real source/harness compiler without inheriting and
    # rediscovering the older spelling TestCase's unrelated test methods.
    @classmethod
    def setUpClass(cls) -> None:
        SPELLINGS.SceneGenericShaderTypeSpellingTests.setUpClass.__func__(cls)

    @classmethod
    def tearDownClass(cls) -> None:
        SPELLINGS.SceneGenericShaderTypeSpellingTests.tearDownClass.__func__(cls)

    link = SPELLINGS.SceneGenericShaderTypeSpellingTests.link
    assert_pixels = SPELLINGS.SceneGenericShaderTypeSpellingTests.assert_pixels

    def analyze(self, source: str, root: Path, name: str = "audio-view.frag") -> dict:
        authored = root / name
        authored.write_text(source, encoding="utf-8")
        completed = subprocess.run(
            [str(self.binary), "--analyze", str(authored)],
            cwd=root, env=self.environment, capture_output=True,
            text=True, timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        return json.loads(completed.stdout)

    def render_ramp(
        self, payload: dict, root: Path, uniform: str, count: int,
    ) -> list[float]:
        linked = self.link(payload, root)
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)
        fragment = root / "linked.frag"
        spirv, metal = root / "fragment.spv", root / "fragment.metal"
        cross = SPELLINGS.GLSLANG.with_name("spirv-cross")
        completed = subprocess.run(
            [str(SPELLINGS.GLSLANG), "-V", "--auto-map-bindings",
             "--auto-map-locations", str(fragment), "-o", str(spirv)],
            cwd=root, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        reflected = subprocess.run(
            [str(cross), str(spirv), "--reflect"],
            cwd=root, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(reflected.returncode, 0, reflected.stdout + reflected.stderr)
        reflection = json.loads(reflected.stdout)
        ubos = reflection.get("ubos", [])
        self.assertEqual(len(ubos), 1, reflection)
        ubo = ubos[0]
        members = reflection["types"][ubo["type"]]["members"]
        matches = [member for member in members if member["name"] == uniform]
        self.assertEqual(len(matches), 1, reflection)
        member = matches[0]
        self.assertEqual(member["type"], "float", member)
        self.assertEqual(member["array"], [count], member)
        # Raw Vulkan scalar arrays use 16-byte stride. The product later
        # lowers this ABI separately; do not fill it as contiguous host data.
        self.assertEqual(member["array_stride"], 16, member)
        offset, stride = member["offset"], member["array_stride"]
        self.assertGreaterEqual(offset, 0)
        self.assertEqual(offset % 4, 0)
        self.assertLessEqual(offset + (count - 1) * stride + 4, ubo["block_size"])
        raw = bytearray([0xA5] * ubo["block_size"])
        for index in range(count):
            struct.pack_into("<f", raw, offset + index * stride, (index + 1) / 128)
        completed = subprocess.run(
            [str(cross), str(spirv), "--msl", "--rename-entry-point", "main",
             "comparisonFragment", "frag", "--output", str(metal)],
            cwd=root, capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        indices = re.findall(r"\[\[buffer\((\d+)\)\]\]", metal.read_text())
        self.assertEqual(len(indices), 1, metal.read_text())
        inputs = root / "fragment-uniforms.json"
        inputs.write_text(json.dumps([{"index": int(indices[0]), "bytes": list(raw)}]))
        (root / "uniform-layout.json").write_text(json.dumps({
            "reflection": reflection, "metalBufferIndex": int(indices[0]),
            "logicalCount": count, "rawSPIRVOnly": True,
        }, sort_keys=True))
        completed = subprocess.run(
            [str(self.binary), "--render-uniforms", str(metal), str(inputs)],
            cwd=root, env=self.environment, capture_output=True,
            text=True, timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        return json.loads(completed.stdout)

    def test_first_interior_last_rows_and_equivalent_source_names(self) -> None:
        cases = (
            ("g_AudioSpectrum64Left", 64, "float4", "int cursor = 0;", "cursor", 0),
            ("g_AudioSpectrum64Left", 64, "vec4", "int cursor = 15;", "((cursor))", 15),
            ("g_AudioSpectrum32Right", 32, "float4", "int band = 13;", "(band / 4 + 0)", 3),
            ("g_AudioSpectrum16Left", 16, "vec4", "int renamedRow = 2;", "renamedRow", 2),
        )
        for ordinal, (uniform, count, spelling, setup, row, selected) in enumerate(cases):
            with self.subTest(uniform=uniform, row=row), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = (f"uniform float {uniform}[{count}];\n"
                          f"void main() {{ {setup} {spelling} lanes = ({uniform}[{row}]); "
                          "gl_FragColor = lanes; }")
                payload = self.analyze(source, root, f"renamed-resource-{ordinal}.frag")
                self.assertTrue(payload["idempotent"], payload)
                expected = [(selected * 4 + lane + 1) / 128 for lane in range(4)]
                self.assertEqual(len(set(expected)), 4)
                self.assert_pixels(self.render_ramp(payload, root, uniform, count), expected)

    def test_invalid_rows_return_zero_without_clamping_or_overflow(self) -> None:
        uniform = "g_AudioSpectrum64Right"
        for row in (-1, 16, 2147483647):
            with self.subTest(row=row), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = (f"uniform float {uniform}[64];\n"
                          f"void main() {{ int row = {row}; float4 lanes = {uniform}[row]; "
                          "gl_FragColor = lanes; }")
                payload = self.analyze(source, root)
                self.assertTrue(payload["idempotent"], payload)
                self.assert_pixels(self.render_ramp(payload, root, uniform, 64), [0.0] * 4)

    def test_direct_scalar_and_existing_contiguous_index_remain_single_bin(self) -> None:
        uniform = "g_AudioSpectrum64Left"
        sources = (
            f"uniform float {uniform}[64];\n"
            f"void main() {{ int bin = 5; float value = {uniform}[bin]; "
            "gl_FragColor = vec4(value); }",
            f"uniform float {uniform}[64];\n"
            f"void main() {{ gl_FragColor = vec4({uniform}[5]); }}",
            f"uniform float {uniform}[64];\n"
            f"float readBin(float bin) {{ return {uniform}[bin / 4][bin % 4]; }}\n"
            "void main() { gl_FragColor = vec4(readBin(5)); }",
        )
        for source in sources:
            with self.subTest(source=source), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                payload = self.analyze(source, root)
                self.assertTrue(payload["idempotent"], payload)
                self.assert_pixels(self.render_ramp(payload, root, uniform, 64), [6 / 128] * 4)

    def test_inout_integer_row_is_read_by_value(self) -> None:
        source = """
uniform float g_AudioSpectrum32Left[32];
vec4 readLanes(inout int row) {
    vec4 result = g_AudioSpectrum32Left[row];
    return result;
}
void main() {
    int position = 2;
    vec4 color = readLanes(position);
    gl_FragColor = position == 2 ? color : vec4(-1.0);
}
"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = self.analyze(source, root)
            self.assertTrue(payload["idempotent"], payload)
            self.assert_pixels(self.render_ramp(payload, root, "g_AudioSpectrum32Left", 32),
                               [9 / 128, 10 / 128, 11 / 128, 12 / 128])

    def test_non_audio_shapes_and_unsafe_rows_keep_their_rejection_boundary(self) -> None:
        cases = (
            ("ordinary", "uniform float ordinaryBins[64];",
             "vec4 lanes = ordinaryBins[1];", "ordinaryBins[1]"),
            ("wrong-count", "uniform float g_AudioSpectrum64Left[32];",
             "vec4 lanes = g_AudioSpectrum64Left[1];", "g_AudioSpectrum64Left[1]"),
            ("non-uniform", "float g_AudioSpectrum64Left[64];",
             "vec4 lanes = g_AudioSpectrum64Left[1];", "g_AudioSpectrum64Left[1]"),
            ("vec2", "uniform float g_AudioSpectrum64Left[64];",
             "vec2 lanes = g_AudioSpectrum64Left[1];", "g_AudioSpectrum64Left[1]"),
            ("vec3", "uniform float g_AudioSpectrum64Left[64];",
             "vec3 lanes = g_AudioSpectrum64Left[1];", "g_AudioSpectrum64Left[1]"),
            ("float-row", "uniform float g_AudioSpectrum64Left[64];",
             "float row = 1.0; vec4 lanes = g_AudioSpectrum64Left[row];", None),
            ("side-effect-row", "uniform float g_AudioSpectrum64Left[64];",
             "int row = 1; vec4 lanes = g_AudioSpectrum64Left[row++];", None),
            ("unknown-call-row", "uniform float g_AudioSpectrum64Left[64];\n"
             "int chooseRow(int row) { return row; }",
             "vec4 lanes = g_AudioSpectrum64Left[chooseRow(1)];", None),
            ("local-shadow", "uniform float g_AudioSpectrum64Left[64];",
             "float g_AudioSpectrum64Left[64]; vec4 lanes = g_AudioSpectrum64Left[1];", None),
            ("macro-audio-name", "#define g_AudioSpectrum64Left ordinaryBins\n"
             "uniform float g_AudioSpectrum64Left[64];",
             "vec4 lanes = g_AudioSpectrum64Left[1];", None),
            ("macro-helper-name", "#define mwxPackedAudio_g_AudioSpectrum64Left occupied\n"
             "uniform float g_AudioSpectrum64Left[64];",
             "vec4 lanes = g_AudioSpectrum64Left[1];", None),
            ("source-helper-name", "uniform float g_AudioSpectrum64Left[64];\n"
             "vec4 mwxPackedAudio_g_AudioSpectrum64Left(int row) { return vec4(0.5); }",
             "vec4 lanes = g_AudioSpectrum64Left[1];", None),
        )
        for name, declarations, statement, preserved in cases:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                # No component use can erase the invalid scalar-to-vector
                # assignment: GLSL must type-check the declaration itself.
                source = declarations + "\nvoid main() { " + statement + " gl_FragColor = vec4(0.5); }"
                payload = self.analyze(source, root)
                canonical = payload["canonicalFragment"]
                self.assertTrue(payload["idempotent"], payload)
                if preserved:
                    self.assertIn(preserved, canonical)
                self.assertRegex(canonical,
                                 r"\bvec[234]\s+lanes\s*=\s*(?:ordinaryBins|g_AudioSpectrum64Left)\s*\[")
                if "normalizedFragment" in payload:
                    linked = self.link(payload, root)
                    self.assertNotEqual(linked.returncode, 0, linked.stdout + linked.stderr)

    def test_vector_array_with_same_name_keeps_its_valid_vector_type(self) -> None:
        source = ("void main() { vec4 g_AudioSpectrum64Left[16]; "
                  "g_AudioSpectrum64Left[0] = vec4(0.125, 0.25, 0.5, 0.75); "
                  "vec4 lanes = g_AudioSpectrum64Left[0]; gl_FragColor = lanes; }")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = self.analyze(source, root)
            canonical = payload["canonicalFragment"]
            self.assertIn("vec4 g_AudioSpectrum64Left[16]", canonical)
            self.assertIn("vec4 lanes = g_AudioSpectrum64Left[0]", canonical)
            self.assertNotRegex(canonical, r"\buniform\b")
            # A local vector array has no global scalar/audio source view.
            pixels = SPELLINGS.SceneGenericShaderTypeSpellingTests.render(self, payload, root)
            self.assert_pixels(pixels, [0.125, 0.25, 0.5, 0.75])

    def test_shadowed_array_parameters_and_uniform_writes_are_not_licensed(self) -> None:
        for qualifier in ("in", "out", "inout"):
            with self.subTest(qualifier=qualifier), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = (
                    "uniform float g_AudioSpectrum64Left[64];\n"
                    f"vec4 readOther({qualifier} float g_AudioSpectrum64Left[64]) {{ "
                    "vec4 result = g_AudioSpectrum64Left[1]; return result; }\n"
                    "void main() { float localBins[64]; gl_FragColor = readOther(localBins); }"
                )
                payload = self.analyze(source, root)
                self.assertRegex(payload["canonicalFragment"],
                                 r"\bvec4\s+result\s*=\s*g_AudioSpectrum64Left\s*\[\s*1\s*\]")
                if "normalizedFragment" in payload:
                    linked = self.link(payload, root)
                    self.assertNotEqual(linked.returncode, 0, linked.stdout + linked.stderr)
        for qualifier in ("out", "inout"):
            with self.subTest(uniformWrite=qualifier), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                source = (
                    "uniform float g_AudioSpectrum64Left[64];\n"
                    f"void writeBins({qualifier} float values[64]) {{ values[0] = 0.5; }}\n"
                    "void main() { writeBins(g_AudioSpectrum64Left); "
                    "vec4 lanes = g_AudioSpectrum64Left[1]; gl_FragColor = lanes; }"
                )
                payload = self.analyze(source, root)
                self.assertIn("writeBins(g_AudioSpectrum64Left)", payload["canonicalFragment"])
                # Adapting an independent read must never license a uniform
                # write. The original strict GLSL error must remain.
                if "normalizedFragment" in payload:
                    linked = self.link(payload, root)
                    self.assertNotEqual(linked.returncode, 0, linked.stdout + linked.stderr)


if __name__ == "__main__":
    unittest.main()

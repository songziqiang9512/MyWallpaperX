#!/usr/bin/env python3
"""Read-only numeric function inputs use the existing shared compiler chain."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_shader_scalar_vector_builtin_canonicalization as harness


class SceneDirectFunctionScalarConversionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        # Reuse the existing canonicalizer -> normalizer -> Metal fixture.
        harness.SceneShaderScalarVectorBuiltInCanonicalizationTests.setUpClass()
        cls.binary = harness.SceneShaderScalarVectorBuiltInCanonicalizationTests.binary

    @classmethod
    def tearDownClass(cls) -> None:
        harness.SceneShaderScalarVectorBuiltInCanonicalizationTests.tearDownClass()

    def analyze(self, source: str, root: Path) -> dict:
        authored = root / 'source.frag'
        authored.write_text(source)
        return json.loads(subprocess.check_output(
            [str(self.binary), '--analyze', str(authored)], text=True, timeout=30))

    def test_fractional_read_only_arguments_truncate_at_the_call(self) -> None:
        source = '''
float takeValue(vec2 unused, in int amount) { return float(amount); }
void main() {
    vec2 uv = vec2(0.0);
    float positive = 1.9;
    float negative = -1.9;
    float red = takeValue(uv, positive);
    float green = takeValue(uv, negative);
    float blue = takeValue(uv, 0.75);
    gl_FragColor = vec4(red, green, blue, 1.0);
}
'''
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.analyze(source, root)
            self.assertTrue(result['idempotent'])
            vertex, fragment = root / 'author.vert', root / 'author.frag'
            vertex.write_text(result['normalizedVertex'])
            fragment.write_text(result['normalizedFragment'])
            spirv, metal = root / 'result.spv', root / 'result.metal'
            for command in (
                [str(harness.GLSLANG), '-V', '--auto-map-bindings', '--auto-map-locations',
                 '-l', str(vertex), str(fragment)],
                [str(harness.GLSLANG), '-V', '--auto-map-bindings', '--auto-map-locations',
                 str(fragment), '-o', str(spirv)],
                [str(harness.GLSLANG.with_name('spirv-cross')), str(spirv), '--msl',
                 '--rename-entry-point', 'main', 'comparisonFragment', 'frag', '--output', str(metal)],
            ):
                compiled = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=30)
                self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            pixels = json.loads(subprocess.check_output(
                [str(self.binary), '--render', str(metal)], text=True, timeout=30))
            self.assertEqual(pixels, [1.0, -1.0, 0.0, 1.0] * 2)

    def test_numeric_builtin_overload_keeps_float_arguments(self) -> None:
        source = '''
float pow(int a, int b) { return 0.25; }
void main() { float value = 1.9; gl_FragColor = vec4(pow(value, value)); }
'''
        with tempfile.TemporaryDirectory() as directory:
            result = self.analyze(source, Path(directory))
            self.assertIn('pow(value, value)', result['normalizedFragment'])
            self.assertNotIn('pow(int(value)', result['normalizedFragment'])
            texture_source = '''
uniform sampler2D g_Texture0;
vec4 textureLod(sampler2D tex, vec2 uv, int level) { return vec4(0.25); }
void main() { vec2 uv = vec2(0.5); float lod = 1.9;
    gl_FragColor = textureLod(g_Texture0, uv, lod); }
'''
            result = self.analyze(texture_source, Path(directory))
            self.assertIn('textureLod(g_Texture0, uv, lod)', result['normalizedFragment'])
            self.assertNotIn('uv, int(lod)', result['normalizedFragment'])

    def test_mutable_overloaded_and_unknown_inputs_are_not_retyped(self) -> None:
        cases = [
            ('float takeValue(out int amount) { amount = 1; return 0.0; }',
             'float value = 1.9;', 'takeValue(value)'),
            ('float takeValue(inout int amount) { amount += 1; return 0.0; }',
             'float value = 1.9;', 'takeValue(value)'),
            ('float takeValue(int amount) { return float(amount); }\n'
             'float takeValue(float amount) { return amount; }',
             'float value = 1.9;', 'takeValue(value)'),
            ('float takeValue(int amount) { return float(amount); }',
             '', 'takeValue(missing)'),
            ('float takeValue(int amount) { return float(amount); }',
             'vec2 value = vec2(1.9);', 'takeValue(value)'),
        ]
        cases += [
            ('float elsewhere(float value) { return value; }\n'
             'float takeValue(int amount) { return float(amount); }',
             '', 'takeValue(value)'),
            ('float elsewhere(float value) { return value; }\n'
             'float takeValue(int amount) { return float(amount); }',
             'int value = 1;', 'takeValue(value)'),
            ('float takeValue(int amount) { return float(amount); }',
             'float value[2];', 'takeValue(value)'),
            ('float takeValue(int amount) { return float(amount); }',
             'float value[2];', 'takeValue(value[0])'),
            ('float takeValue(int amount) { return float(amount); }',
             '{ float value = 1.9; }', 'takeValue(value)'),
            ('float takeValue(int amount) { return float(amount); }',
             'float value = 1.9; { int value = 1; }', 'takeValue(value)'),
            ('float takeValue(int amount) { return float(amount); }\n'
             'float takeValue(float value);',
             'float value = 1.9;', 'takeValue(value)'),
            ('float takeValue(int amount) { return float(amount); }',
             'float value = 1.9;', 'takeValue(value + 0.5)'),
        ]
        with tempfile.TemporaryDirectory() as directory:
            for helpers, declaration, call in cases:
                with self.subTest(helpers=helpers, call=call):
                    source = helpers + '\nvoid main() { ' + declaration
                    source += ' gl_FragColor = vec4(' + call + '); }'
                    result = self.analyze(source, Path(directory))
                    self.assertIn(call, result['normalizedFragment'])
                    self.assertNotIn('takeValue(int(', result['normalizedFragment'])


if __name__ == '__main__':
    unittest.main()

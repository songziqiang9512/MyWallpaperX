#!/usr/bin/env python3
"""Typed smoothstep endpoint broadcasts use the shared compiler and GPU harness."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.tests import test_scene_shader_scalar_vector_builtin_canonicalization as harness


class SceneSmoothstepVectorBroadcastTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        harness.SceneShaderScalarVectorBuiltInCanonicalizationTests.setUpClass()
        cls.binary = harness.SceneShaderScalarVectorBuiltInCanonicalizationTests.binary

    @classmethod
    def tearDownClass(cls) -> None:
        harness.SceneShaderScalarVectorBuiltInCanonicalizationTests.tearDownClass()

    def analyze(self, source: str, root: Path) -> dict:
        authored = root / 'source.frag'
        authored.write_text(source, encoding='utf-8')
        return json.loads(subprocess.check_output(
            [str(self.binary), '--analyze', str(authored)], text=True, timeout=30))

    def compile_fragment(self, result: dict, root: Path) -> subprocess.CompletedProcess:
        vertex, fragment = root / 'author.vert', root / 'author.frag'
        vertex.write_text(result['normalizedVertex'], encoding='utf-8')
        fragment.write_text(result['normalizedFragment'], encoding='utf-8')
        return subprocess.run(
            [str(harness.GLSLANG), '-V', '--auto-map-bindings', '--auto-map-locations',
             '-l', str(vertex), str(fragment)],
            cwd=root, capture_output=True, text=True, timeout=30)

    def pixels(self, result: dict, root: Path) -> list[float]:
        linked = self.compile_fragment(result, root)
        self.assertEqual(linked.returncode, 0, linked.stdout + linked.stderr)
        spirv, metal = root / 'result.spv', root / 'result.metal'
        for command in (
            [str(harness.GLSLANG), '-V', '--auto-map-bindings', '--auto-map-locations',
             str(root / 'author.frag'), '-o', str(spirv)],
            [str(harness.GLSLANG.with_name('spirv-cross')), str(spirv), '--msl',
             '--rename-entry-point', 'main', 'comparisonFragment', 'frag', '--output', str(metal)],
        ):
            compiled = subprocess.run(command, cwd=root, capture_output=True,
                                      text=True, timeout=30)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        return json.loads(subprocess.check_output(
            [str(self.binary), '--render', str(metal)], text=True, timeout=30))

    def compare_explicit_broadcast(self, source: str, explicit: str, root: Path) -> dict:
        candidate, reference = root / 'candidate', root / 'reference'
        candidate.mkdir()
        reference.mkdir()
        result = self.analyze(source, candidate)
        expected = self.analyze(explicit, reference)
        self.assertTrue(result['idempotent'])
        actual_pixels = self.pixels(result, candidate)
        reference_pixels = self.pixels(expected, reference)
        self.assertEqual(len(actual_pixels), 8)
        for actual, wanted in zip(actual_pixels, reference_pixels):
            self.assertAlmostEqual(actual, wanted, places=6)
        return result

    def test_mixed_vector_edges_link_and_match_explicit_broadcast_on_gpu(self) -> None:
        # Same expression shape as the authored deformer call; no author media
        # or sample identity enters this reusable compatibility gate.
        for width in (2, 3, 4):
            for scalar_first in (False, True):
                with self.subTest(width=width, scalar_first=scalar_first):
                    lower = '0.0' if scalar_first else 'lower'
                    upper = 'upper' if scalar_first else '0.5'
                    call = f'smoothstep({lower}, {upper}, (uv - 0.5) * direction)'
                    explicit_lower = f'vec{width}(0.0)' if scalar_first else 'lower'
                    explicit_upper = 'upper' if scalar_first else f'vec{width}(0.5)'
                    explicit_call = (f'smoothstep({explicit_lower}, {explicit_upper}, '
                                     '(uv - 0.5) * direction)')
                    components = ', '.join(('0.625', '0.75', '0.875', '1.0')[:width])
                    output = {2: 'vec4(value, 0.125, 1.0)',
                              3: 'vec4(value, 1.0)', 4: 'value'}[width]
                    source = f'''void main() {{
    vec{width} uv = vec{width}({components});
    vec{width} direction = vec{width}(1.0);
    vec{width} lower = vec{width}(0.0); vec{width} upper = vec{width}(0.5);
    vec{width} value = {call};
    gl_FragColor = {output};
}}'''
                    with tempfile.TemporaryDirectory() as directory:
                        result = self.compare_explicit_broadcast(
                            source, source.replace(call, explicit_call), Path(directory))
                        self.assertIn(explicit_call, result['canonicalFragment'])

    def test_parameter_scopes_and_scalar_arithmetic_are_typed_locally(self) -> None:
        source = '''
float elsewhere(float direction) { return direction; }
vec2 transition(vec2 lower, float upper, vec2 position, vec2 direction) {
    return smoothstep(lower, upper + 0.125, (position - 0.5) * direction);
}
void main() {
    vec2 value = transition(vec2(0.0), 0.375, vec2(0.625), vec2(1.0));
    gl_FragColor = vec4(value, 0.125, 1.0);
}'''
        with tempfile.TemporaryDirectory() as directory:
            result = self.compare_explicit_broadcast(source, source.replace(
                'smoothstep(lower, upper + 0.125,',
                'smoothstep(lower, vec2(upper + 0.125),'), Path(directory))
            self.assertIn('smoothstep(lower, vec2(upper + 0.125),',
                          result['canonicalFragment'])

    def test_native_scalar_edges_and_same_width_vectors_keep_their_calls(self) -> None:
        for call in ('smoothstep(0.0, 0.5, position)',
                     'smoothstep(lower, upper, position)'):
            with self.subTest(call=call), tempfile.TemporaryDirectory() as directory:
                source = f'''void main() {{
    vec2 lower = vec2(0.0); vec2 upper = vec2(0.5);
    vec2 position = vec2(0.125, 0.375);
    vec2 value = {call}; gl_FragColor = vec4(value, 0.125, 1.0);
}}'''
                result = self.analyze(source, Path(directory))
                self.assertEqual(result['canonicalFragment'], source)
                self.assertTrue(result['idempotent'])
                expected = [0.15625, 0.84375, 0.125, 1.0] * 2
                for actual, wanted in zip(self.pixels(result, Path(directory)), expected):
                    self.assertAlmostEqual(actual, wanted, places=6)

    def test_authored_overload_keeps_its_body_and_gpu_result(self) -> None:
        source = '''
vec2 smoothstep(vec2 lower, float upper, vec2 position) { return vec2(0.25, 0.75); }
void main() { vec2 lower = vec2(0.0); vec2 position = vec2(0.125);
    gl_FragColor = vec4(smoothstep(lower, 0.5, position), 0.125, 1.0); }
'''
        with tempfile.TemporaryDirectory() as directory:
            result = self.analyze(source, Path(directory))
            self.assertEqual(result['canonicalFragment'], source)
            self.assertEqual(self.pixels(result, Path(directory)),
                             [0.25, 0.75, 0.125, 1.0] * 2)

    def test_unknown_wrong_width_and_unproven_scope_stay_rejected(self) -> None:
        cases = [
            ('', '', 'smoothstep(lower, missing, position)'),
            ('', 'vec3 upper = vec3(0.5);', 'smoothstep(lower, upper, position)'),
            ('', 'vec3 positionWide = vec3(0.125);',
             'smoothstep(lower, 0.5, positionWide)'),
            ('', 'vec3 wide = vec3(1.0);', 'smoothstep(lower, 0.5, position * wide)'),
            ('float elsewhere(float upper) { return upper; }', '',
             'smoothstep(lower, upper, position)'),
            ('', '{ float upper = 0.5; }', 'smoothstep(lower, upper, position)'),
            ('', 'float upper[2];', 'smoothstep(lower, upper[0], position)'),
            ('', 'int upper = 1;', 'smoothstep(lower, upper, position)'),
            ('', 'float upper = 0.5; { vec3 upper = vec3(0.5); }',
             'smoothstep(lower, upper, position)'),
        ]
        for helper, declaration, call in cases:
            with self.subTest(call=call, declaration=declaration), \
                    tempfile.TemporaryDirectory() as directory:
                source = helper + f'''\nvoid main() {{
    vec2 lower = vec2(0.0); vec2 position = vec2(0.125);
    {declaration} gl_FragColor = vec4({call}, 0.125, 1.0);
}}'''
                result = self.analyze(source, Path(directory))
                expected = source.replace('position * wide', 'position * (wide).xy')
                self.assertEqual(result['canonicalFragment'], expected)
                self.assertTrue(result['idempotent'])
                compiled = self.compile_fragment(result, Path(directory))
                self.assertNotEqual(compiled.returncode, 0,
                                    'unproven call unexpectedly compiled: ' + call)

    def test_authored_prototype_and_malformed_sources_are_not_broadcast(self) -> None:
        for source in (
            'vec2 smoothstep(vec2 lower, float upper, vec2 position);\n'
            'void main() { vec2 lower = vec2(0.0); vec2 position = vec2(0.125);'
            ' gl_FragColor = vec4(smoothstep(lower, 0.5, position), 0.125, 1.0); }',
            'void main() { vec2 lower = vec2(0.0); vec2 position = vec2(0.125); @;'
            ' gl_FragColor = vec4(smoothstep(lower, 0.5, position), 0.125, 1.0); }',
        ):
            with self.subTest(source=source), tempfile.TemporaryDirectory() as directory:
                result = self.analyze(source, Path(directory))
                self.assertEqual(result['canonicalFragment'], source)

    def test_new_additive_proof_does_not_widen_other_builtin_rewrites(self) -> None:
        for call in ('pow(position - 0.5, 0.5)',
                     'mix(position - 0.5, wide, 0.5)',
                     'smoothstep(lower, 0.5, position + wide)'):
            with self.subTest(call=call), tempfile.TemporaryDirectory() as directory:
                source = f'''void main() {{
    vec2 lower = vec2(0.0); vec2 position = vec2(0.125);
    vec3 wide = vec3(1.0); gl_FragColor = vec4({call}, 0.125, 1.0);
}}'''
                result = self.analyze(source, Path(directory))
                expected = source.replace('position + wide', 'position + (wide).xy')
                self.assertEqual(result['canonicalFragment'], expected)
                self.assertTrue(result['idempotent'])
                self.assertNotEqual(self.compile_fragment(result, Path(directory)).returncode, 0)


if __name__ == '__main__':
    unittest.main()

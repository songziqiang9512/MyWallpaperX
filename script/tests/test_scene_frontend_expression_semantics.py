"""Value and binding contracts, independent of equivalent emitted expression shapes."""
import unittest

from script.tests.scene_authored_shader_frontend_harness import (
    AuthoredShaderFrontendHarness, VEC4_COORDINATE_VERTEX_SOURCE,
)


class SceneFrontendExpressionSemanticsTests(AuthoredShaderFrontendHarness, unittest.TestCase):
    def test_component_expression_narrowing_preserves_values_and_operator_order(self):
        fragment = """
            varying vec4 v_Coordinates;
            uniform vec4 g_SourceResolution;
            uniform vec4 g_ProviderResolution;
            uniform vec2 g_ScaleCenter;
            uniform vec2 g_TextureScale;
            uniform vec2 g_Offset;
            void main() {
                vec2 ratio = vec2(g_ProviderResolution.x / g_ProviderResolution.y,
                                  g_SourceResolution.x / g_SourceResolution.y);
                vec2 center = g_ScaleCenter * 2.0 - 1.0;
                vec2 coordinates = (((v_Coordinates * 2.0 - 1.0 - center)
                    / ratio / g_TextureScale + 1.0 + center) / 2.0 - g_Offset);
                gl_FragColor = vec4(coordinates, 0.0, 1.0);
            }
        """
        kernel = """
        constant SceneAuthoredUniforms mwxTestUniforms = {
            float4(120, 60, 0, 0), float4(160, 40, 0, 0),
            float2(0.75, 0.375), float2(1.25, 0.8), float2(0.1, -0.2), float2(0)
        };
        kernel void mwxTestEvaluate(device float4 *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
            const float4 inputs[3] = { float4(0.25, 0.75, 11, -7),
                float4(-0.25, 0.8, -4, 31), float4(1.2, -0.5, 102, 64) };
            SceneAuthoredFragmentInput input = {};
            input.v_Coordinates = inputs[id];
            float4 result = {};
            mwxF_main(input, result, mwxTestUniforms);
            out[id] = result;
        }
        """
        expected = []
        for xy in ((0.25, 0.75), (-0.25, 0.8), (1.2, -0.5)):
            for value, center, ratio, scale, offset in zip(xy, (0.5, -0.25), (4, 2),
                                                         (1.25, 0.8), (0.1, -0.2)):
                expected.append((((value * 2 - 1 - center) / ratio / scale + 1 + center) / 2) - offset)
            expected.extend((0, 1))
        for varying, expression in (('v_Coordinates', 'v_Coordinates * 2.0'),
                                    ('v_PathUV', '2.0 * v_Coordinates'),
                                    ('v_Compound', '(v_Coordinates + vec4(0.0)) * 2.0'),
                                    ('v_Local', 'localUV * 2.0')):
            with self.subTest(varying=varying, expression=expression):
                output = self.compile(VEC4_COORDINATE_VERTEX_SOURCE.replace('v_Coordinates', varying),
                    fragment.replace('void main() {', 'void main() { vec4 localUV = v_Coordinates;')
                        .replace('v_Coordinates * 2.0', expression).replace('v_Coordinates', varying),
                    canonicalize=True)
                self.assertEqual(output['diagnosticCodes'], [])
                self.assertIsNone(output.get('metalError'))
                values = self.evaluate(output['metalSource'], kernel.replace('v_Coordinates', varying), 3)
                self.assertEqual(len(values), len(expected))
                for value, wanted in zip(values, expected):
                    self.assertAlmostEqual(value, wanted, places=6)

        # normalize(vec4) cannot be moved after a vec2 narrowing: z/w affect x/y.
        invalid = self.compile(VEC4_COORDINATE_VERTEX_SOURCE, """
            varying vec4 v_Coordinates;
            void main() { vec2 value = normalize(v_Coordinates); gl_FragColor = vec4(value, 0.0, 1.0); }
        """)
        self.assertIsNotNone(invalid.get('metalError'))

    def test_builtin_vectors_do_not_borrow_a_different_functions_scalar_scope(self):
        for expression, expected in (('abs(scale)', (0.1, 0.2)),
                                     ('pow(scale, 2.0)', (0.01, 0.04))):
            with self.subTest(expression=expression):
                scale_y = -0.2 if expression == "abs(scale)" else 0.2
                fragment = f'''float helper() {{ float scale = 0.5; return scale; }}
                    void main() {{ vec3 spare = vec3(0.0), scale = vec3(0.1, {scale_y}, 99.0);
                        vec2 first = vec2(0.0), value = {expression};
                        gl_FragColor = vec4(first + value, 0.0, 1.0); }}'''
                output = self.compile(VEC4_COORDINATE_VERTEX_SOURCE, fragment, canonicalize=True)
                self.assertEqual(output['diagnosticCodes'], [])
                self.assertIsNone(output.get('metalError'))
                kernel = '''constant SceneAuthoredUniforms mwxTestUniforms = {float2(0)};
                    kernel void mwxTestEvaluate(device float4 *out [[buffer(0)]]) {
                        SceneAuthoredFragmentInput input = {}; float4 value = {};
                        mwxF_main(input, value, mwxTestUniforms); out[0] = value;
                    }'''
                values = self.evaluate(output['metalSource'], kernel, 1)
                self.assertEqual(len(values), 4)
                for actual, wanted in zip(values, (*expected, 0, 1)):
                    self.assertAlmostEqual(actual, wanted, places=6)

    def test_dead_resolution_projection_and_neutral_resolution_have_distinct_contracts(self):
        fragment = """
            uniform sampler2D g_Texture0;
            uniform sampler2D g_Texture1;
            varying vec4 v_Coordinates;
            void main() { gl_FragColor = texSample2D(g_Texture0, v_Coordinates.xy); }
        """
        vertex = """
            uniform vec4 g_Texture1Resolution;
            attribute vec3 a_Position;
            attribute vec2 a_TexCoord;
            varying vec4 v_Coordinates;
            void main() {
                gl_Position = vec4(a_Position, 1.0);
                v_Coordinates.xy = a_TexCoord;
                v_Coordinates.zw = EXPRESSION;
            }
        """
        for slot, varying in ((1, 'v_Coordinates'), (3, 'v_AuthorUV')):
            for expression, retained in (
                ('vec2(g_Texture1Resolution.x / g_Texture1Resolution.y, '
                 'g_Texture1Resolution.z / g_Texture1Resolution.w)', False),
                ('vec2(v_Coordinates.x * g_Texture1Resolution.z / g_Texture1Resolution.x, '
                 'v_Coordinates.y * g_Texture1Resolution.w / g_Texture1Resolution.y)', True),
            ):
                with self.subTest(slot=slot, retained=retained):
                    resolution = f'g_Texture{slot}Resolution'
                    def renamed(source):
                        return source.replace('g_Texture1', f'g_Texture{slot}').replace('v_Coordinates', varying)
                    output = self.compile(renamed(vertex.replace('EXPRESSION', expression)), renamed(fragment))
                    self.assertEqual(output['diagnosticCodes'], [])
                    self.assertEqual(output['textureSlots'], [0])
                    self.assertEqual(output['schemaSamplerSlots'], [0])
                    self.assertEqual(resolution in output['uniformNames'], retained)
                    self.assertEqual(resolution in output['metalSource'], retained)
                    self.assertIsNone(output.get('metalError'))


if __name__ == '__main__':
    unittest.main()

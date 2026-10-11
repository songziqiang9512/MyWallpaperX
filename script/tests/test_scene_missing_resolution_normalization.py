#!/usr/bin/env python3
"""Missing-resolution proof through shared production syntax and compiler paths."""
import unittest
from script.tests import test_scene_shader_dead_binding_projection as support

VERTEX = '''uniform vec4 g_Texture1Resolution;
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_Coordinates;
void main() {
 v_Coordinates.xy = a_TexCoord.xy;
 v_Coordinates.zw = vec2(a_TexCoord.x * g_Texture1Resolution.z / g_Texture1Resolution.x,
                         a_TexCoord.y * g_Texture1Resolution.w / g_Texture1Resolution.y);
 gl_Position = vec4(a_Position, 1.0);
}
'''
FRAGMENT = '''uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
varying vec4 v_Coordinates;
float warp(vec2 p) {
 float value = 0.0;
 for (float i = 0.0; i < p.x; i++) { value += p.y; }
 return value;
}
void main() {
 float value = warp(v_Coordinates.zw) + v_Coordinates.w;
 gl_FragColor = texSample2D(g_Texture0, v_Coordinates.xy) * value;
}
'''


class MissingResolutionNormalizationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        support.SceneShaderDeadBindingProjectionTests.setUpClass()
        cls.addClassCleanup(support.SceneShaderDeadBindingProjectionTests.doClassCleanups)
        cls.probe = support.SceneShaderDeadBindingProjectionTests()

    def assert_fact(self, vertex=VERTEX, fragment=FRAGMENT, slot=1, active=(0,)):
        result = self.probe.compile(vertex, fragment, metadata={
            "neutralProofOnly": True, "activeSlots": list(active)})
        self.assertEqual(result, {"sourceSlot": slot, "unitSlot": slot})

    def test_direct_attribute_and_generic_fragment_share_one_proof(self):
        self.assert_fact()
        self.assert_fact(VERTEX.replace("Texture1", "Texture5"),
                         FRAGMENT.replace("Texture1", "Texture5"), slot=5)
        self.assert_fact(fragment=FRAGMENT.replace("uniform sampler2D g_Texture1;\n", ""))
        self.assert_fact(VERTEX.replace("\n", "\r\n"), FRAGMENT.replace("\n", "\r\n"))

    def test_actual_defaults_and_incomplete_annotation_coverage_keep_resource_path(self):
        for declaration in (
            'uniform sampler2D g_Texture1; // {"default":"util/white"}',
            'uniform sampler2D g_Texture1; // {"default":"_rt_Composite"}',
            'uniform sampler2D g_Texture1; // {"default":null}',
            'uniform sampler2D g_Texture1; // {"default":',
            'uniform float unused; uniform sampler2D g_Texture1; // {"default":"util/white"}',
            'uniform\nsampler2D g_Texture1; // {"default":"util/white"}',
        ):
            with self.subTest(declaration=declaration):
                self.assert_fact(fragment=FRAGMENT.replace(
                    "uniform sampler2D g_Texture1;", declaration), slot=-1)
        self.assert_fact(fragment=FRAGMENT.replace(
            "uniform sampler2D g_Texture0;",
            'uniform sampler2D g_Texture0; // {"default":"util/white"}'))

    def test_unsafe_resolution_reads_and_shadowed_sources_are_not_normalization(self):
        variants = [
            VERTEX.replace("/ g_Texture1Resolution.x", "/ (g_Texture1Resolution.x + 1.0)"),
            VERTEX.replace("g_Texture1Resolution.z", "g_Texture1Resolution.y"),
            VERTEX.replace("gl_Position =", "float extra = g_Texture1Resolution.x; gl_Position ="),
            VERTEX.replace("void main() {", "void main() { vec2 a_TexCoord = vec2(1.0);"),
            VERTEX.replace("uniform vec4", "uniform vec3"),
            VERTEX.replace("Resolution;", "Resolution[1];"),
            VERTEX.replace("v_Coordinates.zw =", "if (a_TexCoord.x > 0.5) { v_Coordinates.zw =")
                  .replace("gl_Position =", "} gl_Position ="),
        ]
        for vertex in variants:
            with self.subTest(vertex=vertex):
                self.assert_fact(vertex=vertex, slot=-1)
        self.assert_fact(fragment="uniform vec4 g_Texture1Resolution;\n" + FRAGMENT.replace(
            "float value = warp", "float extra = g_Texture1Resolution.x; float value = warp"), slot=-1)
        self.assert_fact(active=(0, 1), slot=-1)

    def test_generic_artifact_omits_only_the_missing_resolution_dependency(self):
        # Keep the same helper/loop declaration, but use a simple output whose
        # transfer proof is independent of this uniform-binding regression.
        fragment = FRAGMENT.replace(" * value;", ";")
        result = self.probe.compile(VERTEX, fragment)
        self.assertEqual(result.get("genericSlots"), [0], result)
        self.assertIn("g_Texture1Resolution", result["genericUniforms"])
        self.assertEqual(result["genericMetalError"], "")
        bound = fragment.replace("uniform sampler2D g_Texture1;",
            'uniform sampler2D g_Texture1; // {"default":"util/white"}')
        result = self.probe.compile(VERTEX, bound)
        self.assertEqual(result.get("genericSlots"), [0, 1], result)
        self.assertEqual(result["genericMetalError"], "")

    def test_explicit_bound_resolution_keeps_both_backends_and_cache_identity(self):
        fragment = """uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
varying vec4 v_Coordinates;
void main() { gl_FragColor = texSample2D(g_Texture0, v_Coordinates.zw); }
"""
        results = [self.probe.compile(VERTEX, fragment, metadata={
            "boundTextureSlots": slots}) for slots in ([], [0, 1], [])]
        for index, expected in enumerate(([0], [0, 1], [0])):
            with self.subTest(index=index):
                for backend in ("bounded", "generic"):
                    self.assertEqual(results[index][backend + "Slots"], expected)
                    self.assertEqual(results[index][backend + "MetalError"], "")
        self.assertEqual(results[0]["requestKey"], results[2]["requestKey"])
        self.assertNotEqual(results[0]["requestKey"], results[1]["requestKey"])


if __name__ == "__main__":
    unittest.main()

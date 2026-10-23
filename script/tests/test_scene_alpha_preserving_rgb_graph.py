#!/usr/bin/env python3

"""Closed RGB-DAG purpose facts keep the original sampled alpha independent."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
from scene_swift_source_sets import scene_swift_sources  # noqa: E402

HARNESS = r'''
import Foundation

private let vertex = """
attribute vec3 a_Position;
attribute vec2 a_TexCoord;
varying vec4 v_UV;
void main() {
    gl_Position = vec4(a_Position, 1.0);
    v_UV = vec4(a_TexCoord, a_TexCoord);
}
"""

private let two = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform float u_Opacity;
varying vec4 v_UV;
void main() {
    vec4 source = texSample2D(g_Texture0, v_UV.xy);
    vec4 overlay = texSample2D(g_Texture1, v_UV.zw);
    float weight = overlay.a * u_Opacity;
    source.rgb = mix(source.rgb, overlay.rgb, weight);
    gl_FragColor = source;
}
"""

private let three = two
    .replacingOccurrences(of: "uniform float u_Opacity;", with: "uniform sampler2D g_Texture3;\nuniform float u_Opacity;")
    .replacingOccurrences(of: "    float weight =", with: "    vec4 backdrop = texSample2D(g_Texture3, v_UV.xy);\n    source.rgb = mix(backdrop.rgb, source.rgb, source.a);\n    float weight =")

private let helper = """
vec3 TintJoin(int mode, vec3 under, vec3 over, float coverage) {
    return mix(under, over, coverage);
}
"""

private func withHelper(_ source: String) -> String {
    helper + source.replacingOccurrences(of: "mix(source.rgb, overlay.rgb, weight)", with: "TintJoin(0, source.rgb, overlay.rgb, weight)")
}

private func fact(_ fragment: String, vertex vertexSource: String = vertex, fragmentOnly: Bool = false) -> [String: Any] {
    guard let syntax = SceneAuthoredShaderSyntaxAnalyzer.validatedStages(
        vertexSource: vertexSource, fragmentSource: fragment
    ) else { return ["accepted": false] }
    let result = fragmentOnly
        ? SceneAuthoredShaderColorMixGraphAnalyzer.alphaPreservingRGBGraph(fragment: syntax.fragment)
        : SceneAuthoredShaderColorMixGraphAnalyzer.alphaPreservingRGBGraph(vertex: syntax.vertex, fragment: syntax.fragment)
    guard let value = result else { return ["accepted": false] }
    return [
        "accepted": true,
        "slots": value.colorSampleSlots.sorted(),
        "alpha": value.alphaCarrierSlot,
        "full": Dictionary(uniqueKeysWithValues: value.fullColorSampleCallCounts.map { (String($0.key), $0.value) }),
        "rgb": Dictionary(uniqueKeysWithValues: value.rgbSampleCallCounts.map { (String($0.key), $0.value) }),
    ]
}

@main
private enum Main {
    static func main() throws {
        let renamed = withHelper(three)
            .replacingOccurrences(of: "source", with: "canvas")
            .replacingOccurrences(of: "overlay", with: "picture")
            .replacingOccurrences(of: "backdrop", with: "behind")
            .replacingOccurrences(of: "weight", with: "amount")
            .replacingOccurrences(of: "TintJoin", with: "AnotherBlend")
            .replacingOccurrences(of: "g_Texture0", with: "g_Texture4")
            .replacingOccurrences(of: "g_Texture1", with: "g_Texture6")
            .replacingOccurrences(of: "g_Texture3", with: "g_Texture7")
        let rgbSample = two
            .replacingOccurrences(of: "vec4 overlay = texSample2D(g_Texture1, v_UV.zw);", with: "vec3 overlay = texSample2D(g_Texture1, v_UV.zw).rgb;")
            .replacingOccurrences(of: "overlay.a * u_Opacity", with: "u_Opacity")
            .replacingOccurrences(of: "overlay.rgb", with: "overlay")
        let aliases = two
            .replacingOccurrences(of: "vec4 source =", with: "vec4 original =")
            .replacingOccurrences(of: "    float weight =", with: "    vec4 source = original;\n    vec3 colored = overlay.rgb;\n    float weight =")
            .replacingOccurrences(of: "mix(source.rgb, overlay.rgb, weight)", with: "mix(source.rgb, colored, weight)")
            .replacingOccurrences(of: "gl_FragColor = source;", with: "vec3 result = source.rgb;\n    float retained = source.a;\n    gl_FragColor = vec4(result, retained);")
        let coordinateCoverage = three
            .replacingOccurrences(of: "    float weight = overlay.a * u_Opacity;", with: "    vec2 inBounds = step(vec2(0.0, 0.0), v_UV.zw);\n    float weight = overlay.a * u_Opacity * inBounds.x * inBounds.y;\n    weight *= 0.75;")
        let insert = "    gl_FragColor = source;"
        let mutations: [String: String] = [
            "alphaWrite": two.replacingOccurrences(of: insert, with: "    source.a = overlay.a;\n" + insert),
            "alphaArithmetic": two.replacingOccurrences(of: insert, with: "    gl_FragColor = vec4(source.rgb, source.a * 1.0);"),
            "rgbaMix": two.replacingOccurrences(of: "source.rgb = mix(source.rgb, overlay.rgb, weight);", with: "source = mix(source, overlay, weight);"),
            "rgbAsUV": two.replacingOccurrences(of: "v_UV.zw);", with: "source.rg);"),
            "rgbAliasAsUV": two.replacingOccurrences(of: "    vec4 overlay =", with: "    vec2 moved = source.rg;\n    vec4 overlay =").replacingOccurrences(of: "v_UV.zw);", with: "moved);"),
            "rgbAsData": two.replacingOccurrences(of: "overlay.a * u_Opacity", with: "overlay.r * u_Opacity"),
            "alphaAsUV": two.replacingOccurrences(of: "v_UV.zw);", with: "vec2(source.a, source.a));"),
            "extraRGBRead": two.replacingOccurrences(of: insert, with: "    vec3 unused = overlay.rgb;\n" + insert),
            "extraAlphaRead": two.replacingOccurrences(of: insert, with: "    float unused = overlay.a;\n" + insert),
            "extraCoverageUse": two.replacingOccurrences(of: insert, with: "    vec2 unused = vec2(weight, weight);\n" + insert),
            "extraSample": two.replacingOccurrences(of: insert, with: "    vec4 unused = texSample2D(g_Texture1, v_UV.xy);\n" + insert),
            "alphaOnlySample": two.replacingOccurrences(of: "overlay.a * u_Opacity", with: "texSample2D(g_Texture1, v_UV.xy).a * u_Opacity"),
            "helperEscape": "vec3 Other(vec3 x) { return x; }\n" + two.replacingOccurrences(of: insert, with: "    vec3 unused = Other(overlay.rgb);\n" + insert),
            "helperInout": withHelper(two).replacingOccurrences(of: "vec3 under", with: "inout vec3 under"),
            "helperWrongMath": withHelper(two).replacingOccurrences(of: "return mix(under, over, coverage);", with: "return under + over * coverage;"),
            "helperExtraRead": withHelper(two).replacingOccurrences(of: "return mix(under, over, coverage);", with: "vec3 unused = texSample2D(g_Texture1, v_UV.xy).rgb; return mix(under, over, coverage);"),
            "helperNameOnly": two.replacingOccurrences(of: "mix(source.rgb, overlay.rgb, weight)", with: "ApplyBlending(0, source.rgb, overlay.rgb, weight)"),
            "shadowedMix": "vec3 mix(vec3 a, vec3 b, float x) { return a; }\n" + two,
            "shadowedScalar": "float saturate(float a) { return a; }\n" + two.replacingOccurrences(of: "overlay.a * u_Opacity", with: "saturate(overlay.a)"),
            "conditionalWrite": two.replacingOccurrences(of: "    source.rgb =", with: "    if (u_Opacity > 0.0) source.rgb ="),
            "divisionByZero": two.replacingOccurrences(of: "overlay.a * u_Opacity", with: "overlay.a / 0.0"),
            "nonFiniteLiteral": two.replacingOccurrences(of: "overlay.a * u_Opacity", with: "1e999"),
            "unsupportedSwizzle": two.replacingOccurrences(of: "overlay.rgb, weight", with: "overlay.bgr, weight"),
            "wholeAssignment": two.replacingOccurrences(of: insert, with: "    source = overlay;\n" + insert),
            "unusedColorAlphaOnly": two.replacingOccurrences(of: "mix(source.rgb, overlay.rgb, weight)", with: "mix(source.rgb, source.rgb, weight)"),
        ]
        var results: [String: Any] = [
            "two": fact(two), "three": fact(three), "helper": fact(withHelper(three)),
            "renamed": fact(renamed), "lerp": fact(three.replacingOccurrences(of: "mix(", with: "lerp(")),
            "helperLerp": fact(withHelper(three).replacingOccurrences(of: "return mix(", with: "return lerp(")),
            "rgbSample": fact(rgbSample), "aliases": fact(aliases), "coordinateCoverage": fact(coordinateCoverage),
            "memberNamedLocal": fact(two.replacingOccurrences(of: "source", with: "rgb")),
        ]
        var rejected = mutations.mapValues { source in fact(source)["accepted"] as? Bool == false }
        // Keep the source after the output inside main, rather than appending
        // a different function or relying on source text shape assertions.
        rejected["lateMutation"] = fact(two.replacingOccurrences(of: insert, with: insert + "\n    source.rgb = overlay.rgb;"))["accepted"] as? Bool == false
        let sampledVertex = vertex.replacingOccurrences(of: "attribute vec3", with: "uniform sampler2D g_Texture0;\nattribute vec3")
            .replacingOccurrences(of: "vec4(a_Position, 1.0)", with: "texSample2D(g_Texture0, a_TexCoord)")
        rejected["vertexSample"] = fact(two, vertex: sampledVertex)["accepted"] as? Bool == false
        results["fragmentOnlyWithVertexSample"] = fact(two, vertex: sampledVertex, fragmentOnly: true)
        results["rejected"] = rejected
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''


class AlphaPreservingRGBGraphTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-rgb-graph-")
        root = Path(cls.temp.name)
        harness = root / "main.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "harness"
        environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(root / "module-cache"))
        compilation = subprocess.run(
            [swiftc, "-Onone", "-whole-module-optimization", "-num-threads", "2", "-parse-as-library",
             "-module-cache-path", str(root / "module-cache"), "-o", str(binary),
             *map(str, scene_swift_sources("authored_shader_frontend_core")), str(harness)],
            text=True, capture_output=True, env=environment, timeout=180,
        )
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        execution = subprocess.run([str(binary)], text=True, capture_output=True, timeout=30)
        if execution.returncode != 0:
            raise RuntimeError(execution.stderr)
        cls.result = json.loads(execution.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temp"):
            cls.temp.cleanup()

    def test_two_and_three_inputs_keep_original_alpha(self) -> None:
        for name, slots in (("two", [0, 1]), ("three", [0, 1, 3]), ("helper", [0, 1, 3])):
            with self.subTest(name=name):
                self.assertEqual(self.result[name], {
                    "accepted": True, "alpha": 0, "slots": slots,
                    "full": {str(slot): 1 for slot in slots}, "rgb": {},
                })

    def test_names_and_equivalent_mix_spelling_do_not_select_fact(self) -> None:
        self.assertEqual(self.result["renamed"], {
            "accepted": True, "alpha": 4, "slots": [4, 6, 7],
            "full": {"4": 1, "6": 1, "7": 1}, "rgb": {},
        })
        for name in ("lerp", "helperLerp", "coordinateCoverage"):
            with self.subTest(name=name):
                self.assertEqual(self.result[name], self.result["three"])

    def test_rgb_samples_and_reaching_aliases_have_exact_call_counts(self) -> None:
        self.assertEqual(self.result["rgbSample"], {
            "accepted": True, "alpha": 0, "slots": [0, 1],
            "full": {"0": 1}, "rgb": {"1": 1},
        })
        for name in ("aliases", "memberNamedLocal"):
            with self.subTest(name=name):
                self.assertEqual(self.result[name], self.result["two"])

    def test_output_fact_shares_fragment_owner_without_granting_vertex_purpose(self) -> None:
        self.assertEqual(self.result["fragmentOnlyWithVertexSample"], self.result["two"])
        self.assertTrue(self.result["rejected"]["vertexSample"])

    def test_extra_reads_data_escapes_alpha_changes_and_unproven_helpers_reject(self) -> None:
        for name, rejected in self.result["rejected"].items():
            with self.subTest(name=name):
                self.assertTrue(rejected)


if __name__ == "__main__":
    unittest.main()

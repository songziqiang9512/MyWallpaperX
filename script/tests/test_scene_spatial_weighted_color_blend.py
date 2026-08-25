#!/usr/bin/env python3

"""Identity-free source proof for spatially weighted graph color blending."""

from __future__ import annotations

import json
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

private let unmasked = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture1;
uniform sampler2D g_Texture2;
uniform float u_Multiply;
varying vec4 v_TexCoord;
varying vec4 v_PointerUV;
varying float v_PointerScale;
void main() {
    vec4 base = texSample2D(g_Texture0, v_TexCoord.xy);
    vec4 replacement = texSample2D(g_Texture1, v_TexCoord.zw);
    float weight = replacement.a * u_Multiply;
    vec2 point = v_PointerUV.xy / v_PointerUV.z;
    point -= v_TexCoord.xy;
    point = saturate(point);
    point *= v_PointerScale;
    vec2 falloff = texSample2D(g_Texture2, point).ra;
    weight *= falloff.x * falloff.y;
    base.rgb = ApplyBlending(0, base.rgb, replacement.rgb, weight);
    gl_FragColor = base;
}
"""

private let masked = unmasked
    .replacingOccurrences(
        of: "uniform float u_Multiply;",
        with: "uniform sampler2D g_Texture3;\nuniform float u_Multiply;"
    )
    .replacingOccurrences(
        of: "    vec2 point =",
        with: "    weight *= texSample2D(g_Texture3, v_TexCoord.xy).r;\n    vec2 point ="
    )

private let symbolicMode = unmasked.replacingOccurrences(
    of: "ApplyBlending(0",
    with: "ApplyBlending(AUTHORED_BLEND_MODE"
)

private func fact(_ source: String) -> [String: Any] {
    guard let value = SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer
            .analyze(fragmentSource: source) else { return ["accepted": false] }
    let transfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
        fragmentSource: source
    )
    let transferAccepted: Bool
    if case .straightAlphaPreserving(textureSlot: value.sourceSlot) = transfer {
        transferAccepted = true
    } else {
        transferAccepted = false
    }
    return [
        "accepted": true,
        "source": value.sourceSlot,
        "color": value.straightColorSlot,
        "preserved": value.preservedRedAlphaSlot,
        "mask": value.optionalMaskSlot as Any,
        "slots": value.activeSlots.sorted(),
        "transfer": transferAccepted,
    ]
}

@main
private enum Main {
    static func main() throws {
        let renamed = unmasked
            .replacingOccurrences(of: "base", with: "carrier")
            .replacingOccurrences(of: "replacement", with: "overlay")
            .replacingOccurrences(of: "weight", with: "amount")
            .replacingOccurrences(of: "falloff", with: "profile")
        let mutations = [
            "wrongProjection": unmasked.replacingOccurrences(of: ").ra", with: ").rg"),
            "wrongMode": unmasked.replacingOccurrences(of: "ApplyBlending(0", with: "ApplyBlending(1"),
            "alphaWrite": unmasked.replacingOccurrences(
                of: "    gl_FragColor = base;",
                with: "    base.a = 1.0;\n    gl_FragColor = base;"
            ),
            "compoundAlphaWrite": unmasked.replacingOccurrences(
                of: "    base.rgb = ApplyBlending",
                with: "    base.a *= 0.5;\n    base.rgb = ApplyBlending"
            ),
            "incrementAlphaWrite": unmasked.replacingOccurrences(
                of: "    base.rgb = ApplyBlending",
                with: "    base.a++;\n    base.rgb = ApplyBlending"
            ),
            "inoutAlphaEscape": unmasked
                .replacingOccurrences(
                    of: "void main() {",
                    with: "void mutate(inout vec4 value) { value.a *= 0.5; }\nvoid main() {"
                )
                .replacingOccurrences(
                    of: "    base.rgb = ApplyBlending",
                    with: "    mutate(base);\n    base.rgb = ApplyBlending"
                ),
            "hiddenSample": unmasked.replacingOccurrences(
                of: "    gl_FragColor = base;",
                with: "    weight *= texSample2D(g_Texture3, v_TexCoord.xy).g;\n    gl_FragColor = base;"
            ),
        ]
        let output: [String: Any] = [
            "unmasked": fact(unmasked),
            "masked": fact(masked),
            "renamed": fact(renamed),
            "symbolicModeAccepted":
                SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer.analyze(
                    fragmentSource: symbolicMode,
                    normalBlendModeIdentifiers: ["AUTHORED_BLEND_MODE"]
                ) != nil,
            "symbolicModeUnprovenRejected":
                SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer.analyze(
                    fragmentSource: symbolicMode
                ) == nil,
            "mutationsRejected": mutations.mapValues {
                SceneAuthoredShaderSpatialWeightedColorBlendAnalyzer
                    .analyze(fragmentSource: $0) == nil
            },
        ]
        print(String(data: try JSONSerialization.data(
            withJSONObject: output, options: [.sortedKeys]
        ), encoding: .utf8)!)
    }
}
'''


class SceneSpatialWeightedColorBlendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.temp = tempfile.TemporaryDirectory(prefix="mwx-spatial-color-blend-")
        root = Path(cls.temp.name)
        harness = root / "main.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        binary = root / "harness"
        command = [
            swiftc,
            "-O",
            "-parse-as-library",
            "-o",
            str(binary),
            *map(str, scene_swift_sources("authored_shader_frontend_core")),
            str(harness),
        ]
        compilation = subprocess.run(command, text=True, capture_output=True)
        if compilation.returncode != 0:
            raise RuntimeError(compilation.stderr)
        execution = subprocess.run([str(binary)], text=True, capture_output=True)
        if execution.returncode != 0:
            raise RuntimeError(execution.stderr)
        cls.result = json.loads(execution.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        if hasattr(cls, "temp"):
            cls.temp.cleanup()

    def test_unmasked_and_optional_mask_roles_are_proven(self) -> None:
        self.assertEqual(
            self.result["unmasked"],
            {
                "accepted": True,
                "color": 1,
                "mask": None,
                "preserved": 2,
                "slots": [0, 1, 2],
                "source": 0,
                "transfer": True,
            },
        )
        self.assertEqual(self.result["masked"]["mask"], 3)
        self.assertEqual(self.result["masked"]["slots"], [0, 1, 2, 3])
        self.assertTrue(self.result["masked"]["transfer"])

    def test_names_do_not_select_the_profile(self) -> None:
        self.assertTrue(self.result["renamed"]["accepted"])
        self.assertTrue(self.result["renamed"]["transfer"])

    def test_resolved_zero_combo_can_prove_symbolic_normal_mode(self) -> None:
        self.assertTrue(self.result["symbolicModeAccepted"])
        self.assertTrue(self.result["symbolicModeUnprovenRejected"])

    def test_semantic_drift_fails_closed(self) -> None:
        self.assertTrue(all(self.result["mutationsRejected"].values()))


if __name__ == "__main__":
    unittest.main()

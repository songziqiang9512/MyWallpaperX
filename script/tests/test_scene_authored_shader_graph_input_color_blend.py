#!/usr/bin/env python3
"""Graph-input color-blend facts are strict and identity-free."""

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

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = scene_swift_sources("authored_shader_frontend_core")
FIXTURE_ROOT = Path(__file__).parent / "fixtures/scene_color_blend"

HARNESS = r'''
import Foundation

private struct FactOutput: Codable {
    let sourceSlot: Int
    let auxiliaryRedSlots: [Int]
    let alphaOutput: String
}

@main
private enum Harness {
    static func main() throws {
        let authoredStock = try String(
            contentsOfFile: CommandLine.arguments[1],
            encoding: .utf8
        )
        let authoredLegacyMaskOverride = try String(
            contentsOfFile: CommandLine.arguments[2],
            encoding: .utf8
        )
        let cases: [String: String] = [
            "authoredStock": preparedAuthored(
                authoredStock,
                maskEnabled: true,
                modeZero: false
            ),
            "authoredLegacyMaskOverride": preparedAuthored(
                authoredLegacyMaskOverride,
                maskEnabled: true,
                modeZero: false
            ),
            "authoredStockModeZero": preparedAuthored(
                authoredStock,
                maskEnabled: false,
                modeZero: true
            ),
            "static": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float weight = g_Opacity;",
                "carrier.rgb = ApplyBlending(30, carrier.rgb, g_Color, weight);",
                "gl_FragColor = carrier;",
            ]),
            "maskMultiply": fragment(
                extraDeclarations: ["uniform sampler2D g_Texture1;"],
                body: [
                    "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                    "float weight = g_Opacity;",
                    "weight *= texSample2D(g_Texture1, v_TexCoord.zw).r;",
                    "carrier.rgb = ApplyBlending(12, carrier.rgb, g_Color, weight);",
                    "gl_FragColor = carrier;",
                ]
            ),
            "maskOverride": fragment(
                sourceSlot: 2,
                extraDeclarations: ["uniform sampler2D g_Texture5;"],
                body: [
                    "vec4 surface = texSample2D(g_Texture2, v_TexCoord.xy);",
                    "float gate = g_Opacity;",
                    "gate = texSample2D(g_Texture5, v_TexCoord.zw).r;",
                    "surface.rgb = ApplyBlending(18, surface.rgb, g_Color, gate);",
                    "gl_FragColor = surface;",
                ]
            ),
            "opaque": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float weight = g_Opacity;",
                "carrier.rgb = ApplyBlending(0, carrier.rgb, g_Color, weight);",
                "carrier.a = 1.0;",
                "gl_FragColor = carrier;",
            ]),
            "conditional": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float weight = g_Opacity;",
                "if (weight > 0.0) { carrier.rgb = g_Color; }",
                "gl_FragColor = carrier;",
            ]),
            "wrongBase": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float weight = g_Opacity;",
                "carrier.rgb = ApplyBlending(30, g_Color, carrier.rgb, weight);",
                "gl_FragColor = carrier;",
            ]),
            "nonUniformColor": fragment(
                colorDeclaration: "vec3 g_Color = vec3(1.0);",
                body: [
                    "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                    "float weight = g_Opacity;",
                    "carrier.rgb = ApplyBlending(30, carrier.rgb, g_Color, weight);",
                    "gl_FragColor = carrier;",
                ]
            ),
            "greenMask": fragment(
                extraDeclarations: ["uniform sampler2D g_Texture1;"],
                body: [
                    "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                    "float weight = g_Opacity;",
                    "weight *= texSample2D(g_Texture1, v_TexCoord.zw).g;",
                    "carrier.rgb = ApplyBlending(30, carrier.rgb, g_Color, weight);",
                    "gl_FragColor = carrier;",
                ]
            ),
            "twoMasks": fragment(
                extraDeclarations: [
                    "uniform sampler2D g_Texture1;",
                    "uniform sampler2D g_Texture2;",
                ],
                body: [
                    "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                    "float weight = texSample2D(g_Texture1, v_TexCoord.zw).r * texSample2D(g_Texture2, v_TexCoord.zw).r;",
                    "carrier.rgb = ApplyBlending(30, carrier.rgb, g_Color, weight);",
                    "gl_FragColor = carrier;",
                ]
            ),
            "opaqueMismatch": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float weight = g_Opacity;",
                "carrier.rgb = ApplyBlending(30, carrier.rgb, g_Color, weight);",
                "carrier.a = 1.0;",
                "gl_FragColor = carrier;",
            ]),
            "modeZeroPreservesAlpha": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float weight = g_Opacity;",
                "carrier.rgb = ApplyBlending(0, carrier.rgb, g_Color, weight);",
                "gl_FragColor = carrier;",
            ]),
            "sourceResampled": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float weight = texSample2D(g_Texture0, v_TexCoord.zw).r;",
                "carrier.rgb = ApplyBlending(30, carrier.rgb, g_Color, weight);",
                "gl_FragColor = carrier;",
            ]),
            "negativeMode": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float weight = g_Opacity;",
                "carrier.rgb = ApplyBlending(-1, carrier.rgb, g_Color, weight);",
                "gl_FragColor = carrier;",
            ]),
            "aboveMaximumMode": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float weight = g_Opacity;",
                "carrier.rgb = ApplyBlending(33, carrier.rgb, g_Color, weight);",
                "gl_FragColor = carrier;",
            ]),
        ]
        let result = cases.mapValues { source -> FactOutput? in
            guard let fact = SceneAuthoredShaderGraphInputColorBlendAnalyzer.analyze(
                fragmentSource: source
            ) else { return nil }
            return .init(
                sourceSlot: fact.sourceSlot,
                auxiliaryRedSlots: fact.auxiliaryRedSlots.sorted(),
                alphaOutput: fact.alphaOutput == .preserved ? "preserved" : "opaque"
            )
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    }

    private static func preparedAuthored(
        _ source: String,
        maskEnabled: Bool,
        modeZero: Bool
    ) -> String {
        var active = true
        var result: [String] = []
        for line in source.components(separatedBy: .newlines) {
            let directive = line.trimmingCharacters(in: .whitespaces)
            if directive == "#if MASK" {
                active = maskEnabled
            } else if directive == "#if BLENDMODE == 0" {
                active = modeZero
            } else if directive == "#endif" {
                active = true
            } else if directive.hasPrefix("#include") {
                continue
            } else if active {
                result.append(line.replacingOccurrences(
                    of: "BLENDMODE",
                    with: modeZero ? "0" : "30"
                ))
            }
        }
        return result.joined(separator: "\n")
    }

    private static func fragment(
        sourceSlot: Int = 0,
        colorDeclaration: String = "uniform vec3 g_Color;",
        extraDeclarations: [String] = [],
        body: [String]
    ) -> String {
        ([
            "varying vec4 v_TexCoord;",
            "uniform sampler2D g_Texture\(sourceSlot);",
            "uniform float g_Opacity;",
            colorDeclaration,
        ] + extraDeclarations + [
            "vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {",
            "    return mix(base, blend, opacity);",
            "}",
            "void main() {",
        ] + body.map { "    \($0)" } + ["}"]).joined(separator: "\n")
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneAuthoredShaderGraphInputColorBlendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(prefix="mwx-color-blend-fact-")
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        cls.binary = root / "color-blend-fact-test"
        harness.write_text(HARNESS, encoding="utf-8")
        completed = subprocess.run(
            [
                "xcrun", "--sdk", "macosx", "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness), "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def result(self) -> dict[str, object]:
        completed = subprocess.run(
            [
                str(self.binary),
                str(FIXTURE_ROOT / "stock.frag"),
                str(FIXTURE_ROOT / "legacy-mask-override.frag"),
            ],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def test_identity_free_stock_legacy_and_opaque_facts(self) -> None:
        result = self.result()
        self.assertEqual(
            result["static"],
            {"sourceSlot": 0, "auxiliaryRedSlots": [], "alphaOutput": "preserved"},
        )
        self.assertEqual(
            result["maskMultiply"],
            {"sourceSlot": 0, "auxiliaryRedSlots": [1], "alphaOutput": "preserved"},
        )
        self.assertEqual(
            result["maskOverride"],
            {"sourceSlot": 2, "auxiliaryRedSlots": [5], "alphaOutput": "preserved"},
        )
        self.assertEqual(
            result["opaque"],
            {"sourceSlot": 0, "auxiliaryRedSlots": [], "alphaOutput": "opaque"},
        )
        self.assertEqual(
            result["authoredStock"],
            {"sourceSlot": 0, "auxiliaryRedSlots": [1], "alphaOutput": "preserved"},
        )
        self.assertEqual(
            result["authoredLegacyMaskOverride"],
            {"sourceSlot": 0, "auxiliaryRedSlots": [1], "alphaOutput": "preserved"},
        )
        self.assertEqual(
            result["authoredStockModeZero"],
            {"sourceSlot": 0, "auxiliaryRedSlots": [], "alphaOutput": "opaque"},
        )

    def test_unsafe_or_different_color_flows_are_rejected(self) -> None:
        result = self.result()
        for name in (
            "conditional", "wrongBase", "nonUniformColor", "greenMask",
            "twoMasks", "opaqueMismatch", "modeZeroPreservesAlpha",
            "sourceResampled",
            "negativeMode", "aboveMaximumMode",
        ):
            with self.subTest(name=name):
                self.assertIsNone(result[name])


if __name__ == "__main__":
    unittest.main()

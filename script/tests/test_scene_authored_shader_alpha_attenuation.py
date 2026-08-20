#!/usr/bin/env python3
"""Host-side alpha attenuation facts are strict and identity-free."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "script"))

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = scene_swift_sources("authored_shader_frontend_core")


HARNESS = r'''
import Foundation

private struct FactOutput: Codable {
    let sourceSlot: Int
    let auxiliaryRedSlots: [Int]
}

@main
private enum Harness {
    static func main() throws {
        let cases: [String: String] = [
            "maskOff": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float mask = 1.0;",
                "carrier.a *= mask * g_UserAlpha;",
                "gl_FragColor = carrier;",
            ]),
            "maskOn": fragment(
                extraDeclarations: ["uniform sampler2D g_Texture1;"],
                body: [
                    "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                    "float mask = texSample2D(g_Texture1, v_TexCoord.zw).r;",
                    "carrier.a *= mask * g_UserAlpha;",
                    "gl_FragColor = carrier;",
                ]
            ),
            "unseenNames": fragment(
                sourceSlot: 2,
                alphaUniform: "u_Attenuation",
                extraDeclarations: ["uniform sampler2D g_Texture5;"],
                body: [
                    "vec4 surface = texSample2D(g_Texture2, v_TexCoord.xy);",
                    "float gate = texSample2D(g_Texture5, v_TexCoord.zw).r;",
                    "float weight = gate * u_Attenuation;",
                    "surface.a *= weight;",
                    "gl_FragColor = surface;",
                ]
            ),
            "conditional": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "if (g_UserAlpha > 0.0) { carrier.a *= g_UserAlpha; }",
                "gl_FragColor = carrier;",
            ]),
            "rgbWrite": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "carrier.rgb *= g_UserAlpha;",
                "carrier.a *= g_UserAlpha;",
                "gl_FragColor = carrier;",
            ]),
            "wholeUse": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "vec4 copy = carrier;",
                "carrier.a *= g_UserAlpha;",
                "gl_FragColor = carrier;",
            ]),
            "sourceLocalFactor": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "carrier.a *= carrier.a * g_UserAlpha;",
                "gl_FragColor = carrier;",
            ]),
            "multipleOutput": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "carrier.a *= g_UserAlpha;",
                "gl_FragColor = carrier;",
                "gl_FragColor = carrier;",
            ]),
            "nonRedAuxiliary": fragment(
                extraDeclarations: ["uniform sampler2D g_Texture1;"],
                body: [
                    "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                    "float mask = texSample2D(g_Texture1, v_TexCoord.zw).g;",
                    "carrier.a *= mask * g_UserAlpha;",
                    "gl_FragColor = carrier;",
                ]
            ),
            "unknownHelper": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "carrier.a *= clamp(g_UserAlpha, 0.0, 1.0);",
                "gl_FragColor = carrier;",
            ]),
            "alphaAssignment": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "carrier.a = g_UserAlpha;",
                "gl_FragColor = carrier;",
            ]),
            "sourceResampled": fragment(body: [
                "vec4 carrier = texSample2D(g_Texture0, v_TexCoord.xy);",
                "float mask = texSample2D(g_Texture0, v_TexCoord.zw).r;",
                "carrier.a *= mask * g_UserAlpha;",
                "gl_FragColor = carrier;",
            ]),
        ]
        let output = cases.mapValues { source -> FactOutput? in
            guard let fact = SceneAuthoredShaderAlphaAttenuationAnalyzer.analyze(
                fragmentSource: source
            ) else { return nil }
            return FactOutput(
                sourceSlot: fact.sourceSlot,
                auxiliaryRedSlots: fact.auxiliaryRedSlots.sorted()
            )
        }
        let data = try JSONEncoder().encode(output)
        FileHandle.standardOutput.write(data)
    }

    private static func fragment(
        sourceSlot: Int = 0,
        alphaUniform: String = "g_UserAlpha",
        extraDeclarations: [String] = [],
        body: [String]
    ) -> String {
        ([
            "varying vec4 v_TexCoord;",
            "uniform sampler2D g_Texture\(sourceSlot);",
            "uniform float \(alphaUniform);",
        ] + extraDeclarations + ["void main() {"]
            + body.map { "    \($0)" }
            + ["}"]).joined(separator: "\n")
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneAuthoredShaderAlphaAttenuationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-alpha-attenuation-"
        )
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        cls.binary = root / "alpha-attenuation-test"
        harness.write_text(HARNESS, encoding="utf-8")
        completed = subprocess.run(
            [
                "xcrun",
                "--sdk",
                "macosx",
                "swiftc",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-o",
                str(cls.binary),
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
            [str(self.binary)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def test_identity_free_positive_facts(self) -> None:
        result = self.result()
        self.assertEqual(
            result["maskOff"],
            {"sourceSlot": 0, "auxiliaryRedSlots": []},
        )
        self.assertEqual(
            result["maskOn"],
            {"sourceSlot": 0, "auxiliaryRedSlots": [1]},
        )
        self.assertEqual(
            result["unseenNames"],
            {"sourceSlot": 2, "auxiliaryRedSlots": [5]},
        )

    def test_unsafe_or_non_attenuation_forms_are_rejected(self) -> None:
        result = self.result()
        for name in (
            "conditional",
            "rgbWrite",
            "wholeUse",
            "sourceLocalFactor",
            "multipleOutput",
            "nonRedAuxiliary",
            "unknownHelper",
            "alphaAssignment",
            "sourceResampled",
        ):
            with self.subTest(name=name):
                self.assertIsNone(result[name])


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3

"""Shared straight-color overlay proof for generated scalar signals."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"

import sys

sys.path.insert(0, str(REPOSITORY_ROOT / "script"))
from scene_swift_source_sets import scene_swift_sources  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
]


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let positive: Bool
    let renamedPositive: Bool
    let colorTransfer: Bool
    let secondSampleRejected: Bool
    let sampledFactorRejected: Bool
    let differentFactorRejected: Bool
    let alphaAddRejected: Bool
    let alphaMinRejected: Bool
    let extraOutputRejected: Bool
    let nonUniformColorRejected: Bool
    let shadowedMixRejected: Bool
    let hiddenHelperSampleRejected: Bool
    let artifactAccepted: Bool
    let inputBoundaryInserted: Bool
    let outputBoundaryInserted: Bool
}

private func source(
    slot: Int = 0,
    sourceName: String = "originalColor",
    factorName: String = "effectiveCurveAlpha",
    rgbName: String = "finalColor",
    alphaName: String = "finalAlpha",
    colorName: String = "u_curveColor",
    factor: String = "lineIntensity * u_curveOpacity",
    rgbFactor: String? = nil,
    alphaOperation: String = "max",
    alphaFactor: String? = nil,
    alphaExpression: String? = nil,
    prefix: String = "",
    suffix: String = "",
    helper: String = ""
) -> String {
    let rgbFactor = rgbFactor ?? factorName
    let alphaFactor = alphaFactor ?? factorName
    let alphaExpression = alphaExpression
        ?? "\(alphaOperation)(\(sourceName).a, \(alphaFactor))"
    return """
uniform sampler2D g_Texture\(slot);
uniform vec3 \(colorName);
uniform float u_curveOpacity;
uniform float lineIntensity;
varying vec2 v_TexCoord;
\(helper)
void main() {
    \(prefix)
    vec4 \(sourceName) = texSample2D(g_Texture\(slot), v_TexCoord);
    float \(factorName) = \(factor);
    vec3 \(rgbName) = mix(\(sourceName).rgb, \(colorName), \(rgbFactor));
    float \(alphaName) = \(alphaExpression);
    gl_FragColor = vec4(\(rgbName), \(alphaName));
    \(suffix)
}
"""
}

private func fact(_ source: String) -> Int? {
    SceneAuthoredShaderStraightColorOverlayAnalyzer
        .analyze(fragmentSource: source)?.sourceSlot
}

private func transfer(_ source: String) -> SceneShaderColorTransfer {
    SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: source)
}

private let authored = source()
private let msl = """
#include <metal_stdlib>
using namespace metal;
struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment() {
    Output out = {};
    float lineIntensity = 0.5;
    float u_curveOpacity = 0.8;
    float3 u_curveColor = float3(0.2, 0.8, 1.0);
    float4 originalColor = g_Texture0.sample(g_Texture0Smplr, uv);
    float effectiveCurveAlpha = lineIntensity * u_curveOpacity;
    float3 finalColor = mix(
        originalColor.xyz, u_curveColor, float3(effectiveCurveAlpha)
    );
    float finalAlpha = fast::max(originalColor.w, effectiveCurveAlpha);
    out.mwxFragColor = float4(finalColor, finalAlpha);
    return out;
}
"""

@main
private enum Main {
    static func main() throws {
        let prepared = try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
            msl: msl,
            authoredSource: authored
        )
        let shadowed = """
float3 mix(float3 left, float3 right, float amount) { return right; }
"""
        let hiddenSample = """
vec4 hidden(vec2 coordinate) {
    return texSample2D(g_Texture0, coordinate);
}
"""
        let output = Output(
            positive: fact(authored) == 0,
            renamedPositive: fact(source(
                slot: 5,
                sourceName: "surface",
                factorName: "overlayAmount",
                rgbName: "composedRGB",
                alphaName: "unionAlpha",
                colorName: "tint"
            )) == 5,
            colorTransfer: transfer(authored) == .straightAlpha(textureSlot: 0),
            secondSampleRejected: fact(source(prefix:
                "vec4 hidden = texSample2D(g_Texture0, v_TexCoord * 0.5);"
            )) == nil,
            sampledFactorRejected: fact(source(factor:
                "originalColor.a * u_curveOpacity"
            )) == nil,
            differentFactorRejected: fact(source(
                alphaFactor: "u_curveOpacity"
            )) == nil,
            alphaAddRejected: fact(source(alphaExpression:
                "originalColor.a + effectiveCurveAlpha"
            )) == nil,
            alphaMinRejected: fact(source(alphaOperation: "min")) == nil,
            extraOutputRejected: fact(source(suffix:
                "gl_FragColor.a = 1.0;"
            )) == nil,
            nonUniformColorRejected: fact(source(
                colorName: "localColor",
                prefix: "vec3 localColor = vec3(1.0);"
            )) == nil,
            shadowedMixRejected: fact(source(helper: shadowed)) == nil,
            hiddenHelperSampleRejected: fact(source(helper: hiddenSample)) == nil,
            artifactAccepted: prepared?.transfer.kind == "straight-alpha"
                && prepared?.transfer.slot == 0,
            inputBoundaryInserted: prepared?.msl.contains(
                "mwxGenericUnpremultiply(g_Texture0.sample"
            ) == true,
            outputBoundaryInserted: prepared?.msl.contains(
                "out.mwxFragColor = mwxGenericPremultiply(float4(finalColor, finalAlpha));"
            ) == true
        )
        print(String(
            data: try JSONEncoder().encode(output),
            encoding: .utf8
        )!)
    }
}
'''


class SceneStraightColorOverlayTests(unittest.TestCase):
    def test_source_proof_and_compiler_boundary(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-straight-overlay-") as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            executable = root / "harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compiled = subprocess.run(
                [
                    "xcrun", "swiftc", "-O", "-o", str(executable),
                    *(str(path) for path in SWIFT_SOURCES), str(harness),
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run(
                [str(executable)],
                cwd=REPOSITORY_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            result = json.loads(run.stdout)

        self.assertTrue(result)
        for name, value in result.items():
            self.assertTrue(value, name)


if __name__ == "__main__":
    unittest.main()

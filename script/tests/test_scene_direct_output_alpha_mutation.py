#!/usr/bin/env python3

"""Shared straight-color boundary for direct output alpha attenuation."""

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
    let repeatOffPositive: Bool
    let repeatOnPositive: Bool
    let colorTransfer: Bool
    let pureSampleRemainsPassthrough: Bool
    let wholeReplacementRejected: Bool
    let alphaReplacementRejected: Bool
    let rgbMutationRejected: Bool
    let conditionalMutationRejected: Bool
    let factorReadsOutputRejected: Bool
    let secondSampleRejected: Bool
    let helperSampleRejected: Bool
    let discardRejected: Bool
    let artifactAccepted: Bool
    let inputBoundaryInserted: Bool
    let outputBoundaryInserted: Bool
    let compilerExtraWriteRejected: Bool
    let compilerSecondSampleRejected: Bool
}

private func source(
    slot: Int = 0,
    outputMember: String = "a",
    operation: String = "*=",
    factor: String = "mask",
    beforeOutput: String = "",
    afterOutput: String = "",
    helper: String = ""
) -> String {
    """
uniform sampler2D g_Texture\(slot);
varying vec3 projectedCoordinate;
\(helper)
void main() {
    vec2 coordinate = projectedCoordinate.xy / projectedCoordinate.z;
    float mask = step(0.0, projectedCoordinate.z);
    mask *= step(abs(coordinate.x - 0.5), 0.5);
    \(beforeOutput)
    gl_FragColor = texSample2D(g_Texture\(slot), coordinate);
    gl_FragColor.\(outputMember) \(operation) \(factor);
    \(afterOutput)
}
"""
}

private func fact(_ value: String) -> Int? {
    guard let fact = SceneAuthoredShaderAlphaAttenuationAnalyzer
        .analyze(fragmentSource: value),
          fact.auxiliaryRedSlots.isEmpty else { return nil }
    return fact.sourceSlot
}

private func msl(
    slot: Int = 0,
    beforeReturn: String = ""
) -> String {
    """
#include <metal_stdlib>
using namespace metal;
struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment(
    texture2d<float> g_Texture\(slot) [[texture(0)]],
    sampler g_Texture\(slot)Smplr [[sampler(0)]]
) {
    Output out = {};
    float2 coordinate = float2(0.5);
    float mask = 0.75;
    out.mwxFragColor = g_Texture\(slot).sample(
        g_Texture\(slot)Smplr, coordinate
    );
    out.mwxFragColor.w *= mask;
    \(beforeReturn)
    return out;
}
"""
}

private let authored = source()
private let pureSample = """
uniform sampler2D g_Texture0;
varying vec2 v_TexCoord;
void main() {
    gl_FragColor = texSample2D(g_Texture0, v_TexCoord);
}
"""

@main
private enum Main {
    static func main() throws {
        let prepared = try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
            msl: msl(), authoredSource: authored
        )
        let helper = """
vec4 hidden(vec2 coordinate) {
    return texSample2D(g_Texture0, coordinate);
}
"""
        let output = Output(
            positive: fact(authored) == 0,
            renamedPositive: fact(source(
                slot: 5,
                outputMember: "w",
                factor: "mask * 0.5"
            )) == 5,
            repeatOffPositive: fact(source(beforeOutput: """
                mask *= step(abs(coordinate.x - 0.5), 0.5);
                mask *= step(abs(coordinate.y - 0.5), 0.5);
                """)) == 0,
            repeatOnPositive: fact(source(beforeOutput:
                "coordinate = frac(coordinate);"
            )) == 0,
            colorTransfer:
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: authored
                ) == .straightAlpha(textureSlot: 0),
            pureSampleRemainsPassthrough:
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: pureSample
                ) == .passthrough(textureSlot: 0),
            wholeReplacementRejected: fact(source(afterOutput:
                "gl_FragColor = vec4(1.0);"
            )) == nil,
            alphaReplacementRejected: fact(source(operation: "=")) == nil,
            rgbMutationRejected: fact(source(afterOutput:
                "gl_FragColor.rgb *= vec3(0.5);"
            )) == nil,
            conditionalMutationRejected: fact(source(
                operation: "=",
                factor: "1.0",
                beforeOutput: "if (mask > 0.0) {",
                afterOutput: "}"
            )) == nil,
            factorReadsOutputRejected: fact(source(
                factor: "gl_FragColor.a"
            )) == nil,
            secondSampleRejected: fact(source(beforeOutput:
                "vec4 hidden = texSample2D(g_Texture0, coordinate * 0.5);"
            )) == nil,
            helperSampleRejected: fact(source(helper: helper)) == nil,
            discardRejected: fact(source(beforeOutput:
                "if (mask < 0.0) { discard; }"
            )) == nil,
            artifactAccepted: prepared?.transfer.kind == "straight-alpha"
                && prepared?.transfer.slot == 0,
            inputBoundaryInserted: prepared?.msl.contains(
                "mwxGenericUnpremultiply(g_Texture0.sample"
            ) == true,
            outputBoundaryInserted: prepared?.msl.contains(
                "out.mwxFragColor = mwxGenericPremultiply(out.mwxFragColor);"
            ) == true,
            compilerExtraWriteRejected: (try? SceneGenericShaderArtifactBuilder
                .prepareColorTransfer(
                    msl: msl(beforeReturn: "out.mwxFragColor.x = 0.0;"),
                    authoredSource: authored
                )) == nil,
            compilerSecondSampleRejected: (try? SceneGenericShaderArtifactBuilder
                .prepareColorTransfer(
                    msl: msl(beforeReturn:
                        "float4 hidden = g_Texture0.sample(g_Texture0Smplr, coordinate);"
                    ),
                    authoredSource: authored
                )) == nil
        )
        print(String(
            data: try JSONEncoder().encode(output),
            encoding: .utf8
        )!)
    }
}
'''


class SceneDirectOutputAlphaMutationTests(unittest.TestCase):
    def test_source_proof_and_compiler_boundary(self) -> None:
        with tempfile.TemporaryDirectory(prefix="mwx-direct-alpha-") as directory:
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

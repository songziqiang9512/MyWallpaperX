#!/usr/bin/env python3

"""Generic same-slot carrier-blend color boundary and fail-closed drift."""

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
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
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
    let transfer: String
    let sourceSlot: Int?
    let artifactKind: String?
    let artifactSlot: Int?
    let unpremultipliedSamples: Int
    let premultipliedOutput: Bool
    let wrongSourceSlotRejected: Bool
    let alphaWriteRejected: Bool
    let hiddenSourceSampleRejected: Bool
    let swappedSourceBlendRejected: Bool
    let wrongCompilerSlotRejected: Bool
    let compilerAlphaWriteRejected: Bool
    let hiddenCompilerSampleRejected: Bool
    let swappedCompilerBlendRejected: Bool
    let incompleteCompilerWriteRejected: Bool
}

private let source = """
varying vec2 transitPlane;
uniform sampler2D g_Texture0;
uniform vec2 u_Separation;
uniform float u_Strength;
vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {
    return mix(base, blend, opacity);
}
void main() {
    vec2 displaced = transitPlane + u_Separation;
    vec2 redCoordinate = displaced + vec2(u_Separation.x, 0.0);
    vec2 blueCoordinate = displaced - vec2(0.0, u_Separation.y);
    vec4 parcel = texSample2D(g_Texture0, displaced);
    parcel.r = texSample2D(g_Texture0, redCoordinate).r;
    parcel.b = texSample2D(g_Texture0, blueCoordinate).b;
    parcel.rgb = ApplyBlending(
        0,
        texSample2D(g_Texture0, transitPlane).rgb,
        parcel.rgb,
        u_Strength
    );
    gl_FragColor = parcel;
}
"""

private let msl = """
#include <metal_stdlib>
using namespace metal;
struct FragmentOut { float4 mwxFragColor [[color(0)]]; };
fragment FragmentOut mwxGenericFragment(
    texture2d<float> g_Texture0 [[texture(0)]], sampler s [[sampler(0)]]) {
    FragmentOut out = {};
    float2 displaced = float2(0.4, 0.6);
    float2 redCoordinate = displaced + float2(0.01, 0.0);
    float2 blueCoordinate = displaced - float2(0.0, 0.01);
    float4 parcel = g_Texture0.sample(s, displaced);
    parcel.x = g_Texture0.sample(s, redCoordinate).x;
    parcel.z = g_Texture0.sample(s, blueCoordinate).z;
    float3 originalBase = g_Texture0.sample(s, float2(0.5)).xyz;
    float3 reconstructed = parcel.xyz;
    float opacity = 0.75;
    float3 blended = ApplyBlending(0, originalBase, reconstructed, opacity);
    parcel.x = blended.x;
    parcel.y = blended.y;
    parcel.z = blended.z;
    out.mwxFragColor = parcel;
    return out;
}
"""

private func transferToken(_ source: String) -> String {
    switch SceneAuthoredShaderColorTransferAnalyzer.analyze(
        fragmentSource: source
    ) {
    case let .straightAlphaPreserving(slot): return "straight:\(slot)"
    case let .independentAlphaSignalPreserving(slot): return "signal:\(slot)"
    default: return "unresolved"
    }
}

private func prepared(_ sourceMSL: String, authored: String = source) -> (
    msl: String,
    transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
)? {
    guard let expected = SceneGenericShaderExpectedColorTransfer(
        .straightAlphaPreserving(textureSlot: 0),
        fragmentSource: authored,
        permitsStraightAlphaPreserving: true
    ) else { return nil }
    return try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
        msl: sourceMSL,
        authoredSource: authored,
        expectedColorTransfer: expected
    )
}

@main
private struct Harness {
    static func main() throws {
        let result = prepared(msl)
        let wrongSourceSlot = source.replacingOccurrences(
            of: "parcel.r = texSample2D(g_Texture0, redCoordinate).r;",
            with: "parcel.r = texSample2D(g_Texture1, redCoordinate).r;"
        )
        let alphaWrite = source.replacingOccurrences(
            of: "    parcel.rgb = ApplyBlending(",
            with: "    parcel.a = u_Strength;\n    parcel.rgb = ApplyBlending("
        )
        let hiddenSourceSample = source.replacingOccurrences(
            of: "    gl_FragColor = parcel;",
            with: "    vec4 hidden = texSample2D(g_Texture0, transitPlane);\n    gl_FragColor = parcel;"
        )
        let swappedSourceBlend = source.replacingOccurrences(
            of: "        texSample2D(g_Texture0, transitPlane).rgb,\n        parcel.rgb,",
            with: "        parcel.rgb,\n        texSample2D(g_Texture0, transitPlane).rgb,"
        )
        let output = Output(
            transfer: transferToken(source),
            sourceSlot: SceneAuthoredShaderColorTransferAnalyzer
                .sameSlotCarrierBlendSourceSlot(fragmentSource: source),
            artifactKind: result?.transfer.kind,
            artifactSlot: result?.transfer.slot,
            unpremultipliedSamples: (result?.msl.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count ?? 1) - 1,
            premultipliedOutput: result?.msl.contains(
                "out.mwxFragColor = mwxGenericPremultiply(parcel);"
            ) == true,
            wrongSourceSlotRejected: transferToken(wrongSourceSlot) != "straight:0",
            alphaWriteRejected: transferToken(alphaWrite) != "straight:0",
            hiddenSourceSampleRejected:
                transferToken(hiddenSourceSample) != "straight:0",
            swappedSourceBlendRejected:
                transferToken(swappedSourceBlend) != "straight:0",
            wrongCompilerSlotRejected: prepared(msl.replacingOccurrences(
                of: "parcel.x = g_Texture0.sample(s, redCoordinate).x;",
                with: "parcel.x = g_Texture1.sample(s, redCoordinate).x;"
            )) == nil,
            compilerAlphaWriteRejected: prepared(msl.replacingOccurrences(
                of: "    float3 originalBase =",
                with: "    parcel.w = 0.5;\n    float3 originalBase ="
            )) == nil,
            hiddenCompilerSampleRejected: prepared(msl.replacingOccurrences(
                of: "    float3 originalBase =",
                with: "    float4 hidden = g_Texture0.sample(s, displaced);\n    float3 originalBase ="
            )) == nil,
            swappedCompilerBlendRejected: prepared(msl.replacingOccurrences(
                of: "ApplyBlending(0, originalBase, reconstructed, opacity)",
                with: "ApplyBlending(0, reconstructed, originalBase, opacity)"
            )) == nil,
            incompleteCompilerWriteRejected: prepared(msl.replacingOccurrences(
                of: "    parcel.y = blended.y;\n",
                with: ""
            )) == nil
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneSameSlotCarrierBlendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory()
        root = Path(cls.temporary.name)
        cls.harness = root / "Harness.swift"
        cls.binary = root / "scene-same-slot-carrier-blend"
        cls.harness.write_text(HARNESS, encoding="utf-8")
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        subprocess.run(
            [
                swiftc,
                "-module-cache-path",
                os.environ.get(
                    "MWX_SWIFT_MODULE_CACHE",
                    str(Path(tempfile.gettempdir()) / "mwx-swift-module-cache"),
                ),
                *(str(path) for path in SWIFT_SOURCES),
                str(cls.harness),
                "-o",
                str(cls.binary),
            ],
            check=True,
            cwd=REPOSITORY_ROOT,
        )
        cls.result = json.loads(
            subprocess.run(
                [str(cls.binary)],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_source_and_artifact_use_one_straight_color_boundary(self) -> None:
        self.assertEqual(self.result["transfer"], "straight:0")
        self.assertEqual(self.result["sourceSlot"], 0)
        self.assertEqual(self.result["artifactKind"], "straight-alpha-preserving")
        self.assertEqual(self.result["artifactSlot"], 0)
        self.assertEqual(self.result["unpremultipliedSamples"], 4)
        self.assertTrue(self.result["premultipliedOutput"])

    def test_source_and_compiler_drift_fail_closed(self) -> None:
        for key, value in self.result.items():
            if key.endswith("Rejected"):
                self.assertTrue(value, key)


if __name__ == "__main__":
    unittest.main()

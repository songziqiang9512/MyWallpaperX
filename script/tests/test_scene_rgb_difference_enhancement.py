#!/usr/bin/env python3

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

from scene_swift_source_sets import scene_swift_sources


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderAlphaWeightedSampleAverageCanonicalShape.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderStraightAlphaPreservingLowering.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderStraightAlphaWholeOutputUnionLowering.swift",
]


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let sourceSlot: Int?
    let fullColorSampleCounts: [Int: Int]?
    let dataSampleCounts: [Int: Int]?
    let renamedSlotsAccepted: Bool
    let literalAmountAccepted: Bool
    let reversedDifferenceRejected: Bool
    let nonUnitMaskRejected: Bool
    let wrongMixFactorRejected: Bool
    let dynamicAmountRejected: Bool
    let vectorAmountRejected: Bool
    let sameSlotRejected: Bool
    let wrongSamplerRejected: Bool
    let branchRejected: Bool
    let extraSampleRejected: Bool
    let extraStatementRejected: Bool
    let alphaWriteRejected: Bool
    let additionalFunctionRejected: Bool
    let wrongOutputCarrierRejected: Bool
    let loweringAccepted: Bool
    let sourceSampleUnpremultiplied: Bool
    let referenceSampleUnpremultiplied: Bool
    let outputPremultiplied: Bool
    let compilerExtraSampleRejected: Bool
    let compilerProjectionRejected: Bool
    let compilerSourceSlotDriftRejected: Bool
    let compilerOutputCarrierDriftRejected: Bool
    let zeroSampleCountRejected: Bool
    let singleColorWithoutDataRejected: Bool
}

@main
private struct RGBDifferenceEnhancementHarness {
    static func main() throws {
        let authored = [
            "uniform sampler2D g_Texture0;",
            "uniform sampler2D g_Texture2;",
            "uniform float g_Amount;",
            "varying vec4 v_TexCoord;",
            "void main() {",
            "    vec2 blurredCoords = v_TexCoord.xy;",
            "    vec4 blurred = texSample2D(g_Texture0, blurredCoords);",
            "    vec4 albedo = texSample2D(g_Texture2, v_TexCoord.xy);",
            "    vec3 delta = albedo.rgb - blurred.rgb;",
            "    vec3 enhanced = albedo.rgb + delta * g_Amount;",
            "    float mask = 1.0;",
            "    albedo.rgb = mix(albedo.rgb, enhanced.rgb, mask);",
            "    gl_FragColor = albedo;",
            "}",
        ].joined(separator: "\n")

        func fact(_ source: String) ->
            SceneAuthoredShaderPreservedAlphaRGBFilterFact? {
            SceneAuthoredShaderPreservedAlphaRGBFilterAnalyzer.analyzeAny(
                fragmentSource: source
            )
        }

        let positive = fact(authored)
        let renamed = authored
            .replacingOccurrences(of: "g_Texture0", with: "g_Texture3")
            .replacingOccurrences(of: "g_Texture2", with: "g_Texture6")
            .replacingOccurrences(of: "blurred", with: "referenceColor")
            .replacingOccurrences(of: "albedo", with: "sourceColor")
            .replacingOccurrences(of: "delta", with: "difference")
            .replacingOccurrences(of: "enhanced", with: "boosted")
            .replacingOccurrences(of: "mask", with: "blendFactor")
        let sameSlot = authored
            .replacingOccurrences(
                of: "uniform sampler2D g_Texture0;\n",
                with: ""
            )
            .replacingOccurrences(of: "g_Texture0", with: "g_Texture2")

        let msl = [
            "#include <metal_stdlib>",
            "using namespace metal;",
            "fragment Output mwxGenericFragment() {",
            "    float4 blurred = g_Texture0.sample(g_Texture0Smplr, in.uv);",
            "    float4 albedo = g_Texture2.sample(g_Texture2Smplr, in.uv);",
            "    float3 delta = albedo.xyz - blurred.xyz;",
            "    float3 enhanced = albedo.xyz + delta * uniforms.g_Amount;",
            "    float mask = 1.0;",
            "    albedo.xyz = mix(albedo.xyz, enhanced.xyz, mask);",
            "    Output out;",
            "    out.mwxFragColor = albedo;",
            "    return out;",
            "}",
        ].joined(separator: "\n")
        func lower(_ source: String) -> String? {
            positive.flatMap {
                SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerPreservedAlphaRGBFilter(
                        source,
                        sourceSlot: $0.sourceSlot,
                        fullColorSampleCallCounts:
                            $0.fullColorSampleCallCounts,
                        rgbColorSampleCallCounts:
                            $0.rgbColorSampleCallCounts,
                        dataSampleCallCounts: $0.dataSampleCallCounts
                    )
            }
        }
        let lowered = lower(msl) ?? ""

        let output = Output(
            sourceSlot: positive?.sourceSlot,
            fullColorSampleCounts: positive?.fullColorSampleCallCounts,
            dataSampleCounts: positive?.dataSampleCallCounts,
            renamedSlotsAccepted: fact(renamed)?.sourceSlot == 6,
            literalAmountAccepted: fact(
                authored.replacingOccurrences(
                    of: "delta * g_Amount",
                    with: "delta * 2.0"
                )
            ) != nil,
            reversedDifferenceRejected: fact(
                authored.replacingOccurrences(
                    of: "albedo.rgb - blurred.rgb",
                    with: "blurred.rgb - albedo.rgb"
                )
            ) == nil,
            nonUnitMaskRejected: fact(
                authored.replacingOccurrences(
                    of: "float mask = 1.0",
                    with: "float mask = 0.5"
                )
            ) == nil,
            wrongMixFactorRejected: fact(
                authored.replacingOccurrences(
                    of: "enhanced.rgb, mask)",
                    with: "enhanced.rgb, g_Amount)"
                )
            ) == nil,
            dynamicAmountRejected: fact(
                authored.replacingOccurrences(
                    of: "delta * g_Amount",
                    with: "delta * mask"
                )
            ) == nil,
            vectorAmountRejected: fact(
                authored.replacingOccurrences(
                    of: "uniform float g_Amount;",
                    with: "uniform vec2 g_Amount;"
                )
            ) == nil,
            sameSlotRejected: fact(sameSlot) == nil,
            wrongSamplerRejected: fact(
                authored.replacingOccurrences(
                    of: "uniform sampler2D g_Texture0;",
                    with: "uniform sampler3D g_Texture0;"
                )
            ) == nil,
            branchRejected: fact(
                authored.replacingOccurrences(
                    of: "    albedo.rgb = mix(albedo.rgb, enhanced.rgb, mask);",
                    with: "    if (mask > 0.0) { albedo.rgb = mix(albedo.rgb, enhanced.rgb, mask); }"
                )
            ) == nil,
            extraSampleRejected: fact(
                authored.replacingOccurrences(
                    of: "    vec3 delta =",
                    with: "    vec4 hidden = texSample2D(g_Texture3, v_TexCoord.xy);\n    vec3 delta ="
                )
            ) == nil,
            extraStatementRejected: fact(
                authored.replacingOccurrences(
                    of: "    gl_FragColor = albedo;",
                    with: "    float unrelated = 0.0;\n    gl_FragColor = albedo;"
                )
            ) == nil,
            alphaWriteRejected: fact(
                authored.replacingOccurrences(
                    of: "    gl_FragColor = albedo;",
                    with: "    albedo.a = 0.5;\n    gl_FragColor = albedo;"
                )
            ) == nil,
            additionalFunctionRejected: fact(
                authored.replacingOccurrences(
                    of: "void main() {",
                    with: "float helper(float x) { return x; }\nvoid main() {"
                )
            ) == nil,
            wrongOutputCarrierRejected: fact(
                authored.replacingOccurrences(
                    of: "gl_FragColor = albedo",
                    with: "gl_FragColor = blurred"
                )
            ) == nil,
            loweringAccepted: !lowered.isEmpty,
            sourceSampleUnpremultiplied: lowered.contains(
                "mwxGenericUnpremultiply(g_Texture2.sample(g_Texture2Smplr, in.uv))"
            ),
            referenceSampleUnpremultiplied: lowered.contains(
                "mwxGenericUnpremultiply(g_Texture0.sample(g_Texture0Smplr, in.uv))"
            ),
            outputPremultiplied: lowered.contains(
                "out.mwxFragColor = mwxGenericPremultiply(albedo);"
            ),
            compilerExtraSampleRejected: lower(
                msl.replacingOccurrences(
                    of: "    float3 delta =",
                    with: "    float4 hidden = g_Texture3.sample(g_Texture3Smplr, in.uv);\n    float3 delta ="
                )
            ) == nil,
            compilerProjectionRejected: lower(
                msl.replacingOccurrences(
                    of: "g_Texture0.sample(g_Texture0Smplr, in.uv);",
                    with: "g_Texture0.sample(g_Texture0Smplr, in.uv).xyz;"
                )
            ) == nil,
            compilerSourceSlotDriftRejected: lower(
                msl.replacingOccurrences(
                    of: "g_Texture2.sample(g_Texture2Smplr, in.uv)",
                    with: "g_Texture1.sample(g_Texture1Smplr, in.uv)"
                )
            ) == nil,
            compilerOutputCarrierDriftRejected: lower(
                msl.replacingOccurrences(
                    of: "out.mwxFragColor = albedo;",
                    with: "out.mwxFragColor = blurred;"
                )
            ) == nil,
            zeroSampleCountRejected:
                SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerPreservedAlphaRGBFilter(
                        msl,
                        sourceSlot: 2,
                        fullColorSampleCallCounts: [0: 0, 2: 1],
                        rgbColorSampleCallCounts: [:],
                        dataSampleCallCounts: [:]
                    ) == nil,
            singleColorWithoutDataRejected:
                SceneGenericShaderStraightAlphaPreservingLowering
                    .lowerPreservedAlphaRGBFilter(
                        msl,
                        sourceSlot: 2,
                        fullColorSampleCallCounts: [2: 1],
                        rgbColorSampleCallCounts: [:],
                        dataSampleCallCounts: [:]
                    ) == nil
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneRGBDifferenceEnhancementTests(unittest.TestCase):
    def test_source_and_compiler_artifact_contract(self):
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            self.skipTest("swiftc is unavailable")
        with tempfile.TemporaryDirectory(
            prefix="mwx-scene-rgb-difference-"
        ) as directory:
            root = Path(directory)
            harness = root / "RGBDifferenceEnhancementHarness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "rgb-difference-enhancement-harness"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(
                root / "clang-module-cache"
            )
            environment["SWIFT_MODULECACHE_PATH"] = str(
                root / "swift-module-cache"
            )
            subprocess.run(
                [
                    swiftc,
                    "-parse-as-library",
                    *(str(path) for path in SWIFT_SOURCES),
                    str(harness),
                    "-o", str(binary),
                ],
                cwd=REPOSITORY_ROOT,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertEqual(json.loads(completed.stdout), {
            "sourceSlot": 2,
            "fullColorSampleCounts": {"0": 1, "2": 1},
            "dataSampleCounts": {},
            "renamedSlotsAccepted": True,
            "literalAmountAccepted": True,
            "reversedDifferenceRejected": True,
            "nonUnitMaskRejected": True,
            "wrongMixFactorRejected": True,
            "dynamicAmountRejected": True,
            "vectorAmountRejected": True,
            "sameSlotRejected": True,
            "wrongSamplerRejected": True,
            "branchRejected": True,
            "extraSampleRejected": True,
            "extraStatementRejected": True,
            "alphaWriteRejected": True,
            "additionalFunctionRejected": True,
            "wrongOutputCarrierRejected": True,
            "loweringAccepted": True,
            "sourceSampleUnpremultiplied": True,
            "referenceSampleUnpremultiplied": True,
            "outputPremultiplied": True,
            "compilerExtraSampleRejected": True,
            "compilerProjectionRejected": True,
            "compilerSourceSlotDriftRejected": True,
            "compilerOutputCarrierDriftRejected": True,
            "zeroSampleCountRejected": True,
            "singleColorWithoutDataRejected": True,
        })


if __name__ == "__main__":
    unittest.main()

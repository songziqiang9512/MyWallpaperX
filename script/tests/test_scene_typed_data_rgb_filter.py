#!/usr/bin/env python3

"""Typed-data RGB filters conserve one color carrier and fail closed."""

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
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift",
]


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let transfer: String
    let sourceSlot: Int?
    let fullVectorCounts: [Int: Int]?
    let redCounts: [Int: Int]?
    let redGreenCounts: [Int: Int]?
    let auxiliarySlots: [Int]?
    let totalSamples: Int?
    let renamedAccepted: Bool
    let alphaWriteRejected: Bool
    let alphaIncrementRejected: Bool
    let alphaInoutRejected: Bool
    let secondRGBWriteRejected: Bool
    let secondSourceSampleRejected: Bool
    let helperSampleRejected: Bool
    let unprojectedWholeDataRejected: Bool
    let mixedProjectionRejected: Bool
    let nonterminalOutputRejected: Bool
    let loweringAccepted: Bool
    let sourceUnpremultipliedCount: Int
    let dataUnpremultipliedCount: Int
    let outputPremultiplied: Bool
    let compilerProjectionDriftRejected: Bool
    let compilerSampleDriftRejected: Bool
    let routeProfile: String
    let routeState: String
    let rollbackOwner: String
    let missingTypedPurposeProfile: String
    let providerProfile: String
    let secondGraphInputProfile: String
}

@main
private enum TypedDataRGBFilterHarness {
    static func main() throws {
        let authored = [
            "uniform sampler2D g_Texture0;",
            "uniform sampler2D g_Texture1;",
            "uniform sampler2D g_Texture2;",
            "uniform sampler2D g_Texture3;",
            "uniform sampler2D g_Texture4;",
            "uniform sampler2D g_Texture5;",
            "uniform sampler2D g_Texture6;",
            "varying vec2 v_TexCoord;",
            "vec3 ApplyBlending(const int mode, in vec3 base, in vec3 generated, in float opacity) {",
            "    return mix(base, generated, opacity);",
            "}",
            "void main() {",
            "    vec4 albedo = texSample2D(g_Texture0, v_TexCoord);",
            "    float mask = texSample2D(g_Texture1, v_TexCoord).r;",
            "    vec4 shiftColor = texSample2D(g_Texture4, v_TexCoord) * 2.0 - 1.0;",
            "    vec4 noiseColor = texSample2D(g_Texture3, v_TexCoord) * 2.0 - 1.0;",
            "    vec4 noiseColor2 = texSample2D(g_Texture3, v_TexCoord * 2.0) * 2.0 - 1.0;",
            "    vec3 pattern = vec3(texSample2D(g_Texture2, v_TexCoord).r, texSample2D(g_Texture2, v_TexCoord * 2.0).r, texSample2D(g_Texture2, v_TexCoord * 3.0).r);",
            "    float glow = texSample2D(g_Texture5, v_TexCoord).r;",
            "    vec4 blendColor = texSample2D(g_Texture3, v_TexCoord * 3.0);",
            "    vec2 flow = texSample2D(g_Texture6, v_TexCoord).rg;",
            "    vec3 generated = pattern * noiseColor.rgb + shiftColor.rgb * glow + blendColor.rgb * flow.x;",
            "    albedo.rgb = ApplyBlending(8, albedo.rgb, generated, mask);",
            "    gl_FragColor = albedo;",
            "}",
        ].joined(separator: "\n")
        let msl = [
            "#include <metal_stdlib>",
            "using namespace metal;",
            "fragment void f() {",
            "    float4 albedo = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord);",
            "    float mask = g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord).x;",
            "    float4 shiftColor = g_Texture4.sample(g_Texture4Smplr, in.v_TexCoord) * 2.0 - 1.0;",
            "    float4 noiseColor = g_Texture3.sample(g_Texture3Smplr, in.v_TexCoord) * 2.0 - 1.0;",
            "    float4 noiseColor2 = g_Texture3.sample(g_Texture3Smplr, in.v_TexCoord * 2.0) * 2.0 - 1.0;",
            "    float3 pattern = float3(g_Texture2.sample(g_Texture2Smplr, in.v_TexCoord).x, g_Texture2.sample(g_Texture2Smplr, in.v_TexCoord * 2.0).x, g_Texture2.sample(g_Texture2Smplr, in.v_TexCoord * 3.0).x);",
            "    float glow = g_Texture5.sample(g_Texture5Smplr, in.v_TexCoord).x;",
            "    float4 blendColor = g_Texture3.sample(g_Texture3Smplr, in.v_TexCoord * 3.0);",
            "    float2 flow = g_Texture6.sample(g_Texture6Smplr, in.v_TexCoord).xy;",
            "    albedo.xyz = ApplyBlending(8, albedo.xyz, generated, mask);",
            "    out.mwxFragColor = albedo;",
            "    return out;",
            "}",
        ].joined(separator: "\n")

        func fact(_ source: String) -> SceneAuthoredShaderTypedDataRGBFilterFact? {
            SceneAuthoredShaderTypedDataRGBFilterAnalyzer.analyze(
                fragmentSource: source
            )
        }
        func profile(
            typed: Set<Int>,
            graphInputs: Set<Int> = [0],
            provider: Bool = false
        ) -> SceneGenericShaderCapabilityProfile {
            SceneGenericShaderCapabilityProfile(
                colorTransfer: .straightAlphaPreserving(textureSlot: 0),
                alphaAttenuationSourceSlot: nil,
                colorBlendSourceSlot: nil,
                conditionalStraightUnionSourceSlot: nil,
                singleSamplerAlphaMutationSourceSlot: nil,
                sameSlotChannelReconstructionSourceSlot: nil,
                auxiliaryRGBMixSourceSlot: nil,
                normalizedSampleSumSourceSlot: nil,
                alphaWeightedSampleAverageSourceSlot: nil,
                preservedAlphaRGBFilterSourceSlot: nil,
                preservedAlphaRGBFilterTextureSlots: [],
                typedDataRGBFilterSourceSlot: 0,
                typedDataRGBFilterAuxiliarySlots: [1, 2, 3, 4, 5, 6],
                typedStaticDataAuxiliarySlots: typed,
                unitCompositeBlurredSlot: nil,
                unitCompositePreviousSlot: nil,
                hasExternalProviderTexture: provider,
                producesScalarRedOutput: false,
                isSourceIndependentPremultipliedOutput: false,
                graphTextureSlots: graphInputs.subtracting([0]),
                graphInputTextureSlots: graphInputs,
                r8TextureSlots: [],
                hasDefaultedOpacityMaskSampler: false,
                hasStageScopedUniformBindings: false,
                hasStereoAudioSpectrumArrays: false,
                hasLocalizedMutableFragmentVarying: false
            )
        }

        let analyzed = fact(authored)
        let transfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: authored
        )
        let lowered = try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
            msl: msl,
            authoredSource: authored
        )
        let loweredMSL = lowered?.msl ?? ""
        let selected = profile(typed: [1, 2, 3, 4, 5, 6])
        let projectionDrift = msl.replacingOccurrences(
            of: "g_Texture5.sample(g_Texture5Smplr, in.v_TexCoord).x",
            with: "g_Texture5.sample(g_Texture5Smplr, in.v_TexCoord).xy"
        )
        let sampleDrift = msl.replacingOccurrences(
            of: "    out.mwxFragColor = albedo;",
            with: "    float hidden = g_Texture5.sample(g_Texture5Smplr, in.v_TexCoord).x;\n    out.mwxFragColor = albedo;"
        )
        let renamed = authored
            .replacingOccurrences(of: "albedo", with: "sceneCarrier")
            .replacingOccurrences(of: "generated", with: "proceduralRGB")
            .replacingOccurrences(of: "noiseColor", with: "fieldValue")

        let output = Output(
            transfer: {
                if case .straightAlphaPreserving(textureSlot: 0) = transfer {
                    return "straight-alpha-preserving-0"
                }
                return "unexpected"
            }(),
            sourceSlot: analyzed?.sourceSlot,
            fullVectorCounts: analyzed?.fullVectorDataSampleCallCounts,
            redCounts: analyzed?.redDataSampleCallCounts,
            redGreenCounts: analyzed?.redGreenDataSampleCallCounts,
            auxiliarySlots: analyzed?.auxiliarySlots.sorted(),
            totalSamples: analyzed?.totalSampleCallCount,
            renamedAccepted: fact(renamed) != nil,
            alphaWriteRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = albedo;",
                with: "    albedo.a = mask;\n    gl_FragColor = albedo;"
            )) == nil,
            alphaIncrementRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = albedo;",
                with: "    albedo.a++;\n    gl_FragColor = albedo;"
            )) == nil,
            alphaInoutRejected: fact(authored
                .replacingOccurrences(
                    of: "void main() {",
                    with: "void mutate(inout float value) { value = 0.0; }\nvoid main() {"
                )
                .replacingOccurrences(
                    of: "    gl_FragColor = albedo;",
                    with: "    mutate(albedo.a);\n    gl_FragColor = albedo;"
                )) == nil,
            secondRGBWriteRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = albedo;",
                with: "    albedo.rgb *= 0.5;\n    gl_FragColor = albedo;"
            )) == nil,
            secondSourceSampleRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = albedo;",
                with: "    float hidden = texSample2D(g_Texture0, v_TexCoord).r;\n    gl_FragColor = albedo;"
            )) == nil,
            helperSampleRejected: fact(authored.replacingOccurrences(
                of: "    return mix(base, generated, opacity);",
                with: "    return mix(base, generated, opacity) + texSample2D(g_Texture2, vec2(0.0)).rgb;"
            )) == nil,
            unprojectedWholeDataRejected: fact(authored.replacingOccurrences(
                of: "float glow = texSample2D(g_Texture5, v_TexCoord).r;",
                with: "float glow = texSample2D(g_Texture5, v_TexCoord);"
            )) == nil,
            mixedProjectionRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = albedo;",
                with: "    float mixed = texSample2D(g_Texture3, v_TexCoord).r;\n    gl_FragColor = albedo;"
            )) == nil,
            nonterminalOutputRejected: fact(authored.replacingOccurrences(
                of: "    gl_FragColor = albedo;",
                with: "    gl_FragColor = albedo;\n    mask *= 0.5;"
            )) == nil,
            loweringAccepted: lowered != nil,
            sourceUnpremultipliedCount: loweredMSL.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count - 1,
            dataUnpremultipliedCount: (1 ... 6).reduce(0) { count, slot in
                count + loweredMSL.components(
                    separatedBy: "mwxGenericUnpremultiply(g_Texture\(slot).sample("
                ).count - 1
            },
            outputPremultiplied: loweredMSL.contains(
                "out.mwxFragColor = mwxGenericPremultiply(albedo);"
            ),
            compilerProjectionDriftRejected: (try?
                SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: projectionDrift,
                    authoredSource: authored
                )) == nil,
            compilerSampleDriftRejected: (try?
                SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: sampleDrift,
                    authoredSource: authored
                )) == nil,
            routeProfile: selected.rawValue,
            routeState: selected.defaultRouteState.rawValue,
            rollbackOwner: selected.validatedRollbackOwner.rawValue,
            missingTypedPurposeProfile: profile(
                typed: [1, 2, 3, 4, 5]
            ).rawValue,
            providerProfile: profile(
                typed: [1, 2, 3, 4, 5, 6],
                provider: true
            ).rawValue,
            secondGraphInputProfile: profile(
                typed: [1, 2, 3, 4, 5, 6],
                graphInputs: [0, 6]
            ).rawValue
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneTypedDataRGBFilterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        swiftc = shutil.which("swiftc")
        if swiftc is None:
            raise unittest.SkipTest("swiftc is unavailable")
        cls.build_directory = tempfile.TemporaryDirectory(
            prefix="mwx-typed-data-rgb-filter-"
        )
        root = Path(cls.build_directory.name)
        harness = root / "TypedDataRGBFilterHarness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "typed-data-rgb-filter"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
            [
                swiftc,
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework", "Security",
                "-o", str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr)
        result = subprocess.run(
            [str(cls.binary)],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr or result.stdout)
        cls.result = json.loads(result.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.build_directory.cleanup()

    def test_source_fact_and_compiler_conservation(self) -> None:
        self.assertEqual(self.result["transfer"], "straight-alpha-preserving-0")
        self.assertEqual(self.result["sourceSlot"], 0)
        self.assertEqual(self.result["fullVectorCounts"], {"3": 3, "4": 1})
        self.assertEqual(self.result["redCounts"], {"1": 1, "2": 3, "5": 1})
        self.assertEqual(self.result["redGreenCounts"], {"6": 1})
        self.assertEqual(self.result["auxiliarySlots"], [1, 2, 3, 4, 5, 6])
        self.assertEqual(self.result["totalSamples"], 11)
        self.assertTrue(self.result["renamedAccepted"])
        self.assertTrue(self.result["loweringAccepted"])
        self.assertEqual(self.result["sourceUnpremultipliedCount"], 1)
        self.assertEqual(self.result["dataUnpremultipliedCount"], 0)
        self.assertTrue(self.result["outputPremultiplied"])

    def test_unsafe_source_or_compiler_drift_fails_closed(self) -> None:
        for key in (
            "alphaWriteRejected",
            "alphaIncrementRejected",
            "alphaInoutRejected",
            "secondRGBWriteRejected",
            "secondSourceSampleRejected",
            "helperSampleRejected",
            "unprojectedWholeDataRejected",
            "mixedProjectionRejected",
            "nonterminalOutputRejected",
            "compilerProjectionDriftRejected",
            "compilerSampleDriftRejected",
        ):
            self.assertTrue(self.result[key], (key, self.result))

    def test_only_exact_typed_static_auxiliary_set_gets_generic_owner(self) -> None:
        self.assertEqual(
            self.result["routeProfile"],
            "source-proven-graph-input-typed-data-rgb-filter",
        )
        self.assertEqual(self.result["routeState"], "generic-only")
        self.assertEqual(self.result["rollbackOwner"], "none")
        self.assertEqual(
            self.result["missingTypedPurposeProfile"],
            "source-proven-graph-input-straight-alpha-preserving",
        )
        self.assertEqual(
            self.result["providerProfile"],
            "ordinary-shader",
        )
        self.assertEqual(
            self.result["secondGraphInputProfile"],
            "source-proven-graph-input-straight-alpha-preserving",
        )


if __name__ == "__main__":
    unittest.main()

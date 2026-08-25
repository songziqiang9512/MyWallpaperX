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
    let terminalTransform: String?
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
    let maskedTransfer: String
    let maskedSourceSlot: Int?
    let maskedTerminalTransform: String?
    let maskedAuxiliarySlots: [Int]?
    let maskedLoweringAccepted: Bool
    let maskedSourceUnpremultipliedCount: Int
    let maskedDataUnpremultipliedCount: Int
    let maskedOutputPremultiplied: Bool
    let maskedAlphaWriteRejected: Bool
    let maskedWrongSnapshotRejected: Bool
    let maskedWholeAuxiliaryRejected: Bool
    let maskedDetachedOutputRejected: Bool
    let compilerScalarLaneLoweringAccepted: Bool
    let unmaskedTransferAccepted: Bool
    let unmaskedLoweringAccepted: Bool
    let boundaryHelperConflictRejected: Bool
    let maxCastSourceAccepted: Bool
    let maxLiteralSourceAccepted: Bool
    let maxTerminalTransform: String?
    let maxLoweringAccepted: Bool
    let maxOutputPremultiplied: Bool
    let maxSourceAlphaDriftRejected: Bool
    let maxArtifactAlphaDriftRejected: Bool
    let maxUpperClampRejected: Bool
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
        let maskedAuthored = [
            "uniform sampler2D g_Texture0;",
            "uniform sampler2D g_Texture1;",
            "uniform sampler2D g_Texture2;",
            "varying vec2 v_TexCoord;",
            "vec3 ApplyBlending(const int mode, in vec3 base, in vec3 generated, in float opacity) {",
            "    return mix(base, generated, opacity);",
            "}",
            "void main() {",
            "    vec4 snapshot = texSample2D(g_Texture0, v_TexCoord);",
            "    vec4 carrier = snapshot;",
            "    float signal = texSample2D(g_Texture1, v_TexCoord).r;",
            "    carrier.rgb = ApplyBlending(8, carrier.rgb, carrier.rgb * 0.5, signal);",
            "    float mask = texSample2D(g_Texture2, v_TexCoord).r;",
            "    carrier = mix(snapshot, carrier, mask);",
            "    gl_FragColor = saturate(carrier);",
            "}",
        ].joined(separator: "\n")
        let maskedMSL = [
            "#include <metal_stdlib>",
            "using namespace metal;",
            "fragment void f() {",
            "    float4 snapshot = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord);",
            "    float4 carrier = snapshot;",
            "    float signal = g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord).x;",
            "    carrier.xyz = ApplyBlending(8, carrier.xyz, carrier.xyz * 0.5, signal);",
            "    float mask = g_Texture2.sample(g_Texture2Smplr, in.v_TexCoord).x;",
            "    carrier = mix(snapshot, carrier, mask);",
            "    out.mwxFragColor = fast::clamp(carrier, float4(0.0), float4(1.0));",
            "    return out;",
            "}",
        ].joined(separator: "\n")
        let maxAuthored = maskedAuthored.replacingOccurrences(
            of: "    gl_FragColor = saturate(carrier);",
            with: "    gl_FragColor = vec4(max(CAST3(0), carrier.rgb), carrier.a);"
        )
        let literalMaxAuthored = maxAuthored.replacingOccurrences(
            of: "max(CAST3(0), carrier.rgb)",
            with: "max(0, carrier.rgb)"
        )
        let maxMSL = maskedMSL.replacingOccurrences(
            of: "    out.mwxFragColor = fast::clamp(carrier, float4(0.0), float4(1.0));",
            with: "    out.mwxFragColor = float4(fast::max(float3(0.0), carrier.xyz), carrier.w);"
        )

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
        let maskedAnalyzed = fact(maskedAuthored)
        let maskedTransfer = SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: maskedAuthored
        )
        let maskedLowered = try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
            msl: maskedMSL,
            authoredSource: maskedAuthored
        )
        let maskedLoweredMSL = maskedLowered?.msl ?? ""
        let maxAnalyzed = fact(maxAuthored)
        let maxLowered = try? SceneGenericShaderArtifactBuilder
            .prepareColorTransfer(msl: maxMSL, authoredSource: maxAuthored)
        let maxLoweredMSL = maxLowered?.msl ?? ""
        let unmaskedAuthored = maskedAuthored.replacingOccurrences(
            of: "    float mask = texSample2D(g_Texture2, v_TexCoord).r;\n"
                + "    carrier = mix(snapshot, carrier, mask);\n",
            with: ""
        )
        let unmaskedMSL = maskedMSL.replacingOccurrences(
            of: "    float mask = g_Texture2.sample(g_Texture2Smplr, in.v_TexCoord).x;\n"
                + "    carrier = mix(snapshot, carrier, mask);\n",
            with: ""
        )
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
            terminalTransform: analyzed?.terminalTransform.rawValue,
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
            maskedTransfer: {
                if case .straightAlphaPreserving(textureSlot: 0) = maskedTransfer {
                    return "straight-alpha-preserving-0"
                }
                return "unexpected"
            }(),
            maskedSourceSlot: maskedAnalyzed?.sourceSlot,
            maskedTerminalTransform:
                maskedAnalyzed?.terminalTransform.rawValue,
            maskedAuxiliarySlots: maskedAnalyzed?.auxiliarySlots.sorted(),
            maskedLoweringAccepted: maskedLowered != nil,
            maskedSourceUnpremultipliedCount: maskedLoweredMSL.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count - 1,
            maskedDataUnpremultipliedCount: (1 ... 2).reduce(0) { count, slot in
                count + maskedLoweredMSL.components(
                    separatedBy: "mwxGenericUnpremultiply(g_Texture\(slot).sample("
                ).count - 1
            },
            maskedOutputPremultiplied: maskedLoweredMSL.contains(
                "out.mwxFragColor = mwxGenericPremultiply(fast::clamp(carrier"
            ),
            maskedAlphaWriteRejected: fact(maskedAuthored.replacingOccurrences(
                of: "    gl_FragColor = saturate(carrier);",
                with: "    carrier.a = mask;\n    gl_FragColor = saturate(carrier);"
            )) == nil,
            maskedWrongSnapshotRejected: fact(maskedAuthored.replacingOccurrences(
                of: "carrier = mix(snapshot, carrier, mask);",
                with: "carrier = mix(vec4(0.0), carrier, mask);"
            )) == nil,
            maskedWholeAuxiliaryRejected: fact(maskedAuthored.replacingOccurrences(
                of: "float mask = texSample2D(g_Texture2, v_TexCoord).r;",
                with: "vec4 mask = texSample2D(g_Texture2, v_TexCoord);"
            ).replacingOccurrences(
                of: "carrier = mix(snapshot, carrier, mask);",
                with: "carrier = mix(snapshot, carrier, mask.r);"
            )) == nil,
            maskedDetachedOutputRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: maskedMSL.replacingOccurrences(
                        of: "    out.mwxFragColor = fast::clamp(carrier, float4(0.0), float4(1.0));",
                        with: "    float4 unrelated = float4(0.25);\n"
                            + "    out.mwxFragColor = fast::clamp(unrelated, float4(0.0), float4(1.0));"
                    ),
                    authoredSource: maskedAuthored
                )) == nil,
            compilerScalarLaneLoweringAccepted:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: maskedMSL
                        .replacingOccurrences(
                            of: "    carrier.xyz = ApplyBlending(8, carrier.xyz, carrier.xyz * 0.5, signal);",
                            with: "    float3 filtered = ApplyBlending(8, carrier.xyz, carrier.xyz * 0.5, signal);\n"
                                + "    carrier.x = filtered.x;\n"
                                + "    carrier.y = filtered.y;\n"
                                + "    carrier.z = filtered.z;"
                        )
                        .replacingOccurrences(
                            of: "    carrier = mix(snapshot, carrier, mask);",
                            with: "    carrier = mix(snapshot, carrier, float4(mask));"
                        ),
                    authoredSource: maskedAuthored
                )) != nil,
            unmaskedTransferAccepted: fact(unmaskedAuthored) != nil,
            unmaskedLoweringAccepted:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: unmaskedMSL,
                    authoredSource: unmaskedAuthored
                )) != nil,
            boundaryHelperConflictRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: maskedMSL.replacingOccurrences(
                        of: "fragment void f() {",
                        with: "float4 mwxGenericPremultiply(float4 value) { return value; }\nfragment void f() {"
                    ),
                    authoredSource: maskedAuthored
                )) == nil,
            maxCastSourceAccepted: maxAnalyzed != nil,
            maxLiteralSourceAccepted: fact(literalMaxAuthored) != nil,
            maxTerminalTransform: maxAnalyzed?.terminalTransform.rawValue,
            maxLoweringAccepted: maxLowered != nil,
            maxOutputPremultiplied: maxLoweredMSL.contains(
                "out.mwxFragColor = mwxGenericPremultiply("
                    + "float4(fast::max(float3(0.0), carrier.xyz), carrier.w));"
            ),
            maxSourceAlphaDriftRejected: fact(maxAuthored.replacingOccurrences(
                of: "carrier.a);",
                with: "snapshot.a);"
            )) == nil,
            maxArtifactAlphaDriftRejected:
                (try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
                    msl: maxMSL.replacingOccurrences(
                        of: "carrier.w);",
                        with: "snapshot.w);"
                    ),
                    authoredSource: maxAuthored
                )) == nil,
            maxUpperClampRejected: fact(maxAuthored.replacingOccurrences(
                of: "max(CAST3(0), carrier.rgb)",
                with: "min(CAST3(0), carrier.rgb)"
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
        self.assertEqual(self.result["terminalTransform"], "identity")
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

    def test_masked_snapshot_carrier_reuses_the_typed_data_boundary(self) -> None:
        self.assertEqual(
            self.result["maskedTransfer"], "straight-alpha-preserving-0"
        )
        self.assertEqual(self.result["maskedSourceSlot"], 0)
        self.assertEqual(
            self.result["maskedTerminalTransform"], "saturateRGBA"
        )
        self.assertEqual(self.result["maskedAuxiliarySlots"], [1, 2])
        self.assertTrue(self.result["maskedLoweringAccepted"])
        self.assertEqual(self.result["maskedSourceUnpremultipliedCount"], 1)
        self.assertEqual(self.result["maskedDataUnpremultipliedCount"], 0)
        self.assertTrue(self.result["maskedOutputPremultiplied"])
        self.assertTrue(self.result["maskedAlphaWriteRejected"])
        self.assertTrue(self.result["maskedWrongSnapshotRejected"])
        self.assertTrue(self.result["maskedWholeAuxiliaryRejected"])
        self.assertTrue(self.result["maskedDetachedOutputRejected"])
        self.assertTrue(self.result["compilerScalarLaneLoweringAccepted"])
        self.assertTrue(self.result["unmaskedTransferAccepted"])
        self.assertTrue(self.result["unmaskedLoweringAccepted"])
        self.assertTrue(self.result["boundaryHelperConflictRejected"])

    def test_nonnegative_rgb_preserved_alpha_terminal_is_conserved(self) -> None:
        self.assertTrue(self.result["maxCastSourceAccepted"])
        self.assertTrue(self.result["maxLiteralSourceAccepted"])
        self.assertEqual(
            self.result["maxTerminalTransform"],
            "nonNegativeRGBPreservedAlpha",
        )
        self.assertTrue(self.result["maxLoweringAccepted"])
        self.assertTrue(self.result["maxOutputPremultiplied"])
        self.assertTrue(self.result["maxSourceAlphaDriftRejected"])
        self.assertTrue(self.result["maxArtifactAlphaDriftRejected"])
        self.assertTrue(self.result["maxUpperClampRejected"])

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

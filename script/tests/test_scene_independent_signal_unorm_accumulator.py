#!/usr/bin/env python3
"""Typed RGBA8 target contract for an independent-signal accumulator."""

from __future__ import annotations

import json
from pathlib import Path
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
    / "RenderGraph/ShaderPreparation/SceneGenericShaderExpectedColorTransfer.swift",
    SCENE_ROOT
    / "RenderGraph/ShaderPreparation/SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift",
]


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let positiveSlots: [String: String]
    let positiveWork: [String: Int]
    let explicitClampProofUnaffected: Bool
    let negativeSourceProofs: [String: Bool]
    let artifactProofs: [String: Bool]
    let expectedTransfer: String
    let expectedTransferCacheKey: String
    let profile: String
    let route: String
    let rollback: String
    let targetFactRequired: Bool
    let graphRoleRequired: Bool
    let sourceRoleRequired: Bool
    let graphOnlySamplerRequired: Bool
    let externalProviderRejected: Bool
    let preservedRGBARejected: Bool
}

private func source(
    slot: Int = 0,
    accumulator: String = "albedo",
    sample: String = "sampleValue",
    index: String = "ordinal",
    bound: String = "sampleCount",
    denominator: String = "sampleDrop",
    intensity: String = "g_Intensity",
    tint: String = "g_ColorRays"
) -> String {
    """
    uniform sampler2D g_Texture\(slot);
    uniform float \(intensity);
    uniform vec3 \(tint);
    varying vec2 v_TexCoord;

    void main() {
        vec2 coordinate = v_TexCoord;
        vec2 direction = vec2(0.0, -0.5);
        float distanceValue = length(direction);
        direction /= distanceValue;
        vec4 \(accumulator) = CAST4(0.0);
        const int \(bound) = 30;
        const float sampleIntensity = 0.1;
        const float \(denominator) = \(bound) - 1;
        direction = direction * distanceValue / \(denominator);
        for (int \(index) = 0; \(index) < \(bound); ++\(index)) {
            vec4 \(sample) = texSample2D(g_Texture\(slot), coordinate);
            coordinate -= direction;
            \(accumulator) += \(sample) * (\(index) / \(denominator));
        }
        \(accumulator).rgb *= \(tint);
        gl_FragColor = \(intensity) * sampleIntensity * \(accumulator);
    }
    """
}

private func helperSource(
    slot: Int = 0,
    helper: String = "collectDirection",
    accumulator: String = "combinedSignal",
    sample: String = "sourceValue",
    index: String = "ordinal",
    intensity: String = "g_Intensity",
    tint: String = "g_ColorRays"
) -> String {
    """
    uniform sampler2D g_Texture\(slot);
    uniform float \(intensity);
    uniform float g_Length;
    uniform vec3 \(tint);
    varying vec4 v_TexCoord01;

    vec4 \(helper)(vec2 coordinate, vec2 direction) {
        vec4 weightedSignal = CAST4(0.0);
        const int sampleCount = 8;
        const float sampleDrop = sampleCount - 1;
        direction *= g_Length / sampleDrop;
        for (int \(index) = 0; \(index) < sampleCount; ++\(index)) {
            vec4 \(sample) = texSample2D(g_Texture\(slot), coordinate);
            coordinate -= direction;
            weightedSignal += \(sample) * (\(index) / sampleDrop);
        }
        return weightedSignal;
    }

    void main() {
        vec2 coordinate = v_TexCoord01.xy;
        vec4 \(accumulator) = CAST4(0.0);
        \(accumulator) += \(helper)(coordinate, v_TexCoord01.zw);
        \(accumulator) += \(helper)(coordinate, -v_TexCoord01.zw);
        \(accumulator) += \(helper)(coordinate, v_TexCoord01.zy);
        \(accumulator) += \(helper)(coordinate, -v_TexCoord01.zy);
        const float sampleIntensity = 0.1;
        \(accumulator).rgb *= \(tint);
        gl_FragColor = \(intensity) * sampleIntensity * \(accumulator);
    }
    """
}

private func artifactSource(
    slot: Int = 0,
    output: String = "albedo * (uniforms.g_Intensity * 0.1)",
    extraSample: Bool = false
) -> String {
    """
    #include <metal_stdlib>
    using namespace metal;
    struct Uniforms {
        float g_Intensity;
        float3 g_ColorRays;
    };
    struct FragmentOut { float4 mwxFragColor [[color(0)]]; };
    static inline float4 collect(
        texture2d<float> g_Texture\(slot),
        sampler textureSampler
    ) {
        float4 sampleValue = g_Texture\(slot).sample(
            textureSampler, float2(0.5)
        );
        return sampleValue;
    }
    fragment FragmentOut mwxGenericFragment(
        constant Uniforms& uniforms [[buffer(8)]],
        texture2d<float> g_Texture\(slot) [[texture(\(slot))]],
        sampler textureSampler [[sampler(\(slot))]]
    ) {
        FragmentOut out = {};
        float4 albedo = float4(0.0);
        float4 extra = float4(0.0);
        albedo += collect(g_Texture\(slot), textureSampler);
        \(extraSample ? "albedo += g_Texture\(slot).sample(textureSampler, float2(0.25));" : "")
        out.mwxFragColor = \(output);
        return out;
    }
    """
}

private func slot(_ source: String) -> String {
    SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
        .rgba8UnormAttachmentSourceSlot(fragmentSource: source)
        .map(String.init) ?? "nil"
}

private func work(_ source: String) -> Int? {
    SceneAuthoredShaderIndependentSignalAccumulatorAnalyzer
        .rgba8UnormAttachmentLoopWork(fragmentSource: source)
}

private func profile(
    sourceSlot: Int? = 0,
    outputIsRGBA8Unorm: Bool = true,
    graphTextureSlots: Set<Int> = [0],
    graphInputTextureSlots: Set<Int> = [0],
    hasOnlyGraphInputSampler: Bool = true,
    producesPreservedRGBAOutput: Bool = false,
    external: Bool = false
) -> SceneGenericShaderCapabilityProfile {
    SceneGenericShaderCapabilityProfile(
        colorTransfer: .independentAlphaSignalPreserving(textureSlot: 0),
        alphaAttenuationSourceSlot: nil,
        colorBlendSourceSlot: nil,
        conditionalStraightUnionSourceSlot: nil,
        singleSamplerAlphaMutationSourceSlot: nil,
        sameSlotChannelReconstructionSourceSlot: nil,
        auxiliaryRGBMixSourceSlot: nil,
        normalizedSampleSumSourceSlot: nil,
        independentSignalAccumulatorSourceSlot: nil,
        independentSignalUNormAccumulatorSourceSlot: sourceSlot,
        alphaWeightedSampleAverageSourceSlot: nil,
        preservedAlphaRGBFilterSourceSlot: nil,
        preservedAlphaRGBFilterTextureSlots: [],
        unitCompositeBlurredSlot: nil,
        unitCompositePreviousSlot: nil,
        hasExternalProviderTexture: external,
        producesScalarRedOutput: false,
        producesPreservedRGBAOutput: producesPreservedRGBAOutput,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: graphTextureSlots,
        graphInputTextureSlots: graphInputTextureSlots,
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasOnlyGraphInputSampler: hasOnlyGraphInputSampler,
        outputIsRGBA8Unorm: outputIsRGBA8Unorm,
        hasStageScopedUniformBindings: false,
        hasStereoAudioSpectrumArrays: false
    )
}

@main
private enum Harness {
    static func main() throws {
        let structural = source()
        let renamed = source(
            slot: 3,
            accumulator: "weightedSignal",
            sample: "sourceValue",
            index: "sampleOrdinal",
            bound: "tapCount",
            denominator: "positiveDivisor",
            intensity: "g_SharedIntensity",
            tint: "g_SharedTint"
        )
        let helper = helperSource()
        let renamedHelper = helperSource(
            slot: 5,
            helper: "gatherUnseenDirection",
            accumulator: "unseenSignal",
            sample: "unseenTap",
            index: "tapOrdinal",
            intensity: "g_SharedIntensity",
            tint: "g_SharedTint"
        )
        let explicitClamp = structural.replacingOccurrences(
            of: "gl_FragColor = g_Intensity * sampleIntensity * albedo;",
            with: "gl_FragColor = vec4(g_Intensity * sampleIntensity * albedo.rgb, "
                + "saturate(g_Intensity * sampleIntensity * albedo.a));"
        )
        let differentChannels = structural.replacingOccurrences(
            of: "gl_FragColor = g_Intensity * sampleIntensity * albedo;",
            with: "gl_FragColor = vec4(g_Intensity * sampleIntensity * albedo.rgb, 1.0);"
        )
        let negativeWeight = structural.replacingOccurrences(
            of: "sampleValue * (ordinal / sampleDrop)",
            with: "sampleValue * (-ordinal / sampleDrop)"
        )
        let dynamicLoop = structural
            .replacingOccurrences(
                of: "uniform float g_Intensity;",
                with: "uniform float g_Intensity;\nuniform int g_RuntimeCount;"
            )
            .replacingOccurrences(of: "const int sampleCount = 30;", with: "")
            .replacingOccurrences(of: "sampleCount", with: "g_RuntimeCount")
        let extraSampler = structural
            .replacingOccurrences(
                of: "uniform sampler2D g_Texture0;",
                with: "uniform sampler2D g_Texture0;\nuniform sampler2D g_Texture1;"
            )
            .replacingOccurrences(
                of: "coordinate -= direction;",
                with: "vec4 foreign = texSample2D(g_Texture1, coordinate);\n"
                    + "coordinate -= direction;"
            )
        let indexWrite = structural.replacingOccurrences(
            of: "vec4 sampleValue = texSample2D(g_Texture0, coordinate);",
            with: "ordinal = 0;\n"
                + "vec4 sampleValue = texSample2D(g_Texture0, coordinate);"
        )
        let branch = structural.replacingOccurrences(
            of: "albedo.rgb *= g_ColorRays;",
            with: "if (g_Intensity > 0.0) { albedo.rgb *= g_ColorRays; }"
        )
        let helperDifferentChannels = helper.replacingOccurrences(
            of: "gl_FragColor = g_Intensity * sampleIntensity * combinedSignal;",
            with: "gl_FragColor = vec4(combinedSignal.rgb, 1.0);"
        )
        let helperNegativeWeight = helper.replacingOccurrences(
            of: "sourceValue * (ordinal / sampleDrop)",
            with: "sourceValue * (-ordinal / sampleDrop)"
        )
        let helperDynamicLoop = helper
            .replacingOccurrences(
                of: "uniform float g_Length;",
                with: "uniform float g_Length;\nuniform int g_RuntimeCount;"
            )
            .replacingOccurrences(of: "const int sampleCount = 8;", with: "")
            .replacingOccurrences(of: "sampleCount", with: "g_RuntimeCount")
        let helperBranch = helper.replacingOccurrences(
            of: "weightedSignal += sourceValue * (ordinal / sampleDrop);",
            with: "if (ordinal > 0) { weightedSignal += sourceValue * "
                + "(ordinal / sampleDrop); }"
        )
        let selected = profile()
        let expectedTransfer = SceneGenericShaderExpectedColorTransfer(
            .independentAlphaSignalPreserving(textureSlot: 0),
            fragmentSource: helper,
            usesRGBA8UnormAttachmentBoundary: true
        )!
        let expectedTransferData = try JSONEncoder().encode(expectedTransfer)
        let output = Output(
            positiveSlots: [
                "structural": slot(structural),
                "renamed": slot(renamed),
                "helper": slot(helper),
                "renamedHelper": slot(renamedHelper),
            ],
            positiveWork: [
                "structural": work(structural) ?? -1,
                "renamed": work(renamed) ?? -1,
                "helper": work(helper) ?? -1,
                "renamedHelper": work(renamedHelper) ?? -1,
            ],
            explicitClampProofUnaffected:
                SceneAuthoredShaderIndependentSignalInlineAccumulatorAnalyzer
                    .sourceSlot(fragmentSource: explicitClamp) == 0
                && SceneAuthoredShaderIndependentSignalInlineAccumulatorAnalyzer
                    .sourceSlot(fragmentSource: structural) == nil,
            negativeSourceProofs: [
                "differentChannels": slot(differentChannels) == "nil",
                "negativeWeight": slot(negativeWeight) == "nil",
                "dynamicLoop": slot(dynamicLoop) == "nil",
                "extraSampler": slot(extraSampler) == "nil",
                "indexWrite": slot(indexWrite) == "nil",
                "branch": slot(branch) == "nil",
                "helperDifferentChannels": slot(helperDifferentChannels) == "nil",
                "helperNegativeWeight": slot(helperNegativeWeight) == "nil",
                "helperDynamicLoop": slot(helperDynamicLoop) == "nil",
                "helperBranch": slot(helperBranch) == "nil",
            ],
            artifactProofs: [
                "nestedWholeCarrier":
                    SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer
                        .validates(artifactSource(), expectedSlot: 0),
                "renamedSlot":
                    SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer
                        .validates(artifactSource(slot: 5), expectedSlot: 5),
                "memberCarrierRejected":
                    !SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer
                        .validates(
                            artifactSource(output: "albedo.xyz * uniforms.g_Intensity"),
                            expectedSlot: 0
                        ),
                "secondCarrierRejected":
                    !SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer
                        .validates(
                            artifactSource(output: "albedo * extra * 0.1"),
                            expectedSlot: 0
                        ),
                "vectorFactorRejected":
                    !SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer
                        .validates(
                            artifactSource(output: "albedo * uniforms.g_ColorRays"),
                            expectedSlot: 0
                        ),
                "callFactorRejected":
                    !SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer
                        .validates(
                            artifactSource(output: "albedo * sin(uniforms.g_Intensity)"),
                            expectedSlot: 0
                        ),
                "wrongSlotRejected":
                    !SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer
                        .validates(artifactSource(), expectedSlot: 2),
                "extraSampleRejected":
                    !SceneGenericShaderRGBA8UNormIndependentSignalArtifactAnalyzer
                        .validates(
                            artifactSource(extraSample: true), expectedSlot: 0
                        ),
            ],
            expectedTransfer:
                String(data: expectedTransferData, encoding: .utf8)!,
            expectedTransferCacheKey: expectedTransfer.cacheKey,
            profile: selected.rawValue,
            route: selected.defaultRouteState.rawValue,
            rollback: selected.validatedRollbackOwner.rawValue,
            targetFactRequired: profile(outputIsRGBA8Unorm: false) != selected,
            graphRoleRequired: profile(graphTextureSlots: []) != selected,
            sourceRoleRequired: profile(graphInputTextureSlots: []) != selected,
            graphOnlySamplerRequired:
                profile(hasOnlyGraphInputSampler: false) != selected,
            externalProviderRejected: profile(external: true) != selected,
            preservedRGBARejected:
                profile(producesPreservedRGBAOutput: true) != selected
        )
        print(String(data: try JSONEncoder().encode(output), encoding: .utf8)!)
    }
}
'''


class SceneIndependentSignalUNormAccumulatorTests(unittest.TestCase):
    def test_source_and_typed_target_route_contract(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-independent-signal-unorm-accumulator-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            binary = root / "harness"
            harness.write_text(HARNESS, encoding="utf-8")
            compiled = subprocess.run(
                [
                    "xcrun", "swiftc", "-O", "-o", str(binary),
                    *(str(path) for path in SWIFT_SOURCES), str(harness),
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                capture_output=True,
                check=False,
                timeout=240,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run(
                [str(binary)],
                cwd=REPOSITORY_ROOT,
                text=True,
                capture_output=True,
                check=False,
                timeout=60,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            result = json.loads(run.stdout)

        self.assertEqual(result["positiveSlots"], {
            "structural": "0", "renamed": "3",
            "helper": "0", "renamedHelper": "5",
        })
        self.assertEqual(result["positiveWork"], {
            "structural": 30, "renamed": 30,
            "helper": 32, "renamedHelper": 32,
        })
        self.assertEqual(json.loads(result["expectedTransfer"]), {
            "kind": "independent-alpha-signal-preserving",
            "slot": 0,
            "accumulatorLoopWork": 32,
            "usesRGBA8UnormAttachmentBoundary": True,
        })
        self.assertEqual(
            result["expectedTransferCacheKey"],
            "independent-alpha-signal-preserving:0:accumulator:32:rgba8-unorm",
        )
        for key, value in result["negativeSourceProofs"].items():
            self.assertTrue(value, key)
        for key, value in result["artifactProofs"].items():
            self.assertTrue(value, key)
        for key, value in result.items():
            if isinstance(value, bool):
                self.assertTrue(value, key)
        self.assertEqual(
            result["profile"],
            "source-proven-graph-target-independent-signal-unorm-accumulator",
        )
        self.assertEqual(result["route"], "generic-only")
        self.assertEqual(result["rollback"], "bounded-frontend")


if __name__ == "__main__":
    unittest.main()

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
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift",
]


HARNESS = r'''
import Foundation

private struct Output: Codable {
    let positiveSlots: [String: String]
    let positiveWork: [String: Int]
    let explicitClampProofUnaffected: Bool
    let negativeSourceProofs: [String: Bool]
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

private func slot(_ source: String) -> String {
    SceneAuthoredShaderIndependentSignalInlineAccumulatorAnalyzer
        .rgba8UnormAttachmentSourceSlot(fragmentSource: source)
        .map(String.init) ?? "nil"
}

private func work(_ source: String) -> Int? {
    SceneAuthoredShaderIndependentSignalInlineAccumulatorAnalyzer
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
        let selected = profile()
        let output = Output(
            positiveSlots: [
                "structural": slot(structural),
                "renamed": slot(renamed),
            ],
            positiveWork: [
                "structural": work(structural) ?? -1,
                "renamed": work(renamed) ?? -1,
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
            ],
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
        })
        self.assertEqual(result["positiveWork"], {
            "structural": 30, "renamed": 30,
        })
        for key, value in result["negativeSourceProofs"].items():
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

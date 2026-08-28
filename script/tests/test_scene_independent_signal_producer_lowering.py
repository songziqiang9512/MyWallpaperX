#!/usr/bin/env python3

"""Independent-signal producer lowering, artifact, and route contract."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from script.scene_swift_source_sets import scene_swift_sources


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCENE_ROOT = REPOSITORY_ROOT / "MyWallpaperX/Core/SteamWorkshopScene"
SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
]


HARNESS = r'''
import CryptoKit
import Foundation

private struct Output: Codable {
    let sourceTransfer: Bool
    let renamedSourceTransfer: Bool
    let builderAccepted: Bool
    let inputBoundaryInserted: Bool
    let outputLeftRaw: Bool
    let decoderAccepted: Bool
    let preservingTamperRejected: Bool
    let wrongSlotRejected: Bool
    let unresolvedPromotionRejected: Bool
    let secondWholeSampleRejected: Bool
    let wrongInputSlotRejected: Bool
    let hiddenOutputWriteRejected: Bool
    let producerProfile: String
    let producerRoute: String
    let producerRollback: String
    let providerBackedProducerProfile: String
    let providerBackedProducerRoute: String
    let additionalGraphInputProducerProfile: String
    let additionalGraphInputProducerRoute: String
    let accumulatorProfile: String
    let accumulatorRoute: String
    let accumulatorRollback: String
}

private let authored = """
uniform sampler2D g_Texture0;
uniform sampler2D g_Texture2;
varying vec2 v_TexCoord;
void main() {
    vec4 carrier = texSample2D(g_Texture0, v_TexCoord);
    float noise = texSample2D(g_Texture2, v_TexCoord).r
        * texSample2D(g_Texture2, v_TexCoord * 0.5).r;
    carrier.rgb *= carrier.a;
    carrier.a = 1.0;
    gl_FragColor = carrier * step(0.5, carrier.r);
    gl_FragColor.a *= noise;
}
"""

private let msl = """
#include <metal_stdlib>
using namespace metal;
struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment() {
    Output out = {};
    float4 translatedCarrier = g_Texture0.sample(g_Texture0Smplr, uv);
    float noise = g_Texture2.sample(g_Texture2Smplr, uv).x
        * g_Texture2.sample(g_Texture2Smplr, uv * 0.5).x;
    float alpha = translatedCarrier.w;
    float3 rgb = translatedCarrier.xyz * alpha;
    translatedCarrier.x = rgb.x;
    translatedCarrier.y = rgb.y;
    translatedCarrier.z = rgb.z;
    translatedCarrier.w = 1.0;
    out.mwxFragColor = translatedCarrier * step(0.5, translatedCarrier.x);
    out.mwxFragColor.w *= noise;
    return out;
}
"""

private func prepared(_ source: String) -> (
    msl: String,
    transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
)? {
    try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
        msl: source,
        authoredSource: authored
    )
}

private func artifact(
    source: String,
    transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
) -> SceneGenericShaderProgramArtifact {
    SceneGenericShaderProgramArtifact(
        backendID: "glslang-spirv-cross-msl-v2",
        requestKey: String(repeating: "a", count: 64),
        program: .init(
            metalSource: source,
            metalSourceSHA256: SHA256.hash(data: Data(source.utf8))
                .map { String(format: "%02x", $0) }.joined(),
            vertexFunctionName: "mwxGenericVertex",
            fragmentFunctionName: "mwxGenericFragment",
            uniformBufferIndex: 8,
            uniformLayout: .init(fields: [
                .init(name: "mwxRenderSize", authoredName: "mwxRenderSize",
                      type: "float2", offset: 0),
                .init(name: "mwxTexture0Transform0",
                      authoredName: "mwxTexture0Transform0",
                      type: "float4", offset: 16),
                .init(name: "mwxTexture0Transform1",
                      authoredName: "mwxTexture0Transform1",
                      type: "float4", offset: 32),
                .init(name: "mwxTexture2Transform0",
                      authoredName: "mwxTexture2Transform0",
                      type: "float4", offset: 48),
                .init(name: "mwxTexture2Transform1",
                      authoredName: "mwxTexture2Transform1",
                      type: "float4", offset: 64),
            ], byteSize: 80),
            textureBindings: [
                .init(name: "g_Texture0", slot: 0, channelUse: "wholeVector"),
                .init(name: "g_Texture2", slot: 2, channelUse: "redOnly"),
            ],
            staticLoopWork: 0,
            colorTransfer: transfer,
            fragmentOutputChannelUse: "unproven"
        )
    )
}

private func decoded(
    _ artifact: SceneGenericShaderProgramArtifact,
    expected: SceneShaderColorTransfer
) -> SceneAuthoredShaderProgram? {
    artifact.makeProgram(
        expectedKey: String(repeating: "a", count: 64),
        expectedColorTransfer: expected,
        expectedFragmentOutputChannelUse: .unproven
    )
}

private func makeProducerProfile(
    hasExternalProviderTexture: Bool,
    graphInputTextureSlots: Set<Int>
) -> SceneGenericShaderCapabilityProfile {
    SceneGenericShaderCapabilityProfile(
        colorTransfer: .independentAlphaSignal(textureSlot: 0),
        alphaAttenuationSourceSlot: nil,
        colorBlendSourceSlot: nil,
        conditionalStraightUnionSourceSlot: nil,
        singleSamplerAlphaMutationSourceSlot: nil,
        sameSlotChannelReconstructionSourceSlot: nil,
        auxiliaryRGBMixSourceSlot: nil,
        normalizedSampleSumSourceSlot: nil,
        independentSignalAccumulatorSourceSlot: nil,
        alphaWeightedSampleAverageSourceSlot: nil,
        preservedAlphaRGBFilterSourceSlot: nil,
        preservedAlphaRGBFilterTextureSlots: [],
        unitCompositeBlurredSlot: nil,
        unitCompositePreviousSlot: nil,
        hasExternalProviderTexture: hasExternalProviderTexture,
        producesScalarRedOutput: false,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: [],
        graphInputTextureSlots: graphInputTextureSlots,
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasOnlyGraphInputSampler: false,
        hasStageScopedUniformBindings: true,
        hasStereoAudioSpectrumArrays: false
    )
}

@main
private enum Harness {
    static func main() throws {
        let built = prepared(msl)
        let accepted = built.map { artifact(
            source: $0.msl,
            transfer: $0.transfer
        ) }
        let producerProfile = makeProducerProfile(
            hasExternalProviderTexture: false,
            graphInputTextureSlots: [0]
        )
        let providerBackedProducerProfile = makeProducerProfile(
            hasExternalProviderTexture: true,
            graphInputTextureSlots: [0]
        )
        let additionalGraphInputProducerProfile = makeProducerProfile(
            hasExternalProviderTexture: false,
            graphInputTextureSlots: [0, 7]
        )
        let accumulatorProfile = SceneGenericShaderCapabilityProfile(
            colorTransfer: .independentAlphaSignalPreserving(textureSlot: 0),
            alphaAttenuationSourceSlot: nil,
            colorBlendSourceSlot: nil,
            conditionalStraightUnionSourceSlot: nil,
            singleSamplerAlphaMutationSourceSlot: nil,
            sameSlotChannelReconstructionSourceSlot: nil,
            auxiliaryRGBMixSourceSlot: nil,
            normalizedSampleSumSourceSlot: nil,
            independentSignalAccumulatorSourceSlot: 0,
            alphaWeightedSampleAverageSourceSlot: nil,
            preservedAlphaRGBFilterSourceSlot: nil,
            preservedAlphaRGBFilterTextureSlots: [],
            unitCompositeBlurredSlot: nil,
            unitCompositePreviousSlot: nil,
            hasExternalProviderTexture: false,
            producesScalarRedOutput: false,
            isSourceIndependentPremultipliedOutput: false,
            graphTextureSlots: [0],
            graphInputTextureSlots: [0],
            r8TextureSlots: [],
            hasDefaultedOpacityMaskSampler: false,
            hasOnlyGraphInputSampler: true,
            hasStageScopedUniformBindings: true,
            hasStereoAudioSpectrumArrays: false
        )
        let tampered = built.map {
            artifact(
                source: $0.msl,
                transfer: .init(
                    kind: "independent-alpha-signal-preserving",
                    slot: 0,
                    slots: nil
                )
            )
        }
        let output = Output(
            sourceTransfer: SceneAuthoredShaderColorTransferAnalyzer.analyze(
                fragmentSource: authored
            ) == .independentAlphaSignal(textureSlot: 0),
            renamedSourceTransfer:
                SceneAuthoredShaderColorTransferAnalyzer.analyze(
                    fragmentSource: authored.replacingOccurrences(
                        of: "carrier", with: "unseenSignal"
                    )
                ) == .independentAlphaSignal(textureSlot: 0),
            builderAccepted: built?.transfer.kind
                == "independent-alpha-signal" && built?.transfer.slot == 0,
            inputBoundaryInserted: built?.msl.contains(
                "mwxGenericIndependentSignalUnpremultiply(g_Texture0.sample"
            ) == true,
            outputLeftRaw: built?.msl.contains(
                "out.mwxFragColor = translatedCarrier * step"
            ) == true && built?.msl.localizedCaseInsensitiveContains(
                "premultiply(out.mwxFragColor"
            ) == false,
            decoderAccepted: accepted.flatMap {
                decoded($0, expected: .independentAlphaSignal(textureSlot: 0))
            }?.colorTransfer == .independentAlphaSignal(textureSlot: 0),
            preservingTamperRejected: tampered.flatMap {
                decoded($0, expected: .independentAlphaSignal(textureSlot: 0))
            } == nil,
            wrongSlotRejected: accepted.flatMap {
                decoded($0, expected: .independentAlphaSignal(textureSlot: 7))
            } == nil,
            unresolvedPromotionRejected: accepted.flatMap {
                decoded($0, expected: .unresolved)
            } == nil,
            secondWholeSampleRejected: prepared(msl.replacingOccurrences(
                of: "    float noise =",
                with: "    float4 hidden = g_Texture2.sample(g_Texture2Smplr, uv);\n    float noise ="
            )) == nil,
            wrongInputSlotRejected: prepared(msl.replacingOccurrences(
                of: "float4 translatedCarrier = g_Texture0.sample",
                with: "float4 translatedCarrier = g_Texture1.sample"
            )) == nil,
            hiddenOutputWriteRejected: prepared(msl.replacingOccurrences(
                of: "    out.mwxFragColor.w *= noise;",
                with: "    out.mwxFragColor.xyz *= noise;"
            )) == nil,
            producerProfile: producerProfile.rawValue,
            producerRoute: producerProfile.defaultRouteState.rawValue,
            producerRollback: producerProfile.validatedRollbackOwner.rawValue,
            providerBackedProducerProfile:
                providerBackedProducerProfile.rawValue,
            providerBackedProducerRoute:
                providerBackedProducerProfile.defaultRouteState.rawValue,
            additionalGraphInputProducerProfile:
                additionalGraphInputProducerProfile.rawValue,
            additionalGraphInputProducerRoute:
                additionalGraphInputProducerProfile.defaultRouteState.rawValue,
            accumulatorProfile: accumulatorProfile.rawValue,
            accumulatorRoute: accumulatorProfile.defaultRouteState.rawValue,
            accumulatorRollback:
                accumulatorProfile.validatedRollbackOwner.rawValue
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


class SceneIndependentSignalProducerLoweringTests(unittest.TestCase):
    def test_producer_lowering_artifact_and_route_contract(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-independent-signal-producer-"
        ) as directory:
            root = Path(directory)
            harness = root / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            binary = root / "producer-harness"
            completed = subprocess.run(
                [
                    "xcrun", "swiftc", "-O", "-o", str(binary),
                    *[str(path) for path in SWIFT_SOURCES], str(harness),
                ],
                cwd=REPOSITORY_ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            output = json.loads(subprocess.run(
                [str(binary)], cwd=REPOSITORY_ROOT, check=True,
                capture_output=True, text=True,
            ).stdout)

        for key in (
            "sourceTransfer", "renamedSourceTransfer", "builderAccepted",
            "inputBoundaryInserted", "outputLeftRaw", "decoderAccepted",
            "preservingTamperRejected", "wrongSlotRejected",
            "unresolvedPromotionRejected", "secondWholeSampleRejected",
            "wrongInputSlotRejected", "hiddenOutputWriteRejected",
        ):
            self.assertTrue(output[key], (key, output))
        self.assertEqual(
            output["producerProfile"],
            "source-proven-graph-input-independent-signal-producer",
        )
        self.assertEqual(output["producerRoute"], "generic-only")
        self.assertEqual(output["producerRollback"], "bounded-frontend")
        self.assertEqual(output["providerBackedProducerProfile"], "ordinary-shader")
        self.assertEqual(output["providerBackedProducerRoute"], "prefer-generic")
        self.assertEqual(
            output["additionalGraphInputProducerProfile"], "ordinary-shader",
        )
        self.assertEqual(output["additionalGraphInputProducerRoute"], "prefer-generic")
        self.assertEqual(
            output["accumulatorProfile"],
            "source-proven-graph-target-independent-signal-accumulator",
        )
        self.assertEqual(output["accumulatorRoute"], "generic-only")
        self.assertEqual(output["accumulatorRollback"], "bounded-frontend")


if __name__ == "__main__":
    unittest.main()

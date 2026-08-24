#!/usr/bin/env python3

"""Exact ordered signal/color composition across shared shader owners."""

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

from scene_shader_compiler_artifact import request_cache_key  # noqa: E402
from scene_shader_compiler_color_transfer_contract import (  # noqa: E402
    IndependentSignalContractFailure,
    parse_expected_transfer,
    prepare_independent_signal_contract,
)
from scene_swift_source_sets import scene_swift_sources  # noqa: E402
from script.tests import test_scene_shader_compiler_harness as compiler_support  # noqa: E402


SWIFT_SOURCES = [
    *scene_swift_sources("authored_shader_frontend_core"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderProgramArtifact.swift",
    *scene_swift_sources("generic_shader_compiler_preparation_implementation"),
    SCENE_ROOT
    / "RenderGraph/MaterialProgram/SceneResolvedMaterialGenericShaderRouteProfile.swift",
]


HARNESS = r'''
import CryptoKit
import Foundation

private struct Output: Codable {
    let renamedPositive: Bool
    let unseenPositive: Bool
    let implicitSampleRejected: Bool
    let reversedRolesRejected: Bool
    let wrongAlphaRejected: Bool
    let wrongFactorRejected: Bool
    let extraOutputRejected: Bool
    let controlFlowRejected: Bool
    let extraSampleRejected: Bool
    let sameSlotRejected: Bool
    let builderAccepted: Bool
    let colorBoundaryInserted: Bool
    let signalLeftRaw: Bool
    let outputBoundaryInserted: Bool
    let compilerImplicitSampleRejected: Bool
    let compilerReversedCarrierRejected: Bool
    let compilerExtraOutputRejected: Bool
    let compilerControlFlowRejected: Bool
    let decoderAccepted: Bool
    let decoderReversedOrderRejected: Bool
    let decoderWrongExpectedRejected: Bool
    let expectedEncodingOrdered: Bool
    let profile: String
    let route: String
    let rollback: String
    let externalProviderRejected: Bool
    let scalarOutputRejected: Bool
    let wrongGraphRoleRejected: Bool
}

private func source(
    signalSlot: Int = 6,
    colorSlot: Int = 2,
    mode: Int = 7,
    signalName: String = "pulseValue",
    colorName: String = "canvasValue",
    blendSignal: String? = nil,
    alpha: String? = nil,
    factor: String? = nil,
    output: String? = nil,
    prefix: String = "",
    suffix: String = ""
) -> String {
    let blendSignal = blendSignal ?? signalName
    let alpha = alpha ?? "\(colorName).a = saturate(\(colorName).a + \(signalName).a);"
    let factor = factor ?? "\(signalName).a"
    let output = output ?? "gl_FragColor = \(colorName);"
    return """
uniform sampler2D g_Texture\(signalSlot);
uniform sampler2D g_Texture\(colorSlot);
varying vec2 v_TexCoord;
void main() {
    \(prefix)
    vec4 \(signalName) = texSample2D(g_Texture\(signalSlot), v_TexCoord);
    vec4 \(colorName) = texSample2D(g_Texture\(colorSlot), v_TexCoord);
    \(colorName).rgb = ApplyBlending(\(mode), \(colorName).rgb, \(blendSignal).rgb, \(factor));
    \(alpha)
    \(output)
    \(suffix)
}
"""
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
    float4 translatedPulse = g_Texture6.sample(g_Texture6Smplr, uv);
    float4 translatedCanvas = g_Texture2.sample(g_Texture2Smplr, uv);
    translatedCanvas.xyz = translatedCanvas.xyz + translatedPulse.xyz * translatedPulse.w;
    translatedCanvas.w = clamp(translatedCanvas.w + translatedPulse.w, 0.0, 1.0);
    out.mwxFragColor = translatedCanvas;
    return out;
}
"""

private func prepared(_ metal: String) -> (
    msl: String,
    transfer: SceneGenericShaderProgramArtifact.Program.ColorTransfer
)? {
    try? SceneGenericShaderArtifactBuilder.prepareColorTransfer(
        msl: metal,
        authoredSource: authored
    )
}

private func artifact(
    source: String,
    slots: [Int]
) -> SceneGenericShaderProgramArtifact {
    SceneGenericShaderProgramArtifact(
        backendID: "glslang-spirv-cross-msl-v2",
        requestKey: String(repeating: "b", count: 64),
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
                .init(name: "mwxTexture2Transform0",
                      authoredName: "mwxTexture2Transform0",
                      type: "float4", offset: 16),
                .init(name: "mwxTexture2Transform1",
                      authoredName: "mwxTexture2Transform1",
                      type: "float4", offset: 32),
                .init(name: "mwxTexture6Transform0",
                      authoredName: "mwxTexture6Transform0",
                      type: "float4", offset: 48),
                .init(name: "mwxTexture6Transform1",
                      authoredName: "mwxTexture6Transform1",
                      type: "float4", offset: 64),
            ], byteSize: 80),
            textureBindings: [
                .init(name: "g_Texture2", slot: 2, channelUse: "wholeVector"),
                .init(name: "g_Texture6", slot: 6, channelUse: "wholeVector"),
            ],
            staticLoopWork: 0,
            colorTransfer: .init(
                kind: "independent-alpha-signal-compositing",
                slot: nil,
                slots: slots
            ),
            fragmentOutputChannelUse: "unproven"
        )
    )
}

private func decoded(
    _ artifact: SceneGenericShaderProgramArtifact,
    expected: SceneShaderColorTransfer
) -> SceneAuthoredShaderProgram? {
    artifact.makeProgram(
        expectedKey: String(repeating: "b", count: 64),
        expectedColorTransfer: expected,
        expectedFragmentOutputChannelUse: .unproven
    )
}

private func profile(
    transfer: SceneShaderColorTransfer = .independentAlphaSignalCompositing(
        signalSlot: 6, colorSlot: 2
    ),
    external: Bool = false,
    scalarOutput: Bool = false,
    graphTextureSlots: Set<Int> = [6]
) -> SceneGenericShaderCapabilityProfile {
    SceneGenericShaderCapabilityProfile(
        colorTransfer: transfer,
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
        unitCompositeBlurredSlot: nil,
        unitCompositePreviousSlot: nil,
        hasExternalProviderTexture: external,
        producesScalarRedOutput: scalarOutput,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: graphTextureSlots,
        graphInputTextureSlots: [6, 2],
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasStageScopedUniformBindings: false,
        hasStereoAudioSpectrumArrays: false,
        hasLocalizedMutableFragmentVarying: false
    )
}

@main
private enum Harness {
    static func main() throws {
        let built = prepared(msl)
        let accepted = built.map { artifact(source: $0.msl, slots: [6, 2]) }
        let reversed = built.map { artifact(source: $0.msl, slots: [2, 6]) }
        let selected = profile()
        let expected = SceneGenericShaderExpectedColorTransfer(
            .independentAlphaSignalCompositing(signalSlot: 6, colorSlot: 2)
        )!
        let encoded = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(expected)
        ) as! [String: Any]

        let implicitMetal = msl.replacingOccurrences(
            of: "float4 translatedPulse = g_Texture6.sample(g_Texture6Smplr, uv);",
            with: "float4 translatedPulse = float4(g_Texture6.sample(g_Texture6Smplr, uv));"
        )
        let reversedCarrier = msl.replacingOccurrences(
            of: "out.mwxFragColor = translatedCanvas;",
            with: "out.mwxFragColor = translatedPulse;"
        )
        let extraOutput = msl.replacingOccurrences(
            of: "out.mwxFragColor = translatedCanvas;",
            with: "out.mwxFragColor = translatedCanvas;\n    out.mwxFragColor.w = 1.0;"
        )
        let controlled = msl.replacingOccurrences(
            of: "translatedCanvas.xyz =",
            with: "if (translatedPulse.w > 0.0) translatedCanvas.xyz ="
        )

        let output = Output(
            renamedPositive: transfer(authored) == .independentAlphaSignalCompositing(
                signalSlot: 6, colorSlot: 2
            ),
            unseenPositive: transfer(source(
                signalSlot: 1, colorSlot: 5, mode: 32,
                signalName: "quietCarrier", colorName: "surfaceCarrier"
            )) == .independentAlphaSignalCompositing(signalSlot: 1, colorSlot: 5),
            implicitSampleRejected: transfer(source(prefix:
                "vec4 hiddenValue = vec4(0.0);"
            )) == .unresolved,
            reversedRolesRejected: transfer(source(
                blendSignal: "canvasValue"
            )) == .unresolved,
            wrongAlphaRejected: transfer(source(alpha:
                "canvasValue.a = saturate(canvasValue.a - pulseValue.a);"
            )) == .unresolved,
            wrongFactorRejected: transfer(source(factor:
                "canvasValue.a"
            )) == .unresolved,
            extraOutputRejected: transfer(source(suffix:
                "gl_FragColor = pulseValue;"
            )) == .unresolved,
            controlFlowRejected: transfer(source(prefix:
                "if (v_TexCoord.x < 0.0) { discard; }"
            )) == .unresolved,
            extraSampleRejected: transfer(source(prefix:
                "vec4 extraValue = texSample2D(g_Texture6, v_TexCoord * 0.5);"
            )) == .unresolved,
            sameSlotRejected: transfer(source(
                signalSlot: 2, colorSlot: 2
            )) == .unresolved,
            builderAccepted: built?.transfer.kind
                == "independent-alpha-signal-compositing"
                && built?.transfer.slots == [6, 2],
            colorBoundaryInserted: built?.msl.contains(
                "mwxGenericSignalCompositeUnpremultiply(g_Texture2.sample"
            ) == true,
            signalLeftRaw: built?.msl.contains(
                "translatedPulse = g_Texture6.sample"
            ) == true,
            outputBoundaryInserted: built?.msl.contains(
                "out.mwxFragColor = mwxGenericSignalCompositePremultiply(translatedCanvas);"
            ) == true,
            compilerImplicitSampleRejected: prepared(implicitMetal) == nil,
            compilerReversedCarrierRejected: prepared(reversedCarrier) == nil,
            compilerExtraOutputRejected: prepared(extraOutput) == nil,
            compilerControlFlowRejected: prepared(controlled) == nil,
            decoderAccepted: accepted.flatMap {
                decoded($0, expected: .independentAlphaSignalCompositing(
                    signalSlot: 6, colorSlot: 2
                ))
            } != nil,
            decoderReversedOrderRejected: reversed.flatMap {
                decoded($0, expected: .independentAlphaSignalCompositing(
                    signalSlot: 6, colorSlot: 2
                ))
            } == nil,
            decoderWrongExpectedRejected: accepted.flatMap {
                decoded($0, expected: .independentAlphaSignalCompositing(
                    signalSlot: 2, colorSlot: 6
                ))
            } == nil,
            expectedEncodingOrdered: encoded["kind"] as? String
                == "independent-alpha-signal-compositing"
                && encoded["slots"] as? [Int] == [6, 2]
                && encoded["slot"] == nil,
            profile: selected.rawValue,
            route: selected.defaultRouteState.rawValue,
            rollback: selected.validatedRollbackOwner.rawValue,
            externalProviderRejected: profile(external: true) != selected,
            scalarOutputRejected: profile(scalarOutput: true) != selected,
            wrongGraphRoleRejected: profile(graphTextureSlots: [2]) != selected
        )
        print(String(data: try JSONEncoder().encode(output), encoding: .utf8)!)
    }
}
'''


class SceneIndependentSignalColorCarrierCompositingTests(unittest.TestCase):
    def test_swift_frontend_artifact_and_route_contract(self) -> None:
        with tempfile.TemporaryDirectory(
            prefix="mwx-signal-color-compositing-"
        ) as directory:
            executable = Path(directory) / "harness"
            harness = Path(directory) / "Harness.swift"
            harness.write_text(HARNESS, encoding="utf-8")
            completed = subprocess.run(
                [
                    "xcrun", "swiftc", "-O", "-o", str(executable),
                    *(str(path) for path in SWIFT_SOURCES), str(harness),
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            run = subprocess.run(
                [str(executable)], cwd=REPOSITORY_ROOT,
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            result = json.loads(run.stdout)

        expected_true = {
            key for key, value in result.items() if isinstance(value, bool)
        }
        self.assertTrue(expected_true)
        for key in expected_true:
            self.assertTrue(result[key], key)
        self.assertEqual(
            result["profile"],
            "source-proven-graph-input-independent-signal-compositing",
        )
        self.assertEqual(result["route"], "generic-only")
        self.assertEqual(result["rollback"], "bounded-frontend")

    def test_external_contract_preserves_order_and_rejects_drift(self) -> None:
        expected = {
            "kind": "independent-alpha-signal-compositing", "slots": [6, 2],
        }
        self.assertEqual(parse_expected_transfer(expected), expected)
        bindings = [
            {"name": "g_Texture2", "slot": 2},
            {"name": "g_Texture6", "slot": 6},
        ]
        source = """
#include <metal_stdlib>
using namespace metal;
struct Output { float4 mwxFragColor [[color(0)]]; };
fragment Output mwxGenericFragment() {
    Output out = {};
    float4 firstCarrier = g_Texture6.sample(sampler(), uv);
    float4 secondCarrier = g_Texture2.sample(sampler(), uv);
    secondCarrier.xyz += firstCarrier.xyz * firstCarrier.w;
    secondCarrier.w = clamp(secondCarrier.w + firstCarrier.w, 0.0, 1.0);
    out.mwxFragColor = secondCarrier;
    return out;
}
"""
        prepared, transfer = prepare_independent_signal_contract(
            source, expected, bindings,
        )
        self.assertEqual(transfer, expected)
        self.assertIn(
            "mwxSignalCompositeUnpremultiply(g_Texture2.sample", prepared
        )
        self.assertIn("firstCarrier = g_Texture6.sample", prepared)
        self.assertIn(
            "out.mwxFragColor = mwxSignalCompositePremultiply(secondCarrier);",
            prepared,
        )

        reflection = {
            "types": {"_1": {"members": [
                {"name": "mwxRenderSize", "type": "vec2", "offset": 0},
            ]}},
            "ubos": [{
                "type": "_1", "block_size": 8, "set": 0, "binding": 8,
            }],
            "textures": [
                {"name": "g_Texture2", "binding": 2},
                {"name": "g_Texture6", "binding": 6},
            ],
        }
        uniform = "struct MWXUniforms { float2 mwxRenderSize; };"
        vertex_msl = "\n".join([
            "#include <metal_stdlib>", "using namespace metal;", uniform,
            "vertex float4 mwxGenericVertex(constant MWXUniforms& uniforms "
            "[[buffer(8)]]) { return float4(uniforms.mwxRenderSize, 0.0, 1.0); }",
        ])
        fragment_msl = source.replace(
            "struct Output", uniform + "\nstruct Output"
        ).replace(
            "fragment Output mwxGenericFragment()",
            "fragment Output mwxGenericFragment(constant MWXUniforms& uniforms "
            "[[buffer(8)]])",
        )
        arguments = compiler_support.artifact_arguments(
            reflection, vertex_msl, fragment_msl, "c"
        )
        arguments["expected_color_transfer"] = expected
        artifact = compiler_support.build_program_artifact(**arguments)
        self.assertEqual(artifact["program"]["colorTransfer"], expected)
        self.assertIn(
            "mwxSignalCompositeUnpremultiply(g_Texture2.sample",
            artifact["program"]["metalSource"],
        )

        reverse = {**expected, "slots": [2, 6]}
        request = {
            "schemaVersion": 4,
            "outputSemantics": "color",
            "stages": [
                {"stage": "vertex", "source": "void main() {}"},
                {"stage": "fragment", "source": "void main() {}"},
            ],
            "expectedColorTransfer": expected,
        }
        reverse_request = {**request, "expectedColorTransfer": reverse}
        self.assertNotEqual(
            request_cache_key(request), request_cache_key(reverse_request)
        )

        malformed = [
            {"kind": expected["kind"], "slots": [6, 6]},
            {"kind": expected["kind"], "slots": [6]},
            {"kind": expected["kind"], "slots": [6, 2], "slot": 6},
            {"kind": "unknown", "slots": [6, 2]},
        ]
        for value in malformed:
            with self.subTest(value=value):
                with self.assertRaises(IndependentSignalContractFailure):
                    parse_expected_transfer(value)

        drift = {
            "implicit-sample": source.replace(
                "float4 firstCarrier = g_Texture6.sample(sampler(), uv);",
                "float4 firstCarrier = float4(g_Texture6.sample(sampler(), uv));",
            ),
            "reversed-carrier": source.replace(
                "out.mwxFragColor = secondCarrier;",
                "out.mwxFragColor = firstCarrier;",
            ),
            "extra-output": source.replace(
                "out.mwxFragColor = secondCarrier;",
                "out.mwxFragColor = secondCarrier;\n    out.mwxFragColor.w = 1.0;",
            ),
            "control-flow": source.replace(
                "secondCarrier.xyz +=",
                "if (firstCarrier.w > 0.0) secondCarrier.xyz +=",
            ),
            "extra-sample": source.replace(
                "secondCarrier.xyz +=",
                "float4 extraCarrier = g_Texture6.sample(sampler(), uv);\n"
                "    secondCarrier.xyz +=",
            ),
        }
        for name, value in drift.items():
            with self.subTest(name=name):
                with self.assertRaises(IndependentSignalContractFailure):
                    prepare_independent_signal_contract(value, expected, bindings)
        with self.assertRaises(IndependentSignalContractFailure):
            prepare_independent_signal_contract(source, reverse, bindings)


if __name__ == "__main__":
    unittest.main()

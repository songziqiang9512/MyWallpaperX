#!/usr/bin/env python3

"""RGB-blend scalar-alpha ownership stays source-proven and identity-free."""

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
    let staticSourceSlot: Int?
    let staticAuxiliarySlots: [Int]?
    let audioSourceSlot: Int?
    let audioAuxiliarySlots: [Int]?
    let maskedScalarAuxiliarySlots: [Int]?
    let maskedMaskSlot: Int?
    let multiScalarAuxiliarySlots: [Int]?
    let multiMaskSlot: Int?
    let renamedAccepted: Bool
    let staticTransferAccepted: Bool
    let audioTransferAccepted: Bool
    let staticLoweringAccepted: Bool
    let audioLoweringAccepted: Bool
    let renamedLoweringAccepted: Bool
    let maskedTransferAccepted: Bool
    let maskedLoweringAccepted: Bool
    let multiTransferAccepted: Bool
    let multiLoweringAccepted: Bool
    let modeThreeTransferAccepted: Bool
    let modeThreeLoweringAccepted: Bool
    let saturateTransferAccepted: Bool
    let saturateLoweringAccepted: Bool
    let saturateCompilerTerminalDriftRejected: Bool
    let saturateRouteProfile: String
    let sourceUnpremultipliedOnce: Bool
    let auxiliaryRemainsData: Bool
    let maskRemainsData: Bool
    let outputPremultiplied: Bool
    let differentScalarRejected: Bool
    let alphaAssignmentRejected: Bool
    let alphaAdditionRejected: Bool
    let hiddenSampleRejected: Bool
    let customBlendHelperRejected: Bool
    let sourceBlendModeDriftRejected: Bool
    let missingRGBWriteRejected: Bool
    let missingAlphaWriteRejected: Bool
    let compilerScalarDriftRejected: Bool
    let compilerBlendModeDriftRejected: Bool
    let compilerBaseMultiplierDriftRejected: Bool
    let compilerAuxiliaryDetachedRejected: Bool
    let compilerExtraSampleRejected: Bool
    let sourceMaskOrderRejected: Bool
    let sourceMaskTransformRejected: Bool
    let sourceMaskFactorRejected: Bool
    let compilerMaskSlotRejected: Bool
    let compilerSecondAuxiliaryDetachedRejected: Bool
    let modeThreeHelperDriftRejected: Bool
    let modeThreeFallbackDriftRejected: Bool
    let modeThreeCallModeDriftRejected: Bool
    let staticRouteProfile: String
    let audioRouteProfile: String
    let maskedRouteProfile: String
    let multiRouteProfile: String
    let modeThreeRouteProfile: String
    let renamedRouteProfile: String
    let routeState: String
    let rollbackOwner: String
    let missingTypedPurposeRejected: Bool
    let wrongMaskPurposeRejected: Bool
    let modeThreeMissingMaskPurposeRejected: Bool
    let providerRejected: Bool
    let graphTargetRejected: Bool
    let secondGraphInputRejected: Bool
}

private let staticAuthored = [
    "uniform sampler2D g_Texture0;",
    "uniform sampler2D g_Texture1;",
    "uniform float g_Pulse;",
    "uniform float g_Time;",
    "uniform float g_NoiseAmount;",
    "uniform vec3 g_TintLow;",
    "uniform vec3 g_TintHigh;",
    "varying vec2 v_TexCoord;",
    "vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {",
    "    return mix(base, min(base + blend, CAST3(1.0)), opacity);",
    "    return mix(base, (blend), opacity);",
    "}",
    "void main() {",
    "    vec4 sampled = texSample2D(g_Texture0, v_TexCoord);",
    "    vec4 albedo = sampled;",
    "    float pulse = 0.0;",
    "    pulse = g_Pulse;",
    "    float noise = texSample2D(g_Texture1, vec2(g_Time)).r * g_NoiseAmount;",
    "    pulse += noise;",
    "    pulse = pow(pulse, 1.0);",
    "    albedo.rgb = ApplyBlending(9, albedo.rgb * g_TintLow, albedo.rgb * g_TintHigh, pulse);",
    "    albedo.a *= pulse;",
    "    gl_FragColor = vec4(max(CAST3(0), albedo.rgb), albedo.a);",
    "}",
].joined(separator: "\n")

private let audioAuthored = [
    "uniform sampler2D g_Texture0;",
    "uniform vec3 g_TintLow;",
    "uniform vec3 g_TintHigh;",
    "varying vec2 v_TexCoord;",
    "varying float v_Pulse;",
    "vec3 ApplyBlending(const int mode, in vec3 base, in vec3 blend, in float opacity) {",
    "    return mix(base, min(base + blend, CAST3(1.0)), opacity);",
    "    return mix(base, (blend), opacity);",
    "}",
    "void main() {",
    "    vec4 sampled = texSample2D(g_Texture0, v_TexCoord);",
    "    vec4 albedo = sampled;",
    "    float pulse = 0.0;",
    "    pulse = v_Pulse;",
    "    albedo.rgb = ApplyBlending(9, albedo.rgb * g_TintLow, albedo.rgb * g_TintHigh, pulse);",
    "    albedo.a *= pulse;",
    "    gl_FragColor = vec4(max(CAST3(0), albedo.rgb), albedo.a);",
    "}",
].joined(separator: "\n")

private let staticMSL = [
    "#include <metal_stdlib>",
    "using namespace metal;",
    "fragment void f() {",
    "    float4 sampled = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord);",
    "    float4 albedo = sampled;",
    "    float pulse = 0.0;",
    "    pulse = g_Pulse;",
    "    float noise = g_Texture1.sample(g_Texture1Smplr, in.v_TexCoord).x * g_NoiseAmount;",
    "    pulse += noise;",
    "    pulse = pow(pulse, 1.0);",
    "    float3 param_1 = albedo.xyz * g_TintLow;",
    "    float3 param_2 = albedo.xyz * g_TintHigh;",
    "    float param_3 = pulse;",
    "    float3 blended = ApplyBlending(9, param_1, param_2, param_3);",
    "    albedo.x = blended.x;",
    "    albedo.y = blended.y;",
    "    albedo.z = blended.z;",
    "    albedo.w *= pulse;",
    "    out.mwxFragColor = float4(fast::max(float3(0.0), albedo.xyz), albedo.w);",
    "    return out;",
    "}",
].joined(separator: "\n")

private let audioMSL = [
    "#include <metal_stdlib>",
    "using namespace metal;",
    "fragment void f() {",
    "    float4 sampled = g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord);",
    "    float4 albedo = sampled;",
    "    float pulse = 0.0;",
    "    pulse = in.v_Pulse;",
    "    float3 param_1 = albedo.xyz * g_TintLow;",
    "    float3 param_2 = albedo.xyz * g_TintHigh;",
    "    float param_3 = pulse;",
    "    float3 blended = ApplyBlending(9, param_1, param_2, param_3);",
    "    albedo.x = blended.x;",
    "    albedo.y = blended.y;",
    "    albedo.z = blended.z;",
    "    albedo.w *= pulse;",
    "    out.mwxFragColor = float4(fast::max(float3(0.0), albedo.xyz), albedo.w);",
    "    return out;",
    "}",
].joined(separator: "\n")

private let maskedAuthored = staticAuthored
    .replacingOccurrences(
        of: "uniform sampler2D g_Texture1;",
        with: "uniform sampler2D g_Texture1;\nuniform sampler2D g_Texture2;"
    )
    .replacingOccurrences(
        of: "    albedo.a *= pulse;",
        with: [
            "    albedo.a *= pulse;",
            "    float mask = texSample2D(g_Texture2, v_TexCoord).r;",
            "    albedo = mix(sampled, albedo, mask);",
        ].joined(separator: "\n")
    )

private let maskedMSL = staticMSL.replacingOccurrences(
    of: "    albedo.w *= pulse;",
    with: [
        "    albedo.w *= pulse;",
        "    float mask = g_Texture2.sample(g_Texture2Smplr, in.v_TexCoord).x;",
        "    albedo = mix(sampled, albedo, float4(mask));",
    ].joined(separator: "\n")
)

private let multiAuthored = maskedAuthored
    .replacingOccurrences(
        of: "uniform sampler2D g_Texture2;",
        with: "uniform sampler2D g_Texture2;\nuniform sampler2D g_Texture3;"
    )
    .replacingOccurrences(
        of: "    pulse = g_Pulse;",
        with: [
            "    float phase = texSample2D(g_Texture3, v_TexCoord).r;",
            "    pulse = g_Pulse + phase;",
        ].joined(separator: "\n")
    )

private let multiMSL = maskedMSL
    .replacingOccurrences(
        of: "    pulse = g_Pulse;",
        with: [
            "    float phase = g_Texture3.sample(g_Texture3Smplr, in.v_TexCoord).x;",
            "    pulse = g_Pulse + phase;",
        ].joined(separator: "\n")
    )

private let modeThreeAuthored = multiAuthored
    .replacingOccurrences(
        of: "    return mix(base, min(base + blend, CAST3(1.0)), opacity);",
        with: [
            "    return mix(base, vec3(",
            "        ((blend.r == 0.0) ? blend.r : max((1.0 - ((1.0 - base.r) / blend.r)), 0.0)),",
            "        ((blend.g == 0.0) ? blend.g : max((1.0 - ((1.0 - base.g) / blend.g)), 0.0)),",
            "        ((blend.b == 0.0) ? blend.b : max((1.0 - ((1.0 - base.b) / blend.b)), 0.0))",
            "    ), opacity);",
        ].joined(separator: "\n")
    )
    .replacingOccurrences(of: "ApplyBlending(9,", with: "ApplyBlending(3,")

private let modeThreeMSL = multiMSL.replacingOccurrences(
    of: "ApplyBlending(9,", with: "ApplyBlending(3,"
)

private let saturateAuthored = staticAuthored.replacingOccurrences(
    of: "gl_FragColor = vec4(max(CAST3(0), albedo.rgb), albedo.a);",
    with: "gl_FragColor = saturate(albedo);"
)

private let saturateMSL = staticMSL.replacingOccurrences(
    of: "out.mwxFragColor = float4(fast::max(float3(0.0), albedo.xyz), albedo.w);",
    with: "out.mwxFragColor = fast::clamp(albedo, float4(0.0), float4(1.0));"
)

private func fact(
    _ source: String
) -> SceneAuthoredShaderRGBBlendScalarAlphaAnalyzer.Fact? {
    SceneAuthoredShaderColorTransferAnalyzer.rgbBlendScalarAlphaFact(
        fragmentSource: source
    )
}

private func transferAccepted(_ source: String, slot: Int) -> Bool {
    SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: source)
        == .straightAlpha(textureSlot: slot)
}

private func unormTransferAccepted(_ source: String, slot: Int) -> Bool {
    SceneAuthoredShaderColorTransferAnalyzer.analyze(fragmentSource: source)
        == .straightAlphaUNorm(textureSlot: slot)
}

private func lowered(_ msl: String, authored: String) -> String? {
    guard let prepared = try? SceneGenericShaderArtifactBuilder
        .prepareColorTransfer(msl: msl, authoredSource: authored) else {
        return nil
    }
    return prepared.msl
}

private func profile(
    authored: String,
    active: Set<Int>,
    typed: Set<Int>,
    graphInputs: Set<Int>,
    opacityMasks: Set<Int> = [],
    graphTargets: Set<Int> = [],
    provider: Bool = false
) -> SceneGenericShaderCapabilityProfile {
    SceneGenericShaderCapabilityProfile(
        fragmentSource: authored,
        colorTransfer: SceneAuthoredShaderColorTransferAnalyzer.analyze(
            fragmentSource: authored
        ),
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
        activeTextureSlots: active,
        activeOpacityMaskSlots: opacityMasks,
        typedStaticDataAuxiliarySlots: typed,
        unitCompositeBlurredSlot: nil,
        unitCompositePreviousSlot: nil,
        hasExternalProviderTexture: provider,
        producesScalarRedOutput: false,
        isSourceIndependentPremultipliedOutput: false,
        graphTextureSlots: graphTargets,
        graphInputTextureSlots: graphInputs,
        r8TextureSlots: [],
        hasDefaultedOpacityMaskSampler: false,
        hasStageScopedUniformBindings: false,
        hasStereoAudioSpectrumArrays: false
    )
}

@main
private enum RGBBlendScalarAlphaHarness {
    static func main() throws {
        let renamedAuthored = staticAuthored
            .replacingOccurrences(of: "vec4 sampled =", with: "vec4 origin =")
            .replacingOccurrences(
                of: "vec4 albedo = sampled;", with: "vec4 surface = origin;"
            )
            .replacingOccurrences(of: "albedo", with: "surface")
            .replacingOccurrences(of: "pulse", with: "strength")
            .replacingOccurrences(of: "noise", with: "grain")
        let renamedMSL = staticMSL
            .replacingOccurrences(of: "float4 sampled =", with: "float4 origin =")
            .replacingOccurrences(
                of: "float4 albedo = sampled;", with: "float4 surface = origin;"
            )
            .replacingOccurrences(of: "albedo", with: "surface")
            .replacingOccurrences(of: "pulse", with: "strength")
            .replacingOccurrences(of: "noise", with: "grain")

        let staticFact = fact(staticAuthored)
        let audioFact = fact(audioAuthored)
        let maskedFact = fact(maskedAuthored)
        let multiFact = fact(multiAuthored)
        let staticLowered = lowered(staticMSL, authored: staticAuthored)
        let audioLowered = lowered(audioMSL, authored: audioAuthored)
        let renamedLowered = lowered(renamedMSL, authored: renamedAuthored)
        let maskedLowered = lowered(maskedMSL, authored: maskedAuthored)
        let multiLowered = lowered(multiMSL, authored: multiAuthored)
        let modeThreeLowered = lowered(
            modeThreeMSL, authored: modeThreeAuthored
        )
        let expected = SceneGenericShaderCapabilityProfile
            .sourceProvenGraphInputRGBBlendScalarAlpha
        let staticProfile = profile(
            authored: staticAuthored,
            active: [0, 1], typed: [1], graphInputs: [0]
        )
        let audioProfile = profile(
            authored: audioAuthored,
            active: [0], typed: [], graphInputs: [0]
        )
        let renamedProfile = profile(
            authored: renamedAuthored,
            active: [0, 1], typed: [1], graphInputs: [0]
        )
        let maskedProfile = profile(
            authored: maskedAuthored, active: [0, 1, 2], typed: [1, 2],
            graphInputs: [0], opacityMasks: [2]
        )
        let multiProfile = profile(
            authored: multiAuthored, active: [0, 1, 2, 3],
            typed: [1, 2, 3], graphInputs: [0], opacityMasks: [2]
        )
        let modeThreeProfile = profile(
            authored: modeThreeAuthored, active: [0, 1, 2, 3],
            typed: [1, 2, 3], graphInputs: [0], opacityMasks: [2, 3]
        )
        let saturateProfile = profile(
            authored: saturateAuthored,
            active: [0, 1], typed: [1], graphInputs: [0]
        )
        let hiddenSample = staticAuthored.replacingOccurrences(
            of: "void main() {",
            with: [
                "float hiddenSample(vec2 uv) {",
                "    return texSample2D(g_Texture2, uv).r;",
                "}",
                "void main() {",
            ].joined(separator: "\n")
        )
        let output = Output(
            staticSourceSlot: staticFact?.sourceSlot,
            staticAuxiliarySlots: staticFact?.auxiliarySlots.sorted(),
            audioSourceSlot: audioFact?.sourceSlot,
            audioAuxiliarySlots: audioFact?.auxiliarySlots.sorted(),
            maskedScalarAuxiliarySlots:
                maskedFact?.scalarAuxiliarySlots.sorted(),
            maskedMaskSlot: maskedFact?.maskSlot,
            multiScalarAuxiliarySlots:
                multiFact?.scalarAuxiliarySlots.sorted(),
            multiMaskSlot: multiFact?.maskSlot,
            renamedAccepted: fact(renamedAuthored) != nil,
            staticTransferAccepted: transferAccepted(staticAuthored, slot: 0),
            audioTransferAccepted: transferAccepted(audioAuthored, slot: 0),
            staticLoweringAccepted: staticLowered != nil,
            audioLoweringAccepted: audioLowered != nil,
            renamedLoweringAccepted: renamedLowered != nil,
            maskedTransferAccepted: transferAccepted(maskedAuthored, slot: 0),
            maskedLoweringAccepted: maskedLowered != nil,
            multiTransferAccepted: transferAccepted(multiAuthored, slot: 0),
            multiLoweringAccepted: multiLowered != nil,
            modeThreeTransferAccepted: transferAccepted(
                modeThreeAuthored, slot: 0
            ),
            modeThreeLoweringAccepted: modeThreeLowered != nil,
            saturateTransferAccepted: unormTransferAccepted(
                saturateAuthored, slot: 0
            ),
            saturateLoweringAccepted: lowered(
                saturateMSL, authored: saturateAuthored
            ) != nil,
            saturateCompilerTerminalDriftRejected: lowered(
                saturateMSL.replacingOccurrences(
                    of: "float4(1.0)", with: "float4(2.0)"
                ),
                authored: saturateAuthored
            ) == nil,
            saturateRouteProfile: saturateProfile.rawValue,
            sourceUnpremultipliedOnce: staticLowered?.components(
                separatedBy: "mwxGenericUnpremultiply(g_Texture0.sample("
            ).count == 2,
            auxiliaryRemainsData: staticLowered?.contains(
                "mwxGenericUnpremultiply(g_Texture1.sample("
            ) == false,
            maskRemainsData: maskedLowered?.contains(
                "mwxGenericUnpremultiply(g_Texture2.sample("
            ) == false,
            outputPremultiplied: staticLowered?.contains(
                "out.mwxFragColor = mwxGenericPremultiply(float4("
            ) == true,
            differentScalarRejected: fact(
                staticAuthored.replacingOccurrences(
                    of: "albedo.a *= pulse;", with: "albedo.a *= noise;"
                )
            ) == nil,
            alphaAssignmentRejected: fact(
                staticAuthored.replacingOccurrences(
                    of: "albedo.a *= pulse;", with: "albedo.a = pulse;"
                )
            ) == nil,
            alphaAdditionRejected: fact(
                staticAuthored.replacingOccurrences(
                    of: "albedo.a *= pulse;", with: "albedo.a += pulse;"
                )
            ) == nil,
            hiddenSampleRejected: fact(hiddenSample) == nil,
            customBlendHelperRejected: fact(
                staticAuthored.replacingOccurrences(
                    of: "return mix(base, min(base + blend, CAST3(1.0)), opacity);",
                    with: "return blend;"
                )
            ) == nil,
            sourceBlendModeDriftRejected: fact(
                staticAuthored.replacingOccurrences(
                    of: "ApplyBlending(9,", with: "ApplyBlending(8,"
                )
            ) == nil,
            missingRGBWriteRejected: lowered(
                staticMSL.replacingOccurrences(
                    of: "    albedo.z = blended.z;",
                    with: "    float ignored = blended.z;"
                ),
                authored: staticAuthored
            ) == nil,
            missingAlphaWriteRejected: lowered(
                staticMSL.replacingOccurrences(
                    of: "    albedo.w *= pulse;\n", with: ""
                ),
                authored: staticAuthored
            ) == nil,
            compilerScalarDriftRejected: lowered(
                staticMSL.replacingOccurrences(
                    of: "albedo.w *= pulse;", with: "albedo.w *= noise;"
                ),
                authored: staticAuthored
            ) == nil,
            compilerBlendModeDriftRejected: lowered(
                staticMSL.replacingOccurrences(
                    of: "ApplyBlending(9,", with: "ApplyBlending(8,"
                ),
                authored: staticAuthored
            ) == nil,
            compilerBaseMultiplierDriftRejected: lowered(
                staticMSL.replacingOccurrences(
                    of: "albedo.xyz * g_TintLow",
                    with: "albedo.xyz * g_TintOther"
                ),
                authored: staticAuthored
            ) == nil,
            compilerAuxiliaryDetachedRejected: lowered(
                staticMSL.replacingOccurrences(
                    of: "    pulse += noise;",
                    with: "    float ignoredNoise = noise;"
                ),
                authored: staticAuthored
            ) == nil,
            compilerExtraSampleRejected: lowered(
                staticMSL.replacingOccurrences(
                    of: "    out.mwxFragColor =",
                    with: "    float hidden = g_Texture2.sample(g_Texture2Smplr, in.v_TexCoord).x;\n    out.mwxFragColor ="
                ),
                authored: staticAuthored
            ) == nil,
            sourceMaskOrderRejected: fact(
                maskedAuthored.replacingOccurrences(
                    of: "    albedo.a *= pulse;\n"
                        + "    float mask = texSample2D(g_Texture2, v_TexCoord).r;",
                    with: "    float mask = texSample2D(g_Texture2, v_TexCoord).r;\n"
                        + "    albedo.a *= pulse;"
                )
            ) == nil,
            sourceMaskTransformRejected: fact(
                maskedAuthored.replacingOccurrences(
                    of: "float mask = texSample2D(g_Texture2, v_TexCoord).r;",
                    with: "float mask = texSample2D(g_Texture2, v_TexCoord).r * g_TintLow.r;"
                )
            ) == nil,
            sourceMaskFactorRejected: fact(
                maskedAuthored.replacingOccurrences(
                    of: "albedo = mix(sampled, albedo, mask);",
                    with: "albedo = mix(sampled, albedo, pulse);"
                )
            ) == nil,
            compilerMaskSlotRejected: lowered(
                maskedMSL.replacingOccurrences(
                    of: "g_Texture2.sample(g_Texture2Smplr,",
                    with: "g_Texture1.sample(g_Texture1Smplr,"
                ),
                authored: maskedAuthored
            ) == nil,
            compilerSecondAuxiliaryDetachedRejected: lowered(
                multiMSL.replacingOccurrences(
                    of: "pulse = g_Pulse + phase;",
                    with: "pulse = g_Pulse;"
                ),
                authored: multiAuthored
            ) == nil,
            modeThreeHelperDriftRejected: fact(
                modeThreeAuthored.replacingOccurrences(
                    of: "(1.0 - base.g)", with: "(0.5 - base.g)"
                )
            ) == nil,
            modeThreeFallbackDriftRejected: fact(
                modeThreeAuthored.replacingOccurrences(
                    of: "    return mix(base, (blend), opacity);",
                    with: "    return mix(base, vec3(1.0), opacity);"
                )
            ) == nil,
            modeThreeCallModeDriftRejected: fact(
                modeThreeAuthored.replacingOccurrences(
                    of: "ApplyBlending(3,", with: "ApplyBlending(9,"
                )
            ) == nil,
            staticRouteProfile: staticProfile.rawValue,
            audioRouteProfile: audioProfile.rawValue,
            maskedRouteProfile: maskedProfile.rawValue,
            multiRouteProfile: multiProfile.rawValue,
            modeThreeRouteProfile: modeThreeProfile.rawValue,
            renamedRouteProfile: renamedProfile.rawValue,
            routeState: expected.defaultRouteState.rawValue,
            rollbackOwner: expected.validatedRollbackOwner.rawValue,
            missingTypedPurposeRejected: profile(
                authored: staticAuthored,
                active: [0, 1], typed: [], graphInputs: [0]
            ) != expected,
            wrongMaskPurposeRejected: profile(
                authored: maskedAuthored,
                active: [0, 1, 2], typed: [1, 2], graphInputs: [0]
            ) != expected,
            modeThreeMissingMaskPurposeRejected: profile(
                authored: modeThreeAuthored, active: [0, 1, 2, 3],
                typed: [1, 2, 3], graphInputs: [0], opacityMasks: [3]
            ) != expected,
            providerRejected: profile(
                authored: staticAuthored,
                active: [0, 1], typed: [1], graphInputs: [0], provider: true
            ) != expected,
            graphTargetRejected: profile(
                authored: staticAuthored,
                active: [0, 1], typed: [1], graphInputs: [0], graphTargets: [0]
            ) != expected,
            secondGraphInputRejected: profile(
                authored: staticAuthored,
                active: [0, 1], typed: [1], graphInputs: [0, 2]
            ) != expected
        )
        FileHandle.standardOutput.write(try JSONEncoder().encode(output))
    }
}
'''


@unittest.skipUnless(shutil.which("swiftc"), "swiftc is required")
class SceneRGBBlendScalarAlphaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temporary = tempfile.TemporaryDirectory(
            prefix="mwx-rgb-blend-scalar-alpha-"
        )
        root = Path(cls.temporary.name)
        harness = root / "Harness.swift"
        harness.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "rgb-blend-scalar-alpha-test"
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(root / "clang-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(root / "swift-cache")
        completed = subprocess.run(
            [
                "swiftc",
                "-parse-as-library",
                *(str(path) for path in SWIFT_SOURCES),
                str(harness),
                "-framework",
                "Security",
                "-o",
                str(cls.binary),
            ],
            cwd=REPOSITORY_ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            raise AssertionError(completed.stderr)

        executed = subprocess.run(
            [str(cls.binary)],
            cwd=REPOSITORY_ROOT,
            capture_output=True,
            text=True,
        )
        if executed.returncode != 0:
            raise AssertionError(executed.stderr)
        cls.result = json.loads(executed.stdout)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temporary.cleanup()

    def test_static_audio_and_renamed_shapes_share_the_exact_profile(self) -> None:
        self.assertEqual(self.result["staticSourceSlot"], 0)
        self.assertEqual(self.result["staticAuxiliarySlots"], [1])
        self.assertEqual(self.result["audioSourceSlot"], 0)
        self.assertEqual(self.result["audioAuxiliarySlots"], [])
        self.assertEqual(self.result["maskedScalarAuxiliarySlots"], [1])
        self.assertEqual(self.result["maskedMaskSlot"], 2)
        self.assertEqual(self.result["multiScalarAuxiliarySlots"], [1, 3])
        self.assertEqual(self.result["multiMaskSlot"], 2)
        for key in (
            "renamedAccepted",
            "staticTransferAccepted",
            "audioTransferAccepted",
            "staticLoweringAccepted",
            "audioLoweringAccepted",
            "renamedLoweringAccepted",
            "maskedTransferAccepted",
            "maskedLoweringAccepted",
            "multiTransferAccepted",
            "multiLoweringAccepted",
            "modeThreeTransferAccepted",
            "modeThreeLoweringAccepted",
            "saturateTransferAccepted",
            "saturateLoweringAccepted",
            "sourceUnpremultipliedOnce",
            "auxiliaryRemainsData",
            "maskRemainsData",
            "outputPremultiplied",
        ):
            self.assertTrue(self.result[key], key)
        expected = "source-proven-graph-input-rgb-blend-scalar-alpha"
        self.assertEqual(self.result["staticRouteProfile"], expected)
        self.assertEqual(self.result["audioRouteProfile"], expected)
        self.assertEqual(self.result["renamedRouteProfile"], expected)
        self.assertEqual(self.result["maskedRouteProfile"], expected)
        self.assertEqual(self.result["multiRouteProfile"], expected)
        self.assertEqual(self.result["modeThreeRouteProfile"], expected)
        self.assertEqual(self.result["saturateRouteProfile"], expected)
        self.assertEqual(self.result["routeState"], "generic-only")
        self.assertEqual(self.result["rollbackOwner"], "none")

    def test_source_and_compiler_drift_fail_closed(self) -> None:
        for key in (
            "differentScalarRejected",
            "alphaAssignmentRejected",
            "alphaAdditionRejected",
            "hiddenSampleRejected",
            "customBlendHelperRejected",
            "sourceBlendModeDriftRejected",
            "missingRGBWriteRejected",
            "missingAlphaWriteRejected",
            "compilerScalarDriftRejected",
            "compilerBlendModeDriftRejected",
            "compilerBaseMultiplierDriftRejected",
            "compilerAuxiliaryDetachedRejected",
            "compilerExtraSampleRejected",
            "sourceMaskOrderRejected",
            "sourceMaskTransformRejected",
            "sourceMaskFactorRejected",
            "compilerMaskSlotRejected",
            "compilerSecondAuxiliaryDetachedRejected",
            "modeThreeHelperDriftRejected",
            "modeThreeFallbackDriftRejected",
            "modeThreeCallModeDriftRejected",
            "saturateCompilerTerminalDriftRejected",
        ):
            self.assertTrue(self.result[key], key)

    def test_route_requires_exact_typed_graph_input_shape(self) -> None:
        for key in (
            "missingTypedPurposeRejected",
            "wrongMaskPurposeRejected",
            "modeThreeMissingMaskPurposeRejected",
            "providerRejected",
            "graphTargetRejected",
            "secondGraphInputRejected",
        ):
            self.assertTrue(self.result[key], key)


if __name__ == "__main__":
    unittest.main()
